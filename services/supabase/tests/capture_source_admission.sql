BEGIN;
SELECT extensions.no_plan();
SELECT extensions.ok(relrowsecurity,'source admission RLS') FROM pg_class WHERE oid='internal.capture_source_admissions'::regclass;
SELECT extensions.ok(NOT has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE'),r||' no access to '||t)
 FROM unnest(ARRAY['anon','authenticated','service_role']) r CROSS JOIN unnest(ARRAY[
 'internal.capture_source_admissions','internal.capture_source_admission_stops']) t;
SELECT extensions.is((SELECT count(*)::INTEGER FROM pg_constraint WHERE conrelid='internal.capture_source_admissions'::regclass AND contype='f'),0,'seal survives mutable row loss');
SELECT extensions.ok(NOT has_function_privilege(r,'internal.prepare_capture_source_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)','EXECUTE'),r||' cannot mint private seal') FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SELECT set_config('request.jwt.claim.role','service_role',true);
CREATE FUNCTION pg_temp.new_admission() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE owner UUID:=gen_random_uuid(); scan UUID:=gen_random_uuid(); session UUID:=gen_random_uuid();
 asset UUID; kind TEXT; role TEXT; mime TEXT; key TEXT; n INTEGER; observations JSONB:='[]'; caps JSONB:='[]';
 keys JSONB:='{"image":[],"audio":[],"video":[]}'; storage TEXT[]:='{}'; payload JSONB;
 counts JSONB:='{"image_count":2,"audio_count":1,"video_count":1,"required_video_count":1,"video_frame_count":0}';
BEGIN
 INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES(owner,'authenticated','authenticated','{}','{}',now(),now());
 FOR n IN 0..3 LOOP
  kind:=CASE WHEN n<2 THEN 'image' WHEN n=2 THEN 'audio' ELSE 'video' END;
  role:=CASE kind WHEN 'image' THEN 'display' WHEN 'audio' THEN 'audio' ELSE 'playback' END;
  mime:=CASE kind WHEN 'image' THEN 'image/webp' WHEN 'audio' THEN 'audio/mp4' ELSE 'video/mp4' END;
  key:='staging/'||owner::TEXT||'/source-'||n; asset:=gen_random_uuid();
  INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size)
   VALUES(asset,owner,scan,session,kind,role,'staged','capture_upload',key,n,mime,100);
  caps:=caps||jsonb_build_array(jsonb_build_object('object_key',key,'expires_at',clock_timestamp()+interval '1 hour','scan_id',scan,'asset_id',asset,'session_id',session));
  observations:=observations||jsonb_build_array(jsonb_build_object('sourceKey',key,'backendSHA256',repeat('a',64),'contentType',mime,'byteCount',100,'sha256',repeat('c',64)));
  keys:=jsonb_set(keys,ARRAY[kind],(keys->kind)||jsonb_build_array(key)); storage:=array_append(storage,key);
 END LOOP;
 PERFORM public.register_capture_upload_capabilities(owner,repeat('a',64),caps);
 payload:=jsonb_build_object('schemaVersion',3,'clientScanId',scan,'endpoint','identify-multimodal',
  'captureSourceObservations',jsonb_build_object('version',1,'items',observations),'mediaCounts',counts,
  'media',jsonb_build_object('r2ObjectKeys',keys->'image','audioR2ObjectKeys',keys->'audio','videoR2ObjectKeys',keys->'video'));
 RETURN jsonb_build_object('owner',owner,'scan',scan,'session',session,'payload',payload,'keys',keys,'counts',counts,'storage',storage);
END;
$$;
CREATE FUNCTION pg_temp.admit(f JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.begin_scan_ingestion(f->>'scan',(f->>'owner')::UUID,'identify-multimodal',f->'payload',f->'counts',f->'keys',
 ARRAY(SELECT jsonb_array_elements_text(f->'storage')),NULL,NULL,TRUE,FALSE,'{}',3,300);
$$;
CREATE TEMP TABLE admission_fixture(name TEXT PRIMARY KEY,f JSONB,result JSONB);
INSERT INTO admission_fixture(name,f) SELECT name,pg_temp.new_admission() FROM unnest(ARRAY['main','lost','stop','terminal','scan_delete','account_delete','owner_delete','rollback','legacy','merge']) name;
GRANT SELECT ON admission_fixture TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.admit(JSONB) TO service_role;
SELECT extensions.throws_ok($$SELECT pg_temp.admit(jsonb_set(f,'{payload,captureSourceObservations,items,3,sha256}','"bad"')) FROM admission_fixture WHERE name='rollback'$$,'22023','capture_source_admission_invalid','late invalid member rolls back earlier checksums');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.scan_media_assets WHERE user_id=(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='rollback') AND checksum_sha256 IS NOT NULL),0,'no partial asset checksums');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_source_admissions),0,'no partial seal');
SELECT extensions.lives_ok($$SELECT public.begin_scan_ingestion(f->>'scan',(f->>'owner')::UUID,'identify-multimodal',NULL) FROM admission_fixture WHERE name='legacy'$$,'legacy null payload compatibility preserved');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(f) FROM admission_fixture WHERE name='legacy'$$,'55000','capture_source_admission_conflict','legacy generation cannot upgrade in place');
SET LOCAL ROLE service_role;
SELECT extensions.ok(pg_temp.admit(f)->>'payload_checksum' ~ '^[0-9a-f]{64}$','service atomically admits mixed media '||name) FROM admission_fixture WHERE name NOT IN ('rollback','legacy');
RESET ROLE;
UPDATE admission_fixture SET result=pg_temp.admit(f) WHERE name NOT IN ('rollback','legacy');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.scan_media_assets WHERE user_id=(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='main') AND checksum_sha256=repeat('c',64)),4,'all observed digests bound atomically');
SELECT extensions.ok(NOT i.request_payload ? 'captureSourceObservations' AND i.request_payload ? 'captureSourceProofs','only canonical proofs persist') FROM public.scan_ingestion_intents i JOIN admission_fixture f ON i.scan_id=f.f->>'scan' WHERE name='main';
SELECT extensions.is(i.request_payload#>>'{captureSourceProofs,items,2,contentType}','audio/mp4','audio MP4 parity preserved') FROM public.scan_ingestion_intents i JOIN admission_fixture f ON i.scan_id=f.f->>'scan' WHERE name='main';
CREATE FUNCTION pg_temp.promote_admission(f JSONB) RETURNS BOOLEAN LANGUAGE PLPGSQL AS $$
DECLARE i public.scan_ingestion_intents; item JSONB; op UUID; binding JSONB; bindings JSONB:='[]'; cohort UUID:=gen_random_uuid();
BEGIN
 SELECT * INTO STRICT i FROM public.scan_ingestion_intents WHERE scan_id=f->>'scan';
 FOR item IN SELECT value FROM jsonb_array_elements(i.request_payload#>'{captureSourceProofs,items}') LOOP
  op:=gen_random_uuid();
  binding:=(item-ARRAY['kind','role','assetOrder','ordinal'])||jsonb_build_object('operationId',op,'ownerId',f->>'owner','scanId',f->>'scan',
    'destinationKey','public_uploads/free/'||(f->>'owner')||'/capture-promotion-'||op::TEXT);
  bindings:=bindings||jsonb_build_array(binding);
 END LOOP;
 PERFORM public.register_capture_promotion_ingestion(cohort,i.manifest_checksum,i.payload_checksum,bindings);
 RETURN public.authorize_capture_promotion_action(bindings->2,'write_destination');
END;
$$;
SELECT extensions.ok(pg_temp.promote_admission(f),'sealed complete observation feeds promotion including MP4 audio') FROM admission_fixture WHERE name='main';
SELECT extensions.is(pg_temp.admit(f),result,'exact observation retry returns original checksums') FROM admission_fixture WHERE name='main';
SELECT extensions.is(pg_temp.admit(jsonb_set(f.f,'{payload}',i.request_payload)),f.result,'canonical proof retry returns original checksums') FROM admission_fixture f JOIN public.scan_ingestion_intents i ON i.scan_id=f.f->>'scan' WHERE name='main';
SELECT extensions.throws_ok($$SELECT pg_temp.admit(jsonb_set(f,'{payload}',(f->'payload')-'captureSourceObservations')) FROM admission_fixture WHERE name='main'$$,'55000','capture_source_admission_conflict','omitted proof cannot downgrade');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(jsonb_set(f,'{payload,captureSourceObservations,items,0,sha256}',to_jsonb(repeat('d',64)))) FROM admission_fixture WHERE name='main'$$,'55000','capture_source_admission_conflict','changed proof cannot replace admission');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_intents SET payload_checksum=repeat('d',64) WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='main')$$,'55000','capture_source_admission_conflict','direct intent edit denied');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_jobs SET media_object_keys='{}' WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='main')$$,'55000','capture_source_admission_conflict','direct job edit denied');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_jobs SET scan_id='not-a-uuid' WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='main')$$,'55000','capture_source_admission_conflict','invalid text identity cannot escape seal');
SELECT extensions.throws_ok($$SELECT public.record_scan_ingestion_intent(scan_id,user_id,endpoint,request_payload,media_counts,media_object_keys,upload_session_ids,manifest_checksum,repeat('d',64),resumable,inline_media_redacted,redacted_media_counts,payload_schema_version) FROM public.scan_ingestion_intents WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='main')$$,'55000','capture_source_admission_conflict','legacy service writer cannot replace sealed intent');
SELECT extensions.lives_ok($$UPDATE public.scan_ingestion_intents SET last_replayed_at=now(),replay_attempt_count=replay_attempt_count+1 WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='main')$$,'scheduler bookkeeping remains allowed');
SELECT extensions.is(public.recover_inline_scan_ingestion_completion((f->>'scan')::UUID,(f->>'owner')::UUID),'not_applicable','inline recovery cannot normalize sealed media') FROM admission_fixture WHERE name='main';
DELETE FROM public.scan_ingestion_intents WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='lost');
DELETE FROM public.scan_ingestion_jobs WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='lost');
UPDATE public.scan_media_assets SET order_index=order_index+20 WHERE user_id=(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='lost');
SELECT extensions.is(pg_temp.admit(f),result,'row loss restores original admission without fresh asset reseal') FROM admission_fixture WHERE name='lost';
SELECT extensions.is(i.request_payload#>>'{captureSourceProofs,items,0,assetOrder}','0','restored payload preserves original asset order') FROM public.scan_ingestion_intents i JOIN admission_fixture f ON i.scan_id=f.f->>'scan' WHERE name='lost';
UPDATE public.scan_ingestion_intents SET resumable=FALSE WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='stop');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(f) FROM admission_fixture WHERE name='stop'$$,'55000','capture_source_admission_unavailable','contraction prevents begin reset');
DELETE FROM public.scan_ingestion_intents WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='stop');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(f) FROM admission_fixture WHERE name='stop'$$,'55000','capture_source_admission_unavailable','contraction survives mutable row loss');
UPDATE public.scan_ingestion_jobs SET status='failed_terminal' WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='terminal');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(f) FROM admission_fixture WHERE name='terminal'$$,'55000','capture_source_admission_unavailable','terminal failure cannot reopen');
SELECT extensions.throws_ok($$UPDATE public.scan_ingestion_jobs SET status='complete' WHERE scan_id=(SELECT f->>'scan' FROM admission_fixture WHERE name='terminal')$$,'55000','capture_source_admission_unavailable','terminal failure cannot become success');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT (f->>'scan')::UUID,(f->>'owner')::UUID FROM admission_fixture WHERE name='scan_delete';
SELECT extensions.ok(recovery IS NULL AND retired_at IS NOT NULL,'scan retirement erases private recovery') FROM internal.capture_source_admissions WHERE scan_id=(SELECT (f->>'scan')::UUID FROM admission_fixture WHERE name='scan_delete');
DELETE FROM public.users WHERE id=(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='owner_delete');
SELECT extensions.ok(recovery IS NULL AND retired_at IS NOT NULL,'owner cascade retains only erased identity') FROM internal.capture_source_admissions WHERE scan_id=(SELECT (f->>'scan')::UUID FROM admission_fixture WHERE name='owner_delete');
INSERT INTO internal.account_deletion_jobs(user_id) SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='account_delete';
SELECT extensions.ok(recovery IS NULL AND retired_at IS NOT NULL,'account intake immediately erases private recovery') FROM internal.capture_source_admissions WHERE scan_id=(SELECT (f->>'scan')::UUID FROM admission_fixture WHERE name='account_delete');
SELECT extensions.throws_ok($$SELECT pg_temp.admit(f) FROM admission_fixture WHERE name='account_delete'$$,'55000','capture_source_admission_unavailable','account intake prevents retry');
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge((SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='merge'),(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='rollback'))$$,'55000','ghost_merge_source_work_pending','existing active-work merge fence preserved');
SELECT public.fail_scan_ingestion_terminal((f->>'scan')::UUID,(f->>'owner')::UUID,'capture_abandoned','synthetic fixture settlement','cancelled') FROM admission_fixture WHERE name='merge';
SELECT extensions.lives_ok($$SELECT internal.perform_ghost_profile_merge((SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='merge'),(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='rollback'))$$,'actual settled merge retires source and reparents metadata');
SELECT extensions.ok(recovery IS NULL AND retired_at IS NOT NULL AND owner_id=(SELECT (f->>'owner')::UUID FROM admission_fixture WHERE name='merge'),'merge erases recovery without rebinding seal owner') FROM internal.capture_source_admissions WHERE scan_id=(SELECT (f->>'scan')::UUID FROM admission_fixture WHERE name='merge');
SELECT extensions.finish();
ROLLBACK;

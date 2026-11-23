BEGIN;
SELECT extensions.no_plan();
SELECT extensions.ok(relrowsecurity,'cohort RLS') FROM pg_catalog.pg_class WHERE oid='internal.capture_promotion_cohorts'::regclass;
SELECT extensions.ok(NOT has_table_privilege(r,'internal.capture_promotion_cohorts','SELECT,INSERT,UPDATE,DELETE'),r||' no cohort table access') FROM unnest(ARRAY['anon','authenticated','service_role']) r;
SELECT extensions.ok(NOT has_function_privilege(r,'public.register_capture_promotion_cohort(uuid,uuid,text,text,jsonb)','EXECUTE'),r||' no cohort registration') FROM unnest(ARRAY['anon','authenticated']) r;
SELECT extensions.ok(NOT has_function_privilege(r,f,'EXECUTE'),r||' no private projection') FROM unnest(ARRAY['anon','authenticated','service_role']) r CROSS JOIN unnest(ARRAY[
 'internal.capture_promotion_ingestion_projection(uuid,uuid,uuid,text,text)','internal.require_capture_promotion_cohort_current(uuid)','internal.lock_capture_promotion_action_sources(internal.capture_promotion_operations)']) f;
SELECT extensions.is((SELECT count(*)::INTEGER FROM pg_catalog.pg_constraint WHERE conrelid='internal.capture_promotion_cohorts'::regclass AND contype='f'),0,'logical cohort has no cascading identity dependency');
-- These are all current SQL owners of mutable projection fields, including the
-- legacy service-callable entry points. Test the expanded replayed definitions.
SELECT extensions.ok(owner_lock>0 AND scan_lock>owner_lock AND mutation>scan_lock,
    routine||' locks owner and scan before replacing projection')
FROM (SELECT p.proname AS routine,
    strpos(lower(p.prosrc),'from public.users') AS owner_lock,
    strpos(lower(p.prosrc),'merian-scan-ingestion:') AS scan_lock,
    strpos(lower(p.prosrc),'insert into public.scan_ingestion_') AS mutation
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
    ('begin_scan_ingestion','claim_scan_ingestion_job','record_scan_ingestion_intent')) writers;
SELECT set_config('request.jwt.claim.role','service_role',true);
CREATE FUNCTION pg_temp.new_cohort() RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE owner UUID:=gen_random_uuid(); scan UUID:=gen_random_uuid(); session UUID:=gen_random_uuid(); cohort UUID:=gen_random_uuid();
    asset UUID; op UUID; kind TEXT; role TEXT; mime TEXT; key TEXT; n INTEGER;
    bindings JSONB:='[]'; caps JSONB:='[]'; keys JSONB:='{"image":[],"audio":[],"video":[]}'; all_keys TEXT[]:='{}'; j public.scan_ingestion_jobs%ROWTYPE; i public.scan_ingestion_intents%ROWTYPE;
BEGIN
 INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES(owner,'authenticated','authenticated','{}','{}',now(),now());
 FOR n IN 0..3 LOOP
  kind:=CASE WHEN n<2 THEN 'image' WHEN n=2 THEN 'audio' ELSE 'video' END;
  role:=CASE kind WHEN 'image' THEN 'display' WHEN 'audio' THEN 'audio' ELSE 'playback' END;
  mime:=CASE kind WHEN 'image' THEN 'image/webp' WHEN 'audio' THEN 'audio/wav' ELSE 'video/mp4' END;
  asset:=gen_random_uuid(); op:=gen_random_uuid(); key:='staging/'||owner::TEXT||'/cohort-'||n;
  INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size,checksum_sha256)
    VALUES(asset,owner,scan,session,kind,role,'staged','capture_upload',key,n,mime,100,repeat('c',64));
  bindings:=bindings||jsonb_build_array(jsonb_build_object('operationId',op,'ownerId',owner,'scanId',scan,'assetId',asset,'sessionId',session,
    'backendSHA256',repeat('a',64),'sourceKey',key,'destinationKey','public_uploads/free/'||owner::TEXT||'/capture-promotion-'||op::TEXT,'contentType',mime,'byteCount',100,'sha256',repeat('c',64)));
  caps:=caps||jsonb_build_array(jsonb_build_object('object_key',key,'expires_at',clock_timestamp()+interval '1 hour','scan_id',scan,'asset_id',asset,'session_id',session));
  keys:=jsonb_set(keys,ARRAY[kind],(keys->kind)||jsonb_build_array(key)); all_keys:=array_append(all_keys,key);
 END LOOP;
 PERFORM public.register_capture_upload_capabilities(owner,repeat('a',64),caps);
 PERFORM public.begin_scan_ingestion(scan::TEXT,owner,'identify-multimodal',jsonb_build_object('schemaVersion',1,'clientScanId',scan,'media',jsonb_build_object('r2ObjectKeys',keys->'image','audioR2ObjectKeys',keys->'audio','videoR2ObjectKeys',keys->'video')),
    '{"image_count":2,"audio_count":1,"video_count":1}',keys,all_keys);
 SELECT * INTO STRICT j FROM public.scan_ingestion_jobs WHERE user_id=owner AND scan_id=scan::TEXT;
 SELECT * INTO STRICT i FROM public.scan_ingestion_intents WHERE user_id=owner AND scan_id=scan::TEXT;
 RETURN jsonb_build_object('cohort',cohort,'job',j.id,'intent',i.id,'manifest',j.manifest_checksum,'request',i.payload_checksum,'bindings',bindings);
END;
$$;
CREATE FUNCTION pg_temp.register_cohort(f JSONB) RETURNS TEXT LANGUAGE SQL AS $$
 SELECT public.register_capture_promotion_cohort((f->>'cohort')::UUID,(f->>'job')::UUID,f->>'manifest',f->>'request',f->'bindings');
$$;
GRANT EXECUTE ON FUNCTION pg_temp.register_cohort(JSONB) TO service_role;
CREATE TEMP TABLE cohort_fixture(name TEXT PRIMARY KEY,f JSONB,seal TEXT);
INSERT INTO cohort_fixture(name,f) SELECT n,pg_temp.new_cohort() FROM unnest(ARRAY['main','late','lost_job','lost_intent','thumbnail','rollback']) n;
GRANT SELECT ON cohort_fixture TO service_role;
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(f||'{"bindings":null}') FROM cohort_fixture WHERE name='main'$$,'22023','capture_promotion_cohort_invalid','null members denied');
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(jsonb_set(f,'{bindings}',jsonb_build_array(f->'bindings'->0))) FROM cohort_fixture WHERE name='main'$$,'22023','capture_promotion_cohort_invalid','subset denied');
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(jsonb_set(f,'{bindings}',jsonb_build_array(f->'bindings'->1,f->'bindings'->0,f->'bindings'->2,f->'bindings'->3))) FROM cohort_fixture WHERE name='main'$$,'22023','capture_promotion_cohort_invalid','reordered photo keys denied');
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(f||jsonb_build_object('request',repeat('d',64))) FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','caller checksum mismatch denied');
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(jsonb_set(f,'{bindings,3,sha256}',to_jsonb(repeat('d',64)))) FROM cohort_fixture WHERE name='rollback'$$,'55000','capture_promotion_unavailable','late invalid member rolls back whole registration');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations),0,'failed cohort creates no partial operations');
SET LOCAL ROLE service_role;
SELECT extensions.ok(pg_temp.register_cohort(f) ~ '^[0-9a-f]{64}$','service registers exact mixed cohort '||name) FROM cohort_fixture WHERE name IN ('main','lost_job','lost_intent');
RESET ROLE;
UPDATE cohort_fixture f SET seal=c.cohort_sha256 FROM internal.capture_promotion_cohorts c WHERE c.cohort_id=(f.f->>'cohort')::UUID;
SELECT extensions.is(pg_temp.register_cohort(f),seal,'identical registration returns original seal') FROM cohort_fixture WHERE name='main';
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations),12,'three complete four-member cohorts');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.scans WHERE id IN (SELECT (f->'bindings'->0->>'scanId')::UUID FROM cohort_fixture)),0,'registration preserves pre-scan ownership');
SELECT extensions.is(c.ingestion_projection->>'intentId',f.f->>'intent','intent identity sealed') FROM cohort_fixture f JOIN internal.capture_promotion_cohorts c ON c.cohort_id=(f.f->>'cohort')::UUID WHERE f.name='main';
SELECT extensions.is(c.members->1->>'ordinal','1','second photo ordinal sealed') FROM cohort_fixture f JOIN internal.capture_promotion_cohorts c ON c.cohort_id=(f.f->>'cohort')::UUID WHERE f.name='main';
SELECT extensions.is(c.members->3->>'assetOrder','3','cross-kind asset order sealed') FROM cohort_fixture f JOIN internal.capture_promotion_cohorts c ON c.cohort_id=(f.f->>'cohort')::UUID WHERE f.name='main';
SELECT extensions.ok(public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination'),'first member write authorized') FROM cohort_fixture WHERE name='main';
SELECT extensions.is(pg_temp.register_cohort(f),seal,'retry after issued write preserves cohort') FROM cohort_fixture WHERE name='main';
SELECT extensions.ok(NOT public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination'),'cohort retry cannot reset consumed write') FROM cohort_fixture WHERE name='main';
UPDATE public.scan_ingestion_jobs SET lock_expires_at=now()-interval '1 hour',stage='retry_pending' WHERE id=(SELECT (f->>'job')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.ok(public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination'),'lease expiry does not replace logical identity') FROM cohort_fixture WHERE name='main';
UPDATE public.scan_media_assets SET role='inference_frame' WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','role drift denied');
UPDATE public.scan_media_assets SET role='display' WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
UPDATE public.scan_media_assets SET order_index=20 WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','order drift denied');
UPDATE public.scan_media_assets SET order_index=0 WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
UPDATE public.scan_media_assets SET role='inference_frame' WHERE id=(SELECT (f->'bindings'->1->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','peer role drift blocks unaffected member');
UPDATE public.scan_media_assets SET role='display',order_index=20 WHERE id=(SELECT (f->'bindings'->1->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','peer order drift blocks unaffected member');
UPDATE public.scan_media_assets SET order_index=1,status='deleted' WHERE id=(SELECT (f->'bindings'->1->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_unavailable','peer source status drift blocks unaffected member');
UPDATE public.scan_media_assets SET status='staged' WHERE id=(SELECT (f->'bindings'->1->>'assetId')::UUID FROM cohort_fixture WHERE name='main');
UPDATE public.scan_ingestion_intents SET payload_checksum=repeat('d',64) WHERE id=(SELECT (f->>'intent')::UUID FROM cohort_fixture WHERE name='main');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM cohort_fixture WHERE name='main'$$,'55000','capture_promotion_cohort_unavailable','request drift denied');
UPDATE public.scan_ingestion_intents i SET payload_checksum=f.f->>'request' FROM cohort_fixture f WHERE i.id=(f.f->>'intent')::UUID AND f.name='main';
SELECT extensions.ok(public.register_capture_promotion_operation(f->'bindings'->0),'unbound storage registration remains content only') FROM cohort_fixture WHERE name='late';
SELECT extensions.ok(public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination'),'legacy prepared write consumed') FROM cohort_fixture WHERE name='late';
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(f) FROM cohort_fixture WHERE name='late'$$,'55000','capture_promotion_cohort_conflict','cannot seal a cohort retroactively after write');
UPDATE public.scan_media_assets SET role='thumbnail' WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM cohort_fixture WHERE name='thumbnail');
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(f) FROM cohort_fixture WHERE name='thumbnail'$$,'22023','capture_promotion_cohort_invalid','thumbnail has no ordinary consumer');
DELETE FROM public.scan_ingestion_jobs WHERE id=(SELECT (f->>'job')::UUID FROM cohort_fixture WHERE name='lost_job');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination') FROM cohort_fixture WHERE name='lost_job'$$,'55000','capture_promotion_cohort_unavailable','job loss cannot authorize fresh write');
INSERT INTO public.scan_ingestion_jobs(user_id,scan_id,media_counts,media_object_keys,upload_session_ids,manifest_checksum)
 SELECT (f->'bindings'->0->>'ownerId')::UUID,f->'bindings'->0->>'scanId',c.ingestion_projection->'mediaCounts',c.ingestion_projection->'mediaObjectKeys',ARRAY[(f->'bindings'->0->>'sessionId')::UUID],f->>'manifest'
 FROM cohort_fixture f JOIN internal.capture_promotion_cohorts c ON c.cohort_id=(f.f->>'cohort')::UUID WHERE name='lost_job';
SELECT extensions.throws_ok($$SELECT pg_temp.register_cohort(f||jsonb_build_object('job',j.id)) FROM cohort_fixture f JOIN public.scan_ingestion_jobs j ON j.user_id=(f.f->'bindings'->0->>'ownerId')::UUID WHERE name='lost_job'$$,'55000','capture_promotion_cohort_conflict','replacement job cannot rebind existing cohort');
DELETE FROM public.scan_ingestion_intents WHERE id=(SELECT (f->>'intent')::UUID FROM cohort_fixture WHERE name='lost_intent');
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination') FROM cohort_fixture WHERE name='lost_intent'$$,'55000','capture_promotion_cohort_unavailable','intent loss cannot authorize fresh write');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_cohorts),3,'logical identity survives lost job and intent');
SELECT extensions.ok(public.retire_capture_promotion_operation(f->'bindings'->0),'abandonment remains possible after job loss') FROM cohort_fixture WHERE name='lost_job';
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT (f->'bindings'->0->>'scanId')::UUID,(f->'bindings'->0->>'ownerId')::UUID FROM cohort_fixture WHERE name='main';
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations WHERE cohort_id=(SELECT (f->>'cohort')::UUID FROM cohort_fixture WHERE name='main') AND retired_at IS NOT NULL),4,'scan deletion retires entire bound target cohort');
-- The unfenced replay claimant may only move among eligible lifecycle states;
-- its exact live projection remains identical to the immutable registration.
INSERT INTO cohort_fixture(name,f) VALUES('replay',pg_temp.new_cohort());
SELECT extensions.ok(pg_temp.register_cohort(f) ~ '^[0-9a-f]{64}$','replay cohort registered') FROM cohort_fixture WHERE name='replay';
UPDATE public.scan_ingestion_jobs SET lock_expires_at=now()-interval '1 hour'
 WHERE id=(SELECT (f->>'job')::UUID FROM cohort_fixture WHERE name='replay');
SELECT count(*) FROM public.claim_replayable_scan_ingestion_jobs(50,300);
SELECT extensions.is((SELECT status FROM public.scan_ingestion_jobs
 WHERE id=(SELECT (f->>'job')::UUID FROM cohort_fixture WHERE name='replay')),'retrying','replay moves to eligible lifecycle state');
SELECT extensions.is(internal.capture_promotion_ingestion_projection(
 (f.f->'bindings'->0->>'ownerId')::UUID,(f.f->'bindings'->0->>'scanId')::UUID,
 (f.f->>'job')::UUID,f.f->>'manifest',f.f->>'request'),c.ingestion_projection,
 'replay claimant preserves exact sealed projection')
 FROM cohort_fixture f JOIN internal.capture_promotion_cohorts c ON c.cohort_id=(f.f->>'cohort')::UUID WHERE f.name='replay';
-- Real merge orchestrator reparents the ingestion metadata but never authorizes
-- a new owner to reuse old source/destination authority or removes its obligation.
INSERT INTO cohort_fixture(name,f) VALUES('merge',pg_temp.new_cohort()),('merge_target',pg_temp.new_cohort());
SELECT extensions.ok(pg_temp.register_cohort(f) ~ '^[0-9a-f]{64}$','merge source cohort registered') FROM cohort_fixture WHERE name='merge';
SELECT extensions.ok(public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination'),'merge source has an issued write') FROM cohort_fixture WHERE name='merge';
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge(
 (SELECT (f->'bindings'->0->>'ownerId')::UUID FROM cohort_fixture WHERE name='merge'),
 (SELECT (f->'bindings'->0->>'ownerId')::UUID FROM cohort_fixture WHERE name='merge_target'))$$,
 '55000','ghost_merge_source_work_pending','active cohort ingestion blocks merge');
SELECT public.fail_scan_ingestion_terminal((f->'bindings'->0->>'scanId')::UUID,
 (f->'bindings'->0->>'ownerId')::UUID,'capture_abandoned','synthetic fixture settlement','cancelled')
 FROM cohort_fixture WHERE name='merge';
SELECT extensions.lives_ok($$SELECT internal.perform_ghost_profile_merge(
 (SELECT (f->'bindings'->0->>'ownerId')::UUID FROM cohort_fixture WHERE name='merge'),
 (SELECT (f->'bindings'->0->>'ownerId')::UUID FROM cohort_fixture WHERE name='merge_target'))$$,'complete merge accepts cohort owner');
SELECT extensions.throws_ok($$SELECT internal.capture_promotion_ingestion_projection(
 (f->'bindings'->0->>'ownerId')::UUID,(f->'bindings'->0->>'scanId')::UUID,
 (f->>'job')::UUID,f->>'manifest',f->>'request') FROM cohort_fixture WHERE name='merge'$$,
 '55000','capture_promotion_cohort_unavailable','old-owner projection unavailable after merge');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations
 WHERE cohort_id=(SELECT (f->>'cohort')::UUID FROM cohort_fixture WHERE name='merge') AND retired_at IS NOT NULL),4,'merge retires all retained destination obligations');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_operations
 WHERE cohort_id=(SELECT (f->>'cohort')::UUID FROM cohort_fixture WHERE name='merge') AND write_authorized_at IS NOT NULL),1,'merge preserves consumed write');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.capture_promotion_cohorts
 WHERE cohort_id=(SELECT (f->>'cohort')::UUID FROM cohort_fixture WHERE name='merge')),1,'merge preserves immutable old-owner cohort');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_cohort(NULL,NULL,NULL,NULL,NULL)$$,'42501',NULL,'anon invocation denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_cohort(NULL,NULL,NULL,NULL,NULL)$$,'42501',NULL,'authenticated invocation denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

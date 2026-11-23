BEGIN;
SELECT extensions.no_plan();
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

CREATE TEMP TABLE recovery_fixture AS SELECT pg_temp.new_cohort() f;
GRANT SELECT ON recovery_fixture TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.register_capture_promotion_ingestion((f->>'cohort')::UUID,f->>'manifest',f->>'request',f->'bindings') ?& ARRAY['jobId','cohortId','cohortSHA256'],'runtime cohort registration needs no ledger SELECT') FROM recovery_fixture;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_recovery(f->'bindings'->0) FROM recovery_fixture$$,'55000','capture_promotion_unavailable','unissued operation cannot recover destination');
SELECT extensions.ok(public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination'),'initial write consumed') FROM recovery_fixture;
SELECT extensions.ok(public.authorize_capture_promotion_recovery(f->'bindings'->0),'issued exact destination recoverable') FROM recovery_fixture;
RESET ROLE;
DELETE FROM public.scan_media_assets WHERE id=(SELECT (f->'bindings'->0->>'assetId')::UUID FROM recovery_fixture);
DELETE FROM public.scan_ingestion_jobs WHERE id=(SELECT (f->>'job')::UUID FROM recovery_fixture);
DELETE FROM public.scan_ingestion_intents WHERE id=(SELECT (f->>'intent')::UUID FROM recovery_fixture);
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.authorize_capture_promotion_recovery(f->'bindings'->0),'retained identity recovers after asset/job/intent loss') FROM recovery_fixture;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination') FROM recovery_fixture$$,'55000','capture_promotion_unavailable','missing source never reopens fresh write');
SELECT extensions.ok(public.record_capture_promotion_verification(f->'bindings'->0,'destination_recovery')->>'origin'='destination_recovery','record exact recovered content') FROM recovery_fixture;
RESET ROLE;
CREATE TEMP TABLE saved_recovery_receipt AS SELECT public.record_capture_promotion_verification(f->'bindings'->0,'destination_recovery') receipt FROM recovery_fixture;
GRANT SELECT ON saved_recovery_receipt TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.record_capture_promotion_verification(f->'bindings'->0,'write_acknowledged'),(SELECT receipt FROM saved_recovery_receipt),'repeat preserves first timestamp and origin') FROM recovery_fixture;
-- Closed exact identity and service boundary, even before any storage work.
SELECT extensions.throws_ok(format('SELECT public.authorize_capture_promotion_recovery(%L::jsonb)',
    jsonb_set(f->'bindings'->0,ARRAY[k],to_jsonb(v))), '55000','capture_promotion_unavailable','changed '||k||' cannot recover')
FROM recovery_fixture CROSS JOIN (VALUES
 ('scanId',gen_random_uuid()::TEXT),('assetId',gen_random_uuid()::TEXT),
 ('sessionId',gen_random_uuid()::TEXT),('backendSHA256',repeat('d',64)),
 ('sha256',repeat('d',64))) changes(k,v);
SELECT extensions.ok(public.retire_capture_promotion_operation(f->'bindings'->0),'retirement keeps cleanup obligation') FROM recovery_fixture;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_recovery(f->'bindings'->0) FROM recovery_fixture$$,'55000','capture_promotion_unavailable','retirement stops new GET');
SELECT extensions.throws_ok($$SELECT public.record_capture_promotion_verification(f->'bindings'->0,'destination_recovery') FROM recovery_fixture$$,'55000','capture_promotion_unavailable','late verification cannot revive retired operation');
RESET ROLE;
SELECT extensions.ok(destination_verified_at IS NOT NULL AND write_authorized_at IS NOT NULL AND retired_at IS NOT NULL,'receipt, consumed write and erasure obligation coexist') FROM internal.capture_promotion_operations WHERE operation_id=(SELECT (f->'bindings'->0->>'operationId')::UUID FROM recovery_fixture);
SELECT extensions.ok(NOT has_function_privilege(r,'public.authorize_capture_promotion_recovery(jsonb)','EXECUTE'),r||' cannot recover') FROM unnest(ARRAY['anon','authenticated']) r;
SELECT extensions.ok(NOT has_function_privilege(r,'public.record_capture_promotion_verification(jsonb,text)','EXECUTE'),r||' cannot attest') FROM unnest(ARRAY['anon','authenticated']) r;
SELECT extensions.throws_ok($$SELECT public.record_capture_promotion_verification(f->'bindings'->0,'HEAD') FROM recovery_fixture$$,
 '22023','capture_promotion_invalid','HEAD cannot attest bytes');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_ingestion(gen_random_uuid(),repeat('a',64),repeat('b',64),'[]')$$,
 '22023','capture_promotion_cohort_invalid','empty registration rejected');
SELECT extensions.throws_ok($$SELECT public.register_capture_promotion_ingestion(gen_random_uuid(),repeat('a',64),repeat('b',64),'{}')$$,
 '22023','capture_promotion_cohort_invalid','non-array registration rejected');
SELECT extensions.ok(NOT has_table_privilege('service_role',r,'SELECT'),'runtime wrapper does not grant ledger access: '||r)
 FROM unnest(ARRAY['public.scan_ingestion_jobs','public.scan_ingestion_intents']) r;
SELECT extensions.ok(NOT has_function_privilege(r,'public.register_capture_promotion_ingestion(uuid,text,text,jsonb)','EXECUTE'),r||' cannot register')
 FROM unnest(ARRAY['anon','authenticated']) r;
SELECT extensions.ok(NOT has_function_privilege(r,'internal.lock_capture_promotion_recovery(jsonb)','EXECUTE'),r||' cannot bypass service guard')
 FROM unnest(ARRAY['anon','authenticated','service_role']) r;

CREATE TEMP TABLE recovery_denials AS SELECT name, pg_temp.new_cohort() f
 FROM unnest(ARRAY['unbound','account','scan','peer','missing_owner']) name;
GRANT SELECT ON recovery_denials TO service_role;
SET LOCAL ROLE service_role;
SELECT public.register_capture_promotion_ingestion((f->>'cohort')::UUID,f->>'manifest',f->>'request',f->'bindings') IS NOT NULL
 FROM recovery_denials WHERE name<>'unbound';
SELECT public.register_capture_promotion_operation(f->'bindings'->0) FROM recovery_denials WHERE name='unbound';
SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'write_destination') FROM recovery_denials;
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_recovery(f->'bindings'->0) FROM recovery_denials WHERE name='unbound'$$,
 '55000','capture_promotion_unavailable','issued unbound operation cannot use retained-cohort recovery');
SELECT * FROM public.request_account_deletion((SELECT (f->'bindings'->0->>'ownerId')::UUID FROM recovery_denials WHERE name='account'));
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id)
 SELECT (f->'bindings'->0->>'scanId')::UUID,(f->'bindings'->0->>'ownerId')::UUID FROM recovery_denials WHERE name='scan';
DELETE FROM public.users WHERE id=(SELECT (f->'bindings'->0->>'ownerId')::UUID FROM recovery_denials WHERE name='missing_owner');
UPDATE public.scan_media_assets SET role='inference_frame'
 WHERE id=(SELECT (f->'bindings'->1->>'assetId')::UUID FROM recovery_denials WHERE name='peer');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(format('SELECT public.authorize_capture_promotion_recovery(%L::jsonb)',f->'bindings'->0),
 '55000','capture_promotion_unavailable',name||' retirement prevents recovery') FROM recovery_denials WHERE name IN ('account','scan','missing_owner');
SELECT extensions.throws_ok(format('SELECT public.record_capture_promotion_verification(%L::jsonb,%L)',f->'bindings'->0,'destination_recovery'),
 '55000','capture_promotion_unavailable',name||' retirement prevents receipt') FROM recovery_denials WHERE name IN ('account','scan','missing_owner');
SELECT extensions.ok(public.authorize_capture_promotion_recovery(f->'bindings'->0),'peer drift does not discard historical content observation') FROM recovery_denials WHERE name='peer';
SELECT extensions.throws_ok($$SELECT public.authorize_capture_promotion_action(f->'bindings'->0,'read_destination') FROM recovery_denials WHERE name='peer'$$,
 '55000','capture_promotion_cohort_unavailable','peer drift still prevents fresh I/O');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

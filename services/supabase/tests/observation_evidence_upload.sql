\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Synthetic object','is_biological_subject',FALSE,
            'is_live_capture',TRUE,'confidence_score',0.8,'blur_score',0.2,'colors','[]'::JSONB,
            'estimated_size_cm',NULL,'inference_tier','flash','pet_identification',NULL,'candidates',NULL,
            'image_quality',NULL,'ai_reasoning','Synthetic fixture.','extracted_visual_traits','[]'::JSONB),
        'evidence_manifest','{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation."}}}]}'::JSONB);
$$;
CREATE FUNCTION pg_temp.seed_history_append(owner_id UUID, observation UUID, permit_initial BOOLEAN DEFAULT TRUE)
RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(observation,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(observation,permit_initial);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
END;
$$;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11');
CREATE FUNCTION pg_temp.upload_items(media TEXT DEFAULT '00000000-0000-4000-8000-00000000ed31') RETURNS JSONB LANGUAGE SQL AS $$
SELECT jsonb_build_array(jsonb_build_object('media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),
    jsonb_build_object('media_id','00000000-0000-4000-8000-00000000ed32','content_type','image/png','byte_count',4,'sha256',repeat('b',64)));
$$;
CREATE FUNCTION pg_temp.reserve_upload(items JSONB DEFAULT pg_temp.upload_items()) RETURNS JSONB LANGUAGE SQL AS $$
SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21',items);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.upload_items(TEXT),pg_temp.reserve_upload(JSONB) TO service_role;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE has_table_privilege(role_name,'internal.observation_evidence_upload_cohorts','SELECT')),'cohort has no API table access');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.reserve_owned_observation_evidence_cohort(uuid,uuid,uuid,jsonb)','EXECUTE'),'clients cannot reserve directly');
SELECT extensions.ok(NOT has_function_privilege('anon','public.complete_owned_observation_evidence_upload(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'anonymous completion denied');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_upload()','55000','analysis_history_unavailable','closed media gate denies actual service caller');
RESET ROLE;
UPDATE internal.observation_history_rollout SET media_enabled=TRUE;
SET LOCAL ROLE service_role;
CREATE TEMP TABLE upload_receipts AS SELECT pg_temp.reserve_upload() value;
SELECT extensions.is(jsonb_array_length((SELECT value FROM upload_receipts)),2,'full cohort reserved atomically');
SELECT extensions.is(pg_temp.reserve_upload(),(SELECT value FROM upload_receipts),'retry recovers same keys and expiry');
SELECT extensions.is((SELECT value#>>'{0,expires_at}' FROM upload_receipts),(SELECT value#>>'{1,expires_at}' FROM upload_receipts),'all receipts share original deadline');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(pg_temp.upload_items('00000000-0000-4000-8000-00000000ed33'))$$,'22023','analysis_history_operation_conflict','changed cohort cannot reuse analysis ID');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(jsonb_build_array(pg_temp.upload_items()->1,pg_temp.upload_items()->0))$$,'22023','analysis_history_operation_conflict','changed order conflicts');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(jsonb_build_array(pg_temp.upload_items()->0,pg_temp.upload_items()->0))$$,'22023','invalid_analysis_history','duplicate media denied');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(jsonb_set(pg_temp.upload_items(),'{0,content_type}','"image/heic"'))$$,'22023','invalid_analysis_history','unsupported source denied before I/O');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(jsonb_set(pg_temp.upload_items(),'{0,byte_count}','5242880'))$$,'22023','invalid_analysis_history','aggregate byte cap enforced');
SELECT extensions.throws_ok($$SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ed09','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21',pg_temp.upload_items())$$,'P0002','analysis_history_not_found','foreign owner cannot replay cohort');
SELECT public.complete_owned_observation_evidence_upload('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21','00000000-0000-4000-8000-00000000ed31',(SELECT (value#>>'{0,object_id}')::UUID FROM upload_receipts));
RESET ROLE;
SELECT extensions.throws_ok($$UPDATE internal.observation_evidence_upload_cohorts SET expires_at=clock_timestamp()+INTERVAL '1 day'$$,'22023','analysis_history_evidence_immutable','fixed deadline cannot be renewed');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21','00000000-0000-4000-8000-00000000ed33','image/jpeg',3,repeat('a',64))$$,'22023','analysis_history_operation_conflict','private primitive cannot grow a sealed cohort');
SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21','00000000-0000-4000-8000-00000000ed32',(SELECT (value#>>'{1,object_id}')::UUID FROM upload_receipts));
CREATE FUNCTION pg_temp.assert_upload_manifest(reverse_order BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE SQL AS $$
SELECT internal.assert_protected_analysis_evidence('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed21',
    jsonb_build_object('schema_version',2,'items',(SELECT jsonb_agg(value||'{"kind":"image"}'::JSONB ORDER BY CASE WHEN reverse_order THEN -ordinal ELSE ordinal END)
        FROM jsonb_array_elements(pg_temp.upload_items()) WITH ORDINALITY AS entries(value,ordinal))),TRUE);
$$;
SELECT extensions.lives_ok('SELECT pg_temp.assert_upload_manifest()','original ordered image cohort can bind');
SELECT extensions.throws_ok('SELECT pg_temp.assert_upload_manifest(TRUE)','22023','analysis_history_operation_conflict','reordered images cannot bind to original upload identity');
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
UPDATE internal.observation_evidence_upload_cohorts SET expires_at=clock_timestamp()-INTERVAL '1 minute';
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_upload()','55000','analysis_history_evidence_unavailable','fully ready but unbound expired cohort is explicit remediation');
RESET ROLE;
UPDATE internal.observation_evidence_upload_cohorts SET expires_at=(SELECT (value#>>'{0,expires_at}')::TIMESTAMPTZ FROM upload_receipts);
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET ready_at=NULL WHERE media_id='00000000-0000-4000-8000-00000000ed32';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
-- Simulate one expired unready receipt's cleanup; immutable cohort must remain.
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET expires_at=clock_timestamp()-INTERVAL '1 minute' WHERE ready_at IS NULL;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT extensions.ok(internal.expire_observation_evidence('00000000-0000-4000-8000-00000000ed32'),'expired unready object retires');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_upload()','55000','analysis_history_evidence_unavailable','partial cleanup never re-allocates a missing object');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_upload(pg_temp.upload_items('00000000-0000-4000-8000-00000000ed33'))$$,'22023','analysis_history_operation_conflict','cleanup cannot erase immutable consent binding');
RESET ROLE;
DELETE FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000ed21';
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_upload()','55000','analysis_history_evidence_unavailable','complete cleanup also cannot renew an old analysis');
RESET ROLE;
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot)
VALUES('00000000-0000-4000-8000-00000000ed21','00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed01','{"schema_version":1}')$$,
'22023','analysis_history_operation_conflict','expired photo identity cannot become a description-only intent');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_erasure),2::BIGINT,'cleanup retains both erasure obligations');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ed11','00000000-0000-4000-8000-00000000ed01');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_upload_cohorts),0::BIGINT,'deletion fence removes private upload descriptors');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_upload()','P0002','analysis_history_not_found','deletion wins before upload replay');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

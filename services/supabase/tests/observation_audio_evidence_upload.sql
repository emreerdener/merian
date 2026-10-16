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
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11');
CREATE FUNCTION pg_temp.reserve_audio(bytes INTEGER DEFAULT 46, digest TEXT DEFAULT repeat('a',64)) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad31',bytes,digest);
$$;
CREATE FUNCTION pg_temp.reserve_photo() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21',jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000ad32','content_type','image/jpeg','byte_count',3,'sha256',repeat('b',64))));
$$;
SELECT extensions.ok(NOT prepared_audio_evidence_enabled,'audio starts disabled') FROM internal.observation_history_rollout;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name WHERE has_table_privilege(role_name,'internal.observation_audio_evidence_upload_cohorts','SELECT')),'audio table private');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.reserve_owned_observation_audio_evidence_cohort(uuid,uuid,uuid,uuid,integer,text)','EXECUTE'),'authenticated reserve denied');
SELECT extensions.ok(NOT has_function_privilege('anon','public.complete_owned_observation_audio_evidence_upload(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'anonymous complete denied');
GRANT EXECUTE ON FUNCTION pg_temp.reserve_audio(INTEGER,TEXT),pg_temp.reserve_photo() TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio()','55000','analysis_history_unavailable','closed gate denies service');
RESET ROLE;
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio(45)','22023','invalid_analysis_history','short WAV denied');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio(2700001)','22023','invalid_analysis_history','oversized WAV denied');
CREATE TEMP TABLE audio_receipt AS SELECT pg_temp.reserve_audio() value;
SELECT extensions.is(pg_temp.reserve_audio(),(SELECT value FROM audio_receipt),'exact reservation replay retains object and expiry');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio(48)','22023','analysis_history_operation_conflict','changed length conflicts');
SELECT extensions.throws_ok($$SELECT pg_temp.reserve_audio(46,repeat('b',64))$$,'22023','analysis_history_operation_conflict','changed digest conflicts');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_photo()','22023','analysis_history_operation_conflict','audio forbids photo cohort');
SELECT extensions.throws_ok($$SELECT public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000ad09','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad31',46,repeat('a',64))$$,'P0002','analysis_history_not_found','foreign owner denied');
CREATE TEMP TABLE ready_receipt AS SELECT public.complete_owned_observation_audio_evidence_upload('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad31',(SELECT (value->>'object_id')::UUID FROM audio_receipt)) value;
SELECT extensions.ok((SELECT value->>'ready_at' IS NOT NULL FROM ready_receipt),'trusted completion sets readiness');
SELECT extensions.is(pg_temp.reserve_audio(),(SELECT value FROM ready_receipt),'ready replay retains original receipt');
RESET ROLE;
SELECT extensions.throws_ok($$UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=clock_timestamp()$$,'22023','analysis_history_evidence_immutable','cohort is immutable');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad32','image/jpeg',3,repeat('b',64))$$,'22023','analysis_history_operation_conflict','primitive cannot extend audio cohort');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad22','00000000-0000-4000-8000-00000000ad32','audio/wav',46,repeat('b',64))$$,'22023','analysis_history_operation_conflict','WAV cannot bypass cohort');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES('00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad01','{"schema_version":1}')$$,'22023','analysis_history_operation_conflict','audio cannot enter existing intent');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000ad01',pg_temp.history_append_request('00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21'))$$,'22023','analysis_history_operation_conflict','audio cannot enter existing result');
-- Even premature trusted cleanup cannot allocate a successor under the same identity.
DELETE FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000ad21';
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad31','audio/wav',46,repeat('a',64))$$,'55000','analysis_history_unavailable','primitive cannot replace erased original object');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio()','55000','analysis_history_evidence_unavailable','unexpired missing receipt is not a fresh upload');
RESET ROLE;
-- Restore only synthetic fixture state to exercise expiry independently.
DELETE FROM internal.observation_evidence_erasure WHERE object_id=(SELECT (value->>'object_id')::UUID FROM audio_receipt);
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad31','audio/wav',46,repeat('a',64));
-- Fixture-only time travel preserves a matching cohort and receipt deadline.
ALTER TABLE internal.observation_audio_evidence_upload_cohorts DISABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=transaction_timestamp()-INTERVAL '1 minute';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000ad21';
ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE TRIGGER guard_observation_audio_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio()','55000','analysis_history_evidence_unavailable','expired ready audio never renews');
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'cleanup separately gated');
RESET ROLE;
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),1,'expired audio receipt retires atomically');
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'empty audio cohort not rediscovered');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_audio()','55000','analysis_history_evidence_unavailable','cleanup cannot mint successor');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_photo()','22023','analysis_history_operation_conflict','retained audio identity excludes photos');
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000ad21'),1,'cohort survives cleanup');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=(SELECT (value->>'object_id')::UUID FROM audio_receipt)),'cleanup retains erasure obligation');
SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES('00000000-0000-4000-8000-00000000ad21','00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad01','{"schema_version":1}')$$,'22023','analysis_history_operation_conflict','cleaned audio cannot become text');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ad11','00000000-0000-4000-8000-00000000ad01');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000ad21'),0,'parent deletion removes private cohort');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=(SELECT (value->>'object_id')::UUID FROM audio_receipt)),'deletion preserves opaque erasure');
SELECT * FROM extensions.finish();
ROLLBACK;

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

CREATE FUNCTION pg_temp.source_input(observation UUID,source UUID,child UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',3,'observation_id',observation,'analysis_id',child,'source_analysis_id',source,
 'request_digest',repeat('a',64),'entitlement_protocol',3,'identification_protocol',6,'history_protocol',9,'expected_processor_permission','google_gemini',
 'evidence_manifest',jsonb_build_object('schema_version',3,'items',jsonb_build_array(jsonb_build_object('kind','audio',
 'media_id','00000000-0000-4000-8000-00000000f999','content_type','audio/wav','byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.store_source(owner_id UUID,observation UUID,source UUID,child UUID,occupy BOOLEAN DEFAULT TRUE) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.source_input(observation,source,child);
BEGIN
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,observation,source,input,1,internal.observation_source_fingerprint(input));
 IF occupy THEN
 INSERT INTO internal.observation_analysis_source_occupancy(owner_id,observation_id,source_analysis_id,analysis_id) VALUES(owner_id,observation,source,child);
 END IF;
END;
$$;

CREATE FUNCTION pg_temp.writer_input(child UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
SELECT CASE WHEN version=3 THEN pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121',child)
ELSE pg_temp.source_input('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121',child) || jsonb_build_object('schema_version',2,'history_protocol',8,'evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000e999','content_type','image/jpeg','byte_count',46,'sha256',repeat('b',64))))) END;
$$;
CREATE FUNCTION pg_temp.writer_reserve(child UUID,version INTEGER,bytes INTEGER DEFAULT 46) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
IF version=3 THEN RETURN public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111',child,'00000000-0000-4000-8000-00000000f999',bytes,repeat('b',64)); END IF;
RETURN public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111',child,jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000e999','content_type','image/jpeg','byte_count',bytes,'sha256',repeat('b',64))));
END;
$$;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e101',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121'));
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.lock_observation_evidence_source(uuid,uuid,uuid)','EXECUTE'),'private evidence entry denies API role') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;

CREATE OR REPLACE FUNCTION pg_temp.legacy_reserve(child UUID,version INTEGER,bytes INTEGER DEFAULT 46) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
IF version=3 THEN RETURN public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111',child,'00000000-0000-4000-8000-00000000f998',bytes,repeat('b',64)); END IF;
RETURN public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111',child,jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000e998','content_type','image/jpeg','byte_count',bytes,'sha256',repeat('b',64))));
END;
$$;

SELECT extensions.lives_ok($$SELECT pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e141',2)$$,'V2 legacy cohort reserve remains supported');
SELECT extensions.ok((SELECT binding_analysis_id IS NULL FROM internal.observation_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000e141'),'legacy cohort remains NULL linked');
CREATE TEMP TABLE first_receipt_0 AS SELECT pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e141',2) AS value;
SELECT extensions.is(pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e141',2),(SELECT value FROM first_receipt_0),'legacy replay retains exact receipt');

INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
VALUES('00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121',pg_temp.writer_input('00000000-0000-4000-8000-00000000e131',2),1,internal.observation_source_fingerprint(pg_temp.writer_input('00000000-0000-4000-8000-00000000e131',2)));
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2)$$,'22023','analysis_history_operation_conflict','unoccupied binding cannot upload');
INSERT INTO internal.observation_analysis_source_occupancy VALUES('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e121','00000000-0000-4000-8000-00000000e131');
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2,47)$$,'22023','analysis_history_operation_conflict','changed bound media rejected');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e999','image/jpeg',46,repeat('b',64))$$,'22023','analysis_history_operation_conflict','raw reservation cannot bypass linked cohort');

SELECT extensions.throws_ok($test$ DO $body$ BEGIN INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,owner_id,observation_id,items) VALUES('00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111',internal.observation_source_cohort_items(pg_temp.writer_input('00000000-0000-4000-8000-00000000e131',2),2)); PERFORM pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2); END; $body$ $test$,'22023','analysis_history_operation_conflict','NULL cohort cannot retrofit into source binding');
SELECT extensions.lives_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2)$$,'V2 exact bound cohort and receipt created');
SELECT extensions.is((SELECT binding_analysis_id FROM internal.observation_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000e131'),'00000000-0000-4000-8000-00000000e131'::UUID,'new cohort links exact binding');
CREATE TEMP TABLE bound_receipt_0 AS SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2) AS value;
SELECT extensions.is(pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2),(SELECT value FROM bound_receipt_0),'bound replay preserves original object and deadline');
SELECT extensions.lives_ok($$SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000e101','00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e131','00000000-0000-4000-8000-00000000e999',(SELECT object_id FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000e999'))$$,'bound completion preserves source chain');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e131'),0::BIGINT,'evidence path grants no quota');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e131'),0::BIGINT,'evidence path creates no intent');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e111','00000000-0000-4000-8000-00000000e101');
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e131',2)$$,'P0002','analysis_history_not_found','deletion wins over bound replay');

CREATE OR REPLACE FUNCTION pg_temp.writer_input(child UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
SELECT CASE WHEN version=3 THEN pg_temp.source_input('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122',child)
ELSE pg_temp.source_input('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122',child) || jsonb_build_object('schema_version',2,'history_protocol',8,'evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000e999','content_type','image/jpeg','byte_count',46,'sha256',repeat('b',64))))) END;
$$;
CREATE OR REPLACE FUNCTION pg_temp.writer_reserve(child UUID,version INTEGER,bytes INTEGER DEFAULT 46) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
IF version=3 THEN RETURN public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112',child,'00000000-0000-4000-8000-00000000f999',bytes,repeat('b',64)); END IF;
RETURN public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112',child,jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000e999','content_type','image/jpeg','byte_count',bytes,'sha256',repeat('b',64))));
END;
$$;
SELECT pg_temp.seed_history_append('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e102',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122'));
SELECT set_config('request.jwt.claim.role','service_role',TRUE);

CREATE OR REPLACE FUNCTION pg_temp.legacy_reserve(child UUID,version INTEGER,bytes INTEGER DEFAULT 46) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
IF version=3 THEN RETURN public.reserve_owned_observation_audio_evidence_cohort('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112',child,'00000000-0000-4000-8000-00000000f998',bytes,repeat('b',64)); END IF;
RETURN public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112',child,jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000e998','content_type','image/jpeg','byte_count',bytes,'sha256',repeat('b',64))));
END;
$$;

SELECT extensions.lives_ok($$SELECT pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e142',3)$$,'V3 legacy cohort reserve remains supported');
SELECT extensions.ok((SELECT binding_analysis_id IS NULL FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000e142'),'legacy cohort remains NULL linked');
CREATE TEMP TABLE first_receipt_1 AS SELECT pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e142',3) AS value;
SELECT extensions.is(pg_temp.legacy_reserve('00000000-0000-4000-8000-00000000e142',3),(SELECT value FROM first_receipt_1),'legacy replay retains exact receipt');

INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
VALUES('00000000-0000-4000-8000-00000000e132','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122',pg_temp.writer_input('00000000-0000-4000-8000-00000000e132',3),1,internal.observation_source_fingerprint(pg_temp.writer_input('00000000-0000-4000-8000-00000000e132',3)));
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3)$$,'22023','analysis_history_operation_conflict','unoccupied binding cannot upload');
INSERT INTO internal.observation_analysis_source_occupancy VALUES('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122','00000000-0000-4000-8000-00000000e132');
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3,47)$$,'22023','analysis_history_operation_conflict','changed bound media rejected');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132','00000000-0000-4000-8000-00000000f999','audio/wav',46,repeat('b',64))$$,'22023','analysis_history_operation_conflict','raw reservation cannot bypass linked cohort');

SELECT extensions.throws_ok($test$ DO $body$ BEGIN INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,owner_id,observation_id,media_id,content_type,byte_count,sha256) VALUES('00000000-0000-4000-8000-00000000e132','00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000f999','audio/wav',46,repeat('b',64)); PERFORM pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3); END; $body$ $test$,'22023','analysis_history_operation_conflict','NULL cohort cannot retrofit into source binding');
SELECT extensions.lives_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3)$$,'V3 exact bound cohort and receipt created');
SELECT extensions.is((SELECT binding_analysis_id FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),'00000000-0000-4000-8000-00000000e132'::UUID,'new cohort links exact binding');
CREATE TEMP TABLE bound_receipt_1 AS SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3) AS value;
SELECT extensions.is(pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3),(SELECT value FROM bound_receipt_1),'bound replay preserves original object and deadline');
SELECT extensions.lives_ok($$SELECT internal.complete_observation_evidence('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132','00000000-0000-4000-8000-00000000f999',(SELECT object_id FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000f999'))$$,'bound completion preserves source chain');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e132'),0::BIGINT,'evidence path grants no quota');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),0::BIGINT,'evidence path creates no intent');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e102');
SELECT extensions.throws_ok($$SELECT pg_temp.writer_reserve('00000000-0000-4000-8000-00000000e132',3)$$,'P0002','analysis_history_not_found','deletion wins over bound replay');

SELECT * FROM extensions.finish();
ROLLBACK;

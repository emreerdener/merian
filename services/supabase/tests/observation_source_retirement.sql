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
CREATE FUNCTION pg_temp.seed_funded_history(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM pg_temp.seed_history_append(owner_id,observation);
    INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
    INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;

CREATE FUNCTION pg_temp.admission_input(parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.source_input(parent,source,child) || jsonb_build_object('schema_version',version,'history_protocol',CASE version WHEN 2 THEN 8 ELSE 9 END,
 'evidence_manifest',jsonb_build_object('schema_version',version,'items',jsonb_build_array(jsonb_build_object('kind',CASE version WHEN 2 THEN 'image' ELSE 'audio' END,'media_id',media,'content_type',CASE version WHEN 2 THEN 'image/jpeg' ELSE 'audio/wav' END,'byte_count',46,'sha256',repeat('b',64)))));
$$;
CREATE FUNCTION pg_temp.seed_bound_admission(owner_id UUID,parent UUID,source UUID,child UUID,media UUID,version INTEGER) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE input JSONB:=pg_temp.admission_input(parent,source,child,media,version); receipt JSONB;
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,parent);
 PERFORM internal.append_observation_analysis(owner_id,pg_temp.history_append_request(parent,source));
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,owner_id,parent,source,input,1,internal.observation_source_fingerprint(input));
 INSERT INTO internal.observation_analysis_source_occupancy VALUES(owner_id,parent,source,child);
 IF version=2 THEN
  receipt:=(public.reserve_owned_observation_evidence_cohort(owner_id,parent,child,internal.observation_source_cohort_items(input,2)))->0;
 ELSE receipt:=public.reserve_owned_observation_audio_evidence_cohort(owner_id,parent,child,media,46,repeat('b',64)); END IF;
 PERFORM internal.complete_observation_evidence(owner_id,parent,child,media,(receipt->>'object_id')::UUID);
 RETURN input;
END;
$$;
CREATE FUNCTION pg_temp.admit_bound(owner_id UUID,input JSONB) RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
 IF input->'schema_version'='2'::JSONB THEN RETURN internal.admit_protected_observation_analysis(owner_id,input,repeat('a',64)); END IF;
 RETURN internal.admit_audio_observation_analysis(owner_id,input,repeat('a',64));
END;
$$;
SELECT extensions.ok(NOT source_retirement_enabled,'source retirement gate defaults closed') FROM internal.observation_history_rollout;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3;
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE,execution_retirement_api_enabled=TRUE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000f202',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000f202','00000000-0000-4000-8000-00000000f212','00000000-0000-4000-8000-00000000f222','00000000-0000-4000-8000-00000000f232','00000000-0000-4000-8000-00000000f242',2));
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f202',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f252','observation_id','00000000-0000-4000-8000-00000000f212','analysis_id','00000000-0000-4000-8000-00000000f232','source_analysis_id','00000000-0000-4000-8000-00000000f222','request_digest',repeat('a',64)),10)$$,'55000','analysis_history_retirement_required','V2 gate holds source retirement');
UPDATE internal.observation_history_rollout SET source_retirement_enabled=TRUE;
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f232'$$,'22023','analysis_history_operation_conflict','V2 no unproven release');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET refund_count=1 WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232'; PERFORM public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f202',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f252','observation_id','00000000-0000-4000-8000-00000000f212','analysis_id','00000000-0000-4000-8000-00000000f232','source_analysis_id','00000000-0000-4000-8000-00000000f222','request_digest',repeat('a',64)),10); END; $body$ $test$,'22023','analysis_history_operation_conflict','V2 release proof failure rolls back full retirement');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232'),'reserved','V2 rollback leaves quota reserved');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_retirement_receipts WHERE analysis_id='00000000-0000-4000-8000-00000000f232'),0::BIGINT,'V2 rollback leaves no receipt');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f232'),1::BIGINT,'V2 rollback preserves occupancy');
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232';
UPDATE internal.observation_analysis_intents SET work_token=gen_random_uuid(),work_expires_at=clock_timestamp()+INTERVAL '1 hour' WHERE analysis_id='00000000-0000-4000-8000-00000000f232';
CREATE TEMP TABLE retired_2 AS SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f202',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f252','observation_id','00000000-0000-4000-8000-00000000f212','analysis_id','00000000-0000-4000-8000-00000000f232','source_analysis_id','00000000-0000-4000-8000-00000000f222','request_digest',repeat('a',64)),10) AS value;
SELECT extensions.is((SELECT value->>'state' FROM retired_2),'retired_before_dispatch','V2 original expired unused quota retires');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232'),'refunded','V2 original quota refunded');
SELECT extensions.is((SELECT refund_count FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232'),1,'V2 refunded only once');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f232'),0::BIGINT,'V2 occupancy released');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id='00000000-0000-4000-8000-00000000f232'),1::BIGINT,'V2 binding retained');
SELECT extensions.ok((SELECT state='failed_terminal' AND terminal_reason='retired_before_dispatch' AND work_token IS NULL AND work_expires_at IS NULL FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f232'),'V2 live worker revoked');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_bindings WHERE analysis_id='00000000-0000-4000-8000-00000000f232'$$,'22023','analysis_history_operation_conflict','V2 binding cannot be released');
UPDATE internal.observation_history_rollout SET source_retirement_enabled=FALSE,execution_retirement_api_enabled=FALSE;
SELECT extensions.is(public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f202',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f252','observation_id','00000000-0000-4000-8000-00000000f212','analysis_id','00000000-0000-4000-8000-00000000f232','source_analysis_id','00000000-0000-4000-8000-00000000f222','request_digest',repeat('a',64)),10),(SELECT value FROM retired_2),'V2 exact replay before closed gates and absent occupancy');
DELETE FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f232';
SELECT extensions.is(public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f202',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f252','observation_id','00000000-0000-4000-8000-00000000f212','analysis_id','00000000-0000-4000-8000-00000000f232','source_analysis_id','00000000-0000-4000-8000-00000000f222','request_digest',repeat('a',64)),10),(SELECT value FROM retired_2),'V2 exact replay survives removed accounting');
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=TRUE;
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000f203',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000f203','00000000-0000-4000-8000-00000000f213','00000000-0000-4000-8000-00000000f223','00000000-0000-4000-8000-00000000f233','00000000-0000-4000-8000-00000000f243',3));
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f203',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f253','observation_id','00000000-0000-4000-8000-00000000f213','analysis_id','00000000-0000-4000-8000-00000000f233','source_analysis_id','00000000-0000-4000-8000-00000000f223','request_digest',repeat('a',64)),10)$$,'55000','analysis_history_retirement_required','V3 gate holds source retirement');
UPDATE internal.observation_history_rollout SET source_retirement_enabled=TRUE;
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f233'$$,'22023','analysis_history_operation_conflict','V3 no unproven release');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET refund_count=1 WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233'; PERFORM public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f203',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f253','observation_id','00000000-0000-4000-8000-00000000f213','analysis_id','00000000-0000-4000-8000-00000000f233','source_analysis_id','00000000-0000-4000-8000-00000000f223','request_digest',repeat('a',64)),10); END; $body$ $test$,'22023','analysis_history_operation_conflict','V3 release proof failure rolls back full retirement');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233'),'reserved','V3 rollback leaves quota reserved');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_retirement_receipts WHERE analysis_id='00000000-0000-4000-8000-00000000f233'),0::BIGINT,'V3 rollback leaves no receipt');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f233'),1::BIGINT,'V3 rollback preserves occupancy');
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233';
UPDATE internal.observation_analysis_intents SET work_token=gen_random_uuid(),work_expires_at=clock_timestamp()+INTERVAL '1 hour' WHERE analysis_id='00000000-0000-4000-8000-00000000f233';
CREATE TEMP TABLE retired_3 AS SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f203',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f253','observation_id','00000000-0000-4000-8000-00000000f213','analysis_id','00000000-0000-4000-8000-00000000f233','source_analysis_id','00000000-0000-4000-8000-00000000f223','request_digest',repeat('a',64)),10) AS value;
SELECT extensions.is((SELECT value->>'state' FROM retired_3),'retired_before_dispatch','V3 original expired unused quota retires');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233'),'refunded','V3 original quota refunded');
SELECT extensions.is((SELECT refund_count FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233'),1,'V3 refunded only once');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id='00000000-0000-4000-8000-00000000f233'),0::BIGINT,'V3 occupancy released');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id='00000000-0000-4000-8000-00000000f233'),1::BIGINT,'V3 binding retained');
SELECT extensions.ok((SELECT state='failed_terminal' AND terminal_reason='retired_before_dispatch' AND work_token IS NULL AND work_expires_at IS NULL FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f233'),'V3 live worker revoked');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_analysis_source_bindings WHERE analysis_id='00000000-0000-4000-8000-00000000f233'$$,'22023','analysis_history_operation_conflict','V3 binding cannot be released');
UPDATE internal.observation_history_rollout SET source_retirement_enabled=FALSE,execution_retirement_api_enabled=FALSE;
SELECT extensions.is(public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f203',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f253','observation_id','00000000-0000-4000-8000-00000000f213','analysis_id','00000000-0000-4000-8000-00000000f233','source_analysis_id','00000000-0000-4000-8000-00000000f223','request_digest',repeat('a',64)),10),(SELECT value FROM retired_3),'V3 exact replay before closed gates and absent occupancy');
DELETE FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f233';
SELECT extensions.is(public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f203',jsonb_build_object('schema_version',1,'operation_id','00000000-0000-4000-8000-00000000f253','observation_id','00000000-0000-4000-8000-00000000f213','analysis_id','00000000-0000-4000-8000-00000000f233','source_analysis_id','00000000-0000-4000-8000-00000000f223','request_digest',repeat('a',64)),10),(SELECT value FROM retired_3),'V3 exact replay survives removed accounting');
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=TRUE;
SELECT * FROM extensions.finish();
ROLLBACK;

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
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;
SELECT extensions.ok(NOT source_dispatch_enabled,'source dispatch closed by default') FROM internal.observation_history_rollout;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.observation_analysis_dispatch_witnesses',privilege),'witness private to '||role_name||'/'||privilege) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['INSERT','UPDATE','DELETE','SELECT']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.prepare_source_dispatch_witness(uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),'witness writer private to '||role_name) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3;
UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE,dispatch_enabled=TRUE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000e102',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e122','00000000-0000-4000-8000-00000000e132','00000000-0000-4000-8000-00000000e142',2));
SELECT extensions.throws_ok($$SELECT internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132'))$$,'55000','analysis_history_unavailable','V2 fresh dispatch gate closed');
SELECT set_config('merian.observation_analysis_provider','00000000-0000-4000-8000-00000000e102:00000000-0000-4000-8000-00000000e132',TRUE);
SELECT extensions.throws_ok($$SELECT * FROM public.commit_identification_invocation((SELECT (quota->>'reservation_id')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),'00000000-0000-4000-8000-00000000e102',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),1,pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132'))$$,'55000','analysis_history_dispatch_required','V2 forged context cannot create witness');
UPDATE internal.observation_history_rollout SET source_dispatch_enabled=TRUE;
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE original_analysis_id='00000000-0000-4000-8000-00000000e132'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V2 expired lease holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET attempt_count=2 WHERE original_analysis_id='00000000-0000-4000-8000-00000000e132'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V2 changed attempt holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.identification_provider_attempts SET input_profile='multimodal_text_v1' WHERE reservation_id=(SELECT (quota->>'reservation_id')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'); PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V2 wrong profile holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.observation_analysis_intents SET provider_outcome='{}' WHERE analysis_id='00000000-0000-4000-8000-00000000e132'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V2 prior outcome holds');
CREATE TEMP TABLE grant_2 AS SELECT internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')) AS value;
SELECT extensions.is((SELECT value->>'may_dispatch' FROM grant_2),'true','V2 only first dispatch granted');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e132'),'committed','V2 quota committed atomically');
UPDATE internal.observation_history_rollout SET source_dispatch_enabled=FALSE,dispatch_enabled=FALSE;
SELECT extensions.is((internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e102','00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e132',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e132')))->>'may_dispatch','false','V2 replay before fresh gates never dispatches');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),1::BIGINT,'V2 one retained witness');
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_dispatch_witnesses SET attempt_count=1 WHERE analysis_id='00000000-0000-4000-8000-00000000e132'$$,'22023','analysis_history_operation_conflict','V2 witness immutable');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e112','00000000-0000-4000-8000-00000000e102');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e132'),'committed','V2 deletion never refunds dispatch');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id='00000000-0000-4000-8000-00000000e132'),0::BIGINT,'V2 deletion erases witness');
UPDATE internal.observation_history_rollout SET dispatch_enabled=TRUE;
SELECT pg_temp.admit_bound('00000000-0000-4000-8000-00000000e103',pg_temp.seed_bound_admission('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e123','00000000-0000-4000-8000-00000000e133','00000000-0000-4000-8000-00000000e143',3));
SELECT extensions.throws_ok($$SELECT internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133'))$$,'55000','analysis_history_unavailable','V3 fresh dispatch gate closed');
SELECT set_config('merian.observation_analysis_provider','00000000-0000-4000-8000-00000000e103:00000000-0000-4000-8000-00000000e133',TRUE);
SELECT extensions.throws_ok($$SELECT * FROM public.commit_identification_invocation((SELECT (quota->>'reservation_id')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),'00000000-0000-4000-8000-00000000e103',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),1,pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133'))$$,'55000','analysis_history_dispatch_required','V3 forged context cannot create witness');
UPDATE internal.observation_history_rollout SET source_dispatch_enabled=TRUE;
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE original_analysis_id='00000000-0000-4000-8000-00000000e133'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V3 expired lease holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.ai_quota_reservations SET attempt_count=2 WHERE original_analysis_id='00000000-0000-4000-8000-00000000e133'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V3 changed attempt holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.identification_provider_attempts SET input_profile='multimodal_text_v1' WHERE reservation_id=(SELECT (quota->>'reservation_id')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'); PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V3 wrong profile holds');
SELECT extensions.throws_ok($test$ DO $body$ BEGIN UPDATE internal.observation_analysis_intents SET provider_outcome='{}' WHERE analysis_id='00000000-0000-4000-8000-00000000e133'; PERFORM internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')); END; $body$ $test$,'55000','analysis_history_dispatch_required','V3 prior outcome holds');
CREATE TEMP TABLE grant_3 AS SELECT internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')) AS value;
SELECT extensions.is((SELECT value->>'may_dispatch' FROM grant_3),'true','V3 only first dispatch granted');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e133'),'committed','V3 quota committed atomically');
UPDATE internal.observation_history_rollout SET source_dispatch_enabled=FALSE,dispatch_enabled=FALSE;
SELECT extensions.is((internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000e103','00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e133',(SELECT (quota->>'lease_token')::UUID FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000e133')))->>'may_dispatch','false','V3 replay before fresh gates never dispatches');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),1::BIGINT,'V3 one retained witness');
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_dispatch_witnesses SET attempt_count=1 WHERE analysis_id='00000000-0000-4000-8000-00000000e133'$$,'22023','analysis_history_operation_conflict','V3 witness immutable');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e113','00000000-0000-4000-8000-00000000e103');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000e133'),'committed','V3 deletion never refunds dispatch');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id='00000000-0000-4000-8000-00000000e133'),0::BIGINT,'V3 deletion erases witness');
UPDATE internal.observation_history_rollout SET dispatch_enabled=TRUE;
SELECT * FROM extensions.finish();
ROLLBACK;

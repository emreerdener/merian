\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN PROTECTED ANALYSIS HELPERS
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
CREATE FUNCTION pg_temp.funded_input(observation UUID,analysis UUID,source UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT (pg_temp.history_append_request(observation,analysis,source)-'result_snapshot') || '{"entitlement_protocol":3,"identification_protocol":6,"history_protocol":7,"expected_processor_permission":"google_gemini"}'::JSONB;
$$;
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;
CREATE FUNCTION pg_temp.funded_dispatch(owner_id UUID,observation UUID,analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT internal.dispatch_observation_analysis(owner_id,observation,analysis,(quota->>'lease_token')::UUID,pg_temp.funded_provenance(analysis)) FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.funded_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
    SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
        pg_temp.history_append_request(observation,analysis,(input_snapshot->>'source_analysis_id')::UUID) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
    FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.protected_input(observation UUID,analysis UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','openai','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
$$;
CREATE FUNCTION pg_temp.protected_ready(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE receipt JSONB;
BEGIN
 receipt:=internal.reserve_observation_evidence(owner_id,observation,analysis,media,'image/jpeg',3,repeat('a',64));
 PERFORM internal.complete_observation_evidence(owner_id,observation,analysis,media,(receipt->>'object_id')::UUID);
 RETURN (receipt->>'object_id')::UUID;
END;
$$;
CREATE FUNCTION pg_temp.protected_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
 SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
 (input_snapshot-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
 FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
-- END PROTECTED ANALYSIS HELPERS
SELECT extensions.ok(NOT(SELECT protected_analysis_enabled FROM internal.observation_history_rollout),'protected analysis is closed independently');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) AS r
 WHERE n.nspname='internal' AND p.proname IN ('admit_protected_observation_analysis','append_protected_observation_analysis','assert_protected_analysis_evidence','expire_unbound_observation_evidence') AND has_function_privilege(r,p.oid,'EXECUTE')),'API roles cannot bind or expire evidence');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE;
CREATE FUNCTION pg_temp.admit_protected(analysis UUID DEFAULT '00000000-0000-4000-8000-00000000e721',media UUID DEFAULT '00000000-0000-4000-8000-00000000e731') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e701',pg_temp.protected_input('00000000-0000-4000-8000-00000000e711',analysis,media),repeat('a',64));
$$;
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e731','image/jpeg',3,repeat('a',64));
SELECT extensions.throws_ok('SELECT pg_temp.admit_protected()','55000','analysis_history_unavailable','closed binding gate creates no intent');
UPDATE internal.observation_history_rollout SET protected_analysis_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.admit_protected()','55000','analysis_history_evidence_unavailable','unready receipt cannot admit inference');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000e701'),0::BIGINT,'invalid evidence cannot hold credit');
CREATE TEMP TABLE image_objects AS SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e731') AS id;
SELECT extensions.throws_ok($$SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e701',jsonb_set(pg_temp.protected_input('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e731'),'{evidence_manifest,items,0,sha256}',to_jsonb(repeat('b',64))),repeat('a',64))$$,'55000','analysis_history_evidence_unavailable','claimed content must match verified object tuple');
SELECT extensions.throws_ok($$SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000e701',pg_temp.funded_input('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721'),repeat('a',64))$$,'22023','analysis_history_operation_conflict','V1 admission still rejects protected media');
SELECT extensions.throws_ok($$SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e701',pg_temp.protected_input('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e729','00000000-0000-4000-8000-00000000e731'),repeat('a',64))$$,'55000','analysis_history_evidence_unavailable','another analysis cannot reuse this receipt');
SELECT extensions.throws_ok($$SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e701',jsonb_set(pg_temp.protected_input('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e731'),'{evidence_manifest,items,0,object_id}','"00000000-0000-4000-8000-00000000e740"'),repeat('a',64))$$,'22023','invalid_analysis_history','object keys cannot be smuggled into protected snapshots');
SELECT extensions.throws_ok($$SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e701',pg_temp.protected_input('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e731') || '{"history_protocol":7}',repeat('a',64))$$,'22023','invalid_analysis_history','old client cannot initiate protected V2');
SELECT pg_temp.admit_protected();
SELECT pg_temp.admit_protected();
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000e701'),1::BIGINT,'photo admission replay holds one credit');
SELECT extensions.is((SELECT quota->>'input_profile' FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e721'),'multimodal_photo_v1','photo routing does not use text profile');
SELECT extensions.throws_ok($$DELETE FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000e731'$$,'55000','analysis_history_evidence_bound','admitted media cannot be independently deleted');
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721','00000000-0000-4000-8000-00000000e739','image/jpeg',3,repeat('a',64))$$,'22023','analysis_history_operation_conflict','admission seals exact media set');
-- Synthetic clock advancement without sleeping: immutable production metadata is never editable.
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET expires_at=clock_timestamp()-INTERVAL '1 second' WHERE media_id='00000000-0000-4000-8000-00000000e731';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT extensions.is(internal.expire_unbound_observation_evidence('00000000-0000-4000-8000-00000000e731'),FALSE,'admission pins ready evidence past reservation expiry');
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721');
SELECT pg_temp.protected_draft('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721');
SELECT extensions.throws_ok($$SELECT internal.append_protected_observation_analysis(owner_id,draft) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e721'$$,'55000','analysis_history_completion_required','raw media append cannot bypass funded completion');
CREATE TEMP TABLE protected_receipt AS SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721') AS value;
SELECT extensions.is((SELECT (value->>'snapshot')::JSONB->>'schema_version' FROM protected_receipt),'2','protected result explicitly stores V2 snapshot');
SELECT extensions.ok((SELECT value->>'snapshot' NOT LIKE '%' || id::TEXT || '%' FROM protected_receipt CROSS JOIN image_objects),'snapshot contains no private object UUID/key');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000e721'),'consumed','durable photo result settles one credit');
SELECT extensions.is(internal.complete_observation_analysis('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721'),(SELECT value FROM protected_receipt),'lost response returns exact V2 completion receipt');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000e701',TRUE);
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e711","limit":1,"before_ordinal":1}',7)$$,'55000','analysis_history_reader_upgrade_required','protocol7 rejects whole mixed history even cursor excludes V2');
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000e702',TRUE);
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e711","limit":1,"before_ordinal":null}',7)$$,'P0002','analysis_history_not_found','foreign reader cannot learn protected version');
SELECT set_config('request.jwt.claim.sub','',TRUE);
INSERT INTO image_objects SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e722','00000000-0000-4000-8000-00000000e732');
SELECT pg_temp.admit_protected('00000000-0000-4000-8000-00000000e722','00000000-0000-4000-8000-00000000e732');
SELECT internal.fail_observation_analysis(owner_id,observation_id,analysis_id,(quota->>'lease_token')::UUID,'cancelled_before_dispatch','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000e722';
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000e722'),0::BIGINT,'terminal cancellation retires unused ready evidence');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_erasure WHERE object_id IN (SELECT id FROM image_objects)),1::BIGINT,'terminal cleanup is durable before return');
SELECT extensions.is(pg_temp.admit_protected('00000000-0000-4000-8000-00000000e722','00000000-0000-4000-8000-00000000e732')->>'state','failed_terminal','terminal admission retry needs no erased evidence');
INSERT INTO image_objects SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e723','00000000-0000-4000-8000-00000000e733');
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET expires_at=clock_timestamp()-INTERVAL '1 second' WHERE media_id='00000000-0000-4000-8000-00000000e733';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT extensions.throws_ok($$SELECT pg_temp.admit_protected('00000000-0000-4000-8000-00000000e723','00000000-0000-4000-8000-00000000e733')$$,'55000','analysis_history_evidence_unavailable','expired unbound ready evidence cannot be admitted');
SELECT extensions.is(internal.expire_unbound_observation_evidence('00000000-0000-4000-8000-00000000e733'),TRUE,'unbound ready upload can be cleaned after expiry');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e701');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects WHERE observation_id='00000000-0000-4000-8000-00000000e711'),0::BIGINT,'parent deletion removes even pinned completed evidence');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_erasure WHERE object_id IN (SELECT id FROM image_objects)),3::BIGINT,'all object erasures survive history deletion');
SELECT extensions.throws_ok($$SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000e701','00000000-0000-4000-8000-00000000e711','00000000-0000-4000-8000-00000000e721')$$,'P0002','analysis_history_not_found','deletion wins protected completion replay');
SELECT * FROM extensions.finish();
ROLLBACK;

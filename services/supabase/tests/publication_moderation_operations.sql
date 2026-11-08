\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN PHOTO MODERATION HELPERS
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Unidentified plant','is_biological_subject',TRUE,
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
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','google_gemini','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
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

CREATE FUNCTION pg_temp.seed_publication_intent(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,observation);
 PERFORM pg_temp.protected_ready(owner_id,observation,analysis,media);
 PERFORM internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64));
 PERFORM pg_temp.funded_dispatch(owner_id,observation,analysis);
 PERFORM pg_temp.protected_draft(owner_id,observation,analysis);
 PERFORM internal.complete_observation_analysis(owner_id,observation,analysis);
END;
$$;
CREATE FUNCTION pg_temp.publication_request(observation UUID,analysis UUID,operation UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id',observation,'analysis_id',analysis,'operation_id',operation,
 'expected_observation_revision',1,'expected_review_revision',0,'taxonomy_version_id',public.active_taxonomy_version_id(),
 'initial_taxon_id',NULL,'note','Synthetic public note','media_ids',jsonb_build_array(media));
$$;

CREATE FUNCTION pg_temp.seed_photo_moderation(owner_id UUID,observation UUID,analysis UUID,media UUID,operation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM pg_temp.seed_publication_intent(owner_id,observation,analysis,media);
 PERFORM internal.prepare_observation_publication_intent(owner_id,pg_temp.publication_request(observation,analysis,operation,media));
END;
$$;
CREATE FUNCTION pg_temp.photo_execution_proof(receipt JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'policy_version','photo_publication_v1',
 'policy_sha256','b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9','request_sha256',repeat('b',64),
 'provider','gemini','model','gemini-2.5-flash','processor_permission','google_gemini','source',receipt->'source');
$$;
CREATE FUNCTION pg_temp.photo_execution_result(decision TEXT DEFAULT 'approved') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('decision',decision,'classification',CASE WHEN decision='approved' THEN 'allow' ELSE 'reject' END,'confidence',0.99,
 'categories','[]'::JSONB,'model','gemini-2.5-flash','usage',jsonb_build_object('input_tokens',100,'output_tokens',10,'total_tokens',110));
$$;
CREATE FUNCTION pg_temp.prepare_photo_execution(owner_id UUID,observation UUID,receipt JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.prepare_publication_photo_execution(owner_id,observation,(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt));
$$;

-- Reconstruct pre-guard admitted rows for compatibility/capacity tests only.
CREATE FUNCTION pg_temp.legacy_publication_intake(owner_id UUID, request JSONB, ip TEXT) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM internal.prepare_observation_publication_intent(owner_id,request);
 INSERT INTO internal.observation_publication_operations(operation_id,observation_id,owner_id,ip_hash,receipt)
 VALUES((request->>'operation_id')::UUID,(request->>'observation_id')::UUID,owner_id,ip,
 jsonb_build_object('schema_version',1,'operation_id',request->'operation_id','observation_id',request->'observation_id',
 'analysis_id',request->'analysis_id','status','accepted','admitted_at',clock_timestamp()));
END;
$$;

-- END PHOTO MODERATION HELPERS

UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE,publication_intent_enabled=TRUE,publication_operation_enabled=TRUE,publication_execution_enabled=TRUE,publication_moderation_enabled=TRUE;
UPDATE internal.ai_quota_policies SET enabled=TRUE WHERE operation='observation_photo_publication_moderation';
SELECT pg_temp.seed_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff31','00000000-0000-4000-8000-00000000ff41');
SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff41','00000000-0000-4000-8000-00000000ff31'),repeat('b',64));
SELECT pg_temp.legacy_publication_intake('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff44','00000000-0000-4000-8000-00000000ff31'),repeat('b',64));
CREATE TEMP TABLE work AS SELECT public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41') AS receipt;
CREATE TEMP TABLE attempts(label TEXT PRIMARY KEY,receipt JSONB);
GRANT SELECT,INSERT ON work,attempts TO service_role;
CREATE FUNCTION pg_temp.recover() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.read_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41',(SELECT (receipt->>'work_token')::UUID FROM work));
$$;
CREATE FUNCTION pg_temp.admit(media UUID DEFAULT '00000000-0000-4000-8000-00000000ff31') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41',(SELECT (receipt->>'work_token')::UUID FROM work),media);
$$;
CREATE FUNCTION pg_temp.advance(action TEXT,payload JSONB DEFAULT '{}',operation UUID DEFAULT '00000000-0000-4000-8000-00000000ff41') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.advance_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',operation,(SELECT (receipt->>'work_token')::UUID FROM work),(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,action,payload) FROM attempts WHERE label='original';
$$;
GRANT EXECUTE ON FUNCTION pg_temp.recover(),pg_temp.admit(UUID),pg_temp.advance(TEXT,JSONB,UUID),pg_temp.photo_execution_proof(JSONB),pg_temp.photo_execution_result(TEXT) TO service_role,authenticated;
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.read_publication_moderation_work(uuid,uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.admit_publication_moderation_work(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'client roles cannot recover provider tokens or nominate scope');
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.recover(),'[{"media_id":"00000000-0000-4000-8000-00000000ff31","attempt":null}]'::JSONB,'actual service recovers exact cohort with no manufactured attempt');
SELECT extensions.throws_ok($$SELECT pg_temp.admit('00000000-0000-4000-8000-00000000ffff')$$,'P0002','analysis_history_not_found','outside cohort denied before quota');
INSERT INTO attempts VALUES('original',pg_temp.admit());
SELECT extensions.is(pg_temp.admit(),(SELECT receipt FROM attempts WHERE label='original'),'lost admission reply recovers same attempt');
SELECT extensions.is(pg_temp.recover()#>'{0,attempt}',(SELECT receipt FROM attempts WHERE label='original'),'recovery includes original provider lease');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('dispatch')$$,'22023','analysis_history_operation_conflict','dispatch still requires durable execution proof');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('retire','{}','00000000-0000-4000-8000-00000000ff44')$$,'P0002','analysis_history_not_found','another operation cannot use this provider token');
SELECT extensions.is(pg_temp.advance('prepare',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt))),'{}'::JSONB,'proof saved through exact scoped facade') FROM attempts WHERE label='original';
RESET ROLE;
SELECT extensions.is((SELECT c.scope_key FROM internal.ai_quota_reservation_counters c JOIN internal.observation_photo_moderation_attempts a ON c.reservation_id=(a.quota->>'reservation_id')::UUID WHERE c.scope_type='ip_rate'),repeat('b',64),'provider reservation uses original intake hash');
SELECT extensions.ok((SELECT q.complimentary_client_scan_id IS NULL AND q.original_analysis_id IS NULL FROM internal.ai_quota_reservations q JOIN internal.observation_photo_moderation_attempts a ON q.id=(a.quota->>'reservation_id')::UUID),'no complimentary credit or original analysis identity borrowed');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=FALSE;
SELECT extensions.throws_ok($$SELECT pg_temp.advance('dispatch')$$,'55000','analysis_history_unavailable','closing execution gate blocks paid dispatch under existing work');
SELECT extensions.is(pg_temp.recover()#>>'{0,attempt,state}','reserved','recovery remains readable while claim lives after gate closure');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE;
UPDATE internal.observation_publication_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE work_token IS NOT NULL;
SELECT extensions.throws_ok($$SELECT pg_temp.advance('retire')$$,'22023','analysis_history_operation_conflict','expired orchestrator cannot cancel another worker reserved attempt');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('dispatch')$$,'22023','analysis_history_operation_conflict','expired work cannot start paid dispatch');
UPDATE work SET receipt=public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41');
SELECT extensions.is(pg_temp.admit(),(SELECT receipt FROM attempts WHERE label='original'),'replacement work recovers original reserved provider attempt');
SELECT extensions.is(pg_temp.advance('dispatch')->>'dispatch_allowed','true','one exact dispatch permit');
SELECT extensions.is(pg_temp.advance('dispatch')->>'dispatch_allowed','false','replay cannot execute provider twice');
UPDATE internal.observation_publication_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE work_token IS NOT NULL;
UPDATE internal.observation_history_rollout SET publication_execution_enabled=FALSE;
SELECT extensions.throws_ok($$SELECT pg_temp.advance('retire')$$,'22023','analysis_history_operation_conflict','live provider dispatch cannot retire early despite work expiry');
INSERT INTO attempts SELECT 'approved',pg_temp.advance('complete',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt),'result',pg_temp.photo_execution_result())) FROM attempts WHERE label='original';
SELECT extensions.is((SELECT receipt->>'state' FROM attempts WHERE label='approved'),'approved','late provider result commits after orchestration expiry and execution gate closure');
SELECT extensions.is(pg_temp.advance('complete',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt),'result',pg_temp.photo_execution_result())),(SELECT receipt FROM attempts WHERE label='approved'),'identical late completion recovers durable receipt') FROM attempts WHERE label='original';
SELECT extensions.throws_ok($$SELECT pg_temp.advance('complete',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt),'result',pg_temp.photo_execution_result('rejected'))) FROM attempts WHERE label='original'$$,'22023','analysis_history_operation_conflict','late result cannot change decision');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE;
UPDATE work SET receipt=public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41');
SELECT extensions.is(pg_temp.admit(),(SELECT receipt FROM attempts WHERE label='approved'),'terminal recovery never auto-creates a successor');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderation_attempts),1,'one attempt across claim changes and retries');
-- A second accepted operation proves expiry retirement keeps provider accounting
-- and cannot become automatic admission of another provider attempt.
SELECT pg_temp.legacy_publication_intake('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff42','00000000-0000-4000-8000-00000000ff31'),repeat('b',64));
UPDATE work SET receipt=public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff42');
UPDATE attempts SET label='prior' WHERE label='original';
INSERT INTO attempts SELECT 'original',public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff42',(receipt->>'work_token')::UUID,'00000000-0000-4000-8000-00000000ff31') FROM work;
SELECT pg_temp.advance('prepare',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt)),'00000000-0000-4000-8000-00000000ff42') FROM attempts WHERE label='original';
SELECT pg_temp.advance('dispatch','{}','00000000-0000-4000-8000-00000000ff42');
-- Synthetic clock advancement only, rolled back with the whole catalog.
ALTER TABLE internal.observation_photo_moderation_attempts DISABLE TRIGGER guard_publication_moderation_attempt_update;
UPDATE internal.observation_photo_moderation_attempts SET dispatch_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id=(SELECT (receipt->>'attempt_id')::UUID FROM attempts WHERE label='original');
ALTER TABLE internal.observation_photo_moderation_attempts ENABLE TRIGGER guard_publication_moderation_attempt_update;
UPDATE internal.observation_publication_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE work_token IS NOT NULL;
UPDATE internal.observation_history_rollout SET publication_execution_enabled=FALSE;
SELECT extensions.is(pg_temp.advance('retire','{}','00000000-0000-4000-8000-00000000ff42')->>'state','unknown_execution','expired dispatched retirement ignores orchestration expiry and closed execution gate');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM attempts WHERE label='original')),'failed','uncertain dispatch retains provider charge');
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE;
UPDATE work SET receipt=public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff42');
SELECT extensions.is(public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff42',(receipt->>'work_token')::UUID,'00000000-0000-4000-8000-00000000ff31')->>'state','unknown_execution','unknown execution remains terminal without automatic successor') FROM work;
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderation_attempts),2,'recovery creates no third attempt');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.read_publication_moderation_work('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff41','00000000-0000-4000-8000-00000000ffff')$$,'42501','permission denied for function read_publication_moderation_work','actual authenticated role cannot read provider lease');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff01');
SELECT extensions.throws_ok('SELECT pg_temp.recover()','P0002','analysis_history_not_found','deletion defeats recovery');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('complete',jsonb_build_object('proof',pg_temp.photo_execution_proof(receipt),'result',pg_temp.photo_execution_result())) FROM attempts WHERE label='original'$$,'P0002','analysis_history_not_found','deletion defeats late completion replay');
SELECT * FROM extensions.finish();
ROLLBACK;

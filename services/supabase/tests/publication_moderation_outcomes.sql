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
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','google_gemini','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000ee32','content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
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
 PERFORM pg_temp.protected_ready(owner_id,observation,analysis,'00000000-0000-4000-8000-00000000ee32');
 PERFORM internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64));
 PERFORM pg_temp.funded_dispatch(owner_id,observation,analysis);
 PERFORM pg_temp.protected_draft(owner_id,observation,analysis);
 PERFORM internal.complete_observation_analysis(owner_id,observation,analysis);
END;
$$;
CREATE FUNCTION pg_temp.publication_request(observation UUID,analysis UUID,operation UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id',observation,'analysis_id',analysis,'operation_id',operation,
 'expected_observation_revision',1,'expected_review_revision',0,'taxonomy_version_id',public.active_taxonomy_version_id(),
 'initial_taxon_id',NULL,'note',CASE WHEN operation='00000000-0000-4000-8000-00000000ee41' THEN NULL ELSE 'Synthetic public note' END,'media_ids',jsonb_build_array(media,'00000000-0000-4000-8000-00000000ee32'));
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
SELECT pg_temp.seed_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee21','00000000-0000-4000-8000-00000000ee31','00000000-0000-4000-8000-00000000ee41');
CREATE TEMP TABLE outcomes_work(operation UUID PRIMARY KEY,token UUID,attempt JSONB);
CREATE FUNCTION pg_temp.new_work(op UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE work JSONB;
BEGIN
 PERFORM pg_temp.legacy_publication_intake('00000000-0000-4000-8000-00000000ee01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee21',op,'00000000-0000-4000-8000-00000000ee31'),repeat('b',64));
 work:=public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op);
 INSERT INTO outcomes_work VALUES(op,(work->>'work_token')::UUID,NULL);
END;
$$;
CREATE FUNCTION pg_temp.settle(op UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op,token) FROM outcomes_work WHERE operation=op;
$$;
CREATE FUNCTION pg_temp.advance(op UUID,action TEXT,result TEXT DEFAULT 'approved') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.advance_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op,token,(attempt->>'attempt_id')::UUID,(attempt->>'lease_token')::UUID,action,
 CASE WHEN action='prepare' THEN jsonb_build_object('proof',pg_temp.photo_execution_proof(attempt))
 WHEN action='complete' THEN jsonb_build_object('proof',pg_temp.photo_execution_proof(attempt),'result',pg_temp.photo_execution_result(result)) ELSE '{}'::JSONB END)
 FROM outcomes_work WHERE operation=op;
$$;
CREATE FUNCTION pg_temp.status(op UUID) RETURNS TEXT LANGUAGE SQL AS $$
 SELECT public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op)->>'status';
$$;
SELECT pg_temp.new_work('00000000-0000-4000-8000-00000000ee41');
SELECT pg_temp.new_work('00000000-0000-4000-8000-00000000ee42');
SELECT pg_temp.new_work('00000000-0000-4000-8000-00000000ee43');
SELECT pg_temp.new_work('00000000-0000-4000-8000-00000000ee44');
SELECT pg_temp.new_work('00000000-0000-4000-8000-00000000ee45');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":false}'::JSONB,'unattempted cohort remains pending');
SELECT extensions.throws_ok($$SELECT public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',gen_random_uuid())$$,'22023','analysis_history_operation_conflict','stale token cannot settle fresh work');
SELECT extensions.throws_ok($$SELECT public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ee02','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',NULL)$$,'P0002','analysis_history_not_found','cross owner cannot settle');

CREATE FUNCTION pg_temp.container_attestation(op UUID DEFAULT '00000000-0000-4000-8000-00000000ee45') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'policy_version','public_photo_container_v1','source',sources->0) FROM internal.observation_publication_intents WHERE operation_id=op;
$$;
CREATE FUNCTION pg_temp.finish_container(op UUID DEFAULT '00000000-0000-4000-8000-00000000ee45',att JSONB DEFAULT NULL,work UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.finalize_publication_container_rejection('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op,COALESCE(work,token),COALESCE(att,pg_temp.container_attestation(op))) FROM outcomes_work WHERE operation=op;
$$;
SELECT extensions.is((SELECT publication_container_settlement_enabled FROM internal.observation_history_rollout),FALSE,'container attestation ships disabled');
SELECT extensions.throws_ok('SELECT pg_temp.finish_container()','55000','analysis_history_unavailable','source settlement cannot enable container settlement');
SAVEPOINT container_trial;
UPDATE internal.observation_history_rollout SET publication_container_settlement_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT pg_temp.finish_container(work=>gen_random_uuid())$$,'22023','analysis_history_operation_conflict','container settlement requires exact live work');
SELECT extensions.throws_ok($$SELECT pg_temp.finish_container(att=>jsonb_set(pg_temp.container_attestation(),'{source,sha256}',to_jsonb(repeat('b',64))))$$,'22023','invalid_analysis_history','container proof cannot replace original digest');
SELECT extensions.throws_ok($$SELECT pg_temp.finish_container(att=>pg_temp.container_attestation() || '{"diagnostic":"private"}'::jsonb)$$,'22023','invalid_analysis_history','container proof rejects diagnostics and extra fields');
SELECT extensions.throws_ok($$SELECT pg_temp.finish_container(att=>jsonb_set(pg_temp.container_attestation(),'{policy_version}','"unreviewed"'))$$,'22023','invalid_analysis_history','container proof pins reviewed policy');
SELECT extensions.throws_ok($$SELECT public.finalize_publication_container_rejection('00000000-0000-4000-8000-00000000ee02','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',NULL,pg_temp.container_attestation())$$,'P0002','analysis_history_not_found','container proof remains owner scoped');
SAVEPOINT container_attempt;
SELECT public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT token FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45'),'00000000-0000-4000-8000-00000000ee31');
SELECT extensions.throws_ok('SELECT pg_temp.finish_container()','22023','analysis_history_operation_conflict','existing provider attempt retains recovery ownership');
ROLLBACK TO container_attempt;
GRANT SELECT ON outcomes_work TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.finish_container(UUID,JSONB,UUID),pg_temp.container_attestation(UUID) TO service_role;
CREATE TEMP TABLE frozen_container AS SELECT pg_temp.container_attestation() AS att;
GRANT SELECT ON frozen_container TO service_role;
-- The helper reads private intent only as fixture owner; actual service submits
-- the frozen attestation through the granted facade, never a table read.
SET LOCAL ROLE service_role;
SELECT extensions.is(public.finalize_publication_container_rejection('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT token FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45'),(SELECT att FROM frozen_container)),'{"finalized":true,"status":"needs_action","reason":"public_container_rejected"}'::JSONB,'actual service persists exact container attestation');
SELECT extensions.throws_ok('SELECT * FROM internal.observation_publication_container_attestations','42501','permission denied for table observation_publication_container_attestations','service cannot directly read private attestation');
RESET ROLE;
SELECT extensions.is((SELECT attestation FROM internal.observation_publication_container_attestations WHERE operation_id='00000000-0000-4000-8000-00000000ee45'),pg_temp.container_attestation(),'stored attestation equals exact original source and policy');
SELECT extensions.is((SELECT attempt_ids FROM internal.observation_publication_moderation_outcomes WHERE operation_id='00000000-0000-4000-8000-00000000ee45'),'{}'::UUID[],'container outcome contains no provider attempt');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_work WHERE operation_id='00000000-0000-4000-8000-00000000ee45'),0,'container settlement retires work atomically');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_work WHERE operation_id='00000000-0000-4000-8000-00000000ee45'),0,'container rejection cannot seed copy work');
UPDATE internal.observation_history_rollout SET publication_container_settlement_enabled=FALSE;
SELECT extensions.is(pg_temp.finish_container(work=>gen_random_uuid())->>'reason','public_container_rejected','lost response replays before live token and closed gate');
SELECT extensions.throws_ok($$SELECT pg_temp.finish_container(att=>jsonb_set(pg_temp.container_attestation(),'{source}',(SELECT sources->1 FROM internal.observation_publication_intents WHERE operation_id='00000000-0000-4000-8000-00000000ee45')))$$,'22023','analysis_history_operation_conflict','replay cannot replace rejected source with another original sibling');
SELECT extensions.is(pg_temp.status('00000000-0000-4000-8000-00000000ee45'),'needs_action','owner status contains only bounded needs action');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_container_attestations SET attestation='{}'$$,'22023','analysis_history_evidence_immutable','attestation cannot be rewritten');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT public.finalize_publication_container_rejection(NULL,NULL,NULL,NULL,NULL)','42501','permission denied for function finalize_publication_container_rejection','authenticated cannot submit attestations');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok('SELECT public.finalize_publication_container_rejection(NULL,NULL,NULL,NULL,NULL)','42501','permission denied for function finalize_publication_container_rejection','anonymous cannot submit attestations');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_container_attestations),0,'deletion cascades private attestations');
SELECT extensions.throws_ok('SELECT pg_temp.finish_container()','P0002','analysis_history_not_found','deletion precedes attestation replay');
ROLLBACK TO container_trial;

UPDATE outcomes_work SET attempt=public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token,'00000000-0000-4000-8000-00000000ee31') WHERE operation<>'00000000-0000-4000-8000-00000000ee45';
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":false}'::JSONB,'reserved attempt blocks settlement without refund');
SELECT pg_temp.advance(operation,'prepare') FROM outcomes_work WHERE operation IN ('00000000-0000-4000-8000-00000000ee41','00000000-0000-4000-8000-00000000ee42','00000000-0000-4000-8000-00000000ee43');
SELECT pg_temp.advance(operation,'dispatch') FROM outcomes_work WHERE operation IN ('00000000-0000-4000-8000-00000000ee41','00000000-0000-4000-8000-00000000ee42','00000000-0000-4000-8000-00000000ee43');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":false}'::JSONB,'dispatched attempt retains completion ownership');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee41','complete');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee42','complete','rejected');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee44','retire');
ALTER TABLE internal.observation_photo_moderation_attempts DISABLE TRIGGER guard_publication_moderation_attempt_update;
UPDATE internal.observation_photo_moderation_attempts SET dispatch_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE operation_id='00000000-0000-4000-8000-00000000ee43';
ALTER TABLE internal.observation_photo_moderation_attempts ENABLE TRIGGER guard_publication_moderation_attempt_update;
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee43','retire');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":false}'::JSONB,'one approved photo cannot approve an unattempted cohort');
SAVEPOINT missing_proof;
DELETE FROM internal.observation_photo_execution_proofs WHERE attempt_id=(SELECT (attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41');
SELECT extensions.throws_ok($$SELECT pg_temp.settle('00000000-0000-4000-8000-00000000ee41')$$,'22023','analysis_history_operation_conflict','approval without its durable proof/result cannot settle');
ROLLBACK TO missing_proof;
ALTER TABLE outcomes_work ADD COLUMN first_attempt JSONB;
UPDATE outcomes_work SET first_attempt=attempt;
UPDATE outcomes_work SET attempt=public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token,'00000000-0000-4000-8000-00000000ee32') WHERE operation='00000000-0000-4000-8000-00000000ee41';
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":false}'::JSONB,'second reserved photo blocks completion');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee41','prepare');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee41','dispatch');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee41','complete');
-- Gate closure cannot strand durable terminal provider decisions.
UPDATE internal.observation_history_rollout SET publication_execution_enabled=FALSE,publication_moderation_enabled=FALSE;
GRANT SELECT ON outcomes_work TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.settle(UUID),pg_temp.status(UUID) TO service_role;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee41'),'{"finalized":true,"status":"photos_approved","reason":null}'::JSONB,'actual service settles exact complete approval after gate closure');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee42'),'{"finalized":true,"status":"needs_action","reason":"photo_rejected"}'::JSONB,'rejection needs action');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee43')->>'reason','unknown_execution','unknown stays terminal and charged');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee44')->>'reason','cancelled','proven cancellation does not automatically retry');
SELECT extensions.is(pg_temp.status('00000000-0000-4000-8000-00000000ee41'),'photos_approved','status distinguishes provider approval from publication');
SELECT extensions.is(pg_temp.status('00000000-0000-4000-8000-00000000ee42'),'needs_action','status reports durable failure');
SELECT extensions.throws_ok('SELECT * FROM internal.observation_publication_moderation_outcomes','42501','permission denied for table observation_publication_moderation_outcomes','service cannot directly read private attempts');
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_work WHERE operation_id IN (SELECT operation FROM outcomes_work)),1,'only unattempted work remains discoverable');
SELECT extensions.is((SELECT attempt_ids FROM internal.observation_publication_moderation_outcomes WHERE operation_id='00000000-0000-4000-8000-00000000ee41'),ARRAY[(SELECT (first_attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41'),(SELECT (attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41')],'outcome pins original ordered attempt');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (attempt#>>'{quota,reservation_id}')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee43')),'failed','settlement does not refund unknown dispatch');
SELECT extensions.is(public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',NULL),'{"finalized":true,"status":"photos_approved","reason":null}'::JSONB,'lost response recovers without live work');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_moderation_outcomes SET reason='cancelled',state='needs_action' WHERE operation_id='00000000-0000-4000-8000-00000000ee41'$$,'22023','analysis_history_evidence_immutable','outcome immutable');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.finalize_publication_photo_moderation(NULL,NULL,NULL,NULL)$$,'42501','permission denied for function finalize_publication_photo_moderation','actual client cannot nominate settlement');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.finalize_publication_photo_moderation(NULL,NULL,NULL,NULL)$$,'42501','permission denied for function finalize_publication_photo_moderation','actual anonymous caller denied');
RESET ROLE;
UPDATE internal.observation_history_rollout SET publication_execution_enabled=TRUE,publication_moderation_enabled=TRUE;
SELECT extensions.is(public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41'),'{"claimed":false}'::JSONB,'settled approval cannot be reclaimed for moderation');
SELECT extensions.throws_ok($$SELECT internal.admit_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee44','00000000-0000-4000-8000-00000000ee31',(SELECT (attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee44'),repeat('b',64))$$,'22023','analysis_history_operation_conflict','even private explicit successor cannot reopen settled cancellation');
-- Explicit predecessor chains survive quota reservation pruning. Billing
-- counters are not causal order, including a lower new count after pruning.
UPDATE outcomes_work SET attempt=public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token,'00000000-0000-4000-8000-00000000ee31') WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','retire');
UPDATE outcomes_work SET attempt=internal.admit_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,'00000000-0000-4000-8000-00000000ee31',(attempt->>'attempt_id')::UUID,repeat('b',64)) WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT extensions.is((SELECT (attempt#>>'{quota,attempt_count}')::INT FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45'),2,'predecessor uses second quota attempt');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','retire');
DELETE FROM internal.ai_quota_reservations WHERE id=(SELECT (attempt#>>'{quota,reservation_id}')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45');
UPDATE outcomes_work SET attempt=internal.admit_publication_photo_moderation('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,'00000000-0000-4000-8000-00000000ee31',(attempt->>'attempt_id')::UUID,repeat('b',64)) WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT extensions.is((SELECT (attempt#>>'{quota,attempt_count}')::INT FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45'),1,'new reservation restarts quota counter');
SELECT extensions.is(public.read_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token)#>>'{0,attempt,attempt_id}',attempt->>'attempt_id','recovery selects causal successor instead of higher billing counter') FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT extensions.is(public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token,'00000000-0000-4000-8000-00000000ee31')->>'attempt_id',attempt->>'attempt_id','admission recovers same causal leaf') FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','prepare');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','dispatch');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','complete');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee45'),'{"finalized":false}'::JSONB,'older cancelled predecessors cannot poison successful successor');
UPDATE outcomes_work SET first_attempt=attempt WHERE operation='00000000-0000-4000-8000-00000000ee45';
UPDATE outcomes_work SET attempt=public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',operation,token,'00000000-0000-4000-8000-00000000ee32') WHERE operation='00000000-0000-4000-8000-00000000ee45';
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','prepare');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','dispatch');
SELECT pg_temp.advance('00000000-0000-4000-8000-00000000ee45','complete');
SELECT extensions.is(pg_temp.settle('00000000-0000-4000-8000-00000000ee45')->>'status','photos_approved','causal successor plus complete cohort settles approved');
-- Separate copy recovery is seeded only by complete approval, never refusal.
SELECT extensions.ok(NOT (SELECT publication_copy_execution_enabled FROM internal.observation_history_rollout),'copy execution defaults closed');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_work),2,'only the two approved cohorts seed copy recovery');
SELECT extensions.throws_ok('SELECT public.list_publication_copy_work()','55000','analysis_history_unavailable','closed copy gate prevents discovery');
CREATE FUNCTION pg_temp.copy_claim(op UUID DEFAULT '00000000-0000-4000-8000-00000000ee41') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.claim_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op);
$$;
CREATE FUNCTION pg_temp.copy_read(token UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.read_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',token);
$$;
CREATE FUNCTION pg_temp.copy_release(token UUID) RETURNS VOID LANGUAGE SQL AS $$
 SELECT public.release_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',token);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.copy_claim(UUID),pg_temp.copy_read(UUID),pg_temp.copy_release(UUID) TO service_role,authenticated,anon;
UPDATE internal.observation_history_rollout SET publication_copy_execution_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.list_publication_copy_work()),2,'service discovers copy recovery separately');
SELECT extensions.throws_ok('SELECT * FROM internal.observation_publication_copy_work','42501','permission denied for table observation_publication_copy_work','service has no direct work table access');
SELECT extensions.throws_ok($$SELECT pg_temp.copy_claim('00000000-0000-4000-8000-00000000ee42')$$,'22023','analysis_history_operation_conflict','refused cohort cannot claim');
CREATE TEMP TABLE copy_claim AS SELECT pg_temp.copy_claim() AS receipt;
SELECT extensions.is((SELECT receipt->>'claimed' FROM copy_claim),'true','service claims approved cohort');
SELECT extensions.is(pg_temp.copy_claim(),'{"claimed":false}'::JSONB,'duplicate cannot obtain token');
SELECT extensions.is((SELECT jsonb_array_length(receipt->'cohort') FROM copy_claim),2,'claim contains the entire ordered cohort');
SELECT extensions.ok((SELECT (receipt->'cohort'->0)-ARRAY['attempt_id','source']='{}' FROM copy_claim),'no provider lease or note in copy context');
SELECT extensions.is(pg_temp.copy_read((SELECT (receipt->>'work_token')::UUID FROM copy_claim)),(SELECT receipt->'cohort' FROM copy_claim),'live copy token recovers immutable cohort');
RESET ROLE;
SELECT extensions.throws_ok($$SELECT pg_temp.copy_read((SELECT token FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41'))$$,'22023','analysis_history_operation_conflict','moderation token cannot authorize copy recovery');
SELECT extensions.is((SELECT receipt#>>'{cohort,0,attempt_id}' FROM copy_claim),(SELECT first_attempt->>'attempt_id' FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41'),'first approved causal leaf remains first');
SELECT extensions.is((SELECT receipt#>>'{cohort,1,attempt_id}' FROM copy_claim),(SELECT attempt->>'attempt_id' FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41'),'second approved causal leaf remains second');
-- Corrupt only a test outcome to prove the facade fails closed on order drift.
ALTER TABLE internal.observation_publication_moderation_outcomes DISABLE TRIGGER reject_publication_moderation_outcome_update;
UPDATE internal.observation_publication_moderation_outcomes SET attempt_ids=ARRAY[attempt_ids[2],attempt_ids[1]] WHERE operation_id='00000000-0000-4000-8000-00000000ee41';
SELECT extensions.throws_ok($$SELECT pg_temp.copy_read((SELECT (receipt->>'work_token')::UUID FROM copy_claim))$$,'22023','analysis_history_operation_conflict','reordered outcome cannot authorize recovery');
UPDATE internal.observation_publication_moderation_outcomes SET attempt_ids=ARRAY[attempt_ids[2],attempt_ids[1]] WHERE operation_id='00000000-0000-4000-8000-00000000ee41';
ALTER TABLE internal.observation_publication_moderation_outcomes ENABLE TRIGGER reject_publication_moderation_outcome_update;
UPDATE internal.observation_history_rollout SET publication_copy_execution_enabled=FALSE;
SELECT extensions.lives_ok($$SELECT pg_temp.copy_read((SELECT (receipt->>'work_token')::UUID FROM copy_claim))$$,'gate closure preserves original recovery only');
SELECT extensions.lives_ok($$SELECT pg_temp.copy_release((SELECT (receipt->>'work_token')::UUID FROM copy_claim))$$,'gate closure permits scoped release');
UPDATE internal.observation_history_rollout SET publication_copy_execution_enabled=TRUE;
SELECT extensions.is(pg_temp.copy_claim(),'{"claimed":false}'::JSONB,'release backoff cannot be bypassed');
UPDATE internal.observation_publication_copy_work SET recover_after=clock_timestamp()-INTERVAL '1 second';
CREATE TEMP TABLE copy_reclaim AS SELECT pg_temp.copy_claim() AS receipt;
SELECT extensions.throws_ok($$SELECT pg_temp.copy_release((SELECT (receipt->>'work_token')::UUID FROM copy_claim))$$,'22023','analysis_history_operation_conflict','stale worker cannot release successor');
UPDATE internal.observation_publication_copy_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE operation_id='00000000-0000-4000-8000-00000000ee41';
SELECT extensions.throws_ok($$SELECT pg_temp.copy_read((SELECT (receipt->>'work_token')::UUID FROM copy_reclaim))$$,'22023','analysis_history_operation_conflict','expired work cannot read execution context');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects),0,'copy recovery allocates no public objects');
SELECT extensions.throws_ok($$SELECT public.claim_publication_copy_work('00000000-0000-4000-8000-00000000ee02','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41')$$,'P0002','analysis_history_not_found','cross owner copy claim denied');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.copy_claim()','42501','permission denied for function claim_publication_copy_work','actual authenticated role denied');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok('SELECT pg_temp.copy_claim()','42501','permission denied for function claim_publication_copy_work','actual anonymous role denied');
RESET ROLE;
-- Atomic no-note cohort reservation under the reclaimed copy token.
UPDATE internal.observation_publication_copy_work SET work_expires_at=clock_timestamp()+INTERVAL '120 seconds' WHERE operation_id='00000000-0000-4000-8000-00000000ee41';
CREATE FUNCTION pg_temp.reserve_cohort() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.reserve_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',(SELECT (receipt->>'work_token')::UUID FROM copy_reclaim));
$$;
CREATE FUNCTION pg_temp.read_cohort() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.read_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41');
$$;
CREATE FUNCTION pg_temp.abandon_cohort() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.abandon_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',(SELECT (receipt->>'work_token')::UUID FROM copy_reclaim));
$$;
GRANT SELECT ON copy_reclaim TO service_role,authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.reserve_cohort(),pg_temp.read_cohort(),pg_temp.abandon_cohort() TO service_role,authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_cohort()','55000','analysis_history_unavailable','copy gate must also authorize reservation');
SELECT extensions.ok(NOT (SELECT publication_copy_reservation_enabled FROM internal.observation_history_rollout),'reservation has an independent closed gate');
UPDATE internal.observation_history_rollout SET publication_copy_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_cohort()','55000','analysis_history_unavailable','enabling old copy gates cannot enable allocation');
UPDATE internal.observation_history_rollout SET publication_copy_reservation_enabled=TRUE;
-- Force a failure on the second allocation: both inserted objects must roll back.
CREATE FUNCTION pg_temp.reject_second_copy() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF NEW.source->>'media_id'='00000000-0000-4000-8000-00000000ee32' THEN RAISE EXCEPTION 'synthetic_second_copy_failure'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER test_second_copy BEFORE INSERT ON internal.observation_photo_copies FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_second_copy();
SELECT extensions.throws_ok('SELECT pg_temp.reserve_cohort()','P0001','synthetic_second_copy_failure','second member failure aborts the whole reservation');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects),0,'failed cohort leaves no partial object registry');
DROP TRIGGER test_second_copy ON internal.observation_photo_copies;
CREATE FUNCTION pg_temp.legacy_partial_reserve() RETURNS JSONB LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM internal.reserve_publication_photo_copy('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',(SELECT (first_attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation='00000000-0000-4000-8000-00000000ee41'));
 RETURN pg_temp.reserve_cohort();
END;
$$;
SELECT extensions.throws_ok('SELECT pg_temp.legacy_partial_reserve()','22023','analysis_history_operation_conflict','legacy partial reservation cannot be silently adopted or renewed');
SET LOCAL ROLE service_role;
CREATE TEMP TABLE cohort_reservation AS SELECT pg_temp.reserve_cohort() AS receipt;
SELECT extensions.is(jsonb_array_length((SELECT receipt->'copies' FROM cohort_reservation)),2,'actual service reserves the complete ordered cohort');
SELECT extensions.is(pg_temp.reserve_cohort(),(SELECT receipt FROM cohort_reservation),'lost response recovers same keys leases and expiry');
SELECT extensions.is(pg_temp.read_cohort()->'reservation',(SELECT receipt FROM cohort_reservation),'historical read returns original reservation');
SELECT extensions.is(pg_temp.read_cohort()->'publication','null'::JSONB,'reservation is not a publication');
SELECT extensions.throws_ok('SELECT * FROM internal.observation_publication_copy_cohorts','42501','permission denied for table observation_publication_copy_cohorts','no direct service access to cohort receipts');
RESET ROLE;
SELECT extensions.is((SELECT count(DISTINCT expires_at)::INT FROM internal.observation_photo_copies),1,'all copies share one expiry');
SELECT extensions.ok((SELECT bool_and(p.expires_at=r.available_at) FROM internal.observation_photo_copies p JOIN internal.publication_photo_objects r USING(object_id)),'registry erasure deadlines match the original common expiry');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_copy_cohorts SET expires_at=expires_at+INTERVAL '1 minute'$$,'22023','analysis_history_evidence_immutable','cohort deadline immutable');
CREATE FUNCTION pg_temp.complete_cohort_member(index INT) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.complete_publication_copy_cohort_photo('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',(SELECT (receipt->>'work_token')::UUID FROM copy_reclaim),
 (receipt->'copies'->index->>'attempt_id')::UUID,(receipt->'copies'->index->>'object_id')::UUID,(receipt->'copies'->index->>'lease_token')::UUID) FROM cohort_reservation;
$$;
SELECT extensions.ok(pg_temp.complete_cohort_member(0)->>'ready_at' IS NOT NULL,'exact first member completes');
SELECT extensions.is(pg_temp.complete_cohort_member(0),pg_temp.complete_cohort_member(0),'identical completion is recoverable');
SELECT extensions.is(pg_temp.read_cohort()#>>'{reservation,expires_at}',(SELECT receipt->>'expires_at' FROM cohort_reservation),'readiness does not extend expiry');
SELECT extensions.throws_ok($$SELECT public.complete_publication_copy_cohort_photo('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',(SELECT (receipt->>'work_token')::UUID FROM copy_reclaim),(SELECT (receipt#>>'{copies,1,attempt_id}')::UUID FROM cohort_reservation),(SELECT (receipt#>>'{copies,0,object_id}')::UUID FROM cohort_reservation),(SELECT (receipt#>>'{copies,0,lease_token}')::UUID FROM cohort_reservation))$$,'22023','analysis_history_operation_conflict','substituted member identity is denied');
CREATE TEMP TABLE note_copy_claim AS SELECT pg_temp.copy_claim('00000000-0000-4000-8000-00000000ee45') AS receipt;
SELECT extensions.throws_ok($$SELECT public.reserve_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM note_copy_claim))$$,'22023','analysis_history_operation_conflict','public note needs its own approval before copying');
CREATE FUNCTION pg_temp.finish_copy(op UUID DEFAULT '00000000-0000-4000-8000-00000000ee41', token UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.finalize_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op,
 COALESCE(token,CASE WHEN op='00000000-0000-4000-8000-00000000ee41' THEN (SELECT (receipt->>'work_token')::UUID FROM copy_reclaim) ELSE (SELECT (receipt->>'work_token')::UUID FROM note_copy_claim) END));
$$;
SELECT extensions.ok(NOT (SELECT publication_copy_settlement_enabled FROM internal.observation_history_rollout),'copy settlement gate defaults closed');
SELECT extensions.throws_ok('SELECT pg_temp.finish_copy()','55000','analysis_history_unavailable','copy execution gates do not enable settlement');
UPDATE internal.observation_history_rollout SET publication_copy_settlement_enabled=TRUE;
SELECT extensions.is(pg_temp.finish_copy(),'{"finalized":false}'::JSONB,'valid unexpired copies have no terminal failure');
CREATE FUNCTION pg_temp.copy_outcome_trial(kind TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE op UUID:='00000000-0000-4000-8000-00000000ee41'; result JSONB; saved JSONB; past TIMESTAMPTZ:=clock_timestamp()-INTERVAL '1 second';
BEGIN
 BEGIN
  IF kind IN ('note','legacy_copy') THEN op:='00000000-0000-4000-8000-00000000ee45';
  ELSE
   ALTER TABLE internal.observation_photo_copies DISABLE TRIGGER guard_publication_photo_copy;
   UPDATE internal.observation_photo_copies SET expires_at=past;
   ALTER TABLE internal.observation_photo_copies ENABLE TRIGGER guard_publication_photo_copy;
   ALTER TABLE internal.observation_publication_copy_cohorts DISABLE TRIGGER reject_publication_copy_cohort_update;
   UPDATE internal.observation_publication_copy_cohorts SET expires_at=past,
    copies=(SELECT jsonb_agg(value||jsonb_build_object('expires_at',past) ORDER BY ordinality) FROM jsonb_array_elements(copies) WITH ORDINALITY);
   ALTER TABLE internal.observation_publication_copy_cohorts ENABLE TRIGGER reject_publication_copy_cohort_update;
  END IF;
  IF kind='legacy_copy' THEN
   PERFORM internal.reserve_publication_photo_copy('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',(SELECT (first_attempt->>'attempt_id')::UUID FROM outcomes_work WHERE operation=op));
   result:=pg_temp.finish_copy(op);
   RAISE EXCEPTION 'synthetic_trial_rollback' USING ERRCODE='Z0001';
  END IF;
  IF kind='claimed_expiry' THEN
   UPDATE internal.publication_photo_objects SET claim_token='00000000-0000-4000-8000-00000000ef01',claim_expires_at=clock_timestamp()+INTERVAL '1 minute';
  END IF;
  saved:=pg_temp.finish_copy(op);
  IF kind='claimed_expiry' THEN
   result:=jsonb_build_object('reason',saved->>'reason','claims_preserved',(SELECT bool_and(claim_token='00000000-0000-4000-8000-00000000ef01' AND claim_expires_at>clock_timestamp()) FROM internal.publication_photo_objects));
   RAISE EXCEPTION 'synthetic_trial_rollback' USING ERRCODE='Z0001';
  END IF;
  result:=jsonb_build_object('status',saved->>'status','reason',saved->>'reason',
   'retired',NOT EXISTS(SELECT 1 FROM internal.observation_publication_copy_work WHERE operation_id=op),
   'approval_preserved',(SELECT state='photos_approved' FROM internal.observation_publication_moderation_outcomes WHERE operation_id=op),
   'owner_status',public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op)->>'status',
   'private_shape',(public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',op)-ARRAY['schema_version','operation_id','observation_id','analysis_id','status'])='{}'::JSONB,
   'object_count',jsonb_array_length(saved->'object_ids'),
   'cleanup_ready',kind='note' OR (SELECT bool_and(revoked_at IS NOT NULL AND available_at<=clock_timestamp()) FROM internal.publication_photo_objects));
  UPDATE internal.observation_history_rollout SET publication_copy_settlement_enabled=FALSE;
  result:=result||jsonb_build_object('replay',saved=pg_temp.finish_copy(op,gen_random_uuid()),
   'cannot_reclaim',pg_temp.copy_claim(op)='{"claimed":false}'::JSONB);
  RAISE EXCEPTION 'synthetic_trial_rollback' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN result;
 END;
END;
$$;
SELECT extensions.is(pg_temp.copy_outcome_trial('legacy_copy'),'{"finalized":false}'::JSONB,'note with a legacy copy remains recoverable');
SELECT extensions.is(pg_temp.copy_outcome_trial('claimed_expiry'),'{"reason":"staging_expired","claims_preserved":true}'::JSONB,'expiry finalization preserves existing erasure claim ownership');
SELECT extensions.is(pg_temp.copy_outcome_trial('note'),'{"status":"needs_action","reason":"note_requires_text_moderation","retired":true,"approval_preserved":true,"owner_status":"needs_action","private_shape":true,"object_count":0,"cleanup_ready":true,"replay":true,"cannot_reclaim":true}'::JSONB,'note outcome is separate immutable authority and prevents repeated claims');
SELECT extensions.is(pg_temp.copy_outcome_trial('expiry'),'{"status":"needs_action","reason":"staging_expired","retired":true,"approval_preserved":true,"owner_status":"needs_action","private_shape":true,"object_count":2,"cleanup_ready":true,"replay":true,"cannot_reclaim":true}'::JSONB,'expired cohort retires work and queues all exact siblings');
GRANT SELECT ON copy_reclaim,note_copy_claim TO service_role,authenticated,anon;
GRANT EXECUTE ON FUNCTION pg_temp.finish_copy(UUID,UUID) TO service_role,authenticated,anon;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.finish_copy(),'{"finalized":false}'::JSONB,'actual service can inspect settlement eligibility');
SELECT extensions.throws_ok('SELECT * FROM internal.observation_publication_copy_outcomes','42501','permission denied for table observation_publication_copy_outcomes','outcomes have no direct service grant');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.finish_copy()','42501','permission denied for function finalize_publication_copy_work','authenticated cannot choose settlement owner');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok('SELECT pg_temp.finish_copy()','42501','permission denied for function finalize_publication_copy_work','anonymous cannot settle copy work');
RESET ROLE;
SELECT public.release_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM note_copy_claim));
UPDATE internal.observation_publication_copy_work SET recover_after=clock_timestamp()-INTERVAL '1 second' WHERE operation_id='00000000-0000-4000-8000-00000000ee45';
-- Trials isolate publication side effects so later denial/erasure fixtures remain unchanged.
CREATE FUNCTION pg_temp.bind_cohort() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.bind_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',(SELECT (receipt->>'work_token')::UUID FROM copy_reclaim));
$$;
SELECT extensions.ok(NOT (SELECT publication_copy_binding_enabled FROM internal.observation_history_rollout),'binding has a separate closed gate');
SELECT extensions.throws_ok('SELECT pg_temp.bind_cohort()','55000','analysis_history_unavailable','old copy gates do not activate binding');
UPDATE internal.observation_history_rollout SET publication_copy_binding_enabled=TRUE,publication_binding_enabled=TRUE,community_admission_enabled=TRUE,community_authority_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.bind_cohort()','55000','analysis_history_evidence_unavailable','one ready member cannot publish an incomplete cohort');
CREATE FUNCTION pg_temp.mismatch_bound_cohort() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN NEW.object_ids:=ARRAY[NEW.object_ids[2],NEW.object_ids[1]]; RETURN NEW; END;
$$;
CREATE FUNCTION pg_temp.binding_trial(mode TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE result JSONB; receipt JSONB; replay JSONB;
BEGIN
 BEGIN
  PERFORM pg_temp.complete_cohort_member(1);
  IF mode='stale' THEN
   UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000ee11';
  ELSIF mode='revoked' THEN
   UPDATE internal.publication_photo_objects SET revoked_at=clock_timestamp();
  ELSIF mode='mismatch' THEN
   CREATE TRIGGER synthetic_wrong_binding BEFORE INSERT ON internal.observation_photo_publications FOR EACH ROW EXECUTE FUNCTION pg_temp.mismatch_bound_cohort();
  ELSIF mode='expired_work' THEN
   UPDATE internal.observation_publication_copy_work SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE work_token IS NOT NULL;
  END IF;
  receipt:=pg_temp.bind_cohort();
  IF mode='container_publication' THEN
   result:=pg_temp.finish_container('00000000-0000-4000-8000-00000000ee41');
   RAISE EXCEPTION 'rollback_synthetic_binding' USING ERRCODE='Z0001';
  END IF;
  IF mode='legacy_publication' THEN
   DELETE FROM internal.observation_publication_copy_cohorts WHERE operation_id='00000000-0000-4000-8000-00000000ee41';
   result:=pg_temp.finish_copy();
   RAISE EXCEPTION 'rollback_synthetic_binding' USING ERRCODE='Z0001';
  END IF;
  result:=jsonb_build_object('status',receipt->>'status',
   'exact',(SELECT object_ids=(SELECT array_agg((value->>'object_id')::UUID ORDER BY ordinality) FROM jsonb_array_elements((SELECT c.receipt->'copies' FROM cohort_reservation c)) WITH ORDINALITY) FROM internal.observation_photo_publications WHERE operation_id='00000000-0000-4000-8000-00000000ee41'),
   'retired',NOT EXISTS(SELECT 1 FROM internal.observation_publication_copy_work WHERE operation_id='00000000-0000-4000-8000-00000000ee41'));
  UPDATE internal.observation_history_rollout SET publication_copy_binding_enabled=FALSE,publication_copy_reservation_enabled=FALSE,publication_binding_enabled=FALSE;
  UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000ee11';
  IF mode='missing_receipt' THEN DELETE FROM internal.observation_publication_copy_cohorts WHERE operation_id='00000000-0000-4000-8000-00000000ee41'; END IF;
  replay:=public.bind_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee41',NULL);
  result:=result||jsonb_build_object('publication_wins',pg_temp.finish_copy()='{"finalized":true,"status":"admitted","reason":null,"object_ids":[]}'::JSONB,'replayed',receipt=replay,'cleanup_denied',pg_temp.abandon_cohort()='{"abandoned":false}'::JSONB);
  RAISE EXCEPTION 'rollback_synthetic_binding' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN result;
 END;
END;
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.binding_trial('stale')$$,'40001','analysis_history_revision_conflict','binding rejects a changed authority revision');
SELECT extensions.throws_ok($$SELECT pg_temp.binding_trial('revoked')$$,'22023','analysis_history_operation_conflict','binding rejects a revoked staging object');
SELECT extensions.throws_ok($$SELECT pg_temp.binding_trial('expired_work')$$,'22023','analysis_history_operation_conflict','new binding requires a live copy token');
CREATE TEMP TABLE before_binding_trial AS SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000ee11';
SELECT extensions.throws_ok($$SELECT pg_temp.binding_trial('mismatch')$$,'22023','analysis_history_operation_conflict','post-write ordered mismatch aborts the complete transaction');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_admissions),0,'mismatched writer leaves no admission');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_bindings),0,'mismatched writer leaves no bindings');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects WHERE bound_at IS NOT NULL),0,'mismatched writer leaves no bound registry state');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts WHERE scan_id='00000000-0000-4000-8000-00000000ee11'),0,'mismatched writer leaves no public post');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_community_requests WHERE scan_id='00000000-0000-4000-8000-00000000ee11'),0,'mismatched writer leaves no community request');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_publication_copy_work WHERE operation_id='00000000-0000-4000-8000-00000000ee41'),'mismatched writer preserves recovery work');
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000ee11'),(SELECT state_revision FROM before_binding_trial),'mismatched writer preserves observation authority revision');
SELECT extensions.throws_ok($$SELECT pg_temp.binding_trial('missing_receipt')$$,'22023','analysis_history_operation_conflict','historical publication cannot substitute for missing immutable reservation');
SELECT extensions.is(pg_temp.binding_trial('container_publication'),'{"finalized":true,"status":"admitted","reason":null}'::JSONB,'valid committed publication wins over container rejection without an attestation');
SELECT extensions.is(pg_temp.binding_trial('legacy_publication'),'{"finalized":true,"status":"admitted","reason":null,"object_ids":[]}'::JSONB,'validated legacy publication wins without creating new copy authority');
SELECT extensions.is(pg_temp.binding_trial('success'),'{"status":"admitted","exact":true,"retired":true,"replayed":true,"cleanup_denied":true,"publication_wins":true}'::JSONB,'exact ordered binding retires work and replays after authority and gate closure without cleanup');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_publications),0,'synthetic trial rolls publication back completely');
SELECT extensions.throws_ok($$SELECT public.bind_publication_copy_cohort('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM note_copy_claim))$$,'22023','analysis_history_operation_conflict','unapproved note cannot bind');
GRANT SELECT ON copy_reclaim TO anon;
GRANT EXECUTE ON FUNCTION pg_temp.bind_cohort() TO authenticated,anon;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.bind_cohort()','42501','permission denied for function bind_publication_copy_cohort','actual authenticated caller cannot publish through service facade');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok('SELECT pg_temp.bind_cohort()','42501','permission denied for function bind_publication_copy_cohort','actual anonymous caller cannot publish through service facade');
RESET ROLE;
UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000ee11';
SELECT extensions.is(pg_temp.finish_copy(),'{"finalized":false}'::JSONB,'authority loss alone cannot create a terminal outcome');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_cohort()','40001','analysis_history_revision_conflict','stale revision cannot reuse a reservation for I/O');
SELECT extensions.throws_ok('SELECT pg_temp.complete_cohort_member(1)','40001','analysis_history_revision_conflict','authority changes block readiness after external writes');
SELECT extensions.ok(pg_temp.read_cohort()->'reservation' IS NOT NULL,'authority loss still permits historical cleanup recovery');
UPDATE internal.observation_history_rollout SET publication_copy_reservation_enabled=FALSE;
SELECT extensions.is(pg_temp.abandon_cohort()->>'abandoned','true','authority loss and gate closure can abandon the entire unbound cohort');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects WHERE revoked_at IS NOT NULL AND available_at<=clock_timestamp()),2,'all siblings become due for targeted erasure');
SELECT extensions.is(pg_temp.abandon_cohort()->>'abandoned','true','abandon replay does not allocate or extend anything');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_cohort()','42501','permission denied for function reserve_publication_copy_cohort','actual client cannot nominate reservation owner');
SELECT extensions.throws_ok('SELECT pg_temp.read_cohort()','42501','permission denied for function read_publication_copy_cohort','actual client cannot read private cohort receipts');
RESET ROLE;
INSERT INTO internal.observation_photo_publications(operation_id,object_ids,receipt) VALUES('00000000-0000-4000-8000-00000000ee41',ARRAY[gen_random_uuid()],'{"status":"admitted"}');
SELECT extensions.is(pg_temp.copy_claim(),'{"claimed":false}'::JSONB,'durable binding retires copy recovery');
SELECT extensions.is(pg_temp.read_cohort()->'publication','{"status":"admitted"}'::JSONB,'lost binding response recovers despite retired work');
SELECT extensions.is(pg_temp.abandon_cohort(),'{"abandoned":false}'::JSONB,'historical publication wins over late abandonment');
CREATE TEMP TABLE live_deleted_copy AS SELECT pg_temp.copy_claim('00000000-0000-4000-8000-00000000ee45') AS receipt;
SELECT extensions.is((SELECT receipt->>'claimed' FROM live_deleted_copy),'true','unbound operation holds a live lease before deletion');
SELECT extensions.is(pg_temp.finish_copy('00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM live_deleted_copy))->>'reason','note_requires_text_moderation','live note work settles before deletion');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_copy_outcomes SET reason='staging_expired'$$,'22023','analysis_history_evidence_immutable','copy outcomes cannot be rewritten');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_moderation_outcomes),0,'deletion removes outcomes');
SELECT extensions.throws_ok($$SELECT pg_temp.settle('00000000-0000-4000-8000-00000000ee41')$$,'P0002','analysis_history_not_found','deletion wins over historical replay');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_work),0,'deletion cascades all copy work');
SELECT extensions.throws_ok('SELECT pg_temp.copy_claim()','P0002','analysis_history_not_found','deletion defeats copy recovery');
SELECT extensions.throws_ok($$SELECT public.read_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM live_deleted_copy))$$,'P0002','analysis_history_not_found','deletion defeats active copy read');
SELECT extensions.throws_ok($$SELECT public.release_publication_copy_work('00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11','00000000-0000-4000-8000-00000000ee45',(SELECT (receipt->>'work_token')::UUID FROM live_deleted_copy))$$,'P0002','analysis_history_not_found','deletion defeats active copy release');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_cohorts),0,'deletion removes private cohort receipts');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_objects),2,'registry obligations survive private history deletion');
SELECT extensions.throws_ok('SELECT pg_temp.read_cohort()','P0002','analysis_history_not_found','deletion wins over cohort and publication recovery');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_outcomes),0,'deletion cascades private copy outcomes');
SELECT extensions.throws_ok($$SELECT pg_temp.finish_copy('00000000-0000-4000-8000-00000000ee45')$$,'P0002','analysis_history_not_found','deletion wins over terminal outcome replay');

-- Genuine immutable HEIC source fixtures, with no edits to saved evidence.
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,publication_intent_enabled=TRUE,publication_operation_enabled=TRUE,publication_execution_enabled=TRUE,publication_moderation_enabled=TRUE;
CREATE OR REPLACE FUNCTION pg_temp.protected_input(observation UUID,analysis UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','google_gemini','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/heic','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','image','media_id','00000000-0000-4000-8000-00000000ee32','content_type','image/heic','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
$$;
CREATE OR REPLACE FUNCTION pg_temp.protected_ready(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE receipt JSONB;
BEGIN
 receipt:=internal.reserve_observation_evidence(owner_id,observation,analysis,media,'image/heic',3,repeat('a',64));
 PERFORM internal.complete_observation_evidence(owner_id,observation,analysis,media,(receipt->>'object_id')::UUID);
 RETURN (receipt->>'object_id')::UUID;
END;
$$;

SELECT pg_temp.seed_photo_moderation('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef21','00000000-0000-4000-8000-00000000ef31','00000000-0000-4000-8000-00000000ef41');
SELECT public.admit_owned_observation_publication('00000000-0000-4000-8000-00000000ef01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef21','00000000-0000-4000-8000-00000000ef41','00000000-0000-4000-8000-00000000ef31'),repeat('c',64));
CREATE TEMP TABLE source_work AS SELECT public.claim_observation_publication_work('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef41') AS receipt;
CREATE FUNCTION pg_temp.finish_source(token UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef41',COALESCE(token,(SELECT (receipt->>'work_token')::UUID FROM source_work)));
$$;
SELECT extensions.is((SELECT publication_source_settlement_enabled FROM internal.observation_history_rollout),FALSE,'source settlement ships disabled');
SELECT extensions.is(pg_temp.finish_source(),'{"finalized":false}'::JSONB,'existing gates cannot settle unsupported sources');
UPDATE internal.observation_history_rollout SET publication_source_settlement_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.finish_source(gen_random_uuid())','22023','analysis_history_operation_conflict','unsupported source requires original live work');
SAVEPOINT existing_provider;
SELECT public.admit_publication_moderation_work('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef41',(SELECT (receipt->>'work_token')::UUID FROM source_work),'00000000-0000-4000-8000-00000000ef31');
SELECT extensions.is(pg_temp.finish_source(),'{"finalized":false}'::JSONB,'existing provider reservation keeps original recovery ownership');
ROLLBACK TO existing_provider;
GRANT SELECT ON source_work TO service_role;
GRANT EXECUTE ON FUNCTION pg_temp.finish_source(UUID) TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_temp.finish_source(),'{"finalized":true,"status":"needs_action","reason":"unsupported_source_type"}'::JSONB,'actual service settles immutable unsupported type before quota');
RESET ROLE;
SELECT extensions.is((SELECT attempt_ids FROM internal.observation_publication_moderation_outcomes WHERE operation_id='00000000-0000-4000-8000-00000000ef41'),'{}'::UUID[],'unsupported outcome records zero provider attempts');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderation_attempts WHERE operation_id='00000000-0000-4000-8000-00000000ef41'),0,'source settlement admits no provider attempt');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_work WHERE operation_id='00000000-0000-4000-8000-00000000ef41'),0,'source settlement removes reclaimable work');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_copy_work WHERE operation_id='00000000-0000-4000-8000-00000000ef41'),0,'source remediation never seeds copying');
UPDATE internal.observation_history_rollout SET publication_source_settlement_enabled=FALSE;
SELECT extensions.is(pg_temp.finish_source(gen_random_uuid())->>'reason','unsupported_source_type','saved source outcome replays after token retirement and gate closure');
SELECT extensions.is(public.read_owned_observation_publication_status('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef41')->>'status','needs_action','owner receives sanitized needs-action status');
SELECT extensions.throws_ok($$SELECT public.finalize_publication_photo_moderation('00000000-0000-4000-8000-00000000ef02','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef41',NULL)$$,'P0002','analysis_history_not_found','saved source outcome stays owner scoped');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef01');
SELECT extensions.throws_ok('SELECT pg_temp.finish_source()','P0002','analysis_history_not_found','deletion defeats saved unsupported-source replay');

SELECT * FROM extensions.finish();
ROLLBACK;

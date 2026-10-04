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
-- END PHOTO MODERATION HELPERS
SELECT extensions.ok(NOT (SELECT publication_moderation_enabled FROM internal.observation_history_rollout),'moderation gate defaults closed');
SELECT extensions.ok((SELECT count(*)>=4 AND bool_and(NOT enabled) FROM internal.ai_quota_policies WHERE operation='observation_photo_publication_moderation'),'all plan policies including complimentary are held');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) r
 WHERE n.nspname='internal' AND p.proname IN ('admit_publication_photo_moderation','dispatch_publication_photo_moderation','complete_publication_photo_moderation','retire_publication_photo_moderation','publication_moderation_receipt') AND has_function_privilege(r,p.oid,'EXECUTE')),'no API writer or private receipt reader');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE,publication_intent_enabled=TRUE;
SELECT pg_temp.seed_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff31','00000000-0000-4000-8000-00000000ff41');
CREATE FUNCTION pg_temp.moderation_admit(operation UUID DEFAULT '00000000-0000-4000-8000-00000000ff41',previous UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.admit_publication_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',operation,'00000000-0000-4000-8000-00000000ff31',previous,repeat('a',64));
$$;
SELECT extensions.throws_ok('SELECT pg_temp.moderation_admit()','55000','analysis_history_unavailable','closed gate cannot reserve');
UPDATE internal.observation_history_rollout SET publication_moderation_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.moderation_admit()','P0001','ai_quota_policy_disabled','closed provider policy cannot reserve');
UPDATE internal.ai_quota_policies SET enabled=TRUE WHERE operation='observation_photo_publication_moderation';
CREATE TEMP TABLE moderation_receipts(label TEXT PRIMARY KEY,receipt JSONB);
INSERT INTO moderation_receipts VALUES('first',pg_temp.moderation_admit());
SELECT extensions.is(pg_temp.moderation_admit(),(SELECT receipt FROM moderation_receipts WHERE label='first'),'lost admission response recovers one attempt');
SELECT extensions.ok((SELECT receipt->>'state'='reserved' AND receipt#>'{quota,complimentary_client_scan_id}'='null'::JSONB AND receipt#>'{quota,original_analysis_id}'='null'::JSONB FROM moderation_receipts WHERE label='first'),'moderation quota has no identification or complimentary link');
SELECT extensions.is((SELECT count(*)::INT FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000ff01'),1,'moderation creates no extra scan-credit consumption or hold');
CREATE FUNCTION pg_temp.dispatch_fixture(label TEXT) RETURNS JSONB LANGUAGE PLPGSQL AS $$
DECLARE r JSONB;
BEGIN
 SELECT receipt INTO r FROM moderation_receipts WHERE moderation_receipts.label=$1;
 IF EXISTS(SELECT 1 FROM internal.observation_photo_moderation_attempts WHERE id=(r->>'attempt_id')::UUID AND state='reserved') THEN
  PERFORM pg_temp.prepare_photo_execution('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',r);
 END IF;
 RETURN internal.dispatch_publication_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(r->>'attempt_id')::UUID,(r->>'lease_token')::UUID);
END;
$$;
CREATE FUNCTION pg_temp.complete_fixture(label TEXT,decision TEXT) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.complete_publication_photo_execution('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt),pg_temp.photo_execution_result(decision)) FROM moderation_receipts r WHERE r.label=$1;
$$;
CREATE FUNCTION pg_temp.retire_fixture(label TEXT) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.retire_publication_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID) FROM moderation_receipts r WHERE r.label=$1;
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.complete_fixture('first','approved')$$,'22023','analysis_history_operation_conflict','undispatched attempt cannot approve');
SELECT extensions.throws_ok($$SELECT internal.dispatch_publication_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID) FROM moderation_receipts WHERE label='first'$$,'22023','analysis_history_operation_conflict','dispatch cannot precede saved exact execution proof');
SELECT extensions.throws_ok($$SELECT internal.prepare_publication_photo_execution('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt)||jsonb_build_object('policy_sha256',repeat('c',64))) FROM moderation_receipts WHERE label='first'$$,'22023','invalid_analysis_history','unqualified policy digest cannot dispatch');
SELECT extensions.is(pg_temp.dispatch_fixture('first')->>'dispatch_allowed','true','first dispatch commits provider quota');
SELECT extensions.is((SELECT proof FROM internal.observation_photo_execution_proofs WHERE attempt_id=(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='first')),(SELECT pg_temp.photo_execution_proof(receipt) FROM moderation_receipts WHERE label='first'),'dispatch retains the exact private source and request proof');
SELECT extensions.throws_ok($$SELECT internal.complete_publication_photo_moderation('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,'approved') FROM moderation_receipts WHERE label='first'$$,'22023','analysis_history_operation_conflict','bare decision completion cannot bypass bounded output recording');

SELECT extensions.is(pg_temp.dispatch_fixture('first')->>'dispatch_allowed','false','lost dispatch response cannot execute provider twice');
SELECT extensions.throws_ok($$SELECT pg_temp.retire_fixture('first')$$,'22023','analysis_history_operation_conflict','unexpired in-flight dispatch cannot be retried');
INSERT INTO moderation_receipts VALUES('approved',pg_temp.complete_fixture('first','approved'));
SELECT extensions.is(pg_temp.complete_fixture('first','approved'),(SELECT receipt FROM moderation_receipts WHERE label='approved'),'lost decision response replays exact approval');
SELECT extensions.ok((SELECT receipt->>'state'='approved' AND receipt->'lease_token'='null'::JSONB AND receipt#>>'{source,media_id}'='00000000-0000-4000-8000-00000000ff31' AND receipt->>'policy_version'='photo_publication_v1' FROM moderation_receipts WHERE label='approved'),'approval pins source/policy and erases active token');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_execution_results),1,'decision and usage commit atomically once');
SELECT extensions.throws_ok($$SELECT internal.complete_publication_photo_execution('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt),pg_temp.photo_execution_result()||'{"confidence":1}'::JSONB) FROM moderation_receipts WHERE label='first'$$,'22023','analysis_history_operation_conflict','same decision with changed classifier facts is not replay');
SELECT extensions.throws_ok($$SELECT internal.complete_publication_photo_execution('00000000-0000-4000-8000-00000000ff01','00000000-0000-4000-8000-00000000ff11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt)||jsonb_build_object('request_sha256',repeat('c',64)),pg_temp.photo_execution_result()) FROM moderation_receipts WHERE label='first'$$,'22023','analysis_history_operation_conflict','terminal replay rejects a different execution proof');
SELECT extensions.throws_ok($$UPDATE internal.observation_photo_execution_results SET result=result||'{"confidence":1}'::JSONB$$,'22023','analysis_history_evidence_immutable','classifier facts are immutable');
DELETE FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='first');
SELECT extensions.is(pg_temp.complete_fixture('first','approved'),(SELECT receipt FROM moderation_receipts WHERE label='approved'),'private terminal proof survives generic quota pruning');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_fixture('first','rejected')$$,'22023','analysis_history_operation_conflict','decision cannot change on retry');
SELECT extensions.throws_ok($$UPDATE internal.observation_photo_moderation_attempts SET state='rejected' WHERE state='approved'$$,'22023','analysis_history_evidence_immutable','terminal proof cannot mutate');
SELECT extensions.throws_ok($$SELECT pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff41',(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='first'))$$,'22023','analysis_history_operation_conflict','approved decision cannot acquire a successor');
SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff42','00000000-0000-4000-8000-00000000ff31'));
INSERT INTO moderation_receipts VALUES('cancel',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff42'));
SELECT extensions.is(pg_temp.retire_fixture('cancel')->>'state','cancelled','known pre-dispatch cancellation refunds');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='cancel')),'refunded','cancelled attempt refunds quota');
INSERT INTO moderation_receipts VALUES('retry',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff42',(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='cancel')));
SELECT extensions.ok((SELECT (receipt#>>'{quota,attempt_count}')::INT=2 FROM moderation_receipts WHERE label='retry'),'explicit successor receives new metered quota attempt');
SELECT extensions.is(pg_temp.dispatch_fixture('cancel')->>'dispatch_allowed','false','old cancelled lease cannot dispatch after successor');
SELECT pg_temp.dispatch_fixture('retry');
-- Advance only synthetic dispatch expiry, without sleeping or weakening production transitions.
ALTER TABLE internal.observation_photo_moderation_attempts DISABLE TRIGGER guard_publication_moderation_attempt_update;
UPDATE internal.observation_photo_moderation_attempts SET dispatch_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id=(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='retry');
ALTER TABLE internal.observation_photo_moderation_attempts ENABLE TRIGGER guard_publication_moderation_attempt_update;
SELECT extensions.throws_ok($$SELECT pg_temp.complete_fixture('retry','approved')$$,'22023','analysis_history_operation_conflict','expired provider response cannot authorize copying');
SELECT extensions.is(pg_temp.retire_fixture('retry')->>'state','unknown_execution','crash recovery records ambiguity');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='retry')),'failed','unknown dispatch preserves charged provider quota');
INSERT INTO moderation_receipts VALUES('successor',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff42',(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='retry')));
SELECT extensions.throws_ok($$SELECT pg_temp.complete_fixture('retry','approved')$$,'22023','analysis_history_operation_conflict','late superseded decision cannot approve');
SELECT extensions.is(pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff42',(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='retry')),(SELECT receipt FROM moderation_receipts WHERE label='successor'),'explicit retry is itself idempotent');
SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff43','00000000-0000-4000-8000-00000000ff31'));
INSERT INTO moderation_receipts VALUES('expired',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff43'));
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='expired');
SELECT internal.refund_expired_ai_quota_reservations(1000);
SELECT extensions.throws_ok($$SELECT pg_temp.dispatch_fixture('expired')$$,'P0001','ai_quota_finalization_conflict','generic cleanup cannot leave a dispatchable attempt');
SELECT extensions.is(pg_temp.retire_fixture('expired')->>'state','cancelled','retirement recovers an already-refunded lease');
SELECT extensions.is(pg_temp.retire_fixture('expired')->>'state','cancelled','retirement response loss remains idempotent');
SELECT extensions.is((SELECT refund_count FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='expired')),1,'generic cleanup and retirement refund only once');
DELETE FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='expired');
INSERT INTO moderation_receipts VALUES('expired-successor',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff43',(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='expired')));
SELECT extensions.ok((SELECT (receipt#>>'{quota,attempt_count}')::INT=1 AND receipt#>>'{quota,reservation_id}'<>(SELECT receipt#>>'{quota,reservation_id}' FROM moderation_receipts WHERE label='expired') FROM moderation_receipts WHERE label='expired-successor'),'pruned quota receives a new reservation without colliding with old attempt count');
SELECT pg_temp.dispatch_fixture('expired-successor');
SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000ff01',pg_temp.publication_request('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff21','00000000-0000-4000-8000-00000000ff44','00000000-0000-4000-8000-00000000ff31'));
INSERT INTO moderation_receipts VALUES('pruned-dispatch',pg_temp.moderation_admit('00000000-0000-4000-8000-00000000ff44'));
SELECT pg_temp.dispatch_fixture('pruned-dispatch');
ALTER TABLE internal.observation_photo_moderation_attempts DISABLE TRIGGER guard_publication_moderation_attempt_update;
UPDATE internal.observation_photo_moderation_attempts SET dispatch_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE id=(SELECT (receipt->>'attempt_id')::UUID FROM moderation_receipts WHERE label='pruned-dispatch');
ALTER TABLE internal.observation_photo_moderation_attempts ENABLE TRIGGER guard_publication_moderation_attempt_update;
DELETE FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='pruned-dispatch');
SELECT extensions.is(pg_temp.retire_fixture('pruned-dispatch')->>'state','unknown_execution','expired private dispatch remains recoverable after generic quota pruning');
SELECT extensions.is((SELECT count(*)::INT FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='pruned-dispatch')),0,'pruned recovery never invents a quota refund or reservation');

SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts WHERE scan_id='00000000-0000-4000-8000-00000000ff11'),0,'decisions publish no media or discussion');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ff11','00000000-0000-4000-8000-00000000ff01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_moderation_attempts),0,'deletion fence erases private decisions and attempts');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='successor')),'refunded','deletion refunds only still-reserved successor');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (receipt#>>'{quota,reservation_id}')::UUID FROM moderation_receipts WHERE label='expired-successor')),'committed','deletion never refunds an already-dispatched provider execution');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_fixture('first','approved')$$,'P0002','analysis_history_not_found','deletion wins durable decision replay');
SELECT extensions.throws_ok('SELECT pg_temp.moderation_admit()','P0002','analysis_history_not_found','deletion wins moderation admission');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_execution_proofs),0,'deletion erases private execution proofs');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_photo_execution_results),0,'deletion erases private output and usage');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result()||'{"classification":"review"}'::JSONB),'review never authorizes approval');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result()||'{"confidence":0.94}'::JSONB),'low confidence never authorizes approval');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result()||'{"categories":["personal_data"]}'::JSONB),'allow with a category is invalid');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result('rejected')||'{"categories":["personal_data","personal_data"]}'::JSONB),'duplicate categories are invalid');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result()||'{"usage":{"input_tokens":100,"output_tokens":10,"total_tokens":111}}'::JSONB),'usage must sum exactly');
SELECT extensions.ok(NOT internal.valid_publication_photo_result(pg_temp.photo_execution_result()||'{"notes":"private"}'::JSONB),'unbounded output fields are rejected');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) r WHERE n.nspname='internal' AND p.proname IN ('prepare_publication_photo_execution','complete_publication_photo_execution','valid_publication_photo_result','dispatch_publication_photo_moderation','complete_publication_photo_moderation') AND has_function_privilege(r,p.oid,'EXECUTE')),'execution owner has no API exposure');
SELECT * FROM extensions.finish();
ROLLBACK;

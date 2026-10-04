\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN FUNDED ANALYSIS HELPERS
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
-- END FUNDED ANALYSIS HELPERS
SELECT extensions.ok(NOT(SELECT admission_enabled OR dispatch_enabled FROM internal.observation_history_rollout WHERE singleton),'new admission and dispatch are closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) AS r
    WHERE n.nspname='internal' AND p.proname IN ('admit_observation_analysis','dispatch_observation_analysis','record_observation_analysis_draft','complete_observation_analysis','fail_observation_analysis','settle_complimentary_analysis') AND has_function_privilege(r,p.oid,'EXECUTE')),'no API role can call private funding primitives');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611');
CREATE FUNCTION pg_temp.admit(analysis UUID DEFAULT '00000000-0000-4000-8000-00000000d621',source UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000d601',pg_temp.funded_input('00000000-0000-4000-8000-00000000d611',analysis,source),repeat('a',64));
$$;
SELECT extensions.throws_ok('SELECT pg_temp.admit()','55000','analysis_history_unavailable','closed admission creates no hold');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000d601'),0::BIGINT,'denied admission consumes no credit');
UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,append_enabled=TRUE;
SELECT pg_temp.admit();
SELECT pg_temp.admit();
SELECT extensions.throws_ok($$SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000d601',pg_temp.funded_input('00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621') || jsonb_build_object('request_digest',repeat('b',64)),repeat('a',64))$$,'22023','analysis_history_operation_conflict','analysis retry cannot change frozen input');
UPDATE internal.observation_history_rollout SET media_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621','00000000-0000-4000-8000-00000000d631','image/jpeg',3,repeat('a',64))$$,'22023','analysis_history_operation_conflict','description admission cannot acquire media later');
SELECT extensions.throws_ok($$SELECT public.reserve_identification_quota('00000000-0000-4000-8000-00000000d601','scan_identification','00000000-0000-4000-8000-00000000d621',repeat('a',64),'00000000-0000-4000-8000-00000000d621',FALSE,3,FALSE,'multimodal_text_v1','google_gemini',6)$$,'55000','analysis_history_admission_required','legacy quota cannot renew child lease');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000d601'),1::BIGINT,'duplicate admission creates one hold');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM public.scans WHERE id='00000000-0000-4000-8000-00000000d621') AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id='00000000-0000-4000-8000-00000000d621'),'child admission creates no fake scan or ingestion job');
SELECT extensions.throws_ok($$SELECT public.begin_scan_ingestion('00000000-0000-4000-8000-00000000d621','00000000-0000-4000-8000-00000000d601','identify-multimodal','{}')$$,'55000','analysis_history_admission_required','legacy ingestion cannot create a child job');
SELECT extensions.throws_ok($$SELECT public.fail_scan_ingestion_terminal('00000000-0000-4000-8000-00000000d621','00000000-0000-4000-8000-00000000d601','fixture','fixture','fixture_failure')$$,'55000','analysis_history_completion_required','legacy terminal path cannot release a child hold');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation((quota->>'reservation_id')::UUID,owner_id,(quota->>'lease_token')::UUID,'committed') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'$$,'55000','analysis_history_dispatch_required','direct quota finalization cannot bypass intent');
SELECT extensions.throws_ok($$SELECT public.commit_identification_invocation((quota->>'reservation_id')::UUID,owner_id,(quota->>'lease_token')::UUID,(quota->>'attempt_count')::INTEGER,pg_temp.funded_provenance(analysis_id)) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'$$,'55000','analysis_history_dispatch_required','direct provider dispatch cannot bypass intent');
SELECT extensions.throws_ok($$SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621')$$,'55000','analysis_history_unavailable','provider dispatch has separate hold');
UPDATE internal.observation_history_rollout SET dispatch_enabled=TRUE;
SELECT extensions.is((pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621')->>'may_dispatch')::BOOLEAN,TRUE,'first dispatch accounts provider execution');
SELECT extensions.is((pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621')->>'may_dispatch')::BOOLEAN,FALSE,'lost dispatch response never repeats inference');
SELECT extensions.is((pg_temp.admit()->>'state'),'dispatched','ambiguous admission retry is recovery only');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d621'),'held','dispatch does not consume user credit');
SELECT extensions.throws_ok($$SELECT internal.fail_observation_analysis(owner_id,observation_id,analysis_id,(quota->>'lease_token')::UUID,'timeout','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'$$,'22023','analysis_history_operation_conflict','timeout is not terminal proof');
SELECT pg_temp.funded_draft('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621');
SELECT extensions.is((SELECT count(*) FROM public.ai_usage_events WHERE scan_id='00000000-0000-4000-8000-00000000d621'),1::BIGINT,'durable draft records provider usage');
SELECT extensions.throws_ok($$SELECT internal.append_observation_analysis(owner_id,draft) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'$$,'55000','analysis_history_completion_required','raw append cannot bypass settlement');
SELECT extensions.throws_ok($$SELECT public.complete_identification_invocation(invocation_id,owner_id,(quota->>'lease_token')::UUID,'refusal','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'$$,'55000','analysis_history_completion_required','legacy reporting cannot change admitted provider accounting');
CREATE FUNCTION pg_temp.reject_funding_commit() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN IF NEW.client_scan_id='00000000-0000-4000-8000-00000000d621' AND NEW.state='consumed' THEN RAISE EXCEPTION 'synthetic_settlement_failure'; END IF; RETURN NEW; END; $$;
CREATE TRIGGER synthetic_reject_funding_commit BEFORE UPDATE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_funding_commit();
SELECT extensions.throws_ok($$SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621')$$,'P0001','synthetic_settlement_failure','settlement failure aborts entire completion');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000d621') AND (SELECT state='draft' FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d621'),'failed completion leaves only recoverable draft');
DROP TRIGGER synthetic_reject_funding_commit ON internal.complimentary_scan_usage;
CREATE TEMP TABLE receipt AS SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621') AS value;
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d621'),'consumed','durable completion consumes held credit');
SELECT extensions.is(internal.complete_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621'),(SELECT value FROM receipt),'lost completion response returns exact receipt');
CREATE TEMP TABLE original_projection AS SELECT to_jsonb(h) AS value FROM internal.observation_histories h WHERE observation_id='00000000-0000-4000-8000-00000000d611';
SELECT pg_temp.admit('00000000-0000-4000-8000-00000000d622','00000000-0000-4000-8000-00000000d621');
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d622');
SELECT pg_temp.funded_draft('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d622');
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NOW()+INTERVAL '1 day' WHERE id='00000000-0000-4000-8000-00000000d601';
SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d622');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d622'),'released','purchase before completion releases hold');
SELECT extensions.is((SELECT to_jsonb(h) FROM internal.observation_histories h WHERE observation_id='00000000-0000-4000-8000-00000000d611'),(SELECT value FROM original_projection),'reanalysis preserves selected identification and authority');
UPDATE public.users SET subscription_tier='free',subscription_expires_at=NULL WHERE id='00000000-0000-4000-8000-00000000d601';
SELECT pg_temp.admit('00000000-0000-4000-8000-00000000d623','00000000-0000-4000-8000-00000000d621');
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d623');
SELECT internal.fail_observation_analysis(owner_id,observation_id,analysis_id,(quota->>'lease_token')::UUID,'provider_refusal','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d623';
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d623'),'released','proven refusal releases user credit');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d623'),'committed','provider costs remain charged after refusal');
SELECT extensions.is((SELECT outcome FROM public.ai_usage_events WHERE scan_id='00000000-0000-4000-8000-00000000d623'),'refusal','known refusal is not reported as unknown execution');
SELECT pg_temp.admit('00000000-0000-4000-8000-00000000d625');
CREATE TEMP TABLE expired_token AS SELECT (quota->>'lease_token')::UUID AS token FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d625';
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE original_analysis_id='00000000-0000-4000-8000-00000000d625';
SELECT pg_temp.admit('00000000-0000-4000-8000-00000000d625');
SELECT extensions.throws_ok($$SELECT internal.dispatch_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d625',(SELECT token FROM expired_token),pg_temp.funded_provenance('00000000-0000-4000-8000-00000000d625'))$$,'22023','analysis_history_operation_conflict','expired worker cannot dispatch after lease renewal');
SELECT internal.fail_observation_analysis(owner_id,observation_id,analysis_id,(quota->>'lease_token')::UUID,'cancelled_before_dispatch','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000d625';
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d625'),'released','proven cancellation before dispatch releases one renewed hold');
SELECT pg_temp.admit('00000000-0000-4000-8000-00000000d624','00000000-0000-4000-8000-00000000d621');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d601');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE observation_id='00000000-0000-4000-8000-00000000d611'),0::BIGINT,'observation deletion clears private inputs drafts and receipts');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d624'),'released','deletion releases unfinished hold');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000d624'),'refunded','deletion before dispatch refunds unused provider reservation');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000d621'),'consumed','deletion never restores already consumed result credit');
SELECT extensions.throws_ok($$SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000d601','00000000-0000-4000-8000-00000000d611','00000000-0000-4000-8000-00000000d621')$$,'P0002','analysis_history_not_found','deletion fence wins completed replay');
SELECT extensions.ok((SELECT user_id IS NULL AND completed_at IS NOT NULL AND claim_token IS NULL FROM internal.scan_deletion_tombstones WHERE scan_id='00000000-0000-4000-8000-00000000d624'),'deleted child has permanent ownerless completed generation marker');
SELECT extensions.throws_ok($$SELECT public.reserve_identification_quota('00000000-0000-4000-8000-00000000d601','scan_identification','00000000-0000-4000-8000-00000000d624',repeat('a',64),'00000000-0000-4000-8000-00000000d624',FALSE,3,FALSE,'multimodal_text_v1','google_gemini',6)$$,'55000','scan_generation_deleted','legacy quota cannot resurrect a deleted child');
SELECT extensions.throws_ok($$INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture) VALUES('00000000-0000-4000-8000-00000000d624','00000000-0000-4000-8000-00000000d601','{}',0.8,FALSE,'flash','private',TRUE)$$,'55000','scan_generation_deleted','legacy scan insert cannot resurrect deleted child');
SELECT extensions.throws_ok($$SELECT public.begin_scan_ingestion('00000000-0000-4000-8000-00000000d624','00000000-0000-4000-8000-00000000d601','identify-multimodal','{}')$$,'55000','scan_generation_deleted','legacy ingestion cannot resurrect deleted child');
SELECT * FROM extensions.finish();
ROLLBACK;

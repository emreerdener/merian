\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.seed_fenced_chat(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 UPDATE public.users SET subscription_tier='pro',subscription_expires_at=now()+interval '1 year' WHERE id=owner_id;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/private.jpg'],0.9,TRUE,'flash','private');
 IF NOT EXISTS(SELECT 1 FROM public.user_ai_consent_events WHERE user_id=owner_id) THEN
 INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',now(),'self_attestation','Synthetic adult receipt','ios','1.0.3','275');
 INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',now(),'Synthetic terms receipt','ios','1.0.3','275');
 INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',now(),'Synthetic disclosure','Grant','ios','1.0.3','275');
 END IF;
END;
$$;
CREATE FUNCTION pg_temp.open_fenced_chat() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE,chat_execution_enabled=TRUE;
 UPDATE internal.field_chat_admission_cutover SET seeded_at=now()-interval '2 days',not_before_utc=now()-interval '1 day',beta_early_activation_at=NULL,beta_original_not_before_utc=NULL,
 activated_at=NULL,activated_candidate_sha=NULL,activated_migration_sha256=NULL,
 activated_explore_bundle_sha256=NULL,activated_insight_bundle_sha256=NULL,activated_species_dictionary_bundle_sha256=NULL;
 PERFORM public.activate_field_chat_admission_cutover(repeat('a',40),repeat('b',64),repeat('c',64),repeat('d',64),repeat('e',64));
 UPDATE internal.ai_quota_policies SET daily_limit=1000,user_window_limit=1000,ip_window_limit=1000 WHERE operation='insight_chat_reply' AND allowed;
END;
$$;

SELECT set_config('request.jwt.claims','{"role":"service_role","sub":"00000000-0000-4000-8000-00000000ca01"}',TRUE);
CREATE TEMP TABLE fixture AS SELECT n,('00000000-0000-4000-8000-00000000cb0'||n)::UUID scan,
 ('00000000-0000-4000-8000-00000000cc0'||n)::UUID request FROM generate_series(1,4) n;
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ca01',scan) FROM fixture;
SELECT pg_temp.open_fenced_chat();
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
CREATE FUNCTION pg_temp.legacy_send(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT to_jsonb(r) FROM fixture,LATERAL public.reserve_field_chat_send('00000000-0000-4000-8000-00000000ca01',gen_random_uuid(),'insight',scan,'Question',request) r WHERE fixture.n=$1;
$$;
SELECT extensions.is(public.get_insight_chat_send_route('00000000-0000-4000-8000-00000000ca01',(SELECT scan FROM fixture WHERE n=1)), '{"requires_context":false}'::JSONB,'ordinary legacy observation remains legacy before enrollment');
CREATE TEMP TABLE admitted AS SELECT n,pg_temp.legacy_send(n) result FROM fixture WHERE n<=3;
SELECT extensions.ok((pg_temp.legacy_send(1)->>'is_replay')::BOOLEAN,'ordinary exact legacy replay preserved');
CREATE TEMP TABLE quota AS SELECT n,to_jsonb(q) result FROM fixture,LATERAL internal.reserve_ai_quota_core('00000000-0000-4000-8000-00000000ca01','insight_chat_reply',request,repeat('a',64),scan,FALSE,NULL,FALSE) q WHERE n<=3;
CREATE FUNCTION pg_temp.commit_chat(n INTEGER) RETURNS BOOLEAN LANGUAGE SQL AS $$
 SELECT public.finalize_ai_quota_reservation((result->>'reservation_id')::UUID,'00000000-0000-4000-8000-00000000ca01',(result->>'lease_token')::UUID,'committed') FROM quota WHERE quota.n=$1;
$$;
SELECT public.enroll_owned_observation_history((SELECT scan FROM fixture WHERE n=1),9);
SELECT extensions.is(public.get_insight_chat_send_route('00000000-0000-4000-8000-00000000ca01',(SELECT scan FROM fixture WHERE n=1)), '{"requires_context":true}'::JSONB,'enrollment requires immutable context independently of gate');
SELECT extensions.throws_ok('SELECT pg_temp.legacy_send(1)','55000','field_chat_context_required','legacy exact replay cannot rebuild enrolled context');
SELECT extensions.throws_ok('SELECT pg_temp.commit_chat(1)','55000','field_chat_context_required','admission then enrollment then commit cannot dispatch');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (result->>'reservation_id')::UUID FROM quota WHERE n=1)),'reserved','denied commit leaves reservation uncommitted');
SELECT pg_temp.commit_chat(2);
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history((SELECT scan FROM fixture WHERE n=2),9)$$,'55000','analysis_history_chat_in_progress','enrollment holds dispatched incomplete legacy work');
INSERT INTO public.insight_chat_messages(id,conversation_id,user_id,scan_id,role,message_text,safety_metadata)
 SELECT gen_random_uuid(),(result->>'conversation_id')::UUID,'00000000-0000-4000-8000-00000000ca01',scan,'assistant','Synthetic answer',jsonb_build_object('request_id',request)
 FROM fixture JOIN admitted USING(n) WHERE n=2;
SELECT extensions.throws_ok($$SELECT public.enroll_owned_observation_history((SELECT scan FROM fixture WHERE n=2),9)$$,'55000','analysis_history_chat_in_progress','wrong assistant identity cannot settle enrollment');
DELETE FROM public.insight_chat_messages WHERE scan_id=(SELECT scan FROM fixture WHERE n=2) AND role='assistant';
INSERT INTO public.insight_chat_messages(id,conversation_id,user_id,scan_id,role,message_text,safety_metadata)
 SELECT internal.insight_chat_assistant_id((result->>'conversation_id')::UUID,request),(result->>'conversation_id')::UUID,'00000000-0000-4000-8000-00000000ca01',scan,'assistant','Synthetic answer',jsonb_build_object('request_id',request)
 FROM fixture JOIN admitted USING(n) WHERE n=2;
SELECT extensions.lives_ok($$SELECT public.enroll_owned_observation_history((SELECT scan FROM fixture WHERE n=2),9)$$,'exact assistant receipt permits enrollment');
SELECT extensions.throws_ok('SELECT pg_temp.commit_chat(2)','55000','field_chat_context_required','generic idempotent commit is not renewed permission after enrollment');
SELECT pg_temp.commit_chat(3);
-- Simulate an already-enrolled historical migration state: old stale rescue must still hold.
INSERT INTO internal.observation_histories(observation_id) SELECT scan FROM fixture WHERE n=3;
UPDATE internal.ai_quota_reservations SET committed_at=clock_timestamp()-interval '20 minutes' WHERE id=(SELECT (result->>'reservation_id')::UUID FROM quota WHERE n=3);
SELECT extensions.ok(NOT public.recover_stale_field_chat_quota('00000000-0000-4000-8000-00000000ca01','insight_chat_reply',(SELECT request FROM fixture WHERE n=3),(SELECT (result->>'conversation_id')::UUID FROM admitted WHERE n=3),(SELECT scan FROM fixture WHERE n=3)),'stale rescue cannot reopen protected work');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE id=(SELECT (result->>'reservation_id')::UUID FROM quota WHERE n=3)),'committed','stale denial leaves consumed quota intact');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=TRUE;
SELECT extensions.is(public.get_insight_chat_send_route('00000000-0000-4000-8000-00000000ca01',(SELECT scan FROM fixture WHERE n=4)), '{"requires_context":true}'::JSONB,'server execution cutover protects new unenrolled observations too');
SELECT extensions.throws_ok('SELECT pg_temp.legacy_send(4)','55000','field_chat_context_required','client omission cannot bypass server cutover');
SELECT extensions.lives_ok($$SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000ca01',gen_random_uuid(),(SELECT scan FROM fixture WHERE n=4),'Question',(SELECT request FROM fixture WHERE n=4),NULL,1)$$,'snapshot owner can use private core');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
SELECT extensions.is(public.get_insight_chat_send_route('00000000-0000-4000-8000-00000000ca01',(SELECT scan FROM fixture WHERE n=4)), '{"requires_context":true}'::JSONB,'stored context stays protected after rollout closes');
SELECT extensions.throws_ok('SELECT pg_temp.legacy_send(4)','55000','field_chat_context_required','stored context never downgrades to legacy replay');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.reserve_field_chat_send_core(uuid,uuid,text,uuid,text,uuid)','EXECUTE') AND NOT has_function_privilege('service_role','internal.finalize_ai_quota_reservation_core(uuid,uuid,uuid,text)','EXECUTE') AND NOT has_function_privilege('service_role','internal.recover_stale_field_chat_quota_core(uuid,text,uuid,uuid,uuid)','EXECUTE'),'API callers cannot bypass private cores');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.get_insight_chat_send_route(uuid,uuid)','EXECUTE') AND has_function_privilege('service_role','public.get_insight_chat_send_route(uuid,uuid)','EXECUTE'),'route is service only');
SELECT public.request_scan_deletion((SELECT scan FROM fixture WHERE n=4),'00000000-0000-4000-8000-00000000ca01');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_send_route('00000000-0000-4000-8000-00000000ca01',(SELECT scan FROM fixture WHERE n=4))$$,'P0002','field_chat_subject_not_found','deletion wins over route recovery');
SELECT * FROM extensions.finish();
ROLLBACK;

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

SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
CREATE TEMP TABLE fixture AS SELECT n,('00000000-0000-4000-8000-00000000dc'||lpad(n::TEXT,2,'0'))::UUID scan,
 ('00000000-0000-4000-8000-00000000dd'||lpad(n::TEXT,2,'0'))::UUID request FROM generate_series(1,9) n;
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000da01',scan) FROM fixture;
SELECT pg_temp.open_fenced_chat();
CREATE TEMP TABLE reserved AS SELECT n,public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000da01',scan,request,'Question',NULL,1,repeat('a',64)) result FROM fixture;
SELECT * FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=fixture.scan,
 LATERAL public.reserve_protected_insight_chat_send_with_context('00000000-0000-4000-8000-00000000da01',gen_random_uuid(),fixture.scan,'Question',request,NULL,1,f.reservation_id,f.lease_token) bound;
CREATE FUNCTION pg_temp.dispatch(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.grant_protected_insight_chat_dispatch('00000000-0000-4000-8000-00000000da01',scan,request,f.reservation_id,f.lease_token)
 FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=fixture.scan WHERE fixture.n=$1;
$$;
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000da01',f.lease_token,'committed') FROM internal.insight_chat_execution_fences f JOIN fixture ON scan=f.scan_id WHERE n=1$$,'55000','field_chat_execution_held','generic finalizer cannot bypass dispatch marker even with a bound context');
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"dispatch_granted","model":"gemini-2.5-flash"}'::JSONB,'first dispatch has closed grant');
SELECT extensions.ok((SELECT dispatch_grant_id IS NOT NULL AND dispatch_granted_at IS NOT NULL AND state='committed' FROM internal.insight_chat_execution_fences f JOIN internal.ai_quota_reservations q ON q.id=f.reservation_id JOIN fixture ON scan=f.scan_id WHERE n=1),'marker and quota commit atomically');
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"held"}'::JSONB,'lost reply cannot regain permission');
SELECT extensions.throws_ok($$UPDATE internal.insight_chat_execution_fences SET dispatch_grant_id=NULL,dispatch_granted_at=NULL WHERE scan_id=(SELECT scan FROM fixture WHERE n=1)$$,'55000','field_chat_execution_immutable','dispatch marker cannot be cleared');
SELECT extensions.throws_ok($$UPDATE internal.insight_chat_execution_fences SET dispatch_grant_id=gen_random_uuid() WHERE scan_id=(SELECT scan FROM fixture WHERE n=1)$$,'55000','field_chat_execution_immutable','dispatch marker cannot be replaced');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE;
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"held"}'::JSONB,'already granted remains held with gate closed');
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(2)','55000','field_chat_execution_unavailable','fresh dispatch requires gate');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=TRUE;
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE request_id=(SELECT request FROM fixture WHERE n=2);
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(2)','55000','field_chat_execution_held','expired quota cannot dispatch');
SELECT extensions.ok((SELECT dispatch_grant_id IS NULL FROM internal.insight_chat_execution_fences JOIN fixture ON scan=scan_id WHERE n=2),'denial does not commit marker');
-- Force failure AFTER marker assignment to prove transaction rollback.
CREATE FUNCTION pg_temp.reject_commit() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN
 IF NEW.request_id=(SELECT request FROM fixture WHERE n=3) AND NEW.state='committed' THEN RAISE EXCEPTION 'synthetic_commit_denied' USING ERRCODE='55000'; END IF; RETURN NEW; END; $$;
CREATE TRIGGER synthetic_chat_commit_failure AFTER UPDATE ON internal.ai_quota_reservations FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_commit();
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(3)','55000','synthetic_commit_denied','failed quota commit rolls back marker');
SELECT extensions.ok((SELECT dispatch_grant_id IS NULL AND state='reserved' FROM internal.insight_chat_execution_fences f JOIN internal.ai_quota_reservations q ON q.id=f.reservation_id JOIN fixture ON scan=f.scan_id WHERE n=3),'rollback retains original reserved state');
DROP TRIGGER synthetic_chat_commit_failure ON internal.ai_quota_reservations;
DELETE FROM public.insight_chat_messages WHERE id=(SELECT message_id FROM internal.insight_chat_execution_fences JOIN fixture ON scan=scan_id WHERE n=4);
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(4)','55000','field_chat_execution_held','erased message is permanently held');
SELECT public.request_scan_deletion((SELECT scan FROM fixture WHERE n=5),'00000000-0000-4000-8000-00000000da01');
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(5)','P0002','field_chat_subject_not_found','deletion request wins before physical deletion');
DELETE FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT message_id FROM internal.insight_chat_execution_fences JOIN fixture ON scan=scan_id WHERE n=6);
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(6)','55000','field_chat_execution_held','missing immutable context cannot dispatch');
SELECT extensions.throws_ok($$SELECT public.grant_protected_insight_chat_dispatch('00000000-0000-4000-8000-00000000da01',scan,request,f.reservation_id,gen_random_uuid()) FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=fixture.scan WHERE n=7$$,'55000','field_chat_execution_held','wrong lease cannot dispatch');
SELECT extensions.throws_ok($$SELECT public.grant_protected_insight_chat_dispatch(gen_random_uuid(),scan,request,f.reservation_id,f.lease_token) FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=fixture.scan WHERE n=7$$,'P0002','field_chat_subject_not_found','foreign owner cannot dispatch');
SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000da01',f.lease_token,'refunded') FROM internal.insight_chat_execution_fences f JOIN fixture ON scan=f.scan_id WHERE n=8;
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(8)','55000','field_chat_execution_held','refunded attempt never grants');
SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000da01',f.lease_token,'failed') FROM internal.insight_chat_execution_fences f JOIN fixture ON scan=f.scan_id WHERE n=1;
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"held"}'::JSONB,'provider failure never grants a successor');
DELETE FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM fixture WHERE n=1);
DELETE FROM public.insight_chat_messages WHERE id=(SELECT message_id FROM internal.insight_chat_execution_fences JOIN fixture ON scan=scan_id WHERE n=1);
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"held"}'::JSONB,'marker survives quota pruning and message erasure');
-- Removing required consent proof conclusively denies new dispatch without rebasing context.
DELETE FROM public.user_adult_eligibility_receipts WHERE user_id='00000000-0000-4000-8000-00000000da01';
SELECT extensions.throws_ok('SELECT pg_temp.dispatch(9)','P0001','ai_consent_required','current consent is checked after admission');
SELECT extensions.is(pg_temp.dispatch(1),'{"status":"held"}'::JSONB,'replay never renews consent or permission');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.grant_protected_insight_chat_dispatch(uuid,uuid,uuid,uuid,uuid)','EXECUTE') AND has_function_privilege('service_role','public.grant_protected_insight_chat_dispatch(uuid,uuid,uuid,uuid,uuid)','EXECUTE'),'dispatch service only');
SELECT * FROM extensions.finish();
ROLLBACK;

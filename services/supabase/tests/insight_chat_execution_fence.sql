\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN EXECUTION FENCE HELPERS
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
-- END EXECUTION FENCE HELPERS
CREATE TEMP TABLE fixture AS SELECT n,('00000000-0000-4000-8000-00000000f'||lpad(n::TEXT,3,'0'))::UUID scan,
 ('00000000-0000-4000-8000-00000000e'||lpad(n::TEXT,3,'0'))::UUID request FROM generate_series(1,8) n;
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000fa01',scan) FROM fixture;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
CREATE FUNCTION pg_temp.reserve_fenced(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000fa01',scan,request,'Question',NULL,1,repeat('a',64)) FROM fixture WHERE fixture.n=$1;
$$;
CREATE FUNCTION pg_temp.bind_fenced(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT to_jsonb(result) FROM fixture JOIN internal.insight_chat_execution_fences fence ON fence.client_message_id=fixture.request,
 LATERAL public.reserve_protected_insight_chat_send_with_context('00000000-0000-4000-8000-00000000fa01',gen_random_uuid(),fixture.scan,'Question',fixture.request,NULL,1,fence.reservation_id,fence.lease_token) result WHERE fixture.n=$1;
$$;
SELECT extensions.throws_ok('SELECT pg_temp.reserve_fenced(1)','55000','field_chat_execution_unavailable','first admission default off');
SELECT pg_temp.open_fenced_chat();
CREATE TEMP TABLE admitted AS SELECT n,pg_temp.reserve_fenced(n) result FROM fixture;
SELECT extensions.ok((SELECT bool_and(result->>'status'='reserved' AND result ?& ARRAY['reservation_id','lease_token','lease_expires_at','model'] AND NOT result ? 'quota') FROM admitted),'first admission grants exactly one original quota attempt');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences WHERE scan_id IN(SELECT scan FROM fixture)),8,'one durable fence per submitted identity');
SELECT extensions.is(pg_temp.reserve_fenced(1),' {"status":"held"}'::JSONB,'exact replay exposes no lease or new grant');
SELECT extensions.throws_ok($$SELECT public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000fa01',(SELECT scan FROM fixture WHERE n=1),(SELECT request FROM fixture WHERE n=1),'Changed',NULL,1,repeat('a',64))$$,'23505','field_chat_idempotency_conflict','changed question cannot reuse identity');
SELECT extensions.throws_ok($$SELECT public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000fa01',(SELECT scan FROM fixture WHERE n=2),(SELECT request FROM fixture WHERE n=1),'Question',NULL,1,repeat('a',64))$$,'23505','field_chat_idempotency_conflict','global identity cannot move to another scan');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000fa01',f.lease_token,'committed') FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=1$$,'55000','field_chat_execution_held','provider quota commit requires bound immutable message');
SELECT extensions.ok((pg_temp.bind_fenced(1)->>'is_replay')::BOOLEAN=FALSE,'first final admission atomically binds context');
SELECT extensions.ok((pg_temp.bind_fenced(1)->>'is_replay')::BOOLEAN,'binding exact replay returns original receipt');
SELECT extensions.ok((SELECT message_bound AND message_id IS NOT NULL FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=1),'message binding durable');
SELECT public.grant_protected_insight_chat_dispatch('00000000-0000-4000-8000-00000000fa01',f.scan_id,f.client_message_id,f.reservation_id,f.lease_token) FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=1;
SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000fa01',f.lease_token,'failed') FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=1;
SELECT extensions.throws_ok($$SELECT * FROM public.reserve_ai_quota('00000000-0000-4000-8000-00000000fa01','insight_chat_reply',(SELECT request FROM fixture WHERE n=1),repeat('a',64))$$,'55000','field_chat_execution_held','generic caller cannot reopen failed protected quota');
SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000fa01',f.lease_token,'refunded') FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=2;
UPDATE internal.ai_quota_reservations SET lease_expires_at=now()-interval '1 hour' WHERE request_id=(SELECT request FROM fixture WHERE n=3);
SELECT internal.refund_expired_ai_quota_reservations();
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM fixture WHERE n=3)),'refunded','normal expired-reservation cleanup still runs');
SELECT extensions.throws_ok('SELECT pg_temp.bind_fenced(3)','55000','field_chat_execution_held','expired/refunded grant cannot admit a message');
SELECT pg_temp.bind_fenced(4);
SELECT public.grant_protected_insight_chat_dispatch('00000000-0000-4000-8000-00000000fa01',f.scan_id,f.client_message_id,f.reservation_id,f.lease_token) FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=4;
UPDATE internal.ai_quota_reservations SET updated_at=now()-interval '31 days' WHERE request_id IN(SELECT request FROM fixture WHERE n<=4);
SELECT internal.prune_ai_quota_state();
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.ai_quota_reservations WHERE request_id IN(SELECT request FROM fixture WHERE n<=4)),0,'ordinary terminal pruning is preserved');
SELECT extensions.ok((SELECT bool_and(pg_temp.reserve_fenced(n)='{"status":"held"}'::JSONB) FROM fixture WHERE n<=4),'all pruned states retain their no-successor fences');
SELECT extensions.throws_ok($$SELECT * FROM public.reserve_ai_quota('00000000-0000-4000-8000-00000000fa01','insight_chat_reply',(SELECT request FROM fixture WHERE n=1),repeat('a',64))$$,'55000','field_chat_execution_held','generic caller cannot replace a pruned protected quota');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
SELECT extensions.ok((pg_temp.bind_fenced(1)->>'is_replay')::BOOLEAN,'original immutable receipt replays after prune and gates close');
SELECT extensions.is(pg_temp.reserve_fenced(2),'{"status":"held"}'::JSONB,'known pre-admission refund stays retired even with gate closed');
SELECT pg_temp.open_fenced_chat();
SELECT pg_temp.bind_fenced(5);
DELETE FROM public.insight_chat_messages WHERE id=(SELECT message_id FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=5);
SELECT extensions.ok((SELECT message_bound AND message_id IS NULL FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=5),'message erasure retains retired binding');
SELECT extensions.throws_ok('SELECT pg_temp.bind_fenced(5)','55000','field_chat_execution_held','deleted message cannot be rebound');
SELECT extensions.is(pg_temp.reserve_fenced(5),'{"status":"held"}'::JSONB,'deleted message cannot obtain new quota');
DELETE FROM public.scans WHERE id=(SELECT scan FROM fixture WHERE n=6);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=6),0,'scan deletion erases only its fence');
SELECT extensions.throws_ok('SELECT pg_temp.reserve_fenced(6)','P0002','field_chat_subject_not_found','deleted scan cannot regain a grant');
UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE,image_storage_urls=ARRAY[]::TEXT[] WHERE id=(SELECT scan FROM fixture WHERE n=7);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=7),0,'scientific account detachment removes private fence');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences JOIN fixture ON request=client_message_id WHERE n=8),1,'unrelated sibling stays fenced');
SELECT pg_temp.bind_fenced(8);
SELECT public.request_scan_deletion((SELECT scan FROM fixture WHERE n=8),'00000000-0000-4000-8000-00000000fa01');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation(f.reservation_id,'00000000-0000-4000-8000-00000000fa01',f.lease_token,'committed') FROM internal.insight_chat_execution_fences f JOIN fixture ON request=client_message_id WHERE n=8$$,'P0002','field_chat_subject_not_found','permanent deletion request fences commit before row erasure');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.insight_chat_execution_fences','SELECT') AND NOT has_table_privilege('authenticated','internal.insight_chat_execution_fences','SELECT'),'ledger has no direct API grants');
SELECT extensions.ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.insight_chat_execution_fences'::regclass),'ledger uses deny-by-default RLS');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.reserve_protected_insight_chat_quota(uuid,uuid,uuid,text,jsonb,integer,text)','EXECUTE') AND has_function_privilege('service_role','public.reserve_protected_insight_chat_quota(uuid,uuid,uuid,text,jsonb,integer,text)','EXECUTE'),'quota facade service-only');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok('SELECT * FROM internal.insight_chat_execution_fences','42501',NULL,'service cannot directly inspect ledger');
RESET ROLE;
-- Actual merge keeps scan-owned evidence and retires colliding operational
-- quota rows; no duplicate message or quota UUID becomes a dispatch grant.
CREATE TEMP TABLE merge_fixture AS SELECT
 '00000000-0000-4000-8000-00000000fb01'::UUID source,
 '00000000-0000-4000-8000-00000000fb02'::UUID target;
SELECT pg_temp.seed_fenced_chat(source,('00000000-0000-4000-8000-00000000fb1'||n)::UUID) FROM merge_fixture,generate_series(1,4) n;
SELECT pg_temp.seed_fenced_chat(target,'00000000-0000-4000-8000-00000000fb21') FROM merge_fixture;
CREATE TEMP TABLE source_quota AS SELECT n,public.reserve_protected_insight_chat_quota(source,
 ('00000000-0000-4000-8000-00000000fb1'||n)::UUID,('00000000-0000-4000-8000-00000000fb3'||n)::UUID,'Question',NULL,1,repeat('b',64)) result FROM merge_fixture,generate_series(1,4) n;
SELECT public.reserve_ai_quota(target,'insight_chat_reply','00000000-0000-4000-8000-00000000fb31',repeat('b',64)) FROM merge_fixture;
SELECT extensions.is((SELECT public.reserve_protected_insight_chat_quota(target,'00000000-0000-4000-8000-00000000fb21','00000000-0000-4000-8000-00000000fb33','Question',NULL,1,repeat('b',64))->>'status' FROM merge_fixture),'reserved','same UUID on a different account does not interfere');
CREATE TEMP TABLE source_context AS SELECT n,to_jsonb(bound_message) context FROM merge_fixture,source_quota,
 LATERAL public.reserve_protected_insight_chat_send_with_context(source,gen_random_uuid(),('00000000-0000-4000-8000-00000000fb1'||n)::UUID,'Question',('00000000-0000-4000-8000-00000000fb3'||n)::UUID,NULL,1,(source_quota.result->>'reservation_id')::UUID,(source_quota.result->>'lease_token')::UUID) bound_message WHERE n IN(2,4);
SELECT public.grant_protected_insight_chat_dispatch(source,'00000000-0000-4000-8000-00000000fb12','00000000-0000-4000-8000-00000000fb32',(result->>'reservation_id')::UUID,(result->>'lease_token')::UUID) FROM merge_fixture,source_quota WHERE n=2;
INSERT INTO public.insight_chat_conversations(id,user_id,scan_id)
 SELECT '00000000-0000-4000-8000-00000000fb42',target,'00000000-0000-4000-8000-00000000fb12' FROM merge_fixture;
INSERT INTO public.insight_chat_messages(conversation_id,user_id,scan_id,role,message_text,client_message_id)
 SELECT '00000000-0000-4000-8000-00000000fb42',target,'00000000-0000-4000-8000-00000000fb12','user','Duplicate target question','00000000-0000-4000-8000-00000000fb32' FROM merge_fixture;
SELECT internal.perform_ghost_profile_merge(source,target) FROM merge_fixture;
SELECT extensions.ok((SELECT bool_and(s.user_id=target) FROM internal.insight_chat_execution_fences f JOIN public.scans s ON s.id=f.scan_id,merge_fixture WHERE f.client_message_id::TEXT LIKE '00000000-0000-4000-8000-00000000fb3%'),'all fences follow canonical scan owner through actual merge');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.ai_quota_reservations WHERE request_id IN('00000000-0000-4000-8000-00000000fb31','00000000-0000-4000-8000-00000000fb33')),0,'both sides of protected quota collisions retire');
SELECT extensions.ok((SELECT message_bound AND message_id IS NULL FROM internal.insight_chat_execution_fences WHERE scan_id='00000000-0000-4000-8000-00000000fb12'),'duplicate message deletion retires original binding without aborting merge');
SELECT extensions.ok((SELECT state='committed' AND user_id=target FROM internal.ai_quota_reservations,merge_fixture WHERE request_id='00000000-0000-4000-8000-00000000fb32'),'committed quota ownership can move after duplicate message deletion');
SELECT extensions.is((SELECT public.reserve_protected_insight_chat_quota(target,'00000000-0000-4000-8000-00000000fb11','00000000-0000-4000-8000-00000000fb31','Question',NULL,1,repeat('b',64)) FROM merge_fixture),'{"status":"held"}'::JSONB,'merged pre-admission collision remains held');
SELECT extensions.ok((SELECT result.is_replay AND result.context_snapshot=(SELECT context->'context_snapshot' FROM source_context WHERE n=4) FROM merge_fixture,source_quota,LATERAL public.reserve_protected_insight_chat_send_with_context(target,gen_random_uuid(),'00000000-0000-4000-8000-00000000fb14','Question','00000000-0000-4000-8000-00000000fb34',NULL,1,(source_quota.result->>'reservation_id')::UUID,(source_quota.result->>'lease_token')::UUID) result WHERE n=4),'nonduplicate context and binding survive actual account merge unchanged');
SELECT extensions.throws_ok($$UPDATE internal.insight_chat_execution_fences SET request_sha256=repeat('0',64) WHERE scan_id='00000000-0000-4000-8000-00000000fb14'$$,'55000','field_chat_execution_immutable','request evidence immutable even for internal writers');
SELECT extensions.lives_ok('SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()','scan-derived ownership adds no unclassified user FK');
SELECT extensions.ok((SELECT bool_and(public.reserve_protected_insight_chat_quota(target,s.id,'00000000-0000-4000-8000-00000000fb33','Question',NULL,1,repeat('b',64))='{"status":"held"}'::JSONB) FROM merge_fixture,public.scans s WHERE s.id IN('00000000-0000-4000-8000-00000000fb13','00000000-0000-4000-8000-00000000fb21')),'both colliding protected scans stay held after merge');
SELECT * FROM extensions.finish();
ROLLBACK;

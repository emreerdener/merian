\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN NO ADMISSION HELPERS
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
 UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE,chat_execution_enabled=TRUE,reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
 UPDATE internal.field_chat_admission_cutover SET seeded_at=now()-interval '2 days',not_before_utc=now()-interval '1 day',beta_early_activation_at=NULL,beta_original_not_before_utc=NULL,
 activated_at=NULL,activated_candidate_sha=NULL,activated_migration_sha256=NULL,
 activated_explore_bundle_sha256=NULL,activated_insight_bundle_sha256=NULL,activated_species_dictionary_bundle_sha256=NULL;
 PERFORM public.activate_field_chat_admission_cutover(repeat('a',40),repeat('b',64),repeat('c',64),repeat('d',64),repeat('e',64));
 UPDATE internal.ai_quota_policies SET daily_limit=1000,user_window_limit=1000,ip_window_limit=1000 WHERE operation='insight_chat_reply' AND allowed;
END;
$$;
-- END NO ADMISSION HELPERS
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
CREATE TEMP TABLE seal_fixture AS SELECT
 '00000000-0000-4000-8000-00000000ac01'::UUID owner,
 ('00000000-0000-4000-8000-00000000ac1'||n)::UUID scan,
 ('00000000-0000-4000-8000-00000000ac2'||n)::UUID request,
 ('00000000-0000-4000-8000-00000000ac3'||n)::UUID conversation,n FROM generate_series(1,4) n;
SELECT pg_temp.seed_fenced_chat(owner,scan) FROM seal_fixture;
SELECT pg_temp.open_fenced_chat();
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ac01"}',TRUE);
SELECT public.enroll_owned_observation_history(scan,9) FROM seal_fixture WHERE n=1;
CREATE TEMP TABLE seal_ticket AS SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) ticket
 FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id
 WHERE h.observation_id=(SELECT scan FROM seal_fixture WHERE n=1);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
CREATE FUNCTION pg_temp.seal_chat(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.seal_unadmitted_insight_chat_request(owner,scan,conversation,request,'Question',
 CASE WHEN n=1 THEN (SELECT ticket FROM seal_ticket) ELSE 'null'::JSONB END,1) FROM seal_fixture WHERE seal_fixture.n=$1;
$$;
SELECT extensions.ok(has_function_privilege('service_role','public.seal_unadmitted_insight_chat_request(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.seal_unadmitted_insight_chat_request(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.seal_unadmitted_insight_chat_request(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE'),'seal service-only');
CREATE FUNCTION pg_temp.read_seal(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.get_insight_chat_no_admission(owner,scan,conversation,request,'Question',
 CASE WHEN n=1 THEN (SELECT ticket FROM seal_ticket) ELSE 'null'::JSONB END,1) FROM seal_fixture WHERE seal_fixture.n=$1;
$$;
SELECT extensions.ok(has_function_privilege('service_role','public.get_insight_chat_no_admission(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.get_insight_chat_no_admission(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_insight_chat_no_admission(uuid,uuid,uuid,uuid,text,jsonb,integer)','EXECUTE'),'proof recovery is service-only');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
SELECT extensions.is(pg_temp.read_seal(1),'{"status":"fresh_candidate"}'::JSONB,'fresh read has no gates or authority derivation');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=TRUE,chat_context_enabled=TRUE;
SELECT extensions.is(pg_temp.seal_chat(1),'{"status":"held"}'::JSONB,'current ticket is not denial proof');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences WHERE scan_id IN(SELECT scan FROM seal_fixture)),0,'held probe creates no seal');
UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id=(SELECT scan FROM seal_fixture WHERE n=1);
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE;
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(1)','55000','field_chat_execution_unavailable','closed gate cannot create denial proof');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=TRUE;
UPDATE internal.observation_history_rollout SET chat_context_enabled=FALSE;
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(1)','55000','field_chat_context_unavailable','closed context gate cannot create proof');
UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE;
CREATE TEMP TABLE sealed AS SELECT pg_temp.seal_chat(1) receipt;
SELECT extensions.is((SELECT receipt FROM sealed),(SELECT jsonb_build_object('status','not_admitted','context_version',1,'scan_id',scan,'conversation_id',conversation,'client_message_id',request,'reason','displayed_identification_changed') FROM seal_fixture WHERE n=1),'exact immutable closed denial receipt');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_messages WHERE user_id='00000000-0000-4000-8000-00000000ac01'),0,'seal consumes no message');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.ai_quota_reservations WHERE user_id='00000000-0000-4000-8000-00000000ac01'),0,'seal consumes no quota');
SELECT extensions.throws_ok($$SELECT * FROM seal_fixture,LATERAL public.reserve_insight_chat_send_with_context(owner,conversation,scan,'Question',request,(SELECT ticket FROM seal_ticket),1) WHERE n=1$$,'55000','field_chat_not_admitted','unfunded context writer cannot bypass seal');
SELECT extensions.throws_ok($$SELECT * FROM seal_fixture,LATERAL public.reserve_protected_insight_chat_send_with_context(owner,conversation,scan,'Question',request,(SELECT ticket FROM seal_ticket),1,gen_random_uuid(),gen_random_uuid()) WHERE n=1$$,'55000','field_chat_execution_held','fabricated funding cannot bypass seal');
SELECT extensions.throws_ok($$SELECT public.admit_insight_chat_local_refusal(owner,conversation,scan,'Question',request,(SELECT ticket FROM seal_ticket),1,'foraging_or_ingestion') FROM seal_fixture WHERE n=1$$,'55000','field_chat_execution_held','local refusal cannot recast seal');
SELECT extensions.throws_ok($$SELECT * FROM seal_fixture,LATERAL public.reserve_ai_quota(owner,'insight_chat_reply',request,repeat('a',64)) WHERE n=1$$,'55000','field_chat_not_admitted','generic quota insert cannot bind sealed NULL reservation');
SELECT public.reserve_ai_quota('00000000-0000-4000-8000-00000000ac01','insight_chat_reply','00000000-0000-4000-8000-00000000ac99',repeat('b',64));
SELECT extensions.throws_ok($$UPDATE internal.ai_quota_reservations SET request_id=(SELECT request FROM seal_fixture WHERE n=1) WHERE request_id='00000000-0000-4000-8000-00000000ac99'$$,'55000','field_chat_not_admitted','UPDATE cannot disguise an existing quota as a sealed request');
SELECT extensions.throws_ok($$UPDATE internal.insight_chat_execution_fences SET no_admission_reason=NULL,no_admission_conversation_id=NULL WHERE scan_id=(SELECT scan FROM seal_fixture WHERE n=1)$$,'55000','field_chat_execution_immutable','terminal seal is immutable');
SELECT extensions.throws_ok($$SELECT public.seal_unadmitted_insight_chat_request(owner,scan,conversation,request,'Changed',(SELECT ticket FROM seal_ticket),1) FROM seal_fixture WHERE n=1$$,'23505','field_chat_idempotency_conflict','changed text conflicts');
SELECT extensions.throws_ok($$SELECT public.seal_unadmitted_insight_chat_request(owner,scan,gen_random_uuid(),request,'Question',(SELECT ticket FROM seal_ticket),1) FROM seal_fixture WHERE n=1$$,'23505','field_chat_idempotency_conflict','changed proposed conversation conflicts');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
SELECT extensions.is(pg_temp.read_seal(1),(SELECT receipt FROM sealed),'read-only recovery returns original proof before fresh gates');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_no_admission(owner,(SELECT scan FROM seal_fixture WHERE n=2),conversation,request,'Question',(SELECT ticket FROM seal_ticket),1) FROM seal_fixture WHERE n=1$$,'23505','field_chat_idempotency_conflict','read recovery never treats another scan request as fresh');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_no_admission(owner,scan,gen_random_uuid(),request,'Question',(SELECT ticket FROM seal_ticket),1) FROM seal_fixture WHERE n=1$$,'23505','field_chat_idempotency_conflict','read proof requires exact proposed conversation');
SELECT extensions.is(pg_temp.seal_chat(1),(SELECT receipt FROM sealed),'original receipt recovers before fresh gates');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=TRUE,chat_context_enabled=TRUE;
SELECT public.reserve_protected_insight_chat_quota(owner,scan,request,'Question',NULL,1,repeat('a',64)) FROM seal_fixture WHERE n=2;
SELECT extensions.is(pg_temp.read_seal(2),'{"status":"held"}'::JSONB,'nonterminal attempt cannot become fresh or terminal proof');
SELECT extensions.is(pg_temp.seal_chat(2),'{"status":"held"}'::JSONB,'existing reservation never becomes no-admission proof');
INSERT INTO internal.observation_histories(observation_id) SELECT scan FROM seal_fixture WHERE n=3;
SELECT extensions.is(pg_temp.read_seal(3),'{"status":"fresh_candidate"}'::JSONB,'read recovery never derives damaged current authority');
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(3)','55000','field_chat_context_unavailable','damaged authority is not stale-ticket proof');
SELECT public.reserve_ai_quota(owner,'insight_chat_reply',request,repeat('f',64)) FROM seal_fixture WHERE n=3;
SELECT extensions.is(pg_temp.read_seal(3),'{"status":"held"}'::JSONB,'quota without a fence remains held');
DELETE FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM seal_fixture WHERE n=3);
INSERT INTO public.insight_chat_conversations(id,user_id,scan_id)
 SELECT conversation,owner,scan FROM seal_fixture WHERE n=2;
INSERT INTO public.insight_chat_messages(conversation_id,user_id,scan_id,role,message_text,safety_metadata)
 SELECT conversation,owner,scan,'assistant','Synthetic recovery evidence',jsonb_build_object('request_id',(SELECT request FROM seal_fixture WHERE n=3)) FROM seal_fixture WHERE n=2;
SELECT extensions.is(pg_temp.read_seal(3),'{"status":"held"}'::JSONB,'assistant evidence on another owned scan is not a fresh candidate');
DELETE FROM public.scans WHERE id=(SELECT scan FROM seal_fixture WHERE n=4);
SELECT extensions.throws_ok('SELECT pg_temp.read_seal(4)','P0002','field_chat_subject_not_found','deleted subject blocks read proof');
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(4)','P0002','field_chat_subject_not_found','deleted observation wins');
SELECT extensions.throws_ok($$SELECT public.seal_unadmitted_insight_chat_request(gen_random_uuid(),scan,conversation,request,'Question',(SELECT ticket FROM seal_ticket),1) FROM seal_fixture WHERE n=1$$,'P0002','field_chat_subject_not_found','unknown owner denied before recovery');
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11');
-- A different account may have used the same UUID; do not erase its attempt
-- or let canonical reparenting silently merge that attempt into a terminal seal.
SELECT public.reserve_ai_quota('00000000-0000-4000-8000-00000000ad01','insight_chat_reply',(SELECT request FROM seal_fixture WHERE n=1),repeat('c',64));
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000ac01','00000000-0000-4000-8000-00000000ad01')$$,'55000','field_chat_execution_merge_conflict','merge collision fails atomically without erasing another attempt');
SELECT extensions.is((SELECT user_id FROM public.scans WHERE id=(SELECT scan FROM seal_fixture WHERE n=1)),'00000000-0000-4000-8000-00000000ac01'::UUID,'failed merge preserves original seal owner');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.ai_quota_reservations WHERE user_id='00000000-0000-4000-8000-00000000ad01' AND request_id=(SELECT request FROM seal_fixture WHERE n=1)),1,'failed merge preserves target attempt');
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ac01')$$,'55000','field_chat_execution_merge_conflict','reverse merge preserves the same conflict');
SELECT extensions.ok(EXISTS(SELECT 1 FROM public.users WHERE id='00000000-0000-4000-8000-00000000ac01') AND EXISTS(SELECT 1 FROM public.users WHERE id='00000000-0000-4000-8000-00000000ad01'),'both profiles survive failed merge');
-- Fixture-only removal models an independent collision-free merge, not a
-- production remediation path or permission to delete operational evidence.
DELETE FROM internal.ai_quota_reservations WHERE user_id='00000000-0000-4000-8000-00000000ad01' AND request_id=(SELECT request FROM seal_fixture WHERE n=1);
INSERT INTO internal.insight_chat_execution_fences(scan_id,client_message_id,request_sha256,no_admission_reason,no_admission_conversation_id)
 SELECT '00000000-0000-4000-8000-00000000ad11',request,repeat('d',64),'displayed_identification_changed',conversation FROM seal_fixture WHERE n=1;
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000ac01','00000000-0000-4000-8000-00000000ad01')$$,'55000','field_chat_execution_merge_conflict','two seals cannot collapse into an ambiguous owner/request');
DELETE FROM internal.insight_chat_execution_fences WHERE scan_id='00000000-0000-4000-8000-00000000ad11';
INSERT INTO public.insight_chat_conversations(id,user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000ad31','00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11');
INSERT INTO public.insight_chat_messages(conversation_id,user_id,scan_id,role,message_text,safety_metadata)
 SELECT '00000000-0000-4000-8000-00000000ad31','00000000-0000-4000-8000-00000000ad01','00000000-0000-4000-8000-00000000ad11','assistant','Synthetic retained answer',jsonb_build_object('request_id',request) FROM seal_fixture WHERE n=1;
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000ac01','00000000-0000-4000-8000-00000000ad01')$$,'55000','field_chat_execution_merge_conflict','assistant-only evidence also prevents merge');
DELETE FROM public.insight_chat_conversations WHERE id='00000000-0000-4000-8000-00000000ad31';
SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000ac01','00000000-0000-4000-8000-00000000ad01');
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(1)','P0002','field_chat_subject_not_found','old owner cannot recover merged receipt');
UPDATE seal_fixture SET owner='00000000-0000-4000-8000-00000000ad01';
SELECT extensions.is(pg_temp.read_seal(1),(SELECT receipt FROM sealed),'exact read follows current merged owner');
SELECT extensions.is(pg_temp.seal_chat(1),(SELECT receipt FROM sealed),'seal follows actual account merge without rewriting evidence');
SELECT extensions.throws_ok($$SELECT public.seal_unadmitted_insight_chat_request(owner,'00000000-0000-4000-8000-00000000ad11',conversation,request,'Question',NULL,1) FROM seal_fixture WHERE n=1$$,'23505','field_chat_idempotency_conflict','merged request cannot move to another scan');
DELETE FROM public.scans WHERE id=(SELECT scan FROM seal_fixture WHERE n=1);
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_execution_fences WHERE scan_id=(SELECT scan FROM seal_fixture WHERE n=1)),0,'deletion cascades private seal');
SELECT extensions.throws_ok('SELECT pg_temp.seal_chat(1)','P0002','field_chat_subject_not_found','deleted receipt never recovers');
SELECT * FROM extensions.finish();
ROLLBACK;

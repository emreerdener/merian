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
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb01');
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb02');
SELECT pg_temp.open_fenced_chat();
CREATE FUNCTION pg_temp.refuse(request UUID, reason TEXT DEFAULT 'dangerous_handling',scan UUID DEFAULT '00000000-0000-4000-8000-00000000eb01',question TEXT DEFAULT 'Question')
RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.admit_insight_chat_local_refusal('00000000-0000-4000-8000-00000000ea01',gen_random_uuid(),scan,question,request,NULL,1,reason); $$;
CREATE TEMP TABLE saved AS SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec01') receipt;
CREATE FUNCTION pg_temp.read_completion(request UUID DEFAULT '00000000-0000-4000-8000-00000000ec01') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.get_insight_chat_turn_completion('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb01',request,'Question',NULL,1,m.id,m.conversation_id)
 FROM public.insight_chat_messages m WHERE user_id='00000000-0000-4000-8000-00000000ea01' AND role='user' AND client_message_id=request;
$$;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_messages WHERE user_id='00000000-0000-4000-8000-00000000ea01'),2,'fresh refusal creates exactly question and answer');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.insight_chat_turn_contexts c JOIN public.insight_chat_messages m ON m.id=c.message_id WHERE user_id='00000000-0000-4000-8000-00000000ea01'),1,'one immutable context');
SELECT extensions.is((SELECT sum(admitted_count)::INTEGER FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000ea01'),1,'one normal chat slot');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.ai_quota_reservations WHERE user_id='00000000-0000-4000-8000-00000000ea01'),0,'no provider quota');
SELECT extensions.is(pg_temp.read_completion(),(SELECT receipt FROM saved),'exact completion read matches atomic refusal');
SELECT extensions.is(pg_temp.refuse('00000000-0000-4000-8000-00000000ec01'),(SELECT receipt FROM saved),'same ID replay returns original receipt');
SELECT extensions.ok((SELECT (receipt->'message')-ARRAY['id','conversation_id','scan_id','role','text','client_message_id','model','is_refusal','refusal_reason','created_at']='{}'::JSONB FROM saved),'receipt exposes only ten public fields');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec01','medical_or_veterinary')$$,'55000','field_chat_completion_held','changed reason cannot rewrite completed refusal');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec01','dangerous_handling','00000000-0000-4000-8000-00000000eb02')$$,'55000','field_chat_execution_held','same owner request cannot move to another scan');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec01','dangerous_handling','00000000-0000-4000-8000-00000000eb01','Changed')$$,'23505','field_chat_idempotency_conflict','changed question conflicts');
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
UPDATE public.scans SET ai_reasoning='New mutable reasoning' WHERE id='00000000-0000-4000-8000-00000000eb01';
SELECT extensions.is(pg_temp.refuse('00000000-0000-4000-8000-00000000ec01'),(SELECT receipt FROM saved),'replay ignores closed gates and changed mutable context');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec02')$$,'55000','field_chat_execution_unavailable','fresh refusal remains default gated');
SELECT pg_temp.open_fenced_chat();
-- A deliberate assistant write failure must roll back every part of admission.
CREATE FUNCTION pg_temp.deny_answer() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN IF NEW.role='assistant' THEN RAISE EXCEPTION 'synthetic_write_failure' USING ERRCODE='P0001'; END IF; RETURN NEW; END; $$;
CREATE TRIGGER test_deny_answer BEFORE INSERT ON public.insight_chat_messages FOR EACH ROW EXECUTE FUNCTION pg_temp.deny_answer();
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec02')$$,'P0001','synthetic_write_failure','failed answer rolls back transaction');
DROP TRIGGER test_deny_answer ON public.insight_chat_messages;
SELECT extensions.is((SELECT sum(admitted_count)::INTEGER FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000ea01'),1,'failed answer consumes no daily slot');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000ec02'),'failed answer leaves no question');
-- Existing incomplete immutable provider-style turn must never become a refusal.
SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000ea01',gen_random_uuid(),'00000000-0000-4000-8000-00000000eb01','Question','00000000-0000-4000-8000-00000000ec03',NULL,1);
SELECT extensions.is(pg_temp.read_completion('00000000-0000-4000-8000-00000000ec03'),'{"context_version":1,"completed":false}'::JSONB,'exact incomplete turn has no completion authority');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec03')$$,'55000','field_chat_completion_held','incomplete old turn never filled with refusal');
INSERT INTO public.insight_chat_messages(id,conversation_id,user_id,scan_id,role,message_text,safety_metadata)
 SELECT internal.insight_chat_assistant_id(conversation_id,client_message_id),conversation_id,user_id,scan_id,'assistant','Provider answer',jsonb_build_object('request_id',client_message_id) FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000ec03';
SELECT extensions.is(pg_temp.read_completion('00000000-0000-4000-8000-00000000ec03')#>>'{message,text}','Provider answer','exact provider-style receipt can be read');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec03')$$,'55000','field_chat_completion_held','provider answer cannot become refusal');
-- Missing private context never borrows the mutable scan.
DELETE FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT id FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000ec03');
SELECT extensions.throws_ok($$SELECT pg_temp.read_completion('00000000-0000-4000-8000-00000000ec03')$$,'55000','field_chat_context_missing','missing context holds even with assistant');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.get_insight_chat_turn_completion(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.admit_insight_chat_local_refusal(uuid,uuid,uuid,text,uuid,jsonb,integer,text)','EXECUTE'),'exposed routines deny app roles');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.insight_chat_completion_receipt(uuid,uuid,uuid,uuid,uuid,jsonb)','EXECUTE') AND NOT has_function_privilege('service_role','internal.insight_chat_refusal_text(text)','EXECUTE'),'private helpers have no API execute');
-- Wrong expected user identity and malformed saved context fail closed.
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_completion('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb01','00000000-0000-4000-8000-00000000ec01','Question',NULL,1,gen_random_uuid(),(SELECT (receipt#>>'{message,conversation_id}')::UUID FROM saved))$$,'55000','field_chat_context_missing','wrong user receipt cannot recover answer');
INSERT INTO internal.insight_chat_turn_contexts(message_id,context_version,displayed_ticket,context_snapshot)
 SELECT id,1,'null','{}' FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000ec03';
SELECT extensions.throws_ok($$SELECT pg_temp.read_completion('00000000-0000-4000-8000-00000000ec03')$$,'55000','field_chat_context_missing','malformed context remains held');
SELECT public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ec04','Question',NULL,1,repeat('a',64));
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec04','dangerous_handling','00000000-0000-4000-8000-00000000eb02')$$,'55000','field_chat_execution_held','prior quota cannot become local refusal');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec04')$$,'55000','field_chat_execution_held','other-scan execution fence denies same request');
SELECT public.request_scan_deletion('00000000-0000-4000-8000-00000000eb01','00000000-0000-4000-8000-00000000ea01');
SELECT extensions.throws_ok('SELECT pg_temp.read_completion()','P0002','field_chat_subject_not_found','deletion wins over completion');
SELECT extensions.throws_ok($$SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec01')$$,'P0002','field_chat_subject_not_found','deletion wins over refusal replay');
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000eb01';
-- A surviving message graph follows its actual account merge without changing IDs.
SELECT pg_temp.refuse('00000000-0000-4000-8000-00000000ec05','dangerous_handling','00000000-0000-4000-8000-00000000eb02');
CREATE TEMP TABLE merge_before AS SELECT public.get_insight_chat_turn_completion(user_id,scan_id,client_message_id,message_text,NULL,1,id,conversation_id) receipt,id,conversation_id FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000ec05';
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ea02','00000000-0000-4000-8000-00000000eb03');
SET CONSTRAINTS ALL DEFERRED;
SELECT internal.merge_ghost_chat_conversations('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000ea02');
UPDATE public.scans SET user_id='00000000-0000-4000-8000-00000000ea02' WHERE user_id='00000000-0000-4000-8000-00000000ea01';
UPDATE public.insight_chat_conversations SET user_id='00000000-0000-4000-8000-00000000ea02' WHERE user_id='00000000-0000-4000-8000-00000000ea01';
UPDATE public.insight_chat_messages SET user_id='00000000-0000-4000-8000-00000000ea02' WHERE user_id='00000000-0000-4000-8000-00000000ea01';
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.is((SELECT public.get_insight_chat_turn_completion('00000000-0000-4000-8000-00000000ea02','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ec05','Question',NULL,1,id,conversation_id) FROM merge_before),(SELECT receipt FROM merge_before),'new owner recovers unchanged surviving receipt after merge');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_completion('00000000-0000-4000-8000-00000000ea01','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ec05','Question',NULL,1,id,conversation_id) FROM merge_before$$,'P0002','field_chat_subject_not_found','old owner cannot recover merged receipt');
-- Duplicate source user/context is removed by conversation merge, not guessed.
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000ea03','00000000-0000-4000-8000-00000000eb04');
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO public.insight_chat_conversations(id,scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ea03');
INSERT INTO public.insight_chat_messages(conversation_id,scan_id,user_id,role,message_text,client_message_id)
 VALUES('00000000-0000-4000-8000-00000000ed01','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ea03','user','Question','00000000-0000-4000-8000-00000000ec05');
SELECT internal.merge_ghost_chat_conversations('00000000-0000-4000-8000-00000000ea02','00000000-0000-4000-8000-00000000ea03');
UPDATE public.scans SET user_id='00000000-0000-4000-8000-00000000ea03' WHERE user_id='00000000-0000-4000-8000-00000000ea02';
UPDATE public.insight_chat_conversations SET user_id='00000000-0000-4000-8000-00000000ea03' WHERE user_id='00000000-0000-4000-8000-00000000ea02';
UPDATE public.insight_chat_messages SET user_id='00000000-0000-4000-8000-00000000ea03' WHERE user_id='00000000-0000-4000-8000-00000000ea02';
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT id FROM merge_before)),'duplicate source context cascades');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_completion('00000000-0000-4000-8000-00000000ea03','00000000-0000-4000-8000-00000000eb02','00000000-0000-4000-8000-00000000ec05','Question',NULL,1,id,conversation_id) FROM merge_before$$,'55000','field_chat_context_missing','duplicate target cannot borrow erased source context');
SELECT * FROM extensions.finish();
ROLLBACK;

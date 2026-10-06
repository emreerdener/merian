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
CREATE TEMP TABLE fixture AS SELECT n,('00000000-0000-4000-8000-00000000ba0'||n)::UUID scan,('00000000-0000-4000-8000-00000000bb0'||n)::UUID request FROM generate_series(1,7)n;
SELECT pg_temp.seed_fenced_chat('00000000-0000-4000-8000-00000000bc01',scan) FROM fixture;
SELECT pg_temp.open_fenced_chat();
SELECT public.reserve_protected_insight_chat_quota('00000000-0000-4000-8000-00000000bc01',scan,request,'Question',NULL,1,repeat('a',64)) FROM fixture;
SELECT * FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=fixture.scan,
 LATERAL public.reserve_protected_insight_chat_send_with_context('00000000-0000-4000-8000-00000000bc01',gen_random_uuid(),scan,'Question',request,NULL,1,f.reservation_id,f.lease_token) a;
CREATE TEMP TABLE reply AS SELECT '{"answer":"Synthetic answer","model":"gemini-2.5-flash","is_refusal":false,"refusal_reason":null,"usage":{"prompt_tokens":10,"candidate_tokens":5,"thinking_tokens":0,"cached_tokens":0,"total_tokens":15,"modality_breakdown":{"prompt":{"text":10},"cached":{},"candidates":{"text":5},"tool":{}}}}'::JSONB data;
CREATE FUNCTION pg_temp.dispatch(n INTEGER) RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.grant_protected_insight_chat_dispatch('00000000-0000-4000-8000-00000000bc01',scan,request,f.reservation_id,f.lease_token) FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=scan WHERE fixture.n=$1; $$;
CREATE FUNCTION pg_temp.complete_reply(n INTEGER,payload JSONB DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.complete_protected_insight_chat_reply('00000000-0000-4000-8000-00000000bc01',scan,request,'Question',NULL,1,f.message_id,m.conversation_id,f.reservation_id,f.lease_token,COALESCE(payload,(SELECT data FROM reply)))
 FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=scan JOIN public.insight_chat_messages m ON m.id=f.message_id WHERE fixture.n=$1;
$$;
CREATE FUNCTION pg_temp.recover_reply(n INTEGER,payload JSONB DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.get_protected_insight_chat_reply('00000000-0000-4000-8000-00000000bc01',scan,request,'Question',NULL,1,f.message_id,m.conversation_id,f.reservation_id,f.lease_token,COALESCE(payload,(SELECT data FROM reply)))
 FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=scan JOIN public.insight_chat_messages m ON m.id=f.message_id WHERE fixture.n=$1;
$$;
SELECT extensions.throws_ok('SELECT pg_temp.complete_reply(1)','55000','field_chat_execution_held','no reply write before original dispatch');
SELECT pg_temp.dispatch(n) FROM fixture;
CREATE TEMP TABLE saved AS SELECT pg_temp.complete_reply(1) receipt;
SELECT extensions.is((SELECT receipt#>>'{message,text}' FROM saved),'Synthetic answer','original committed attempt persists reply');
SELECT extensions.is(pg_temp.complete_reply(1),(SELECT receipt FROM saved),'exact repeat returns original receipt');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.ai_usage_events WHERE source_id=(SELECT (receipt#>>'{message,id}')::UUID FROM saved)),1,'reply usage ledger emitted once');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(1,(SELECT jsonb_set(data,'{answer}','"Changed"') FROM reply))$$,'23505','field_chat_reply_conflict','different answer never overwrites');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(1,(SELECT jsonb_set(data,'{usage,prompt_tokens}','11') FROM reply))$$,'23505','field_chat_reply_conflict','different accounting never overwrites');
SELECT extensions.throws_ok($$SELECT public.complete_protected_insight_chat_reply('00000000-0000-4000-8000-00000000bc01',scan,request,'Question',NULL,1,f.message_id,m.conversation_id,f.reservation_id,gen_random_uuid(),(SELECT data FROM reply)) FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=scan JOIN public.insight_chat_messages m ON m.id=f.message_id WHERE n=1$$,'55000','field_chat_execution_held','wrong original lease cannot adopt completion');
DELETE FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM fixture WHERE n IN(1));
UPDATE internal.observation_history_rollout SET chat_execution_enabled=FALSE,chat_context_enabled=FALSE;
SELECT extensions.is(pg_temp.complete_reply(1),(SELECT receipt FROM saved),'original receipt recovers after quota prune and closed gates');
SELECT extensions.is(pg_temp.recover_reply(1),(SELECT receipt FROM saved),'exact full payload recovery survives quota pruning');
SELECT extensions.throws_ok($$SELECT pg_temp.recover_reply(1,(SELECT jsonb_set(data,'{usage,prompt_tokens}','11') FROM reply))$$,'23505','field_chat_reply_conflict','public-equivalent answer cannot recover different private usage');
SELECT extensions.is(pg_temp.recover_reply(2)->>'completed','false','missing exact answer is read-only absence, never dispatch authority');
DELETE FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM fixture WHERE n=2);
SELECT extensions.throws_ok('SELECT pg_temp.complete_reply(2)','55000','field_chat_execution_held','pruned quota cannot authorize missing reply');
UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-interval '1 hour' WHERE request_id=(SELECT request FROM fixture WHERE n=3);
SELECT extensions.lives_ok('SELECT pg_temp.complete_reply(3)','original dispatched completion survives lease expiry and closed gate');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(4,(SELECT jsonb_set(data,'{usage,prompt_tokens}','-1') FROM reply))$$,'22023','field_chat_invalid_reply','negative token count denied');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(4,(SELECT jsonb_set(data,'{usage,total_tokens}','2147483648') FROM reply))$$,'22023','field_chat_invalid_reply','overflow token count denied');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(4,(SELECT jsonb_set(data,'{usage,modality_breakdown,prompt,private_payload}','1') FROM reply))$$,'22023','field_chat_invalid_reply','arbitrary usage keys denied');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(4,(SELECT data||'{"debug":"private"}' FROM reply))$$,'22023','field_chat_invalid_reply','additive reply payload denied');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(4,(SELECT jsonb_set(data,'{model}','"other-model"') FROM reply))$$,'22023','field_chat_invalid_reply','unapproved model denied');
DELETE FROM internal.insight_chat_turn_contexts WHERE message_id=(SELECT f.message_id FROM fixture JOIN internal.insight_chat_execution_fences f ON f.scan_id=scan WHERE n=4);
SELECT extensions.throws_ok('SELECT pg_temp.complete_reply(4)','55000','field_chat_context_missing','missing admitted context cannot persist answer');
CREATE FUNCTION pg_temp.deny_touch() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic_touch_failure' USING ERRCODE='P0001'; END; $$;
CREATE TRIGGER test_deny_touch BEFORE UPDATE ON public.insight_chat_conversations FOR EACH ROW EXECUTE FUNCTION pg_temp.deny_touch();
SELECT extensions.throws_ok('SELECT pg_temp.complete_reply(5)','P0001','synthetic_touch_failure','failed touch rolls back answer and usage ledger');
DROP TRIGGER test_deny_touch ON public.insight_chat_conversations;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_messages WHERE scan_id=(SELECT scan FROM fixture WHERE n=5) AND role='assistant'),0,'failed completion leaves no assistant');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.ai_usage_events WHERE scan_id=(SELECT scan FROM fixture WHERE n=5)),0,'failed completion leaves no usage record');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id=(SELECT request FROM fixture WHERE n=5)),'committed','failed persistence does not refund original dispatch');
SELECT extensions.lives_ok($$SELECT pg_temp.complete_reply(5,(SELECT jsonb_set(data,'{usage}','null') FROM reply))$$,'missing usage remains null while known dispatched model is retained');
SELECT extensions.is((SELECT model FROM public.insight_chat_messages WHERE scan_id=(SELECT scan FROM fixture WHERE n=5) AND role='assistant'),'gemini-2.5-flash','missing usage does not erase known provider attribution');
SELECT extensions.lives_ok($$SELECT pg_temp.complete_reply(6,(SELECT jsonb_set(jsonb_set(data,'{is_refusal}','true'),'{refusal_reason}','"provider_safety"') FROM reply))$$,'provider refusal is bound to original paid dispatch');
SELECT public.request_scan_deletion((SELECT scan FROM fixture WHERE n=7),'00000000-0000-4000-8000-00000000bc01');
SELECT extensions.throws_ok('SELECT pg_temp.complete_reply(7)','P0002','field_chat_subject_not_found','deletion fences new assistant');
SELECT extensions.throws_ok($$SELECT pg_temp.complete_reply(7,'{}')$$,'P0002','field_chat_subject_not_found','deleted owner denial precedes invalid reply');
SELECT extensions.throws_ok($$SELECT public.get_protected_insight_chat_reply('00000000-0000-4000-8000-00000000bc02',(SELECT scan FROM fixture WHERE n=1),(SELECT request FROM fixture WHERE n=1),'Question',NULL,1,NULL,NULL,NULL,NULL,'{}')$$,'P0002','field_chat_subject_not_found','wrong owner denial precedes payload validation');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.get_protected_insight_chat_reply(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),'exact private-payload recovery is service only');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.complete_protected_insight_chat_reply(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid,uuid,uuid,jsonb)','EXECUTE') AND has_function_privilege('service_role','public.complete_protected_insight_chat_reply(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),'completion service only');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.validate_protected_insight_chat_reply(jsonb)','EXECUTE'),'payload helper private');
SELECT * FROM extensions.finish();
ROLLBACK;

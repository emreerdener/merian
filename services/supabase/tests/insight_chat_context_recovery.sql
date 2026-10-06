\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.seed_chat_observation(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,ai_reasoning,user_observation_context)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/private.jpg'],0.9,TRUE,'flash','private','Original reasoning','{"free_text":"Recorded encounter","media":"do not retain"}');
END;
$$;
CREATE FUNCTION pg_temp.open_chat_fixture() RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 UPDATE internal.observation_history_rollout SET chat_context_enabled=TRUE,reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
 UPDATE internal.field_chat_admission_cutover SET seeded_at=now()-interval '2 days',not_before_utc=now()-interval '1 day',beta_early_activation_at=NULL,beta_original_not_before_utc=NULL,
 activated_at=NULL,activated_candidate_sha=NULL,activated_migration_sha256=NULL,
 activated_explore_bundle_sha256=NULL,activated_insight_bundle_sha256=NULL,activated_species_dictionary_bundle_sha256=NULL;
 PERFORM public.activate_field_chat_admission_cutover(repeat('a',40),repeat('b',64),repeat('c',64),repeat('d',64),repeat('e',64));
END;
$$;

SELECT extensions.ok(has_function_privilege('service_role','public.get_insight_chat_turn_context(uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.get_insight_chat_turn_context(uuid,uuid,uuid,text,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_insight_chat_turn_context(uuid,uuid,uuid,text,jsonb,integer)','EXECUTE'),'resolver is service-only');
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cc01',('00000000-0000-4000-8000-00000000cc1'||n)::UUID) FROM generate_series(1,3) n;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.is(public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Question',NULL,1),'{"context_version":1,"found":false}'::JSONB,'missing turn explicit even while gates closed; PostgREST SQL-null legacy ticket supported');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_conversations WHERE user_id='00000000-0000-4000-8000-00000000cc01'),0,'probe creates no conversation');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cc01'),0,'probe consumes no daily admission');
SELECT pg_temp.open_chat_fixture();
CREATE TEMP TABLE recovered_original AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cc01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cc11','Question','00000000-0000-4000-8000-00000000cc21','null',1);
SELECT public.reserve_field_chat_send('00000000-0000-4000-8000-00000000cc01',gen_random_uuid(),'insight','00000000-0000-4000-8000-00000000cc12','Old question','00000000-0000-4000-8000-00000000cc22');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000cc01"}',TRUE);
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000cc13',9);
CREATE TEMP TABLE recovery_ticket AS SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) ticket
 FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id
 WHERE h.observation_id='00000000-0000-4000-8000-00000000cc13';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
CREATE TEMP TABLE recovered_history AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cc01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cc13','History question','00000000-0000-4000-8000-00000000cc23',(SELECT ticket FROM recovery_ticket),1);
UPDATE internal.observation_history_rollout SET chat_context_enabled=FALSE,reader_enabled=FALSE;
UPDATE public.scans SET ai_reasoning='Changed parent' WHERE user_id='00000000-0000-4000-8000-00000000cc01';
UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000cc13';
CREATE TEMP TABLE recovered_read AS SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21',' Question ',NULL,1) result;
SELECT extensions.is((SELECT result->'context_snapshot' FROM recovered_read),(SELECT context_snapshot FROM recovered_original),'read retains original context despite mutable parent and closed gates');
SELECT extensions.is((SELECT result->'message'->>'id' FROM recovered_read),(SELECT message->>'id' FROM recovered_original),'read retains exact original message');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_messages WHERE user_id='00000000-0000-4000-8000-00000000cc01'),3,'read inserts no message');
SELECT extensions.is((SELECT admitted_count FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cc01'),3,'read does not consume admission');
SELECT extensions.is(public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc13','00000000-0000-4000-8000-00000000cc23','History question',(SELECT ticket FROM recovery_ticket),1)->'context_snapshot',(SELECT context_snapshot FROM recovered_history),'enrolled replay precedes newer current authority');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Different','null',1)$$,'23505','field_chat_idempotency_conflict','same ID cannot change text');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc13','00000000-0000-4000-8000-00000000cc23','History question','null',1)$$,'23505','field_chat_idempotency_conflict','same ID cannot drop ticket');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc12','00000000-0000-4000-8000-00000000cc22','Old question','null',1)$$,'55000','field_chat_context_missing','old uncontexted message holds without backfill');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11',gen_random_uuid(),'Question','{}',1)$$,'22023','field_chat_invalid_request','malformed ticket never becomes missing');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11',gen_random_uuid(),'Question','null',2)$$,'22023','field_chat_invalid_request','unsupported context version denied');
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cc02','00000000-0000-4000-8000-00000000cc18');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc02','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Question','null',1)$$,'P0002','field_chat_subject_not_found','other owner cannot probe');
SET CONSTRAINTS ALL DEFERRED;
SELECT internal.merge_ghost_chat_conversations('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc02');
UPDATE public.scans SET user_id='00000000-0000-4000-8000-00000000cc02' WHERE user_id='00000000-0000-4000-8000-00000000cc01';
UPDATE public.insight_chat_conversations SET user_id='00000000-0000-4000-8000-00000000cc02' WHERE user_id='00000000-0000-4000-8000-00000000cc01';
UPDATE public.insight_chat_messages SET user_id='00000000-0000-4000-8000-00000000cc02' WHERE user_id='00000000-0000-4000-8000-00000000cc01';
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.is(public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc02','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Question','null',1)->'context_snapshot',(SELECT context_snapshot FROM recovered_original),'new merged owner recovers original snapshot by message identity');
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc01','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Question','null',1)$$,'P0002','field_chat_subject_not_found','old merged owner loses access');
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000cc11';
SELECT extensions.throws_ok($$SELECT public.get_insight_chat_turn_context('00000000-0000-4000-8000-00000000cc02','00000000-0000-4000-8000-00000000cc11','00000000-0000-4000-8000-00000000cc21','Question','null',1)$$,'P0002','field_chat_subject_not_found','deletion wins over historical recovery');
SELECT * FROM extensions.finish();
ROLLBACK;

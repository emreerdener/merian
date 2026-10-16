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

SELECT extensions.ok(NOT has_function_privilege('service_role','internal.prepare_current_insight_chat_context(uuid,uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('authenticated','internal.prepare_current_insight_chat_context(uuid,uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','internal.prepare_current_insight_chat_context(uuid,uuid,jsonb,integer)','EXECUTE'),'private helper has no API grant');
SELECT extensions.ok(has_function_privilege('service_role','public.prepare_insight_chat_send_context(uuid,uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('authenticated','public.prepare_insight_chat_send_context(uuid,uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.prepare_insight_chat_send_context(uuid,uuid,jsonb,integer)','EXECUTE'),'preflight service-only');
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cd01',('00000000-0000-4000-8000-00000000cd1'||n)::UUID) FROM generate_series(1,4) n;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd11',NULL,1)$$,'55000','field_chat_context_unavailable','preflight remains default-off');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd11','{}',1)$$,'22023','field_chat_invalid_request','malformed ticket rejected');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd11',NULL,2)$$,'22023','field_chat_invalid_request','unsupported version rejected');
SELECT pg_temp.open_chat_fixture();
CREATE TEMP TABLE legacy_prepared AS SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd11',NULL,1) context;
SELECT extensions.ok((SELECT context->>'source_kind'='legacy_scan_v1' AND context->'displayed_ticket'='null'::JSONB AND context-ARRAY['context_version','source_kind','displayed_ticket','scan_context']='{}'::JSONB FROM legacy_prepared),'explicit SQL-null legacy produces closed context without prefix');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_conversations WHERE user_id='00000000-0000-4000-8000-00000000cd01'),0,'successful preflight creates no thread');
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cd01'),0,'successful preflight consumes no daily capacity');
CREATE TEMP TABLE legacy_admitted AS SELECT * FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cd01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cd11','Question','00000000-0000-4000-8000-00000000cd21',NULL,1);
SELECT extensions.is((SELECT context_snapshot-'conversation_prefix' FROM legacy_admitted),(SELECT context FROM legacy_prepared),'final SQL-null admission shares identical scan derivation');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000cd01"}',TRUE);
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000cd12',9);
CREATE TEMP TABLE preflight_ticket AS SELECT jsonb_build_object('analysis_id',h.selected_analysis_id,'state_revision',h.state_revision,'review_revision',a.review_revision) ticket FROM internal.observation_histories h JOIN internal.observation_analysis_authorities a ON a.observation_id=h.observation_id AND a.analysis_id=h.selected_analysis_id WHERE h.observation_id='00000000-0000-4000-8000-00000000cd12';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
UPDATE public.scans SET ai_reasoning='Mutable parent',weather_condition='Mutable weather' WHERE id='00000000-0000-4000-8000-00000000cd12';
CREATE TEMP TABLE enrolled_prepared AS SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd12',(SELECT ticket FROM preflight_ticket),1) context;
SELECT extensions.ok((SELECT context->>'source_kind'='analysis_history_v1' AND context#>>'{scan_context,ai_reasoning}'='Original reasoning' AND NOT (context->'scan_context')?'weather_condition' FROM enrolled_prepared),'historical import never borrows mutable missing encounter data');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd12',NULL,1)$$,'40001','field_chat_context_conflict','enrolled context cannot use legacy ticket');
UPDATE internal.observation_histories SET state_revision=state_revision+1 WHERE observation_id='00000000-0000-4000-8000-00000000cd12';
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cd01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cd12','Question',gen_random_uuid(),(SELECT ticket FROM preflight_ticket),1)$$,'40001','field_chat_context_conflict','final admission rechecks preflight after authority race');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd12',(SELECT ticket FROM preflight_ticket),1)$$,'40001','field_chat_context_conflict','stale preflight does not rebase');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_conversations WHERE scan_id='00000000-0000-4000-8000-00000000cd12'),0,'race denial rolls back empty thread');
SELECT extensions.is((SELECT admitted_count FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cd01'),1,'race denial consumes no additional capacity');
INSERT INTO internal.observation_histories(observation_id) VALUES('00000000-0000-4000-8000-00000000cd13');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd13',NULL,1)$$,'55000','field_chat_context_unavailable','damaged history never falls back');
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000cd14';
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd14',NULL,1)$$,'P0002','field_chat_subject_not_found','deleted subject denied');
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cd02','00000000-0000-4000-8000-00000000cd18');
SELECT extensions.throws_ok($$SELECT public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd02','00000000-0000-4000-8000-00000000cd11',NULL,1)$$,'P0002','field_chat_subject_not_found','foreign owner denied');
-- A valid bounded preflight can still exceed the final bound once its exact
-- conversation prefix is frozen. That denial must roll back the new send.
SELECT pg_temp.seed_chat_observation('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd15');
INSERT INTO public.species_dictionary(id,scientific_name,common_names,wikipedia_overview,habitat_description)
 VALUES('00000000-0000-4000-8000-00000000cd55','Preflight bound fixture','{"en":"Fixture"}',repeat('🌱',4000),repeat('🌱',4000));
UPDATE public.scans SET species_id='00000000-0000-4000-8000-00000000cd55',ai_reasoning=repeat('🌱',4000),semantic_location=repeat('🌱',4000),depth_scale_text=repeat('🌱',4000),weather_condition=repeat('🌱',4000) WHERE id='00000000-0000-4000-8000-00000000cd15';
SELECT extensions.ok(octet_length(public.prepare_insight_chat_send_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd15',NULL,1)::TEXT)<131072,'large fresh context fits before final prefix');
INSERT INTO public.insight_chat_conversations(id,user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000cd35','00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd15');
INSERT INTO public.insight_chat_messages(conversation_id,user_id,scan_id,role,message_text,created_at)
 SELECT '00000000-0000-4000-8000-00000000cd35','00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd15','assistant',repeat('🌱',900),now()-interval '1 hour'+n*interval '1 second' FROM generate_series(1,12) n;
SELECT extensions.throws_ok($$SELECT public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cd01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cd15','Question','00000000-0000-4000-8000-00000000cd25',NULL,1)$$,'55000','field_chat_context_unavailable','final exact prefix overflow uses stable denial');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.insight_chat_messages WHERE client_message_id='00000000-0000-4000-8000-00000000cd25'),0,'overflow rolls back admitted question');
SELECT extensions.is((SELECT admitted_count FROM internal.field_chat_daily_admissions WHERE user_id='00000000-0000-4000-8000-00000000cd01'),1,'overflow rolls back daily slot');
UPDATE internal.observation_history_rollout SET chat_context_enabled=FALSE;
SELECT extensions.ok((SELECT is_replay AND context_snapshot=(SELECT context_snapshot FROM legacy_admitted) FROM public.reserve_insight_chat_send_with_context('00000000-0000-4000-8000-00000000cd01',gen_random_uuid(),'00000000-0000-4000-8000-00000000cd11','Question','00000000-0000-4000-8000-00000000cd21',NULL,1)),'same-ID replay precedes fresh helper and closed gate');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.prepare_current_insight_chat_context('00000000-0000-4000-8000-00000000cd01','00000000-0000-4000-8000-00000000cd11',NULL,1)$$,'42501',NULL,'direct private helper execution denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

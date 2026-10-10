\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(25);
CREATE FUNCTION pg_temp.seed_saved_observation(owner_id UUID,observation UUID,has_primary BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/legacy-public.jpg'],0.9,TRUE,'flash','private',CASE WHEN has_primary THEN '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB END,CASE WHEN has_primary THEN '{"version":1,"resolution":"genus","scientific_name":"Savedfixture","common_name":null}'::JSONB END);
END;
$$;


SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11');
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000fa02','00000000-0000-4000-8000-00000000fa12');
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL
WHERE id IN ('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa02');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000fa11',9);
RESET ROLE;
CREATE TEMP TABLE preflight_request(value JSONB);
INSERT INTO preflight_request SELECT jsonb_build_object('schema_version',1,'observation_id',observation_id,
 'analysis_id','00000000-0000-4000-8000-00000000fa21','source_analysis_id',selected_analysis_id,
 'entitlement_protocol',3,'identification_protocol',6,'history_protocol',8)
FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
GRANT SELECT ON preflight_request TO authenticated;
CREATE TEMP TABLE preflight_result(value JSONB);
GRANT ALL ON preflight_result TO authenticated;
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_reanalysis_preflight(jsonb)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_owned_observation_reanalysis_preflight(jsonb)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.get_owned_observation_reanalysis_preflight(jsonb)','EXECUTE'),'only authenticated RPC grant');
SELECT extensions.ok(NOT (SELECT orchestration_enabled OR admission_enabled OR protected_analysis_enabled FROM internal.observation_history_rollout WHERE singleton),'all admission gates remain closed');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value) FROM preflight_request$$,'55000','analysis_history_unavailable','closed gates deny even owned source');
RESET ROLE;
UPDATE internal.observation_history_rollout SET orchestration_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE;
SELECT set_config('request.jwt.claims','{}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value) FROM preflight_request$$,'42501','authentication_required','missing caller denied');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"owner_id":"00000000-0000-4000-8000-00000000fa02"}') FROM preflight_request$$,'22023','invalid_analysis_history','owner injection denied');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"identification_protocol":5}') FROM preflight_request$$,'22023','invalid_analysis_history','legacy capability denied');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"source_analysis_id":null}') FROM preflight_request$$,'22023','invalid_analysis_history','source is required');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||jsonb_build_object('analysis_id',value->'source_analysis_id')) FROM preflight_request$$,'22023','invalid_analysis_history','child must differ from source');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"observation_id":"00000000-0000-4000-8000-00000000fa12"}') FROM preflight_request$$,'P0002','analysis_history_not_found','other owner hidden');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"source_analysis_id":"00000000-0000-4000-8000-00000000fa99"}') FROM preflight_request$$,'P0002','analysis_history_not_found','missing source denied');
INSERT INTO preflight_result SELECT public.get_owned_observation_reanalysis_preflight(value) FROM preflight_request;
SELECT extensions.is((SELECT value->>'decision' FROM preflight_result),'permission_required','no consent yields advisory permission state');
RESET ROLE;
INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
VALUES(gen_random_uuid(),'00000000-0000-4000-8000-00000000fa01','2026-08-03',now(),'self_attestation','I confirm I am 18 or older','ios','1.0.3','275');
INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
VALUES(gen_random_uuid(),'00000000-0000-4000-8000-00000000fa01','2026-08-03',now(),'I accept the terms and allow this data sharing','ios','1.0.3','275');
INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
VALUES(gen_random_uuid(),'00000000-0000-4000-8000-00000000fa01','google_gemini','2026-08-04.1','granted',now(),
 'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
 'I accept the terms and allow this data sharing','ios','1.0.3','275');
CREATE TEMP TABLE preflight_before AS SELECT
 (SELECT count(*) FROM internal.ai_quota_reservations) AS quota,
 (SELECT count(*) FROM internal.identification_provider_attempts) AS attempts,
 (SELECT count(*) FROM internal.complimentary_scan_usage) AS funding,
 (SELECT count(*) FROM internal.observation_analysis_intents) AS intents,
 (SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11') AS revision,
 (SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11') AS selected;
TRUNCATE preflight_result;
SET LOCAL ROLE authenticated;
INSERT INTO preflight_result SELECT public.get_owned_observation_reanalysis_preflight(value) FROM preflight_request;
SELECT extensions.is((SELECT value->>'decision' FROM preflight_result),'ready','current consent and policy resolve ready');
SELECT extensions.is((SELECT value->>'processor_permission' FROM preflight_result),'google_gemini','recipient comes from current photo policy');
SELECT extensions.ok((SELECT count(*)=8 FROM preflight_result,jsonb_object_keys(value)),'response is exactly eight public fields');
SELECT extensions.ok((SELECT r.value->'observation_id'=q.value->'observation_id'
 AND r.value->'analysis_id'=q.value->'analysis_id' AND r.value->'source_analysis_id'=q.value->'source_analysis_id'
 FROM preflight_result r,preflight_request q),'response binds all exact identities');
RESET ROLE;
SELECT extensions.ok((SELECT quota=(SELECT count(*) FROM internal.ai_quota_reservations)
 AND attempts=(SELECT count(*) FROM internal.identification_provider_attempts)
 AND funding=(SELECT count(*) FROM internal.complimentary_scan_usage)
 AND intents=(SELECT count(*) FROM internal.observation_analysis_intents)
 AND revision=(SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11')
 AND selected=(SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11')
 FROM preflight_before),'preflight changes no funding, attempt, intent, selection or revision');
-- Protected photo admission requires staged same-owner evidence; the older
-- description admission forbids it. This preview follows the photo contract.
INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,content_type,byte_count,sha256)
VALUES('00000000-0000-4000-8000-00000000fa41','00000000-0000-4000-8000-00000000fa11',
 '00000000-0000-4000-8000-00000000fa21','00000000-0000-4000-8000-00000000fa01','image/jpeg',16,repeat('a',64));
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT public.get_owned_observation_reanalysis_preflight(value)->>'decision' FROM preflight_request),
 'ready','same-owner staged photo evidence remains eligible for protected admission');
RESET ROLE;
-- Each durable state, including terminal failure, remains recovery-only even
-- if today's recipient changed. No new provider assignment is disclosed.
INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot,state)
SELECT ('00000000-0000-4000-8000-00000000fa3'||n)::UUID,'00000000-0000-4000-8000-00000000fa11',
 '00000000-0000-4000-8000-00000000fa01',jsonb_build_object('source_analysis_id',value->'source_analysis_id'),s
FROM preflight_request CROSS JOIN LATERAL (VALUES(1,'admitted'),(2,'dispatched'),(3,'draft'),(4,'complete'),(5,'failed_terminal')) states(n,s);
SET LOCAL ROLE authenticated;
SELECT extensions.ok((SELECT bool_and((public.get_owned_observation_reanalysis_preflight(value||jsonb_build_object('analysis_id','00000000-0000-4000-8000-00000000fa3'||n))->>'decision')='recovery_only')
 FROM preflight_request,generate_series(1,5)n),'all saved lifecycle states recover without new admission');
SELECT extensions.ok((SELECT (public.get_owned_observation_reanalysis_preflight(value||'{"analysis_id":"00000000-0000-4000-8000-00000000fa32"}')->'processor_permission')='null'::JSONB
 FROM preflight_request),'uncertain dispatch exposes no fresh recipient');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||jsonb_build_object('analysis_id',value->'source_analysis_id','source_analysis_id','00000000-0000-4000-8000-00000000fa99')) FROM preflight_request$$,'P0002','analysis_history_not_found','source validation precedes conflicting child lookup');
RESET ROLE;
-- A legacy identity is not permission to import its recipient or retry it.
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
VALUES('00000000-0000-4000-8000-00000000fa29','00000000-0000-4000-8000-00000000fa01','failed_terminal','server_replay_limit_reached','replay_exhausted');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"analysis_id":"00000000-0000-4000-8000-00000000fa29"}') FROM preflight_request$$,'22023','analysis_history_operation_conflict','legacy child identity conflicts');
RESET ROLE;
UPDATE internal.identification_provider_bindings SET provider='openai',binding='openai_photo_v1',processor_permission='openai',
 provider_model='gpt-6-sol',minimum_identification_protocol=4
WHERE operation='scan_identification' AND input_profile='multimodal_photo_v1';
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT public.get_owned_observation_reanalysis_preflight(value)->>'processor_permission' FROM preflight_request),'openai','new work uses current provider binding');
SELECT extensions.is((SELECT public.get_owned_observation_reanalysis_preflight(value||'{"analysis_id":"00000000-0000-4000-8000-00000000fa35"}')->>'decision' FROM preflight_request),'recovery_only','terminal recovery does not re-resolve current entitlement');
RESET ROLE;
UPDATE public.scans SET is_tombstoned=TRUE WHERE id='00000000-0000-4000-8000-00000000fa11';
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value) FROM preflight_request$$,'P0002','analysis_history_not_found','deletion blocks fresh preflight');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_reanalysis_preflight(value||'{"analysis_id":"00000000-0000-4000-8000-00000000fa34"}') FROM preflight_request$$,'P0002','analysis_history_not_found','deletion blocks prior complete recovery');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

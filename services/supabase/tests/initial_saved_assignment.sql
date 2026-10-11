\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.admission_owner(owner_id UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',NOW(),NOW());
 INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
 INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
 INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
 VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE FUNCTION pg_temp.admission_input() RETURNS JSONB LANGUAGE SQL AS $input$
 SELECT '{"schema_version":1,"route":"identify-describe","ordered_descriptions":["  Synthetic α / é / é\n\ttext  "],"media":[],"owner_timeline":[{"kind":"description","index":0}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null}'::JSONB;
$input$;
CREATE FUNCTION pg_temp.admit_initial(owner_id UUID,scan UUID,value JSONB DEFAULT pg_temp.admission_input()) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.admit_initial_analysis(owner_id,scan,internal.initial_canonical(value),internal.initial_digest('input',internal.initial_canonical(value)),
 (SELECT configuration_assets_digest FROM internal.initial_analysis_rollout WHERE singleton),repeat('a',64));
$$;

CREATE FUNCTION pg_temp.preparation_candidate(value JSONB DEFAULT pg_temp.admission_input()) RETURNS TEXT LANGUAGE SQL AS $$
 SELECT internal.initial_canonical(jsonb_build_object('version',2,'variant','no_media','input',value));
$$;
CREATE TEMP TABLE v2_vectors AS SELECT '{"candidate":{"version":2,"variant":"no_media","input":{"schema_version":1,"route":"identify-describe","ordered_descriptions":["  Synthetic α / é / é\n\ttext  "],"media":[],"owner_timeline":[{"kind":"description","index":0}],"capture":{"has_video":false,"video_clip_count":0,"declared_video_frame_count":0,"video_inference_frame_count":0},"context":{"depth_scale_text":null,"semantic_location":null,"weather_condition":null,"device_locale":null,"device_time_zone":null,"device_region":null,"time_of_day":null,"gps_latitude":null,"gps_longitude":null,"gps_elevation":null,"zoom_factor":null,"estimated_size_cm":null,"weather_temperature_f":null,"current_month":null},"options":{"timestamp":null,"geoprivacy":"private","public_location_label":null,"preferred_goal":null,"observation_context":null},"admission":{"client_protocol":3,"identification_protocol":6,"expected_processor_permission":"google_gemini"},"experiment":null}},"candidate_canonical":"{\"input\":{\"admission\":{\"client_protocol\":3,\"expected_processor_permission\":\"google_gemini\",\"identification_protocol\":6},\"capture\":{\"declared_video_frame_count\":0,\"has_video\":false,\"video_clip_count\":0,\"video_inference_frame_count\":0},\"context\":{\"current_month\":null,\"depth_scale_text\":null,\"device_locale\":null,\"device_region\":null,\"device_time_zone\":null,\"estimated_size_cm\":null,\"gps_elevation\":null,\"gps_latitude\":null,\"gps_longitude\":null,\"semantic_location\":null,\"time_of_day\":null,\"weather_condition\":null,\"weather_temperature_f\":null,\"zoom_factor\":null},\"experiment\":null,\"media\":[],\"options\":{\"geoprivacy\":\"private\",\"observation_context\":null,\"preferred_goal\":null,\"public_location_label\":null,\"timestamp\":null},\"ordered_descriptions\":[\"  Synthetic α / é / é\\n\\ttext  \"],\"owner_timeline\":[{\"index\":0,\"kind\":\"description\"}],\"route\":\"identify-describe\",\"schema_version\":1},\"variant\":\"no_media\",\"version\":2}","candidate_digest":"e762bcdecf8df8a59a9a0fc4498f1b5d540b3f7998b1078a129f40c46204a298","assignment":{"version":2,"candidate_digest":"e762bcdecf8df8a59a9a0fc4498f1b5d540b3f7998b1078a129f40c46204a298","route":"identify-describe","operation":"scan_identification","effective_plan":"pro_complimentary","effective_tier":"pro","flash_fallback_used":false,"quota_model":"gemini-2.5-pro","policy_version":1,"provider":"gemini","binding":"gemini_baseline_v1","processor_permission":"google_gemini","input_profile":"description_compat_v1","provider_model":null,"effective_model":"gemini-2.5-pro","minimum_client_protocol":0,"accepted_client_protocol":3,"minimum_identification_protocol":0,"accepted_identification_protocol":6,"asset_manifest_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1","preparation":{"kind":"none","profile":null,"options":null},"experiment":null},"assignment_canonical":"{\"accepted_client_protocol\":3,\"accepted_identification_protocol\":6,\"asset_manifest_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"binding\":\"gemini_baseline_v1\",\"candidate_digest\":\"e762bcdecf8df8a59a9a0fc4498f1b5d540b3f7998b1078a129f40c46204a298\",\"effective_model\":\"gemini-2.5-pro\",\"effective_plan\":\"pro_complimentary\",\"effective_tier\":\"pro\",\"experiment\":null,\"flash_fallback_used\":false,\"input_profile\":\"description_compat_v1\",\"minimum_client_protocol\":0,\"minimum_identification_protocol\":0,\"operation\":\"scan_identification\",\"policy_version\":1,\"preparation\":{\"kind\":\"none\",\"options\":null,\"profile\":null},\"processor_permission\":\"google_gemini\",\"provider\":\"gemini\",\"provider_model\":null,\"quota_model\":\"gemini-2.5-pro\",\"resolver_id\":\"git_blob_sha256_v1\",\"retention_owner\":\"initial_engine_release_archive\",\"route\":\"identify-describe\",\"version\":2}","assignment_digest":"907cb094de73c33072387756f92b0eee181a6d6581534b57e3eaef0d4b9beaca"}'::JSONB v;
SELECT extensions.is(internal.parse_initial_preparation_candidate(v->>'candidate_canonical'),v->'candidate','SQL accepts exact shared candidate') FROM v2_vectors;
SELECT extensions.is(internal.initial_preparation_digest('preparation-candidate',v->>'candidate_canonical'),v->>'candidate_digest','SQL candidate domain vector') FROM v2_vectors;
SELECT extensions.is(internal.initial_preparation_digest('assignment',v->>'assignment_canonical'),v->>'assignment_digest','SQL complete assignment domain vector') FROM v2_vectors;
SELECT extensions.ok(internal.initial_schema_matches(v->'assignment',internal.initial_assignment_schema_v2()),'SQL assignment matches closed schema') FROM v2_vectors;
SELECT extensions.ok(NOT internal.initial_schema_matches((v->'assignment')-field,internal.initial_assignment_schema_v2()),'SQL assignment requires '||field)
 FROM v2_vectors CROSS JOIN LATERAL jsonb_object_keys(v->'assignment') field;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'gate remains disabled');
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.initial_analysis_preparation_intents',privilege),'private expectation unavailable to '||role_name)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private comparison unavailable to '||role_name)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.resolve_initial_preparation_assignment(uuid,uuid,text,text,boolean)',
 'internal.assert_initial_preparation_assignment(uuid,uuid,text,boolean,boolean)']) signature;
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e002');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e003');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000e004');
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate())$$,
 '55000','initial_analysis_unavailable','disabled gate denies before claiming');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'disabled creation leaves no fence');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
-- A content-addressed object alone does not attest the required source resolver.
CREATE TEMP TABLE original_rollout AS SELECT * FROM internal.initial_analysis_rollout;
CREATE TEMP TABLE malformed_asset AS SELECT manifest-'resolver_id' AS manifest FROM internal.initial_analysis_configuration_assets
 WHERE digest=(SELECT configuration_assets_digest FROM original_rollout);
INSERT INTO internal.initial_analysis_configuration_assets(digest,manifest)
 SELECT internal.initial_digest('assets',internal.initial_canonical(manifest)),manifest FROM malformed_asset;
UPDATE internal.initial_analysis_rollout SET configuration_assets_digest=(SELECT internal.initial_digest('assets',internal.initial_canonical(manifest)) FROM malformed_asset);
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate())$$,
 '55000','initial_analysis_configuration_unavailable','unattested resolver rejected before claim');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'invalid manifest creates no permanent claim');
UPDATE internal.initial_analysis_rollout SET configuration_assets_digest=(SELECT configuration_assets_digest FROM original_rollout);
CREATE TEMP TABLE saved_preparation AS SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate()) value;
SELECT extensions.is((SELECT value->>'outcome' FROM saved_preparation),'prepared','original creation succeeds');
SELECT extensions.is((SELECT canonical_candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e101'),pg_temp.preparation_candidate(),'exact Unicode input saved');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'preparation creates no funding');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'preparation holds no credit');
SELECT extensions.is(public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate()),(SELECT value FROM saved_preparation),'exact retry preserves deadline/digests');
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate())$$,
 'P0002','initial_analysis_owner_unavailable','foreign owner cannot claim absent public scan');
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate(jsonb_set(pg_temp.admission_input(),'{ordered_descriptions}','["Changed synthetic text"]')))$$,
 '22023','initial_analysis_identity_conflict','changed accepted text cannot replace original intent');
SELECT extensions.throws_ok($$UPDATE internal.initial_analysis_preparation_intents SET assignment_digest=repeat('a',64) WHERE scan_id='00000000-0000-4000-8000-00000000e101'$$,
 '22023','initial_analysis_storage_immutable','expectation immutable');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e101'$$,
 '22023','initial_analysis_storage_immutable','unfunded expectation cannot disappear');
-- A mutation tripwire distinguishes pre-mutation denial from rollback after a
-- forbidden write. Any attempted funding write replaces the expected denial.
CREATE FUNCTION pg_temp.funding_tripwire() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
 IF current_setting('merian.test_funding_tripwire',TRUE)='on' THEN
  IF TG_TABLE_NAME<>'users' THEN RAISE EXCEPTION 'synthetic_funding_mutation' USING ERRCODE='P0001'; END IF;
  IF NEW.complimentary_entitlement_epoch IS DISTINCT FROM OLD.complimentary_entitlement_epoch THEN
   RAISE EXCEPTION 'synthetic_funding_mutation' USING ERRCODE='P0001'; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END;
$$;
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_reservations FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.ai_quota_counters FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.complimentary_scan_usage FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE INSERT OR UPDATE OR DELETE ON internal.identification_provider_attempts FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
CREATE TRIGGER test_funding_tripwire BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.funding_tripwire();
SELECT set_config('merian.test_funding_tripwire','on',TRUE);
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=clock_timestamp()+INTERVAL '1 hour' WHERE id='00000000-0000-4000-8000-00000000e001';
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 '55000','initial_analysis_assignment_changed','changed actual entitlement denies before hold or funding');
UPDATE public.users SET subscription_tier='free',subscription_expires_at=NULL WHERE id='00000000-0000-4000-8000-00000000e001';
UPDATE internal.initial_analysis_rollout SET configuration_assets_digest=(SELECT internal.initial_digest('assets',internal.initial_canonical(manifest)) FROM malformed_asset);
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 '55000','initial_analysis_configuration_unavailable','invalid asset after creation denies before funding');
UPDATE internal.initial_analysis_rollout SET configuration_assets_digest=(SELECT configuration_assets_digest FROM original_rollout);
-- Missing first-acquisition rows must not enter a blocking shared selector.
-- The subtransaction restores both catalog rows and the helper definition.
CREATE FUNCTION pg_temp.missing_prelock(kind TEXT, fresh BOOLEAN DEFAULT FALSE) RETURNS TEXT LANGUAGE PLPGSQL AS $probe$
BEGIN
 IF kind='policy' THEN
  DELETE FROM internal.identification_provider_bindings WHERE operation='scan_identification';
  DELETE FROM internal.ai_quota_policies WHERE operation='scan_identification';
  EXECUTE $ddl$CREATE OR REPLACE FUNCTION internal.resolve_quota_policy(p_operation TEXT,p_effective_plan TEXT)
   RETURNS internal.ai_quota_policies LANGUAGE PLPGSQL SET search_path='' AS 'BEGIN RAISE EXCEPTION ''synthetic_shared_selector_entered''; END;'$ddl$;
 ELSIF kind='binding' THEN
  DELETE FROM internal.identification_provider_bindings WHERE operation='scan_identification';
  EXECUTE $ddl$CREATE OR REPLACE FUNCTION internal.resolve_identification_provider_binding(p_operation TEXT,p_effective_plan TEXT,p_model TEXT,p_policy_version BIGINT,p_input_profile TEXT)
   RETURNS internal.identification_provider_bindings LANGUAGE PLPGSQL SET search_path='' AS 'BEGIN RAISE EXCEPTION ''synthetic_shared_selector_entered''; END;'$ddl$;
 ELSIF kind='entitlement' THEN
  DELETE FROM internal.entitlement_rollout_config;
  EXECUTE $ddl$CREATE OR REPLACE FUNCTION internal.resolve_fresh_quota_entitlement(
   p_user_id UUID,p_operation TEXT,p_original_analysis_id UUID,p_flash_fallback_eligible BOOLEAN,p_quota_now TIMESTAMPTZ)
   RETURNS TABLE(effective_plan TEXT,complimentary_client_scan_id UUID,flash_fallback_used BOOLEAN,acquire_complimentary_hold BOOLEAN)
   LANGUAGE PLPGSQL SET search_path='' AS 'BEGIN RAISE EXCEPTION ''synthetic_shared_selector_entered''; END;'$ddl$;
 ELSIF kind='consent' THEN
  DELETE FROM internal.ai_consent_rollout_config;
  EXECUTE $ddl$CREATE OR REPLACE FUNCTION internal.require_identification_processor_consent(p_user_id UUID,p_processor_permission TEXT)
   RETURNS VOID LANGUAGE PLPGSQL SET search_path='' AS 'BEGIN RAISE EXCEPTION ''synthetic_shared_selector_entered''; END;'$ddl$;
 END IF;
 IF fresh THEN
  PERFORM public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e199',pg_temp.preparation_candidate());
 ELSE
  PERFORM public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64));
 END IF;
 RAISE EXCEPTION 'synthetic_unexpected_success';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END;
$probe$;
SELECT extensions.is(pg_temp.missing_prelock('policy'),'ai_quota_policy_missing','absent policy denies before blocking helper');
SELECT extensions.is(pg_temp.missing_prelock('binding'),'ai_provider_assignment_unavailable','absent binding denies before blocking helper');
SELECT extensions.is(pg_temp.missing_prelock('entitlement'),'ai_entitlement_unavailable','absent entitlement rollout denies before core');
SELECT extensions.is(pg_temp.missing_prelock('consent'),'initial_analysis_configuration_unavailable','absent consent rollout denies before helper');
SELECT extensions.is(pg_temp.missing_prelock('entitlement',TRUE),'ai_entitlement_unavailable','fresh create rejects absent rollout before selector');
CREATE TEMP TABLE original_bindings AS SELECT * FROM internal.identification_provider_bindings;
UPDATE internal.identification_provider_bindings SET minimum_client_protocol=CASE minimum_client_protocol WHEN 2 THEN 1 ELSE 2 END WHERE operation='scan_identification' AND input_profile='description_compat_v1';
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 '55000','initial_analysis_assignment_changed','changed complete binding rejected before mutation');
SELECT extensions.is(public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',pg_temp.preparation_candidate()),(SELECT value FROM saved_preparation),'create replay does not rebase binding');
UPDATE internal.identification_provider_bindings b SET minimum_client_protocol=o.minimum_client_protocol FROM original_bindings o WHERE b.operation=o.operation AND b.effective_plan=o.effective_plan AND b.model=o.model AND b.policy_version=o.policy_version AND b.input_profile=o.input_profile;
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 '55000','initial_analysis_unavailable','revoked gate denies before funding');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT public.reserve_identification_quota('00000000-0000-4000-8000-00000000e001','scan_identification','00000000-0000-4000-8000-00000000e101',repeat('a',64),'00000000-0000-4000-8000-00000000e101',TRUE,3,FALSE,'description_compat_v1','google_gemini',6)$$,
 '55000','initial_analysis_admission_required','ordinary wrapper cannot consume saved intent');
SELECT extensions.throws_ok($$SELECT internal.reserve_ai_quota_core('00000000-0000-4000-8000-00000000e001','scan_identification','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 '55000','initial_analysis_preparation_required','direct base core cannot bypass saved comparison');
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
-- Unfunded cancellation/expiry and strong erasure own no accounting authority.
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e102',pg_temp.preparation_candidate());
SELECT set_config('merian.test_funding_tripwire','on',TRUE);
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e102')->>'dispatch','dispatch_prevented','unfunded C1 works while gate disabled with no funding write');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e102'),0::BIGINT,'C1 erases all private candidate/assignment bytes');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000e102'),'cancelled_pre_dispatch','C1 terminal fence retained');
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e102')->>'dispatch','dispatch_prevented','cancellation exact replay');
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e102',pg_temp.preparation_candidate())$$,
 '55000','initial_analysis_cancelled','terminal identity cannot recreate an intent');
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103',pg_temp.preparation_candidate());
-- Privileged fixture-only time travel; production immutability was checked above.
SET CONSTRAINTS ALL IMMEDIATE;
ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage;
UPDATE internal.initial_analysis_preparation_intents SET created_at='2000-01-01T00:00:00Z',expires_at='2000-01-01T00:05:00Z' WHERE scan_id='00000000-0000-4000-8000-00000000e103';
ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage;
SET CONSTRAINTS ALL DEFERRED;
SELECT set_config('merian.test_funding_tripwire','on',TRUE);
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000e002','00000000-0000-4000-8000-00000000e103')->>'outcome','expired','expiry retires unfunded owner without accounting');
SELECT set_config('merian.test_funding_tripwire','off',TRUE);
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000e103'),'cancelled_pre_dispatch','expiry leaves terminal namespace');
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e003','00000000-0000-4000-8000-00000000e104',pg_temp.preparation_candidate());
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000e104',NULL,clock_timestamp());
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e104'),0::BIGINT,'pre-row tombstone erases input and hashes');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000e104'),'cancelled_unknown','strong erasure conservatively leaves terminal exclusion');
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e003','00000000-0000-4000-8000-00000000e104',repeat('a',64))$$,
 '55000','initial_analysis_deleted','delayed funding cannot resurrect deleted evidence');
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e003','00000000-0000-4000-8000-00000000e105',pg_temp.preparation_candidate());
DELETE FROM public.users WHERE id='00000000-0000-4000-8000-00000000e003';
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e105'),0::BIGINT,'raw pre-row owner deletion erases intent');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000e105'),'cancelled_unknown','raw owner cascade keeps terminal fence');
SELECT public.create_initial_preparation_intent('00000000-0000-4000-8000-00000000e004','00000000-0000-4000-8000-00000000e106',pg_temp.preparation_candidate());
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000e004');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e106'),0::BIGINT,'supported detachment erases pre-row intent');
SELECT extensions.is((SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id='00000000-0000-4000-8000-00000000e106'),'cancelled_pre_dispatch','supported detachment leaves C1 terminal fence');
-- A lost/failed admission save rolls back original accounting atomically.
CREATE FUNCTION pg_temp.fail_promotion() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN RAISE EXCEPTION 'synthetic_promotion_failure' USING ERRCODE='P0001'; END;
$$;
CREATE TRIGGER test_fail_promotion BEFORE INSERT ON internal.initial_analysis_admissions FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_promotion();
SELECT extensions.throws_ok($$SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64))$$,
 'P0001','synthetic_promotion_failure','promotion save failure surfaces');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'failed promotion rolls back quota');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'failed promotion rolls back hold');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_submissions WHERE scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'failed promotion rolls back submission');
SELECT extensions.is(public.get_initial_preparation_status('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101'),(SELECT value FROM saved_preparation),'failed promotion preserves exact original intent');
DROP TRIGGER test_fail_promotion ON internal.initial_analysis_admissions;
CREATE TEMP TABLE candidate_for_service AS SELECT pg_temp.preparation_candidate() value;
GRANT SELECT ON candidate_for_service TO service_role;
CREATE TEMP TABLE funded(value JSONB);
GRANT INSERT ON funded TO service_role;
SET LOCAL ROLE service_role;
INSERT INTO funded SELECT public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',repeat('a',64));
RESET ROLE;
SELECT extensions.is((SELECT value#>>'{binding,version}' FROM funded),'2','real service-role produces v2 binding');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000e101'),0::BIGINT,'promotion removes redundant unfunded owner');
SELECT extensions.is((SELECT value#>>'{binding,assignment_digest}' FROM funded),(SELECT value->>'assignment_digest' FROM saved_preparation),'promotion retains original assignment identity');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000e101'),1::BIGINT,'one original reservation');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;
DELETE FROM internal.identification_provider_bindings WHERE operation='scan_identification' AND input_profile='description_compat_v1';
SELECT extensions.is(public.finalize_initial_preparation('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',NULL)->'binding',(SELECT value->'binding' FROM funded),'admitted replay ignores changed defaults and caller IP');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101')$$,
 '55000','initial_analysis_preparation_required','v1 cannot reinterpret v2 admission');
SELECT extensions.throws_ok($$SELECT internal.lock_initial_media_scope('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101',(SELECT value#>>'{binding,submission_digest}' FROM funded))$$,
 '55000','initial_analysis_preparation_required','M1 v1 cannot reinterpret v2');
SELECT extensions.is(public.cancel_initial_analysis('00000000-0000-4000-8000-00000000e001','00000000-0000-4000-8000-00000000e101')->>'dispatch','dispatch_prevented','funded v2 cancellation uses existing exact accounting proof');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE request_id='00000000-0000-4000-8000-00000000e101'),'refunded','funded pre-dispatch v2 follows C1');
SELECT * FROM extensions.finish();
ROLLBACK;

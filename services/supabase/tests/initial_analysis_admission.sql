\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN INITIAL ADMISSION HELPERS
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
-- END INITIAL ADMISSION HELPERS
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'activation remains false');
SELECT extensions.ok(NOT has_table_privilege(role_name,table_name,privilege),'private admission data denied')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.initial_analysis_admissions','internal.initial_analysis_operation_fences','internal.initial_analysis_configuration_assets']) table_name
 CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) privilege;
SELECT extensions.ok(NOT has_function_privilege(role_name,'public.admit_initial_analysis(uuid,uuid,text,text,text,text)','EXECUTE'),'client cannot admit') FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT extensions.ok(has_function_privilege('service_role','public.admit_initial_analysis(uuid,uuid,text,text,text,text)','EXECUTE'),'only fixed service admission installed');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000c001');
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000c002');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101')$$,'55000','initial_analysis_unavailable','default-off admission rejects');
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','ac0a0001-0000-8000-8000-00000000c104')$$,'55000','initial_analysis_experiment_unavailable','comparison namespace cannot lose its marker');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','ac0b0001-0000-8000-8000-00000000c104')$$,'55000','initial_analysis_experiment_unavailable','prompt comparison namespace remains held');
CREATE TEMP TABLE original_admission AS SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101') AS value;
SELECT extensions.is((SELECT value->>'outcome' FROM original_admission),'admitted','fresh admission acknowledged without dispatch grant');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000c101'),1::BIGINT,'one original funding reservation');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000c001' AND client_scan_id='00000000-0000-4000-8000-00000000c101'),'held','original complimentary hold remains unconsumed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE funding_snapshot::TEXT ~ 'lease_token|lease_expires_at|daily_remaining|scans_remaining|is_replay|reservation_state'), 'funding identity excludes mutable counters and lease capabilities');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-00000000c101'),0::BIGINT,'admission does not invoke or commit');
SELECT extensions.is(pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101')->'binding',(SELECT value->'binding' FROM original_admission),'identical replay retains every binding field');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c002','00000000-0000-4000-8000-00000000c101')$$,'P0002','initial_analysis_owner_unavailable','cross-owner response discloses no binding');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101',jsonb_set(pg_temp.admission_input(),'{ordered_descriptions}','["Different synthetic text"]'))$$,'22023','initial_analysis_identity_conflict','changed text conflicts');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101',jsonb_set(jsonb_set(pg_temp.admission_input(),'{route}','"identify-multimodal"'),'{ordered_descriptions}','["Different synthetic text"]'))$$,'22023','initial_analysis_identity_conflict','route is not another namespace');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101',jsonb_set(pg_temp.admission_input(),'{options,geoprivacy}','"open"'))$$,'22023','initial_analysis_identity_conflict','changed explicit option conflicts');
-- Retry authority does not depend on current defaults, caller deployment or lease.
UPDATE internal.ai_quota_reservations SET lease_expires_at=now()-INTERVAL '1 hour' WHERE original_analysis_id='00000000-0000-4000-8000-00000000c101';
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE,configuration_assets_digest=NULL;
SELECT extensions.is(public.admit_initial_analysis('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101',internal.initial_canonical(pg_temp.admission_input()),internal.initial_digest('input',internal.initial_canonical(pg_temp.admission_input())),NULL,NULL)->'binding',(SELECT value->'binding' FROM original_admission),'recovery replays before gate/config/IP/lease defaults');
SELECT internal.refund_expired_ai_quota_reservations(100);
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000c101'),'reserved','expiry cannot refund the bound operation');
SELECT extensions.throws_ok($$SELECT public.reserve_identification_quota('00000000-0000-4000-8000-00000000c001','scan_identification','00000000-0000-4000-8000-00000000c101',repeat('a',64),'00000000-0000-4000-8000-00000000c101',TRUE,3,FALSE,'description_compat_v1','google_gemini',6)$$,'55000','initial_analysis_admission_required','generic current reservation cannot reacquire expired binding');
SELECT extensions.throws_ok($$SELECT public.reserve_ai_quota('00000000-0000-4000-8000-00000000c001','scan_identification','00000000-0000-4000-8000-00000000c101',repeat('a',64),NULL,TRUE,3,FALSE)$$,'55000','initial_analysis_admission_required','legacy omitted-original-ID cannot bypass binding');
SELECT extensions.throws_ok($$SELECT public.finalize_ai_quota_reservation(q.id,q.user_id,q.lease_token,'refunded') FROM internal.ai_quota_reservations q WHERE original_analysis_id='00000000-0000-4000-8000-00000000c101'$$,'55000','initial_analysis_execution_required','generic finalizer cannot refund');
SELECT extensions.throws_ok($$SELECT public.commit_identification_invocation(q.id,q.user_id,q.lease_token,1,'{}') FROM internal.ai_quota_reservations q WHERE original_analysis_id='00000000-0000-4000-8000-00000000c101'$$,'55000','initial_analysis_execution_required','generic commit cannot dispatch');
-- Force an error after the reservation inside the same SQL transaction.
UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE,
 configuration_assets_digest=(SELECT digest FROM internal.initial_analysis_configuration_assets LIMIT 1);
CREATE FUNCTION pg_temp.reject_initial_fixture() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN
 IF NEW.scan_id='00000000-0000-4000-8000-00000000c102' THEN RAISE EXCEPTION 'synthetic_storage_failure' USING ERRCODE='22023'; END IF; RETURN NEW; END; $$;
CREATE TRIGGER zz_reject_initial_fixture BEFORE INSERT ON internal.initial_analysis_submissions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_initial_fixture();
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c102')$$,'22023','synthetic_storage_failure','post-reservation error propagates for atomic rollback');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000c102'),0::BIGINT,'failed storage leaves no orphan funding');
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000c102'),0::BIGINT,'failed storage rolls back new fence');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000c102'),0::BIGINT,'failed storage leaves no complimentary hold');
DROP TRIGGER zz_reject_initial_fixture ON internal.initial_analysis_submissions;
SELECT extensions.throws_ok($$SELECT public.admit_initial_analysis('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c102',internal.initial_canonical(pg_temp.admission_input()),internal.initial_digest('input',internal.initial_canonical(pg_temp.admission_input())),NULL,NULL)$$,'55000','initial_analysis_configuration_unavailable','recovery-only absence cannot allocate');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES('00000000-0000-4000-8000-00000000c101',NULL,clock_timestamp());
SELECT extensions.is((SELECT count(*) FROM internal.initial_analysis_admissions WHERE scan_id='00000000-0000-4000-8000-00000000c101'),0::BIGINT,'pre-row deletion erases canonical bytes and every derived binding hash');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000c101'),'content-free ID fence survives private erasure');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_initial('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c101')$$,'55000','initial_analysis_deleted','delayed identical admission cannot resurrect deleted evidence');
SELECT extensions.throws_ok($$DELETE FROM internal.initial_analysis_operation_fences WHERE scan_id='00000000-0000-4000-8000-00000000c101'$$,'22023','initial_analysis_storage_immutable','namespace fence cannot be pruned');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.initial_analysis_admissions$$,'42501',NULL,'actual service cannot read private input/bindings directly');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

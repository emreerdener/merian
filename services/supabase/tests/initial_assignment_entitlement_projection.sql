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

SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000c001');
CREATE FUNCTION pg_temp.project_entitlement(fallback BOOLEAN DEFAULT TRUE, original UUID DEFAULT '00000000-0000-4000-8000-00000000c101', operation TEXT DEFAULT 'scan_identification')
RETURNS JSONB LANGUAGE SQL AS $$
 SELECT to_jsonb(p) FROM internal.resolve_fresh_quota_entitlement(
 '00000000-0000-4000-8000-00000000c001',operation,original,fallback,clock_timestamp()) p;
$$;
SELECT extensions.ok(NOT has_function_privilege(role_name,
 'internal.resolve_fresh_quota_entitlement(uuid,text,uuid,boolean,timestamp with time zone)','EXECUTE'),
 'API role cannot call private projection') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is((SELECT prosecdef FROM pg_proc WHERE oid='internal.resolve_fresh_quota_entitlement(uuid,text,uuid,boolean,timestamptz)'::regprocedure),FALSE,'projection is invoker');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
CREATE TEMP TABLE before_projection AS SELECT
 (SELECT count(*) FROM internal.ai_quota_reservations) reservations,
 (SELECT count(*) FROM internal.ai_quota_counters) counters,
 (SELECT count(*) FROM internal.complimentary_scan_usage) usage_count,
 (SELECT complimentary_entitlement_epoch FROM public.users WHERE id='00000000-0000-4000-8000-00000000c001') epoch;
SELECT extensions.is(pg_temp.project_entitlement()->>'effective_plan','pro_complimentary','fresh available credit selects Pro');
SELECT extensions.is(pg_temp.project_entitlement()->>'acquire_complimentary_hold','true','projection describes hold without acquiring it');
SELECT extensions.is(pg_temp.project_entitlement()->>'complimentary_client_scan_id','00000000-0000-4000-8000-00000000c101','original identity remains linked');
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=clock_timestamp()+INTERVAL '1 hour' WHERE id='00000000-0000-4000-8000-00000000c001';
SELECT extensions.is(pg_temp.project_entitlement()->>'effective_plan','pro_paid','paid lane retained');
SELECT extensions.is(pg_temp.project_entitlement()->>'acquire_complimentary_hold','false','paid lane never requests a hold');
SELECT extensions.is(pg_temp.project_entitlement()->'complimentary_client_scan_id','null'::JSONB,'paid lane has no complimentary link');
UPDATE public.users SET subscription_tier='free',subscription_expires_at=NULL WHERE id='00000000-0000-4000-8000-00000000c001';
UPDATE internal.entitlement_rollout_config SET entitlement_mode='legacy_trial',required_client_protocol=0 WHERE config_key='current';
SELECT extensions.is(pg_temp.project_entitlement()->>'effective_plan',internal.effective_plan(u.subscription_tier,u.created_at,u.subscription_expires_at),'legacy lane delegates unchanged trial policy') FROM public.users u WHERE u.id='00000000-0000-4000-8000-00000000c001';
SELECT extensions.is(pg_temp.project_entitlement()->>'acquire_complimentary_hold','false','legacy trial creates no hold');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations),(SELECT reservations FROM before_projection),'projection creates zero reservations');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_counters),(SELECT counters FROM before_projection),'projection changes zero counter rows');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage),(SELECT usage_count FROM before_projection),'projection creates zero credit holds');
SELECT extensions.is((SELECT complimentary_entitlement_epoch FROM public.users WHERE id='00000000-0000-4000-8000-00000000c001'),(SELECT epoch FROM before_projection),'projection does not bump entitlement epoch');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
CREATE TEMP TABLE admitted AS SELECT * FROM public.reserve_identification_quota(
 '00000000-0000-4000-8000-00000000c001','scan_identification','00000000-0000-4000-8000-00000000c101',repeat('a',64),
 '00000000-0000-4000-8000-00000000c101',TRUE,3,FALSE,'description_compat_v1','google_gemini',6);
SELECT extensions.is((SELECT effective_plan FROM admitted),'pro_complimentary','unchanged reservation owner selects projected lane');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000c101'),'held','only funding owner acquires original hold');
SELECT extensions.is(pg_temp.project_entitlement()->>'acquire_complimentary_hold','false','existing held credit is not acquired twice');
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id='00000000-0000-4000-8000-00000000c001';
CREATE TEMP TABLE replayed AS SELECT * FROM public.reserve_identification_quota(
 '00000000-0000-4000-8000-00000000c001','scan_identification','00000000-0000-4000-8000-00000000c101',repeat('a',64),
 '00000000-0000-4000-8000-00000000c101',TRUE,3,FALSE,'description_compat_v1','google_gemini',6);
SELECT extensions.is((SELECT reservation_id FROM replayed),(SELECT reservation_id FROM admitted),'replay retains original funding');
SELECT extensions.is((SELECT effective_plan FROM replayed),'pro_complimentary','replay precedes fresh paid selection');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000c101'),1::BIGINT,'replay creates no second hold');
UPDATE public.users SET subscription_tier='free',subscription_expires_at=NULL WHERE id='00000000-0000-4000-8000-00000000c001';
INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) VALUES
 ('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c103'),
 ('00000000-0000-4000-8000-00000000c001','00000000-0000-4000-8000-00000000c104');
SELECT extensions.is(pg_temp.project_entitlement(TRUE,'00000000-0000-4000-8000-00000000c102')->>'effective_plan','free','exhausted eligible new operation selects Flash');
SELECT extensions.is(pg_temp.project_entitlement(TRUE,'00000000-0000-4000-8000-00000000c102')->>'flash_fallback_used','true','fallback effect is explicit');
SELECT extensions.is(pg_temp.project_entitlement(TRUE,'00000000-0000-4000-8000-00000000c102')->>'acquire_complimentary_hold','false','fallback never creates a credit hold');
SELECT extensions.throws_ok($$SELECT pg_temp.project_entitlement(FALSE,'00000000-0000-4000-8000-00000000c102')$$,'P0001','ai_entitlement_required','exhausted ineligible request denies');
SELECT extensions.is(pg_temp.project_entitlement(FALSE)->>'effective_plan','pro_complimentary','original held credit survives exhaustion');
SELECT extensions.throws_ok($$SELECT pg_temp.project_entitlement(TRUE,NULL)$$,'22023','ai_quota_invalid_request','complimentary scan needs original identity');
SELECT extensions.throws_ok($$SELECT pg_temp.project_entitlement(NULL)$$,'22023','ai_quota_invalid_request','null fallback is not authority');
SELECT extensions.is(pg_temp.project_entitlement(TRUE,'00000000-0000-4000-8000-00000000c101','species_chat')->>'complimentary_client_scan_id','00000000-0000-4000-8000-00000000c101','non-scan operation retains existing linked entitlement semantics');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT * FROM internal.resolve_fresh_quota_entitlement('00000000-0000-4000-8000-00000000c001','scan_identification','00000000-0000-4000-8000-00000000c102',TRUE,clock_timestamp())$$,'42501',NULL,'actual service role cannot invoke private projection');
RESET ROLE;
SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'activation unchanged');
SELECT * FROM extensions.finish();
ROLLBACK;

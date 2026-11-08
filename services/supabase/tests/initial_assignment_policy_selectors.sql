\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),
 'private selector is unavailable to '||role_name) FROM
 unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN
 unnest(ARRAY['internal.resolve_quota_policy(text,text)',
 'internal.resolve_identification_provider_binding(text,text,text,bigint,text)']) signature;
SELECT extensions.is(prosecdef,FALSE,'selector uses invoker privileges') FROM pg_proc
 WHERE oid IN ('internal.resolve_quota_policy(text,text)'::regprocedure,
 'internal.resolve_identification_provider_binding(text,text,text,bigint,text)'::regprocedure);

-- Every currently enabled policy and every registered binding must resolve the
-- complete original row, including separate quota and actual-provider models.
SELECT extensions.is(to_jsonb(actual),to_jsonb(expected),'exact enabled policy: '||expected.operation||'/'||expected.effective_plan)
 FROM internal.ai_quota_policies expected
 CROSS JOIN LATERAL internal.resolve_quota_policy(expected.operation,expected.effective_plan) actual
 WHERE expected.enabled AND expected.allowed;
SELECT extensions.is(to_jsonb(actual),to_jsonb(expected),'exact binding: '||expected.input_profile||'/'||expected.effective_plan)
 FROM internal.identification_provider_bindings expected
 CROSS JOIN LATERAL internal.resolve_identification_provider_binding(expected.operation,expected.effective_plan,expected.model,expected.policy_version,expected.input_profile) actual;

SELECT extensions.throws_ok($$SELECT internal.resolve_quota_policy('missing_operation','free')$$,
 'P0001','ai_quota_policy_missing','missing policy fails closed');
SELECT extensions.throws_ok($$SELECT internal.resolve_quota_policy('scan_identification',NULL)$$,
 'P0001','ai_quota_policy_missing','null plan cannot choose a default');
CREATE TEMP TABLE original_free_policy AS SELECT model FROM internal.ai_quota_policies WHERE operation='scan_identification' AND effective_plan='free';
UPDATE internal.ai_quota_policies SET enabled=FALSE,allowed=FALSE,model=NULL
 WHERE operation='scan_identification' AND effective_plan='free';
SELECT extensions.throws_ok($$SELECT internal.resolve_quota_policy('scan_identification','free')$$,
 'P0001','ai_quota_policy_disabled','disabled retains precedence over not allowed');
UPDATE internal.ai_quota_policies SET enabled=TRUE WHERE operation='scan_identification' AND effective_plan='free';
SELECT extensions.throws_ok($$SELECT internal.resolve_quota_policy('scan_identification','free')$$,
 'P0001','ai_entitlement_required','not allowed retains original denial');
UPDATE internal.ai_quota_policies SET allowed=TRUE,model=(SELECT model FROM original_free_policy) WHERE operation='scan_identification' AND effective_plan='free';

CREATE TEMP TABLE chosen AS SELECT * FROM internal.identification_provider_bindings
 WHERE operation='scan_identification' AND effective_plan='free' AND input_profile='multimodal_text_v1';
CREATE FUNCTION pg_temp.resolve_changed(field TEXT) RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE row internal.identification_provider_bindings;
BEGIN
 SELECT * INTO STRICT row FROM chosen;
 PERFORM internal.resolve_identification_provider_binding(
 CASE WHEN field='operation' THEN 'missing_operation' ELSE row.operation END,
 CASE WHEN field='plan' THEN 'missing_plan' ELSE row.effective_plan END,
 CASE WHEN field='model' THEN 'missing_model' ELSE row.model END,
 CASE WHEN field='policy' THEN -1 ELSE row.policy_version END,
 CASE WHEN field='profile' THEN 'missing_profile' ELSE row.input_profile END);
END;
$$;
SELECT extensions.throws_ok(format('SELECT pg_temp.resolve_changed(%L)',field),
 'P0001','ai_provider_assignment_unavailable','changed binding '||field||' cannot select fallback')
 FROM unnest(ARRAY['operation','plan','model','policy','profile']) field;

CREATE TEMP TABLE before_selection AS SELECT
 (SELECT count(*) FROM internal.ai_quota_reservations) reservations,
 (SELECT count(*) FROM internal.ai_quota_counters) counters,
 (SELECT count(*) FROM internal.complimentary_scan_usage) holds,
 (SELECT count(*) FROM internal.identification_provider_attempts) attempts;
SELECT internal.resolve_quota_policy('scan_identification','free') IS NOT NULL;
SELECT internal.resolve_identification_provider_binding(operation,effective_plan,model,policy_version,input_profile) IS NOT NULL FROM chosen;
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_reservations),(SELECT reservations FROM before_selection),'selection creates no reservation');
SELECT extensions.is((SELECT count(*) FROM internal.ai_quota_counters),(SELECT counters FROM before_selection),'selection creates no counter');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage),(SELECT holds FROM before_selection),'selection creates no hold');
SELECT extensions.is((SELECT count(*) FROM internal.identification_provider_attempts),(SELECT attempts FROM before_selection),'selection creates no attempt');

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.resolve_quota_policy('scan_identification','free')$$,
 '42501',NULL,'actual service role cannot call policy selector');
SELECT extensions.throws_ok($$SELECT internal.resolve_identification_provider_binding('scan_identification','free','gemini-2.5-flash',1,'multimodal_text_v1')$$,
 '42501',NULL,'actual service role cannot call binding selector');
RESET ROLE;
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
SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000d001');
UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL
 WHERE id='00000000-0000-4000-8000-00000000d001';
CREATE TEMP TABLE public_results(label TEXT,reservation_id UUID,model TEXT,effective_plan TEXT,binding TEXT,is_replay BOOLEAN);
GRANT INSERT ON public_results TO service_role;
SET LOCAL ROLE service_role;
INSERT INTO public_results SELECT 'quota',reservation_id,model,effective_plan,NULL,is_replay
 FROM public.reserve_ai_quota('00000000-0000-4000-8000-00000000d001','scan_identification',
 '00000000-0000-4000-8000-00000000d101',repeat('b',64),'00000000-0000-4000-8000-00000000d101',TRUE,3,FALSE);
INSERT INTO public_results SELECT 'identify',reservation_id,model,effective_plan,binding,is_replay
 FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000d001','scan_identification',
 '00000000-0000-4000-8000-00000000d102',repeat('b',64),'00000000-0000-4000-8000-00000000d102',TRUE,3,FALSE,'multimodal_text_v1','google_gemini',6);
RESET ROLE;
SELECT extensions.is((SELECT effective_plan FROM public_results WHERE label='quota'),'pro_paid','real service-role quota wrapper reaches private policy selector');
SELECT extensions.is((SELECT model FROM public_results WHERE label='quota'),
 (SELECT model FROM internal.ai_quota_policies WHERE operation='scan_identification' AND effective_plan='pro_paid'),'quota model unchanged');
SELECT extensions.is((SELECT model FROM public_results WHERE label='identify'),
 (SELECT COALESCE(b.provider_model,p.model) FROM internal.identification_provider_bindings b JOIN internal.ai_quota_policies p
 ON p.operation=b.operation AND p.effective_plan=b.effective_plan AND p.model=b.model AND p.policy_version=b.policy_version
 WHERE p.operation='scan_identification' AND p.effective_plan='pro_paid' AND b.input_profile='multimodal_text_v1'),'real service-role identification wrapper returns original provider model');
SELECT extensions.is((SELECT binding FROM public_results WHERE label='identify'),'gemini_baseline_v1','provider binding unchanged');
-- Existing paid reservations replay their original assignment even when the
-- current policy revision and binding no longer match that saved assignment.
UPDATE internal.ai_quota_policies SET policy_version=policy_version+1 WHERE operation='scan_identification' AND effective_plan='pro_paid';
DELETE FROM internal.identification_provider_bindings WHERE operation='scan_identification' AND effective_plan='pro_paid' AND input_profile='multimodal_text_v1';
SET LOCAL ROLE service_role;
INSERT INTO public_results SELECT 'replay',reservation_id,model,effective_plan,binding,is_replay
 FROM public.reserve_identification_quota('00000000-0000-4000-8000-00000000d001','scan_identification',
 '00000000-0000-4000-8000-00000000d102',repeat('b',64),'00000000-0000-4000-8000-00000000d102',TRUE,3,FALSE,'multimodal_text_v1','google_gemini',6);
RESET ROLE;
SELECT extensions.is((SELECT reservation_id FROM public_results WHERE label='replay'),(SELECT reservation_id FROM public_results WHERE label='identify'),'service-role replay retains exact original reservation');
SELECT extensions.is((SELECT is_replay FROM public_results WHERE label='replay'),TRUE,'replay bypasses unavailable fresh selectors');
SELECT extensions.is((SELECT model FROM public_results WHERE label='replay'),(SELECT model FROM public_results WHERE label='identify'),'replay keeps saved provider model');

SELECT extensions.is((SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout),FALSE,'activation remains off');
SELECT * FROM extensions.finish();
ROLLBACK;

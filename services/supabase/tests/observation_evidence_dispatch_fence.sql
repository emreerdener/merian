\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'old acquisition denied to '||role_name||': '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['public.retire_expired_observation_evidence()','public.retire_expired_observation_video_evidence()','public.claim_observation_evidence_erasure()']) signature;
SELECT extensions.throws_ok('SELECT '||signature,'42501','legacy_private_evidence_acquisition_denied','original owner reaches permanent denial: '||signature)
FROM unnest(ARRAY['public.retire_expired_observation_evidence()','public.retire_expired_observation_video_evidence()','public.claim_observation_evidence_erasure()']) signature;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'implementation remains private: '||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY['internal.retire_expired_observation_evidence_worker_impl()','internal.retire_expired_observation_video_evidence_worker_impl()','internal.claim_observation_evidence_erasure_worker_impl()','internal.require_observation_evidence_dispatch(uuid)']) signature;
SELECT extensions.ok(has_function_privilege('service_role',signature,'EXECUTE'),'new service acquisition: '||signature)
FROM unnest(ARRAY['public.retire_expired_observation_evidence_for_dispatch(uuid)','public.retire_expired_observation_video_evidence_for_dispatch(uuid)','public.claim_observation_evidence_erasure_for_dispatch(uuid)']) signature;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'new acquisition denies clients: '||signature)
FROM unnest(ARRAY['anon','authenticated']) role_name
CROSS JOIN unnest(ARRAY['public.retire_expired_observation_evidence_for_dispatch(uuid)','public.retire_expired_observation_video_evidence_for_dispatch(uuid)','public.claim_observation_evidence_erasure_for_dispatch(uuid)']) signature;
SELECT extensions.ok(p.pronargdefaults=0 AND p.pronargs=1,'no default/missing dispatch bypass: '||p.proname)
FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN
('retire_expired_observation_evidence_for_dispatch','retire_expired_observation_video_evidence_for_dispatch','claim_observation_evidence_erasure_for_dispatch');

SELECT vault.create_secret('https://abcdefghijklmnopqrst.supabase.co','SUPABASE_URL') IS NOT NULL;
SELECT vault.create_secret('sb_secret_'||repeat('a',30),'SUPABASE_SERVICE_ROLE_KEY') IS NOT NULL;
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE;
UPDATE internal.observation_evidence_worker_state SET enabled=TRUE,approved_project='abcdefghijklmnopqrst',pending_request_id=-370,
 pending_dispatch_id='00000000-0000-4000-8000-00000000ee01';
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.claim_observation_evidence_erasure_for_dispatch(NULL)$$,'42501','private_evidence_dispatch_unavailable','null dispatch denied');
SELECT extensions.throws_ok($$SELECT public.claim_observation_evidence_erasure_for_dispatch('00000000-0000-4000-8000-00000000ee02')$$,'42501','private_evidence_dispatch_unavailable','wrong dispatch denied');
SELECT extensions.is(public.retire_expired_observation_evidence_for_dispatch('00000000-0000-4000-8000-00000000ee01'),0,'current dispatch photo/audio lane permitted');
SELECT extensions.is(public.retire_expired_observation_video_evidence_for_dispatch('00000000-0000-4000-8000-00000000ee01'),0,'current dispatch video lane permitted');
SELECT extensions.is(public.claim_observation_evidence_erasure_for_dispatch('00000000-0000-4000-8000-00000000ee01'),NULL::JSONB,'current dispatch empty claim permitted');
RESET ROLE;
UPDATE internal.observation_evidence_worker_state SET pending_dispatch_id='00000000-0000-4000-8000-00000000ee02';
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.claim_observation_evidence_erasure_for_dispatch('00000000-0000-4000-8000-00000000ee01')$$,'42501','private_evidence_dispatch_unavailable','rotated dispatch cannot acquire future work');
SELECT extensions.is(public.finish_observation_evidence_erasure('00000000-0000-4000-8000-00000000ee03','00000000-0000-4000-8000-00000000ee04',TRUE),FALSE,'settlement entry remains available independently of dispatch');
RESET ROLE;
UPDATE internal.observation_evidence_worker_state SET enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.claim_observation_evidence_erasure_for_dispatch('00000000-0000-4000-8000-00000000ee02')$$,'42501','private_evidence_dispatch_unavailable','pause denies new acquisition');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

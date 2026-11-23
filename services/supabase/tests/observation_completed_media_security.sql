\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT has_function_privilege(role_name,'public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)','EXECUTE'),'completed media denies ' || role_name)
FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT extensions.ok(has_function_privilege('service_role','public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)','EXECUTE'),'verified adapter can resolve originals');
SELECT extensions.ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'resolver has bounded definer scope')
FROM pg_proc WHERE oid='public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)'::regprocedure;
SELECT set_config('request.jwt.claim.role','authenticated',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.resolve_owned_observation_media(NULL,NULL,NULL,NULL,1)$$,'42501',NULL,'actual authenticated role denied');
RESET ROLE;
SELECT set_config('request.jwt.claim.role','anon',TRUE);
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.resolve_owned_observation_media(NULL,NULL,NULL,NULL,1)$$,'42501',NULL,'actual anonymous role denied');
RESET ROLE;
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.resolve_owned_observation_media(NULL,NULL,NULL,NULL,1)$$,'22023','invalid_analysis_history','actual service role reaches validation only');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

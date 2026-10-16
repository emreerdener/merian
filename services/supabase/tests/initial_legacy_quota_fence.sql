\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.ok(has_function_privilege('service_role',
 'public.reserve_ai_quota(uuid,text,uuid,text)','EXECUTE'),'legacy service ABI retained');
SELECT extensions.ok(NOT has_function_privilege(role_name,
 'public.reserve_ai_quota(uuid,text,uuid,text)','EXECUTE'),'client legacy ABI denied')
 FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,
 'internal.reserve_ai_quota_core(uuid,text,uuid,text)','EXECUTE'),'private core remains private')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(prosecdef AND provolatile='v'
 AND proconfig @> ARRAY['search_path=""','statement_timeout=5s']
 AND pg_get_userbyid(proowner)='postgres','legacy wrapper privilege and snapshot attributes')
 FROM pg_proc WHERE oid='public.reserve_ai_quota(uuid,text,uuid,text)'::regprocedure;
SELECT extensions.ok(NOT initial_analysis_lifecycle_enabled,'initial activation remains off')
 FROM internal.initial_analysis_rollout;

SELECT * FROM extensions.finish();
ROLLBACK;

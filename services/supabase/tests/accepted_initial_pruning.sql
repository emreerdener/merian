BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(9);

SELECT extensions.ok(NOT has_function_privilege(role_name,
    'internal.preserve_accepted_initial_finalization_inputs()','EXECUTE'),
    role_name||' cannot invoke the trigger directly')
    FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(prosecdef,'operational DELETE invokes the private guard with its reviewed owner')
    FROM pg_catalog.pg_proc WHERE oid='internal.preserve_accepted_initial_finalization_inputs()'::regprocedure;
SELECT extensions.ok(proconfig @> ARRAY['search_path=""'],'private guard has an empty search path')
    FROM pg_catalog.pg_proc WHERE oid='internal.preserve_accepted_initial_finalization_inputs()'::regprocedure;
SELECT extensions.is(tgtype::INTEGER,11,'row-level BEFORE DELETE protects '||tgrelid::regclass::TEXT)
    FROM pg_catalog.pg_trigger WHERE tgname='a_preserve_accepted_initial_finalization'
    AND tgrelid IN ('public.scan_ingestion_jobs'::regclass,'public.scan_ingestion_intents'::regclass);
SELECT extensions.ok('a_preserve_accepted_initial_finalization'<'guard_ordinary_initial_job',
    'prune preservation executes before terminal erasure');
SELECT extensions.is(ordinary_initial_evidence_enabled,FALSE,'prepared evidence remains disabled')
    FROM internal.observation_history_rollout;
SELECT * FROM extensions.finish();
ROLLBACK;

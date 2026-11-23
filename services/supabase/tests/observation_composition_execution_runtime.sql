BEGIN;
SELECT no_plan();
SELECT ok(NOT composition_analysis_enabled AND NOT composition_dispatch_enabled AND NOT composition_runtime_enabled,'composition execution defaults closed') FROM internal.observation_history_rollout;
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private runtime denied '||role_name||' '||p.proname)
 FROM pg_proc p CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
 WHERE p.pronamespace='internal'::regnamespace AND p.proname IN (
 'admit_composition_observation_analysis','lock_composition_observation_analysis','assert_composition_observation_dispatchable',
 'claim_composition_observation_analysis','dispatch_composition_observation_analysis','record_composition_observation_outcome',
 'record_composition_observation_draft','account_composition_observation_draft','settle_composition_observation_terminal',
 'complete_composition_observation_analysis','release_completed_composition_source');
SELECT ok(relrowsecurity,'private proof has RLS') FROM pg_class WHERE oid IN (
 'internal.observation_composition_accounting_receipts'::regclass,
 'internal.observation_composition_terminal_receipts'::regclass,
 'internal.observation_composition_source_completions'::regclass);
SELECT ok(NOT has_table_privilege(role_name,relation,'SELECT,INSERT,UPDATE,DELETE'),'proof table denied '||role_name)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.observation_composition_accounting_receipts','internal.observation_composition_terminal_receipts','internal.observation_composition_source_completions']) relation;
SELECT * FROM finish();
ROLLBACK;

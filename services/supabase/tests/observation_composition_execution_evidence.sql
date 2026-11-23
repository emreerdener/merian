BEGIN;
SELECT no_plan();
SELECT ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'] FROM pg_proc WHERE oid='internal.assert_ready_composition_analysis_evidence(uuid,uuid,uuid,jsonb)'::regprocedure),'private bounded complete-cohort guard');
SELECT ok((SELECT NOT prosecdef AND provolatile='s' AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid='internal.observation_composition_execution_profile(jsonb)'::regprocedure),'profile is a private stable invoker');
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'helper denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['internal.assert_ready_composition_analysis_evidence(uuid,uuid,uuid,jsonb)','internal.observation_composition_execution_profile(jsonb)']) signature;
SELECT ok(NOT EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature=signature),'no new API grant')
FROM unnest(ARRAY['internal.assert_ready_composition_analysis_evidence(uuid,uuid,uuid,jsonb)','internal.observation_composition_execution_profile(jsonb)']) signature;
SELECT ok(NOT composition_runtime_enabled AND NOT composition_evidence_enabled AND NOT admission_enabled,'admission remains closed') FROM internal.observation_history_rollout;
SELECT * FROM finish();
ROLLBACK;

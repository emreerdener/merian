BEGIN;
SELECT no_plan();
SELECT ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'] FROM pg_proc WHERE oid='internal.assert_ready_video_analysis_evidence(uuid,uuid,uuid,jsonb)'::regprocedure),'private bounded guard');
SELECT ok(NOT has_function_privilege(role_name,'internal.assert_ready_video_analysis_evidence(uuid,uuid,uuid,jsonb)','EXECUTE'),'guard denied to '||role_name) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok(NOT EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature='internal.assert_ready_video_analysis_evidence(uuid,uuid,uuid,jsonb)'),'no new API grant');
SELECT ok(NOT media_enabled AND NOT video_evidence_enabled AND NOT protected_analysis_enabled,'existing gates remain closed') FROM internal.observation_history_rollout;
SELECT * FROM finish();
ROLLBACK;

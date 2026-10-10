BEGIN;
SELECT no_plan();
SELECT ok(NOT video_analysis_enabled,'video admission defaults closed') FROM internal.observation_history_rollout;
SELECT ok(NOT has_function_privilege(role_name,'internal.admit_video_observation_analysis(uuid,jsonb,text)','EXECUTE'),'private admission denied '||role_name) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'] FROM pg_proc WHERE oid='internal.admit_video_observation_analysis(uuid,jsonb,text)'::regprocedure),'bounded private admission');
SELECT ok(position('admit_video_observation_analysis' IN pg_get_functiondef('public.begin_owned_observation_analysis(uuid,jsonb,text)'::regprocedure))=0,'public begin remains unconnected');
SELECT ok(position('assert_ready_video_analysis_evidence' IN pg_get_functiondef('internal.guard_source_bound_analysis_intent()'::regprocedure))>0,'storage backstop verifies V4 readiness');
SELECT * FROM finish();
ROLLBACK;

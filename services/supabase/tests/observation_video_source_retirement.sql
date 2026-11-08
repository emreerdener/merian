BEGIN;
SELECT no_plan();
SELECT ok(NOT video_source_retirement_enabled,'video retirement defaults closed') FROM internal.observation_history_rollout;
SELECT ok(has_function_privilege('service_role','public.retire_owned_observation_video_source(uuid,jsonb,integer)','EXECUTE'),'service-only retirement grant');
SELECT ok(NOT has_function_privilege(role_name,'public.retire_owned_observation_video_source(uuid,jsonb,integer)','EXECUTE'),'denied retirement role '||role_name) FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_source_retirements','SELECT,INSERT,UPDATE,DELETE'),'private retirement table '||role_name) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.observation_video_source_retirements'::regclass),'retirement RLS');
SELECT ok((SELECT proconfig @> ARRAY['search_path=""','statement_timeout=5s'] AND prosecdef FROM pg_proc WHERE oid='public.retire_owned_observation_video_source(uuid,jsonb,integer)'::regprocedure),'fixed service boundary');
SELECT ok(EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature='public.retire_owned_observation_video_source(uuid,jsonb,integer)' AND role_name='service_role'),'registered grant');
SELECT ok(position('observation_video_source' IN pg_get_functiondef('internal.observation_source_release_proven(internal.observation_analysis_source_bindings)'::regprocedure))=0,'legacy release proof not widened');
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private helper denied '||role_name||' '||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN('observation_video_source_identity','observation_video_source_preexecution_clear','observation_video_retirement_record_valid','observation_video_source_release_proven','observation_video_retirement_can_remove','guard_observation_video_retirement');
SELECT * FROM finish();
ROLLBACK;

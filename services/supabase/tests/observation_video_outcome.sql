BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private video outcome denied '||role_name||'/'||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
'internal.assert_video_analysis_dispatch_identity(internal.observation_analysis_intents)',
'internal.record_video_observation_outcome(uuid,uuid,uuid,uuid,jsonb)',
'internal.read_video_observation_outcome(uuid,uuid,uuid)']) signature;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded private outcome helper '||proname)
FROM pg_proc WHERE pronamespace='internal'::regnamespace AND proname IN ('assert_video_analysis_dispatch_identity','record_video_observation_outcome','read_video_observation_outcome');
SELECT ok(position('input_snapshot->''schema_version''<>''4''::JSONB' IN pg_get_functiondef('public.list_observation_analysis_recovery()'::regprocedure))>0,'legacy recovery discovery excludes V4');
SELECT * FROM finish();
ROLLBACK;

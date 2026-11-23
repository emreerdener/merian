BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'private video outcome denied '||role_name||'/'||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
'internal.assert_video_analysis_dispatch_identity(internal.observation_analysis_intents)',
'internal.record_video_observation_outcome(uuid,uuid,uuid,uuid,jsonb)',
'internal.read_video_observation_outcome(uuid,uuid,uuid)']) signature;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded private outcome helper '||proname)
FROM pg_proc WHERE pronamespace='internal'::regnamespace AND proname IN ('assert_video_analysis_dispatch_identity','record_video_observation_outcome','read_video_observation_outcome');
SELECT ok(position($excluded$input_snapshot->'schema_version' NOT IN ('4'::JSONB,'5'::JSONB,'6'::JSONB)$excluded$ IN pg_get_functiondef('public.list_observation_analysis_recovery()'::regprocedure))>0,'legacy recovery discovery excludes dedicated video and composition contracts');
SELECT * FROM finish();
ROLLBACK;

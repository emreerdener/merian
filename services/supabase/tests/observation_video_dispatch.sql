BEGIN;
SELECT no_plan();
SELECT ok(NOT video_dispatch_enabled,'private video dispatch defaults closed') FROM internal.observation_history_rollout;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'video execution private to '||role_name||'/'||signature)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
'internal.lock_video_observation_analysis(uuid,uuid,uuid)',
'internal.assert_video_observation_dispatchable(internal.observation_analysis_intents)',
'internal.claim_video_observation_analysis(uuid,uuid,uuid)',
'internal.dispatch_video_observation_analysis(uuid,uuid,uuid,uuid,jsonb)']) signature;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded private helper '||proname)
FROM pg_proc WHERE pronamespace='internal'::regnamespace AND proname IN ('lock_video_observation_analysis','assert_video_observation_dispatchable','claim_video_observation_analysis','dispatch_video_observation_analysis');
SELECT ok(position('observation_video_source_fingerprint' IN pg_get_functiondef('internal.lock_observation_analysis_source(uuid,uuid,uuid)'::regprocedure))=0,'generic execution lock still rejects V4');
SELECT * FROM finish();
ROLLBACK;

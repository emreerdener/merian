BEGIN;
SELECT no_plan();
SELECT ok(NOT video_orchestration_enabled,'video orchestration defaults closed') FROM internal.observation_history_rollout;
SELECT ok(NOT video_dispatch_enabled AND NOT video_analysis_enabled AND NOT orchestration_enabled,'existing execution gates stay closed') FROM internal.observation_history_rollout;
SELECT is(count(*)::integer,4,'four explicit video service boundaries') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('begin_owned_observation_video_analysis','claim_observation_video_analysis_recovery','list_observation_video_analysis_recovery','advance_owned_observation_video_analysis');
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""'],'fixed service owner '||proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('begin_owned_observation_video_analysis','claim_observation_video_analysis_recovery','list_observation_video_analysis_recovery','advance_owned_observation_video_analysis');
SELECT ok(has_function_privilege(role_name,p.oid,'EXECUTE')=(role_name='service_role'),'boundary grant '||role_name||'/'||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='public' AND p.proname IN ('begin_owned_observation_video_analysis','claim_observation_video_analysis_recovery','list_observation_video_analysis_recovery','advance_owned_observation_video_analysis');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='public' AND p.proname IN ('begin_owned_observation_video_analysis','claim_observation_video_analysis_recovery','list_observation_video_analysis_recovery','advance_owned_observation_video_analysis') AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC has no video worker authority');
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private state owner remains private '||role_name||'/'||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('admit_video_observation_analysis','claim_video_observation_analysis','dispatch_video_observation_analysis','record_video_observation_outcome','read_video_observation_outcome','record_video_observation_draft','account_video_observation_draft','settle_video_observation_terminal','complete_video_observation_analysis');
SELECT * FROM finish();
ROLLBACK;

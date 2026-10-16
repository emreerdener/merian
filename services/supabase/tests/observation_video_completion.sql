BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private completion denied '||role_name||' '||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('assert_accounted_video_analysis','assert_video_completion_evidence','video_analysis_completion_matches','complete_video_observation_analysis');
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded completion writer') FROM pg_proc WHERE oid='internal.complete_video_observation_analysis(uuid,uuid,uuid,uuid)'::regprocedure;
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='internal' AND p.proname IN ('assert_accounted_video_analysis','assert_video_completion_evidence','video_analysis_completion_matches','complete_video_observation_analysis') AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC cannot complete');
SELECT * FROM finish();
ROLLBACK;

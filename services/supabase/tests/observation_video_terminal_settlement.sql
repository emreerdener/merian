BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private terminal settlement denied '||role_name||' '||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('video_analysis_terminal_product','video_analysis_terminal_accounting','video_analysis_terminal_candidate','guard_video_analysis_terminal','settle_video_observation_terminal');
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_terminal_receipts','SELECT,INSERT,UPDATE,DELETE'),'terminal receipt denied '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok(relrowsecurity,'terminal receipt RLS enabled') FROM pg_class WHERE oid='internal.observation_video_terminal_receipts'::regclass;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded terminal writer') FROM pg_proc WHERE oid='internal.settle_video_observation_terminal(uuid,uuid,uuid,uuid)'::regprocedure;
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='internal' AND p.proname IN ('video_analysis_terminal_product','video_analysis_terminal_accounting','video_analysis_terminal_candidate','guard_video_analysis_terminal','settle_video_observation_terminal') AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC cannot settle');
SELECT * FROM finish();
ROLLBACK;

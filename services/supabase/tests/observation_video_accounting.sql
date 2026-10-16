BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private accounting denied '||role_name||' '||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('video_analysis_accounting_product','video_analysis_accounting_invocation','video_analysis_accounting_candidate','guard_video_analysis_accounting','account_video_observation_draft');
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_accounting_receipts','SELECT,INSERT,UPDATE,DELETE'),'receipt denied '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok(relrowsecurity,'accounting receipt RLS enabled') FROM pg_class WHERE oid='internal.observation_video_accounting_receipts'::regclass;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded accounting writer') FROM pg_proc WHERE oid='internal.account_video_observation_draft(uuid,uuid,uuid,uuid)'::regprocedure;
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='internal' AND p.proname IN ('video_analysis_accounting_product','video_analysis_accounting_invocation','video_analysis_accounting_candidate','guard_video_analysis_accounting','account_video_observation_draft') AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC cannot account');
SELECT * FROM finish();
ROLLBACK;

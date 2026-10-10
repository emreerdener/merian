BEGIN;
SELECT no_plan();
SELECT ok(NOT has_function_privilege(role_name,'internal.record_video_observation_draft(uuid,uuid,uuid,uuid,jsonb)','EXECUTE'),'private draft denied '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'],'bounded private draft writer')
FROM pg_proc WHERE oid='internal.record_video_observation_draft(uuid,uuid,uuid,uuid,jsonb)'::regprocedure;
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid='internal.record_video_observation_draft(uuid,uuid,uuid,uuid,jsonb)'::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC cannot write drafts');
SELECT * FROM finish();
ROLLBACK;

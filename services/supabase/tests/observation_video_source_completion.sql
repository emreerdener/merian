BEGIN;
SELECT no_plan();
SELECT ok(NOT source_completion_release_enabled,'source completion remains disabled') FROM internal.observation_history_rollout;
SELECT ok(relrowsecurity,'private video completion proof RLS') FROM pg_class WHERE oid='internal.observation_video_source_completions'::regclass;
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_source_completions',privilege),'private proof '||role_name||'/'||privilege)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private helper '||role_name||'/'||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('video_source_completion_product','video_source_completion_candidate','video_source_completion_proven','guard_video_source_completion','release_completed_video_source');
SELECT ok(prosecdef AND proconfig @> ARRAY['search_path=""'],'fixed helper '||proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='internal' AND p.proname IN ('video_source_completion_product','video_source_completion_candidate','video_source_completion_proven','guard_video_source_completion','release_completed_video_source');
SELECT ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='internal' AND p.proname IN ('video_source_completion_product','video_source_completion_candidate','video_source_completion_proven','guard_video_source_completion','release_completed_video_source') AND a.grantee=0 AND a.privilege_type='EXECUTE'),'PUBLIC cannot release');
SELECT ok(position('identification_invocations' IN pg_get_functiondef('internal.video_source_completion_candidate(internal.observation_analysis_source_bindings)'::regprocedure))=0,'candidate survives invocation retention');
SELECT ok(position('expires_at' IN pg_get_functiondef('internal.video_source_completion_candidate(internal.observation_analysis_source_bindings)'::regprocedure))=0,'candidate does not re-enter fresh admission');
SELECT ok(position('release_completed_video_source' IN pg_get_functiondef('internal.complete_video_observation_analysis(uuid,uuid,uuid,uuid)'::regprocedure))>0,'original completion owns release');
SELECT ok(position('video_source_completion' IN pg_get_functiondef('internal.observation_source_completion_product(internal.observation_analysis_source_bindings)'::regprocedure))=0,'generic product unchanged');
SELECT * FROM finish();
ROLLBACK;

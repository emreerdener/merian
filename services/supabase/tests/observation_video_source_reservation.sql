BEGIN;
SELECT no_plan();
SELECT ok(NOT video_source_reservation_enabled AND NOT video_source_recovery_enabled,'video source gates default closed') FROM internal.observation_history_rollout;
SELECT ok(has_function_privilege('service_role',signature,'EXECUTE'),'service only RPC grant')
FROM unnest(ARRAY['public.reserve_owned_observation_video_source(uuid,jsonb,integer)','public.get_owned_observation_video_source(uuid,jsonb,integer)']) signature;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY['public.reserve_owned_observation_video_source(uuid,jsonb,integer)','public.get_owned_observation_video_source(uuid,jsonb,integer)']) signature;
SELECT ok((SELECT proconfig @> ARRAY['search_path=""','statement_timeout=5s'] AND prosecdef FROM pg_proc WHERE oid=signature::regprocedure),'fixed privileged boundary')
FROM unnest(ARRAY['public.reserve_owned_observation_video_source(uuid,jsonb,integer)','public.get_owned_observation_video_source(uuid,jsonb,integer)']) signature;
SELECT ok(EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature=signature AND role_name='service_role'),'exact allowlist entry')
FROM unnest(ARRAY['public.reserve_owned_observation_video_source(uuid,jsonb,integer)','public.get_owned_observation_video_source(uuid,jsonb,integer)']) signature;
SELECT ok(position('p_reader IS DISTINCT FROM 11' IN pg_get_functiondef('public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)'::regprocedure))>0,'reader11 unchanged');
SELECT ok(position('observation_video_source_fingerprint' IN pg_get_functiondef('internal.observation_source_release_proven(internal.observation_analysis_source_bindings)'::regprocedure))=0,'no V4 release authority');
SELECT * FROM finish();
ROLLBACK;

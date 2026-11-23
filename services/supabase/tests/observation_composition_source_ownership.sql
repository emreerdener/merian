BEGIN;
SELECT no_plan();
SELECT ok(NOT composition_source_reservation_enabled AND NOT composition_source_recovery_enabled AND NOT composition_runtime_enabled,'composition source gates default closed') FROM internal.observation_history_rollout;
SELECT ok(has_function_privilege('service_role',signature,'EXECUTE'),'service only RPC grant')
FROM unnest(ARRAY['public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','public.get_owned_observation_composition_source(uuid,jsonb,integer)']) signature;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY['public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','public.get_owned_observation_composition_source(uuid,jsonb,integer)']) signature;
SELECT ok((SELECT proconfig @> ARRAY['search_path=""','statement_timeout=5s'] AND prosecdef FROM pg_proc WHERE oid=signature::regprocedure),'fixed privileged boundary')
FROM unnest(ARRAY['public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','public.get_owned_observation_composition_source(uuid,jsonb,integer)']) signature;
SELECT ok(EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature=signature AND role_name='service_role'),'exact allowlist entry')
FROM unnest(ARRAY['public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','public.get_owned_observation_composition_source(uuid,jsonb,integer)']) signature;
SELECT ok(position('p_reader IS DISTINCT FROM 11' IN pg_get_functiondef('public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)'::regprocedure))>0,'reader11 unchanged');
SELECT ok(position('p_reader IS DISTINCT FROM 12' IN pg_get_functiondef('public.reserve_owned_observation_video_source(uuid,jsonb,integer)'::regprocedure))>0,'reader12 unchanged');
SELECT ok(position($reader$p_reader IS DISTINCT FROM (CASE WHEN p_request->'fingerprint_version'='2'::JSONB THEN 15 ELSE 14 END)$reader$ IN pg_get_functiondef(signature::regprocedure))>0,'reader14 for legacy composition; reader15 for focused composition')
FROM unnest(ARRAY['public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','public.get_owned_observation_composition_source(uuid,jsonb,integer)']) signature;
SELECT ok(position('composition_runtime_enabled' IN pg_get_functiondef('public.reserve_owned_observation_composition_source(uuid,jsonb,integer)'::regprocedure))>0,'fresh source reservation requires runtime gate');
SELECT ok(relrowsecurity,'private inventory has RLS') FROM pg_class WHERE oid='internal.observation_composition_evidence_upload_cohorts'::regclass;
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_composition_evidence_upload_cohorts',privilege),'no inventory '||privilege||' for '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
SELECT ok(position('observation_composition_evidence_upload_cohorts' IN pg_get_functiondef(signature::regprocedure))>0,'composition namespace covered')
FROM unnest(ARRAY['internal.observation_source_child_is_unused(uuid)','internal.validate_observation_source_binding()','internal.validate_observation_source_cohort()','public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)','public.reserve_owned_observation_video_source(uuid,jsonb,integer)','public.get_owned_observation_analysis_source(uuid,jsonb,integer)']) signature;
SELECT ok(position('observation_composition_source_fingerprint' IN pg_get_functiondef('internal.observation_source_release_proven(internal.observation_analysis_source_bindings)'::regprocedure))=0,'no V5 legacy release authority');
SELECT * FROM finish();
ROLLBACK;

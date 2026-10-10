BEGIN;
SELECT no_plan();
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.observation_video_evidence_upload_cohorts'::regclass),'video RLS enabled');
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_evidence_upload_cohorts','SELECT,INSERT,UPDATE,DELETE'),'video table denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'video helper denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['internal.lock_owned_observation_video_source_binding(uuid,uuid,uuid,jsonb)','internal.guard_observation_video_cohort()']) signature;
SELECT ok((SELECT proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=signature::regprocedure),'fixed empty path')
FROM unnest(ARRAY['internal.lock_owned_observation_video_source_binding(uuid,uuid,uuid,jsonb)','internal.guard_observation_video_cohort()']) signature;
SELECT ok(position('observation_video_evidence_upload_cohorts' IN pg_get_functiondef(signature::regprocedure))>0,'video included in '||signature)
FROM unnest(ARRAY['internal.validate_observation_source_binding()','internal.observation_source_child_is_unused(uuid)','public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)','public.get_owned_observation_analysis_source(uuid,jsonb,integer)','internal.validate_observation_source_cohort()']) signature;
SELECT ok(position('observation_video_source_fingerprint' IN pg_get_functiondef(signature::regprocedure))=0,'legacy lifecycle remains V4 closed: '||signature)
FROM unnest(ARRAY['internal.lock_owned_observation_source_binding(uuid,uuid,uuid,jsonb)','internal.observation_source_release_proven(internal.observation_analysis_source_bindings)','internal.observation_source_completion_product(internal.observation_analysis_source_bindings)','public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)']) signature;
SELECT * FROM finish();
ROLLBACK;

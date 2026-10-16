BEGIN;
SELECT no_plan();
SELECT ok(NOT video_evidence_enabled,'video evidence defaults closed') FROM internal.observation_history_rollout;
SELECT ok(has_function_privilege('service_role',signature,'EXECUTE'),'service boundary '||signature)
FROM unnest(ARRAY['public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)','public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_video_evidence()']) signature;
SELECT ok(EXISTS(SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature=signature AND role_name='service_role'),'registered '||signature)
FROM unnest(ARRAY['public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)','public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_video_evidence()']) signature;
SELECT ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""','statement_timeout=10s'] FROM pg_proc WHERE oid=signature::regprocedure),'bounded security definer '||signature)
FROM unnest(ARRAY['public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)','public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_video_evidence()']) signature;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'denied '||role_name||' '||signature)
FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY['public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)','public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_video_evidence()']) signature;
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_video_evidence_allocations','SELECT,INSERT,UPDATE,DELETE'),'private allocation '||role_name) FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='internal.observation_video_evidence_allocations'::regclass),'allocation RLS');
SELECT ok(position('observation_video_evidence_allocations' IN pg_get_functiondef('internal.observation_video_source_preexecution_clear(uuid)'::regprocedure))>0,'retirement refuses retained allocations');
SELECT ok(position('observation_video_evidence_allocations' IN pg_get_functiondef('internal.observation_video_evidence_execution_clear(uuid)'::regprocedure))=0,'post-allocation execution fence permits allocation');
SELECT ok(position('observation_evidence_objects' IN pg_get_functiondef('internal.observation_video_evidence_execution_clear(uuid)'::regprocedure))=0,'post-allocation execution fence permits own objects');
SELECT ok(position('observation_video_evidence_allocations' IN pg_get_functiondef(signature::regprocedure))>0,'legacy expiry excludes video '||signature)
FROM unnest(ARRAY['internal.expire_observation_evidence(uuid)','internal.expire_unbound_observation_evidence(uuid)','public.retire_expired_observation_evidence()']) signature;
SELECT ok(NOT has_function_privilege(role_name,p.oid,'EXECUTE'),'private helper '||role_name||' '||p.proname)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
WHERE n.nspname='internal' AND p.proname IN ('observation_video_evidence_execution_clear','lock_video_evidence_request','guard_video_evidence_allocation','guard_video_evidence_object','video_evidence_receipt');
SELECT * FROM finish();
ROLLBACK;

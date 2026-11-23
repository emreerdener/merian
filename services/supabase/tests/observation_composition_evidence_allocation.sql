BEGIN;
SELECT no_plan();
SELECT ok(NOT composition_evidence_enabled AND NOT composition_runtime_enabled,'composition evidence stays closed') FROM internal.observation_history_rollout;
SELECT ok(relrowsecurity,'allocation RLS') FROM pg_class WHERE oid='internal.observation_composition_evidence_allocations'::regclass;
SELECT ok(NOT has_table_privilege(role_name,'internal.observation_composition_evidence_allocations',privilege),'no direct allocation '||privilege||' for '||role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) privilege;
SELECT ok(has_function_privilege('service_role',signature,'EXECUTE'),'service-only allocation/cleanup boundary')
FROM unnest(ARRAY['public.reserve_owned_observation_composition_evidence(uuid,jsonb,integer)','public.complete_owned_observation_composition_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_composition_evidence_for_dispatch(uuid)']) signature;
SELECT ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'denied to '||role_name)
FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY['public.reserve_owned_observation_composition_evidence(uuid,jsonb,integer)','public.complete_owned_observation_composition_evidence(uuid,jsonb,uuid,uuid,integer)','public.retire_expired_observation_composition_evidence_for_dispatch(uuid)']) signature;
SELECT ok(NOT has_function_privilege('service_role',signature,'EXECUTE'),'private helper denied')
FROM unnest(ARRAY['internal.lock_composition_evidence_request(uuid,jsonb,integer)','internal.guard_composition_evidence_object()','internal.retire_expired_observation_composition_evidence_worker_impl()']) signature;
SELECT ok(position('require_observation_evidence_dispatch' IN pg_get_functiondef('public.retire_expired_observation_composition_evidence_for_dispatch(uuid)'::regprocedure))>0,'cleanup retains current dispatch fence');
SELECT ok(position('observation_composition_evidence_allocations' IN pg_get_functiondef(signature::regprocedure))>0,'old expiry excludes mixed allocation')
FROM unnest(ARRAY['internal.expire_observation_evidence(uuid)','internal.expire_unbound_observation_evidence(uuid)','internal.retire_expired_observation_evidence_worker_impl()']) signature;
SELECT * FROM finish();
ROLLBACK;

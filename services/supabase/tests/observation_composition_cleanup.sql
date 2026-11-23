BEGIN;
SELECT no_plan();
SELECT ok(NOT enabled,'worker remains inactive') FROM internal.observation_evidence_worker_state;
SELECT ok(NOT composition_runtime_enabled AND NOT composition_evidence_enabled,'mixed runtime remains closed') FROM internal.observation_history_rollout;
SELECT ok(NOT has_function_privilege('service_role','internal.valid_composition_evidence_worker_counts(jsonb)','EXECUTE'),'private count validator');
CREATE FUNCTION pg_temp.composition_worker_receipt() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT '{"schema_version":3,"dispatch_id":"00000000-0000-4000-8000-00000000ee01","retired":5,"video_retired":7,"composition_retired":8,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}'::jsonb;
$$;
SELECT ok(internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt(),'00000000-0000-4000-8000-00000000ee01'),'complete V3 maxima');
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt(),'00000000-0000-4000-8000-00000000ee02'),'wrong dispatch rejected');
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt()-'composition_retired','00000000-0000-4000-8000-00000000ee01'),'missing mixed count rejected');
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(jsonb_set(pg_temp.composition_worker_receipt(),'{composition_retired}',value),'00000000-0000-4000-8000-00000000ee01'),'invalid mixed count: '||value::text)
FROM unnest(ARRAY['9'::jsonb,'-1','1.5','"1"','null']) value;
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt()||'{"object_id":"synthetic"}','00000000-0000-4000-8000-00000000ee01'),'extra identity forbidden');
SELECT ok(internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt()||'{"retirement_failures":3}','00000000-0000-4000-8000-00000000ee01'),'all three stage failures observable');
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt()||'{"retirement_failures":4}','00000000-0000-4000-8000-00000000ee01'),'failure count bounded');
SELECT ok(internal.valid_observation_evidence_worker_receipt((pg_temp.composition_worker_receipt()-'composition_retired')||'{"schema_version":2}','00000000-0000-4000-8000-00000000ee01'),'old correlated terminal receipt still accepted');
SELECT ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.composition_worker_receipt()||'{"schema_version":2}','00000000-0000-4000-8000-00000000ee01'),'V2 cannot carry V3 capabilities');
-- Synthetic transport responses only. Disabled scheduling makes reconciliation
-- observable without queuing HTTP; all state is rolled back.
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-42001,pending_dispatch_id='00000000-0000-4000-8000-00000000ee01',last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-42001,200,pg_temp.composition_worker_receipt()::text,FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT ok(pending_request_id IS NULL AND last_result='success' AND last_composition_retired=8 AND last_receipt_schema_version=3,'V3 terminal count persisted with original correlation') FROM internal.observation_evidence_worker_state;
SELECT is((public.get_observation_evidence_erasure_health()->'worker'->>'last_receipt_schema_version')::int,3,'health reports observed worker generation');
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-42002,pending_dispatch_id='00000000-0000-4000-8000-00000000ee01',last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-42002,200,((pg_temp.composition_worker_receipt()-'composition_retired')||'{"schema_version":2}')::text,FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT ok(last_receipt_schema_version=2 AND last_composition_retired IS NULL,'old receipt never invents mixed worker health') FROM internal.observation_evidence_worker_state;
SELECT is((public.get_observation_evidence_erasure_health()->'retirement'->>'composition')::bigint,0::bigint,'empty mixed candidate inventory');
SELECT * FROM finish();
ROLLBACK;

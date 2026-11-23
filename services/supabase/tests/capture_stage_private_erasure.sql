\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- Isolate ordering/count assertions from earlier local synthetic fixtures.
-- Both queue inventories are restored by this test's final rollback.
DELETE FROM internal.observation_evidence_erasure;
DELETE FROM internal.initial_capture_audio_stage_erasure;
-- Synthetic local authority and opaque objects only. No HTTP dispatch occurs.
SELECT vault.create_secret('https://abcdefghijklmnopqrst.supabase.co','SUPABASE_URL') IS NOT NULL;
SELECT vault.create_secret('sb_secret_'||repeat('a',30),'SUPABASE_SERVICE_ROLE_KEY') IS NOT NULL;
UPDATE internal.observation_evidence_worker_state SET enabled=TRUE,approved_project='abcdefghijklmnopqrst',pending_request_id=-473,
 pending_dispatch_id='00000000-0000-4000-8000-00000000ee01';
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),'typed erasure denies client: '||role_name||signature)
FROM unnest(ARRAY['anon','authenticated']) role_name CROSS JOIN unnest(ARRAY[
 'public.claim_private_evidence_erasure_v4_for_dispatch(uuid)',
 'public.finish_private_evidence_erasure_v4(text,uuid,uuid,text,boolean)']) signature;
SELECT extensions.ok(has_function_privilege('service_role',signature,'EXECUTE'),'typed service grant: '||signature)
FROM unnest(ARRAY['public.claim_private_evidence_erasure_v4_for_dispatch(uuid)','public.finish_private_evidence_erasure_v4(text,uuid,uuid,text,boolean)']) signature;
INSERT INTO internal.initial_capture_audio_stage_erasure(object_id,backend_sha256,available_at) VALUES
 ('00000000-0000-4000-8000-00000000ea01',repeat('a',64),transaction_timestamp()-interval '3 minutes'),
 ('00000000-0000-4000-8000-00000000ea02',repeat('a',64),transaction_timestamp()-interval '1 minute');
SET LOCAL ROLE service_role;
SELECT extensions.is(public.claim_observation_evidence_erasure_for_dispatch('00000000-0000-4000-8000-00000000ee01'),NULL::JSONB,'old worker cannot acquire stage objects');
SELECT extensions.throws_ok($$SELECT public.claim_private_evidence_erasure_v4_for_dispatch(NULL)$$,'42501','private_evidence_dispatch_unavailable','missing dispatch fails closed');
SELECT extensions.throws_ok($$SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee02')$$,'42501','private_evidence_dispatch_unavailable','wrong dispatch fails closed');
RESET ROLE;
INSERT INTO internal.observation_evidence_erasure(object_id,available_at) VALUES
 ('00000000-0000-4000-8000-00000000ea03',transaction_timestamp()-interval '2 minutes');
SET LOCAL ROLE service_role;
CREATE TEMP TABLE first_claim AS SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01') value;
SELECT extensions.is((SELECT value->>'object_id' FROM first_claim),'00000000-0000-4000-8000-00000000ea01','oldest stage precedes History work');
SELECT extensions.is((SELECT value->>'namespace' FROM first_claim),'capture_stage','stage target is explicit');
SELECT extensions.is((SELECT value->>'backend_sha256' FROM first_claim),repeat('a',64),'recorded backend accompanies claim');
SELECT extensions.is((SELECT count(*)::int FROM first_claim,jsonb_object_keys(value)),5,'typed claim is closed and opaque');
SELECT extensions.ok((SELECT (value->>'claim_expires_at')::timestamptz BETWEEN clock_timestamp()+interval '58 seconds' AND clock_timestamp()+interval '61 seconds' FROM first_claim),'lease remains sixty seconds');
SELECT extensions.is(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea01',(SELECT (value->>'claim_token')::uuid FROM first_claim),repeat('b',64),TRUE),FALSE,'wrong backend cannot settle');
SELECT extensions.is(public.finish_private_evidence_erasure_v4('history','00000000-0000-4000-8000-00000000ea01',(SELECT (value->>'claim_token')::uuid FROM first_claim),NULL,TRUE),FALSE,'wrong namespace cannot settle');
SELECT extensions.is(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea01',gen_random_uuid(),repeat('a',64),TRUE),FALSE,'wrong token cannot settle');
SELECT extensions.throws_ok($$SELECT public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea01',gen_random_uuid(),NULL,TRUE)$$,'22023','invalid_analysis_history','stage backend cannot be omitted');
CREATE TEMP TABLE second_claim AS SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01') value;
SELECT extensions.is((SELECT value->>'object_id' FROM second_claim),'00000000-0000-4000-8000-00000000ea03','older History work precedes newer stage');
SELECT extensions.is((SELECT value->>'namespace' FROM second_claim),'history','History namespace retained');
SELECT extensions.is((SELECT value->'backend_sha256' FROM second_claim),'null'::jsonb,'History does not acquire a stage backend');
RESET ROLE;
UPDATE internal.observation_evidence_worker_state SET enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01')$$,'42501','private_evidence_dispatch_unavailable','pause prevents new acquisition');
SELECT extensions.ok(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea01',(SELECT (value->>'claim_token')::uuid FROM first_claim),repeat('a',64),TRUE),'existing stage claim settles after pause');
SELECT extensions.ok(public.finish_private_evidence_erasure_v4('history','00000000-0000-4000-8000-00000000ea03',(SELECT (value->>'claim_token')::uuid FROM second_claim),NULL,TRUE),'existing History claim settles after pause');
SELECT extensions.is(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea01',(SELECT (value->>'claim_token')::uuid FROM first_claim),repeat('a',64),TRUE),FALSE,'consumed stage claim cannot replay');
RESET ROLE;
UPDATE internal.observation_evidence_worker_state SET enabled=TRUE;
SET LOCAL ROLE service_role;
CREATE TEMP TABLE failed_claim AS SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01') value;
SELECT extensions.ok(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea02',(SELECT (value->>'claim_token')::uuid FROM failed_claim),repeat('a',64),FALSE),'failed marker settles with retained obligation');
RESET ROLE;
SELECT extensions.is((public.get_observation_evidence_erasure_health()->>'schema_version')::int,2,'health exposes typed queue generation');
SELECT extensions.is((public.get_observation_evidence_erasure_health()#>>'{capture_stage,pending}')::int,1,'failed stage remains pending');
SELECT extensions.is((public.get_observation_evidence_erasure_health()#>>'{capture_stage,deferred}')::int,1,'failure backs off');
SELECT extensions.is((public.get_observation_evidence_erasure_health()#>>'{capture_stage,marker_failures}')::int,1,'failure remains observable');
UPDATE internal.initial_capture_audio_stage_erasure SET available_at=clock_timestamp()-interval '1 second' WHERE object_id='00000000-0000-4000-8000-00000000ea02';
SET LOCAL ROLE service_role;
CREATE TEMP TABLE expired_claim AS SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01') value;
RESET ROLE;
UPDATE internal.initial_capture_audio_stage_erasure SET claim_expires_at=clock_timestamp()-interval '1 second',first_observed_at=NULL WHERE object_id='00000000-0000-4000-8000-00000000ea02';
SET LOCAL ROLE service_role;
SELECT extensions.is(public.finish_private_evidence_erasure_v4('capture_stage','00000000-0000-4000-8000-00000000ea02',(SELECT (value->>'claim_token')::uuid FROM expired_claim),repeat('a',64),TRUE),FALSE,'expired claim cannot acknowledge storage');
RESET ROLE;
SELECT extensions.is((public.get_observation_evidence_erasure_health()#>>'{capture_stage,expired_claims}')::int,1,'unknown claim outcome remains visible');
SELECT extensions.is((public.get_observation_evidence_erasure_health()#>>'{capture_stage,unknown_age}')::int,1,'missing age is not invented');
-- Equal due times use stable namespace ordering and still issue one claim.
INSERT INTO internal.initial_capture_audio_stage_erasure(object_id,backend_sha256,available_at) VALUES ('00000000-0000-4000-8000-00000000ea04',repeat('a',64),transaction_timestamp()-interval '4 minutes');
INSERT INTO internal.observation_evidence_erasure(object_id,available_at) VALUES ('00000000-0000-4000-8000-00000000ea05',transaction_timestamp()-interval '4 minutes');
SET LOCAL ROLE service_role;
CREATE TEMP TABLE tie_claim AS SELECT public.claim_private_evidence_erasure_v4_for_dispatch('00000000-0000-4000-8000-00000000ee01') value;
SELECT extensions.is((SELECT value->>'object_id' FROM tie_claim),'00000000-0000-4000-8000-00000000ea04','stable tie picks stage first');
RESET ROLE;
SELECT extensions.ok((SELECT claim_token IS NULL FROM internal.observation_evidence_erasure WHERE object_id='00000000-0000-4000-8000-00000000ea05'),'one typed claim per acquisition');
CREATE FUNCTION pg_temp.receipt() RETURNS JSONB LANGUAGE SQL AS $$ SELECT '{"schema_version":4,"dispatch_id":"00000000-0000-4000-8000-00000000ee01","retired":0,"video_retired":0,"composition_retired":0,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}'::jsonb $$;
SELECT extensions.ok(internal.valid_observation_evidence_worker_receipt(pg_temp.receipt()||jsonb_build_object('schema_version',v),'00000000-0000-4000-8000-00000000ee01'),'correlated generation accepted: '||v) FROM unnest(ARRAY[3,4]) v;
SELECT extensions.ok(internal.valid_observation_evidence_worker_receipt((pg_temp.receipt()-'composition_retired')||'{"schema_version":2}','00000000-0000-4000-8000-00000000ee01'),'old V2 dispatch can still settle');
SELECT extensions.ok(NOT internal.valid_observation_evidence_worker_receipt(pg_temp.receipt()||'{"namespace":"capture_stage"}','00000000-0000-4000-8000-00000000ee01'),'receipt contains only aggregate counts');
UPDATE internal.observation_evidence_worker_state SET enabled=FALSE,pending_request_id=-474,last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-474,200,pg_temp.receipt()::text,FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok(last_result='success' AND last_receipt_schema_version=4 AND last_composition_retired=0,'dispatcher persists observed V4 capability') FROM internal.observation_evidence_worker_state;
SELECT * FROM extensions.finish();
ROLLBACK;

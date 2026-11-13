-- Inactive classification/retention boundary. Initial fixtures are injected
-- while only the new deny-all creation guard is disabled, then it is restored.
-- This does not qualify a dispatch producer or a positive erasure transition.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok((SELECT prosecdef AND pg_get_userbyid(proowner)='postgres'
 AND proconfig=ARRAY['search_path=""']::TEXT[] FROM pg_proc
 WHERE oid='internal.require_initial_invocation_erasure()'::REGPROCEDURE),
 'deferred retirement validator has trusted owner, definer authority and empty search path');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,
 LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.oid='internal.require_initial_invocation_erasure()'::REGPROCEDURE AND a.grantee=0)
 AND NOT has_function_privilege('anon','internal.require_initial_invocation_erasure()','EXECUTE')
 AND NOT has_function_privilege('authenticated','internal.require_initial_invocation_erasure()','EXECUTE')
 AND NOT has_function_privilege('service_role','internal.require_initial_invocation_erasure()','EXECUTE'),
 'deferred retirement validator remains unavailable for direct API calls');

CREATE FUNCTION pg_temp.invocation_provenance() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT '{"version":1,"provider":"gemini","binding":"gemini_baseline_v1","model":"gemini-2.5-flash","variant":"multimodal","operation":"scan_identification","policy_version":1,"prompt":"identify_vision_v1","schema":"merian_identify_v1","confidence":"unqualified","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":null,"timeout_ms":90000,"generation":{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}}'::JSONB
$$;
CREATE FUNCTION pg_temp.seed_accounting_row(p_id UUID,p_initial BOOLEAN DEFAULT FALSE,p_receipt UUID DEFAULT NULL) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO internal.identification_invocations(id,user_id,scan_id,reservation_id,attempt_count,lease_sha256,provider,model,binding,input_profile,effective_plan,policy_version,provenance,occurred_at,is_initial_analysis,initial_admission_receipt_id)
 VALUES(p_id,'00000000-0000-4000-8000-000000000302',p_id,p_id,1,repeat('a',64),'gemini','gemini-2.5-flash','gemini_baseline_v1','multimodal_photo_v1','free',1,pg_temp.invocation_provenance(),'2000-01-01T00:00:00Z',p_initial,p_receipt)
$$;
SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000301');
SELECT extensions.ok(NOT is_initial_analysis AND initial_admission_receipt_id IS NULL,'ordinary invocation retains ordinary defaults') FROM internal.identification_invocations WHERE id='00000000-0000-4000-8000-000000000301';
SELECT extensions.throws_ok($$SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000303',TRUE,'00000000-0000-4000-8000-000000000304')$$,'55000','initial_analysis_dispatch_unavailable','initial dispatch remains unavailable even with receipt');
SELECT extensions.throws_ok($$SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000303',FALSE,'00000000-0000-4000-8000-000000000304')$$,'55000','initial_analysis_dispatch_unavailable','ordinary invocation cannot carry receipt');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET is_initial_analysis=TRUE$$,'55000','initial_analysis_invocation_immutable','ordinary classification cannot be promoted');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET initial_admission_receipt_id='00000000-0000-4000-8000-000000000304'$$,'55000','initial_analysis_invocation_immutable','ordinary receipt cannot be added');
INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES('00000000-0000-4000-8000-000000000305');
SELECT extensions.throws_ok($$SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000305')$$,'55000','initial_analysis_dispatch_unavailable','initial operation cannot masquerade as ordinary insertion');
ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000303',TRUE,'00000000-0000-4000-8000-000000000304');
SELECT pg_temp.seed_accounting_row('00000000-0000-4000-8000-000000000306',TRUE,NULL);
ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET is_initial_analysis=FALSE WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_immutable','initial classification cannot be cleared');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET initial_admission_receipt_id=NULL WHERE id='00000000-0000-4000-8000-000000000303'$$,'55000','initial_analysis_invocation_immutable','receipt erasure remains closed pending integration');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET model='changed' WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_immutable','initial provenance identity cannot change');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,lease_sha256=NULL WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_immutable','unqualified anonymization cannot silently drop authority');
SELECT extensions.throws_ok($$DELETE FROM internal.identification_invocations WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_retained','direct initial pruning denied');
SELECT extensions.throws_ok($$TRUNCATE internal.identification_invocations$$,'55000','initial_analysis_invocation_retained','initial truncate denied');
SELECT extensions.is(internal.reconcile_identification_usage(1000),3,'five-minute accounting reconciles ordinary and both initial records');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE NOT is_initial_analysis),0::BIGINT,'ordinary thirty-day accounting still pruned');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis),2::BIGINT,'all initial records retained even with missing receipt');
SELECT extensions.is((SELECT count(*) FROM public.ai_usage_events WHERE source_id IN ('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000303','00000000-0000-4000-8000-000000000306') AND outcome='unknown'),3::BIGINT,'original accounting owner appends unknown events');
SELECT extensions.ok(event_id IS NOT NULL AND initial_admission_receipt_id='00000000-0000-4000-8000-000000000304' AND lease_sha256=repeat('a',64),'accounting preserves original initial correlation') FROM internal.identification_invocations WHERE id='00000000-0000-4000-8000-000000000303';
SELECT extensions.is(internal.complete_identification_usage(id,'draft','{}'),event_id,'late report reuses existing accounting event') FROM internal.identification_invocations WHERE id='00000000-0000-4000-8000-000000000303';
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET event_id=NULL WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_immutable','initial event cannot be cleared');
SELECT extensions.throws_ok($$UPDATE internal.identification_invocations SET event_id='00000000-0000-4000-8000-000000000399' WHERE is_initial_analysis$$,'55000','initial_analysis_invocation_immutable','initial event cannot be replaced');
SELECT extensions.is(internal.reconcile_identification_usage(1000),0,'reconciliation replay emits no new event');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis),2::BIGINT,'reconciliation replay retains classified rows');
SELECT extensions.is((SELECT count(*) FROM pg_constraint WHERE conrelid='internal.identification_invocations'::regclass AND contype='f'),0::BIGINT,'no receipt/owner foreign-key lock edge added');
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.guard_initial_invocation_authority()','EXECUTE'),role_name||' guard execution denied') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT prosecdef,'guard remains invoker') FROM pg_proc WHERE oid='internal.guard_initial_invocation_authority()'::regprocedure;
SELECT * FROM extensions.finish();
ROLLBACK;

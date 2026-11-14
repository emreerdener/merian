\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SET LOCAL request.jwt.claim.role='service_role';
CREATE FUNCTION pg_temp.release_manifest(p_id UUID,p_sha TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE config JSONB; encoded TEXT;
BEGIN
 config:=jsonb_build_object('assignments',internal.gemini_assignment_manifest(),
 'required_functions',(SELECT jsonb_object_agg('function_'||n,repeat('a',64)) FROM generate_series(1,20) n)||jsonb_build_object('gemini-release-smoke',repeat('a',64)),
 'required_gates','{"candidate_validation":true,"exact_source":true,"migrations":true,"privileged_routines":true,"function_deployment":true,"authorization_smokes":true,"independent_holds":true}'::JSONB,
 'smoke_cases',(SELECT jsonb_agg(jsonb_build_object('id','case_'||n,'digest',repeat('b',64),'model','gemini-3.5-flash-lite','reservation_microusd',100)) FROM generate_series(1,8) n));
 encoded:=config::TEXT;
 RETURN jsonb_build_object('version',1,'release_id',p_id,'target','synthetic_test','backend_sha',p_sha,'configuration_digest',encode(extensions.digest(convert_to(encoded,'UTF8'),'sha256'),'hex'),
 'configuration_text',encoded,'app',jsonb_build_object('version','1.0','build','1','source_fingerprint',repeat('c',64),'testflight_group','Synthetic group','availability_checked_at',now()-interval '1 minute'),
 'authorization',jsonb_build_object('reference','synthetic authorized release','backend_deployment',true,'activation',true,'provider_smokes',true,'protective_suspension',true,'spending_cap_microusd',800),
 'expected_previous_revision',(SELECT revision FROM internal.gemini_routing_head WHERE singleton),'window_start',now()-interval '1 minute','window_end',now()+interval '1 hour')::TEXT;
END;
$$;
CREATE TEMP TABLE test_release(id UUID,manifest TEXT);
SELECT extensions.throws_ok(format('SELECT internal.register_gemini_release(%L)',
 jsonb_set(pg_temp.release_manifest(gen_random_uuid(),repeat('1',40))::JSONB,
 '{app,availability_checked_at}',to_jsonb(value))::TEXT),
 '22023','gemini_release_manifest_invalid',label)
FROM (VALUES ((now()-interval '8 days')::TEXT,'stale TestFlight verification cannot qualify a release'),
 ((now()+interval '1 hour')::TEXT,'future TestFlight verification cannot qualify a release')) cases(value,label);
SELECT extensions.throws_ok(format('SELECT internal.register_gemini_release(%L)',
 (pg_temp.release_manifest(gen_random_uuid(),repeat('1',40))::JSONB #- '{app,availability_checked_at}')::TEXT),
 '22023','gemini_release_manifest_invalid','missing TestFlight verification cannot bypass SQL eligibility');
SELECT extensions.throws_ok(format('SELECT internal.register_gemini_release(%L)',
 jsonb_set(pg_temp.release_manifest(gen_random_uuid(),repeat('1',40))::JSONB,
 '{app,availability_checked_at}','null'::JSONB)::TEXT),
 '22023','gemini_release_manifest_invalid','null TestFlight verification cannot bypass SQL eligibility');
INSERT INTO test_release SELECT '00000000-0000-4000-8000-000000000010',pg_temp.release_manifest('00000000-0000-4000-8000-000000000010',repeat('1',40));
SELECT extensions.is(internal.register_gemini_release((SELECT manifest FROM test_release)),(SELECT id FROM test_release),'registers exact authorized frozen release');
SELECT extensions.is(internal.register_gemini_release((SELECT manifest FROM test_release)),(SELECT id FROM test_release),'exact registration retry is idempotent');
SELECT extensions.is((SELECT revision FROM internal.gemini_routing_head WHERE singleton),0::BIGINT,'release preparation does not activate');
CREATE TEMP TABLE claim(value JSONB);
INSERT INTO claim SELECT public.claim_gemini_release_smoke((SELECT id FROM test_release),'case_1',(SELECT configuration_digest FROM internal.gemini_activation_releases WHERE id=(SELECT id FROM test_release)));
SELECT extensions.ok((SELECT value ? 'owner_token' FROM claim),'first claim owns case');
SELECT extensions.ok(NOT public.claim_gemini_release_smoke((SELECT id FROM test_release),'case_1',(SELECT configuration_digest FROM internal.gemini_activation_releases WHERE id=(SELECT id FROM test_release))) ? 'owner_token','exact concurrent/retry claim never returns another execution owner');
SELECT extensions.is(public.advance_gemini_release_smoke((SELECT id FROM test_release),'case_1',(SELECT (value->>'owner_token')::UUID FROM claim),'dispatch'),'dispatch_intent','dispatch is durable before call');
SELECT extensions.is(public.advance_gemini_release_smoke((SELECT id FROM test_release),'case_1',(SELECT (value->>'owner_token')::UUID FROM claim),'uncertain'),'uncertain','lost response retains uncertainty');
SELECT extensions.is(public.claim_gemini_release_smoke((SELECT id FROM test_release),'case_1',(SELECT configuration_digest FROM internal.gemini_activation_releases WHERE id=(SELECT id FROM test_release)))->>'state','uncertain','uncertain execution never reruns or passes');
SELECT extensions.throws_ok($$SELECT internal.verify_gemini_release(id,(manifest::JSONB->>'configuration_text')::JSONB->'required_functions',(manifest::JSONB->>'configuration_text')::JSONB->'required_gates') FROM test_release$$,'55000','gemini_release_verification_failed','uncertainty cannot qualify activation');
-- Separate release identity; no resetting or reclaiming the ambiguous case.
TRUNCATE test_release;
INSERT INTO test_release SELECT '00000000-0000-4000-8000-000000000020',pg_temp.release_manifest('00000000-0000-4000-8000-000000000020',repeat('2',40));
SELECT internal.register_gemini_release((SELECT manifest FROM test_release));
CREATE TEMP TABLE original_holds AS SELECT internal.gemini_independent_holds() AS value;
DO $$
DECLARE case_id TEXT; claim JSONB; rid UUID:=(SELECT id FROM test_release); digest TEXT; receipt JSONB;
BEGIN
 SELECT configuration_digest INTO digest FROM internal.gemini_activation_releases WHERE id=rid;
 receipt:='{"returnedModel":"gemini-3.5-flash-lite","usage":{"promptTokens":10,"candidateTokens":2,"thinkingTokens":3,"cachedTokens":0,"toolTokens":0,"totalTokens":15,"modalityBreakdown":{"prompt":{},"cached":{},"candidates":{},"tool":{}}},"usageConsistent":true,"finishReason":"STOP","failure":null}';
 FOR case_id IN SELECT 'case_'||n FROM generate_series(1,8) n LOOP
  claim:=public.claim_gemini_release_smoke(rid,case_id,digest);
  PERFORM public.advance_gemini_release_smoke(rid,case_id,(claim->>'owner_token')::UUID,'dispatch');
  PERFORM public.advance_gemini_release_smoke(rid,case_id,(claim->>'owner_token')::UUID,'receipt',receipt);
  PERFORM public.advance_gemini_release_smoke(rid,case_id,(claim->>'owner_token')::UUID,'outcome',receipt,TRUE);
 END LOOP;
END $$;
SELECT extensions.ok((SELECT bool_and(state='passed' AND settlement='settled') FROM internal.gemini_release_smokes WHERE release_id=(SELECT id FROM test_release)),'complete reasoning receipts settle exact owned cases');
SELECT extensions.ok(internal.verify_gemini_release(id,(manifest::JSONB->>'configuration_text')::JSONB->'required_functions',(manifest::JSONB->>'configuration_text')::JSONB->'required_gates'),'records immutable technical evidence') FROM test_release;
CREATE FUNCTION pg_temp.activate(p_target TEXT DEFAULT 'synthetic_test') RETURNS BIGINT LANGUAGE SQL AS $$
 SELECT internal.activate_gemini_release(id,p_target,manifest::JSONB->>'backend_sha',manifest::JSONB->>'configuration_digest',(manifest::JSONB->>'configuration_text')::JSONB->'required_functions',(manifest::JSONB->>'configuration_text')::JSONB->'required_gates') FROM test_release;
$$;
SELECT extensions.throws_ok($$SELECT pg_temp.activate('wrong_target')$$,'55000','gemini_release_identity_mismatch','wrong target fails closed');
SAVEPOINT policy_drift;
UPDATE internal.ai_quota_policies SET policy_version=policy_version+1 WHERE operation='scan_overview_enrichment' AND effective_plan='free';
SELECT extensions.throws_ok($$SELECT pg_temp.activate()$$,'55000','gemini_assignment_manifest_changed','policy drift cannot change frozen activation scope');
ROLLBACK TO policy_drift;
SELECT extensions.is(pg_temp.activate(),1::BIGINT,'complete assignment activation is atomic');
SELECT extensions.is(pg_temp.activate(),1::BIGINT,'exact activation retry returns same revision');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.ai_quota_policies WHERE allowed AND model LIKE 'gemini-2.5-%'),'all current allowed Gemini operations use candidates');
SELECT extensions.is(internal.gemini_independent_holds(),(SELECT value FROM original_holds),'activation preserves independent holds');
SELECT extensions.ok(internal.suspend_gemini_release(id,1,manifest::JSONB->>'configuration_digest','{"reason":"synthetic verification failure"}'),'protective suspension is revision fenced') FROM test_release;
SELECT extensions.ok(NOT internal.gemini_dispatch_open('gemini-3.8-flash',1),'suspension closes uninvoked transport');
SELECT extensions.throws_ok($$SELECT pg_temp.activate()$$,'55000','gemini_release_superseded_or_suspended','suspended retry cannot report current success');
SELECT extensions.throws_ok($$SELECT internal.suspend_gemini_release(id,0,manifest::JSONB->>'configuration_digest','{}') FROM test_release$$,'55000','gemini_suspension_revision_mismatch','old release cannot suspend another revision');
SELECT extensions.is((SELECT count(*) FROM internal.gemini_release_smokes WHERE state='uncertain'),1::BIGINT,'suspension and activation retain uncertain liabilities');
SELECT * FROM extensions.finish();
ROLLBACK;

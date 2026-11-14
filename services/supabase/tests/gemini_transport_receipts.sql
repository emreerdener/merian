\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SET LOCAL request.jwt.claim.role='service_role';
CREATE TEMP TABLE fixture(owner UUID,reservation UUID,token UUID,receipt UUID);
INSERT INTO fixture VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),NULL);
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
 SELECT owner,'authenticated','authenticated',owner::TEXT||'@example.invalid','{}','{}' FROM fixture;
INSERT INTO public.users(id,email,public_username,public_author_name,public_identity_source)
 SELECT owner,owner::TEXT||'@example.invalid','gemini_'||left(replace(owner::TEXT,'-',''),16),'Synthetic transport','alias' FROM fixture ON CONFLICT(id) DO NOTHING;
INSERT INTO internal.ai_quota_reservations(id,user_id,operation,request_id,lease_token,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,state)
 SELECT reservation,owner,'scan_group_tag_enrichment',gen_random_uuid(),token,'gemini-2.5-flash','free','free','free',false,1,1,'committed' FROM fixture;
SELECT extensions.ok(internal.gemini_dispatch_open_at('gemini-2.5-flash',0,'2026-11-29 23:59:59.999+00'),'legacy assignment can drain before cutoff');
SELECT extensions.ok(NOT internal.gemini_dispatch_open_at('gemini-2.5-flash',0,'2026-11-30 00:00:00+00'),'legacy dispatch closes exactly at cutoff');
SELECT extensions.ok(NOT internal.gemini_dispatch_open_at('gemini-2.5-pro',0,'2026-12-01 00:00:00+00'),'saved legacy model never reroutes after December 1');
SAVEPOINT suspended;
UPDATE internal.gemini_routing_revisions SET status='suspended' WHERE revision=0;
SELECT extensions.throws_ok($$SELECT public.authorize_gemini_transport(reservation,owner,token,1) FROM fixture$$,'55000','gemini_dispatch_closed','worker with initial committed permit cannot transport after suspension');
SELECT extensions.is((SELECT count(*) FROM internal.gemini_invocation_receipts),0::BIGINT,'permit alone has not created a provider receipt');
SELECT extensions.ok(public.record_gemini_non_invocation(reservation,owner,token,1,NULL),'live owner can attest no invocation after final guard denial') FROM fixture;
SELECT extensions.is((SELECT settlement FROM internal.gemini_invocation_receipts),'not_invoked','positive owner proof settles liability');
ROLLBACK TO suspended;
UPDATE fixture SET receipt=public.authorize_gemini_transport(reservation,owner,token,1);
SELECT extensions.is((SELECT state FROM internal.gemini_invocation_receipts),'dispatch_intent','final transport permit preserves possible provider liability');
SELECT extensions.throws_ok($$SELECT public.authorize_gemini_transport(reservation,owner,token,1) FROM fixture$$,'55000','gemini_dispatch_already_owned','another worker cannot repeat dispatch');
SELECT extensions.throws_ok($$SELECT public.record_gemini_non_invocation(reservation,owner,token,1,NULL) FROM fixture$$,'55000','gemini_non_invocation_conflict','same lease without owning transport witness is not non-invocation proof');
SAVEPOINT expired;
UPDATE internal.ai_quota_reservations SET lease_expires_at=now()-interval '1 second' WHERE id=(SELECT reservation FROM fixture);
SELECT extensions.throws_ok($$SELECT public.record_gemini_non_invocation(reservation,owner,token,1,receipt) FROM fixture$$,'55000','gemini_non_invocation_not_owned','expired owner cannot cancel uncertain execution');
SELECT extensions.is((SELECT settlement FROM internal.gemini_invocation_receipts),'unresolved','expiry retains liability');
ROLLBACK TO expired;
CREATE TEMP TABLE response(value JSONB);
INSERT INTO response VALUES('{"returnedModel":"gemini-3.5-flash-lite","usage":{"promptTokens":10,"candidateTokens":2,"thinkingTokens":3,"cachedTokens":0,"toolTokens":0,"totalTokens":15,"modalityBreakdown":{"prompt":{},"cached":{},"candidates":{},"tool":{}}},"usageConsistent":true,"finishReason":"STOP","failure":"identity"}');
SELECT extensions.ok(public.record_gemini_invocation_receipt(receipt,token,(SELECT value FROM response)),'a legacy request with new returned identity retains usage despite rejection') FROM fixture;
SELECT extensions.is((SELECT requested_model FROM internal.gemini_invocation_receipts),'gemini-2.5-flash','requested identity is immutable');
SELECT extensions.is((SELECT returned_model FROM internal.gemini_invocation_receipts),'gemini-3.5-flash-lite','returned identity is a separate response fact');
SELECT extensions.ok((SELECT estimated_cost_microusd>0 FROM internal.gemini_invocation_receipts),'mismatched response still has accounting');
SELECT extensions.ok(public.record_gemini_invocation_receipt(receipt,token,(SELECT value FROM response)),'exact receipt replay is idempotent') FROM fixture;
SELECT extensions.throws_ok($$SELECT public.record_gemini_non_invocation(reservation,owner,token,1,receipt) FROM fixture$$,'55000','gemini_non_invocation_conflict','a received response can never be relabelled uninvoked');
SELECT extensions.ok((SELECT jan.cost=53 AND dec.cost=26 FROM internal.price_gemini_receipt((SELECT jsonb_set(value,'{returnedModel}','"gemini-3.8-flash"') FROM response),'2026-12-31 23:59:59.999+00') dec CROSS JOIN internal.price_gemini_receipt((SELECT jsonb_set(value,'{returnedModel}','"gemini-3.8-flash"') FROM response),'2027-01-01 00:00:00+00') jan),'effective-dated January pricing is used at dispatch time');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.is((SELECT count(*) FROM public.ai_usage_events WHERE source_type='gemini_invocation_receipt' AND source_id=(SELECT receipt FROM fixture)),1::BIGINT,'exact response retry writes one durable support ledger event');
SELECT extensions.ok((SELECT e.model='gemini-2.5-flash' AND e.metadata->>'ai_returned_model'='gemini-3.5-flash-lite'
 AND e.estimated_cost_microusd=r.estimated_cost_microusd AND e.outcome='error'
 FROM public.ai_usage_events e JOIN internal.gemini_invocation_receipts r ON r.id=e.source_id
 WHERE e.source_type='gemini_invocation_receipt' AND r.id=(SELECT receipt FROM fixture)),'support ledger preserves requested identity but prices recognized returned identity even after rejection');
SAVEPOINT retained;
UPDATE internal.ai_quota_reservations SET state='failed' WHERE id=(SELECT reservation FROM fixture);
UPDATE internal.ai_quota_policies SET model='gemini-3.5-flash-lite',policy_version=policy_version+1 WHERE operation='scan_group_tag_enrichment';
SELECT extensions.throws_ok($$SELECT * FROM internal.reserve_ai_quota_core((SELECT owner FROM fixture),'scan_group_tag_enrichment',(SELECT request_id FROM internal.ai_quota_reservations WHERE id=(SELECT reservation FROM fixture)),repeat('a',64))$$,'P0001','ai_quota_unavailable','failed legacy admission cannot acquire a new model under the same request identity');
SELECT extensions.is((SELECT model FROM internal.ai_quota_reservations WHERE id=(SELECT reservation FROM fixture)),'gemini-2.5-flash','rejected retry preserves the admitted requested model');
ROLLBACK TO retained;
DELETE FROM internal.ai_quota_reservations WHERE id=(SELECT reservation FROM fixture);
SELECT extensions.is((SELECT count(*) FROM internal.gemini_invocation_receipts WHERE id=(SELECT receipt FROM fixture)),1::BIGINT,'queue retention cannot erase response or liability evidence');
ROLLBACK TO retained;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid IN ('internal.gemini_invocation_receipts'::regclass,'internal.gemini_species_executions'::regclass) AND confdeltype='c'),'no queue cascade can erase uncertain receipts');
SELECT * FROM extensions.finish();
ROLLBACK;

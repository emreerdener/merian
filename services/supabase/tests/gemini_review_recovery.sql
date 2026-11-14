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

UPDATE fixture SET receipt=public.authorize_gemini_transport(reservation,owner,token,1);
CREATE TEMP TABLE response(value JSONB);
INSERT INTO response VALUES('{"returnedModel":"gemini-2.5-flash","usage":{"promptTokens":10,"candidateTokens":2,"thinkingTokens":3,"cachedTokens":0,"toolTokens":0,"totalTokens":15,"modalityBreakdown":{"prompt":{},"cached":{},"candidates":{},"tool":{}}},"usageConsistent":true,"finishReason":"STOP","failure":null}');
SELECT extensions.ok(public.record_gemini_invocation_receipt(receipt,token,(SELECT value FROM response)),'valid envelope is durable before application decoding') FROM fixture;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT extensions.is((SELECT outcome FROM public.ai_usage_events WHERE source_id=(SELECT receipt FROM fixture)),'unknown','provider response alone is not application success');
CREATE TEMP TABLE original_usage AS SELECT * FROM public.ai_usage_events WHERE source_id=(SELECT receipt FROM fixture);
SELECT extensions.throws_ok($$SELECT public.record_gemini_application_outcome(receipt,gen_random_uuid(),'error') FROM fixture$$,'55000','gemini_receipt_not_owned','another owner cannot decide the application outcome');
SAVEPOINT valid_application;
SELECT extensions.ok(public.record_gemini_application_outcome(receipt,token,'success'),'valid user group-tag application records durable acceptance') FROM fixture;
SELECT extensions.is((SELECT application_outcome FROM internal.gemini_invocation_receipts WHERE id=(SELECT receipt FROM fixture)),'success','user support success is separate durable evidence');
ROLLBACK TO valid_application;
SELECT extensions.ok(public.record_gemini_application_outcome(receipt,token,'error'),'strict application rejection is durably separate from provider receipt') FROM fixture;
SELECT extensions.ok(public.record_gemini_application_outcome(receipt,token,'error'),'exact outcome retry is idempotent') FROM fixture;
SELECT extensions.throws_ok($$SELECT public.record_gemini_application_outcome(receipt,token,'success') FROM fixture$$,'23505','gemini_application_outcome_conflict','rejected application cannot be relabelled successful');
SELECT extensions.ok((SELECT e.outcome='unknown' AND e.estimated_cost_microusd IS NOT DISTINCT FROM original.estimated_cost_microusd
 AND e.pricing_version IS NOT DISTINCT FROM original.pricing_version AND e.total_tokens=original.total_tokens
 FROM public.ai_usage_events e JOIN original_usage original USING(id)),'semantic rejection preserves the append-only provider ledger without repricing or losing tokens');
SELECT extensions.is((SELECT application_outcome FROM internal.gemini_invocation_receipts WHERE id=(SELECT receipt FROM fixture)),'error','application outcome is retained separately from the append-only provider ledger');
SELECT extensions.is((SELECT receipt FROM internal.gemini_invocation_receipts WHERE id=(SELECT receipt FROM fixture)),(SELECT value FROM response),'application rejection preserves immutable provider facts');
SELECT extensions.is((SELECT count(*) FROM public.ai_usage_events WHERE source_id=(SELECT receipt FROM fixture)),1::BIGINT,'outcome retries preserve one usage event');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.record_gemini_application_outcome(uuid,uuid,text)','EXECUTE') AND has_function_privilege('service_role','public.record_gemini_application_outcome(uuid,uuid,text)','EXECUTE'),'application outcome is service-only');

-- Synthetic species jobs isolate received-result and bootstrap uncertainty.
INSERT INTO public.species_dictionary(id,scientific_name,common_names)
 VALUES('00000000-0000-4000-8000-00000000fe01','Reviewfixture species','{"en":"Synthetic review species"}');
CREATE TEMP TABLE job_fixture AS SELECT id FROM public.species_enrichment_jobs
 WHERE species_id='00000000-0000-4000-8000-00000000fe01' AND content_group='habitat';
UPDATE public.species_enrichment_jobs SET status='running',attempts=1,locked_at=now() WHERE id=(SELECT id FROM job_fixture);
SELECT extensions.ok(NOT public.complete_gemini_species_job(id,1,true),'ready execution cannot claim successful provider completion') FROM job_fixture;
SELECT extensions.ok((SELECT status='running' FROM public.species_enrichment_jobs WHERE id=(SELECT id FROM job_fixture)) AND (SELECT completion_recorded_at IS NULL FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture)),'rejected ready success preserves ownership and completion evidence');
SAVEPOINT no_call;
SELECT public.advance_gemini_species_execution(job_id,attempt_count,owner_token,'not_invoked') FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture);
SELECT extensions.ok(NOT public.complete_gemini_species_job(id,1,true),'explicit non-invocation is not successful provider completion') FROM job_fixture;
SELECT extensions.ok(public.complete_gemini_species_job(id,1,false,'synthetic pre-dispatch failure'),'proven uninvoked failure can finish without paid replacement liability') FROM job_fixture;
ROLLBACK TO no_call;
SELECT extensions.ok(public.advance_gemini_species_execution(job_id,attempt_count,owner_token,'dispatch'),'species owner enters transport') FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture);
SELECT extensions.ok(public.advance_gemini_species_execution(job_id,attempt_count,owner_token,'receipt',(SELECT value FROM response)),'species response persists before downstream work') FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture);
SELECT extensions.ok(NOT public.complete_gemini_species_job(id,1,false,'synthetic persistence failure'),'post-response persistence failure cannot make generation retryable') FROM job_fixture;
SELECT extensions.is((SELECT status FROM public.species_enrichment_jobs WHERE id=(SELECT id FROM job_fixture)),'running','received work remains owned pending recovery');
SELECT extensions.is((SELECT outcome FROM public.ai_usage_events WHERE source_id=(SELECT owner_token FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture))),'unknown','received species response alone does not claim business success');
SAVEPOINT received;
-- Even a late older worker using the generic completion cannot enable replacement.
SELECT public.complete_species_enrichment_job(id,false,'synthetic older worker failure') FROM job_fixture;
UPDATE public.species_enrichment_jobs SET next_run_at=now()-interval '1 day' WHERE id=(SELECT id FROM job_fixture);
SELECT extensions.is((SELECT count(*) FROM public.claim_species_model_enrichment_jobs(50,now(),ARRAY['habitat'],true) WHERE job_id=(SELECT id FROM job_fixture)),0::BIGINT,'preview excludes unresolved received generation');
SELECT extensions.is((SELECT count(*) FROM public.claim_species_model_enrichment_jobs(50,now(),ARRAY['habitat'],false) WHERE job_id=(SELECT id FROM job_fixture)),0::BIGINT,'model claim excludes unresolved received generation');
SELECT extensions.is((SELECT count(*) FROM public.claim_species_enrichment_jobs(50,now(),'habitat') WHERE job_id=(SELECT id FROM job_fixture)),0::BIGINT,'older claim excludes unresolved received generation');
SELECT extensions.throws_ok($$UPDATE public.species_enrichment_jobs SET status='running',attempts=2 WHERE id=(SELECT id FROM job_fixture)$$,'55000','gemini_species_execution_uncertain','direct reclaim cannot replace received generation');
ROLLBACK TO received;
SELECT extensions.ok(public.complete_gemini_species_job(id,1,true),'persisted outcome can complete without another invocation') FROM job_fixture;
SELECT extensions.ok(public.complete_gemini_species_job(id,1,true),'successful completion retry is idempotent') FROM job_fixture;
SELECT extensions.is((SELECT outcome FROM public.ai_usage_events WHERE source_id=(SELECT owner_token FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture))),'unknown','business completion does not rewrite the append-only provider ledger');
UPDATE public.species_enrichment_jobs SET status='queued',next_run_at=now()-interval '1 day' WHERE id=(SELECT id FROM job_fixture);
SELECT extensions.is((SELECT attempts FROM public.claim_species_model_enrichment_jobs(50,now(),ARRAY['habitat'],false) WHERE job_id=(SELECT id FROM job_fixture)),2,'later scheduled refresh has a new attempt after known completion');
SELECT extensions.is((SELECT state FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture) AND attempt_count=2),'ready','later refresh owns new execution without rewriting old receipt');
-- The bootstrap representation has possible dispatch but no invented timestamp.
UPDATE internal.gemini_species_executions SET state='dispatch_intent',dispatch_intent_at=NULL WHERE job_id=(SELECT id FROM job_fixture) AND attempt_count=2;
SELECT extensions.throws_ok($$SELECT public.advance_gemini_species_execution(job_id,attempt_count,owner_token,'not_invoked') FROM internal.gemini_species_executions WHERE job_id=(SELECT id FROM job_fixture) AND attempt_count=2$$,'55000','gemini_species_transition_invalid','bootstrap uncertainty is not live non-invocation proof');
SELECT extensions.ok(NOT public.complete_gemini_species_job(id,2,false,'synthetic old failure'),'bootstrap uncertainty cannot become retryable') FROM job_fixture;
SELECT public.complete_species_enrichment_job(id,false,'synthetic older worker failure') FROM job_fixture;
UPDATE public.species_enrichment_jobs SET next_run_at=now()-interval '1 day' WHERE id=(SELECT id FROM job_fixture);
SELECT extensions.is((SELECT count(*) FROM public.claim_species_model_enrichment_jobs(50,now(),ARRAY['habitat'],false) WHERE job_id=(SELECT id FROM job_fixture)),0::BIGINT,'bootstrap uncertainty remains excluded even after older completion');
SELECT extensions.is((SELECT count(*) FROM public.claim_species_enrichment_jobs(50,now(),'habitat') WHERE job_id=(SELECT id FROM job_fixture)),0::BIGINT,'older claims cannot replace bootstrap uncertainty');
SELECT * FROM extensions.finish();
ROLLBACK;

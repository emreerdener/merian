-- Provider receipt facts and application acceptance are distinct durable facts.
SET lock_timeout='5s';
SET statement_timeout='5min';
ALTER TABLE internal.gemini_invocation_receipts ADD COLUMN application_outcome TEXT
 CHECK(application_outcome IN ('success','refusal','error'));
ALTER TABLE internal.gemini_species_executions ADD COLUMN completion_recorded_at TIMESTAMPTZ;
-- Compatibility may already be installed with older in-flight workers. There
-- is no retained proof distinguishing their ready rows from possible calls.
UPDATE internal.gemini_species_executions SET state='dispatch_intent'
 WHERE assignment_revision=0 AND requested_model='gemini-2.5-flash' AND state='ready';
UPDATE internal.gemini_species_executions AS execution SET completion_recorded_at=job.completed_at
 FROM public.species_enrichment_jobs AS job WHERE job.id=execution.job_id AND job.attempts=execution.attempt_count
 AND job.status='succeeded' AND execution.state='received' AND execution.receipt->'failure' IS NOT DISTINCT FROM 'null'::JSONB;

CREATE FUNCTION public.record_gemini_application_outcome(p_receipt_id UUID,p_lease_token UUID,p_outcome TEXT)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE saved internal.gemini_invocation_receipts;
BEGIN
 PERFORM internal.require_service_role();
 IF p_outcome IS NULL OR p_outcome NOT IN ('success','refusal','error') THEN
  RAISE EXCEPTION 'gemini_application_outcome_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO saved FROM internal.gemini_invocation_receipts WHERE id=p_receipt_id FOR UPDATE;
 IF NOT FOUND OR p_lease_token IS NULL OR saved.lease_token IS DISTINCT FROM p_lease_token OR saved.state<>'received' THEN
  RAISE EXCEPTION 'gemini_receipt_not_owned' USING ERRCODE='55000'; END IF;
 IF (saved.application_outcome IS NOT NULL AND saved.application_outcome IS DISTINCT FROM p_outcome)
  OR (p_outcome<>'error' AND saved.receipt->'failure' IS DISTINCT FROM 'null'::JSONB) THEN
  RAISE EXCEPTION 'gemini_application_outcome_conflict' USING ERRCODE='23505'; END IF;
 IF saved.application_outcome IS NULL THEN
  UPDATE internal.gemini_invocation_receipts SET application_outcome=p_outcome WHERE id=saved.id;
 END IF;
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.record_gemini_application_outcome(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_gemini_application_outcome(UUID,UUID,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.record_gemini_application_outcome(uuid,uuid,text)','Original response owner records one immutable application validation outcome without rewriting provider facts or pricing.');

-- A received response cannot be replaced after a later persistence failure.
-- Successful completion distinguishes subsequent scheduled refresh work.
DO $migration$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.register_gemini_release(text)'::regprocedure);
 anchor:='OR (m#>>''{app,availability_checked_at}'')::TIMESTAMPTZ>pg_catalog.clock_timestamp()';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_release_availability_source_drift'; END IF;
 EXECUTE replace(definition,anchor,'OR pg_catalog.jsonb_typeof(m#>''{app,availability_checked_at}'') IS DISTINCT FROM ''string'' '||anchor);
 definition:=pg_catalog.pg_get_functiondef('internal.bind_gemini_species_execution()'::regprocedure);
 anchor:='WHERE job_id=NEW.id AND state=''dispatch_intent''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_species_bind_source_drift'; END IF;
 EXECUTE replace(definition,anchor,'WHERE job_id=NEW.id AND state IN (''dispatch_intent'',''received'') AND completion_recorded_at IS NULL');
 definition:=pg_catalog.pg_get_functiondef('public.claim_species_model_enrichment_jobs(integer,timestamp with time zone,text[],boolean)'::regprocedure);
 anchor:='WHERE job.content_group = ANY(target_content_groups)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'gemini_species_claim_source_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||' AND NOT EXISTS(SELECT 1 FROM internal.gemini_species_executions e WHERE e.job_id=job.id AND e.state IN (''dispatch_intent'',''received'') AND e.completion_recorded_at IS NULL)');
 definition:=pg_catalog.pg_get_functiondef('public.claim_species_enrichment_jobs(integer,timestamp with time zone,text)'::regprocedure);
 anchor:='WHERE sej.status IN (''queued'', ''failed'')';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_species_legacy_claim_source_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||' AND NOT EXISTS(SELECT 1 FROM internal.gemini_species_executions e WHERE e.job_id=sej.id AND e.state IN (''dispatch_intent'',''received'') AND e.completion_recorded_at IS NULL)');
 definition:=pg_catalog.pg_get_functiondef('public.advance_gemini_species_execution(uuid,integer,uuid,text,jsonb)'::regprocedure);
 anchor:='ELSIF p_action=''not_invoked'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_species_non_invocation_source_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||' IF saved.state=''dispatch_intent'' AND saved.dispatch_intent_at IS NULL THEN RAISE EXCEPTION ''gemini_species_transition_invalid'' USING ERRCODE=''55000''; END IF;');
END;
$migration$;

CREATE OR REPLACE FUNCTION public.complete_gemini_species_job(target_job_id UUID,expected_attempt INTEGER,succeeded BOOLEAN,error_message TEXT DEFAULT NULL)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE execution internal.gemini_species_executions; job public.species_enrichment_jobs;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO job FROM public.species_enrichment_jobs WHERE id=target_job_id AND attempts=expected_attempt
  AND content_group IN ('habitat','lookalikes','group_tags') FOR UPDATE;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 SELECT * INTO execution FROM internal.gemini_species_executions WHERE job_id=target_job_id AND attempt_count=expected_attempt FOR UPDATE;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 IF execution.completion_recorded_at IS NOT NULL THEN RETURN succeeded IS TRUE AND job.status='succeeded'; END IF;
 IF succeeded IS NULL OR job.status<>'running' OR execution.state='dispatch_intent'
  OR (succeeded IS TRUE AND execution.state<>'received')
  OR (execution.state='received' AND (succeeded IS DISTINCT FROM TRUE OR execution.receipt->'failure' IS DISTINCT FROM 'null'::JSONB)) THEN RETURN FALSE; END IF;
 PERFORM public.complete_species_enrichment_job(target_job_id,succeeded,error_message);
 UPDATE internal.gemini_species_executions SET completion_recorded_at=pg_catalog.clock_timestamp()
 WHERE job_id=target_job_id AND attempt_count=expected_attempt;
 RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION internal.record_gemini_support_usage() RETURNS TRIGGER
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE receipt JSONB; operation_name TEXT; requested TEXT; plan TEXT:='unknown';
 source_kind TEXT; source UUID; happened TIMESTAMPTZ; cost BIGINT; price_version TEXT; settlement TEXT; application_outcome TEXT;
 execution internal.gemini_invocation_receipts; job internal.gemini_species_executions; smoke internal.gemini_release_smokes;
BEGIN
 IF TG_TABLE_NAME='gemini_invocation_receipts' THEN
  SELECT * INTO execution FROM internal.gemini_invocation_receipts WHERE id=NEW.id;
  IF execution.state<>'received' OR execution.receipt IS NULL OR execution.operation IN ('scan_identification','scan_audio_identification') THEN RETURN NULL; END IF;
  receipt:=execution.receipt;operation_name:=execution.operation;requested:=execution.requested_model;plan:=execution.effective_plan;
  source_kind:='gemini_invocation_receipt';source:=execution.id;happened:=execution.dispatch_intent_at;
  cost:=execution.estimated_cost_microusd;price_version:=execution.pricing_version;settlement:=execution.settlement;application_outcome:=execution.application_outcome;
 ELSIF TG_TABLE_NAME='gemini_species_executions' THEN
  SELECT * INTO job FROM internal.gemini_species_executions WHERE job_id=NEW.job_id AND attempt_count=NEW.attempt_count;
  IF job.state<>'received' OR job.receipt IS NULL THEN RETURN NULL; END IF;
  receipt:=job.receipt;operation_name:=job.operation;requested:=job.requested_model;
  source_kind:='gemini_species_receipt';source:=job.owner_token;happened:=job.dispatch_intent_at;
  cost:=job.estimated_cost_microusd;SELECT p.version INTO price_version FROM internal.price_gemini_receipt(receipt,happened) p;settlement:=job.settlement;application_outcome:=CASE WHEN job.completion_recorded_at IS NOT NULL THEN 'success' END;
 ELSE
  SELECT * INTO smoke FROM internal.gemini_release_smokes WHERE release_id=NEW.release_id AND case_id=NEW.case_id;
  IF smoke.state NOT IN ('passed','failed') OR smoke.receipt IS NULL THEN RETURN NULL; END IF;
  receipt:=smoke.receipt;operation_name:='gemini_release_smoke';requested:=smoke.requested_model;
  source_kind:='gemini_release_smoke';source:=smoke.owner_token;happened:=smoke.dispatch_intent_at;
  SELECT p.cost,p.version INTO cost,price_version FROM internal.price_gemini_receipt(receipt,happened) p;settlement:=smoke.settlement;application_outcome:=CASE WHEN smoke.state='passed' THEN 'success' ELSE 'error' END;
 END IF;
 INSERT INTO public.ai_usage_events(occurred_at,operation,model,effective_plan,input_modality,
 prompt_tokens,cached_tokens,candidate_tokens,thinking_tokens,tool_tokens,total_tokens,prompt_tokens_by_modality,
 outcome,source_type,source_id,estimated_cost_microusd,pricing_version,metadata)
 VALUES(happened,operation_name,requested,COALESCE(plan,'unknown'),'unknown',
 (receipt#>>'{usage,promptTokens}')::BIGINT,(receipt#>>'{usage,cachedTokens}')::BIGINT,
 (receipt#>>'{usage,candidateTokens}')::BIGINT,(receipt#>>'{usage,thinkingTokens}')::BIGINT,
 (receipt#>>'{usage,toolTokens}')::BIGINT,(receipt#>>'{usage,totalTokens}')::BIGINT,
 COALESCE(receipt#>'{usage,modalityBreakdown}','{}'::JSONB),
 CASE WHEN receipt->'failure'<>'null'::JSONB THEN 'error' ELSE COALESCE(application_outcome,'unknown') END,source_kind,source,cost,price_version,
 jsonb_build_object('ai_provider','gemini','ai_returned_model',receipt->'returnedModel','gemini_settlement',settlement,
 'accounting_contract','durable_gemini_receipt_v1','provider_response_only',application_outcome IS NULL,'application_outcome',application_outcome))
 ON CONFLICT(source_type,source_id,operation) DO NOTHING;
 RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.record_gemini_support_usage() FROM PUBLIC,anon,authenticated,service_role;

NOTIFY pgrst,'reload schema';
RESET lock_timeout;
RESET statement_timeout;

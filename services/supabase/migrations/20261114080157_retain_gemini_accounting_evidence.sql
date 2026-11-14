-- Durable content-free accounting is independent of queue/user retention.
SET lock_timeout='5s';
SET statement_timeout='5min';
ALTER TABLE internal.gemini_invocation_receipts DROP CONSTRAINT gemini_invocation_receipts_reservation_id_fkey;
ALTER TABLE internal.gemini_species_executions DROP CONSTRAINT gemini_species_executions_job_id_fkey;
ALTER TABLE internal.gemini_invocation_receipts ADD COLUMN operation TEXT, ADD COLUMN effective_plan TEXT;
ALTER TABLE internal.gemini_species_executions ADD COLUMN operation TEXT;
UPDATE internal.gemini_invocation_receipts e SET operation=q.operation,effective_plan=q.effective_plan
 FROM internal.ai_quota_reservations q WHERE q.id=e.reservation_id;
UPDATE internal.gemini_species_executions e SET operation=CASE j.content_group WHEN 'habitat' THEN 'scan_overview_enrichment'
 WHEN 'lookalikes' THEN 'scan_lookalike_enrichment' ELSE 'scan_group_tag_enrichment' END
 FROM public.species_enrichment_jobs j WHERE j.id=e.job_id;

CREATE FUNCTION internal.snapshot_gemini_accounting_scope() RETURNS TRIGGER
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_TABLE_NAME='gemini_invocation_receipts' THEN
  SELECT q.operation,q.effective_plan INTO NEW.operation,NEW.effective_plan FROM internal.ai_quota_reservations q WHERE q.id=NEW.reservation_id;
 ELSE
  SELECT CASE j.content_group WHEN 'habitat' THEN 'scan_overview_enrichment' WHEN 'lookalikes' THEN 'scan_lookalike_enrichment' ELSE 'scan_group_tag_enrichment' END
   INTO NEW.operation FROM public.species_enrichment_jobs j WHERE j.id=NEW.job_id;
 END IF;
 IF NEW.operation IS NULL THEN RAISE EXCEPTION 'gemini_accounting_scope_missing' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.snapshot_gemini_accounting_scope() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER snapshot_gemini_accounting_scope BEFORE INSERT ON internal.gemini_invocation_receipts
 FOR EACH ROW EXECUTE FUNCTION internal.snapshot_gemini_accounting_scope();
CREATE TRIGGER snapshot_gemini_accounting_scope BEFORE INSERT ON internal.gemini_species_executions
 FOR EACH ROW EXECUTE FUNCTION internal.snapshot_gemini_accounting_scope();

-- Deferred execution reads the final receipt + price from the same transaction.
-- Existing requested-model fields keep their historical meaning. Only the
-- verified returned identity can select a tariff; unresolved evidence is NULL.
CREATE FUNCTION internal.record_gemini_support_usage() RETURNS TRIGGER
 LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE receipt JSONB; operation_name TEXT; requested TEXT; plan TEXT:='unknown';
 source_kind TEXT; source UUID; happened TIMESTAMPTZ; cost BIGINT; price_version TEXT; settlement TEXT;
 execution internal.gemini_invocation_receipts; job internal.gemini_species_executions; smoke internal.gemini_release_smokes;
BEGIN
 IF TG_TABLE_NAME='gemini_invocation_receipts' THEN
  SELECT * INTO execution FROM internal.gemini_invocation_receipts WHERE id=NEW.id;
  IF execution.state<>'received' OR execution.receipt IS NULL OR execution.operation IN ('scan_identification','scan_audio_identification') THEN RETURN NULL; END IF;
  receipt:=execution.receipt;operation_name:=execution.operation;requested:=execution.requested_model;plan:=execution.effective_plan;
  source_kind:='gemini_invocation_receipt';source:=execution.id;happened:=execution.dispatch_intent_at;
  cost:=execution.estimated_cost_microusd;price_version:=execution.pricing_version;settlement:=execution.settlement;
 ELSIF TG_TABLE_NAME='gemini_species_executions' THEN
  SELECT * INTO job FROM internal.gemini_species_executions WHERE job_id=NEW.job_id AND attempt_count=NEW.attempt_count;
  IF job.state<>'received' OR job.receipt IS NULL THEN RETURN NULL; END IF;
  receipt:=job.receipt;operation_name:=job.operation;requested:=job.requested_model;
  source_kind:='gemini_species_receipt';source:=job.owner_token;happened:=job.dispatch_intent_at;
  cost:=job.estimated_cost_microusd;SELECT p.version INTO price_version FROM internal.price_gemini_receipt(receipt,happened) p;settlement:=job.settlement;
 ELSE
  SELECT * INTO smoke FROM internal.gemini_release_smokes WHERE release_id=NEW.release_id AND case_id=NEW.case_id;
  IF smoke.state NOT IN ('passed','failed') OR smoke.receipt IS NULL THEN RETURN NULL; END IF;
  receipt:=smoke.receipt;operation_name:='gemini_release_smoke';requested:=smoke.requested_model;
  source_kind:='gemini_release_smoke';source:=smoke.owner_token;happened:=smoke.dispatch_intent_at;
  SELECT p.cost,p.version INTO cost,price_version FROM internal.price_gemini_receipt(receipt,happened) p;settlement:=smoke.settlement;
 END IF;
 INSERT INTO public.ai_usage_events(occurred_at,operation,model,effective_plan,input_modality,
 prompt_tokens,cached_tokens,candidate_tokens,thinking_tokens,tool_tokens,total_tokens,prompt_tokens_by_modality,
 outcome,source_type,source_id,estimated_cost_microusd,pricing_version,metadata)
 VALUES(happened,operation_name,requested,COALESCE(plan,'unknown'),'unknown',
 (receipt#>>'{usage,promptTokens}')::BIGINT,(receipt#>>'{usage,cachedTokens}')::BIGINT,
 (receipt#>>'{usage,candidateTokens}')::BIGINT,(receipt#>>'{usage,thinkingTokens}')::BIGINT,
 (receipt#>>'{usage,toolTokens}')::BIGINT,(receipt#>>'{usage,totalTokens}')::BIGINT,
 COALESCE(receipt#>'{usage,modalityBreakdown}','{}'::JSONB),
 CASE WHEN receipt->'failure'='null'::JSONB THEN 'success' ELSE 'error' END,source_kind,source,cost,price_version,
 jsonb_build_object('ai_provider','gemini','ai_returned_model',receipt->'returnedModel','gemini_settlement',settlement,
 'accounting_contract','durable_gemini_receipt_v1','provider_response_only',TRUE))
 ON CONFLICT(source_type,source_id,operation) DO NOTHING;
 RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.record_gemini_support_usage() FROM PUBLIC,anon,authenticated,service_role;
CREATE CONSTRAINT TRIGGER record_gemini_support_usage AFTER INSERT OR UPDATE ON internal.gemini_invocation_receipts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.record_gemini_support_usage();
CREATE CONSTRAINT TRIGGER record_gemini_support_usage AFTER INSERT OR UPDATE ON internal.gemini_species_executions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.record_gemini_support_usage();
CREATE CONSTRAINT TRIGGER record_gemini_support_usage AFTER INSERT OR UPDATE ON internal.gemini_release_smokes
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.record_gemini_support_usage();
COMMENT ON TABLE internal.gemini_invocation_receipts IS 'Content-free immutable identity/accounting and unresolved liability retained independently of queue/user deletion. Opaque reservation IDs are historical links, not live ownership authority.';
COMMENT ON TABLE internal.gemini_species_executions IS 'Content-free attempt evidence outlives queue deletion. Missing queue ownership never authorizes dispatch, cancellation or reinvocation.';
NOTIFY pgrst,'reload schema';
RESET lock_timeout;
RESET statement_timeout;

-- Both ordinary and protected messages already bind the business request ID.
-- Its current reservation/attempt identifies durable accounting without adding
-- fields to immutable chat reply bytes or trusting a caller receipt pointer.
DO $migration$
DECLARE source TEXT; anchor TEXT;
BEGIN
 source:=pg_catalog.pg_get_functiondef('internal.trg_record_insight_chat_ai_usage()'::REGPROCEDURE);
 anchor:='  IF NEW.role <> ''assistant'' OR NEW.llm_total_tokens IS NULL THEN RETURN NEW; END IF;';
 IF (length(source)-length(replace(source,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_chat_usage_writer_drift'; END IF;
 EXECUTE replace(source,anchor,anchor||$new$
  IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations q
    JOIN internal.gemini_invocation_receipts r ON r.reservation_id=q.id AND r.attempt_count=q.attempt_count
    WHERE q.user_id=NEW.user_id AND q.operation='insight_chat_reply'
      AND q.request_id::TEXT=NEW.safety_metadata->>'request_id'
      AND r.requested_model=NEW.model AND r.state='received') THEN RETURN NEW; END IF;
  IF NEW.model='gemini-3.5-flash-lite' THEN RAISE EXCEPTION 'gemini_message_accounting_missing' USING ERRCODE='55000'; END IF;
$new$);
END;
$migration$;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- Original execution proof is shared by successful and known-terminal accounting.
-- Only successful drafts require result provenance; all require saved outcome
-- provenance and the immutable original dispatch identity.
CREATE OR REPLACE FUNCTION internal.video_analysis_accounting_invocation(i internal.observation_analysis_intents)
RETURNS internal.identification_invocations LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE q internal.ai_quota_reservations; v internal.identification_invocations;
BEGIN
 PERFORM internal.assert_video_analysis_dispatch_identity(i);
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(i.quota->>'reservation_id') FOR UPDATE;
 IF NOT FOUND OR q.user_id IS DISTINCT FROM i.owner_id OR q.original_analysis_id IS DISTINCT FROM i.analysis_id
 OR q.request_id IS DISTINCT FROM i.analysis_id OR q.operation IS DISTINCT FROM 'scan_identification'
 OR q.state IS DISTINCT FROM 'committed' OR q.committed_at IS NULL OR q.failed_at IS NOT NULL OR q.refund_count<>0
 OR q.attempt_count<>1 OR q.lease_token::TEXT IS DISTINCT FROM i.quota->>'lease_token' THEN RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
 SELECT * INTO v FROM internal.identification_invocations WHERE id=i.invocation_id FOR UPDATE;
 IF NOT FOUND OR v.reservation_id IS DISTINCT FROM q.id OR v.user_id IS DISTINCT FROM i.owner_id
 OR v.scan_id IS DISTINCT FROM i.analysis_id OR v.attempt_count<>1
 OR v.lease_sha256 IS DISTINCT FROM encode(extensions.digest(i.quota->>'lease_token','sha256'),'hex')
 OR v.provenance IS DISTINCT FROM i.provider_outcome->'provenance'
 OR (i.provider_outcome#>>'{outcome,kind}'='draft' AND v.provenance IS DISTINCT FROM i.draft#>'{result_snapshot,identification_provenance}')
 OR v.provider IS DISTINCT FROM i.quota->>'provider' OR v.model IS DISTINCT FROM i.quota->>'model'
 OR v.binding IS DISTINCT FROM i.quota->>'binding' OR v.input_profile IS DISTINCT FROM i.quota->>'input_profile'
 OR v.effective_plan IS DISTINCT FROM i.quota->>'effective_plan' OR v.policy_version::TEXT IS DISTINCT FROM i.quota->>'policy_version'
 OR v.input_profile IS DISTINCT FROM (CASE WHEN i.input_snapshot#>'{evidence_manifest,provenance,audio}'='null'::JSONB THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END)
 THEN RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
 RETURN v;
END;
$$;

CREATE TABLE internal.observation_video_terminal_receipts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_video_terminal_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_video_terminal_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.video_analysis_terminal_product(i internal.observation_analysis_intents)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('owner_id',i.owner_id,'observation_id',i.observation_id,'analysis_id',i.analysis_id,
 'source_analysis_id',i.input_snapshot->'source_analysis_id','invocation_id',i.invocation_id,
 'reason',CASE i.provider_outcome#>>'{outcome,kind}' WHEN 'refusal' THEN 'provider_refusal' ELSE 'invalid_result' END,
 'input_sha256',encode(extensions.digest(i.input_snapshot::TEXT,'sha256'),'hex'),
 'outcome_sha256',encode(extensions.digest(i.provider_outcome::TEXT,'sha256'),'hex'),
 'usage_sha256',encode(extensions.digest((i.provider_outcome->'usage')::TEXT,'sha256'),'hex'),
 'funding_sha256',encode(extensions.digest(i.quota::TEXT,'sha256'),'hex'))
 WHERE i.input_snapshot->'schema_version'='4'::JSONB AND i.draft IS NULL AND i.receipt IS NULL
 AND i.provider_outcome#>>'{outcome,kind}' IN ('refusal','invalid_output');
$$;

CREATE FUNCTION internal.video_analysis_terminal_accounting(i internal.observation_analysis_intents)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE v internal.identification_invocations; e public.ai_usage_events; expected JSONB; kind TEXT;
BEGIN
 IF internal.video_analysis_terminal_product(i) IS NULL THEN RETURN NULL; END IF;
 kind:=i.provider_outcome#>>'{outcome,kind}';
 v:=internal.video_analysis_accounting_invocation(i);
 SELECT * INTO e FROM public.ai_usage_events WHERE id=v.event_id FOR SHARE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 expected:=internal.observation_source_expected_usage(v,i.provider_outcome->'usage');
 expected:=jsonb_set(jsonb_set(expected,'{outcome}',to_jsonb(CASE kind WHEN 'refusal' THEN 'refusal' ELSE 'error' END)),
 '{metadata,ai_outcome}',to_jsonb(kind));
 IF (SELECT jsonb_object_agg(key,to_jsonb(e)->key) FROM jsonb_object_keys(expected) key) IS DISTINCT FROM expected
 OR e.conversation_id IS NOT NULL OR e.message_id IS NOT NULL OR e.is_backfilled THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('execution',jsonb_build_object('reservation_id',v.reservation_id,'invocation_id',v.id,'attempt_count',v.attempt_count,
 'lease_sha256',v.lease_sha256,'provider',v.provider,'model',v.model,'binding',v.binding,'input_profile',v.input_profile,
 'effective_plan',v.effective_plan,'policy_version',v.policy_version,'provenance',v.provenance),
 'accounting',jsonb_build_object('event_id',e.id,'facts',expected,'estimated_cost_microusd',e.estimated_cost_microusd,'pricing_version',e.pricing_version));
END;
$$;

-- Settlement proof is distinct from completion, retirement or source-release authority.
CREATE FUNCTION internal.video_analysis_terminal_candidate(i internal.observation_analysis_intents)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE product JSONB; accounting JSONB; credit internal.complimentary_scan_usage; q internal.ai_quota_reservations; settlement JSONB;
BEGIN
 product:=internal.video_analysis_terminal_product(i);
 IF product IS NULL OR i.state IS DISTINCT FROM 'failed_terminal' OR i.terminal_reason IS DISTINCT FROM product->>'reason'
 OR i.provider_usage IS DISTINCT FROM i.provider_outcome->'usage' OR i.work_token IS NOT NULL OR i.work_expires_at IS NOT NULL
 OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=i.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_video_accounting_receipts WHERE analysis_id=i.analysis_id) THEN RETURN NULL; END IF;
 accounting:=internal.video_analysis_terminal_accounting(i);
 IF accounting IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(i.quota->>'reservation_id');
 SELECT * INTO credit FROM internal.complimentary_scan_usage WHERE user_id=i.owner_id AND client_scan_id=i.analysis_id FOR UPDATE;
 IF i.quota->'complimentary_client_scan_id'='null'::JSONB THEN
  IF FOUND OR q.complimentary_client_scan_id IS NOT NULL THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state','not_allocated','reason',NULL,'settled_at',NULL,'credit_released',FALSE);
 ELSE
  IF NOT FOUND OR i.quota->>'complimentary_client_scan_id' IS DISTINCT FROM i.analysis_id::TEXT
   OR q.complimentary_client_scan_id IS DISTINCT FROM i.analysis_id OR credit.state IS DISTINCT FROM 'released'
   OR credit.settlement_reason IS DISTINCT FROM i.terminal_reason OR credit.settled_at IS NULL THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state',credit.state,'reason',credit.settlement_reason,'settled_at',credit.settled_at,'credit_released',TRUE);
 END IF;
 RETURN jsonb_build_object('schema_version',1,'product',product,'settlement',settlement)||accounting;
END;
$$;

CREATE FUNCTION internal.guard_video_analysis_terminal()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE i internal.observation_analysis_intents; expected JSONB;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
   AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN OLD;
 END IF;
 IF current_setting('merian.video_terminal',TRUE) IS DISTINCT FROM NEW.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO i FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND OR i.owner_id IS DISTINCT FROM NEW.owner_id OR i.observation_id IS DISTINCT FROM NEW.observation_id
 OR i.input_snapshot->>'source_analysis_id' IS DISTINCT FROM NEW.source_analysis_id::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 expected:=internal.video_analysis_terminal_candidate(i);
 IF expected IS NULL OR NEW.proof IS DISTINCT FROM expected THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER guard_video_analysis_terminal BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_video_terminal_receipts FOR EACH ROW EXECUTE FUNCTION internal.guard_video_analysis_terminal();

CREATE FUNCTION internal.settle_video_observation_terminal(p_owner UUID,p_observation UUID,p_analysis UUID,p_quota_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE i internal.observation_analysis_intents; receipt internal.observation_video_terminal_receipts;
 product JSONB; proof JSONB; settlement JSONB; prior_fence TEXT; credit internal.complimentary_scan_usage; q internal.ai_quota_reservations;
BEGIN
 i:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 PERFORM internal.assert_video_analysis_dispatch_identity(i);
 product:=internal.video_analysis_terminal_product(i);
 IF p_quota_token IS NULL OR p_quota_token::TEXT IS DISTINCT FROM i.quota->>'lease_token' OR product IS NULL THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO receipt FROM internal.observation_video_terminal_receipts WHERE analysis_id=p_analysis;
 IF FOUND THEN
  IF receipt.owner_id IS DISTINCT FROM p_owner OR receipt.observation_id IS DISTINCT FROM p_observation
   OR receipt.source_analysis_id::TEXT IS DISTINCT FROM i.input_snapshot->>'source_analysis_id'
   OR receipt.proof->'product' IS DISTINCT FROM product OR i.state IS DISTINCT FROM 'failed_terminal'
   OR i.terminal_reason IS DISTINCT FROM product->>'reason' OR i.provider_usage IS DISTINCT FROM i.provider_outcome->'usage'
   OR i.work_token IS NOT NULL OR i.work_expires_at IS NOT NULL THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN receipt.proof;
 END IF;
 IF i.state IS DISTINCT FROM 'dispatched' OR i.provider_usage IS NOT NULL OR i.terminal_reason IS NOT NULL
 OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
 OR EXISTS(SELECT 1 FROM internal.observation_video_accounting_receipts WHERE analysis_id=p_analysis) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.video_analysis_accounting_invocation(i);
 PERFORM internal.complete_identification_usage(i.invocation_id,i.provider_outcome#>>'{outcome,kind}',i.provider_outcome->'usage');
 IF internal.video_analysis_terminal_accounting(i) IS NULL THEN RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(i.quota->>'reservation_id');
 SELECT * INTO credit FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis FOR UPDATE;
 IF i.quota->'complimentary_client_scan_id'='null'::JSONB THEN
  IF FOUND OR q.complimentary_client_scan_id IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 ELSE
  IF NOT FOUND OR credit.state IS DISTINCT FROM 'held' OR credit.settled_at IS NOT NULL OR credit.settlement_reason IS NOT NULL
   OR i.quota->>'complimentary_client_scan_id' IS DISTINCT FROM p_analysis::TEXT OR q.complimentary_client_scan_id IS DISTINCT FROM p_analysis THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 END IF;
 settlement:=internal.settle_complimentary_analysis(p_owner,p_analysis,product->>'reason');
 IF settlement->'credit_consumed' IS DISTINCT FROM 'false'::JSONB
 OR settlement->'credit_released' IS DISTINCT FROM to_jsonb(i.quota->'complimentary_client_scan_id'<>'null'::JSONB) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 UPDATE internal.observation_analysis_intents SET state='failed_terminal',terminal_reason=product->>'reason',
 provider_usage=provider_outcome->'usage',work_token=NULL,work_expires_at=NULL WHERE analysis_id=p_analysis RETURNING * INTO i;
 proof:=internal.video_analysis_terminal_candidate(i);
 IF proof IS NULL THEN RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
 prior_fence:=current_setting('merian.video_terminal',TRUE);
 PERFORM set_config('merian.video_terminal',p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT,TRUE);
 INSERT INTO internal.observation_video_terminal_receipts VALUES(p_analysis,p_owner,p_observation,internal.source_child_uuid(i.input_snapshot->>'source_analysis_id'),proof);
 PERFORM set_config('merian.video_terminal',COALESCE(prior_fence,''),TRUE);
 RETURN proof;
END;
$$;
REVOKE ALL ON FUNCTION internal.video_analysis_terminal_product(internal.observation_analysis_intents),
 internal.video_analysis_terminal_accounting(internal.observation_analysis_intents),
 internal.video_analysis_terminal_candidate(internal.observation_analysis_intents),internal.guard_video_analysis_terminal(),
 internal.settle_video_observation_terminal(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
RESET statement_timeout;
RESET lock_timeout;

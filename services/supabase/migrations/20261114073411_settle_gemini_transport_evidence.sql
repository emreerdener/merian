SET lock_timeout='5s';
SET statement_timeout='5min';
CREATE FUNCTION internal.gemini_dispatch_open_at(p_model TEXT,p_revision BIGINT,p_at TIMESTAMPTZ)
 RETURNS BOOLEAN LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT p_model IN ('gemini-2.5-flash','gemini-2.5-pro','gemini-3.8-flash','gemini-3.5-flash-lite')
 AND (p_model NOT IN ('gemini-2.5-flash','gemini-2.5-pro') OR p_at<TIMESTAMPTZ '2026-11-30 00:00:00+00')
 AND EXISTS(SELECT 1 FROM internal.gemini_routing_revisions WHERE revision=p_revision AND status IN ('active','superseded'));
$$;
REVOKE ALL ON FUNCTION internal.gemini_dispatch_open_at(TEXT,BIGINT,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.gemini_dispatch_open(p_model TEXT,p_revision BIGINT)
 RETURNS BOOLEAN LANGUAGE SQL VOLATILE SET search_path='' AS $$
 SELECT internal.gemini_dispatch_open_at(p_model,p_revision,pg_catalog.clock_timestamp());
$$;

CREATE FUNCTION public.record_gemini_non_invocation(p_reservation_id UUID,p_user_id UUID,p_lease_token UUID,p_attempt_count INTEGER,p_receipt_id UUID DEFAULT NULL)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE quota internal.ai_quota_reservations; saved internal.gemini_invocation_receipts; assigned BIGINT;
BEGIN
    PERFORM internal.require_service_role();
 SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=p_reservation_id FOR UPDATE;
 IF NOT FOUND OR quota.user_id IS DISTINCT FROM p_user_id OR p_lease_token IS NULL OR quota.lease_token IS DISTINCT FROM p_lease_token
  OR quota.attempt_count IS DISTINCT FROM p_attempt_count OR quota.state<>'committed' OR quota.lease_expires_at<=pg_catalog.clock_timestamp() THEN
  RAISE EXCEPTION 'gemini_non_invocation_not_owned' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.gemini_invocation_receipts WHERE reservation_id=quota.id AND attempt_count=quota.attempt_count FOR UPDATE;
 IF FOUND THEN
  -- A lease/permit alone is not proof. Only the worker which received this
  -- unique transport witness can attest that it has not called the provider.
  IF p_receipt_id IS NULL OR saved.id IS DISTINCT FROM p_receipt_id OR saved.lease_token IS DISTINCT FROM p_lease_token
   OR saved.state NOT IN ('dispatch_intent','not_invoked') OR saved.receipt IS NOT NULL THEN
   RAISE EXCEPTION 'gemini_non_invocation_conflict' USING ERRCODE='55000'; END IF;
  UPDATE internal.gemini_invocation_receipts SET state='not_invoked',settlement='not_invoked',estimated_cost_microusd=0 WHERE id=saved.id;
 ELSE
  IF p_receipt_id IS NOT NULL THEN RAISE EXCEPTION 'gemini_non_invocation_conflict' USING ERRCODE='55000'; END IF;
  SELECT revision INTO assigned FROM internal.gemini_assignment_revisions WHERE operation=quota.operation AND effective_plan=quota.effective_plan AND policy_version=quota.policy_version AND requested_model=quota.model;
  IF assigned IS NULL AND quota.model IN ('gemini-2.5-flash','gemini-2.5-pro') THEN assigned:=0; END IF;
  IF internal.gemini_dispatch_open(quota.model,assigned) THEN RAISE EXCEPTION 'gemini_non_invocation_dispatch_open' USING ERRCODE='55000'; END IF;
  INSERT INTO internal.gemini_invocation_receipts(reservation_id,attempt_count,lease_token,assignment_revision,requested_model,state,settlement,estimated_cost_microusd)
   VALUES(quota.id,quota.attempt_count,p_lease_token,assigned,quota.model,'not_invoked','not_invoked',0);
 END IF;
 -- This settles provider liability only. Committed admission counters stay
 -- consumed; reserved feature holds use their existing owner cancellation RPC.
 -- Never bypass initial/history/protected-chat settlement ownership.
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.record_gemini_non_invocation(UUID,UUID,UUID,INTEGER,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_gemini_non_invocation(UUID,UUID,UUID,INTEGER,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.record_gemini_non_invocation(uuid,uuid,uuid,integer,uuid)','Live transport owner attests positive non-invocation; a missing response or expired lease cannot settle liability.');

-- Read-only reconciliation makes uncertainty visible without reclaim/refund.
CREATE VIEW internal.gemini_unresolved_liabilities WITH (security_invoker=TRUE) AS
 SELECT 'quota'::TEXT AS owner_kind,id::TEXT AS owner_id,requested_model,state,dispatch_intent_at,estimated_cost_microusd
 FROM internal.gemini_invocation_receipts WHERE settlement='unresolved'
 UNION ALL SELECT 'species_job',job_id::TEXT||':'||attempt_count::TEXT,requested_model,state,dispatch_intent_at,estimated_cost_microusd
 FROM internal.gemini_species_executions WHERE settlement='unresolved' AND state<>'ready'
 UNION ALL SELECT 'release_smoke',release_id::TEXT||':'||case_id,requested_model,state,dispatch_intent_at,NULL::BIGINT
 FROM internal.gemini_release_smokes WHERE settlement='unresolved';
REVOKE ALL ON internal.gemini_unresolved_liabilities FROM PUBLIC,anon,authenticated,service_role;

-- Newly written identification ledger rows price the returned identity receipt.
-- Historical ledger rows and already prepared accounting candidates are immutable.
DO $migration$
DECLARE source TEXT; anchor TEXT;
BEGIN
 source:=pg_catalog.pg_get_functiondef('internal.prepare_identification_usage_event(internal.identification_invocations,text,jsonb)'::REGPROCEDURE);
 anchor:='    RETURN ROW(gen_random_uuid(), invocation.occurred_at';
 IF strpos(source,anchor)=0 THEN RAISE EXCEPTION 'gemini_usage_writer_drift'; END IF;
 source:=replace(source,anchor,$new$    IF invocation.provider='gemini' AND (invocation.binding='gemini_generation3_v1' OR EXISTS(
      SELECT 1 FROM internal.gemini_invocation_receipts WHERE reservation_id=invocation.reservation_id AND attempt_count=invocation.attempt_count)) THEN
      cost:=NULL; price_version:=NULL;
      SELECT r.estimated_cost_microusd,r.pricing_version
        INTO cost,price_version FROM internal.gemini_invocation_receipts r
        WHERE r.reservation_id=invocation.reservation_id AND r.attempt_count=invocation.attempt_count;
      metadata:=metadata||COALESCE((SELECT jsonb_build_object('gemini_receipt_id',r.id,'ai_returned_model',r.returned_model,'gemini_settlement',r.settlement) FROM internal.gemini_invocation_receipts r WHERE r.reservation_id=invocation.reservation_id AND r.attempt_count=invocation.attempt_count),jsonb_build_object('gemini_settlement','unresolved'));
    END IF;
$new$ || anchor);
 EXECUTE source;
END;
$migration$;
CREATE FUNCTION internal.gemini_invocation_result_matches(p_invocation internal.identification_invocations,p_result JSONB)
 RETURNS BOOLEAN LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT CASE WHEN p_result->'version'='3'::JSONB THEN
  internal.initial_requested_provenance_matches(p_result,p_invocation.provenance)
  AND EXISTS(SELECT 1 FROM internal.gemini_invocation_receipts r
   WHERE r.reservation_id=p_invocation.reservation_id AND r.attempt_count=p_invocation.attempt_count
   AND r.state='received' AND r.requested_model=p_invocation.model AND r.requested_model=p_result->>'model'
   AND r.returned_model=p_result->>'returned_model' AND r.returned_model=r.requested_model
   AND r.receipt->>'returnedModel'=r.returned_model AND r.receipt->'failure'='null'::JSONB
   AND r.receipt->>'finishReason'='STOP')
 ELSE p_result=p_invocation.provenance END;
$$;
REVOKE ALL ON FUNCTION internal.gemini_invocation_result_matches(internal.identification_invocations,JSONB) FROM PUBLIC,anon,authenticated,service_role;
DO $migration$
DECLARE source TEXT; anchor TEXT;
BEGIN
 source:=pg_catalog.pg_get_functiondef('internal.record_observation_analysis_draft(uuid,uuid,uuid,uuid,jsonb,jsonb)'::REGPROCEDURE);
 anchor:=$old$SELECT 1 FROM internal.identification_invocations WHERE id=saved.invocation_id
            AND provenance=p_draft#>'{result_snapshot,identification_provenance}'$old$;
 IF strpos(source,anchor)=0 THEN RAISE EXCEPTION 'gemini_history_result_writer_drift'; END IF;
 EXECUTE replace(source,anchor,$new$SELECT 1 FROM internal.identification_invocations invocation WHERE id=saved.invocation_id
            AND internal.gemini_invocation_result_matches(invocation,p_draft#>'{result_snapshot,identification_provenance}')$new$);
 source:=pg_catalog.pg_get_functiondef('internal.assert_initial_result_origin(internal.initial_consuming_staging,boolean)'::REGPROCEDURE);
 anchor:=$old$internal.initial_requested_provenance_matches(internal.decode_initial_result_numbers_v1(provenance,internal.initial_result_schema_v2()->'provenance'),original.provenance)$old$;
 IF strpos(source,anchor)=0 THEN RAISE EXCEPTION 'gemini_retained_result_writer_drift'; END IF;
 EXECUTE replace(source,anchor,$new$internal.gemini_invocation_result_matches(original,internal.decode_initial_result_numbers_v1(provenance,internal.initial_result_schema_v2()->'provenance'))$new$);
 source:=pg_catalog.pg_get_functiondef('internal.guard_scan_identification_provenance()'::REGPROCEDURE);
 anchor:='    RETURN NEW;';
 IF (length(source)-length(replace(source,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'gemini_scan_result_writer_drift'; END IF;
 EXECUTE replace(source,anchor,$new$    IF TG_OP='INSERT' AND NEW.identification_provenance->'version'='3'::JSONB AND NOT EXISTS(
      SELECT 1 FROM internal.identification_invocations invocation WHERE invocation.scan_id=NEW.id AND invocation.user_id=NEW.user_id
       AND internal.gemini_invocation_result_matches(invocation,NEW.identification_provenance)) THEN
      RAISE EXCEPTION 'gemini_result_receipt_required' USING ERRCODE='22023'; END IF;
$new$ || anchor);
END;
$migration$;

NOTIFY pgrst,'reload schema';
RESET lock_timeout;
RESET statement_timeout;

-- Photo moderation uses its own attempt token and resolves quota server-side.
CREATE FUNCTION public.record_gemini_photo_non_invocation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID,p_receipt UUID)
 RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
 SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
 IF NOT FOUND OR attempt.state<>'dispatched' OR attempt.lease_token IS DISTINCT FROM p_token
  OR attempt.dispatch_expires_at<=pg_catalog.clock_timestamp() THEN RAISE EXCEPTION 'gemini_photo_not_owned' USING ERRCODE='55000'; END IF;
 RETURN public.record_gemini_non_invocation((attempt.quota->>'reservation_id')::UUID,p_owner,p_token,attempt.attempt_count,p_receipt);
END;
$$;
REVOKE ALL ON FUNCTION public.record_gemini_photo_non_invocation(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_gemini_photo_non_invocation(UUID,UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.record_gemini_photo_non_invocation(uuid,uuid,uuid,uuid,uuid)','Accept positive non-invocation evidence only from the live owning photo moderation attempt.');
NOTIFY pgrst,'reload schema';

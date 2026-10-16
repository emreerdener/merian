SET lock_timeout='5s';
SET statement_timeout='2min';

-- C1: no owner/content/funding survives in permanent lifecycle state. Existing
-- prepared admissions are deliberately NOT backfilled with pending authority.
CREATE TABLE internal.initial_analysis_lifecycle_fences(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
 state TEXT NOT NULL CHECK(state IN ('pending_pre_dispatch','dispatch_authorized',
  'cancelled_pre_dispatch','cancelled_dispatched','cancelled_unknown'))
);
CREATE TABLE internal.initial_analysis_cancellations(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_lifecycle_fences(scan_id),
 owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 dispatch TEXT NOT NULL CHECK(dispatch IN ('dispatch_prevented','dispatch_already_authorized','dispatch_outcome_unknown'))
);
CREATE INDEX initial_analysis_cancellations_owner ON internal.initial_analysis_cancellations(owner_id,scan_id);
ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_cancellations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_lifecycle_fences,internal.initial_analysis_cancellations FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO internal.ghost_profile_merge_reference_policies
 (source_schema,source_table,source_column,referenced_schema,referenced_table,referenced_column,strategy,execution_order,handler_key,purpose)
VALUES('internal','initial_analysis_cancellations','owner_id','public','users','id','preserve',901,NULL,
 'Hold identity transfer while owner-bound initial cancellation recovery exists; never reparent or silently erase it.');

CREATE FUNCTION internal.initial_cancellation_dispatch(p_state TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT CASE p_state WHEN 'cancelled_pre_dispatch' THEN 'dispatch_prevented'
 WHEN 'cancelled_dispatched' THEN 'dispatch_already_authorized'
 WHEN 'cancelled_unknown' THEN 'dispatch_outcome_unknown' END;
$$;
CREATE FUNCTION internal.guard_initial_lifecycle_fence() RETURNS TRIGGER
LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.state='cancelled_unknown' OR (NEW.state='pending_pre_dispatch' AND EXISTS(
   SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=NEW.scan_id)) THEN RETURN NEW; END IF;
 ELSIF TG_OP='UPDATE' THEN
  IF NEW.scan_id=OLD.scan_id AND
   ((OLD.state='pending_pre_dispatch' AND NEW.state IN ('cancelled_pre_dispatch','cancelled_unknown'))
    OR (OLD.state='dispatch_authorized' AND NEW.state='cancelled_dispatched')) THEN RETURN NEW; END IF;
 END IF;
 -- No callable or direct initial transition to dispatch_authorized exists.
 RAISE EXCEPTION 'initial_analysis_lifecycle_immutable' USING ERRCODE='22023';
END;
$$;
CREATE TRIGGER guard_initial_lifecycle_fence BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_lifecycle_fences
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_lifecycle_fence();
CREATE FUNCTION internal.record_initial_pending_state() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(NEW.scan_id,'pending_pre_dispatch');
 RETURN NEW;
END;
$$;
CREATE TRIGGER record_initial_pending_state AFTER INSERT ON internal.initial_analysis_admissions
 FOR EACH ROW EXECUTE FUNCTION internal.record_initial_pending_state();

CREATE FUNCTION internal.guard_initial_cancellation() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' THEN
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
   OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id) THEN RETURN OLD; END IF;
 ELSIF TG_OP='INSERT' THEN
  PERFORM id FROM public.users WHERE id=NEW.owner_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||NEW.scan_id::TEXT,0::BIGINT));
  IF NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.scan_id)
   AND NOT EXISTS(SELECT 1 FROM public.scans WHERE id=NEW.scan_id)
   AND EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences f WHERE f.scan_id=NEW.scan_id
    AND internal.initial_cancellation_dispatch(f.state)=NEW.dispatch) THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END;
$$;
CREATE TRIGGER guard_initial_cancellation BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_cancellations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cancellation();
REVOKE ALL ON FUNCTION internal.initial_cancellation_dispatch(TEXT),internal.guard_initial_lifecycle_fence(),
 internal.record_initial_pending_state(),internal.guard_initial_cancellation() FROM PUBLIC,anon,authenticated,service_role;

-- Cancellation is not scan deletion: allow its own terminal fence to erase the
-- private submission chain without ordinary tombstone/funded-history fanout.
DO $guard$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_initial_analysis_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF TG_OP=''DELETE'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial erasure guard changed'; END IF;
 definition:=replace(definition,anchor,anchor||$body$
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences f WHERE f.scan_id=OLD.scan_id
            AND internal.initial_cancellation_dispatch(f.state) IS NOT NULL) THEN RETURN OLD; END IF;
$body$);
 anchor:='    IF TG_TABLE_NAME=''initial_analysis_submissions'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial insert scope changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences f WHERE f.scan_id=NEW.scan_id
        AND internal.initial_cancellation_dispatch(f.state) IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_cancelled' USING ERRCODE='55000'; END IF;
$body$||anchor);
END;
$guard$;

CREATE FUNCTION internal.cancel_initial_analysis(p_owner UUID,p_scan UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE owned_by UUID; scan_exists BOOLEAN; saved internal.initial_analysis_cancellations;
 submission internal.initial_analysis_submissions; admission internal.initial_analysis_admissions;
 quota internal.ai_quota_reservations; funding JSONB; allocation internal.complimentary_scan_usage;
 lifecycle TEXT; terminal TEXT:='cancelled_unknown'; classification TEXT; proven BOOLEAN:=FALSE; settlement JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO owned_by FROM public.scans WHERE id=p_scan FOR UPDATE;
 scan_exists:=FOUND;
 IF scan_exists AND owned_by IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 SELECT state INTO lifecycle FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_already_complete' USING ERRCODE='55000'; END IF;
 IF saved.scan_id IS NOT NULL THEN
  IF saved.dispatch IS DISTINCT FROM internal.initial_cancellation_dispatch(lifecycle) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',saved.dispatch);
 END IF;
 IF internal.initial_cancellation_dispatch(lifecycle) IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF submission.scan_id IS NULL THEN
  -- First-writer-wins namespace claim, never proof of absent legacy execution.
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled)
   OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 ELSE
  SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
  SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admission.funding_binding_id AND user_id=p_owner FOR UPDATE;
  -- The owner is already locked. Do not take the usage row before the quota
  -- counter order; the existing settlement owner locks/rechecks it below.
  SELECT * INTO allocation FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan;
  funding:=jsonb_build_object('version',1,'original',jsonb_build_object(
   'reservation_id',quota.id,'request_id',quota.request_id,'original_analysis_id',quota.original_analysis_id,
   'operation',quota.operation,'attempt_count',quota.attempt_count,'effective_plan',quota.effective_plan,
   'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,'policy_version',quota.policy_version,
   'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
  proven:=lifecycle='pending_pre_dispatch' AND admission.owner_id=p_owner AND quota.user_id=p_owner
   AND quota.request_id=p_scan AND quota.original_analysis_id=p_scan AND quota.operation='scan_identification'
   AND quota.attempt_count=1 AND quota.state='reserved' AND quota.committed_at IS NULL AND quota.failed_at IS NULL
   AND quota.refunded_at IS NULL AND quota.refund_count=0 AND quota.stale_recovery_count=0
   AND submission.funding_snapshot=funding
   AND admission.funding_digest=internal.initial_digest('funding',internal.initial_canonical(funding))
   AND ((quota.complimentary_client_scan_id IS NULL AND allocation.client_scan_id IS NULL)
    OR (quota.complimentary_client_scan_id=p_scan AND allocation.state='held'))
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=quota.id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan);
  IF proven IS TRUE THEN
   IF NOT internal.finalize_ai_quota_reservation_core(quota.id,p_owner,quota.lease_token,'refunded') THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   settlement:=internal.settle_complimentary_analysis(p_owner,p_scan,'cancelled_before_dispatch');
   IF (settlement->>'credit_released')::BOOLEAN IS DISTINCT FROM (quota.complimentary_client_scan_id IS NOT NULL) THEN
    RAISE EXCEPTION 'initial_analysis_settlement_unavailable' USING ERRCODE='55000'; END IF;
   terminal:='cancelled_pre_dispatch';
  ELSIF lifecycle='dispatch_authorized' THEN terminal:='cancelled_dispatched';
  END IF;
 END IF;
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan) ON CONFLICT(scan_id) DO NOTHING;
 IF lifecycle IS NULL THEN
  INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(p_scan,terminal);
 ELSE
  UPDATE internal.initial_analysis_lifecycle_fences SET state=terminal WHERE scan_id=p_scan;
 END IF;
 classification:=internal.initial_cancellation_dispatch(terminal);
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 INSERT INTO internal.initial_analysis_cancellations(scan_id,owner_id,dispatch) VALUES(p_scan,p_owner,classification);
 RETURN jsonb_build_object('version',1,'outcome','cancelled','dispatch',classification);
END;
$$;
REVOKE ALL ON FUNCTION internal.cancel_initial_analysis(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.cancel_initial_analysis(p_owner UUID,p_scan UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.cancel_initial_analysis(p_owner,p_scan);
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_initial_analysis(UUID,UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_initial_analysis(UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.cancel_initial_analysis(uuid,uuid)','Inactive C1 exact owner-bound cancellation; never invocation authority');

-- Stronger deletion erases recovery receipts too. No accounting helper here.
CREATE FUNCTION internal.fence_initial_analysis_erasure(p_scan UUID) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan) THEN
  INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan) ON CONFLICT(scan_id) DO NOTHING;
  INSERT INTO internal.initial_analysis_lifecycle_fences(scan_id,state) VALUES(p_scan,'cancelled_unknown')
   ON CONFLICT(scan_id) DO UPDATE SET state=CASE
    WHEN initial_analysis_lifecycle_fences.state='dispatch_authorized' THEN 'cancelled_dispatched' ELSE 'cancelled_unknown' END
   WHERE initial_analysis_lifecycle_fences.state IN ('pending_pre_dispatch','dispatch_authorized');
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_initial_analysis_erasure(UUID) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.erase_initial_analysis_for_scan_fence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM internal.fence_initial_analysis_erasure(NEW.scan_id);
 DELETE FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;
 DELETE FROM internal.initial_analysis_cancellations WHERE scan_id=NEW.scan_id;
 RETURN NEW;
END;
$$;
DO $erasure$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_initial_analysis_tombstone_scope()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    SELECT owner_id INTO owned_by FROM internal.initial_analysis_submissions WHERE scan_id=NEW.scan_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial tombstone scope changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n    IF owned_by IS NULL THEN SELECT owner_id INTO owned_by FROM internal.initial_analysis_cancellations WHERE scan_id=NEW.scan_id; END IF;');
 -- Supported account owner cancels only pre-row operations, while the user can
 -- still be updated. Existing saved-scan detachment and raw DELETE guards stay.
 SELECT pg_catalog.pg_get_functiondef('public.apply_user_tombstone(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    FOR observation IN SELECT id FROM public.scans WHERE user_id=target_user_id ORDER BY id LOOP';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed account detachment loop changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    FOR observation IN SELECT s.scan_id FROM internal.initial_analysis_submissions s
        WHERE s.owner_id=target_user_id
            AND NOT EXISTS(SELECT 1 FROM public.scans WHERE id=s.scan_id)
            AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=s.scan_id)
        ORDER BY s.scan_id LOOP
        PERFORM internal.cancel_initial_analysis(target_user_id,observation);
    END LOOP;
$body$||anchor);
END;
$erasure$;

-- Close generic prepared-operation ingress and settlement under their existing
-- serialization. Do not insert ordinary deletion tombstones or add late locks.
DO $namespace$
DECLARE definition TEXT; anchor TEXT; replacement TEXT; signature TEXT; identity_name TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_source_child_ingestion()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=child) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed raw ingestion guard changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=child
        AND internal.initial_cancellation_dispatch(state) IS NOT NULL) THEN
        RAISE EXCEPTION 'initial_analysis_cancelled' USING ERRCODE='55000';
    END IF;
$body$||anchor);
 -- UUID spelling is not identity. Match the same normalized namespace used by
 -- raw ingestion guards without rewriting any legacy identifiers.
 SELECT pg_catalog.pg_get_functiondef('public.admit_initial_analysis(uuid,uuid,text,text,text,text)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='WHERE scan_id=p_scan::TEXT';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'Reviewed initial admission namespace changed'; END IF;
 EXECUTE replace(definition,anchor,'WHERE internal.source_child_uuid(scan_id)=p_scan');
 FOR signature,identity_name IN SELECT * FROM (VALUES
  ('public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)','scan_id_uuid'),
  ('public.complete_scan_ingestion_with_entitlement(uuid,uuid,jsonb,jsonb,text[])','p_scan_id'),
  ('public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)','p_scan_id'),
  ('public.claim_scan_ingestion_job(text,uuid,text,jsonb,jsonb,uuid[],text,integer)','scan_id_uuid'),
  ('public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])','p_scan_id'),
  ('public.recover_missing_owned_scan(uuid,uuid,jsonb)','p_scan_id'),
  ('public.recover_stranded_scan_ingestion_attempt(uuid,uuid)','p_scan_id'),
  ('public.recover_inline_scan_ingestion_completion(uuid,uuid)','p_scan_id')
 ) routines(signature,identity_name) LOOP
  SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
  IF signature LIKE 'public.begin_scan_ingestion(%' OR signature LIKE 'public.complete_scan_ingestion_with_entitlement(%'
   OR signature LIKE 'public.fail_scan_ingestion_terminal(%' THEN
   anchor:=format('    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=%s)',identity_name);
  ELSE
   anchor:=E'    IF EXISTS (\n        SELECT 1\n        FROM internal.scan_deletion_tombstones AS tombstones\n        WHERE tombstones.scan_id = '||identity_name;
  END IF;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'Reviewed legacy initial boundary changed: %',signature; END IF;
  replacement:=format($body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=%s) THEN
        RAISE EXCEPTION 'initial_analysis_execution_required' USING ERRCODE='55000';
    END IF;
$body$,identity_name);
  EXECUTE replace(definition,anchor,replacement||anchor);
 END LOOP;
 -- Both the ordinary and over-budget batch paths exclude the permanent
 -- identity, not mutable lifecycle state. Admission/cancel cannot claim an
 -- existing generic job/intent; a prepared identity therefore predates any
 -- contradictory visible job and is never removed by cancellation/erasure.
 SELECT pg_catalog.pg_get_functiondef('public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='        WHERE jobs.endpoint = ''identify-multimodal''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN RAISE EXCEPTION 'Reviewed batch replay candidates changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
          AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences initial_fence
              WHERE initial_fence.scan_id=internal.source_child_uuid(jobs.scan_id))
$body$);
 -- This older intent owner has no advisory before its INSERT. Reuse its early
 -- owner lock and add the same normalized UUID advisory before any intent row.
 SELECT pg_catalog.pg_get_functiondef('public.record_scan_ingestion_intent(text,uuid,text,jsonb,jsonb,jsonb,uuid[],text,text,boolean,boolean,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    INSERT INTO public.scan_ingestion_intents (';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed legacy intent boundary changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF internal.source_child_uuid(p_scan_id) IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
            'merian-scan-ingestion:'||internal.source_child_uuid(p_scan_id)::TEXT,0::BIGINT));
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences
            WHERE scan_id=internal.source_child_uuid(p_scan_id)) THEN
            RAISE EXCEPTION 'initial_analysis_execution_required' USING ERRCODE='55000';
        END IF;
    END IF;
$body$||anchor);
END;
$namespace$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- Bound accounting is held until exact source retirement/dispatch is prepared.
-- Ordinary cleanup must continue processing unrelated reservations.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    PERFORM internal.require_service_role();';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed quota finalizer entry changed'; END IF;
    EXECUTE replace(definition,anchor,anchor || $body$
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations q
        JOIN internal.observation_analysis_source_bindings b ON b.analysis_id=q.original_analysis_id
        WHERE q.id=p_reservation_id) THEN
        RAISE EXCEPTION 'analysis_history_retirement_required' USING ERRCODE='55000';
    END IF;
$body$);

    SELECT pg_catalog.pg_get_functiondef('internal.refund_expired_ai_quota_reservations(integer)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='          AND reservations.lease_expires_at <= quota_now';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed expiry cleanup changed'; END IF;
    EXECUTE replace(definition,anchor,anchor || $body$
          AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
              WHERE b.analysis_id=reservations.original_analysis_id)
$body$);
    SELECT pg_catalog.pg_get_functiondef('internal.prune_ai_quota_state()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        WHERE candidates.state IN (''committed'', ''failed'', ''refunded'')';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed quota pruning changed'; END IF;
    EXECUTE replace(definition,anchor,anchor || $body$
          AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
              WHERE b.analysis_id=candidates.original_analysis_id)
$body$);

    SELECT pg_catalog.pg_get_functiondef('internal.fail_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF p_reason IS NULL OR NOT ((saved.state=''admitted'' AND p_reason IN (''cancelled_before_dispatch'',''admission_expired''))';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed failure replay boundary changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_retirement_required' USING ERRCODE='55000';
    END IF;
$body$ || anchor);

    -- Exact existing retirement receipt recovery remains before this fresh hold.
    SELECT pg_catalog.pg_get_functiondef('public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF NOT COALESCE((SELECT execution_retirement_api_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement replay changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=analysis) THEN
        RAISE EXCEPTION 'analysis_history_retirement_required' USING ERRCODE='55000';
    END IF;
$body$ || anchor);

    -- Parent deletion is separately proven and must not be broken by holding
    -- generic finalization. Never use this path for a live-parent intent prune.
    SELECT pg_catalog.pg_get_functiondef('internal.erase_observation_analysis_intent()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='            PERFORM internal.finalize_observation_provider_reservation(OLD.owner_id,OLD.analysis_id,(OLD.quota->>''reservation_id'')::UUID,(OLD.quota->>''lease_token'')::UUID,''refunded'');';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed intent erasure changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
            -- Source bindings may already be erased by an earlier tombstone
            -- trigger. Apply the same unused-work proof to every intent here.
            IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
                AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
                RAISE EXCEPTION 'analysis_history_retirement_required' USING ERRCODE='55000';
            END IF;
            IF OLD.invocation_id IS NULL AND OLD.provider_outcome IS NULL AND OLD.draft IS NULL AND OLD.receipt IS NULL
                AND OLD.terminal_reason IS NULL AND OLD.provider_usage IS NULL
                AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=OLD.analysis_id)
                AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=OLD.analysis_id)
                AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=OLD.analysis_id)
                AND EXISTS(SELECT 1 FROM internal.ai_quota_reservations q
                    WHERE q.id=(OLD.quota->>'reservation_id')::UUID AND q.user_id=OLD.owner_id
                        AND q.original_analysis_id=OLD.analysis_id AND q.request_id=OLD.analysis_id
                        AND q.operation='scan_identification' AND q.state='reserved'
                        AND q.lease_token::TEXT=OLD.quota->>'lease_token'
                        AND to_jsonb(q.attempt_count)=OLD.quota->'attempt_count') THEN
                DECLARE old_context TEXT:=current_setting('merian.observation_analysis_provider',TRUE);
                BEGIN
                    PERFORM set_config('merian.observation_analysis_provider',OLD.owner_id::TEXT||':'||OLD.analysis_id::TEXT,TRUE);
                    PERFORM internal.finalize_ai_quota_reservation_core((OLD.quota->>'reservation_id')::UUID,OLD.owner_id,(OLD.quota->>'lease_token')::UUID,'refunded');
                    PERFORM set_config('merian.observation_analysis_provider',COALESCE(old_context,''),TRUE);
                END;
            END IF;
$body$);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

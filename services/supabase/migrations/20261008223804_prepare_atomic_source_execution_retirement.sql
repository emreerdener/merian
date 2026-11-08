SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN source_retirement_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Binding/witness retention is unchanged. Only terminal occupancy can leave a
-- live parent, and only after the entire retirement proof exists atomically.
DO $guard$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF TG_OP=''DELETE'' THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed source storage deletion changed'; END IF;
    EXECUTE replace(definition,anchor,anchor || $body$
        IF TG_TABLE_SCHEMA='internal' AND TG_TABLE_NAME='observation_analysis_source_occupancy'
            AND EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
                JOIN internal.observation_analysis_intents i ON i.analysis_id=b.analysis_id
                JOIN internal.observation_analysis_retirement_receipts r ON r.analysis_id=i.analysis_id
                JOIN internal.ai_quota_reservations q ON q.id=(i.quota->>'reservation_id')::UUID
                WHERE b.analysis_id=OLD.analysis_id AND b.owner_id=OLD.owner_id
                    AND b.observation_id=OLD.observation_id AND b.source_analysis_id=OLD.source_analysis_id
                    AND i.owner_id=b.owner_id AND i.observation_id=b.observation_id AND i.input_snapshot=b.input_snapshot
                    AND b.fingerprint_version=1 AND b.fingerprint=internal.observation_source_fingerprint(i.input_snapshot)
                    AND i.state='failed_terminal' AND i.terminal_reason='retired_before_dispatch'
                    AND i.provider_usage='{}'::JSONB AND i.invocation_id IS NULL AND i.provider_outcome IS NULL
                    AND i.draft IS NULL AND i.receipt IS NULL AND i.work_token IS NULL AND i.work_expires_at IS NULL
                    AND r.owner_id=b.owner_id AND r.observation_id=b.observation_id
                    AND r.request_identity=jsonb_build_object('schema_version',1,'operation_id',r.operation_id,
                        'observation_id',b.observation_id,'analysis_id',b.analysis_id,'source_analysis_id',b.source_analysis_id,
                        'request_digest',i.input_snapshot->>'request_digest')
                    AND r.receipt=r.request_identity || '{"state":"retired_before_dispatch"}'::JSONB
                    AND q.user_id=b.owner_id AND q.original_analysis_id=b.analysis_id AND q.request_id=b.analysis_id
                    AND q.operation='scan_identification' AND q.state='refunded' AND q.refund_count=1
                    AND q.committed_at IS NULL AND q.failed_at IS NULL
                    AND q.lease_token::TEXT=i.quota->>'lease_token' AND to_jsonb(q.attempt_count)=i.quota->'attempt_count'
                    AND i.quota->>'original_analysis_id'=b.analysis_id::TEXT AND i.quota->>'reservation_state'='reserved'
                    AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=b.analysis_id)
                    AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=b.analysis_id OR reservation_id=q.id)
                    AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=b.analysis_id)) THEN
            RETURN OLD;
        END IF;
$body$);
END;
$guard$;

DO $retire$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    observation UUID; analysis UUID; source UUID; operation UUID; field TEXT;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement declarations changed'; END IF;
    definition:=replace(definition,anchor,anchor || E'\n    binding internal.observation_analysis_source_bindings; old_context TEXT;');
    anchor:='    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement ownership entry changed'; END IF;
    definition:=replace(definition,anchor,$body$
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
$body$ || anchor);
    anchor:='    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=analysis) THEN
        RAISE EXCEPTION ''analysis_history_retirement_required'' USING ERRCODE=''55000'';
    END IF;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed source retirement hold changed'; END IF;
    definition:=replace(definition,anchor,$body$
    -- Exact receipt replay above needs neither occupancy nor a retained quota.
    binding:=internal.lock_observation_evidence_source(p_owner,observation,analysis);
    IF binding.analysis_id IS NOT NULL AND (SELECT source_retirement_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_retirement_required' USING ERRCODE='55000';
    END IF;
$body$);
    anchor:='    IF saved.input_snapshot->>''observation_id'' IS DISTINCT FROM observation::TEXT';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement identity proof changed'; END IF;
    definition:=replace(definition,anchor,$body$
    IF binding.analysis_id IS NOT NULL AND (binding.input_snapshot IS DISTINCT FROM saved.input_snapshot
        OR binding.source_analysis_id IS DISTINCT FROM source) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$body$ || anchor);
    anchor:='    PERFORM internal.finalize_observation_provider_reservation(p_owner,analysis,reservation.id,reservation.lease_token,''refunded'');';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement refund changed'; END IF;
    definition:=replace(definition,anchor,$body$
    IF binding.analysis_id IS NOT NULL THEN
        old_context:=current_setting('merian.observation_analysis_provider',TRUE);
        PERFORM set_config('merian.observation_analysis_provider',p_owner::TEXT||':'||analysis::TEXT,TRUE);
        PERFORM internal.finalize_ai_quota_reservation_core(reservation.id,p_owner,reservation.lease_token,'refunded');
        PERFORM set_config('merian.observation_analysis_provider',COALESCE(old_context,''),TRUE);
    ELSE
        PERFORM internal.finalize_observation_provider_reservation(p_owner,analysis,reservation.id,reservation.lease_token,'refunded');
    END IF;
$body$);
    anchor:='    RETURN answer;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed retirement completion changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF binding.analysis_id IS NOT NULL THEN
        DELETE FROM internal.observation_analysis_source_occupancy
        WHERE owner_id=p_owner AND observation_id=observation AND source_analysis_id=source AND analysis_id=analysis;
        IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    END IF;
$body$ || anchor);
END;
$retire$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private lock/validation primitives only; neither function grants admission.
CREATE FUNCTION internal.lock_owned_observation_source(p_owner UUID,p_observation UUID,p_source UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    IF p_source IS NULL OR p_source=p_observation THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-analysis-source:' || p_observation::TEXT || ':' || p_source::TEXT,0::BIGINT));
    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND analysis_id=p_source) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_owned_observation_source(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.lock_owned_observation_source_binding(
    p_owner UUID,p_observation UUID,p_analysis UUID,p_expected_input JSONB
) RETURNS internal.observation_analysis_source_bindings
LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; source UUID; fingerprint TEXT;
BEGIN
    -- Authorization/deletion precedes payload inspection. Never infer the source
    -- from a mutable selected result or an unrelated child binding.
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    fingerprint:=internal.observation_source_fingerprint(p_expected_input);
    source:=(p_expected_input->>'source_analysis_id')::UUID;
    IF p_analysis IS NULL OR p_analysis IN (p_observation,source)
        OR p_expected_input->>'observation_id' IS DISTINCT FROM p_observation::TEXT
        OR p_expected_input->>'analysis_id' IS DISTINCT FROM p_analysis::TEXT THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_source(p_owner,p_observation,source);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || p_analysis::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-history-evidence:' || p_analysis::TEXT,0::BIGINT));
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
    IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner
        OR binding.observation_id IS DISTINCT FROM p_observation
        OR binding.source_analysis_id IS DISTINCT FROM source
        OR binding.input_snapshot IS DISTINCT FROM p_expected_input
        OR binding.fingerprint_version IS DISTINCT FROM 1
        OR binding.fingerprint IS DISTINCT FROM fingerprint
        OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy
            WHERE owner_id=p_owner AND observation_id=p_observation
                AND source_analysis_id=source AND analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN binding;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_owned_observation_source_binding(UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.guard_observation_source_storage()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' THEN
        IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
            AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP='UPDATE' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_source(NEW.owner_id,NEW.observation_id,NEW.source_analysis_id);
    -- An inserted binding cannot use the exact-binding helper yet. Keep both
    -- child locks before the following validation trigger's namespace reads.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || NEW.analysis_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_source_storage() FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.lock_owned_observation_source_binding(UUID,UUID,UUID,JSONB) IS
    'Private live-binding validation only. Exact terminal replay precedes this helper; no reservation, funding, release or dispatch authority. Call before child locks.';
RESET statement_timeout;
RESET lock_timeout;

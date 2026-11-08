SET lock_timeout='5s';
SET statement_timeout='2min';

-- No funding exception: this durable-chain check is a storage backstop only.
-- Caller owns the canonical locks. Do not acquire a late source lock here.
CREATE FUNCTION internal.assert_observation_source_input_chain(p_owner UUID,p_observation UUID,p_analysis UUID,p_input JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; cohort internal.observation_evidence_upload_cohorts;
    audio internal.observation_audio_evidence_upload_cohorts; expected JSONB;
BEGIN
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
    IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner
        OR binding.observation_id IS DISTINCT FROM p_observation
        OR binding.input_snapshot IS DISTINCT FROM p_input
        OR binding.fingerprint_version IS DISTINCT FROM 1
        OR binding.fingerprint IS DISTINCT FROM internal.observation_source_fingerprint(p_input)
        OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy
            WHERE owner_id=p_owner AND observation_id=p_observation
                AND source_analysis_id=binding.source_analysis_id AND analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF p_input->'schema_version'='2'::JSONB THEN
        SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis;
        IF NOT FOUND OR cohort.owner_id IS DISTINCT FROM p_owner OR cohort.observation_id IS DISTINCT FROM p_observation
            OR cohort.binding_analysis_id IS DISTINCT FROM p_analysis
            OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        expected:=internal.observation_source_cohort_items(p_input,2);
        IF cohort.items IS DISTINCT FROM expected THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    ELSIF p_input->'schema_version'='3'::JSONB THEN
        SELECT * INTO audio FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis;
        IF NOT FOUND OR audio.owner_id IS DISTINCT FROM p_owner OR audio.observation_id IS DISTINCT FROM p_observation
            OR audio.binding_analysis_id IS DISTINCT FROM p_analysis
            OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        expected:=internal.observation_source_cohort_items(p_input,3);
        IF expected IS DISTINCT FROM jsonb_build_array(jsonb_build_object('media_id',audio.media_id,
            'content_type',audio.content_type,'byte_count',audio.byte_count,'sha256',audio.sha256)) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    ELSE
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_observation_source_input_chain(UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_source_bound_analysis_intent()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || NEW.analysis_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id) THEN
        PERFORM internal.assert_observation_source_input_chain(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot);
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_source_bound_analysis_intent() FROM PUBLIC,anon,authenticated,service_role;
-- Run before existing evidence checks, which may already take child locks.
CREATE TRIGGER a_guard_source_bound_analysis_intent BEFORE INSERT ON internal.observation_analysis_intents
    FOR EACH ROW EXECUTE FUNCTION internal.guard_source_bound_analysis_intent();
COMMENT ON FUNCTION internal.assert_observation_source_input_chain(UUID,UUID,UUID,JSONB) IS
    'Private durable metadata-chain check. No late locks, quota, consent, dispatch or settlement authority. Future funding exception requires intent/state/context and exact original quota checks too.';
RESET statement_timeout;
RESET lock_timeout;

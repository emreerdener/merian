SET lock_timeout='5s';
SET statement_timeout='2min';

-- Lock preparation only. Existing invocation denial remains unconditional.
CREATE FUNCTION internal.lock_observation_analysis_source(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; saved internal.observation_analysis_intents;
BEGIN
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
    IF NOT FOUND THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_analysis::TEXT,0::BIGINT));
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
        IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN;
    END IF;
    IF binding.owner_id IS DISTINCT FROM p_owner OR binding.observation_id IS DISTINCT FROM p_observation THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_source(p_owner,p_observation,binding.source_analysis_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_analysis::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
    -- Parent ownership serializes the hint read with all supported intent writes.
    -- The caller takes its existing intent row lock only after this proof.
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;
    IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
        OR saved.input_snapshot IS DISTINCT FROM binding.input_snapshot
        OR binding.fingerprint_version IS DISTINCT FROM 1
        OR binding.fingerprint IS DISTINCT FROM internal.observation_source_fingerprint(saved.input_snapshot) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- This establishes identity and lock order only. Recovery must not depend
    -- on live occupancy, media retention or upload expiry. Fresh dispatch still
    -- requires a separate admission proof and remains denied in this checkpoint.
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_observation_analysis_source(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE signature TEXT; definition TEXT; anchor TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'internal.claim_observation_analysis(uuid,uuid,uuid)',
        'public.claim_observation_analysis_recovery(uuid,uuid,uuid)',
        'internal.dispatch_observation_analysis(uuid,uuid,uuid,uuid,jsonb)',
        'internal.record_observation_analysis_draft(uuid,uuid,uuid,uuid,jsonb,jsonb)',
        'internal.complete_observation_analysis(uuid,uuid,uuid)',
        'internal.fail_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)',
        'public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:='    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
            RAISE EXCEPTION 'Reviewed execution entry changed: %',signature;
        END IF;
        EXECUTE replace(definition,anchor,'    PERFORM internal.lock_observation_analysis_source(p_owner,p_observation,p_analysis);');
    END LOOP;
    FOREACH signature IN ARRAY ARRAY[
        'internal.append_protected_observation_analysis(uuid,jsonb)',
        'internal.append_audio_observation_analysis(uuid,jsonb)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
        anchor:='    PERFORM users.id FROM public.users AS users WHERE users.id=p_user_id FOR UPDATE;';
        IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
            RAISE EXCEPTION 'Reviewed append entry changed: %',signature;
        END IF;
        EXECUTE replace(definition,anchor,'    PERFORM internal.lock_observation_analysis_source(p_user_id,observation,analysis);' || E'\n' || anchor);
    END LOOP;
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

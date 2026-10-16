-- Local qualification only: fixed private readers, no API grants or transport.
-- Recovery is original data; fresh I/O facts never prevent later erasure.
SET lock_timeout='5s';
SET statement_timeout='120s';

CREATE FUNCTION internal.assert_initial_media_handoff_reader_idle(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE member TEXT; present BOOLEAN;
BEGIN
    IF p_scan IS NULL OR internal.initial_media_handoff_sealed()
        OR internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
        OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    FOR member IN SELECT unnest(ARRAY['initial_media_handoff_staging','initial_media_handoff_writes',
        'initial_preparation_admission_staging','initial_preparation_admission_writes','initial_admitted_cancellation_staging',
        'initial_cancellation_quota_statements','initial_cancellation_credit_witness','initial_cancellation_lifecycle_witness',
        'initial_cancellation_retirement_witness','initial_cancellation_erasure_witness','initial_cancellation_receipt_witness',
        'initial_cancellation_terminal_snapshot']::TEXT[]) LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM internal.%I WHERE scan_id=$1)',member) INTO present USING p_scan;
        IF present THEN RAISE EXCEPTION 'initial_analysis_handoff_write_invalid' USING ERRCODE='55000'; END IF;
    END LOOP;
END; $$;

CREATE FUNCTION internal.read_initial_media_handoff_state(p_owner UUID,p_scan UUID,p_admission_digest TEXT)
RETURNS TABLE(response JSONB,admission internal.initial_preparation_admission_receipts,
    progress internal.initial_media_copy_progress,claim internal.initial_media_verification_claims_v2,
    verification internal.initial_media_verification_receipts_v2,"transfer" internal.initial_preparation_transfer_receipts,
    observed_at_ms BIGINT)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; now_ms BIGINT;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_admission_digest IS NULL OR p_admission_digest !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    -- Existing recovery owns the complete false-scope lock and terminal checks.
    -- Never acquire fresh eligibility in this transaction afterwards.
    PERFORM internal.recover_initial_admitted_media(p_owner,p_scan);
    PERFORM internal.assert_initial_media_handoff_reader_idle(p_scan);
    SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
    IF r.receipt_digest IS DISTINCT FROM p_admission_digest THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
    RETURN QUERY SELECT internal.initial_media_handoff_recovery_response(r,now_ms),r,c,k,v,t,now_ms
        FROM (SELECT 1) singleton
        LEFT JOIN internal.initial_media_copy_progress c ON c.scan_id=p_scan
        LEFT JOIN internal.initial_media_verification_claims_v2 k ON k.scan_id=p_scan
        LEFT JOIN internal.initial_media_verification_receipts_v2 v ON v.scan_id=p_scan
        LEFT JOIN internal.initial_preparation_transfer_receipts t ON t.scan_id=p_scan;
EXCEPTION WHEN NO_DATA_FOUND THEN
    RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
END; $$;

-- Closed implementation helper; wrappers below supply literal phase names.
CREATE FUNCTION internal.load_initial_media_handoff_io(
    p_owner UUID,p_scan UUID,p_admission_digest TEXT,p_phase TEXT,p_claim UUID
) RETURNS TABLE(admission internal.initial_preparation_admission_receipts,
    progress internal.initial_media_copy_progress,claim internal.initial_media_verification_claims_v2,
    source_backend internal.initial_preparation_source_backends,
    destination_backend internal.initial_analysis_media_backends,observed_at_ms BIGINT)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; c internal.initial_media_copy_progress;
    k internal.initial_media_verification_claims_v2; src internal.initial_preparation_source_backends;
    dst internal.initial_analysis_media_backends; profile JSONB; destination_text TEXT;
    original_sources UUID[]; actual_sources UUID[]; now_ms BIGINT; prior_ms BIGINT; cutoff BIGINT;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_admission_digest IS NULL OR p_admission_digest !~ '^[0-9a-f]{64}$'
        OR p_phase IS NULL OR p_phase NOT IN ('copy','verification')
        OR (p_claim IS NOT NULL) IS DISTINCT FROM (p_phase='verification') THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    -- Direct fresh scope: never call recovery, then escalate into eligibility.
    PERFORM internal.lock_initial_media_handoff_scope(p_owner,p_scan,TRUE);
    PERFORM internal.assert_initial_media_handoff_reader_idle(p_scan);
    SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
    IF r.receipt_digest IS DISTINCT FROM p_admission_digest THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    r:=internal.initial_admission_retained_receipt(p_owner,p_scan,r.admission_receipt_id);
    PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,r.admission_receipt_id);
    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    IF EXISTS(SELECT 1 FROM internal.identification_invocations v WHERE v.scan_id=p_scan
            OR v.reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts t WHERE t.scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    -- Bound the live union before aggregation, including corrupt privileged
    -- images. Canonical receipt arrays already have their original size caps.
    IF (SELECT count(*) FROM (SELECT 1 FROM internal.initial_preparation_source_registry
            WHERE scan_id=p_scan LIMIT 17) bounded)>16 THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    SELECT array_agg(object_id ORDER BY object_id) INTO original_sources FROM (
        SELECT (value->>'object_id')::UUID AS object_id FROM jsonb_array_elements(r.outcome::JSONB#>'{source_verification,entries}')
        UNION SELECT (value->>'object_id')::UUID FROM jsonb_array_elements(r.outcome::JSONB#>'{resolved_manifest,entries}')
            WHERE value->>'object_id' IS NOT NULL
    ) original;
    SELECT array_agg(t.object_id ORDER BY t.object_id) INTO actual_sources
        FROM internal.initial_preparation_source_registry t WHERE t.scan_id=p_scan;
    IF original_sources IS NULL OR actual_sources IS DISTINCT FROM original_sources
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry t WHERE t.scan_id=p_scan
            AND (t.retired OR t.marker_confirmed OR t.claim_token IS NOT NULL OR t.claim_expires_at IS NOT NULL
                OR t.backend_generation::TEXT IS DISTINCT FROM r.configuration::JSONB#>>'{assignment,preparation,backend_generation}')) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    -- The live-receipt check above matches every exact M1 image and row count;
    -- the retained proof binds each original source/prepared alias to that union.
    SELECT * INTO c FROM internal.initial_media_copy_progress t WHERE t.scan_id=p_scan;
    SELECT * INTO k FROM internal.initial_media_verification_claims_v2 t WHERE t.scan_id=p_scan;
    IF c.scan_id IS NULL
        OR (p_phase='copy' AND (c.completed_at_ms IS NOT NULL OR k.scan_id IS NOT NULL
            OR jsonb_array_length(c.completed_objects::JSONB)>=jsonb_array_length(r.mapping::JSONB->'objects')))
        OR (p_phase='verification' AND (c.completed_at_ms IS NULL OR k.scan_id IS NULL
            OR (k.claim::JSONB->>'claim_token')::UUID IS DISTINCT FROM p_claim
            OR EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 t WHERE t.scan_id=p_scan))) THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    profile:=r.configuration::JSONB#>'{assignment,handoff,profile}';
    SELECT * INTO src FROM internal.initial_preparation_source_backends t
        WHERE t.generation=(profile->>'source_backend_generation')::UUID;
    SELECT * INTO dst FROM internal.initial_analysis_media_backends t
        WHERE t.generation=(profile->>'destination_backend_generation')::UUID;
    IF src.generation IS NULL OR dst.generation IS NULL
        OR src.configuration_digest IS DISTINCT FROM profile->>'source_backend_config_digest' THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    destination_text:=internal.initial_canonical(to_jsonb(dst));
    IF destination_text IS DISTINCT FROM r.destination
        OR internal.initial_handoff_catalog_digest('destination_backend',destination_text)
            IS DISTINCT FROM profile->>'destination_backend_config_digest' THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    -- All locks and proof checks precede the sole authorization-time sample.
    now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
    cutoff:=(r.media_binding::JSONB#>>ARRAY['phase_window','cutoffs',p_phase])::BIGINT;
    prior_ms:=greatest((r.manifest::JSONB->>'authorized_at_ms')::BIGINT,c.started_at_ms,c.last_object_at_ms,
        c.completed_at_ms,(k.claim::JSONB->>'issued_at_ms')::BIGINT);
    IF now_ms<prior_ms OR now_ms>=cutoff THEN
        RAISE EXCEPTION 'initial_analysis_handoff_expired' USING ERRCODE='55000'; END IF;
    RETURN QUERY SELECT r,c,
        CASE WHEN k.scan_id IS NULL THEN NULL::internal.initial_media_verification_claims_v2 ELSE k END,
        src,dst,now_ms;
EXCEPTION WHEN NO_DATA_FOUND THEN
    -- Transfer/erasure can remove the preparation intent before fresh
    -- eligibility's STRICT lookup. It is a closed denial, never fresh data.
    RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000';
END; $$;

CREATE FUNCTION internal.load_initial_media_copy_io(p_owner UUID,p_scan UUID,p_admission_digest TEXT)
RETURNS TABLE(admission internal.initial_preparation_admission_receipts,
    progress internal.initial_media_copy_progress,claim internal.initial_media_verification_claims_v2,
    source_backend internal.initial_preparation_source_backends,
    destination_backend internal.initial_analysis_media_backends,observed_at_ms BIGINT)
LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
    SELECT * FROM internal.load_initial_media_handoff_io(p_owner,p_scan,p_admission_digest,'copy',NULL);
$$;
CREATE FUNCTION internal.load_initial_media_verification_io(p_owner UUID,p_scan UUID,p_admission_digest TEXT,p_claim UUID)
RETURNS TABLE(admission internal.initial_preparation_admission_receipts,
    progress internal.initial_media_copy_progress,claim internal.initial_media_verification_claims_v2,
    source_backend internal.initial_preparation_source_backends,
    destination_backend internal.initial_analysis_media_backends,observed_at_ms BIGINT)
LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
    SELECT * FROM internal.load_initial_media_handoff_io(p_owner,p_scan,p_admission_digest,'verification',p_claim);
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_media_handoff_reader_idle(UUID),
    internal.read_initial_media_handoff_state(UUID,UUID,TEXT),
    internal.load_initial_media_handoff_io(UUID,UUID,TEXT,TEXT,UUID),
    internal.load_initial_media_copy_io(UUID,UUID,TEXT),
    internal.load_initial_media_verification_io(UUID,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

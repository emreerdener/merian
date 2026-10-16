-- Fixed private handoff owners. Results are original stored data, never I/O or
-- provider authority. No API grants or installed adapter composition.
SET lock_timeout='5s';
SET statement_timeout='120s';

-- Read/lock only. Decide fresh vs exact replay under the original owner scope
-- before eligibility/funding/member acquisition; never false-scope then true.
CREATE FUNCTION internal.prepare_initial_media_handoff_operation(
    p_owner UUID,p_scan UUID,p_action TEXT,p_admission_digest TEXT,
    p_object UUID DEFAULT NULL,p_claim UUID DEFAULT NULL,p_verification_digest TEXT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; admitted internal.initial_analysis_admissions;
    fresh BOOLEAN; transferred BOOLEAN; member TEXT; present BOOLEAN;
BEGIN
    IF p_owner IS NULL OR p_scan IS NULL OR p_action IS NULL OR p_action NOT IN
        ('start_copy','record_object','complete_copy','claim','verify','transfer')
        OR p_admission_digest IS NULL OR p_admission_digest !~ '^[0-9a-f]{64}$'
        OR (p_object IS NOT NULL) IS DISTINCT FROM (p_action='record_object')
        OR (p_claim IS NOT NULL) IS DISTINCT FROM (p_action='verify')
        OR (p_verification_digest IS NOT NULL) IS DISTINCT FROM (p_action='transfer')
        OR (p_verification_digest IS NOT NULL AND p_verification_digest !~ '^[0-9a-f]{64}$') THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    -- These owner-serialized reads choose lock policy only. The complete proof
    -- and every supplied immutable argument are checked after canonical locks.
    transferred:=EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan);
    fresh:=NOT transferred AND NOT CASE p_action
        WHEN 'start_copy' THEN EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=p_scan)
        WHEN 'record_object' THEN EXISTS(SELECT 1 FROM internal.initial_media_copy_progress c,
            LATERAL jsonb_array_elements(c.completed_objects::JSONB) x(value)
            WHERE c.scan_id=p_scan AND (x.value->>'object_id')::UUID=p_object)
        WHEN 'complete_copy' THEN EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=p_scan AND completed_at_ms IS NOT NULL)
        WHEN 'claim' THEN EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan)
        WHEN 'verify' THEN EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan)
        WHEN 'transfer' THEN transferred END;
    PERFORM internal.lock_initial_media_handoff_scope(p_owner,p_scan,fresh);
    IF internal.initial_media_handoff_sealed() OR internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
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
    SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
    IF NOT FOUND OR r.owner_id IS DISTINCT FROM p_owner OR r.receipt_digest IS DISTINCT FROM p_admission_digest THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    r:=internal.initial_admission_retained_receipt(p_owner,p_scan,r.admission_receipt_id);
    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    PERFORM internal.assert_initial_admission_live_receipt(p_owner,p_scan,r.admission_receipt_id);
    IF p_action='record_object' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r.mapping::JSONB->'objects') x(value)
            WHERE (value->>'object_id')::UUID=p_object)
        OR p_action='verify' AND (SELECT (claim::JSONB->>'claim_token')::UUID FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan) IS DISTINCT FROM p_claim
        OR p_action='transfer' AND (SELECT receipt_digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan) IS DISTINCT FROM p_verification_digest THEN
        RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    -- No receipt, token, time or cached success is returned before these checks.
    RETURN fresh;
END; $$;

-- Output derivation is read-only under the caller's already-held scope. No new
-- eligibility locks or artifact timestamp/token sampling occur here.
CREATE FUNCTION internal.initial_media_handoff_operation_response(p_owner UUID,p_scan UUID,p_transfer BOOLEAN)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts; result JSONB;
BEGIN
    IF p_transfer IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan AND owner_id=p_owner;
    result:=internal.initial_media_handoff_recovery_response(r,floor(extract(epoch FROM clock_timestamp())*1000));
    IF NOT p_transfer AND result->>'outcome'='transferred' THEN
        RETURN internal.parse_initial_admission_recovery_response(internal.initial_canonical(jsonb_build_object(
            'version',2,'outcome','held','authority','none','reason','already_transferred',
            'transfer_receipt_digest',result->'transfer_receipt_digest')));
    END IF;
    RETURN result;
END; $$;

CREATE FUNCTION internal.begin_initial_media_copy_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT)
RETURNS TABLE(response JSONB,"progress" internal.initial_media_copy_progress)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'start_copy',p_admission_digest,NULL,NULL,NULL) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'start_copy',p_admission_digest,NULL,NULL,NULL);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,FALSE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_media_copy_progress;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_media_copy_progress t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.record_initial_media_copy_object_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT,p_object UUID)
RETURNS TABLE(response JSONB,"progress" internal.initial_media_copy_progress)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'record_object',p_admission_digest,p_object,NULL,NULL) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'record_object',p_admission_digest,p_object,NULL,NULL);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,FALSE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_media_copy_progress;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_media_copy_progress t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.complete_initial_media_copy_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT)
RETURNS TABLE(response JSONB,"progress" internal.initial_media_copy_progress)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'complete_copy',p_admission_digest,NULL,NULL,NULL) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'complete_copy',p_admission_digest,NULL,NULL,NULL);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,FALSE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_media_copy_progress;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_media_copy_progress t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.claim_initial_media_verification_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT)
RETURNS TABLE(response JSONB,"claim" internal.initial_media_verification_claims_v2)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'claim',p_admission_digest,NULL,NULL,NULL) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'claim',p_admission_digest,NULL,NULL,NULL);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,FALSE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_media_verification_claims_v2;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_media_verification_claims_v2 t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.settle_initial_media_verification_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT,p_claim UUID)
RETURNS TABLE(response JSONB,"verification" internal.initial_media_verification_receipts_v2)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'verify',p_admission_digest,NULL,p_claim,NULL) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'verify',p_admission_digest,NULL,p_claim,NULL);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,FALSE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_media_verification_receipts_v2;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_media_verification_receipts_v2 t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

CREATE FUNCTION internal.transfer_initial_preparation_v2(p_owner UUID,p_scan UUID,p_admission_digest TEXT,p_verification_digest TEXT)
RETURNS TABLE(response JSONB,"transfer" internal.initial_preparation_transfer_receipts)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
    IF internal.prepare_initial_media_handoff_operation(p_owner,p_scan,'transfer',p_admission_digest,NULL,NULL,p_verification_digest) THEN
        SET CONSTRAINTS internal.initial_media_handoff_completion,internal.initial_source_intent_cohort,
            internal.initial_source_fence_cohort,internal.initial_source_mapping_cohort,
            internal.initial_source_registry_cohort,internal.initial_execution_cohort DEFERRED;
        INSERT INTO internal.initial_media_handoff_staging(scan_id,owner_id,action,admission_digest,object_id,claim_token,verification_digest)
            VALUES(p_scan,p_owner,'transfer',p_admission_digest,NULL,NULL,p_verification_digest);
        PERFORM internal.execute_initial_media_handoff_stage(p_scan);
    END IF;
    result:=internal.initial_media_handoff_operation_response(p_owner,p_scan,TRUE);
    IF result->>'outcome'='held' THEN
        RETURN QUERY SELECT result,NULL::internal.initial_preparation_transfer_receipts;
    ELSE
        RETURN QUERY SELECT result,t FROM internal.initial_preparation_transfer_receipts t WHERE t.scan_id=p_scan AND t.owner_id=p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_incomplete' USING ERRCODE='55000'; END IF;
    END IF;
END; $$;

REVOKE ALL ON FUNCTION internal.prepare_initial_media_handoff_operation(UUID,UUID,TEXT,TEXT,UUID,UUID,TEXT),
    internal.initial_media_handoff_operation_response(UUID,UUID,BOOLEAN),
    internal.begin_initial_media_copy_v2(UUID,UUID,TEXT),
    internal.record_initial_media_copy_object_v2(UUID,UUID,TEXT,UUID),
    internal.complete_initial_media_copy_v2(UUID,UUID,TEXT),
    internal.claim_initial_media_verification_v2(UUID,UUID,TEXT),
    internal.settle_initial_media_verification_v2(UUID,UUID,TEXT,UUID),
    internal.transfer_initial_preparation_v2(UUID,UUID,TEXT,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

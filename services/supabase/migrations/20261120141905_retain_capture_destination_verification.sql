SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Prepared observation only. A verified GET is neither writer quiescence nor
-- binding, publication, History admission, or permission to discard originals.
ALTER TABLE internal.capture_promotion_operations
    ADD COLUMN destination_verified_at TIMESTAMPTZ,
    ADD COLUMN verification_origin TEXT,
    ADD CONSTRAINT capture_promotion_verified_shape CHECK (
        (destination_verified_at IS NULL) = (verification_origin IS NULL)
        AND (verification_origin IS NULL OR verification_origin IN
            ('write_acknowledged','write_precondition_failed','destination_recovery'))
        AND (destination_verified_at IS NULL OR write_authorized_at IS NOT NULL));

-- Historical read/receipt owner. Deliberately does not lock/read mutable assets,
-- jobs or intents. Never grants source GET or another PUT. The retained cohort
-- and exact operation remain authoritative for this point-in-time observation.
-- Account/user/scan precede operation; no operation -> source/job lock inversion.
CREATE FUNCTION internal.lock_capture_promotion_recovery(p_binding JSONB)
RETURNS internal.capture_promotion_operations LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; saved internal.capture_promotion_operations%ROWTYPE;
BEGIN
    b := internal.parse_capture_promotion_binding(p_binding);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:' || b.owner_id::TEXT,0));
    PERFORM id FROM public.users WHERE id=b.owner_id FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=b.owner_id) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || b.scan_id::TEXT,0));
    IF EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=b.scan_id) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id FOR UPDATE;
    IF NOT FOUND OR saved.retired_at IS NOT NULL OR saved.write_authorized_at IS NULL
        OR saved.cohort_id IS NULL OR internal.capture_promotion_binding(saved) IS DISTINCT FROM p_binding THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM internal.capture_promotion_cohorts c
        WHERE c.cohort_id=saved.cohort_id AND c.owner_id=b.owner_id AND c.scan_id=b.scan_id
        AND c.consumer='ordinary_scan_ingestion'
        AND (SELECT count(*) FROM pg_catalog.jsonb_array_elements(c.members) member
            WHERE member->'binding'=p_binding)=1) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN saved;
END;
$$;

CREATE FUNCTION public.authorize_capture_promotion_recovery(p_binding JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_capture_promotion_recovery(p_binding);
    RETURN TRUE;
END;
$$;

-- Trusted service attests a complete, bounded, actually-read destination body
-- matching the closed saved MIME/length/SHA binding. No caller timestamp or URL.
-- A lost receipt reply can repeat exactly; the first observation is never reset.
CREATE FUNCTION public.record_capture_promotion_verification(p_binding JSONB,p_origin TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE saved internal.capture_promotion_operations%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_origin IS NULL OR p_origin NOT IN ('write_acknowledged','write_precondition_failed','destination_recovery') THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE='22023';
    END IF;
    saved := internal.lock_capture_promotion_recovery(p_binding);
    IF saved.destination_verified_at IS NULL THEN
        UPDATE internal.capture_promotion_operations
            SET destination_verified_at=pg_catalog.clock_timestamp(),verification_origin=p_origin
            WHERE operation_id=saved.operation_id RETURNING * INTO saved;
    END IF;
    RETURN pg_catalog.jsonb_build_object('operationId',saved.operation_id,'cohortId',saved.cohort_id,
        'verifiedAt',saved.destination_verified_at,'origin',saved.verification_origin);
END;
$$;

REVOKE ALL ON FUNCTION internal.lock_capture_promotion_recovery(JSONB),
    public.authorize_capture_promotion_recovery(JSONB),public.record_capture_promotion_verification(JSONB,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.authorize_capture_promotion_recovery(JSONB),public.record_capture_promotion_verification(JSONB,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.authorize_capture_promotion_recovery(jsonb)','Prepared exact retained-cohort destination GET authority only; no source access, write, binding or publication.'),
 ('service_role','public.record_capture_promotion_verification(jsonb,text)','Prepared monotonic content observation after actual bounded destination verification; retains consumed writes and retirement obligations.');

-- Runtime entry point does not require direct ledger SELECT or a mutating claim
-- to discover a job ID. Resolve it under the same fence, then use the original
-- exact-job registration owner. The caller already holds begin's checksums.
CREATE FUNCTION public.register_capture_promotion_ingestion(p_cohort UUID,p_manifest TEXT,p_request TEXT,p_bindings JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; job UUID; seal TEXT;
BEGIN
    PERFORM internal.require_service_role();
    IF p_bindings IS NULL OR pg_catalog.jsonb_typeof(p_bindings) IS DISTINCT FROM 'array'
        OR pg_catalog.octet_length(p_bindings::TEXT)>32768 THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.jsonb_array_length(p_bindings) NOT BETWEEN 1 AND 8 THEN
        RAISE EXCEPTION 'capture_promotion_cohort_invalid' USING ERRCODE='22023';
    END IF;
    b := internal.parse_capture_promotion_binding(p_bindings->0);
    PERFORM internal.lock_capture_promotion_source(b);
    SELECT id INTO job FROM public.scan_ingestion_jobs WHERE user_id=b.owner_id AND scan_id=b.scan_id::TEXT;
    IF NOT FOUND THEN RAISE EXCEPTION 'capture_promotion_cohort_unavailable' USING ERRCODE='55000'; END IF;
    seal := public.register_capture_promotion_cohort(p_cohort,job,p_manifest,p_request,p_bindings);
    RETURN pg_catalog.jsonb_build_object('cohortId',p_cohort,'jobId',job,'cohortSHA256',seal);
END;
$$;
REVOKE ALL ON FUNCTION public.register_capture_promotion_ingestion(UUID,TEXT,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.register_capture_promotion_ingestion(UUID,TEXT,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.register_capture_promotion_ingestion(uuid,text,text,jsonb)','Prepared complete cohort registration from locked server-owned ingestion identity, without ledger table privileges or mutation.');

RESET statement_timeout;
RESET lock_timeout;

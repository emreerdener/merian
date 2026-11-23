SET lock_timeout='5s';
SET statement_timeout='2min';

-- These service-only adapters extend the existing ordinary ingestion owner.
-- They neither admit a job nor dispatch a provider nor settle funding.
CREATE FUNCTION public.reserve_owned_initial_evidence(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.reserve_ordinary_initial_evidence(p_owner,p_request);
END;
$$;
CREATE FUNCTION public.complete_owned_initial_evidence(p_owner UUID,p_request JSONB,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.complete_ordinary_initial_evidence(p_owner,p_request,p_object);
END;
$$;

-- Recovery must survive ingestion-job TTL, but never observation deletion.
-- A strict job/binding cannot fall back to reconstructing a mutable scan row.
CREATE FUNCTION public.recover_owned_initial_completion(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; job public.scan_ingestion_jobs;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_scan IS NULL OR p_owner=p_scan THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0));
    SELECT * INTO job FROM public.scan_ingestion_jobs WHERE user_id=p_owner AND scan_id=p_scan::TEXT FOR UPDATE;
    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=p_scan FOR UPDATE;
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan AND (user_id<>p_owner OR is_tombstoned))
        OR (saved.scan_id IS NOT NULL AND saved.owner_id<>p_owner) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF saved.scan_id IS NULL AND job.initial_evidence_generation IS NULL THEN RETURN NULL; END IF;
    IF saved.sealed_at IS NULL OR saved.retired_at IS NOT NULL
        OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan AND user_id=p_owner AND NOT is_tombstoned) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN saved.completion_response;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_owned_initial_evidence(UUID,JSONB),
 public.complete_owned_initial_evidence(UUID,JSONB,UUID),
 public.recover_owned_initial_completion(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_initial_evidence(UUID,JSONB),
 public.complete_owned_initial_evidence(UUID,JSONB,UUID),
 public.recover_owned_initial_completion(UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_initial_evidence(uuid,jsonb)','Allocate immutable private evidence for an already accepted ordinary ingestion job; default closed.'),
 ('service_role','public.complete_owned_initial_evidence(uuid,jsonb,uuid)','Acknowledge trusted exact-byte readback of an allocated ordinary initial artifact.'),
 ('service_role','public.recover_owned_initial_completion(uuid,uuid)','Recover the sealed initial completion under owner and deletion fences, including after ingestion-job TTL.');
RESET statement_timeout;
RESET lock_timeout;

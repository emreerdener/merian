SET lock_timeout='5s';
SET statement_timeout='2min';

-- Internal ingestion recovery only. This is not a completed observation and
-- grants no right to redispatch inference, mutate funding, or adopt scan data.
CREATE FUNCTION public.recover_owned_initial_result(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; receipt JSONB; digest TEXT;
BEGIN
    PERFORM internal.require_service_role();
    saved:=internal.lock_ordinary_initial_evidence(p_owner,p_request);
    -- Recovery cannot create an allocation. A missing or unfinished retention
    -- attempt fails closed; any insertion by the locking helper rolls back.
    IF saved.allocated_at IS NULL THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    receipt:=internal.ordinary_initial_evidence_receipt(saved);
    IF jsonb_array_length(receipt->'items')<>jsonb_array_length(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items')
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    IF saved.accepted_result IS NULL THEN RETURN NULL; END IF;
    digest:=encode(extensions.digest(convert_to(jsonb_build_object('result',saved.accepted_result,'species_id',saved.accepted_species_id)::TEXT,'UTF8'),'sha256'),'hex');
    IF saved.accepted_result_digest IS DISTINCT FROM digest THEN
        RAISE EXCEPTION 'initial_evidence_result_integrity' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('schema_version',1,'owner_id',saved.owner_id,'scan_id',saved.scan_id,
        'generation',saved.generation,'evidence_digest',saved.evidence_digest,
        'result',saved.accepted_result,'species_id',saved.accepted_species_id,'result_digest',digest);
END;
$$;

REVOKE ALL ON FUNCTION public.recover_owned_initial_result(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_owned_initial_result(UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.recover_owned_initial_result(uuid,jsonb)','Recover the exact accepted ordinary provider result under request, owner, deletion and ready-artifact fences; never redispatch inference.');

RESET statement_timeout;
RESET lock_timeout;

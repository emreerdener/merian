SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.ordinary_initial_evidence
 ADD COLUMN accepted_result JSONB,
 ADD COLUMN accepted_species_id UUID,
 ADD COLUMN accepted_result_digest TEXT,
 ADD CONSTRAINT ordinary_initial_accepted_result CHECK(
   (accepted_result IS NULL)=(accepted_result_digest IS NULL)
   AND (accepted_result IS NOT NULL OR accepted_species_id IS NULL)
   AND (accepted_result_digest IS NULL OR accepted_result_digest ~ '^[0-9a-f]{64}$'));

CREATE OR REPLACE FUNCTION internal.guard_ordinary_initial_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF to_jsonb(NEW)-ARRAY['allocated_at','retired_at','sealed_at','result_snapshot','completion_response','accepted_result','accepted_species_id','accepted_result_digest']
        IS DISTINCT FROM to_jsonb(OLD)-ARRAY['allocated_at','retired_at','sealed_at','result_snapshot','completion_response','accepted_result','accepted_species_id','accepted_result_digest']
        OR (OLD.allocated_at IS NOT NULL AND NEW.allocated_at IS DISTINCT FROM OLD.allocated_at)
        OR (OLD.retired_at IS NOT NULL AND NEW.retired_at IS DISTINCT FROM OLD.retired_at)
        OR (NEW.retired_at IS NOT NULL AND NEW.sealed_at IS NOT NULL)
        OR (OLD.sealed_at IS NOT NULL AND (NEW.sealed_at IS DISTINCT FROM OLD.sealed_at
            OR NEW.result_snapshot IS DISTINCT FROM OLD.result_snapshot OR NEW.completion_response IS DISTINCT FROM OLD.completion_response))
        OR (OLD.accepted_result IS NOT NULL AND (NEW.accepted_result IS DISTINCT FROM OLD.accepted_result
            OR NEW.accepted_species_id IS DISTINCT FROM OLD.accepted_species_id OR NEW.accepted_result_digest IS DISTINCT FROM OLD.accepted_result_digest))
        OR (OLD.accepted_result IS NULL AND NEW.accepted_result IS NOT NULL AND (NEW.allocated_at IS NULL OR NEW.retired_at IS NOT NULL))
        OR (NEW.sealed_at IS NOT NULL AND (NEW.allocated_at IS NULL OR NEW.accepted_result IS NULL)) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;

-- Bind the server-validated provider result and resolved taxonomy before any
-- scan insertion. A saved scan, even one owned by this user, cannot supply it.
CREATE FUNCTION public.bind_owned_initial_result(p_owner UUID,p_request JSONB,p_result JSONB,p_species UUID)
RETURNS TEXT LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; receipt JSONB; digest TEXT;
BEGIN
    PERFORM internal.require_service_role();
    saved:=internal.lock_ordinary_initial_evidence(p_owner,p_request);
    IF jsonb_typeof(p_result) IS DISTINCT FROM 'object' OR octet_length(p_result::TEXT)>1044480
        OR p_result->>'scan_id' IS DISTINCT FROM saved.scan_id::TEXT
        OR NOT(p_result ?& ARRAY['is_biological_subject','confidence_score','inference_tier','ai_reasoning'])
        OR jsonb_typeof(p_result->'is_biological_subject') IS DISTINCT FROM 'boolean'
        OR jsonb_typeof(p_result->'confidence_score') IS DISTINCT FROM 'number'
        OR (p_result->>'confidence_score')::NUMERIC NOT BETWEEN 0 AND 1
        OR jsonb_typeof(p_result->'inference_tier') IS DISTINCT FROM 'string'
        OR (p_result->>'inference_tier' IN ('flash','pro')) IS NOT TRUE THEN
        RAISE EXCEPTION 'invalid_scan_response_envelope' USING ERRCODE='22023';
    END IF;
    digest:=encode(extensions.digest(convert_to(jsonb_build_object('result',p_result,'species_id',p_species)::TEXT,'UTF8'),'sha256'),'hex');
    IF saved.accepted_result IS NOT NULL THEN
        IF saved.accepted_result IS DISTINCT FROM p_result OR saved.accepted_species_id IS DISTINCT FROM p_species
            OR saved.accepted_result_digest IS DISTINCT FROM digest THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN digest;
    END IF;
    IF saved.sealed_at IS NOT NULL OR saved.retired_at IS NOT NULL OR saved.allocated_at IS NULL
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=saved.scan_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    receipt:=internal.ordinary_initial_evidence_receipt(saved);
    IF jsonb_array_length(receipt->'items')<>jsonb_array_length(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items')
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    UPDATE internal.ordinary_initial_evidence SET accepted_result=p_result,accepted_species_id=p_species,accepted_result_digest=digest
        WHERE scan_id=saved.scan_id;
    RETURN digest;
END;
$$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    definition:=pg_get_functiondef('internal.seal_ordinary_initial_completion(uuid,uuid,jsonb)'::regprocedure);
    anchor:=$a$    proof:=jsonb_build_object('schema_version',1,$a$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_result_seal_drift'; END IF;
    EXECUTE replace(definition,anchor,$a$    IF saved.accepted_result IS NULL OR p_response->'data' IS DISTINCT FROM saved.accepted_result
        OR result IS DISTINCT FROM jsonb_build_object(
            'scan_id',p_scan,'primary_identification',saved.accepted_result->'primary_identification',
            'identification_provenance',saved.accepted_result->'identification_provenance','species_id',saved.accepted_species_id,
            'is_biological_subject',saved.accepted_result->'is_biological_subject','candidates',saved.accepted_result->'candidates',
            'pet_identification',saved.accepted_result->'pet_identification','ai_confidence_score',saved.accepted_result->'confidence_score',
            'ai_reasoning',saved.accepted_result->'ai_reasoning','inference_tier',saved.accepted_result->'inference_tier') THEN
        RAISE EXCEPTION 'initial_evidence_result_integrity' USING ERRCODE='22023';
    END IF;
    -- Baseline8 retains the original full wire result. The scan row above is
    -- compared only as a projection, never adopted as provenance.
    result:=saved.accepted_result;
$a$||anchor);
END;
$patch$;

REVOKE ALL ON FUNCTION public.bind_owned_initial_result(UUID,JSONB,JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bind_owned_initial_result(UUID,JSONB,JSONB,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.bind_owned_initial_result(uuid,jsonb,jsonb,uuid)','Bind the original server-validated ordinary result and taxonomy before scan insertion; immutable and replay-only thereafter.');
RESET statement_timeout;
RESET lock_timeout;

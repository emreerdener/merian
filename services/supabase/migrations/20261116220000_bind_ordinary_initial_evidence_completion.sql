SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE public.scan_ingestion_jobs ADD COLUMN initial_evidence_generation UUID;

-- The accepted intent marks the existing job in the same begin transaction.
-- Missing reservation/readback can never downgrade that job to legacy success.
CREATE FUNCTION internal.bind_ordinary_initial_intent()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE request JSONB:=NEW.request_payload->'initialEvidence'; contract JSONB; generation UUID;
BEGIN
    IF TG_OP='UPDATE' AND OLD.request_payload ? 'initialEvidence' THEN
        IF NEW.user_id<>OLD.user_id OR NEW.scan_id<>OLD.scan_id OR NEW.request_payload<>OLD.request_payload
            OR NEW.payload_checksum IS DISTINCT FROM OLD.payload_checksum THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- The immutable intent was already bound by its insert transaction.
        -- Scheduler updates hold this intent row before running this trigger;
        -- reacquiring the job here would invert retention's job -> intent order.
        RETURN NEW;
    END IF;
    IF request IS NULL THEN
        IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE user_id=NEW.user_id AND scan_id=NEW.scan_id AND initial_evidence_generation IS NOT NULL)
            OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id::TEXT=NEW.scan_id) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN NEW;
    END IF;
    IF jsonb_typeof(request) IS DISTINCT FROM 'object' OR octet_length(request::TEXT)>1044480
        OR NOT(request ?& ARRAY['schema_version','scan_id','generation','evidence_digest','evidence_manifest'])
        OR request-ARRAY['schema_version','scan_id','generation','evidence_digest','evidence_manifest']<>'{}'
        OR request->'schema_version' IS DISTINCT FROM '1'::JSONB OR request->>'scan_id' IS DISTINCT FROM NEW.scan_id
        OR jsonb_typeof(request->'scan_id') IS DISTINCT FROM 'string' OR jsonb_typeof(request->'generation') IS DISTINCT FROM 'string'
        OR jsonb_typeof(request->'evidence_digest') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    contract:=internal.initial_evidence_contract(request->'evidence_manifest',request->>'scan_id',request->>'generation');
    generation:=(request->>'generation')::UUID;
    IF request->>'evidence_digest' IS DISTINCT FROM contract->>'evidence_digest' OR NEW.payload_checksum IS NULL
        OR NEW.user_id IN (NEW.scan_id::UUID,generation)
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'items') x WHERE x->>'media_id'=NEW.user_id::TEXT) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE user_id=NEW.user_id AND scan_id=NEW.scan_id AND initial_evidence_generation=generation)
        AND (SELECT ordinary_initial_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    UPDATE public.scan_ingestion_jobs SET initial_evidence_generation=generation
        WHERE user_id=NEW.user_id AND scan_id=NEW.scan_id AND status NOT IN ('complete','failed_terminal')
        AND (initial_evidence_generation IS NULL OR initial_evidence_generation=generation);
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER bind_ordinary_initial_intent BEFORE INSERT OR UPDATE ON public.scan_ingestion_intents
    FOR EACH ROW EXECUTE FUNCTION internal.bind_ordinary_initial_intent();

CREATE FUNCTION internal.guard_ordinary_initial_job()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP='UPDATE' AND OLD.initial_evidence_generation IS NOT NULL AND
        (NEW.initial_evidence_generation IS DISTINCT FROM OLD.initial_evidence_generation OR NEW.user_id<>OLD.user_id OR NEW.scan_id<>OLD.scan_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF TG_OP='DELETE' OR NEW.status='failed_terminal' THEN
        -- A permanently retired job cannot be resurrected into a different
        -- object allocation. Keep its marker; erase its private byte objects.
        UPDATE internal.ordinary_initial_evidence SET retired_at=COALESCE(retired_at,clock_timestamp())
            WHERE scan_id::TEXT=OLD.scan_id AND owner_id=OLD.user_id AND sealed_at IS NULL;
        DELETE FROM internal.ordinary_initial_evidence_objects WHERE scan_id IN (
            SELECT scan_id FROM internal.ordinary_initial_evidence WHERE scan_id::TEXT=OLD.scan_id AND owner_id=OLD.user_id AND retired_at IS NOT NULL
        );
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_ordinary_initial_job BEFORE UPDATE OR DELETE ON public.scan_ingestion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.guard_ordinary_initial_job();

CREATE FUNCTION internal.seal_ordinary_initial_completion(p_owner UUID,p_scan UUID,p_response JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; job public.scan_ingestion_jobs; scan public.scans; result JSONB; receipt JSONB; proof JSONB;
BEGIN
    -- Caller owns user -> scan advisory -> job/scan locks and performs funding
    -- settlement in this transaction. Failure here rolls the entire completion back.
    SELECT * INTO job FROM public.scan_ingestion_jobs WHERE user_id=p_owner AND scan_id=p_scan::TEXT FOR UPDATE;
    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=p_scan FOR UPDATE;
    IF job.initial_evidence_generation IS NULL AND saved.scan_id IS NULL THEN
        IF p_response ? 'initial_evidence' THEN RAISE EXCEPTION 'invalid_scan_response_envelope' USING ERRCODE='22023'; END IF;
        RETURN p_response;
    END IF;
    IF saved.scan_id IS NULL OR saved.owner_id<>p_owner OR saved.retired_at IS NOT NULL OR saved.allocated_at IS NULL THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    IF saved.sealed_at IS NOT NULL THEN RETURN saved.completion_response; END IF;
    IF job.id IS DISTINCT FROM saved.job_id OR job.initial_evidence_generation IS DISTINCT FROM saved.generation OR job.status<>'complete'
        OR jsonb_typeof(p_response) IS DISTINCT FROM 'object' OR p_response->'success' IS DISTINCT FROM 'true'::JSONB
        OR p_response#>>'{data,scan_id}' IS DISTINCT FROM p_scan::TEXT THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO scan FROM public.scans WHERE id=p_scan AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    receipt:=internal.ordinary_initial_evidence_receipt(saved);
    IF jsonb_array_length(receipt->'items')<>jsonb_array_length(internal.initial_evidence_contract(saved.evidence_manifest,p_scan::TEXT,saved.generation::TEXT)->'items')
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    result:=jsonb_build_object('scan_id',scan.id,'primary_identification',scan.primary_identification,
        'identification_provenance',scan.identification_provenance,'species_id',scan.species_id,'is_biological_subject',scan.is_biological_subject,
        'candidates',scan.candidates,'pet_identification',scan.pet_identification,'ai_confidence_score',scan.ai_confidence_score,
        'ai_reasoning',scan.ai_reasoning,'inference_tier',scan.inference_tier);
    proof:=jsonb_build_object('schema_version',1,'owner_id',p_owner,'scan_id',p_scan,'generation',saved.generation,'evidence_digest',saved.evidence_digest);
    IF p_response ? 'initial_evidence' AND p_response->'initial_evidence' IS DISTINCT FROM proof THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    p_response:=p_response||jsonb_build_object('initial_evidence',proof);
    UPDATE internal.ordinary_initial_evidence SET sealed_at=job.completed_at,result_snapshot=result,completion_response=p_response WHERE scan_id=p_scan;
    RETURN p_response;
END;
$$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    definition:=pg_get_functiondef('public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)'::regprocedure);
    -- Reuse the reviewed profile fence, including its retired-owner denial and
    -- null-input semantics. Do not prepend a second check with a different error.
    anchor:=$owner$    IF p_user_id IS NOT NULL THEN
        PERFORM id FROM public.users WHERE id = p_user_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'scan_ingestion_owner_unavailable' USING ERRCODE = 'P0002';
        END IF;
    END IF;$owner$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1
        OR strpos(definition,'PERFORM pg_advisory_xact_lock(')=0
        OR strpos(definition,anchor)>strpos(definition,'PERFORM pg_advisory_xact_lock(') THEN
        RAISE EXCEPTION 'initial_ingestion_lock_drift';
    END IF;

    definition:=pg_get_functiondef('public.complete_scan_ingestion_with_entitlement(uuid,uuid,jsonb,jsonb,text[])'::regprocedure);
    anchor:=$a$    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'result', finalization_result,
        'response_envelope', COALESCE($a$;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'initial_completion_seal_drift'; END IF;
    EXECUTE replace(definition,anchor,$a$    stored_response:=internal.seal_ordinary_initial_completion(p_user_id,p_scan_id,COALESCE(stored_response,enriched_response));
    UPDATE public.scan_ingestion_jobs SET response_envelope=stored_response
        WHERE user_id=p_user_id AND scan_id=p_scan_id::TEXT AND response_envelope IS DISTINCT FROM stored_response;

$a$||anchor);
END;
$patch$;

REVOKE ALL ON FUNCTION internal.bind_ordinary_initial_intent(),internal.guard_ordinary_initial_job(),
    internal.seal_ordinary_initial_completion(UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

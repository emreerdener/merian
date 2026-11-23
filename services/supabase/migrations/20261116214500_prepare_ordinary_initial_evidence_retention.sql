SET lock_timeout='5s';
SET statement_timeout='2min';

-- Companion of the existing ordinary ingestion job, never a second admission,
-- inference or funding owner. A completed proof survives job/intent retention.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN ordinary_initial_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.ordinary_initial_evidence (
    scan_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    generation UUID NOT NULL UNIQUE,
    job_id UUID NOT NULL UNIQUE,
    payload_checksum TEXT NOT NULL CHECK(payload_checksum ~ '^[0-9a-f]{64}$'),
    evidence_digest TEXT NOT NULL CHECK(evidence_digest ~ '^[0-9a-f]{64}$'),
    evidence_manifest JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    allocated_at TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    sealed_at TIMESTAMPTZ,
    result_snapshot JSONB,
    completion_response JSONB,
    CHECK(owner_id<>scan_id AND generation NOT IN (owner_id,scan_id)),
    CHECK((sealed_at IS NULL)=(result_snapshot IS NULL) AND (sealed_at IS NULL)=(completion_response IS NULL))
);
CREATE TABLE internal.ordinary_initial_evidence_objects (
    object_id UUID PRIMARY KEY,
    scan_id UUID NOT NULL REFERENCES internal.ordinary_initial_evidence(scan_id) ON DELETE CASCADE,
    media_id UUID NOT NULL UNIQUE,
    item_index INTEGER NOT NULL CHECK(item_index BETWEEN 0 AND 63),
    role TEXT NOT NULL CHECK(role IN ('source_image','prepared_image','source_audio','prepared_audio','source_video','playback_video','inference_frame','source_companion_audio','prepared_companion_audio')),
    role_index INTEGER NOT NULL CHECK(role_index BETWEEN 0 AND 4),
    content_type TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 1 AND 33554432),
    sha256 TEXT NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
    ready_at TIMESTAMPTZ,
    UNIQUE(scan_id,item_index,role,role_index),
    CHECK(object_id<>media_id AND object_id<>scan_id AND media_id<>scan_id)
);
CREATE INDEX ordinary_initial_evidence_objects_parent ON internal.ordinary_initial_evidence_objects(scan_id);
ALTER TABLE internal.ordinary_initial_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.ordinary_initial_evidence_objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.ordinary_initial_evidence,internal.ordinary_initial_evidence_objects FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.lock_ordinary_initial_evidence(p_owner UUID,p_request JSONB)
RETURNS internal.ordinary_initial_evidence LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE scan UUID; generation UUID; contract JSONB; job public.scan_ingestion_jobs; intent public.scan_ingestion_intents; saved internal.ordinary_initial_evidence;
BEGIN
    IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>1044480
        OR NOT(p_request ?& ARRAY['schema_version','scan_id','generation','evidence_digest','evidence_manifest'])
        OR p_request-ARRAY['schema_version','scan_id','generation','evidence_digest','evidence_manifest']<>'{}'
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR jsonb_typeof(p_request->'scan_id') IS DISTINCT FROM 'string'
        OR jsonb_typeof(p_request->'generation') IS DISTINCT FROM 'string'
        OR jsonb_typeof(p_request->'evidence_digest') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    contract:=internal.initial_evidence_contract(p_request->'evidence_manifest',p_request->>'scan_id',p_request->>'generation');
    IF p_request->>'evidence_digest' IS DISTINCT FROM contract->>'evidence_digest' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    scan:=(p_request->>'scan_id')::UUID; generation:=(p_request->>'generation')::UUID;
    IF p_owner IN (scan,generation) OR EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'items') x WHERE x->>'media_id'=p_owner::TEXT) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0));
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=scan AND (user_id<>p_owner OR is_tombstoned)) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=scan FOR UPDATE;
    IF FOUND THEN
        IF saved.owner_id<>p_owner OR saved.generation<>generation OR saved.evidence_digest<>p_request->>'evidence_digest'
            OR saved.evidence_manifest<>p_request->'evidence_manifest' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF saved.retired_at IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
        -- Sealed identity/receipts survive the transient ingestion ledger. No
        -- rollout check may strand recovery of already accepted byte evidence.
        IF saved.sealed_at IS NOT NULL THEN RETURN saved; END IF;
    END IF;
    SELECT * INTO job FROM public.scan_ingestion_jobs WHERE user_id=p_owner AND scan_id=scan::TEXT FOR UPDATE;
    IF NOT FOUND OR job.status IN ('complete','failed_terminal') THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    SELECT * INTO intent FROM public.scan_ingestion_intents WHERE user_id=p_owner AND scan_id=scan::TEXT FOR UPDATE;
    IF NOT FOUND OR intent.request_payload->'initialEvidence' IS DISTINCT FROM p_request
        OR intent.payload_checksum IS NULL THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF saved.scan_id IS NOT NULL THEN
        IF saved.job_id<>job.id OR saved.payload_checksum<>intent.payload_checksum THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN saved;
    END IF;
    IF (SELECT ordinary_initial_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.ordinary_initial_evidence(scan_id,owner_id,generation,job_id,payload_checksum,evidence_digest,evidence_manifest)
        VALUES(scan,p_owner,generation,job.id,intent.payload_checksum,p_request->>'evidence_digest',p_request->'evidence_manifest') RETURNING * INTO saved;
    RETURN saved;
END;
$$;

CREATE FUNCTION internal.ordinary_initial_evidence_receipt(p_saved internal.ordinary_initial_evidence)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('schema_version',1,'owner_id',p_saved.owner_id,'scan_id',p_saved.scan_id,'generation',p_saved.generation,
    'evidence_digest',p_saved.evidence_digest,'items',COALESCE((
        SELECT jsonb_agg(x.value||jsonb_build_object('object_id',o.object_id,'ready',o.ready_at IS NOT NULL) ORDER BY x.ordinality)
        FROM jsonb_array_elements(internal.initial_evidence_contract(p_saved.evidence_manifest,p_saved.scan_id::TEXT,p_saved.generation::TEXT)->'items') WITH ORDINALITY x
        JOIN internal.ordinary_initial_evidence_objects o ON o.scan_id=p_saved.scan_id AND o.media_id=(x.value->>'media_id')::UUID
    ),'[]'::JSONB));
$$;

CREATE FUNCTION internal.reserve_ordinary_initial_evidence(p_owner UUID,p_request JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; item JSONB; candidate UUID; receipt JSONB;
BEGIN
    saved:=internal.lock_ordinary_initial_evidence(p_owner,p_request);
    IF saved.allocated_at IS NOT NULL THEN
        receipt:=internal.ordinary_initial_evidence_receipt(saved);
        IF jsonb_array_length(receipt->'items')<>jsonb_array_length(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items') THEN
            RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
        END IF;
        RETURN receipt;
    END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items') LOOP
        IF EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence_objects WHERE scan_id=saved.scan_id AND media_id=(item->>'media_id')::UUID) THEN CONTINUE; END IF;
        -- A missing receipt after sealing is lost evidence, never authority to
        -- allocate a replacement object for the accepted operation.
        IF saved.sealed_at IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
        FOR attempt IN 1..4 LOOP
            candidate:=gen_random_uuid();
            PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-object:'||candidate::TEXT,0));
            EXIT WHEN candidate NOT IN (saved.owner_id,saved.scan_id,saved.generation)
                AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items') x WHERE x->>'media_id'=candidate::TEXT)
                AND NOT EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence_objects WHERE object_id=candidate)
                AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=candidate)
                AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=candidate);
            IF attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
        END LOOP;
        INSERT INTO internal.ordinary_initial_evidence_objects(object_id,scan_id,media_id,item_index,role,role_index,content_type,byte_count,sha256)
            VALUES(candidate,saved.scan_id,(item->>'media_id')::UUID,(item->>'item_index')::INTEGER,item->>'role',(item->>'role_index')::INTEGER,item->>'content_type',(item->>'byte_count')::INTEGER,item->>'sha256');
    END LOOP;
    UPDATE internal.ordinary_initial_evidence SET allocated_at=clock_timestamp() WHERE scan_id=saved.scan_id RETURNING * INTO saved;
    receipt:=internal.ordinary_initial_evidence_receipt(saved);
    RETURN receipt;
END;
$$;

-- Only trusted storage orchestration may acknowledge after actual readback.
CREATE FUNCTION internal.complete_ordinary_initial_evidence(p_owner UUID,p_request JSONB,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence;
BEGIN
    saved:=internal.lock_ordinary_initial_evidence(p_owner,p_request);
    UPDATE internal.ordinary_initial_evidence_objects SET ready_at=COALESCE(ready_at,clock_timestamp())
        WHERE scan_id=saved.scan_id AND object_id=p_object;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    RETURN internal.ordinary_initial_evidence_receipt(saved);
END;
$$;

-- Private erasure markers survive both account and scan cascades. The existing
-- worker owns physical erasure/ack; no second storage cleanup dispatcher.
CREATE FUNCTION internal.erase_ordinary_initial_evidence_object()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    INSERT INTO internal.observation_evidence_erasure(object_id) VALUES(OLD.object_id) ON CONFLICT DO NOTHING;
    RETURN OLD;
END;
$$;
CREATE TRIGGER erase_ordinary_initial_evidence_object BEFORE DELETE ON internal.ordinary_initial_evidence_objects
    FOR EACH ROW EXECUTE FUNCTION internal.erase_ordinary_initial_evidence_object();
CREATE FUNCTION internal.fence_ordinary_initial_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.ordinary_initial_evidence WHERE scan_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER fence_ordinary_initial_evidence AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.fence_ordinary_initial_evidence();

CREATE FUNCTION internal.guard_ordinary_initial_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF to_jsonb(NEW)-ARRAY['allocated_at','retired_at','sealed_at','result_snapshot','completion_response']
        IS DISTINCT FROM to_jsonb(OLD)-ARRAY['allocated_at','retired_at','sealed_at','result_snapshot','completion_response']
        OR (OLD.allocated_at IS NOT NULL AND NEW.allocated_at IS DISTINCT FROM OLD.allocated_at)
        OR (OLD.retired_at IS NOT NULL AND NEW.retired_at IS DISTINCT FROM OLD.retired_at)
        OR (NEW.retired_at IS NOT NULL AND NEW.sealed_at IS NOT NULL)
        OR (OLD.sealed_at IS NOT NULL AND (NEW.sealed_at IS DISTINCT FROM OLD.sealed_at
            OR NEW.result_snapshot IS DISTINCT FROM OLD.result_snapshot OR NEW.completion_response IS DISTINCT FROM OLD.completion_response))
        OR (NEW.sealed_at IS NOT NULL AND NEW.allocated_at IS NULL) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_ordinary_initial_evidence BEFORE UPDATE ON internal.ordinary_initial_evidence
    FOR EACH ROW EXECUTE FUNCTION internal.guard_ordinary_initial_evidence();
CREATE FUNCTION internal.guard_ordinary_initial_evidence_object()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.ordinary_initial_evidence; expected JSONB;
BEGIN
    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=NEW.scan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT x INTO expected FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items') x
        WHERE x->>'media_id'=NEW.media_id::TEXT;
    IF expected IS NULL OR expected IS DISTINCT FROM to_jsonb(NEW)-ARRAY['object_id','scan_id','ready_at']
        OR NEW.object_id IN (saved.owner_id,saved.scan_id,saved.generation)
        OR EXISTS(SELECT 1 FROM jsonb_array_elements(internal.initial_evidence_contract(saved.evidence_manifest,saved.scan_id::TEXT,saved.generation::TEXT)->'items') x WHERE x->>'media_id'=NEW.object_id::TEXT)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=NEW.object_id)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=NEW.object_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF TG_OP='INSERT' THEN
        IF saved.allocated_at IS NOT NULL OR saved.sealed_at IS NOT NULL OR NEW.ready_at IS NOT NULL THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    ELSIF to_jsonb(NEW)-'ready_at' IS DISTINCT FROM to_jsonb(OLD)-'ready_at'
        OR (OLD.ready_at IS NOT NULL AND NEW.ready_at IS DISTINCT FROM OLD.ready_at)
        OR (saved.sealed_at IS NOT NULL AND NEW.ready_at IS DISTINCT FROM OLD.ready_at) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_ordinary_initial_evidence_object BEFORE INSERT OR UPDATE ON internal.ordinary_initial_evidence_objects
    FOR EACH ROW EXECUTE FUNCTION internal.guard_ordinary_initial_evidence_object();

REVOKE ALL ON FUNCTION internal.lock_ordinary_initial_evidence(UUID,JSONB),
    internal.ordinary_initial_evidence_receipt(internal.ordinary_initial_evidence),
    internal.reserve_ordinary_initial_evidence(UUID,JSONB),
    internal.complete_ordinary_initial_evidence(UUID,JSONB,UUID),
    internal.erase_ordinary_initial_evidence_object(),internal.fence_ordinary_initial_evidence(),
    internal.guard_ordinary_initial_evidence(),internal.guard_ordinary_initial_evidence_object()
    FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- No API grants, production callers, enrollment or media append activation.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN media_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN media_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_evidence_objects (
    media_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    analysis_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    object_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL CHECK(content_type IN ('image/jpeg','image/png','image/heic','audio/mp4','video/mp4')),
    byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 1 AND 33554432),
    sha256 TEXT NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (clock_timestamp() + INTERVAL '5 minutes'),
    ready_at TIMESTAMPTZ,
    CHECK(analysis_id <> observation_id AND media_id <> observation_id AND media_id <> analysis_id),
    CHECK(object_id NOT IN (owner_id,observation_id,analysis_id,media_id))
);
CREATE INDEX observation_evidence_objects_parent ON internal.observation_evidence_objects(observation_id,analysis_id);
CREATE INDEX observation_evidence_objects_expiry ON internal.observation_evidence_objects(expires_at) WHERE ready_at IS NULL;

-- No FK: erasure obligations survive every parent/account cascade. Keys contain
-- only a random object UUID, never an owner/observation/analysis identifier.
CREATE TABLE internal.observation_evidence_erasure (
    object_id UUID PRIMARY KEY,
    available_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    erased_at TIMESTAMPTZ,
    CHECK((claim_token IS NULL) = (claim_expires_at IS NULL))
);
CREATE INDEX observation_evidence_erasure_pending ON internal.observation_evidence_erasure(available_at) WHERE erased_at IS NULL;
ALTER TABLE internal.observation_evidence_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_evidence_erasure ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_evidence_objects, internal.observation_evidence_erasure FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.lock_owned_observation_evidence(p_owner UUID,p_observation UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || p_observation::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_observation AND user_id=p_owner AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
END;
$$;

CREATE FUNCTION internal.reserve_observation_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_content_type TEXT,p_bytes INTEGER,p_sha256 TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects; candidate UUID;
BEGIN
    IF p_analysis IS NULL OR p_media IS NULL OR p_analysis=p_observation OR p_media IN (p_analysis,p_observation)
        OR p_content_type IS NULL OR p_content_type NOT IN ('image/jpeg','image/png','image/heic','audio/mp4','video/mp4')
        OR p_bytes IS NULL OR p_bytes NOT BETWEEN 1 AND 33554432 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=p_media;
    IF FOUND THEN
        IF saved.observation_id<>p_observation OR saved.analysis_id<>p_analysis OR saved.owner_id<>p_owner
            OR saved.content_type<>p_content_type OR saved.byte_count<>p_bytes OR saved.sha256<>p_sha256 THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF saved.ready_at IS NULL AND saved.expires_at<=clock_timestamp() THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        RETURN to_jsonb(saved);
    END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-evidence:' || p_analysis::TEXT,0::BIGINT));
    -- Analysis intents are not implemented yet. Bind only an unused analysis
    -- identity; the future admitted producer must prove intent ownership too.
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis AND observation_id<>p_observation)
        OR (SELECT count(*) FROM internal.observation_evidence_objects WHERE observation_id=p_observation AND analysis_id=p_analysis)>=64 THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- Never reuse an opaque key retained by an erasure marker. The bounded
    -- allocator also serializes the exceedingly rare random-ID collision.
    FOR attempt IN 1..4 LOOP
        candidate := gen_random_uuid();
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-object:' || candidate::TEXT,0::BIGINT));
        EXIT WHEN candidate NOT IN (p_owner,p_observation,p_analysis,p_media)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=candidate)
            AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=candidate);
        IF attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    END LOOP;
    INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,content_type,byte_count,sha256,object_id)
    VALUES(p_media,p_observation,p_analysis,p_owner,p_content_type,p_bytes,p_sha256,candidate) RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;

-- Runs alphabetically AFTER guard_observation_analysis_generation, which owns
-- owner/generation locks. Description-only append must not race a reservation
-- for the same analysis, even when a malformed producer names another parent.
CREATE FUNCTION internal.guard_observation_media_binding()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation_media_binding BEFORE INSERT ON internal.observation_analysis_results
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_media_binding();
REVOKE ALL ON FUNCTION internal.guard_observation_media_binding() FROM PUBLIC, anon, authenticated, service_role;

-- Only trusted storage orchestration may call this after verifying the exact
-- write-once object's digest/size/type. It is not a client assertion of upload.
CREATE FUNCTION internal.complete_observation_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_object UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects
        WHERE media_id=p_media AND observation_id=p_observation AND analysis_id=p_analysis AND owner_id=p_owner AND object_id=p_object FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF saved.ready_at IS NULL THEN
        IF saved.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
        UPDATE internal.observation_evidence_objects SET ready_at=clock_timestamp() WHERE media_id=p_media RETURNING * INTO saved;
    END IF;
    RETURN to_jsonb(saved);
END;
$$;

CREATE FUNCTION internal.read_owned_observation_evidence(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT media_reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_evidence_objects
        WHERE media_id=p_media AND observation_id=p_observation AND analysis_id=p_analysis AND owner_id=p_owner AND ready_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    RETURN to_jsonb(saved);
END;
$$;

CREATE FUNCTION internal.guard_observation_evidence_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF (to_jsonb(NEW)-'ready_at') IS DISTINCT FROM (to_jsonb(OLD)-'ready_at')
        OR OLD.ready_at IS NOT NULL OR NEW.ready_at IS NULL THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation_evidence_update BEFORE UPDATE ON internal.observation_evidence_objects
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_evidence_update();

CREATE FUNCTION internal.enqueue_observation_evidence_erasure()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    INSERT INTO internal.observation_evidence_erasure(object_id) VALUES(OLD.object_id) ON CONFLICT DO NOTHING;
    RETURN OLD;
END;
$$;
CREATE TRIGGER enqueue_observation_evidence_erasure BEFORE DELETE ON internal.observation_evidence_objects
FOR EACH ROW EXECUTE FUNCTION internal.enqueue_observation_evidence_erasure();

CREATE FUNCTION internal.fence_observation_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    -- The tombstone writer already owns the canonical owner/generation locks.
    DELETE FROM internal.observation_evidence_objects WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER fence_observation_evidence AFTER INSERT ON internal.scan_deletion_tombstones
FOR EACH ROW EXECUTE FUNCTION internal.fence_observation_evidence();

-- Expiry takes the SAME owner/generation order as readiness. Delete only the
-- still-expired, still-unready row after locking, never a concurrently ready one.
CREATE FUNCTION internal.expire_observation_evidence(p_media UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_objects;
BEGIN
    SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=p_media;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    PERFORM id FROM public.users WHERE id=saved.owner_id FOR UPDATE;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || saved.observation_id::TEXT,0::BIGINT));
    DELETE FROM internal.observation_evidence_objects WHERE media_id=p_media AND ready_at IS NULL AND expires_at<=clock_timestamp();
    RETURN FOUND;
END;
$$;

CREATE FUNCTION internal.claim_observation_evidence_erasure()
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_evidence_erasure;
BEGIN
    SELECT * INTO saved FROM internal.observation_evidence_erasure
        WHERE erased_at IS NULL AND available_at<=clock_timestamp()
        AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp())
        ORDER BY available_at,object_id FOR UPDATE SKIP LOCKED LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE internal.observation_evidence_erasure SET claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+INTERVAL '1 minute'
        WHERE object_id=saved.object_id RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;

-- Acknowledgment means an unconditional zero-byte erasure marker was PUT, NOT
-- DELETE/404. Keep that marker forever: future If-None-Match uploads must fail.
CREATE FUNCTION internal.finish_observation_evidence_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    IF p_success IS NULL THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    UPDATE internal.observation_evidence_erasure
    SET erased_at=CASE WHEN p_success THEN clock_timestamp() ELSE NULL END,
        available_at=clock_timestamp()+INTERVAL '1 minute',claim_token=NULL,claim_expires_at=NULL
    WHERE object_id=p_object AND claim_token=p_claim AND claim_expires_at>clock_timestamp() AND erased_at IS NULL;
    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION internal.lock_owned_observation_evidence(UUID,UUID),
    internal.reserve_observation_evidence(UUID,UUID,UUID,UUID,TEXT,INTEGER,TEXT),
    internal.complete_observation_evidence(UUID,UUID,UUID,UUID,UUID),
    internal.read_owned_observation_evidence(UUID,UUID,UUID,UUID),
    internal.guard_observation_evidence_update(), internal.enqueue_observation_evidence_erasure(),
    internal.fence_observation_evidence(), internal.expire_observation_evidence(UUID),
    internal.claim_observation_evidence_erasure(),internal.finish_observation_evidence_erasure(UUID,UUID,BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;

RESET lock_timeout;
RESET statement_timeout;

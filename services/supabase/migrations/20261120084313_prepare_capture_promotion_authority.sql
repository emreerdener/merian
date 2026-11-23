SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Prepared authority only: no route, storage signer, worker schedule or finalizer
-- is installed. No FK cascade may erase an issued destination-write obligation.
CREATE TABLE internal.capture_promotion_operations (
    operation_id UUID PRIMARY KEY,
    owner_id UUID NOT NULL,
    scan_id UUID NOT NULL,
    asset_id UUID NOT NULL,
    session_id UUID NOT NULL,
    backend_sha256 TEXT NOT NULL CHECK (backend_sha256 ~ '^[0-9a-f]{64}$'),
    source_key TEXT NOT NULL,
    destination_key TEXT NOT NULL,
    content_type TEXT NOT NULL,
    byte_count INTEGER NOT NULL,
    sha256 TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    write_authorized_at TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    observed_absent_at TIMESTAMPTZ,
    next_check_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    claim_token UUID,
    lease_expires_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 1000000),
    last_error_code TEXT CHECK (last_error_code IN ('object_io_failed','backend_unavailable')),
    UNIQUE (backend_sha256, source_key),
    UNIQUE (backend_sha256, destination_key),
    CHECK (source_key ~ ('^staging/' || owner_id::TEXT || '/[A-Za-z0-9_.-]{1,255}$')),
    CHECK (destination_key IN ('public_uploads/free/' || owner_id::TEXT || '/capture-promotion-' || operation_id::TEXT,
                              'public_uploads/pro/' || owner_id::TEXT || '/capture-promotion-' || operation_id::TEXT)),
    CHECK (byte_count > 0 AND CASE
        WHEN content_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif') THEN byte_count <= 5242880
        WHEN content_type = 'audio/wav' THEN byte_count <= 2700000
        WHEN content_type = 'video/mp4' THEN byte_count <= 12582912 ELSE FALSE END),
    CHECK ((claim_token IS NULL) = (lease_expires_at IS NULL)),
    CHECK (retired_at IS NOT NULL OR (claim_token IS NULL AND observed_absent_at IS NULL))
);
ALTER TABLE internal.capture_promotion_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_promotion_operations FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX capture_promotion_owner_idx ON internal.capture_promotion_operations(owner_id);
CREATE INDEX capture_promotion_scan_idx ON internal.capture_promotion_operations(scan_id);
CREATE INDEX capture_promotion_retirement_idx ON internal.capture_promotion_operations(next_check_at, operation_id)
    WHERE retired_at IS NOT NULL;
COMMENT ON TABLE internal.capture_promotion_operations IS
    'Prepared immutable exact-content promotion reservation and independent permanent destination erasure obligation. No source bytes, signed URLs, credentials, completed/GC transition, finalization or publication authority.';

CREATE FUNCTION internal.parse_capture_promotion_binding(p JSONB)
RETURNS internal.capture_promotion_operations LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; k TEXT;
BEGIN
    IF p IS NULL OR pg_catalog.jsonb_typeof(p) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
    END IF;
    IF pg_catalog.octet_length(p::TEXT) > 4096 OR (SELECT count(*) FROM pg_catalog.jsonb_object_keys(p)) <> 11
        OR NOT p ?& ARRAY['operationId','ownerId','scanId','assetId','sessionId','backendSHA256','sourceKey','destinationKey','contentType','byteCount','sha256'] THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
    END IF;
    FOR k IN SELECT pg_catalog.jsonb_object_keys(p) LOOP
        IF k <> 'byteCount' AND pg_catalog.jsonb_typeof(p->k) IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    FOREACH k IN ARRAY ARRAY['operationId','ownerId','scanId','assetId','sessionId'] LOOP
        IF p->>k !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    IF pg_catalog.jsonb_typeof(p->'byteCount') IS DISTINCT FROM 'number'
        OR p->>'byteCount' !~ '^[1-9][0-9]{0,7}$' OR p->>'backendSHA256' !~ '^[0-9a-f]{64}$'
        OR p->>'sha256' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
    END IF;
    b.operation_id := (p->>'operationId')::UUID; b.owner_id := (p->>'ownerId')::UUID;
    b.scan_id := (p->>'scanId')::UUID; b.asset_id := (p->>'assetId')::UUID;
    b.session_id := (p->>'sessionId')::UUID; b.backend_sha256 := p->>'backendSHA256';
    b.source_key := p->>'sourceKey'; b.destination_key := p->>'destinationKey';
    b.content_type := p->>'contentType'; b.byte_count := (p->>'byteCount')::INTEGER; b.sha256 := p->>'sha256';
    IF b.source_key !~ ('^staging/' || b.owner_id::TEXT || '/[A-Za-z0-9_.-]{1,255}$')
        OR b.destination_key NOT IN ('public_uploads/free/' || b.owner_id::TEXT || '/capture-promotion-' || b.operation_id::TEXT,
                                    'public_uploads/pro/' || b.owner_id::TEXT || '/capture-promotion-' || b.operation_id::TEXT)
        OR NOT (CASE WHEN b.content_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif') THEN b.byte_count <= 5242880
            WHEN b.content_type = 'audio/wav' THEN b.byte_count <= 2700000
            WHEN b.content_type = 'video/mp4' THEN b.byte_count <= 12582912 ELSE FALSE END) THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE = '22023';
    END IF;
    RETURN b;
END;
$$;

CREATE FUNCTION internal.capture_promotion_binding(b internal.capture_promotion_operations)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path = '' AS $$
    SELECT pg_catalog.jsonb_build_object('operationId',b.operation_id,'ownerId',b.owner_id,'scanId',b.scan_id,
        'assetId',b.asset_id,'sessionId',b.session_id,'backendSHA256',b.backend_sha256,'sourceKey',b.source_key,
        'destinationKey',b.destination_key,'contentType',b.content_type,'byteCount',b.byte_count,'sha256',b.sha256);
$$;

-- Never lock an ingestion/account job after users: their terminal owners have
-- separate lock orders. Match issuance's account -> user -> scan -> asset ->
-- source order. No lock survives the RPC or covers external storage I/O.
CREATE FUNCTION internal.lock_capture_promotion_source(b internal.capture_promotion_operations)
RETURNS VOID LANGUAGE PLPGSQL SET search_path = '' AS $$
DECLARE asset public.scan_media_assets%ROWTYPE; source internal.capture_object_authorities%ROWTYPE;
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:' || b.owner_id::TEXT,0));
    PERFORM id FROM public.users WHERE id=b.owner_id FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=b.owner_id) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || b.scan_id::TEXT,0));
    IF EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=b.scan_id) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO asset FROM public.scan_media_assets WHERE id=b.asset_id FOR UPDATE;
    IF NOT FOUND OR asset.user_id IS DISTINCT FROM b.owner_id OR asset.client_scan_id IS DISTINCT FROM b.scan_id
        OR asset.upload_session_id IS DISTINCT FROM b.session_id OR asset.source <> 'capture_upload'
        OR asset.storage_key IS DISTINCT FROM b.source_key OR asset.status <> 'staged'
        OR asset.content_type IS DISTINCT FROM b.content_type OR asset.byte_size IS DISTINCT FROM b.byte_count
        OR pg_catalog.lower(asset.checksum_sha256) IS DISTINCT FROM b.sha256
        OR asset.kind IS DISTINCT FROM (CASE WHEN b.content_type LIKE 'image/%' THEN 'image'
            WHEN b.content_type = 'audio/wav' THEN 'audio' ELSE 'video' END) THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO source FROM internal.capture_object_authorities
        WHERE backend_sha256=b.backend_sha256 AND object_key=b.source_key FOR UPDATE;
    IF NOT FOUND OR source.retired_at IS NOT NULL OR source.owner_id IS DISTINCT FROM b.owner_id
        OR source.scan_id IS DISTINCT FROM b.scan_id OR source.asset_id IS DISTINCT FROM b.asset_id
        OR source.session_id IS DISTINCT FROM b.session_id THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
END;
$$;

CREATE FUNCTION public.register_capture_promotion_operation(p_binding JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; saved internal.capture_promotion_operations%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    b := internal.parse_capture_promotion_binding(p_binding);
    PERFORM internal.lock_capture_promotion_source(b);
    SELECT * INTO saved FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id FOR UPDATE;
    IF FOUND THEN
        IF saved.retired_at IS NOT NULL OR internal.capture_promotion_binding(saved) IS DISTINCT FROM p_binding THEN
            RAISE EXCEPTION 'capture_promotion_conflict' USING ERRCODE='55000';
        END IF;
        RETURN TRUE;
    END IF;
    -- Source uniqueness retains uncertainty; a replacement ID is not a retry.
    INSERT INTO internal.capture_promotion_operations(operation_id,owner_id,scan_id,asset_id,session_id,
        backend_sha256,source_key,destination_key,content_type,byte_count,sha256)
    VALUES(b.operation_id,b.owner_id,b.scan_id,b.asset_id,b.session_id,b.backend_sha256,b.source_key,
        b.destination_key,b.content_type,b.byte_count,b.sha256);
    RETURN TRUE;
END;
$$;

CREATE FUNCTION public.authorize_capture_promotion_action(p_binding JSONB,p_action TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; saved internal.capture_promotion_operations%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_action IS NULL OR p_action NOT IN ('read_source','write_destination','read_destination') THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE='22023';
    END IF;
    b := internal.parse_capture_promotion_binding(p_binding);
    PERFORM internal.lock_capture_promotion_source(b);
    SELECT * INTO saved FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id FOR UPDATE;
    IF NOT FOUND OR saved.retired_at IS NOT NULL OR internal.capture_promotion_binding(saved) IS DISTINCT FROM p_binding THEN
        RAISE EXCEPTION 'capture_promotion_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_action='write_destination' THEN
        IF saved.write_authorized_at IS NOT NULL THEN RETURN FALSE; END IF;
        UPDATE internal.capture_promotion_operations SET write_authorized_at=pg_catalog.clock_timestamp() WHERE operation_id=b.operation_id;
        RETURN TRUE;
    END IF;
    IF p_action='read_source' THEN RETURN saved.write_authorized_at IS NULL; END IF;
    RETURN saved.write_authorized_at IS NOT NULL;
END;
$$;

-- All existing source retirement owners (scan, account, owner deletion, merge)
-- already update this row. Propagate in that same transaction without copying
-- or weakening their established trigger and no-reclassification contracts.
CREATE FUNCTION internal.retire_capture_promotions_for_source() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    UPDATE internal.capture_promotion_operations SET retired_at=COALESCE(retired_at,NEW.retired_at),
        next_check_at=least(next_check_at,pg_catalog.clock_timestamp())
        WHERE backend_sha256=NEW.backend_sha256 AND source_key=NEW.object_key;
    RETURN NEW;
END;
$$;
CREATE TRIGGER retire_capture_promotions_for_source AFTER UPDATE OF retired_at ON internal.capture_object_authorities
    FOR EACH ROW WHEN (NEW.retired_at IS NOT NULL) EXECUTE FUNCTION internal.retire_capture_promotions_for_source();

CREATE FUNCTION public.retire_capture_promotion_operation(p_binding JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE b internal.capture_promotion_operations%ROWTYPE; saved internal.capture_promotion_operations%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    b := internal.parse_capture_promotion_binding(p_binding);
    -- Exact abandonment remains possible after owner/asset deletion. It never
    -- authorizes source removal or changes source upload capability lifetime.
    SELECT * INTO saved FROM internal.capture_promotion_operations WHERE operation_id=b.operation_id FOR UPDATE;
    IF NOT FOUND OR internal.capture_promotion_binding(saved) IS DISTINCT FROM p_binding THEN RETURN FALSE; END IF;
    UPDATE internal.capture_promotion_operations SET retired_at=COALESCE(retired_at,pg_catalog.clock_timestamp()),
        next_check_at=least(next_check_at,pg_catalog.clock_timestamp()) WHERE operation_id=b.operation_id;
    RETURN TRUE;
END;
$$;

CREATE FUNCTION public.claim_capture_promotion_retirements(p_token UUID,p_limit INTEGER)
RETURNS TABLE(operation_id UUID,backend_sha256 TEXT,object_key TEXT,owner_id UUID)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_token IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE='22023';
    END IF;
    RETURN QUERY WITH chosen AS (
        SELECT o.operation_id FROM internal.capture_promotion_operations o
        WHERE o.retired_at IS NOT NULL AND o.next_check_at <= pg_catalog.clock_timestamp()
            AND (o.claim_token IS NULL OR o.lease_expires_at <= pg_catalog.clock_timestamp())
        ORDER BY o.next_check_at,o.operation_id LIMIT p_limit FOR UPDATE SKIP LOCKED
    ) UPDATE internal.capture_promotion_operations o SET claim_token=p_token,
        lease_expires_at=pg_catalog.clock_timestamp()+interval '2 minutes',attempt_count=least(o.attempt_count+1,1000000)
        FROM chosen c WHERE o.operation_id=c.operation_id
        RETURNING o.operation_id,o.backend_sha256,o.destination_key,o.owner_id;
END;
$$;

CREATE FUNCTION public.observe_capture_promotion_retirement(p_operation UUID,p_token UUID,p_absent BOOLEAN,p_error TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_operation IS NULL OR p_token IS NULL OR p_absent IS NULL
        OR (p_absent AND p_error IS NOT NULL)
        OR (NOT p_absent AND (p_error IS NULL OR p_error NOT IN ('object_io_failed','backend_unavailable'))) THEN
        RAISE EXCEPTION 'capture_promotion_invalid' USING ERRCODE='22023';
    END IF;
    UPDATE internal.capture_promotion_operations SET observed_absent_at=CASE WHEN p_absent THEN pg_catalog.clock_timestamp() ELSE observed_absent_at END,
        last_error_code=p_error,claim_token=NULL,lease_expires_at=NULL,
        next_check_at=pg_catalog.clock_timestamp()+CASE WHEN p_absent THEN interval '1 hour' ELSE interval '5 minutes' END
        WHERE operation_id=p_operation AND claim_token=p_token AND retired_at IS NOT NULL AND lease_expires_at > pg_catalog.clock_timestamp();
    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION internal.parse_capture_promotion_binding(JSONB),
    internal.capture_promotion_binding(internal.capture_promotion_operations),
    internal.lock_capture_promotion_source(internal.capture_promotion_operations),
    internal.retire_capture_promotions_for_source() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.register_capture_promotion_operation(JSONB),public.authorize_capture_promotion_action(JSONB,TEXT),
    public.retire_capture_promotion_operation(JSONB),public.claim_capture_promotion_retirements(UUID,INTEGER),
    public.observe_capture_promotion_retirement(UUID,UUID,BOOLEAN,TEXT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_capture_promotion_operation(JSONB),public.authorize_capture_promotion_action(JSONB,TEXT),
    public.retire_capture_promotion_operation(JSONB),public.claim_capture_promotion_retirements(UUID,INTEGER),
    public.observe_capture_promotion_retirement(UUID,UUID,BOOLEAN,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.register_capture_promotion_operation(jsonb)','Prepared immutable exact-content operation and independent destination reservation before storage I/O.'),
    ('service_role','public.authorize_capture_promotion_action(jsonb,text)','Fresh full-binding and retirement check; one durable destination write authorization, never implicit retry.'),
    ('service_role','public.retire_capture_promotion_operation(jsonb)','Exact prepared target abandonment; preserves the independent source authority.'),
    ('service_role','public.claim_capture_promotion_retirements(uuid,integer)','Bounded permanent destination retirement claims, independent of source observations and cascades.'),
    ('service_role','public.observe_capture_promotion_retirement(uuid,uuid,boolean,text)','Point-in-time destination absence or error; never final physical-erasure completion.');
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Exact capture keys survive owner/scan/asset cascades. Neither an expired
-- worker lease nor a negative HEAD proves an issued PUT has stopped writing.
-- Consequently this registry has no completed/garbage-collect transition.
CREATE TABLE internal.capture_object_authorities (
    backend_sha256 TEXT NOT NULL CHECK (backend_sha256 ~ '^[0-9a-f]{64}$'),
    object_key TEXT NOT NULL CHECK (octet_length(object_key) BETWEEN 1 AND 512),
    owner_id UUID NOT NULL,
    scan_id UUID,
    asset_id UUID,
    session_id UUID,
    issued_until TIMESTAMPTZ NOT NULL,
    retired_at TIMESTAMPTZ,
    observed_absent_at TIMESTAMPTZ,
    next_check_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    claim_token UUID,
    lease_expires_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 1000000),
    last_error_code TEXT CHECK (last_error_code IN ('object_io_failed','backend_unavailable')),
    PRIMARY KEY (backend_sha256, object_key),
    CHECK ((scan_id IS NULL) = (asset_id IS NULL) AND (asset_id IS NULL) = (session_id IS NULL)),
    CHECK ((claim_token IS NULL) = (lease_expires_at IS NULL)),
    CHECK (object_key ~ ('^staging/' || owner_id::TEXT || '/[A-Za-z0-9_.-]{1,255}$')),
    CHECK (retired_at IS NOT NULL OR (claim_token IS NULL AND observed_absent_at IS NULL))
);
ALTER TABLE internal.capture_object_authorities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_object_authorities FROM PUBLIC, anon, authenticated, service_role;
CREATE INDEX capture_object_scan_idx ON internal.capture_object_authorities(scan_id) WHERE scan_id IS NOT NULL;
CREATE INDEX capture_object_owner_idx ON internal.capture_object_authorities(owner_id);
CREATE INDEX capture_object_recheck_idx ON internal.capture_object_authorities(next_check_at, backend_sha256, object_key)
    WHERE retired_at IS NOT NULL;
COMMENT ON TABLE internal.capture_object_authorities IS
    'Private exact staging-key authority and permanent no-rebind fence. Retained for unresolved late-write erasure; negative observations never certify final physical erasure. No source content, credentials or signed URLs.';

CREATE FUNCTION public.register_capture_upload_capabilities(p_owner UUID, p_backend TEXT, p_objects JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE item JSONB; asset public.scan_media_assets%ROWTYPE; saved internal.capture_object_authorities%ROWTYPE;
    key TEXT; expiry TIMESTAMPTZ; scan UUID; asset_id UUID; session_id UUID; at_time TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_backend IS NULL OR p_backend !~ '^[0-9a-f]{64}$'
        OR p_objects IS NULL OR jsonb_typeof(p_objects) <> 'array' THEN
        RAISE EXCEPTION 'capture_capability_invalid' USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_objects) NOT BETWEEN 1 AND 8 OR octet_length(p_objects::TEXT) > 16384 THEN
        RAISE EXCEPTION 'capture_capability_invalid' USING ERRCODE = '22023';
    END IF;
    PERFORM id FROM public.users WHERE id = p_owner FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM internal.account_deletion_jobs WHERE user_id = p_owner) THEN
        RAISE EXCEPTION 'capture_owner_unavailable' USING ERRCODE = '55000';
    END IF;
    -- Acquire every scan lock in a stable order before asset/object locks.
    FOR scan IN SELECT DISTINCT (value->>'scan_id')::UUID FROM jsonb_array_elements(p_objects)
        WHERE value->>'scan_id' IS NOT NULL ORDER BY 1 LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:' || scan::TEXT, 0));
        IF EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = scan) THEN
            RAISE EXCEPTION 'scan_generation_deleted' USING ERRCODE = '55000';
        END IF;
    END LOOP;
    at_time := clock_timestamp();
    FOR item IN SELECT value FROM jsonb_array_elements(p_objects) ORDER BY value->>'object_key' LOOP
        IF jsonb_typeof(item) <> 'object' OR (SELECT count(*) FROM jsonb_object_keys(item)) <> 5
            OR NOT item ?& ARRAY['object_key','expires_at','scan_id','asset_id','session_id']
            OR jsonb_typeof(item->'object_key') <> 'string' OR jsonb_typeof(item->'expires_at') <> 'string' THEN
            RAISE EXCEPTION 'capture_capability_invalid' USING ERRCODE = '22023';
        END IF;
        key := item->>'object_key'; expiry := (item->>'expires_at')::TIMESTAMPTZ;
        scan := (item->>'scan_id')::UUID; asset_id := (item->>'asset_id')::UUID; session_id := (item->>'session_id')::UUID;
        IF key !~ ('^staging/' || p_owner::TEXT || '/[A-Za-z0-9_.-]{1,255}$')
            OR expiry <= at_time OR expiry > at_time + interval '24 hours 5 minutes'
            OR (scan IS NULL) <> (asset_id IS NULL) OR (asset_id IS NULL) <> (session_id IS NULL)
            OR (SELECT count(*) FROM jsonb_array_elements(p_objects) entry WHERE entry->>'object_key' = key) <> 1 THEN
            RAISE EXCEPTION 'capture_capability_invalid' USING ERRCODE = '22023';
        END IF;
        IF asset_id IS NOT NULL THEN
            SELECT * INTO asset FROM public.scan_media_assets WHERE id = asset_id FOR UPDATE;
            IF NOT FOUND OR asset.user_id IS DISTINCT FROM p_owner OR asset.client_scan_id IS DISTINCT FROM scan
                OR asset.upload_session_id IS DISTINCT FROM session_id OR asset.storage_key IS DISTINCT FROM key
                OR asset.source <> 'capture_upload' OR asset.status <> 'staged' THEN
                RAISE EXCEPTION 'capture_capability_binding_conflict' USING ERRCODE = '55000';
            END IF;
        END IF;
        SELECT * INTO saved FROM internal.capture_object_authorities
            WHERE backend_sha256 = p_backend AND object_key = key FOR UPDATE;
        IF FOUND THEN
            IF saved.retired_at IS NOT NULL OR saved.owner_id <> p_owner OR saved.scan_id IS DISTINCT FROM scan
                OR saved.asset_id IS DISTINCT FROM asset_id OR saved.session_id IS DISTINCT FROM session_id THEN
                RAISE EXCEPTION 'capture_object_retired_or_rebound' USING ERRCODE = '55000';
            END IF;
            UPDATE internal.capture_object_authorities SET issued_until = greatest(issued_until, expiry)
                WHERE backend_sha256 = p_backend AND object_key = key;
        ELSE
            INSERT INTO internal.capture_object_authorities(backend_sha256, object_key, owner_id, scan_id, asset_id, session_id, issued_until)
                VALUES(p_backend, key, p_owner, scan, asset_id, session_id, expiry);
        END IF;
    END LOOP;
    RETURN TRUE;
END;
$$;

-- Deletion fences and the registry survive independently. Registration uses
-- the same owner/scan serialization as the existing deletion request owner.
CREATE FUNCTION internal.retire_capture_objects_for_scan() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    UPDATE internal.capture_object_authorities SET retired_at = COALESCE(retired_at, clock_timestamp()),
        next_check_at = least(next_check_at, clock_timestamp()) WHERE scan_id = NEW.scan_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER retire_capture_objects_for_scan AFTER INSERT ON internal.scan_deletion_tombstones
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_objects_for_scan();

CREATE FUNCTION internal.retire_capture_objects_for_owner() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
DECLARE target UUID;
BEGIN
    IF TG_TABLE_NAME = 'users' THEN target := OLD.id; ELSE target := NEW.user_id; END IF;
    UPDATE internal.capture_object_authorities SET retired_at = COALESCE(retired_at, clock_timestamp()),
        next_check_at = least(next_check_at, clock_timestamp()) WHERE owner_id = target;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER retire_capture_objects_for_account AFTER INSERT ON internal.account_deletion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_objects_for_owner();
CREATE TRIGGER retire_capture_objects_before_owner_delete BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION internal.retire_capture_objects_for_owner();

-- A caller cannot sidestep registration by binding an already fenced key to
-- another scan/asset. This trigger never grants authority to use an object.
CREATE FUNCTION internal.reject_rebound_capture_object() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NEW.source = 'capture_upload' AND EXISTS (
        SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = NEW.storage_key
            AND (a.retired_at IS NOT NULL OR a.owner_id IS DISTINCT FROM NEW.user_id
                OR a.scan_id IS DISTINCT FROM NEW.client_scan_id OR a.asset_id IS DISTINCT FROM NEW.id
                OR a.session_id IS DISTINCT FROM NEW.upload_session_id)
    ) THEN RAISE EXCEPTION 'capture_object_retired_or_rebound' USING ERRCODE = '55000'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER reject_rebound_capture_object BEFORE INSERT OR UPDATE ON public.scan_media_assets
    FOR EACH ROW EXECUTE FUNCTION internal.reject_rebound_capture_object();

CREATE FUNCTION public.claim_capture_object_retirements(p_token UUID, p_limit INTEGER)
RETURNS TABLE(backend_sha256 TEXT, object_key TEXT, owner_id UUID, issued_until TIMESTAMPTZ)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_token IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
        RAISE EXCEPTION 'capture_retirement_invalid' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY WITH selected AS (
        SELECT a.backend_sha256, a.object_key FROM internal.capture_object_authorities a
        WHERE a.retired_at IS NOT NULL AND a.next_check_at <= clock_timestamp()
            AND (a.claim_token IS NULL OR a.lease_expires_at <= clock_timestamp())
        ORDER BY a.next_check_at, a.backend_sha256, a.object_key LIMIT p_limit FOR UPDATE SKIP LOCKED
    ) UPDATE internal.capture_object_authorities a SET claim_token = p_token,
        lease_expires_at = clock_timestamp() + interval '2 minutes', attempt_count = least(a.attempt_count + 1, 1000000)
        FROM selected s WHERE a.backend_sha256 = s.backend_sha256 AND a.object_key = s.object_key
        RETURNING a.backend_sha256, a.object_key, a.owner_id, a.issued_until;
END;
$$;

CREATE FUNCTION public.observe_capture_object_retirement(p_backend TEXT, p_key TEXT, p_token UUID, p_absent BOOLEAN, p_error TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_absent IS NULL OR (p_absent AND p_error IS NOT NULL) OR (NOT p_absent AND p_error IS NULL)
        OR p_error NOT IN ('object_io_failed','backend_unavailable') THEN
        RAISE EXCEPTION 'capture_retirement_invalid' USING ERRCODE = '22023';
    END IF;
    UPDATE internal.capture_object_authorities SET
        observed_absent_at = CASE WHEN p_absent THEN clock_timestamp() ELSE observed_absent_at END,
        last_error_code = p_error, claim_token = NULL, lease_expires_at = NULL,
        next_check_at = CASE WHEN p_absent THEN greatest(clock_timestamp() + interval '1 hour', issued_until + interval '1 minute')
            ELSE clock_timestamp() + interval '5 minutes' END
    WHERE backend_sha256 = p_backend AND object_key = p_key AND claim_token = p_token
        AND lease_expires_at > clock_timestamp() AND retired_at IS NOT NULL;
    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION internal.retire_capture_objects_for_scan(), internal.retire_capture_objects_for_owner(),
    internal.reject_rebound_capture_object() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.register_capture_upload_capabilities(UUID,TEXT,JSONB),
    public.claim_capture_object_retirements(UUID,INTEGER), public.observe_capture_object_retirement(TEXT,TEXT,UUID,BOOLEAN,TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_capture_upload_capabilities(UUID,TEXT,JSONB),
    public.claim_capture_object_retirements(UUID,INTEGER), public.observe_capture_object_retirement(TEXT,TEXT,UUID,BOOLEAN,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.register_capture_upload_capabilities(uuid,text,jsonb)','Persist exact signed staging capability before URL return; reject owner/scan deletion or key rebinding.'),
    ('service_role','public.claim_capture_object_retirements(uuid,integer)','Bounded leased work on permanently retired exact staging keys, independent of scan/account cascades.'),
    ('service_role','public.observe_capture_object_retirement(text,text,uuid,boolean,text)','Record point-in-time absence or retry error without erasing late-write obligations or no-rebind fences.');

RESET statement_timeout;
RESET lock_timeout;

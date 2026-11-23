SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Account completion already locks job then owner. Use a distinct intake fence
-- shared only with signing, avoiding an owner -> job inversion on intake retry.
DROP TRIGGER lock_capture_owner_before_account_retirement ON internal.account_deletion_jobs;
DROP FUNCTION internal.lock_capture_owner_before_account_retirement();
CREATE FUNCTION internal.serialize_capture_account_retirement() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NEW.user_id IS NOT NULL THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:' || NEW.user_id::TEXT, 0));
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.serialize_capture_account_retirement() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER serialize_capture_account_retirement BEFORE INSERT ON internal.account_deletion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.serialize_capture_account_retirement();

CREATE OR REPLACE FUNCTION public.register_capture_upload_capabilities(p_owner UUID, p_backend TEXT, p_objects JSONB)
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
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:' || p_owner::TEXT, 0));
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

RESET statement_timeout;
RESET lock_timeout;

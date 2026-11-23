SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Only the existing private account-merge reparent boundary may move metadata
-- backed by an active old-owner staging capability. API roles cannot mint this
-- transaction-local authority, and successful reparenting retires that capability.
CREATE TABLE internal.capture_reparent_transactions (
    transaction_id xid8 PRIMARY KEY,
    source_owner UUID NOT NULL,
    target_owner UUID NOT NULL,
    CHECK (source_owner <> target_owner)
);
ALTER TABLE internal.capture_reparent_transactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.capture_reparent_transactions FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION internal.reparent_ghost_user_foreign_keys(UUID, UUID)
    RENAME TO reparent_ghost_user_foreign_keys_capture_base;
CREATE FUNCTION internal.reparent_ghost_user_foreign_keys(p_ghost_user_id UUID, p_target_user_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '25s' AS $$
BEGIN
    INSERT INTO internal.capture_reparent_transactions(transaction_id, source_owner, target_owner)
        VALUES (pg_catalog.pg_current_xact_id(), p_ghost_user_id, p_target_user_id);
    PERFORM internal.reparent_ghost_user_foreign_keys_capture_base(p_ghost_user_id, p_target_user_id);
    UPDATE internal.capture_object_authorities a
        SET retired_at = COALESCE(a.retired_at, clock_timestamp()),
            next_check_at = least(a.next_check_at, clock_timestamp())
        WHERE a.owner_id = p_ghost_user_id AND EXISTS (
            SELECT 1 FROM public.scan_media_assets m WHERE m.id = a.asset_id
                AND m.user_id = p_target_user_id AND m.client_scan_id = a.scan_id
                AND m.upload_session_id = a.session_id AND m.storage_key = a.object_key
                AND m.source = 'capture_upload'
        );
    DELETE FROM internal.capture_reparent_transactions WHERE transaction_id = pg_catalog.pg_current_xact_id();
    -- An exception rolls back both the marker and all metadata/authority writes.
END;
$$;
REVOKE ALL ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID,UUID),
    internal.reparent_ghost_user_foreign_keys_capture_base(UUID,UUID) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.reject_rebound_capture_object() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id
        AND OLD.source = 'capture_upload'
        AND (to_jsonb(NEW) - ARRAY['user_id','updated_at']) = (to_jsonb(OLD) - ARRAY['user_id','updated_at'])
        AND EXISTS (SELECT 1 FROM internal.capture_reparent_transactions t
            WHERE t.transaction_id = pg_catalog.pg_current_xact_id()
                AND t.source_owner = OLD.user_id AND t.target_owner = NEW.user_id)
        AND EXISTS (SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = OLD.storage_key)
        AND NOT EXISTS (SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = OLD.storage_key
            AND (a.retired_at IS NOT NULL OR a.owner_id IS DISTINCT FROM OLD.user_id
                OR a.scan_id IS DISTINCT FROM OLD.client_scan_id OR a.asset_id IS DISTINCT FROM OLD.id
                OR a.session_id IS DISTINCT FROM OLD.upload_session_id)) THEN
        RETURN NEW;
    END IF;
    IF NEW.source = 'capture_upload' AND EXISTS (
        SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = NEW.storage_key
            AND (a.retired_at IS NOT NULL OR a.owner_id IS DISTINCT FROM NEW.user_id
                OR a.scan_id IS DISTINCT FROM NEW.client_scan_id OR a.asset_id IS DISTINCT FROM NEW.id
                OR a.session_id IS DISTINCT FROM NEW.upload_session_id)
    ) THEN RAISE EXCEPTION 'capture_object_retired_or_rebound' USING ERRCODE = '55000'; END IF;
    RETURN NEW;
END;
$$;
COMMENT ON TABLE internal.capture_reparent_transactions IS
    'Private transaction-bound exception for metadata-only account merge; removed before return and never grants object reuse or a new upload capability.';
COMMENT ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID,UUID) IS
    'Preserves schema-aware account merge and atomically retires transferred old-owner staging capabilities; no API execution grant.';
RESET statement_timeout;
RESET lock_timeout;

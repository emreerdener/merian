SET lock_timeout = '5s';
SET statement_timeout = '2min';

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
    -- Registered keys cannot evade the fence by changing classification, or by
    -- moving the row away from its old key before binding another identity.
    IF TG_OP = 'UPDATE' AND EXISTS (
        SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = OLD.storage_key
    ) AND (NEW.source IS DISTINCT FROM OLD.source OR NEW.storage_key IS DISTINCT FROM OLD.storage_key
        OR NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.id IS DISTINCT FROM OLD.id
        OR NEW.client_scan_id IS DISTINCT FROM OLD.client_scan_id
        OR NEW.upload_session_id IS DISTINCT FROM OLD.upload_session_id) THEN
        RAISE EXCEPTION 'capture_object_retired_or_rebound' USING ERRCODE = '55000';
    END IF;
    IF EXISTS (
        SELECT 1 FROM internal.capture_object_authorities a WHERE a.object_key = NEW.storage_key
            AND (NEW.source IS DISTINCT FROM 'capture_upload' OR a.retired_at IS NOT NULL
                OR a.owner_id IS DISTINCT FROM NEW.user_id
                OR a.scan_id IS DISTINCT FROM NEW.client_scan_id OR a.asset_id IS DISTINCT FROM NEW.id
                OR a.session_id IS DISTINCT FROM NEW.upload_session_id)
    ) THEN RAISE EXCEPTION 'capture_object_retired_or_rebound' USING ERRCODE = '55000'; END IF;
    RETURN NEW;
END;
$$;

RESET statement_timeout;
RESET lock_timeout;

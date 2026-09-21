-- Five sampled video frames, companion audio, optional standalone audio, and
-- playback video require eight source slots. Preserve owner serialization and
-- active-row scope while aligning the database with the upload manifest.
SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION internal.enforce_staged_scan_media_budget()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    existing_staged_count INTEGER;
BEGIN
    IF NEW.source = 'capture_upload'
       AND NEW.status = 'staged'
       AND NEW.client_scan_id IS NOT NULL
       AND NEW.storage_key IS NOT NULL THEN
        -- Signing calls for one scan can be composable subsets (for example a
        -- live video and later queue recovery frames). Serialize disjoint-key
        -- registrations as well as identical-key registrations so concurrent
        -- requests cannot evade the per-scan media budget.
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED(
                'merian-staged-scan-media-owner:'
                    || NEW.user_id::TEXT,
                0::BIGINT
            )
        );

        SELECT pg_catalog.COUNT(*)::INTEGER
        INTO STRICT existing_staged_count
        FROM public.scan_media_assets AS assets
        WHERE assets.user_id = NEW.user_id
          AND assets.client_scan_id = NEW.client_scan_id
          AND assets.source = 'capture_upload'
          AND assets.status = 'staged'
          AND assets.storage_key IS NOT NULL
          AND assets.id IS DISTINCT FROM NEW.id;

        IF existing_staged_count >= 8 THEN
            RAISE EXCEPTION 'staged_scan_media_budget_exceeded'
                USING ERRCODE = '54000';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_staged_scan_media_budget()
    FROM PUBLIC, anon, authenticated, service_role;

RESET statement_timeout;
RESET lock_timeout;

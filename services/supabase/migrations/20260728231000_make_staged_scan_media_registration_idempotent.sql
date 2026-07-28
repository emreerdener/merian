-- A retry of /generate-upload-urls signs the same deterministic object key.
-- Before registration became idempotent, a lost HTTP response could therefore
-- commit two capture-upload ledger rows for one logical source. The strict
-- finalizer correctly rejected the resulting multi-row update. Preserve one
-- canonical lifecycle row, retain every extra row as an explicitly superseded
-- audit record, and prevent future concurrent staging duplicates.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

WITH ranked_capture_rows AS (
    SELECT
        assets.id,
        assets.status AS prior_status,
        assets.failure_reason AS prior_failure_reason,
        pg_catalog.ROW_NUMBER() OVER (
            PARTITION BY
                assets.user_id,
                assets.client_scan_id,
                assets.storage_key
            ORDER BY
                CASE assets.status
                    WHEN 'promoted' THEN 0
                    WHEN 'ready' THEN 1
                    WHEN 'deleted' THEN 2
                    WHEN 'staged' THEN 3
                    WHEN 'processing' THEN 4
                    ELSE 5
                END,
                assets.created_at,
                assets.id
        ) AS lifecycle_rank,
        pg_catalog.COUNT(*) OVER (
            PARTITION BY
                assets.user_id,
                assets.client_scan_id,
                assets.storage_key
        ) AS identity_count
    FROM public.scan_media_assets AS assets
    WHERE assets.source = 'capture_upload'
      AND assets.client_scan_id IS NOT NULL
      AND assets.storage_key IS NOT NULL
)
UPDATE public.scan_media_assets AS assets
SET status = 'failed',
    failure_reason = 'superseded_staging_registration',
    metadata = COALESCE(assets.metadata, '{}'::JSONB)
        || pg_catalog.JSONB_BUILD_OBJECT(
            'supersededStagingRegistration',
            pg_catalog.JSONB_BUILD_OBJECT(
                'priorStatus',
                ranked.prior_status,
                'priorFailureReason',
                ranked.prior_failure_reason,
                'supersededAt',
                pg_catalog.NOW()
            )
        ),
    updated_at = pg_catalog.NOW()
FROM ranked_capture_rows AS ranked
WHERE ranked.id = assets.id
  AND ranked.identity_count > 1
  AND ranked.lifecycle_rank > 1;

CREATE UNIQUE INDEX idx_scan_media_assets_active_staging_key_unique
    ON public.scan_media_assets(user_id, client_scan_id, storage_key)
    WHERE source = 'capture_upload'
      AND status = 'staged'
      AND client_scan_id IS NOT NULL
      AND storage_key IS NOT NULL;

COMMENT ON INDEX public.idx_scan_media_assets_active_staging_key_unique IS
    'Serializes upload-URL retries so one owner/client-scan/storage key has at most one active staged capture ledger row.';

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

        IF existing_staged_count >= 6 THEN
            RAISE EXCEPTION 'staged_scan_media_budget_exceeded'
                USING ERRCODE = '54000';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_staged_scan_media_budget()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enforce_staged_scan_media_budget
    ON public.scan_media_assets;
CREATE TRIGGER enforce_staged_scan_media_budget
BEFORE INSERT OR UPDATE ON public.scan_media_assets
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_staged_scan_media_budget();

RESET statement_timeout;
RESET lock_timeout;

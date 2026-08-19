SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Replace the initial canonical-order helper with a two-phase rewrite that
-- reserves temporary order space across every row covered by the generated
-- unique index. Non-ready lifecycle rows are preserved after the ready media
-- timeline instead of being allowed to collide with either temporary or final
-- ready positions.
CREATE OR REPLACE FUNCTION internal.align_scan_media_asset_order(
    target_scan_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    media_manifest JSONB;
    manifest_length INTEGER;
    ready_asset_count BIGINT;
    generated_asset_count BIGINT;
    shift_base BIGINT;
BEGIN
    SELECT scan.captured_media
    INTO media_manifest
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id;

    IF NOT FOUND
       OR media_manifest IS NULL
       OR pg_catalog.JSONB_TYPEOF(media_manifest) IS DISTINCT FROM 'array' THEN
        RETURN;
    END IF;

    manifest_length := pg_catalog.JSONB_ARRAY_LENGTH(media_manifest);

    IF manifest_length = 0 THEN
        RETURN;
    END IF;

    SELECT
        pg_catalog.COUNT(*) FILTER (
            WHERE asset.status = 'ready'
        ),
        pg_catalog.COUNT(*),
        GREATEST(
            COALESCE(pg_catalog.MAX(asset.order_index), -1)::BIGINT + 1,
            manifest_length::BIGINT + pg_catalog.COUNT(*)::BIGINT + 1
        )
    INTO ready_asset_count, generated_asset_count, shift_base
    FROM public.scan_media_assets AS asset
    WHERE asset.scan_id = target_scan_id
      AND asset.source IN ('scan_refresh', 'backfill');

    IF ready_asset_count = 0 THEN
        RETURN;
    END IF;

    IF shift_base + generated_asset_count >= 2147483647 THEN
        RAISE EXCEPTION 'scan media order index space exhausted for scan %',
            target_scan_id
            USING ERRCODE = '22003';
    END IF;

    -- Move every row covered by the generated unique index into disjoint
    -- temporary space. Restricting this phase to ready rows would allow a
    -- staged, processing, failed, or deleted row to occupy the temporary key.
    WITH ranked_assets AS (
        SELECT
            asset.id,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY asset.source, asset.role
                ORDER BY asset.order_index, asset.id
            ) AS temporary_rank
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.source IN ('scan_refresh', 'backfill')
    )
    UPDATE public.scan_media_assets AS asset
    SET order_index = (shift_base + ranked_assets.temporary_rank)::INTEGER
    FROM ranked_assets
    WHERE asset.id = ranked_assets.id;

    WITH raw_manifest AS (
        SELECT entry.value AS media_item, entry.ordinality
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(media_manifest)
            WITH ORDINALITY AS entry(value, ordinality)
    ),
    manifest_assets AS (
        SELECT
            CASE
                WHEN raw.media_item ? 'image' THEN 'image'
                WHEN raw.media_item ? 'video' THEN 'video'
                WHEN raw.media_item ? 'audio' THEN 'audio'
                ELSE NULL
            END AS kind,
            CASE
                WHEN raw.media_item ? 'image' THEN
                    public.scan_media_reference_path(raw.media_item #> '{image,_0}')
                WHEN raw.media_item ? 'video' THEN
                    public.scan_media_reference_path(raw.media_item #> '{video,_0,video}')
                WHEN raw.media_item ? 'audio' THEN
                    public.scan_media_reference_path(raw.media_item #> '{audio,_0}')
                ELSE NULL
            END AS url,
            (raw.ordinality - 1)::INTEGER AS desired_order
        FROM raw_manifest AS raw
    ),
    ranked_manifest AS (
        SELECT
            manifest.kind,
            manifest.url,
            manifest.desired_order,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY manifest.kind, manifest.url
                ORDER BY manifest.desired_order
            ) AS duplicate_rank
        FROM manifest_assets AS manifest
        WHERE manifest.kind IS NOT NULL
          AND manifest.url IS NOT NULL
    ),
    ranked_generated AS (
        SELECT
            asset.id,
            asset.kind,
            asset.url,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY asset.kind, asset.url
                ORDER BY asset.source, asset.role, asset.id
            ) AS duplicate_rank
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.status = 'ready'
          AND asset.source IN ('scan_refresh', 'backfill')
    )
    UPDATE public.scan_media_assets AS asset
    SET order_index = manifest.desired_order
    FROM ranked_generated AS generated
    JOIN ranked_manifest AS manifest
      ON manifest.kind = generated.kind
     AND manifest.url = generated.url
     AND manifest.duplicate_rank = generated.duplicate_rank
    WHERE asset.id = generated.id;

    -- Preserve unmatched ready legacy extras after the canonical timeline.
    WITH unmatched AS (
        SELECT
            asset.id,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY asset.source, asset.role
                ORDER BY asset.kind, asset.url, asset.id
            ) AS trailing_rank
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.status = 'ready'
          AND asset.source IN ('scan_refresh', 'backfill')
          AND asset.order_index >= shift_base
    )
    UPDATE public.scan_media_assets AS asset
    SET order_index = manifest_length + unmatched.trailing_rank::INTEGER - 1
    FROM unmatched
    WHERE asset.id = unmatched.id;

    -- Non-ready generated rows are private lifecycle evidence. Keep their
    -- relative order, but place them after every ready row in the same unique
    -- source/role partition so they cannot occupy canonical ready positions.
    WITH ready_ceiling AS (
        SELECT
            asset.source,
            asset.role,
            pg_catalog.MAX(asset.order_index)::BIGINT AS max_ready_order
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.status = 'ready'
          AND asset.source IN ('scan_refresh', 'backfill')
        GROUP BY asset.source, asset.role
    ),
    ranked_non_ready AS (
        SELECT
            asset.id,
            asset.source,
            asset.role,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY asset.source, asset.role
                ORDER BY asset.order_index, asset.id
            ) AS trailing_rank
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.status <> 'ready'
          AND asset.source IN ('scan_refresh', 'backfill')
    )
    UPDATE public.scan_media_assets AS asset
    SET order_index = (
        GREATEST(
            manifest_length::BIGINT,
            COALESCE(
                ready_ceiling.max_ready_order + 1,
                manifest_length::BIGINT
            )
        ) + ranked_non_ready.trailing_rank - 1
    )::INTEGER
    FROM ranked_non_ready
    LEFT JOIN ready_ceiling
      ON ready_ceiling.source = ranked_non_ready.source
     AND ready_ceiling.role = ranked_non_ready.role
    WHERE asset.id = ranked_non_ready.id;
END;
$$;

COMMENT ON FUNCTION internal.align_scan_media_asset_order(UUID) IS
  'Aligns generated ready scan-media rows to captured_media ordinality and preserves non-ready lifecycle rows after the ready timeline.';

REVOKE ALL ON FUNCTION internal.align_scan_media_asset_order(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

RESET statement_timeout;
RESET lock_timeout;

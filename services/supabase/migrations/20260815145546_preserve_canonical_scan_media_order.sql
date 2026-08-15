SET lock_timeout = '5s';
SET statement_timeout = '60s';

-- Keep normalized scan_media_assets rows at the same ordinal positions as the
-- owner-visible captured_media timeline. Description entries intentionally leave
-- gaps because they do not have a scan_media_assets row.
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
    generated_asset_count INTEGER;
    shift_base BIGINT;
BEGIN
    SELECT scan.captured_media
    INTO media_manifest
    FROM public.scans AS scan
    WHERE scan.id = target_scan_id;

    IF NOT FOUND
       OR pg_catalog.JSONB_TYPEOF(media_manifest) <> 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(media_manifest) = 0 THEN
        RETURN;
    END IF;

    manifest_length := pg_catalog.JSONB_ARRAY_LENGTH(media_manifest);

    SELECT
        COUNT(*)::INTEGER,
        GREATEST(
            COALESCE(MAX(asset.order_index), -1)::BIGINT + 1,
            manifest_length::BIGINT + 1
        )
    INTO generated_asset_count, shift_base
    FROM public.scan_media_assets AS asset
    WHERE asset.scan_id = target_scan_id
      AND asset.status = 'ready'
      AND asset.source IN ('scan_refresh', 'backfill');

    IF generated_asset_count = 0 THEN
        RETURN;
    END IF;

    IF shift_base + generated_asset_count >= 2147483647 THEN
        RAISE EXCEPTION 'scan media order index space exhausted for scan %',
            target_scan_id
            USING ERRCODE = '22003';
    END IF;

    -- Move generated rows into unused order space before assigning canonical
    -- positions, avoiding transient conflicts in the generated unique index.
    WITH ranked_assets AS (
        SELECT
            asset.id,
            ROW_NUMBER() OVER (
                PARTITION BY asset.source, asset.role
                ORDER BY asset.order_index, asset.id
            ) AS temporary_rank
        FROM public.scan_media_assets AS asset
        WHERE asset.scan_id = target_scan_id
          AND asset.status = 'ready'
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
            ROW_NUMBER() OVER (
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
            ROW_NUMBER() OVER (
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

    -- Preserve unmatched legacy extras after the canonical timeline instead of
    -- deleting them or letting them collide with description/media ordinals.
    WITH unmatched AS (
        SELECT
            asset.id,
            ROW_NUMBER() OVER (
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
END;
$$;

COMMENT ON FUNCTION internal.align_scan_media_asset_order(UUID) IS
  'Aligns generated ready scan-media rows to captured_media ordinality without deleting unmatched legacy media.';

REVOKE ALL ON FUNCTION internal.align_scan_media_asset_order(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets(target_scan_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM public.refresh_scan_visual_media_assets(target_scan_id);
    PERFORM public.refresh_scan_audio_assets(target_scan_id);
    PERFORM internal.align_scan_media_asset_order(target_scan_id);
END;
$$;

COMMENT ON FUNCTION public.refresh_scan_media_assets(UUID) IS
  'Service-only rebuild of canonical image, playback-video, and standalone-audio assets aligned to captured_media order.';

REVOKE ALL ON FUNCTION public.refresh_scan_media_assets(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role;

RESET statement_timeout;
RESET lock_timeout;

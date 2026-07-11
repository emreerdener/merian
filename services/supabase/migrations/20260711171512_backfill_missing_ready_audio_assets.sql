-- Make standalone audio part of the canonical scan media refresh contract.
--
-- The original refresh function predates scans.audio_storage_urls. Renaming it
-- preserves the battle-tested image/video rebuild, while the new wrapper adds
-- audio synchronization and keeps every existing caller on the same RPC name.

ALTER FUNCTION public.refresh_scan_media_assets(UUID)
    RENAME TO refresh_scan_visual_media_assets;

CREATE OR REPLACE FUNCTION public.refresh_scan_audio_assets(target_scan_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    media_item JSONB;
    audio_url TEXT;
    order_idx INTEGER;
    audio_ordinality BIGINT;
BEGIN
    SELECT s.id, s.user_id, s.audio_storage_urls, s.captured_media
    INTO scan_row
    FROM public.scans s
    WHERE s.id = target_scan_id;

    IF NOT FOUND THEN
        DELETE FROM public.scan_media_assets
        WHERE scan_id = target_scan_id
          AND kind = 'audio'
          AND source IN ('scan_refresh', 'backfill', 'manual');
        RETURN;
    END IF;

    DELETE FROM public.scan_media_assets
    WHERE scan_id = target_scan_id
      AND kind = 'audio'
      AND source IN ('scan_refresh', 'backfill', 'manual');

    IF JSONB_TYPEOF(scan_row.captured_media) = 'array' THEN
        FOR media_item, audio_ordinality IN
            SELECT value, ordinality
            FROM JSONB_ARRAY_ELEMENTS(scan_row.captured_media) WITH ORDINALITY
        LOOP
            audio_url := public.scan_media_reference_path(media_item #> '{audio,_0}');
            IF audio_url IS NULL THEN
                CONTINUE;
            END IF;

            INSERT INTO public.scan_media_assets (
                scan_id, client_scan_id, user_id, kind, role, status, source,
                url, storage_key, thumbnail_url, order_index, has_audio,
                content_type, ready_at, metadata
            ) VALUES (
                scan_row.id, scan_row.id, scan_row.user_id, 'audio', 'audio',
                'ready', 'scan_refresh', audio_url, NULL, NULL,
                (audio_ordinality - 1)::INTEGER, TRUE,
                CASE
                    WHEN LOWER(SPLIT_PART(audio_url, '?', 1)) ~ '\.(m4a|mp4)$' THEN 'audio/mp4'
                    ELSE 'audio/wav'
                END,
                NOW(), JSONB_BUILD_OBJECT('manifest_source', 'captured_media')
            );
        END LOOP;
    END IF;

    SELECT COALESCE(MAX(asset.order_index), -1) + 1
    INTO order_idx
    FROM public.scan_media_assets asset
    WHERE asset.scan_id = target_scan_id
      AND asset.status = 'ready';

    FOR audio_url IN
        SELECT NULLIF(BTRIM(raw_audio_url), '')
        FROM UNNEST(COALESCE(scan_row.audio_storage_urls, ARRAY[]::TEXT[]))
            WITH ORDINALITY AS stored_audio(raw_audio_url, ordinality)
        WHERE NULLIF(BTRIM(raw_audio_url), '') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets existing
              WHERE existing.scan_id = target_scan_id
                AND existing.kind = 'audio'
                AND existing.role = 'audio'
                AND existing.status = 'ready'
                AND existing.url = NULLIF(BTRIM(raw_audio_url), '')
          )
        ORDER BY ordinality
    LOOP
        INSERT INTO public.scan_media_assets (
            scan_id, client_scan_id, user_id, kind, role, status, source,
            url, storage_key, thumbnail_url, order_index, has_audio,
            content_type, ready_at, metadata
        ) VALUES (
            scan_row.id, scan_row.id, scan_row.user_id, 'audio', 'audio',
            'ready', 'scan_refresh', audio_url, NULL, NULL, order_idx, TRUE,
            CASE
                WHEN LOWER(SPLIT_PART(audio_url, '?', 1)) ~ '\.(m4a|mp4)$' THEN 'audio/mp4'
                ELSE 'audio/wav'
            END,
            NOW(), JSONB_BUILD_OBJECT('manifest_source', 'legacy_arrays')
        );
        order_idx := order_idx + 1;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets(target_scan_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.refresh_scan_visual_media_assets(target_scan_id);
    PERFORM public.refresh_scan_audio_assets(target_scan_id);
END;
$$;

COMMENT ON FUNCTION public.refresh_scan_media_assets(UUID) IS
  'Rebuilds canonical image, playback video, and standalone audio scan media assets.';

REVOKE ALL ON FUNCTION public.refresh_scan_visual_media_assets(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_scan_audio_assets(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_scan_media_assets(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role;

DO $$
DECLARE
    repair_scan RECORD;
BEGIN
    FOR repair_scan IN
        SELECT s.id
        FROM public.scans s
        WHERE COALESCE(ARRAY_LENGTH(s.audio_storage_urls, 1), 0) > 0
        ORDER BY s.timestamp DESC NULLS LAST
    LOOP
        PERFORM public.refresh_scan_media_assets(repair_scan.id);
    END LOOP;
END;
$$;

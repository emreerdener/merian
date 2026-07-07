-- Keep generated scan_media_assets.has_audio tied to actual captured media.
--
-- Video clips may be captured without microphone permission or without a
-- successfully extracted audio companion. The previous refresh function marked
-- every video row as having audio, which made Explore/media metadata overstate
-- what was actually persisted.

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets(target_scan_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    media_item JSONB;
    asset_image_url TEXT;
    asset_video_url TEXT;
    asset_thumbnail_url TEXT;
    asset_audio_url TEXT;
    image_urls TEXT[];
    video_urls TEXT[];
    image_count INTEGER;
    video_count INTEGER;
    expected_video_frame_count INTEGER;
    standalone_image_count INTEGER;
    order_idx INTEGER := 0;
    i INTEGER;
BEGIN
    SELECT
        s.id,
        s.user_id,
        s.image_storage_urls,
        s.video_storage_urls,
        s.captured_media
    INTO scan_row
    FROM public.scans s
    WHERE s.id = target_scan_id;

    IF NOT FOUND THEN
        DELETE FROM public.scan_media_assets
        WHERE scan_id = target_scan_id;
        RETURN;
    END IF;

    DELETE FROM public.scan_media_assets
    WHERE scan_id = target_scan_id
      AND source IN ('scan_refresh', 'backfill');

    IF JSONB_TYPEOF(scan_row.captured_media) = 'array'
       AND JSONB_ARRAY_LENGTH(scan_row.captured_media) > 0 THEN
        FOR media_item IN
            SELECT value
            FROM JSONB_ARRAY_ELEMENTS(scan_row.captured_media)
        LOOP
            asset_image_url := public.scan_media_reference_path(media_item #> '{image,_0}');
            IF asset_image_url IS NOT NULL THEN
                INSERT INTO public.scan_media_assets (
                    scan_id,
                    client_scan_id,
                    user_id,
                    kind,
                    role,
                    status,
                    source,
                    url,
                    storage_key,
                    thumbnail_url,
                    order_index,
                    has_audio,
                    content_type,
                    ready_at,
                    metadata
                )
                VALUES (
                    scan_row.id,
                    scan_row.id,
                    scan_row.user_id,
                    'image',
                    'display',
                    'ready',
                    'scan_refresh',
                    asset_image_url,
                    NULL,
                    asset_image_url,
                    order_idx,
                    FALSE,
                    'image/webp',
                    NOW(),
                    JSONB_BUILD_OBJECT('manifest_source', 'captured_media')
                );
                order_idx := order_idx + 1;
                CONTINUE;
            END IF;

            asset_video_url := public.scan_media_reference_path(media_item #> '{video,_0,video}');
            IF asset_video_url IS NOT NULL THEN
                asset_thumbnail_url := public.scan_media_reference_path(media_item #> '{video,_0,thumbnail}');
                asset_audio_url := public.scan_media_reference_path(media_item #> '{video,_0,audio}');
                INSERT INTO public.scan_media_assets (
                    scan_id,
                    client_scan_id,
                    user_id,
                    kind,
                    role,
                    status,
                    source,
                    url,
                    storage_key,
                    thumbnail_url,
                    order_index,
                    has_audio,
                    content_type,
                    ready_at,
                    metadata
                )
                VALUES (
                    scan_row.id,
                    scan_row.id,
                    scan_row.user_id,
                    'video',
                    'playback',
                    'ready',
                    'scan_refresh',
                    asset_video_url,
                    NULL,
                    asset_thumbnail_url,
                    order_idx,
                    asset_audio_url IS NOT NULL,
                    'video/mp4',
                    NOW(),
                    JSONB_BUILD_OBJECT('manifest_source', 'captured_media')
                );
                order_idx := order_idx + 1;
            END IF;
        END LOOP;

        IF order_idx > 0 THEN
            RETURN;
        END IF;
    END IF;

    SELECT COALESCE(ARRAY_AGG(cleaned.clean_url ORDER BY cleaned.ordinality), ARRAY[]::TEXT[])
    INTO image_urls
    FROM (
        SELECT NULLIF(BTRIM(media_images.raw_image_url), '') AS clean_url,
            media_images.ordinality
        FROM UNNEST(COALESCE(scan_row.image_storage_urls, ARRAY[]::TEXT[]))
            WITH ORDINALITY AS media_images(raw_image_url, ordinality)
    ) cleaned
    WHERE cleaned.clean_url IS NOT NULL;

    SELECT COALESCE(ARRAY_AGG(cleaned.clean_url ORDER BY cleaned.ordinality), ARRAY[]::TEXT[])
    INTO video_urls
    FROM (
        SELECT NULLIF(BTRIM(media_videos.raw_video_url), '') AS clean_url,
            media_videos.ordinality
        FROM UNNEST(COALESCE(scan_row.video_storage_urls, ARRAY[]::TEXT[]))
            WITH ORDINALITY AS media_videos(raw_video_url, ordinality)
    ) cleaned
    WHERE cleaned.clean_url IS NOT NULL;

    image_count := COALESCE(ARRAY_LENGTH(image_urls, 1), 0);
    video_count := COALESCE(ARRAY_LENGTH(video_urls, 1), 0);
    expected_video_frame_count := video_count * 5;
    standalone_image_count := CASE
        WHEN video_count > 0 THEN GREATEST(image_count - expected_video_frame_count, 0)
        ELSE image_count
    END;

    IF standalone_image_count > 0 THEN
        FOR i IN 1..standalone_image_count LOOP
            INSERT INTO public.scan_media_assets (
                scan_id,
                client_scan_id,
                user_id,
                kind,
                role,
                status,
                source,
                url,
                storage_key,
                thumbnail_url,
                order_index,
                has_audio,
                content_type,
                ready_at,
                metadata
            )
            VALUES (
                scan_row.id,
                scan_row.id,
                scan_row.user_id,
                'image',
                'display',
                'ready',
                'scan_refresh',
                image_urls[i],
                NULL,
                image_urls[i],
                order_idx,
                FALSE,
                'image/webp',
                NOW(),
                JSONB_BUILD_OBJECT('manifest_source', 'legacy_arrays')
            );
            order_idx := order_idx + 1;
        END LOOP;
    END IF;

    IF video_count > 0 THEN
        FOR i IN 1..video_count LOOP
            asset_thumbnail_url := COALESCE(
                image_urls[standalone_image_count + ((i - 1) * 5) + 1],
                image_urls[1]
            );
            INSERT INTO public.scan_media_assets (
                scan_id,
                client_scan_id,
                user_id,
                kind,
                role,
                status,
                source,
                url,
                storage_key,
                thumbnail_url,
                order_index,
                has_audio,
                content_type,
                ready_at,
                metadata
            )
            VALUES (
                scan_row.id,
                scan_row.id,
                scan_row.user_id,
                'video',
                'playback',
                'ready',
                'scan_refresh',
                video_urls[i],
                NULL,
                asset_thumbnail_url,
                order_idx,
                FALSE,
                'video/mp4',
                NOW(),
                JSONB_BUILD_OBJECT('manifest_source', 'legacy_arrays')
            );
            order_idx := order_idx + 1;
        END LOOP;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.refresh_scan_media_assets(UUID) IS
  'Rebuilds generated scan_media_assets rows from captured_media or legacy media URL arrays. Video has_audio is true only when a captured_media video includes an audio reference.';

REVOKE ALL ON FUNCTION public.refresh_scan_media_assets(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role;

DO $$
DECLARE
    repair_scan RECORD;
BEGIN
    FOR repair_scan IN
        SELECT s.id
        FROM public.scans s
        WHERE COALESCE(ARRAY_LENGTH(s.video_storage_urls, 1), 0) > 0
        ORDER BY s.timestamp DESC NULLS LAST
        LIMIT 500
    LOOP
        BEGIN
            PERFORM public.refresh_scan_media_assets(repair_scan.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skipping video audio metadata refresh for scan %: %',
                repair_scan.id,
                SQLERRM;
        END;
    END LOOP;
END;
$$;

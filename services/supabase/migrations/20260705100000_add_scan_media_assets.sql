-- Normalize scan media into a first-class projection table.
--
-- The legacy scan columns remain compatibility/indexing surfaces:
--   - image_storage_urls
--   - video_storage_urls
--   - captured_media
--
-- scan_media_assets is the durable server-side projection used by newer media
-- readers. It stores only user-visible scan media, so sampled video inference
-- frames are collapsed behind one video asset with a poster thumbnail.

CREATE TABLE IF NOT EXISTS public.scan_media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'video')),
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    order_index INTEGER NOT NULL CHECK (order_index >= 0),
    duration_seconds DOUBLE PRECISION,
    has_audio BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (scan_id, order_index)
);

CREATE INDEX IF NOT EXISTS idx_scan_media_assets_scan_order
    ON public.scan_media_assets(scan_id, order_index);

CREATE INDEX IF NOT EXISTS idx_scan_media_assets_user_scan
    ON public.scan_media_assets(user_id, scan_id);

CREATE INDEX IF NOT EXISTS idx_scan_media_assets_video_scan
    ON public.scan_media_assets(scan_id)
    WHERE kind = 'video';

ALTER TABLE public.scan_media_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own scan media assets" ON public.scan_media_assets;
CREATE POLICY "Users can read their own scan media assets"
    ON public.scan_media_assets
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Anyone can read open live scan media assets" ON public.scan_media_assets;
CREATE POLICY "Anyone can read open live scan media assets"
    ON public.scan_media_assets
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.scans s
            WHERE s.id = scan_media_assets.scan_id
              AND s.geoprivacy = 'open'
              AND s.is_live_capture = TRUE
              AND s.is_tombstoned = FALSE
        )
    );

COMMENT ON TABLE public.scan_media_assets IS
  'Normalized user-visible media assets for scans. Video scans collapse sampled inference frames into one playback video asset with a poster thumbnail.';

COMMENT ON COLUMN public.scan_media_assets.url IS
  'Public media URL for the user-visible image or playback video asset.';

COMMENT ON COLUMN public.scan_media_assets.thumbnail_url IS
  'Image URL used for compact previews and video poster frames.';

COMMENT ON COLUMN public.scan_media_assets.metadata IS
  'Reserved structured metadata for future dimensions, codecs, checksums, and processing status.';

CREATE OR REPLACE FUNCTION public.scan_media_reference_path(reference JSONB)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT NULLIF(BTRIM(
        CASE
            WHEN reference IS NULL THEN NULL
            WHEN JSONB_TYPEOF(reference) = 'string' THEN reference #>> '{}'
            WHEN JSONB_TYPEOF(reference) = 'object' THEN reference ->> 'path'
            ELSE NULL
        END
    ), '');
$$;

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets(target_scan_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    media_item JSONB;
    image_url TEXT;
    video_url TEXT;
    thumbnail_url TEXT;
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
    WHERE scan_id = target_scan_id;

    IF JSONB_TYPEOF(scan_row.captured_media) = 'array'
       AND JSONB_ARRAY_LENGTH(scan_row.captured_media) > 0 THEN
        FOR media_item IN
            SELECT value
            FROM JSONB_ARRAY_ELEMENTS(scan_row.captured_media)
        LOOP
            image_url := public.scan_media_reference_path(media_item #> '{image,_0}');
            IF image_url IS NOT NULL THEN
                INSERT INTO public.scan_media_assets (
                    scan_id,
                    user_id,
                    kind,
                    url,
                    thumbnail_url,
                    order_index,
                    has_audio
                )
                VALUES (
                    scan_row.id,
                    scan_row.user_id,
                    'image',
                    image_url,
                    image_url,
                    order_idx,
                    FALSE
                );
                order_idx := order_idx + 1;
                CONTINUE;
            END IF;

            video_url := public.scan_media_reference_path(media_item #> '{video,_0,video}');
            IF video_url IS NOT NULL THEN
                thumbnail_url := public.scan_media_reference_path(media_item #> '{video,_0,thumbnail}');
                INSERT INTO public.scan_media_assets (
                    scan_id,
                    user_id,
                    kind,
                    url,
                    thumbnail_url,
                    order_index,
                    has_audio
                )
                VALUES (
                    scan_row.id,
                    scan_row.user_id,
                    'video',
                    video_url,
                    thumbnail_url,
                    order_idx,
                    TRUE
                );
                order_idx := order_idx + 1;
            END IF;
        END LOOP;

        IF order_idx > 0 THEN
            RETURN;
        END IF;
    END IF;

    SELECT COALESCE(ARRAY_AGG(clean_url ORDER BY ordinality), ARRAY[]::TEXT[])
    INTO image_urls
    FROM (
        SELECT NULLIF(BTRIM(image_url), '') AS clean_url, ordinality
        FROM UNNEST(COALESCE(scan_row.image_storage_urls, ARRAY[]::TEXT[]))
            WITH ORDINALITY AS images(image_url, ordinality)
    ) cleaned
    WHERE clean_url IS NOT NULL;

    SELECT COALESCE(ARRAY_AGG(clean_url ORDER BY ordinality), ARRAY[]::TEXT[])
    INTO video_urls
    FROM (
        SELECT NULLIF(BTRIM(video_url), '') AS clean_url, ordinality
        FROM UNNEST(COALESCE(scan_row.video_storage_urls, ARRAY[]::TEXT[]))
            WITH ORDINALITY AS videos(video_url, ordinality)
    ) cleaned
    WHERE clean_url IS NOT NULL;

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
                user_id,
                kind,
                url,
                thumbnail_url,
                order_index,
                has_audio
            )
            VALUES (
                scan_row.id,
                scan_row.user_id,
                'image',
                image_urls[i],
                image_urls[i],
                order_idx,
                FALSE
            );
            order_idx := order_idx + 1;
        END LOOP;
    END IF;

    IF video_count > 0 THEN
        FOR i IN 1..video_count LOOP
            thumbnail_url := COALESCE(
                image_urls[standalone_image_count + ((i - 1) * 5) + 1],
                image_urls[1]
            );
            INSERT INTO public.scan_media_assets (
                scan_id,
                user_id,
                kind,
                url,
                thumbnail_url,
                order_index,
                has_audio
            )
            VALUES (
                scan_row.id,
                scan_row.user_id,
                'video',
                video_urls[i],
                thumbnail_url,
                order_idx,
                TRUE
            );
            order_idx := order_idx + 1;
        END LOOP;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets_for_scan()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM public.scan_media_assets
        WHERE scan_id = OLD.id;
        RETURN OLD;
    END IF;

    PERFORM public.refresh_scan_media_assets(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_scan_media_assets ON public.scans;
CREATE TRIGGER trg_refresh_scan_media_assets
AFTER INSERT OR UPDATE OF user_id, image_storage_urls, video_storage_urls, captured_media OR DELETE
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.refresh_scan_media_assets_for_scan();

CREATE OR REPLACE FUNCTION public.refresh_all_scan_media_assets()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
BEGIN
    FOR scan_row IN SELECT id FROM public.scans LOOP
        BEGIN
            PERFORM public.refresh_scan_media_assets(scan_row.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skipping scan media asset projection for scan %: %', scan_row.id, SQLERRM;
        END;
    END LOOP;
END;
$$;

SELECT public.refresh_all_scan_media_assets();

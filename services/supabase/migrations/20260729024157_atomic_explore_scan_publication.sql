-- Publish one owned scan to Explore in a single database transaction.
--
-- The Edge route performs media restoration, selection, thumbnail generation,
-- and audio moderation before entering this boundary. Historically it then
-- upserted explore_posts, deleted/reinserted media, deleted/reinserted
-- hashtags, and marked a resolved community request in separate PostgREST
-- transactions. A failure between those calls could expose a partial post or
-- erase a previously healthy snapshot while the client correctly reported
-- failure.
--
-- Keep the transaction short: this routine performs only owner revalidation
-- and final relational writes. It is SECURITY INVOKER and executable only by
-- service_role; the authenticated Edge handler remains responsible for
-- resolving the caller before supplying p_user_id.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.publish_scan_to_explore_atomically(
    p_scan_id UUID,
    p_user_id UUID,
    p_species_common_name TEXT,
    p_field_notes TEXT,
    p_location_sharing TEXT,
    p_media_rows JSONB,
    p_hashtags TEXT[]
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_audio_urls TEXT[];
    v_community_request_status public.explore_community_request_status;
    v_distinct_hashtag_count INTEGER;
    v_distinct_order_count INTEGER;
    v_hashtags TEXT[] := COALESCE(p_hashtags, ARRAY[]::TEXT[]);
    v_image_urls TEXT[];
    v_location_sharing TEXT;
    v_media_count INTEGER;
    v_media_item JSONB;
    v_media_kind TEXT;
    v_media_order NUMERIC;
    v_media_thumbnail_url TEXT;
    v_media_url TEXT;
    v_post_id UUID;
    v_shared_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    v_scan_geoprivacy TEXT;
    v_video_urls TEXT[];
BEGIN
    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Scan and owner are required'
            USING ERRCODE = '22023';
    END IF;

    IF p_species_common_name IS NOT NULL
       AND (
           pg_catalog.BTRIM(p_species_common_name) = ''
           OR pg_catalog.CHAR_LENGTH(p_species_common_name) > 200
       ) THEN
        RAISE EXCEPTION 'Invalid Explore species common name'
            USING ERRCODE = '22023';
    END IF;

    IF p_field_notes IS NOT NULL
       AND (
           pg_catalog.BTRIM(p_field_notes) = ''
           OR pg_catalog.CHAR_LENGTH(p_field_notes) > 1000
       ) THEN
        RAISE EXCEPTION 'Invalid Explore field notes'
            USING ERRCODE = '22023';
    END IF;

    IF p_location_sharing IS NOT NULL
       AND p_location_sharing NOT IN ('open', 'obscured', 'private') THEN
        RAISE EXCEPTION 'Invalid Explore location sharing'
            USING ERRCODE = '22023';
    END IF;

    IF p_media_rows IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_media_rows) <> 'array' THEN
        RAISE EXCEPTION 'Explore media must be an array'
            USING ERRCODE = '22023';
    END IF;

    v_media_count := pg_catalog.JSONB_ARRAY_LENGTH(p_media_rows);
    IF v_media_count < 1 OR v_media_count > 6 THEN
        RAISE EXCEPTION 'Explore media count is outside the supported range'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.CARDINALITY(v_hashtags) > 5 THEN
        RAISE EXCEPTION 'Explore hashtag count is outside the supported range'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag)
        WHERE hashtag.tag IS NULL
           OR hashtag.tag !~ '^[a-z0-9][a-z0-9_]{1,39}$'
    ) THEN
        RAISE EXCEPTION 'Invalid Explore hashtag'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(DISTINCT hashtag.tag)::INTEGER
    INTO v_distinct_hashtag_count
    FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag);

    IF v_distinct_hashtag_count <> pg_catalog.CARDINALITY(v_hashtags) THEN
        RAISE EXCEPTION 'Duplicate Explore hashtags are not permitted'
            USING ERRCODE = '22023';
    END IF;

    -- The resolved-community publisher locks this row before updating scans.
    -- Preserve that request -> scan order here so concurrent consensus and
    -- publication work cannot form a scan -> request deadlock cycle. A scan
    -- can have at most one request because explore_posts.scan_id and
    -- explore_community_requests.post_id are both unique.
    SELECT community_request.status
    INTO v_community_request_status
    FROM public.explore_community_requests AS community_request
    WHERE community_request.scan_id = p_scan_id
      AND community_request.requested_by = p_user_id
    FOR UPDATE OF community_request;

    IF v_community_request_status = 'needs_id' THEN
        RAISE EXCEPTION 'Wait for the community to identify this request before sharing it to Explore.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT
        COALESCE(scan.image_storage_urls, ARRAY[]::TEXT[]),
        COALESCE(scan.video_storage_urls, ARRAY[]::TEXT[]),
        COALESCE(scan.audio_storage_urls, ARRAY[]::TEXT[]),
        scan.geoprivacy::TEXT
    INTO
        v_image_urls,
        v_video_urls,
        v_audio_urls,
        v_scan_geoprivacy
    FROM public.scans AS scan
    WHERE scan.id = p_scan_id
      AND scan.user_id = p_user_id
      AND NOT scan.is_tombstoned
      AND (
          scan.confirmed_species_id IS NOT NULL
          OR scan.species_id IS NOT NULL
      )
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Owned share-eligible scan not found'
            USING ERRCODE = 'P0001';
    END IF;

    -- Backward-compatible clients may omit a post-owned privacy choice. Resolve
    -- that default from the scan only after taking the owner-row lock so a
    -- concurrent privacy change cannot publish with a stale geoprivacy value.
    v_location_sharing :=
        COALESCE(p_location_sharing, v_scan_geoprivacy);
    IF v_location_sharing NOT IN ('open', 'obscured', 'private') THEN
        RAISE EXCEPTION 'Invalid locked scan geoprivacy'
            USING ERRCODE = '22023';
    END IF;

    FOR v_media_item IN
        SELECT media.item
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_media_rows) AS media(item)
    LOOP
        IF pg_catalog.JSONB_TYPEOF(v_media_item) <> 'object'
           OR NOT (
               v_media_item ?& ARRAY[
                   'kind',
                   'url',
                   'thumbnail_url',
                   'order_index',
                   'duration_seconds',
                   'has_audio'
               ]
           )
           OR (
               v_media_item - ARRAY[
                   'kind',
                   'url',
                   'thumbnail_url',
                   'order_index',
                   'duration_seconds',
                   'has_audio'
               ]
           ) <> '{}'::JSONB THEN
            RAISE EXCEPTION 'Invalid Explore media object shape'
                USING ERRCODE = '22023';
        END IF;

        IF pg_catalog.JSONB_TYPEOF(v_media_item -> 'kind') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'url') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'thumbnail_url') <> 'string'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'order_index') <> 'number'
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'duration_seconds')
                NOT IN ('number', 'null')
           OR pg_catalog.JSONB_TYPEOF(v_media_item -> 'has_audio') <> 'boolean' THEN
            RAISE EXCEPTION 'Invalid Explore media value types'
                USING ERRCODE = '22023';
        END IF;

        v_media_kind := v_media_item ->> 'kind';
        v_media_url := pg_catalog.BTRIM(v_media_item ->> 'url');
        v_media_thumbnail_url :=
            pg_catalog.BTRIM(v_media_item ->> 'thumbnail_url');
        v_media_order := (v_media_item ->> 'order_index')::NUMERIC;

        IF v_media_kind NOT IN ('image', 'video', 'audio')
           OR v_media_url = ''
           OR pg_catalog.CHAR_LENGTH(v_media_url) > 4096
           OR pg_catalog.CHAR_LENGTH(v_media_thumbnail_url) > 4096
           OR v_media_order <> pg_catalog.TRUNC(v_media_order)
           OR v_media_order < 0
           OR v_media_order >= v_media_count
           OR (
               pg_catalog.JSONB_TYPEOF(
                   v_media_item -> 'duration_seconds'
               ) = 'number'
               AND (v_media_item ->> 'duration_seconds')::NUMERIC < 0
           ) THEN
            RAISE EXCEPTION 'Invalid Explore media values'
                USING ERRCODE = '22023';
        END IF;

        IF v_media_kind = 'image'
           AND (
               v_media_thumbnail_url <> v_media_url
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_image_urls)
                       AS source_image(url)
                   WHERE pg_catalog.BTRIM(source_image.url) = v_media_url
               )
               OR (v_media_item ->> 'has_audio')::BOOLEAN
           ) THEN
            RAISE EXCEPTION 'Explore image does not belong to the scan'
                USING ERRCODE = '22023';
        ELSIF v_media_kind = 'video'
           AND (
               v_media_thumbnail_url = ''
               OR v_media_thumbnail_url = v_media_url
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_video_urls)
                       AS source_video(url)
                   WHERE pg_catalog.BTRIM(source_video.url) = v_media_url
               )
               OR NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_image_urls)
                       AS source_thumbnail(url)
                   WHERE pg_catalog.BTRIM(source_thumbnail.url) =
                       v_media_thumbnail_url
               )
           ) THEN
            RAISE EXCEPTION 'Explore video does not belong to the scan'
                USING ERRCODE = '22023';
        ELSIF v_media_kind = 'audio'
           AND (
               NOT EXISTS (
                   SELECT 1
                   FROM pg_catalog.UNNEST(v_audio_urls)
                       AS source_audio(url)
                   WHERE pg_catalog.BTRIM(source_audio.url) = v_media_url
               )
               OR NOT (v_media_item ->> 'has_audio')::BOOLEAN
           ) THEN
            RAISE EXCEPTION 'Explore audio does not belong to the scan'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;

    SELECT pg_catalog.COUNT(
        DISTINCT (media.item ->> 'order_index')::INTEGER
    )::INTEGER
    INTO v_distinct_order_count
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_media_rows) AS media(item);

    IF v_distinct_order_count <> v_media_count THEN
        RAISE EXCEPTION 'Explore media order must be unique and contiguous'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.explore_posts AS existing (
        scan_id,
        user_id,
        species_common_name,
        field_notes,
        location_sharing,
        shared_at,
        unshared_at
    )
    VALUES (
        p_scan_id,
        p_user_id,
        p_species_common_name,
        p_field_notes,
        v_location_sharing,
        v_shared_at,
        NULL
    )
    ON CONFLICT (scan_id) DO UPDATE
    SET species_common_name = EXCLUDED.species_common_name,
        field_notes = EXCLUDED.field_notes,
        location_sharing = EXCLUDED.location_sharing,
        shared_at = EXCLUDED.shared_at,
        unshared_at = NULL
    WHERE existing.user_id = EXCLUDED.user_id
    RETURNING existing.id, existing.shared_at
    INTO v_post_id, v_shared_at;

    IF v_post_id IS NULL THEN
        RAISE EXCEPTION 'Explore post ownership does not match the scan'
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.explore_post_media AS media
    WHERE media.post_id = v_post_id;

    INSERT INTO public.explore_post_media (
        post_id,
        kind,
        url,
        thumbnail_url,
        order_index,
        duration_seconds,
        has_audio
    )
    SELECT
        v_post_id,
        media.kind,
        pg_catalog.BTRIM(media.url),
        pg_catalog.BTRIM(media.thumbnail_url),
        media.order_index,
        media.duration_seconds,
        media.has_audio
    FROM pg_catalog.JSONB_TO_RECORDSET(p_media_rows) AS media(
        kind TEXT,
        url TEXT,
        thumbnail_url TEXT,
        order_index INTEGER,
        duration_seconds DOUBLE PRECISION,
        has_audio BOOLEAN
    );

    DELETE FROM public.explore_post_hashtags AS hashtag
    WHERE hashtag.post_id = v_post_id;

    INSERT INTO public.explore_post_hashtags (
        post_id,
        tag
    )
    SELECT
        v_post_id,
        hashtag.tag
    FROM pg_catalog.UNNEST(v_hashtags) AS hashtag(tag);

    PERFORM public.publish_resolved_community_request_to_explore(
        v_post_id,
        p_user_id
    );

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'post_id', v_post_id,
        'shared_at', v_shared_at,
        'location_sharing', v_location_sharing,
        'publication_status', 'published'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.publish_scan_to_explore_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.publish_scan_to_explore_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    TEXT[]
) TO service_role;

COMMENT ON FUNCTION public.publish_scan_to_explore_atomically(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    JSONB,
    TEXT[]
) IS
    'Service-only owner-checked transaction that replaces an Explore post, media snapshot, hashtags, and resolved-community publication state together.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

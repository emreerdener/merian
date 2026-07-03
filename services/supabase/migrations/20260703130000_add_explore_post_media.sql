CREATE TABLE IF NOT EXISTS public.explore_post_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'video')),
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    order_index INTEGER NOT NULL CHECK (order_index >= 0),
    duration_seconds DOUBLE PRECISION,
    has_audio BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (post_id, kind, url),
    UNIQUE (post_id, order_index)
);

CREATE INDEX IF NOT EXISTS idx_explore_post_media_post_order
    ON public.explore_post_media(post_id, order_index);

ALTER TABLE public.explore_post_media ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own explore post media" ON public.explore_post_media;
CREATE POLICY "Users can read their own explore post media"
    ON public.explore_post_media
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.explore_posts ep
            WHERE ep.id = explore_post_media.post_id
              AND ep.user_id = auth.uid()
        )
    );

COMMENT ON TABLE public.explore_post_media IS
  'Post-owned public media snapshot for Explore posts, including still images and short videos.';

COMMENT ON COLUMN public.explore_post_media.thumbnail_url IS
  'Image URL used for compact surfaces and video poster frames.';

CREATE OR REPLACE FUNCTION public.explore_post_media_items(target_post_id UUID)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'kind', epm.kind,
                'url', epm.url,
                'thumbnail_url', epm.thumbnail_url,
                'order_index', epm.order_index,
                'duration_seconds', epm.duration_seconds,
                'has_audio', epm.has_audio
            )
            ORDER BY epm.order_index, epm.created_at, epm.id
        ),
        '[]'::JSONB
    )
    FROM public.explore_post_media epm
    WHERE epm.post_id = target_post_id;
$$;

CREATE OR REPLACE FUNCTION public.explore_post_hero_image_url(target_post_id UUID)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT NULLIF(BTRIM(epm.thumbnail_url), '')
            FROM public.explore_post_media epm
            WHERE epm.post_id = target_post_id
              AND NULLIF(BTRIM(COALESCE(epm.thumbnail_url, '')), '') IS NOT NULL
            ORDER BY epm.order_index, epm.created_at, epm.id
            LIMIT 1
        ),
        (
            SELECT NULLIF(BTRIM(epm.url), '')
            FROM public.explore_post_media epm
            WHERE epm.post_id = target_post_id
              AND epm.kind = 'image'
              AND NULLIF(BTRIM(epm.url), '') IS NOT NULL
            ORDER BY epm.order_index, epm.created_at, epm.id
            LIMIT 1
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.refresh_explore_post_media(target_post_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    image_urls TEXT[];
    video_urls TEXT[];
    hero_thumbnail_url TEXT;
BEGIN
    SELECT
        s.image_storage_urls,
        s.video_storage_urls
    INTO scan_row
    FROM public.explore_posts ep
    JOIN public.scans s
      ON s.id = ep.scan_id
    WHERE ep.id = target_post_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Explore post not found.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT COALESCE(ARRAY_AGG(NULLIF(BTRIM(image_url), '') ORDER BY ordinality), ARRAY[]::TEXT[])
    INTO image_urls
    FROM UNNEST(COALESCE(scan_row.image_storage_urls, ARRAY[]::TEXT[])) WITH ORDINALITY AS images(image_url, ordinality)
    WHERE NULLIF(BTRIM(image_url), '') IS NOT NULL;

    SELECT COALESCE(ARRAY_AGG(NULLIF(BTRIM(video_url), '') ORDER BY ordinality), ARRAY[]::TEXT[])
    INTO video_urls
    FROM UNNEST(COALESCE(scan_row.video_storage_urls, ARRAY[]::TEXT[])) WITH ORDINALITY AS videos(video_url, ordinality)
    WHERE NULLIF(BTRIM(video_url), '') IS NOT NULL;

    hero_thumbnail_url := image_urls[1];

    IF COALESCE(ARRAY_LENGTH(video_urls, 1), 0) > 0
       AND NULLIF(BTRIM(COALESCE(hero_thumbnail_url, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Video thumbnail unavailable.'
            USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(ARRAY_LENGTH(image_urls, 1), 0) = 0
       AND COALESCE(ARRAY_LENGTH(video_urls, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Explore post has no public media.'
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM public.explore_post_media
    WHERE post_id = target_post_id;

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
        target_post_id,
        'video',
        video_url,
        hero_thumbnail_url,
        ordinality::INTEGER - 1,
        NULL::DOUBLE PRECISION,
        TRUE
    FROM UNNEST(video_urls) WITH ORDINALITY AS videos(video_url, ordinality)
    WHERE NULLIF(BTRIM(video_url), '') IS NOT NULL;

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
        target_post_id,
        'image',
        image_url,
        image_url,
        (COALESCE(ARRAY_LENGTH(video_urls, 1), 0) + ordinality - 1)::INTEGER,
        NULL::DOUBLE PRECISION,
        FALSE
    FROM UNNEST(image_urls) WITH ORDINALITY AS images(image_url, ordinality)
    WHERE NULLIF(BTRIM(image_url), '') IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_all_explore_post_media()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    post_row RECORD;
BEGIN
    FOR post_row IN SELECT id FROM public.explore_posts LOOP
        BEGIN
            PERFORM public.refresh_explore_post_media(post_row.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skipping Explore media snapshot for post %: %', post_row.id, SQLERRM;
        END;
    END LOOP;
END;
$$;

SELECT public.refresh_all_explore_post_media();

DROP FUNCTION IF EXISTS public.explore_projected_post_cards(UUID);

CREATE OR REPLACE FUNCTION public.explore_projected_post_cards(viewer_id UUID)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
    public_latitude DOUBLE PRECISION,
    public_longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    media_items JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        public.explore_post_hero_image_url(ep.id) AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        public.explore_post_community_common_name(
            CASE WHEN eop.projection_state = 'community_resolved' THEN 'resolved' ELSE NULL END,
            community_taxon.common_name,
            community_taxon.scientific_name,
            ep.species_common_name,
            sd.common_names,
            sd.scientific_name
        ) AS species_common_name,
        public.explore_post_community_scientific_name(
            CASE WHEN eop.projection_state = 'community_resolved' THEN 'resolved' ELSE NULL END,
            community_taxon.scientific_name,
            sd.scientific_name
        ) AS species_scientific_name,
        s.pet_identification,
        ep.public_location_label,
        ep.location_sharing,
        ep.public_latitude,
        ep.public_longitude,
        ep.public_coordinate_visibility AS coordinate_visibility,
        s.time_of_day,
        s.current_month,
        s.weather_condition,
        s.weather_temperature_f,
        ep.like_count,
        ep.comment_count,
        EXISTS (
            SELECT 1
            FROM public.explore_post_likes epl
            WHERE epl.post_id = ep.id
              AND epl.user_id = viewer_id
        ) AS viewer_has_liked,
        (ep.user_id = viewer_id) AS is_owned_by_viewer,
        public.explore_post_media_items(ep.id) AS media_items
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id
    WHERE ep.unshared_at IS NULL
      AND COALESCE(eop.projection_state::TEXT, 'normal') <> 'community_needs_id'
      AND s.is_tombstoned = FALSE
      AND EXISTS (
          SELECT 1
          FROM public.explore_post_media epm
          WHERE epm.post_id = ep.id
      )
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = viewer_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = viewer_id)
      );
$$;

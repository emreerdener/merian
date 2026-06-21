ALTER TABLE public.explore_community_requests
ADD COLUMN IF NOT EXISTS explore_published_at TIMESTAMPTZ;

DROP FUNCTION IF EXISTS public.get_scan_explore_share_state(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_scan_explore_share_state(
    self_id UUID,
    target_scan_id UUID
)
RETURNS TABLE(
    scan_id UUID,
    post_id UUID,
    shared_at TIMESTAMPTZ,
    community_request_id UUID,
    community_request_status TEXT,
    is_explore_feed_visible BOOLEAN,
    location_sharing TEXT
)
LANGUAGE SQL
STABLE
AS $$
    WITH state AS (
        SELECT
            s.id AS scan_id,
            ep.id AS post_id,
            ep.shared_at,
            ep.location_sharing AS post_location_sharing,
            ecr.id AS community_request_id,
            ecr.status AS community_request_status,
            ecr.explore_published_at,
            s.geoprivacy::TEXT AS scan_geoprivacy,
            (
                ep.id IS NOT NULL
                AND s.is_tombstoned = FALSE
                AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
                AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
                AND u.is_shadowbanned = FALSE
            ) AS has_live_post
        FROM public.scans s
        JOIN public.users u
            ON u.id = s.user_id
        LEFT JOIN LATERAL (
            SELECT
                id,
                shared_at,
                location_sharing
            FROM public.explore_posts
            WHERE scan_id = s.id
              AND user_id = self_id
              AND unshared_at IS NULL
            ORDER BY shared_at DESC NULLS LAST, id DESC
            LIMIT 1
        ) ep
            ON TRUE
        LEFT JOIN LATERAL (
            SELECT
                id,
                status,
                explore_published_at
            FROM public.explore_community_requests
            WHERE post_id = ep.id
              AND requested_by = self_id
              AND status <> 'withdrawn'
            ORDER BY requested_at DESC, id DESC
            LIMIT 1
        ) ecr
            ON TRUE
        WHERE s.id = target_scan_id
          AND s.user_id = self_id
        LIMIT 1
    )
    SELECT
        scan_id,
        CASE WHEN has_live_post THEN post_id ELSE NULL END AS post_id,
        CASE WHEN has_live_post THEN shared_at ELSE NULL END AS shared_at,
        CASE WHEN has_live_post THEN community_request_id ELSE NULL END AS community_request_id,
        CASE WHEN has_live_post THEN community_request_status::TEXT ELSE NULL END AS community_request_status,
        (
            has_live_post
            AND (
                community_request_id IS NULL
                OR community_request_status = 'withdrawn'
                OR (
                    community_request_status = 'resolved'
                    AND explore_published_at IS NOT NULL
                )
            )
        ) AS is_explore_feed_visible,
        CASE WHEN has_live_post THEN post_location_sharing ELSE scan_geoprivacy END AS location_sharing
    FROM state;
$$;

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
    is_owned_by_viewer BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
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
        (ep.user_id = viewer_id) AS is_owned_by_viewer
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    LEFT JOIN public.explore_observation_projection eop
        ON eop.post_id = ep.id
    LEFT JOIN public.explore_community_requests ecr
        ON ecr.id = eop.community_request_id
    LEFT JOIN public.taxon_nodes community_taxon
        ON community_taxon.id = eop.public_taxon_node_id
    WHERE ep.unshared_at IS NULL
      AND (
          eop.projection_state IS NULL
          OR eop.projection_state = 'normal'
          OR eop.projection_state = 'withdrawn'
          OR (
              eop.projection_state = 'community_resolved'
              AND ecr.explore_published_at IS NOT NULL
          )
      )
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = viewer_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = viewer_id)
      );
$$;

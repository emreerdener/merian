CREATE INDEX IF NOT EXISTS idx_explore_post_likes_created_at_post_id
    ON public.explore_post_likes(created_at DESC, post_id);

CREATE OR REPLACE FUNCTION public.haversine_distance_meters(
    latitude_a DOUBLE PRECISION,
    longitude_a DOUBLE PRECISION,
    latitude_b DOUBLE PRECISION,
    longitude_b DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT 6371000.0 * 2.0 * ASIN(
        LEAST(
            1.0,
            SQRT(
                POWER(SIN(RADIANS((latitude_b - latitude_a) / 2.0)), 2)
                + COS(RADIANS(latitude_a))
                * COS(RADIANS(latitude_b))
                * POWER(SIN(RADIANS((longitude_b - longitude_a) / 2.0)), 2)
            )
        )
    )
$$;

DROP FUNCTION IF EXISTS public.get_explore_feed(UUID, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed_trending(UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID);
DROP FUNCTION IF EXISTS public.get_explore_feed_nearby(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
)
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
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    ranking_value INTEGER
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
        COALESCE(NULLIF(sd.common_names->>'en', ''), sd.scientific_name, 'Unknown Subject') AS species_common_name,
        COALESCE(sd.scientific_name, 'Unknown Subject') AS species_scientific_name,
        public.sanitize_explore_location(s.semantic_location) AS public_location_label,
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
              AND epl.user_id = self_id
        ) AS viewer_has_liked,
        (ep.user_id = self_id) AS is_owned_by_viewer,
        NULL::INTEGER AS ranking_value
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR ep.shared_at < before_shared_at
          OR (ep.shared_at = before_shared_at AND ep.id < before_post_id)
      )
    ORDER BY ep.shared_at DESC, ep.id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_trending(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_ranking_value INTEGER DEFAULT NULL,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
)
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
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    ranking_value INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    WITH recent_likes AS (
        SELECT
            epl.post_id,
            COUNT(*)::INTEGER AS ranking_value
        FROM public.explore_post_likes epl
        WHERE epl.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY epl.post_id
    )
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        COALESCE(NULLIF(sd.common_names->>'en', ''), sd.scientific_name, 'Unknown Subject') AS species_common_name,
        COALESCE(sd.scientific_name, 'Unknown Subject') AS species_scientific_name,
        public.sanitize_explore_location(s.semantic_location) AS public_location_label,
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
              AND epl.user_id = self_id
        ) AS viewer_has_liked,
        (ep.user_id = self_id) AS is_owned_by_viewer,
        COALESCE(recent_likes.ranking_value, 0) AS ranking_value
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    LEFT JOIN recent_likes
        ON recent_likes.post_id = ep.id
    WHERE ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
      AND (
          before_ranking_value IS NULL
          OR before_shared_at IS NULL
          OR before_post_id IS NULL
          OR COALESCE(recent_likes.ranking_value, 0) < before_ranking_value
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND ep.shared_at < before_shared_at
          )
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND ep.shared_at = before_shared_at
              AND ep.id < before_post_id
          )
      )
    ORDER BY COALESCE(recent_likes.ranking_value, 0) DESC, ep.shared_at DESC, ep.id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_nearby(
    self_id UUID,
    viewer_latitude DOUBLE PRECISION,
    viewer_longitude DOUBLE PRECISION,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL
)
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
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    ranking_value INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    WITH search_window AS (
        SELECT
            80467.2::DOUBLE PRECISION AS radius_meters,
            80467.2 / 111320.0 AS latitude_delta,
            80467.2 / GREATEST(ABS(COS(RADIANS(viewer_latitude))) * 111320.0, 1000.0) AS longitude_delta
    ),
    projected_posts AS (
        SELECT
            ep.id AS post_id,
            ep.scan_id,
            public.derive_public_scan_coordinate(
                s.gps_lat_exact,
                s.gps_lat_public,
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) AS latitude,
            public.derive_public_scan_coordinate(
                s.gps_long_exact,
                s.gps_long_public,
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) AS longitude,
            s.image_storage_urls[1] AS hero_image_url,
            ep.shared_at,
            ep.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_avatar_url AS author_avatar_url,
            COALESCE(NULLIF(sd.common_names->>'en', ''), sd.scientific_name, 'Unknown Subject') AS species_common_name,
            COALESCE(sd.scientific_name, 'Unknown Subject') AS species_scientific_name,
            public.sanitize_explore_location(s.semantic_location) AS public_location_label,
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
                  AND epl.user_id = self_id
            ) AS viewer_has_liked,
            (ep.user_id = self_id) AS is_owned_by_viewer
        FROM public.explore_posts ep
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users u
            ON u.id = ep.user_id
        LEFT JOIN public.species_dictionary sd
            ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
        WHERE ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
          AND s.geoprivacy <> 'private'
          AND u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
          )
    ),
    bounded_posts AS (
        SELECT
            projected_posts.*,
            search_window.radius_meters,
            public.haversine_distance_meters(
                projected_posts.latitude,
                projected_posts.longitude,
                viewer_latitude,
                viewer_longitude
            ) AS distance_meters
        FROM projected_posts
        CROSS JOIN search_window
        WHERE projected_posts.latitude IS NOT NULL
          AND projected_posts.longitude IS NOT NULL
          AND projected_posts.latitude BETWEEN viewer_latitude - search_window.latitude_delta AND viewer_latitude + search_window.latitude_delta
          AND (
              (
                  viewer_longitude - search_window.longitude_delta >= -180
                  AND viewer_longitude + search_window.longitude_delta <= 180
                  AND projected_posts.longitude BETWEEN viewer_longitude - search_window.longitude_delta
                      AND viewer_longitude + search_window.longitude_delta
              )
              OR (
                  viewer_longitude - search_window.longitude_delta < -180
                  AND (
                      projected_posts.longitude >= viewer_longitude - search_window.longitude_delta + 360
                      OR projected_posts.longitude <= viewer_longitude + search_window.longitude_delta
                  )
              )
              OR (
                  viewer_longitude + search_window.longitude_delta > 180
                  AND (
                      projected_posts.longitude >= viewer_longitude - search_window.longitude_delta
                      OR projected_posts.longitude <= viewer_longitude + search_window.longitude_delta - 360
                  )
              )
          )
    )
    SELECT
        post_id,
        scan_id,
        hero_image_url,
        shared_at,
        author_user_id,
        author_name,
        author_avatar_url,
        species_common_name,
        species_scientific_name,
        public_location_label,
        time_of_day,
        current_month,
        weather_condition,
        weather_temperature_f,
        like_count,
        comment_count,
        viewer_has_liked,
        is_owned_by_viewer,
        NULL::INTEGER AS ranking_value
    FROM bounded_posts
    WHERE distance_meters <= radius_meters
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR shared_at < before_shared_at
          OR (shared_at = before_shared_at AND post_id < before_post_id)
      )
    ORDER BY shared_at DESC, post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

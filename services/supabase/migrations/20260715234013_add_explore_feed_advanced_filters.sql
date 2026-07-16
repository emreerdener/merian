-- Add one durable advanced-filter contract to every cursor-paginated Explore
-- feed mode. Filters are applied before ORDER BY/LIMIT so pagination never
-- drops matching posts or returns sparse client-filtered pages.

CREATE OR REPLACE FUNCTION public.explore_feed_species_category(
    taxonomy_kingdom TEXT,
    taxonomy_class TEXT
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN LOWER(BTRIM(COALESCE(taxonomy_kingdom, ''))) = 'plantae' THEN 'plants'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_kingdom, ''))) = 'fungi' THEN 'fungi'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) = 'aves' THEN 'birds'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) = 'mammalia' THEN 'mammals'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) IN ('reptilia', 'squamata') THEN 'reptiles'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) = 'amphibia' THEN 'amphibians'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) IN (
            'actinopterygii',
            'chondrichthyes',
            'sarcopterygii'
        ) THEN 'fish'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) IN ('insecta', 'entognatha') THEN 'insects'
        WHEN LOWER(BTRIM(COALESCE(taxonomy_class, ''))) = 'arachnida' THEN 'arachnids'
        ELSE 'other'
    END;
$$;

DROP FUNCTION IF EXISTS public.get_explore_feed(UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE FUNCTION public.get_explore_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL,
    requested_species_categories TEXT[] DEFAULT '{}'::TEXT[],
    requested_media_types TEXT[] DEFAULT '{}'::TEXT[],
    shared_since TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    reference_thumbnail_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    ranking_value INTEGER,
    media_items JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            COALESCE(scan.confirmed_species_id, scan.species_id),
            species.reference_image_url
        ) AS reference_thumbnail_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer,
        NULL::INTEGER AS ranking_value,
        cards.media_items
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
      AND (
          COALESCE(CARDINALITY(requested_species_categories), 0) = 0
          OR public.explore_feed_species_category(species.kingdom, species."class")
              = ANY(requested_species_categories)
      )
      AND (
          COALESCE(CARDINALITY(requested_media_types), 0) = 0
          OR EXISTS (
              SELECT 1
              FROM public.explore_post_media filtered_media
              WHERE filtered_media.post_id = cards.post_id
                AND filtered_media.kind = ANY(requested_media_types)
          )
      )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

DROP FUNCTION IF EXISTS public.get_explore_feed_following(UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE FUNCTION public.get_explore_feed_following(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL,
    requested_species_categories TEXT[] DEFAULT '{}'::TEXT[],
    requested_media_types TEXT[] DEFAULT '{}'::TEXT[],
    shared_since TIMESTAMPTZ DEFAULT NULL
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
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
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
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer,
        NULL::INTEGER AS ranking_value
    FROM public.user_follows follows
    JOIN public.explore_projected_post_cards(self_id) cards
        ON cards.author_user_id = follows.followee_user_id
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    WHERE follows.follower_user_id = self_id
      AND (shared_since IS NULL OR cards.shared_at >= shared_since)
      AND (
          COALESCE(CARDINALITY(requested_species_categories), 0) = 0
          OR public.explore_feed_species_category(species.kingdom, species."class")
              = ANY(requested_species_categories)
      )
      AND (
          COALESCE(CARDINALITY(requested_media_types), 0) = 0
          OR EXISTS (
              SELECT 1
              FROM public.explore_post_media filtered_media
              WHERE filtered_media.post_id = cards.post_id
                AND filtered_media.kind = ANY(requested_media_types)
          )
      )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR cards.shared_at < before_shared_at
          OR (cards.shared_at = before_shared_at AND cards.post_id < before_post_id)
      )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

DROP FUNCTION IF EXISTS public.get_explore_feed_trending(
    UUID,
    INTEGER,
    INTEGER,
    TIMESTAMPTZ,
    UUID
);

CREATE FUNCTION public.get_explore_feed_trending(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_ranking_value INTEGER DEFAULT NULL,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL,
    requested_species_categories TEXT[] DEFAULT '{}'::TEXT[],
    requested_media_types TEXT[] DEFAULT '{}'::TEXT[],
    shared_since TIMESTAMPTZ DEFAULT NULL
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
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
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
        SELECT likes.post_id, COUNT(*)::INTEGER AS ranking_value
        FROM public.explore_post_likes likes
        WHERE likes.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY likes.post_id
    )
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer,
        COALESCE(recent_likes.ranking_value, 0) AS ranking_value
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans scan
        ON scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary species
        ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
    LEFT JOIN recent_likes
        ON recent_likes.post_id = cards.post_id
    WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
      AND (
          COALESCE(CARDINALITY(requested_species_categories), 0) = 0
          OR public.explore_feed_species_category(species.kingdom, species."class")
              = ANY(requested_species_categories)
      )
      AND (
          COALESCE(CARDINALITY(requested_media_types), 0) = 0
          OR EXISTS (
              SELECT 1
              FROM public.explore_post_media filtered_media
              WHERE filtered_media.post_id = cards.post_id
                AND filtered_media.kind = ANY(requested_media_types)
          )
      )
      AND (
          before_ranking_value IS NULL
          OR before_shared_at IS NULL
          OR before_post_id IS NULL
          OR COALESCE(recent_likes.ranking_value, 0) < before_ranking_value
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND cards.shared_at < before_shared_at
          )
          OR (
              COALESCE(recent_likes.ranking_value, 0) = before_ranking_value
              AND cards.shared_at = before_shared_at
              AND cards.post_id < before_post_id
          )
      )
    ORDER BY
        COALESCE(recent_likes.ranking_value, 0) DESC,
        cards.shared_at DESC,
        cards.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

DROP FUNCTION IF EXISTS public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID
);

CREATE FUNCTION public.get_explore_feed_nearby(
    self_id UUID,
    viewer_latitude DOUBLE PRECISION,
    viewer_longitude DOUBLE PRECISION,
    max_limit INTEGER DEFAULT 20,
    before_shared_at TIMESTAMPTZ DEFAULT NULL,
    before_post_id UUID DEFAULT NULL,
    nearby_radius_miles DOUBLE PRECISION DEFAULT 50,
    requested_species_categories TEXT[] DEFAULT '{}'::TEXT[],
    requested_media_types TEXT[] DEFAULT '{}'::TEXT[],
    shared_since TIMESTAMPTZ DEFAULT NULL
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
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
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
            LEAST(GREATEST(COALESCE(nearby_radius_miles, 50), 1), 100)
                * 1609.344 AS radius_meters
    ),
    search_bounds AS (
        SELECT
            search_window.radius_meters,
            search_window.radius_meters / 111320.0 AS latitude_delta,
            search_window.radius_meters
                / GREATEST(
                    ABS(COS(RADIANS(viewer_latitude))) * 111320.0,
                    1000.0
                ) AS longitude_delta
        FROM search_window
    ),
    bounded_posts AS (
        SELECT
            cards.*,
            search_bounds.radius_meters,
            public.haversine_distance_meters(
                cards.public_latitude,
                cards.public_longitude,
                viewer_latitude,
                viewer_longitude
            ) AS distance_meters
        FROM public.explore_projected_post_cards(self_id) cards
        JOIN public.scans scan
            ON scan.id = cards.scan_id
        LEFT JOIN public.species_dictionary species
            ON species.id = COALESCE(scan.confirmed_species_id, scan.species_id)
        CROSS JOIN search_bounds
        WHERE (shared_since IS NULL OR cards.shared_at >= shared_since)
          AND (
              COALESCE(CARDINALITY(requested_species_categories), 0) = 0
              OR public.explore_feed_species_category(species.kingdom, species."class")
                  = ANY(requested_species_categories)
          )
          AND (
              COALESCE(CARDINALITY(requested_media_types), 0) = 0
              OR EXISTS (
                  SELECT 1
                  FROM public.explore_post_media filtered_media
                  WHERE filtered_media.post_id = cards.post_id
                    AND filtered_media.kind = ANY(requested_media_types)
              )
          )
          AND (
              cards.author_user_id = self_id
              OR (
                  cards.location_sharing = 'open'
                  AND cards.public_latitude IS NOT NULL
                  AND cards.public_longitude IS NOT NULL
                  AND cards.public_latitude BETWEEN
                      viewer_latitude - search_bounds.latitude_delta
                      AND viewer_latitude + search_bounds.latitude_delta
                  AND (
                      (
                          viewer_longitude - search_bounds.longitude_delta >= -180
                          AND viewer_longitude + search_bounds.longitude_delta <= 180
                          AND cards.public_longitude BETWEEN
                              viewer_longitude - search_bounds.longitude_delta
                              AND viewer_longitude + search_bounds.longitude_delta
                      )
                      OR (
                          viewer_longitude - search_bounds.longitude_delta < -180
                          AND (
                              cards.public_longitude >=
                                  viewer_longitude - search_bounds.longitude_delta + 360
                              OR cards.public_longitude <=
                                  viewer_longitude + search_bounds.longitude_delta
                          )
                      )
                      OR (
                          viewer_longitude + search_bounds.longitude_delta > 180
                          AND (
                              cards.public_longitude >=
                                  viewer_longitude - search_bounds.longitude_delta
                              OR cards.public_longitude <=
                                  viewer_longitude + search_bounds.longitude_delta - 360
                          )
                      )
                  )
              )
          )
    )
    SELECT
        bounded_posts.post_id,
        bounded_posts.scan_id,
        bounded_posts.hero_image_url,
        bounded_posts.shared_at,
        bounded_posts.author_user_id,
        bounded_posts.author_name,
        bounded_posts.author_avatar_url,
        bounded_posts.species_common_name,
        bounded_posts.species_scientific_name,
        bounded_posts.pet_identification,
        bounded_posts.public_location_label,
        bounded_posts.location_sharing,
        bounded_posts.time_of_day,
        bounded_posts.current_month,
        bounded_posts.weather_condition,
        bounded_posts.weather_temperature_f,
        bounded_posts.like_count,
        bounded_posts.comment_count,
        bounded_posts.viewer_has_liked,
        bounded_posts.is_owned_by_viewer,
        NULL::INTEGER AS ranking_value
    FROM bounded_posts
    WHERE (
        bounded_posts.distance_meters <= bounded_posts.radius_meters
        OR bounded_posts.author_user_id = self_id
    )
      AND (
          before_shared_at IS NULL
          OR before_post_id IS NULL
          OR bounded_posts.shared_at < before_shared_at
          OR (
              bounded_posts.shared_at = before_shared_at
              AND bounded_posts.post_id < before_post_id
          )
      )
    ORDER BY bounded_posts.shared_at DESC, bounded_posts.post_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
$$;

REVOKE ALL ON FUNCTION public.explore_feed_species_category(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.explore_feed_species_category(TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.explore_feed_species_category(TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.explore_feed_species_category(TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.get_explore_feed(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_feed(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_feed(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_feed(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) TO service_role;

REVOKE ALL ON FUNCTION public.get_explore_feed_following(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_feed_following(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_feed_following(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_following(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) TO service_role;

REVOKE ALL ON FUNCTION public.get_explore_feed_trending(
    UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_feed_trending(
    UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_feed_trending(
    UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_trending(
    UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) TO service_role;

REVOKE ALL ON FUNCTION public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    TEXT[],
    TEXT[],
    TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    TEXT[],
    TEXT[],
    TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    TEXT[],
    TEXT[],
    TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    TEXT[],
    TEXT[],
    TIMESTAMPTZ
) TO service_role;

COMMENT ON FUNCTION public.explore_feed_species_category(TEXT, TEXT) IS
  'Maps Explore taxonomy to the shared plants/fungi/vertebrate/arthropod feed and map categories.';
COMMENT ON FUNCTION public.get_explore_feed(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) IS 'Returns the recent Explore feed with server-side species, media, and shared-date filters.';
COMMENT ON FUNCTION public.get_explore_feed_following(
    UUID, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) IS 'Returns followed-author Explore posts with server-side advanced filters.';
COMMENT ON FUNCTION public.get_explore_feed_trending(
    UUID, INTEGER, INTEGER, TIMESTAMPTZ, UUID, TEXT[], TEXT[], TIMESTAMPTZ
) IS 'Returns ranked Explore posts with filters applied before ranking pagination.';
COMMENT ON FUNCTION public.get_explore_feed_nearby(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    DOUBLE PRECISION,
    TEXT[],
    TEXT[],
    TIMESTAMPTZ
) IS 'Returns radius-bounded Explore posts with server-side advanced filters and cursor pagination.';

NOTIFY pgrst, 'reload schema';

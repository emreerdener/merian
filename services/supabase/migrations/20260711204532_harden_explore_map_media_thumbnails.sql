-- Keep the Explore map compatible with clients that require hero_image_url
-- while exposing a durable species-reference poster for media-only posts.
DROP FUNCTION IF EXISTS public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
);

CREATE FUNCTION public.get_explore_map_posts(
    self_id UUID,
    north_latitude DOUBLE PRECISION,
    south_latitude DOUBLE PRECISION,
    east_longitude DOUBLE PRECISION,
    west_longitude DOUBLE PRECISION,
    max_limit INTEGER DEFAULT 500
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    hero_image_url TEXT,
    reference_thumbnail_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    taxonomy_kingdom TEXT,
    taxonomy_class TEXT,
    public_location_label TEXT,
    location_sharing TEXT,
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
        cards.post_id,
        cards.scan_id,
        cards.public_latitude AS latitude,
        cards.public_longitude AS longitude,
        cards.coordinate_visibility,
        COALESCE(
            NULLIF(BTRIM(cards.hero_image_url), ''),
            public.public_species_first_reference_image_url(
                COALESCE(map_scan.confirmed_species_id, map_scan.species_id),
                sd.reference_image_url
            ),
            ''
        ) AS hero_image_url,
        public.public_species_first_reference_image_url(
            COALESCE(map_scan.confirmed_species_id, map_scan.species_id),
            sd.reference_image_url
        ) AS reference_thumbnail_url,
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        cards.author_avatar_url,
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        sd.kingdom AS taxonomy_kingdom,
        sd."class" AS taxonomy_class,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        cards.like_count,
        cards.comment_count,
        cards.viewer_has_liked,
        cards.is_owned_by_viewer
    FROM public.explore_projected_post_cards(self_id) cards
    JOIN public.scans map_scan
        ON map_scan.id = cards.scan_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(map_scan.confirmed_species_id, map_scan.species_id)
    WHERE cards.location_sharing = 'open'
      AND cards.public_latitude IS NOT NULL
      AND cards.public_longitude IS NOT NULL
      AND cards.public_latitude BETWEEN LEAST(north_latitude, south_latitude)
          AND GREATEST(north_latitude, south_latitude)
      AND (
          (
              west_longitude <= east_longitude
              AND cards.public_longitude BETWEEN west_longitude AND east_longitude
          )
          OR (
              west_longitude > east_longitude
              AND (
                  cards.public_longitude >= west_longitude
                  OR cards.public_longitude <= east_longitude
              )
          )
      )
    ORDER BY cards.shared_at DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 500), 0), 500);
$$;

REVOKE ALL ON FUNCTION public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
) FROM anon;
REVOKE ALL ON FUNCTION public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
) TO service_role;

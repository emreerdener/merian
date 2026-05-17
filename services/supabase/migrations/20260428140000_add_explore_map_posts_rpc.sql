CREATE INDEX IF NOT EXISTS idx_scans_public_coordinates_active
    ON public.scans(gps_lat_public, gps_long_public)
    WHERE gps_lat_public IS NOT NULL
      AND gps_long_public IS NOT NULL
      AND is_tombstoned = FALSE;

CREATE OR REPLACE FUNCTION public.is_explore_location_obscured(
    scan_geoprivacy public.geoprivacy_enum,
    coordinate_uncertainty INTEGER,
    iucn_status TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT
        scan_geoprivacy = 'obscured'
        OR COALESCE(coordinate_uncertainty, 0) >= 1000
        OR COALESCE(iucn_status, '') IN (
            'near_threatened',
            'vulnerable',
            'endangered',
            'critically_endangered'
        );
$$;

CREATE OR REPLACE FUNCTION public.get_explore_map_posts(
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
    is_owned_by_viewer BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        s.gps_lat_public AS latitude,
        s.gps_long_public AS longitude,
        CASE
            WHEN public.is_explore_location_obscured(
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) THEN 'obscured'
            ELSE 'exact'
        END AS coordinate_visibility,
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
      AND s.gps_lat_public IS NOT NULL
      AND s.gps_long_public IS NOT NULL
      AND s.gps_lat_public BETWEEN LEAST(north_latitude, south_latitude) AND GREATEST(north_latitude, south_latitude)
      AND (
          (west_longitude <= east_longitude AND s.gps_long_public BETWEEN west_longitude AND east_longitude)
          OR
          (west_longitude > east_longitude AND (
              s.gps_long_public >= west_longitude
              OR s.gps_long_public <= east_longitude
          ))
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    ORDER BY ep.shared_at DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 500), 0), 500);
$$;

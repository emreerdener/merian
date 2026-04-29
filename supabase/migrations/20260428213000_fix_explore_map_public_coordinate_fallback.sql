CREATE OR REPLACE FUNCTION public.derive_public_scan_coordinate(
    exact_coordinate DOUBLE PRECISION,
    stored_public_coordinate DOUBLE PRECISION,
    scan_geoprivacy public.geoprivacy_enum,
    coordinate_uncertainty INTEGER,
    iucn_status TEXT
)
RETURNS DOUBLE PRECISION
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN scan_geoprivacy = 'private' THEN NULL
        WHEN exact_coordinate IS NOT NULL
            AND public.is_explore_location_obscured(
                scan_geoprivacy,
                coordinate_uncertainty,
                iucn_status
            )
            THEN ROUND(exact_coordinate::numeric, 1)::DOUBLE PRECISION
        WHEN exact_coordinate IS NOT NULL THEN exact_coordinate
        ELSE stored_public_coordinate
    END
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_scan_public_coordinates()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    resolved_status TEXT;
BEGIN
    SELECT sd.iucn_red_list_status
    INTO resolved_status
    FROM public.species_dictionary sd
    WHERE sd.id = COALESCE(NEW.confirmed_species_id, NEW.species_id);

    NEW.gps_lat_public := public.derive_public_scan_coordinate(
        NEW.gps_lat_exact,
        NEW.gps_lat_public,
        NEW.geoprivacy,
        NEW.coordinate_uncertainty_in_meters,
        resolved_status
    );

    NEW.gps_long_public := public.derive_public_scan_coordinate(
        NEW.gps_long_exact,
        NEW.gps_long_public,
        NEW.geoprivacy,
        NEW.coordinate_uncertainty_in_meters,
        resolved_status
    );

    IF NEW.geoprivacy = 'private'
       OR NEW.gps_lat_public IS NULL
       OR NEW.gps_long_public IS NULL THEN
        NEW.coordinate_uncertainty_in_meters := NULL;
    ELSIF public.is_explore_location_obscured(
        NEW.geoprivacy,
        NEW.coordinate_uncertainty_in_meters,
        resolved_status
    ) THEN
        NEW.coordinate_uncertainty_in_meters := GREATEST(
            COALESCE(NEW.coordinate_uncertainty_in_meters, 0),
            10000
        );
    ELSE
        NEW.coordinate_uncertainty_in_meters := LEAST(
            COALESCE(NEW.coordinate_uncertainty_in_meters, 0),
            999
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_scan_public_coordinates ON public.scans;
CREATE TRIGGER trg_sync_scan_public_coordinates
BEFORE INSERT OR UPDATE OF
    gps_lat_exact,
    gps_long_exact,
    gps_lat_public,
    gps_long_public,
    geoprivacy,
    coordinate_uncertainty_in_meters,
    species_id,
    confirmed_species_id
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_scan_public_coordinates();

WITH projected_scan_coordinates AS (
    SELECT
        s.id,
        public.derive_public_scan_coordinate(
            s.gps_lat_exact,
            s.gps_lat_public,
            s.geoprivacy,
            s.coordinate_uncertainty_in_meters,
            sd.iucn_red_list_status
        ) AS derived_latitude,
        public.derive_public_scan_coordinate(
            s.gps_long_exact,
            s.gps_long_public,
            s.geoprivacy,
            s.coordinate_uncertainty_in_meters,
            sd.iucn_red_list_status
        ) AS derived_longitude,
        CASE
            WHEN s.geoprivacy = 'private'
                 OR s.gps_lat_exact IS NULL
                 OR s.gps_long_exact IS NULL THEN NULL
            WHEN public.is_explore_location_obscured(
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) THEN GREATEST(COALESCE(s.coordinate_uncertainty_in_meters, 0), 10000)
            ELSE LEAST(COALESCE(s.coordinate_uncertainty_in_meters, 0), 999)
        END AS derived_uncertainty
    FROM public.scans s
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
)
UPDATE public.scans s
SET gps_lat_public = projected_scan_coordinates.derived_latitude,
    gps_long_public = projected_scan_coordinates.derived_longitude,
    coordinate_uncertainty_in_meters = projected_scan_coordinates.derived_uncertainty
FROM projected_scan_coordinates
WHERE projected_scan_coordinates.id = s.id
  AND (
      s.gps_lat_public IS DISTINCT FROM projected_scan_coordinates.derived_latitude
      OR s.gps_long_public IS DISTINCT FROM projected_scan_coordinates.derived_longitude
      OR s.coordinate_uncertainty_in_meters IS DISTINCT FROM projected_scan_coordinates.derived_uncertainty
  );

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
    WITH projected_posts AS (
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
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
          )
    )
    SELECT *
    FROM projected_posts
    WHERE latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude BETWEEN LEAST(north_latitude, south_latitude) AND GREATEST(north_latitude, south_latitude)
      AND (
          (west_longitude <= east_longitude AND longitude BETWEEN west_longitude AND east_longitude)
          OR
          (west_longitude > east_longitude AND (
              longitude >= west_longitude
              OR longitude <= east_longitude
          ))
      )
    ORDER BY shared_at DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 500), 0), 500);
$$;

ALTER TABLE public.explore_posts
    ADD COLUMN IF NOT EXISTS location_sharing TEXT NOT NULL DEFAULT 'obscured',
    ADD COLUMN IF NOT EXISTS public_latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS public_longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS public_coordinate_visibility TEXT,
    ADD COLUMN IF NOT EXISTS public_location_label TEXT;

ALTER TABLE public.explore_posts
    DROP CONSTRAINT IF EXISTS explore_posts_location_sharing_check,
    ADD CONSTRAINT explore_posts_location_sharing_check
        CHECK (location_sharing IN ('open', 'obscured', 'private'));

ALTER TABLE public.explore_posts
    DROP CONSTRAINT IF EXISTS explore_posts_public_coordinate_visibility_check,
    ADD CONSTRAINT explore_posts_public_coordinate_visibility_check
        CHECK (public_coordinate_visibility IS NULL OR public_coordinate_visibility IN ('exact', 'obscured'));

ALTER TABLE public.explore_posts
    DROP CONSTRAINT IF EXISTS explore_posts_public_latitude_check,
    ADD CONSTRAINT explore_posts_public_latitude_check
        CHECK (public_latitude IS NULL OR (public_latitude >= -90 AND public_latitude <= 90));

ALTER TABLE public.explore_posts
    DROP CONSTRAINT IF EXISTS explore_posts_public_longitude_check,
    ADD CONSTRAINT explore_posts_public_longitude_check
        CHECK (public_longitude IS NULL OR (public_longitude >= -180 AND public_longitude <= 180));

CREATE INDEX IF NOT EXISTS idx_explore_posts_public_coordinates_active
    ON public.explore_posts(public_latitude, public_longitude)
    WHERE location_sharing = 'open'
      AND public_latitude IS NOT NULL
      AND public_longitude IS NOT NULL
      AND unshared_at IS NULL;

COMMENT ON COLUMN public.explore_posts.location_sharing IS
    'Post-level geoprivacy override for Explore: open, obscured, or private.';
COMMENT ON COLUMN public.explore_posts.public_latitude IS
    'Post-owned public map latitude projected from the explicit post geoprivacy setting.';
COMMENT ON COLUMN public.explore_posts.public_longitude IS
    'Post-owned public map longitude projected from the explicit post geoprivacy setting.';
COMMENT ON COLUMN public.explore_posts.public_coordinate_visibility IS
    'exact or obscured visibility for the stored post-owned public map coordinate.';
COMMENT ON COLUMN public.explore_posts.public_location_label IS
    'Post-owned scrubbed location label exposed only when post geoprivacy is open or obscured.';

UPDATE public.explore_posts ep
SET location_sharing = CASE
        WHEN s.geoprivacy = 'open' THEN 'open'
        WHEN s.geoprivacy = 'private' THEN 'private'
        ELSE 'obscured'
    END
FROM public.scans s
WHERE s.id = ep.scan_id
  AND ep.location_sharing = 'obscured';

CREATE OR REPLACE FUNCTION public.project_explore_post_location(
    post_location_sharing TEXT,
    scan_latitude DOUBLE PRECISION,
    scan_longitude DOUBLE PRECISION,
    stored_public_latitude DOUBLE PRECISION,
    stored_public_longitude DOUBLE PRECISION,
    raw_public_location TEXT,
    raw_semantic_location TEXT,
    coordinate_uncertainty INTEGER,
    iucn_status TEXT
)
RETURNS TABLE(
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    location_label TEXT
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        CASE
            WHEN post_location_sharing = 'open' THEN public.derive_public_scan_coordinate(
                scan_latitude,
                stored_public_latitude,
                'open'::public.geoprivacy_enum,
                coordinate_uncertainty,
                iucn_status
            )
            ELSE NULL
        END AS latitude,
        CASE
            WHEN post_location_sharing = 'open' THEN public.derive_public_scan_coordinate(
                scan_longitude,
                stored_public_longitude,
                'open'::public.geoprivacy_enum,
                coordinate_uncertainty,
                iucn_status
            )
            ELSE NULL
        END AS longitude,
        CASE
            WHEN post_location_sharing <> 'open' THEN NULL
            WHEN public.is_explore_location_obscured(
                'open'::public.geoprivacy_enum,
                coordinate_uncertainty,
                iucn_status
            ) THEN 'obscured'
            ELSE 'exact'
        END AS coordinate_visibility,
        CASE
            WHEN post_location_sharing IN ('open', 'obscured') THEN
                public.resolve_explore_location_label(raw_public_location, raw_semantic_location)
            ELSE NULL
        END AS location_label;
$$;

CREATE OR REPLACE FUNCTION public.trg_project_explore_post_location()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    projection RECORD;
BEGIN
    SELECT
        projected.latitude,
        projected.longitude,
        projected.coordinate_visibility,
        projected.location_label
    INTO projection
    FROM public.scans s
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    CROSS JOIN LATERAL public.project_explore_post_location(
        NEW.location_sharing,
        s.gps_lat_exact,
        s.gps_long_exact,
        s.gps_lat_public,
        s.gps_long_public,
        s.public_location_label,
        s.semantic_location,
        s.coordinate_uncertainty_in_meters,
        sd.iucn_red_list_status
    ) projected
    WHERE s.id = NEW.scan_id;

    NEW.public_latitude := projection.latitude;
    NEW.public_longitude := projection.longitude;
    NEW.public_coordinate_visibility := projection.coordinate_visibility;
    NEW.public_location_label := projection.location_label;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_project_explore_post_location ON public.explore_posts;
CREATE TRIGGER trg_project_explore_post_location
BEFORE INSERT OR UPDATE
ON public.explore_posts
FOR EACH ROW
EXECUTE FUNCTION public.trg_project_explore_post_location();

CREATE OR REPLACE FUNCTION public.trg_refresh_explore_post_location_from_scan()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.explore_posts
    SET location_sharing = location_sharing
    WHERE scan_id = NEW.id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_explore_post_location_from_scan ON public.scans;
CREATE TRIGGER trg_refresh_explore_post_location_from_scan
AFTER UPDATE OF
    gps_lat_exact,
    gps_long_exact,
    gps_lat_public,
    gps_long_public,
    coordinate_uncertainty_in_meters,
    species_id,
    confirmed_species_id,
    semantic_location,
    public_location_label
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION public.trg_refresh_explore_post_location_from_scan();

UPDATE public.explore_posts
SET location_sharing = location_sharing;

DO $$
DECLARE
    function_signature TEXT;
    target_function REGPROCEDURE;
    function_definition TEXT;
    patched_definition TEXT;
BEGIN
    FOREACH function_signature IN ARRAY ARRAY[
        'public.get_explore_post(uuid, uuid)',
        'public.get_explore_feed(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_trending(uuid, integer, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_nearby(uuid, double precision, double precision, integer, timestamp with time zone, uuid)',
        'public.get_explore_feed_following(uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_author_posts(uuid, uuid, integer, timestamp with time zone, uuid)',
        'public.get_explore_hashtag_posts(uuid, text, integer, timestamp with time zone, uuid)'
    ] LOOP
        target_function := TO_REGPROCEDURE(function_signature);
        IF target_function IS NULL THEN
            RAISE EXCEPTION 'Could not find Explore RPC % to patch post geoprivacy projection', function_signature;
        END IF;

        function_definition := PG_GET_FUNCTIONDEF(target_function);
        patched_definition := function_definition;
        patched_definition := REPLACE(
            patched_definition,
            'public_location_label text,',
            'public_location_label text,' || E'\n    location_sharing text,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'public_location_label TEXT,',
            'public_location_label TEXT,' || E'\n    location_sharing TEXT,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'public.resolve_explore_location_label(s.public_location_label, s.semantic_location) AS public_location_label,',
            'ep.public_location_label AS public_location_label,' || E'\n        ep.location_sharing,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'public.sanitize_explore_location(s.semantic_location) AS public_location_label,',
            'ep.public_location_label AS public_location_label,' || E'\n        ep.location_sharing,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'public.derive_public_scan_coordinate(
                s.gps_lat_exact,
                s.gps_lat_public,
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) AS latitude,',
            'ep.public_latitude AS latitude,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'public.derive_public_scan_coordinate(
                s.gps_long_exact,
                s.gps_long_public,
                s.geoprivacy,
                s.coordinate_uncertainty_in_meters,
                sd.iucn_red_list_status
            ) AS longitude,',
            'ep.public_longitude AS longitude,'
        );
        patched_definition := REPLACE(
            patched_definition,
            'AND s.geoprivacy <> ''private''' || E'\n',
            ''
        );
        patched_definition := REPLACE(
            patched_definition,
            'AND s.geoprivacy <> ''private''::public.geoprivacy_enum' || E'\n',
            ''
        );
        patched_definition := REPLACE(
            patched_definition,
            'AND (s.geoprivacy <> ''private''::public.geoprivacy_enum)' || E'\n',
            ''
        );

        IF patched_definition = function_definition THEN
            RAISE EXCEPTION 'Explore RPC % did not contain expected post geoprivacy patch points', function_signature;
        END IF;

        EXECUTE FORMAT('DROP FUNCTION %s', target_function);
        EXECUTE patched_definition;
    END LOOP;
END $$;

DO $$
DECLARE
    function_definition TEXT;
    patched_definition TEXT;
BEGIN
    function_definition := PG_GET_FUNCTIONDEF('public.get_explore_post_detail(uuid, uuid)'::REGPROCEDURE);
    patched_definition := function_definition;
    patched_definition := REPLACE(
        patched_definition,
        'field_notes text,',
        'field_notes text,' || E'\n    location_sharing text,'
    );
    patched_definition := REPLACE(
        patched_definition,
        'field_notes TEXT,',
        'field_notes TEXT,' || E'\n    location_sharing TEXT,'
    );
    patched_definition := REPLACE(
        patched_definition,
        'NULLIF(BTRIM(COALESCE(ep.field_notes, ''''::text)), ''''::text) AS field_notes,',
        'NULLIF(BTRIM(COALESCE(ep.field_notes, ''''::text)), ''''::text) AS field_notes,' || E'\n        ep.location_sharing,'
    );
    patched_definition := REPLACE(
        patched_definition,
        'NULLIF(BTRIM(COALESCE(ep.field_notes, '''')), '''') AS field_notes,',
        'NULLIF(BTRIM(COALESCE(ep.field_notes, '''')), '''') AS field_notes,' || E'\n        ep.location_sharing,'
    );
    patched_definition := REPLACE(
        patched_definition,
        'AND s.geoprivacy <> ''private''' || E'\n',
        ''
    );
    patched_definition := REPLACE(
        patched_definition,
        'AND s.geoprivacy <> ''private''::public.geoprivacy_enum' || E'\n',
        ''
    );
    patched_definition := REPLACE(
        patched_definition,
        'AND (s.geoprivacy <> ''private''::public.geoprivacy_enum)' || E'\n',
        ''
    );

    IF patched_definition = function_definition THEN
        RAISE EXCEPTION 'get_explore_post_detail did not contain expected post geoprivacy patch points';
    END IF;

    DROP FUNCTION public.get_explore_post_detail(UUID, UUID);
    EXECUTE patched_definition;
END $$;

DO $$
DECLARE
    function_definition TEXT;
    patched_definition TEXT;
BEGIN
    FOR function_definition IN
        SELECT PG_GET_FUNCTIONDEF(p.oid)
        FROM pg_proc p
        JOIN pg_namespace n
            ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND PG_GET_FUNCTIONDEF(p.oid) LIKE '%s.geoprivacy <> ''private''%'
          AND (
              p.proname LIKE 'get_explore_%'
              OR p.proname LIKE 'create_explore_%'
              OR p.proname LIKE 'delete_explore_%'
              OR p.proname LIKE 'moderate_explore_%'
          )
    LOOP
        patched_definition := REPLACE(
            function_definition,
            'AND s.geoprivacy <> ''private''' || E'\n',
            ''
        );
        patched_definition := REPLACE(
            patched_definition,
            'AND s.geoprivacy <> ''private''::public.geoprivacy_enum' || E'\n',
            ''
        );
        patched_definition := REPLACE(
            patched_definition,
            'AND (s.geoprivacy <> ''private''::public.geoprivacy_enum)' || E'\n',
            ''
        );

        IF patched_definition <> function_definition THEN
            EXECUTE patched_definition;
        END IF;
    END LOOP;
END $$;

DROP FUNCTION IF EXISTS public.get_scan_explore_share_state(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_scan_explore_share_state(
    self_id UUID,
    target_scan_id UUID
)
RETURNS TABLE(
    scan_id UUID,
    post_id UUID,
    shared_at TIMESTAMPTZ,
    location_sharing TEXT
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        s.id AS scan_id,
        CASE
            WHEN ep.id IS NOT NULL
             AND s.is_tombstoned = FALSE
             AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
             AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
             AND u.is_shadowbanned = FALSE
                THEN ep.id
            ELSE NULL
        END AS post_id,
        CASE
            WHEN ep.id IS NOT NULL
             AND s.is_tombstoned = FALSE
             AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
             AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
             AND u.is_shadowbanned = FALSE
                THEN ep.shared_at
            ELSE NULL
        END AS shared_at,
        CASE
            WHEN ep.id IS NOT NULL
             AND s.is_tombstoned = FALSE
             AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
             AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
             AND u.is_shadowbanned = FALSE
                THEN ep.location_sharing
            ELSE s.geoprivacy::TEXT
        END AS location_sharing
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
    WHERE s.id = target_scan_id
      AND s.user_id = self_id
    LIMIT 1;
$$;

DROP FUNCTION IF EXISTS public.get_explore_map_posts(
    UUID,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    INTEGER
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
        ep.id AS post_id,
        ep.scan_id,
        ep.public_latitude AS latitude,
        ep.public_longitude AS longitude,
        ep.public_coordinate_visibility AS coordinate_visibility,
        s.image_storage_urls[1] AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        public.explore_post_species_common_name(ep.species_common_name, sd.common_names, sd.scientific_name) AS species_common_name,
        COALESCE(sd.scientific_name, 'Unknown Subject') AS species_scientific_name,
        ep.public_location_label,
        ep.location_sharing,
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
      AND ep.location_sharing = 'open'
      AND u.is_shadowbanned = FALSE
      AND ep.public_latitude IS NOT NULL
      AND ep.public_longitude IS NOT NULL
      AND ep.public_latitude BETWEEN LEAST(north_latitude, south_latitude) AND GREATEST(north_latitude, south_latitude)
      AND (
          (west_longitude <= east_longitude AND ep.public_longitude BETWEEN west_longitude AND east_longitude)
          OR
          (west_longitude > east_longitude AND (
              ep.public_longitude >= west_longitude
              OR ep.public_longitude <= east_longitude
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

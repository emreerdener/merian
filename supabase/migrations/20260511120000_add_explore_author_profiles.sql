-- Public Explore author profiles.
--
-- Profile aggregates intentionally use the author's full non-tombstoned scan
-- history, but the preview/library surfaces only return scans that are already
-- visible as Explore posts to the requesting viewer.

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS device_time_zone TEXT;

CREATE INDEX IF NOT EXISTS idx_explore_posts_author_shared_at_visible
    ON public.explore_posts(user_id, shared_at DESC, id DESC)
    WHERE unshared_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_scans_user_tombstone_timestamp
    ON public.scans(user_id, is_tombstoned, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_scans_user_biological_species
    ON public.scans(user_id, is_biological_subject, species_id, confirmed_species_id)
    WHERE is_tombstoned = FALSE;

DROP FUNCTION IF EXISTS public.get_explore_author_posts(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_author_posts(
    self_id UUID,
    target_author_user_id UUID,
    max_limit INTEGER DEFAULT 30,
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
    WHERE ep.user_id = target_author_user_id
      AND ep.unshared_at IS NULL
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
    LIMIT GREATEST(COALESCE(max_limit, 30), 0);
$$;

DROP FUNCTION IF EXISTS public.get_explore_author_profile(UUID, UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.get_explore_author_profile(
    self_id UUID,
    target_author_user_id UUID,
    preview_limit INTEGER DEFAULT 9
)
RETURNS TABLE(
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_count INTEGER,
    current_streak INTEGER,
    heatmap JSONB,
    awards JSONB,
    published_post_count INTEGER,
    preview_posts JSONB
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    author_row RECORD;
    visible_post_count INTEGER := 0;
    profile_time_zone TEXT := 'UTC';
    local_today DATE;
    heatmap_start DATE;
    heatmap_end DATE;
    computed_species_count INTEGER := 0;
    computed_streak INTEGER := 0;
    heatmap_payload JSONB := '{}'::jsonb;
    awards_payload JSONB := '[]'::jsonb;
    preview_payload JSONB := '[]'::jsonb;
BEGIN
    SELECT u.id, u.public_author_name, u.public_avatar_url
    INTO author_row
    FROM public.users u
    WHERE u.id = target_author_user_id
      AND u.is_shadowbanned = FALSE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO visible_post_count
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    WHERE ep.user_id = target_author_user_id
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND s.geoprivacy <> 'private'
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      );

    IF visible_post_count = 0 THEN
        RETURN;
    END IF;

    SELECT COALESCE((
        SELECT s.device_time_zone
        FROM public.scans s
        JOIN pg_timezone_names tz
            ON tz.name = s.device_time_zone
        WHERE s.user_id = target_author_user_id
          AND s.is_tombstoned = FALSE
          AND s.device_time_zone IS NOT NULL
          AND BTRIM(s.device_time_zone) <> ''
        ORDER BY s.timestamp DESC, s.id DESC
        LIMIT 1
    ), 'UTC')
    INTO profile_time_zone;

    local_today := (NOW() AT TIME ZONE profile_time_zone)::DATE;
    heatmap_end := local_today + (6 - EXTRACT(DOW FROM local_today)::INTEGER);
    heatmap_start := heatmap_end - 363;

    SELECT COUNT(DISTINCT COALESCE(s.confirmed_species_id, s.species_id))::INTEGER
    INTO computed_species_count
    FROM public.scans s
    WHERE s.user_id = target_author_user_id
      AND s.is_tombstoned = FALSE
      AND s.is_biological_subject = TRUE
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL;

    WITH scan_dates AS (
        SELECT DISTINCT (s.timestamp AT TIME ZONE profile_time_zone)::DATE AS scan_date
        FROM public.scans s
        WHERE s.user_id = target_author_user_id
          AND s.is_tombstoned = FALSE
    ),
    anchor AS (
        SELECT CASE
            WHEN EXISTS (SELECT 1 FROM scan_dates WHERE scan_date = local_today) THEN local_today
            WHEN EXISTS (SELECT 1 FROM scan_dates WHERE scan_date = local_today - 1) THEN local_today - 1
            ELSE NULL::DATE
        END AS anchor_date
    ),
    ordered_dates AS (
        SELECT
            sd.scan_date,
            (ROW_NUMBER() OVER (ORDER BY sd.scan_date DESC) - 1)::INTEGER AS row_offset
        FROM scan_dates sd
        CROSS JOIN anchor a
        WHERE a.anchor_date IS NOT NULL
          AND sd.scan_date <= a.anchor_date
    )
    SELECT COUNT(*)::INTEGER
    INTO computed_streak
    FROM ordered_dates od
    CROSS JOIN anchor a
    WHERE od.scan_date = a.anchor_date - od.row_offset;

    WITH generated_days AS (
        SELECT
            generated_day::DATE AS day_date,
            ((generated_day::DATE - heatmap_start) / 7)::INTEGER AS week_index,
            ((generated_day::DATE - heatmap_start) % 7)::INTEGER AS day_index
        FROM GENERATE_SERIES(heatmap_start, heatmap_end, INTERVAL '1 day') AS generated_day
    ),
    scan_counts AS (
        SELECT
            (s.timestamp AT TIME ZONE profile_time_zone)::DATE AS scan_date,
            COUNT(*)::INTEGER AS scan_count
        FROM public.scans s
        WHERE s.user_id = target_author_user_id
          AND s.is_tombstoned = FALSE
          AND (s.timestamp AT TIME ZONE profile_time_zone)::DATE BETWEEN heatmap_start AND local_today
        GROUP BY (s.timestamp AT TIME ZONE profile_time_zone)::DATE
    ),
    day_rows AS (
        SELECT
            gd.week_index,
            gd.day_index,
            gd.day_date,
            CASE
                WHEN gd.day_date > local_today THEN -1
                ELSE COALESCE(sc.scan_count, 0)
            END AS scan_count
        FROM generated_days gd
        LEFT JOIN scan_counts sc
            ON sc.scan_date = gd.day_date
    ),
    week_rows AS (
        SELECT
            dr.week_index,
            MIN(dr.day_date) AS week_start,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'count', dr.scan_count,
                    'date', TO_CHAR(dr.day_date, 'YYYY-MM-DD') || 'T00:00:00Z'
                )
                ORDER BY dr.day_index
            ) AS days
        FROM day_rows dr
        GROUP BY dr.week_index
    ),
    totals AS (
        SELECT
            COALESCE(SUM(scan_count) FILTER (WHERE scan_count > 0), 0)::INTEGER AS total_captures,
            COALESCE(SUM(scan_count) FILTER (
                WHERE scan_count > 0
                  AND EXTRACT(YEAR FROM day_date) = EXTRACT(YEAR FROM local_today)
                  AND EXTRACT(MONTH FROM day_date) = EXTRACT(MONTH FROM local_today)
            ), 0)::INTEGER AS current_month_captures
        FROM day_rows
    )
    SELECT JSONB_BUILD_OBJECT(
        'total_captures', totals.total_captures,
        'current_month_captures', totals.current_month_captures,
        'year_string', EXTRACT(YEAR FROM local_today)::INTEGER::TEXT,
        'weeks', COALESCE(
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'month_label',
                    CASE
                        WHEN wr.week_index = 0
                          OR EXTRACT(MONTH FROM wr.week_start) <> EXTRACT(MONTH FROM (wr.week_start - INTERVAL '7 days'))
                        THEN TO_CHAR(wr.week_start, 'Mon')
                        ELSE NULL
                    END,
                    'days', wr.days
                )
                ORDER BY wr.week_index
            ),
            '[]'::jsonb
        )
    )
    INTO heatmap_payload
    FROM week_rows wr
    CROSS JOIN totals
    GROUP BY totals.total_captures, totals.current_month_captures;

    WITH achievement_records AS (
        SELECT
            s.id,
            s.timestamp,
            COALESCE(s.confirmed_species_id, s.species_id) AS species_key,
            sd.kingdom,
            sd.class,
            s.ecology_type::TEXT AS ecology_type,
            s.weather_temperature_f,
            s.gps_elevation,
            s.is_invasive,
            sd.iucn_red_list_status,
            COALESCE(sd.hazard_type, 'none') AS hazard_type,
            s.ai_confidence_score
        FROM public.scans s
        LEFT JOIN public.species_dictionary sd
            ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
        WHERE s.user_id = target_author_user_id
          AND s.is_tombstoned = FALSE
          AND s.is_biological_subject = TRUE
          AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
    )
    SELECT JSONB_BUILD_ARRAY(
        JSONB_BUILD_OBJECT(
            'type', 'first_scan',
            'current_count', CASE WHEN EXISTS (SELECT 1 FROM achievement_records) THEN 1 ELSE 0 END,
            'last_interaction_at', (SELECT MIN(timestamp) FROM achievement_records)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'explorer',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records), 5),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'plantae',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(kingdom, ''))) = 'plantae'), 10),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(kingdom, ''))) = 'plantae')
        ),
        JSONB_BUILD_OBJECT(
            'type', 'insecta',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(class, ''))) IN ('insecta', 'arachnida')), 10),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(class, ''))) IN ('insecta', 'arachnida'))
        ),
        JSONB_BUILD_OBJECT(
            'type', 'fungi',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(kingdom, ''))) = 'fungi'), 10),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(kingdom, ''))) = 'fungi')
        ),
        JSONB_BUILD_OBJECT(
            'type', 'urban',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''))) IN ('urban', 'domesticated')), 10),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(ecology_type, ''))) IN ('urban', 'domesticated'))
        ),
        JSONB_BUILD_OBJECT(
            'type', 'frost_walker',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE weather_temperature_f < 32.0), 5),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE weather_temperature_f < 32.0)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'alpine',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE gps_elevation > 2500.0), 5),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE gps_elevation > 2500.0)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'nocturnal',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE EXTRACT(HOUR FROM (timestamp AT TIME ZONE profile_time_zone)) >= 22 OR EXTRACT(HOUR FROM (timestamp AT TIME ZONE profile_time_zone)) <= 5), 10),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE EXTRACT(HOUR FROM (timestamp AT TIME ZONE profile_time_zone)) >= 22 OR EXTRACT(HOUR FROM (timestamp AT TIME ZONE profile_time_zone)) <= 5)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'guardian',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE is_invasive = TRUE), 5),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE is_invasive = TRUE)
        ),
        JSONB_BUILD_OBJECT(
            'type', 'conservationist',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE NULLIF(BTRIM(COALESCE(iucn_red_list_status, '')), '') IS NOT NULL AND UPPER(BTRIM(iucn_red_list_status)) NOT IN ('LC', 'NE', 'DD')), 1),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE NULLIF(BTRIM(COALESCE(iucn_red_list_status, '')), '') IS NOT NULL AND UPPER(BTRIM(iucn_red_list_status)) NOT IN ('LC', 'NE', 'DD'))
        ),
        JSONB_BUILD_OBJECT(
            'type', 'toxicologist',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(hazard_type, 'none'))) <> 'none' AND BTRIM(COALESCE(hazard_type, '')) <> ''), 5),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE LOWER(BTRIM(COALESCE(hazard_type, 'none'))) <> 'none' AND BTRIM(COALESCE(hazard_type, '')) <> '')
        ),
        JSONB_BUILD_OBJECT(
            'type', 'perfect_lens',
            'current_count', LEAST((SELECT COUNT(DISTINCT species_key) FROM achievement_records WHERE ai_confidence_score >= 0.98), 25),
            'last_interaction_at', (SELECT MAX(timestamp) FROM achievement_records WHERE ai_confidence_score >= 0.98)
        )
    )
    INTO awards_payload;

    SELECT COALESCE(JSONB_AGG(TO_JSONB(posts) ORDER BY posts.shared_at DESC, posts.post_id DESC), '[]'::jsonb)
    INTO preview_payload
    FROM public.get_explore_author_posts(
        self_id,
        target_author_user_id,
        LEAST(GREATEST(COALESCE(preview_limit, 9), 0), 30),
        NULL,
        NULL
    ) AS posts;

    RETURN QUERY
    SELECT
        author_row.id,
        author_row.public_author_name,
        author_row.public_avatar_url,
        COALESCE(computed_species_count, 0),
        COALESCE(computed_streak, 0),
        heatmap_payload,
        awards_payload,
        visible_post_count,
        preview_payload;
END;
$$;

NOTIFY pgrst, 'reload schema';

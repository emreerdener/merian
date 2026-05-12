-- Explore following relationships.
--
-- Following is asymmetric and only affects public Explore surfaces. It does not
-- grant access to private scans or expose browsable follower/following lists.

CREATE TABLE IF NOT EXISTS public.user_follows (
    follower_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    followee_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (follower_user_id, followee_user_id),
    CONSTRAINT user_follows_no_self_follow CHECK (follower_user_id <> followee_user_id)
);

ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_follows'
          AND policyname = 'Users can insert their own follows'
    ) THEN
        CREATE POLICY "Users can insert their own follows"
            ON public.user_follows
            FOR INSERT
            WITH CHECK (auth.uid() = follower_user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_follows'
          AND policyname = 'Users can remove their own follows'
    ) THEN
        CREATE POLICY "Users can remove their own follows"
            ON public.user_follows
            FOR DELETE
            USING (auth.uid() = follower_user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_follows'
          AND policyname = 'Users can read their own following relationships'
    ) THEN
        CREATE POLICY "Users can read their own following relationships"
            ON public.user_follows
            FOR SELECT
            USING (auth.uid() = follower_user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_user_follows_follower_created_at
    ON public.user_follows(follower_user_id, created_at DESC, followee_user_id);

CREATE INDEX IF NOT EXISTS idx_user_follows_followee_created_at
    ON public.user_follows(followee_user_id, created_at DESC, follower_user_id);

CREATE OR REPLACE FUNCTION public.can_view_explore_author_profile(
    self_id UUID,
    target_author_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = target_author_user_id
          AND u.is_shadowbanned = FALSE
    )
    AND EXISTS (
        SELECT 1
        FROM public.explore_posts ep
        JOIN public.scans s
            ON s.id = ep.scan_id
        WHERE ep.user_id = target_author_user_id
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_user_follow_state(
    self_id UUID,
    target_author_user_id UUID
)
RETURNS TABLE(
    author_user_id UUID,
    follower_count INTEGER,
    following_count INTEGER,
    viewer_is_following BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        target_author_user_id AS author_user_id,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.user_follows uf
            JOIN public.users follower
                ON follower.id = uf.follower_user_id
            WHERE uf.followee_user_id = target_author_user_id
              AND follower.is_shadowbanned = FALSE
        ) AS follower_count,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.user_follows uf
            JOIN public.users followee
                ON followee.id = uf.followee_user_id
            WHERE uf.follower_user_id = target_author_user_id
              AND followee.is_shadowbanned = FALSE
        ) AS following_count,
        EXISTS (
            SELECT 1
            FROM public.user_follows uf
            WHERE uf.follower_user_id = self_id
              AND uf.followee_user_id = target_author_user_id
        ) AS viewer_is_following;
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed_following(
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
    FROM public.user_follows uf
    JOIN public.explore_posts ep
        ON ep.user_id = uf.followee_user_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE uf.follower_user_id = self_id
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
    LIMIT GREATEST(COALESCE(max_limit, 20), 0);
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
    follower_count INTEGER,
    following_count INTEGER,
    viewer_is_following BOOLEAN,
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
    computed_follower_count INTEGER := 0;
    computed_following_count INTEGER := 0;
    computed_viewer_is_following BOOLEAN := FALSE;
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

    SELECT
        state.follower_count,
        state.following_count,
        state.viewer_is_following
    INTO
        computed_follower_count,
        computed_following_count,
        computed_viewer_is_following
    FROM public.get_user_follow_state(self_id, target_author_user_id) AS state;

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
        COALESCE(computed_follower_count, 0),
        COALESCE(computed_following_count, 0),
        COALESCE(computed_viewer_is_following, FALSE),
        preview_payload;
END;
$$;

ALTER TABLE public.explore_post_notifications
    ALTER COLUMN post_id DROP NOT NULL;

ALTER TABLE public.explore_post_notifications
DROP CONSTRAINT IF EXISTS explore_post_notifications_comment_shape;

ALTER TABLE public.explore_post_notifications
ADD CONSTRAINT explore_post_notifications_comment_shape CHECK (
    (
        type = 'comment'
        AND post_id IS NOT NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'like_aggregated'
        AND post_id IS NOT NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
    )
    OR (
        type = 'comment_reaction'
        AND post_id IS NOT NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NOT NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
        AND action_count >= 1
    )
    OR (
        type = 'follow'
        AND post_id IS NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_follow_unique
    ON public.explore_post_notifications(user_id, triggering_user_id, type)
    WHERE type = 'follow' AND triggering_user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.trg_user_follow_notification_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.follower_user_id = NEW.followee_user_id THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_blocks ub
        WHERE (ub.blocker_id = NEW.follower_user_id AND ub.blocked_id = NEW.followee_user_id)
           OR (ub.blocker_id = NEW.followee_user_id AND ub.blocked_id = NEW.follower_user_id)
    ) THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = NEW.follower_user_id
          AND u.is_shadowbanned = FALSE
    ) THEN
        INSERT INTO public.explore_post_notifications (
            user_id,
            post_id,
            type,
            comment_id,
            reaction_emoji,
            triggering_user_id,
            recent_actor_ids,
            action_count,
            is_read,
            created_at,
            updated_at
        )
        VALUES (
            NEW.followee_user_id,
            NULL,
            'follow',
            NULL,
            NULL,
            NEW.follower_user_id,
            ARRAY[]::UUID[],
            1,
            FALSE,
            NOW(),
            NOW()
        )
        ON CONFLICT (user_id, triggering_user_id, type)
        WHERE type = 'follow' AND triggering_user_id IS NOT NULL
        DO UPDATE SET
            is_read = FALSE,
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_user_follow_notification_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.explore_post_notifications
    WHERE user_id = OLD.followee_user_id
      AND triggering_user_id = OLD.follower_user_id
      AND type = 'follow';

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_follow_notification_after_insert ON public.user_follows;
CREATE TRIGGER trg_user_follow_notification_after_insert
AFTER INSERT ON public.user_follows
FOR EACH ROW
EXECUTE FUNCTION public.trg_user_follow_notification_after_insert();

DROP TRIGGER IF EXISTS trg_user_follow_notification_after_delete ON public.user_follows;
CREATE TRIGGER trg_user_follow_notification_after_delete
AFTER DELETE ON public.user_follows
FOR EACH ROW
EXECUTE FUNCTION public.trg_user_follow_notification_after_delete();

CREATE OR REPLACE FUNCTION public.trg_user_blocks_remove_follows()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.user_follows
    WHERE (follower_user_id = NEW.blocker_id AND followee_user_id = NEW.blocked_id)
       OR (follower_user_id = NEW.blocked_id AND followee_user_id = NEW.blocker_id);

    DELETE FROM public.explore_post_notifications
    WHERE type = 'follow'
      AND (
          (user_id = NEW.blocker_id AND triggering_user_id = NEW.blocked_id)
          OR (user_id = NEW.blocked_id AND triggering_user_id = NEW.blocker_id)
      );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_blocks_remove_follows ON public.user_blocks;
CREATE TRIGGER trg_user_blocks_remove_follows
AFTER INSERT ON public.user_blocks
FOR EACH ROW
EXECUTE FUNCTION public.trg_user_blocks_remove_follows();

DROP FUNCTION IF EXISTS public.get_explore_notifications(UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_notifications(
    self_id UUID,
    max_limit INTEGER DEFAULT 50,
    before_updated_at TIMESTAMPTZ DEFAULT NULL,
    before_notification_id UUID DEFAULT NULL
)
RETURNS TABLE(
    notification_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    comment_id UUID,
    reaction_emoji TEXT,
    triggering_user_id UUID,
    triggering_user_name TEXT,
    comment_body TEXT,
    recent_actor_names TEXT[],
    action_count INTEGER,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
AS $$
    WITH visible_notifications AS (
        SELECT n.*
        FROM public.explore_post_notifications n
        LEFT JOIN public.explore_posts ep
            ON ep.id = n.post_id
        LEFT JOIN public.scans s
            ON s.id = ep.scan_id
        LEFT JOIN public.users owner
            ON owner.id = ep.user_id
        LEFT JOIN public.explore_post_comments c
            ON c.id = n.comment_id
        LEFT JOIN public.users actor
            ON actor.id = n.triggering_user_id
        WHERE n.user_id = self_id
          AND (
              (
                  n.type = 'follow'
                  AND n.post_id IS NULL
                  AND n.triggering_user_id IS NOT NULL
                  AND actor.id IS NOT NULL
                  AND actor.is_shadowbanned = FALSE
                  AND EXISTS (
                      SELECT 1
                      FROM public.user_follows uf
                      WHERE uf.follower_user_id = n.triggering_user_id
                        AND uf.followee_user_id = n.user_id
                  )
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks ub
                      WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                         OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                  )
              )
              OR (
                  n.type <> 'follow'
                  AND n.post_id IS NOT NULL
                  AND ep.id IS NOT NULL
                  AND ep.unshared_at IS NULL
                  AND s.is_tombstoned = FALSE
                  AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
                  AND s.geoprivacy <> 'private'
                  AND owner.is_shadowbanned = FALSE
                  AND (
                      n.type = 'like_aggregated'
                      OR (
                          c.id IS NOT NULL
                          AND c.deleted_at IS NULL
                          AND c.moderated_at IS NULL
                          AND (
                              (
                                  n.type = 'comment'
                                  AND n.triggering_user_id IS NOT NULL
                                  AND NOT EXISTS (
                                      SELECT 1
                                      FROM public.user_blocks ub
                                      WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                                         OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                                  )
                              )
                              OR (
                                  n.type = 'comment_reaction'
                                  AND n.reaction_emoji IS NOT NULL
                              )
                          )
                      )
                  )
              )
          )
    )
    SELECT
        n.id AS notification_id,
        n.post_id,
        n.type,
        n.comment_id,
        n.reaction_emoji,
        n.triggering_user_id,
        CASE
            WHEN n.type IN ('comment', 'follow') THEN actor.public_author_name
            WHEN COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0 THEN actor_names.recent_actor_names[1]
            ELSE NULL
        END AS triggering_user_name,
        c.body AS comment_body,
        COALESCE(actor_names.recent_actor_names, ARRAY[]::TEXT[]) AS recent_actor_names,
        n.action_count,
        n.is_read,
        n.created_at,
        n.updated_at
    FROM visible_notifications n
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
       AND c.deleted_at IS NULL
       AND c.moderated_at IS NULL
    LEFT JOIN public.users actor
        ON actor.id = n.triggering_user_id
    LEFT JOIN LATERAL (
        SELECT COALESCE(
            array_agg(u.public_author_name ORDER BY actor_ids.ord),
            ARRAY[]::TEXT[]
        ) AS recent_actor_names
        FROM unnest(n.recent_actor_ids) WITH ORDINALITY AS actor_ids(actor_id, ord)
        JOIN public.users u
            ON u.id = actor_ids.actor_id
        WHERE u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = u.id)
                 OR (ub.blocker_id = u.id AND ub.blocked_id = self_id)
          )
    ) actor_names ON TRUE
    WHERE (
            before_updated_at IS NULL
            OR before_notification_id IS NULL
            OR n.updated_at < before_updated_at
            OR (n.updated_at = before_updated_at AND n.id < before_notification_id)
        )
      AND (
            n.type <> 'comment_reaction'
            OR COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0
        )
    ORDER BY n.updated_at DESC, n.id DESC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0);
$$;

DROP FUNCTION IF EXISTS public.get_unread_explore_notification_count(UUID);

CREATE OR REPLACE FUNCTION public.get_unread_explore_notification_count(self_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.explore_post_notifications n
    LEFT JOIN public.explore_posts ep
        ON ep.id = n.post_id
    LEFT JOIN public.scans s
        ON s.id = ep.scan_id
    LEFT JOIN public.users owner
        ON owner.id = ep.user_id
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
    LEFT JOIN public.users actor
        ON actor.id = n.triggering_user_id
    WHERE n.user_id = self_id
      AND n.is_read = FALSE
      AND (
          (
              n.type = 'follow'
              AND n.post_id IS NULL
              AND n.triggering_user_id IS NOT NULL
              AND actor.id IS NOT NULL
              AND actor.is_shadowbanned = FALSE
              AND EXISTS (
                  SELECT 1
                  FROM public.user_follows uf
                  WHERE uf.follower_user_id = n.triggering_user_id
                    AND uf.followee_user_id = n.user_id
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                     OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
              )
          )
          OR (
              n.type <> 'follow'
              AND n.post_id IS NOT NULL
              AND ep.id IS NOT NULL
              AND ep.unshared_at IS NULL
              AND s.is_tombstoned = FALSE
              AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
              AND s.geoprivacy <> 'private'
              AND owner.is_shadowbanned = FALSE
              AND (
                  n.type = 'like_aggregated'
                  OR (
                      c.id IS NOT NULL
                      AND c.deleted_at IS NULL
                      AND c.moderated_at IS NULL
                      AND (
                          (
                              n.type = 'comment'
                              AND n.triggering_user_id IS NOT NULL
                              AND NOT EXISTS (
                                  SELECT 1
                                  FROM public.user_blocks ub
                                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                                     OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                              )
                          )
                          OR (
                              n.type = 'comment_reaction'
                              AND n.reaction_emoji IS NOT NULL
                              AND EXISTS (
                                  SELECT 1
                                  FROM unnest(n.recent_actor_ids) AS actor_ids(actor_id)
                                  JOIN public.users u
                                      ON u.id = actor_ids.actor_id
                                  WHERE u.is_shadowbanned = FALSE
                                    AND NOT EXISTS (
                                        SELECT 1
                                        FROM public.user_blocks ub
                                        WHERE (ub.blocker_id = self_id AND ub.blocked_id = u.id)
                                           OR (ub.blocker_id = u.id AND ub.blocked_id = self_id)
                                    )
                              )
                          )
                      )
                  )
              )
          )
      );
$$;

CREATE OR REPLACE FUNCTION public.trigger_explore_notification_push_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    project_url TEXT;
    service_role_key TEXT;
    edge_endpoint TEXT;
    should_dispatch BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        should_dispatch := NEW.type <> 'follow';
    ELSIF TG_OP = 'UPDATE' THEN
        should_dispatch := NEW.type IN ('like_aggregated', 'comment_reaction')
            AND COALESCE(NEW.action_count, 0) > COALESCE(OLD.action_count, 0);
    END IF;

    IF NOT should_dispatch THEN
        RETURN NEW;
    END IF;

    SELECT decrypted_secret INTO project_url
    FROM vault.decrypted_secrets
    WHERE name = 'SUPABASE_URL'
    LIMIT 1;

    SELECT decrypted_secret INTO service_role_key
    FROM vault.decrypted_secrets
    WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
    LIMIT 1;

    IF project_url IS NULL THEN
        project_url := current_setting('app.settings.supabase_url', true);
    END IF;

    IF service_role_key IS NULL THEN
        service_role_key := current_setting('app.settings.service_role_key', true);
    END IF;

    IF project_url IS NULL OR service_role_key IS NULL THEN
        RAISE NOTICE 'Explore push delivery skipped because Supabase edge settings were unavailable.';
        RETURN NEW;
    END IF;

    edge_endpoint := project_url || '/functions/v1/send-push-notification';

    PERFORM net.http_post(
        url := edge_endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object('notification_id', NEW.id)
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reparent_user_follows(
    ghost_id UUID,
    target_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.user_follows (follower_user_id, followee_user_id, created_at)
    SELECT target_user_id, uf.followee_user_id, MIN(uf.created_at)
    FROM public.user_follows uf
    WHERE uf.follower_user_id = ghost_id
      AND uf.followee_user_id <> target_user_id
    GROUP BY uf.followee_user_id
    ON CONFLICT (follower_user_id, followee_user_id) DO NOTHING;

    INSERT INTO public.user_follows (follower_user_id, followee_user_id, created_at)
    SELECT uf.follower_user_id, target_user_id, MIN(uf.created_at)
    FROM public.user_follows uf
    WHERE uf.followee_user_id = ghost_id
      AND uf.follower_user_id <> target_user_id
    GROUP BY uf.follower_user_id
    ON CONFLICT (follower_user_id, followee_user_id) DO NOTHING;

    DELETE FROM public.user_follows
    WHERE follower_user_id = ghost_id
       OR followee_user_id = ghost_id
       OR follower_user_id = followee_user_id;
END;
$$;

NOTIFY pgrst, 'reload schema';

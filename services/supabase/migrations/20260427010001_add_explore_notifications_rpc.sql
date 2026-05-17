DROP FUNCTION IF EXISTS public.get_explore_post(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_post(
    self_id UUID,
    target_post_id UUID
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
    WHERE ep.id = target_post_id
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
      );
$$;

DROP FUNCTION IF EXISTS public.get_explore_notifications(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.get_explore_notifications(
    self_id UUID,
    max_limit INTEGER DEFAULT 50,
    notification_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    notification_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    comment_id UUID,
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
        JOIN public.explore_posts ep
            ON ep.id = n.post_id
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users owner
            ON owner.id = ep.user_id
        LEFT JOIN public.explore_post_comments c
            ON c.id = n.comment_id
        WHERE n.user_id = self_id
          AND ep.user_id = self_id
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND owner.is_shadowbanned = FALSE
          AND (
              n.type <> 'comment'
              OR (
                  c.id IS NOT NULL
                  AND c.deleted_at IS NULL
                  AND n.triggering_user_id IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks ub
                      WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                         OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                  )
              )
          )
    )
    SELECT
        n.id AS notification_id,
        n.post_id,
        n.type,
        n.comment_id,
        n.triggering_user_id,
        CASE
            WHEN n.type = 'comment' THEN actor.public_author_name
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
    ORDER BY n.updated_at DESC, n.created_at DESC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0)
    OFFSET GREATEST(COALESCE(notification_offset, 0), 0);
$$;

DROP FUNCTION IF EXISTS public.get_unread_explore_notification_count(UUID);

CREATE OR REPLACE FUNCTION public.get_unread_explore_notification_count(self_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.explore_post_notifications n
    JOIN public.explore_posts ep
        ON ep.id = n.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users owner
        ON owner.id = ep.user_id
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
    WHERE n.user_id = self_id
      AND n.is_read = FALSE
      AND ep.user_id = self_id
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND owner.is_shadowbanned = FALSE
      AND (
          n.type <> 'comment'
          OR (
              c.id IS NOT NULL
              AND c.deleted_at IS NULL
              AND n.triggering_user_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                     OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
              )
          )
      );
$$;

DROP FUNCTION IF EXISTS public.mark_explore_notifications_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_explore_notifications_read(self_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE public.explore_post_notifications
    SET is_read = TRUE
    WHERE user_id = self_id
      AND is_read = FALSE;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

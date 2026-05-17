ALTER TABLE public.explore_post_comments
    ADD COLUMN IF NOT EXISTS moderated_at TIMESTAMPTZ;

ALTER TABLE public.explore_post_comments
    ADD COLUMN IF NOT EXISTS moderated_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_explore_post_comments_moderated_by_user_id
    ON public.explore_post_comments (moderated_by_user_id);

CREATE TABLE IF NOT EXISTS public.explore_comment_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID NOT NULL REFERENCES public.explore_post_comments(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    reporter_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    comment_author_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_comment_reports_comment_reporter_unique
    ON public.explore_comment_reports (comment_id, reporter_user_id);

CREATE INDEX IF NOT EXISTS idx_explore_comment_reports_created_at
    ON public.explore_comment_reports (created_at DESC);

ALTER TABLE public.explore_comment_reports ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.deleted_at IS NULL AND NEW.moderated_at IS NULL THEN
        UPDATE public.explore_posts
        SET comment_count = comment_count + 1
        WHERE id = NEW.post_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_visible BOOLEAN := OLD.deleted_at IS NULL AND OLD.moderated_at IS NULL;
    new_visible BOOLEAN := NEW.deleted_at IS NULL AND NEW.moderated_at IS NULL;
BEGIN
    IF old_visible AND NOT new_visible THEN
        UPDATE public.explore_posts
        SET comment_count = GREATEST(comment_count - 1, 0)
        WHERE id = NEW.post_id;
    ELSIF NOT old_visible AND new_visible THEN
        UPDATE public.explore_posts
        SET comment_count = comment_count + 1
        WHERE id = NEW.post_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.deleted_at IS NULL AND OLD.moderated_at IS NULL THEN
        UPDATE public.explore_posts
        SET comment_count = GREATEST(comment_count - 1, 0)
        WHERE id = OLD.post_id;
    END IF;
    RETURN OLD;
END;
$$;

DROP FUNCTION IF EXISTS public.get_explore_comments(UUID, UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.get_explore_comments(
    self_id UUID,
    target_post_id UUID,
    max_limit INTEGER DEFAULT 50,
    comment_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    comment_id UUID,
    post_id UUID,
    author_user_id UUID,
    author_name TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN,
    viewer_can_moderate BOOLEAN,
    viewer_can_report BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.id AS comment_id,
        c.post_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        c.body,
        c.created_at,
        (c.user_id = self_id) AS viewer_can_delete,
        (ep.user_id = self_id AND c.user_id <> self_id) AS viewer_can_moderate,
        (c.user_id <> self_id) AS viewer_can_report
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = c.user_id
    WHERE c.post_id = target_post_id
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
    ORDER BY c.created_at ASC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0)
    OFFSET GREATEST(COALESCE(comment_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
BEGIN
    IF NEW.deleted_at IS NOT NULL OR NEW.moderated_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT ep.user_id
    INTO recipient_id
    FROM public.explore_posts ep
    WHERE ep.id = NEW.post_id
      AND ep.unshared_at IS NULL;

    IF recipient_id IS NULL OR recipient_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        type,
        comment_id,
        triggering_user_id,
        recent_actor_ids,
        action_count,
        is_read,
        created_at,
        updated_at
    )
    VALUES (
        recipient_id,
        NEW.post_id,
        'comment',
        NEW.id,
        NEW.user_id,
        ARRAY[]::UUID[],
        1,
        FALSE,
        COALESCE(NEW.created_at, NOW()),
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (comment_id)
    WHERE type = 'comment' AND comment_id IS NOT NULL
    DO NOTHING;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
    old_visible BOOLEAN := OLD.deleted_at IS NULL AND OLD.moderated_at IS NULL;
    new_visible BOOLEAN := NEW.deleted_at IS NULL AND NEW.moderated_at IS NULL;
BEGIN
    IF old_visible AND NOT new_visible THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = NEW.id
          AND type = 'comment';
    ELSIF NOT old_visible AND new_visible THEN
        SELECT ep.user_id
        INTO recipient_id
        FROM public.explore_posts ep
        WHERE ep.id = NEW.post_id
          AND ep.unshared_at IS NULL;

        IF recipient_id IS NOT NULL AND recipient_id <> NEW.user_id THEN
            INSERT INTO public.explore_post_notifications (
                user_id,
                post_id,
                type,
                comment_id,
                triggering_user_id,
                recent_actor_ids,
                action_count,
                is_read,
                created_at,
                updated_at
            )
            VALUES (
                recipient_id,
                NEW.post_id,
                'comment',
                NEW.id,
                NEW.user_id,
                ARRAY[]::UUID[],
                1,
                FALSE,
                COALESCE(NEW.created_at, NOW()),
                COALESCE(NEW.created_at, NOW())
            )
            ON CONFLICT (comment_id)
            WHERE type = 'comment' AND comment_id IS NOT NULL
            DO NOTHING;
        END IF;
    END IF;

    RETURN NEW;
END;
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
                  AND c.moderated_at IS NULL
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
              AND c.moderated_at IS NULL
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

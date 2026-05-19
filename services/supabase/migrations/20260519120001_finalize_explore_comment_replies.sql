ALTER TABLE public.explore_post_comments
ADD COLUMN IF NOT EXISTS parent_comment_id UUID REFERENCES public.explore_post_comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_explore_post_comments_parent_created_at_id_visible
    ON public.explore_post_comments(parent_comment_id, created_at, id)
    WHERE deleted_at IS NULL
      AND moderated_at IS NULL
      AND parent_comment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_explore_post_comments_post_top_level_created_at_id_visible
    ON public.explore_post_comments(post_id, created_at, id)
    WHERE deleted_at IS NULL
      AND moderated_at IS NULL
      AND parent_comment_id IS NULL;

CREATE OR REPLACE FUNCTION public.trg_explore_comment_reply_parent_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    parent_row RECORD;
BEGIN
    IF NEW.parent_comment_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_comment_id = NEW.id THEN
        RAISE EXCEPTION 'Explore replies cannot target themselves.';
    END IF;

    SELECT
        c.id,
        c.post_id,
        c.parent_comment_id,
        c.deleted_at,
        c.moderated_at
    INTO parent_row
    FROM public.explore_post_comments c
    WHERE c.id = NEW.parent_comment_id;

    IF parent_row.id IS NULL THEN
        RAISE EXCEPTION 'Explore reply parent comment not found.';
    END IF;

    IF parent_row.post_id <> NEW.post_id THEN
        RAISE EXCEPTION 'Explore replies must target a comment on the same post.';
    END IF;

    IF parent_row.parent_comment_id IS NOT NULL THEN
        RAISE EXCEPTION 'Explore replies can only target top-level comments.';
    END IF;

    IF parent_row.deleted_at IS NOT NULL OR parent_row.moderated_at IS NOT NULL THEN
        RAISE EXCEPTION 'Explore reply parent comment is not visible.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_comment_reply_parent_validate ON public.explore_post_comments;
CREATE TRIGGER trg_explore_comment_reply_parent_validate
BEFORE INSERT OR UPDATE OF post_id, parent_comment_id ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_comment_reply_parent_validate();

CREATE OR REPLACE FUNCTION public.recompute_explore_post_comment_count(target_post_id UUID)
RETURNS void
LANGUAGE SQL
AS $$
    UPDATE public.explore_posts ep
    SET comment_count = COALESCE((
        SELECT COUNT(*)::INTEGER
        FROM public.explore_post_comments c
        LEFT JOIN public.explore_post_comments parent
            ON parent.id = c.parent_comment_id
        WHERE c.post_id = target_post_id
          AND c.deleted_at IS NULL
          AND c.moderated_at IS NULL
          AND (
              c.parent_comment_id IS NULL
              OR (
                  parent.id IS NOT NULL
                  AND parent.parent_comment_id IS NULL
                  AND parent.deleted_at IS NULL
                  AND parent.moderated_at IS NULL
              )
          )
    ), 0)
    WHERE ep.id = target_post_id;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_recompute()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recompute_explore_post_comment_count(OLD.post_id);
        RETURN OLD;
    END IF;

    PERFORM public.recompute_explore_post_comment_count(NEW.post_id);
    IF TG_OP = 'UPDATE' AND OLD.post_id <> NEW.post_id THEN
        PERFORM public.recompute_explore_post_comment_count(OLD.post_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_insert ON public.explore_post_comments;
DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_update ON public.explore_post_comments;
DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_delete ON public.explore_post_comments;

CREATE TRIGGER trg_explore_post_comment_count_after_insert
AFTER INSERT ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_recompute();

CREATE TRIGGER trg_explore_post_comment_count_after_update
AFTER UPDATE ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_recompute();

CREATE TRIGGER trg_explore_post_comment_count_after_delete
AFTER DELETE ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_recompute();

DROP FUNCTION IF EXISTS public.get_explore_comments(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_comments(
    self_id UUID,
    target_post_id UUID,
    max_limit INTEGER DEFAULT 50,
    after_created_at TIMESTAMPTZ DEFAULT NULL,
    after_comment_id UUID DEFAULT NULL
)
RETURNS TABLE(
    comment_id UUID,
    post_id UUID,
    parent_comment_id UUID,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN,
    viewer_can_moderate BOOLEAN,
    viewer_can_report BOOLEAN,
    reply_count INTEGER,
    reactions JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.id AS comment_id,
        c.post_id,
        c.parent_comment_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        c.body,
        c.created_at,
        (c.user_id = self_id) AS viewer_can_delete,
        (ep.user_id = self_id AND c.user_id <> self_id) AS viewer_can_moderate,
        (c.user_id <> self_id) AS viewer_can_report,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.explore_post_comments reply
            JOIN public.users reply_author
                ON reply_author.id = reply.user_id
            WHERE reply.parent_comment_id = c.id
              AND reply.deleted_at IS NULL
              AND reply.moderated_at IS NULL
              AND reply_author.is_shadowbanned = FALSE
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = reply.user_id)
                     OR (ub.blocker_id = reply.user_id AND ub.blocked_id = self_id)
              )
        ) AS reply_count,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'emoji', r.emoji,
                    'count', r.count,
                    'viewer_has_reacted', r.viewer_has_reacted
                )
            )
            FROM (
                SELECT emoji, COUNT(*) AS count, bool_or(user_id = self_id) AS viewer_has_reacted
                FROM public.explore_comment_reactions
                WHERE comment_id = c.id
                GROUP BY emoji
            ) r
        ) AS reactions
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = c.user_id
    WHERE c.post_id = target_post_id
      AND c.parent_comment_id IS NULL
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
             OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
      )
      AND (
          after_created_at IS NULL
          OR after_comment_id IS NULL
          OR c.created_at > after_created_at
          OR (c.created_at = after_created_at AND c.id > after_comment_id)
      )
    ORDER BY c.created_at ASC, c.id ASC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_comment_replies(
    self_id UUID,
    target_parent_comment_id UUID,
    max_limit INTEGER DEFAULT 25,
    after_created_at TIMESTAMPTZ DEFAULT NULL,
    after_comment_id UUID DEFAULT NULL
)
RETURNS TABLE(
    comment_id UUID,
    post_id UUID,
    parent_comment_id UUID,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN,
    viewer_can_moderate BOOLEAN,
    viewer_can_report BOOLEAN,
    reply_count INTEGER,
    reactions JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.id AS comment_id,
        c.post_id,
        c.parent_comment_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        c.body,
        c.created_at,
        (c.user_id = self_id) AS viewer_can_delete,
        (ep.user_id = self_id AND c.user_id <> self_id) AS viewer_can_moderate,
        (c.user_id <> self_id) AS viewer_can_report,
        0 AS reply_count,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'emoji', r.emoji,
                    'count', r.count,
                    'viewer_has_reacted', r.viewer_has_reacted
                )
            )
            FROM (
                SELECT emoji, COUNT(*) AS count, bool_or(user_id = self_id) AS viewer_has_reacted
                FROM public.explore_comment_reactions
                WHERE comment_id = c.id
                GROUP BY emoji
            ) r
        ) AS reactions
    FROM public.explore_post_comments c
    JOIN public.explore_post_comments parent
        ON parent.id = c.parent_comment_id
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = c.user_id
    WHERE c.parent_comment_id = target_parent_comment_id
      AND parent.parent_comment_id IS NULL
      AND parent.deleted_at IS NULL
      AND parent.moderated_at IS NULL
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
             OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
             OR (ub.blocker_id = self_id AND ub.blocked_id = parent.user_id)
             OR (ub.blocker_id = parent.user_id AND ub.blocked_id = self_id)
      )
      AND (
          after_created_at IS NULL
          OR after_comment_id IS NULL
          OR c.created_at > after_created_at
          OR (c.created_at = after_created_at AND c.id > after_comment_id)
      )
    ORDER BY c.created_at ASC, c.id ASC
    LIMIT GREATEST(COALESCE(max_limit, 25), 0);
$$;

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
        type = 'comment_reply'
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

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_comment_reply_unique
    ON public.explore_post_notifications(user_id, comment_id, type)
    WHERE type = 'comment_reply' AND comment_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.insert_explore_comment_reply_notifications(target_reply_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    reply_row RECORD;
    recipient_id UUID;
BEGIN
    SELECT
        reply.id,
        reply.post_id,
        reply.user_id,
        reply.created_at,
        parent.user_id AS parent_user_id,
        ep.user_id AS post_owner_user_id,
        actor.is_shadowbanned AS actor_is_shadowbanned
    INTO reply_row
    FROM public.explore_post_comments reply
    JOIN public.explore_post_comments parent
        ON parent.id = reply.parent_comment_id
    JOIN public.explore_posts ep
        ON ep.id = reply.post_id
    JOIN public.users actor
        ON actor.id = reply.user_id
    WHERE reply.id = target_reply_id
      AND reply.parent_comment_id IS NOT NULL
      AND reply.deleted_at IS NULL
      AND reply.moderated_at IS NULL
      AND parent.parent_comment_id IS NULL
      AND parent.deleted_at IS NULL
      AND parent.moderated_at IS NULL
      AND ep.unshared_at IS NULL;

    IF reply_row.id IS NULL OR reply_row.actor_is_shadowbanned THEN
        RETURN;
    END IF;

    FOR recipient_id IN
        SELECT DISTINCT candidate_id
        FROM (
            VALUES
                (reply_row.parent_user_id),
                (CASE
                    WHEN reply_row.post_owner_user_id <> reply_row.parent_user_id
                    THEN reply_row.post_owner_user_id
                    ELSE NULL
                END)
        ) AS recipients(candidate_id)
        WHERE candidate_id IS NOT NULL
          AND candidate_id <> reply_row.user_id
    LOOP
        IF EXISTS (
            SELECT 1
            FROM public.user_blocks ub
            WHERE (ub.blocker_id = recipient_id AND ub.blocked_id = reply_row.user_id)
               OR (ub.blocker_id = reply_row.user_id AND ub.blocked_id = recipient_id)
        ) THEN
            CONTINUE;
        END IF;

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
            recipient_id,
            reply_row.post_id,
            'comment_reply',
            reply_row.id,
            NULL,
            reply_row.user_id,
            ARRAY[]::UUID[],
            1,
            FALSE,
            COALESCE(reply_row.created_at, NOW()),
            COALESCE(reply_row.created_at, NOW())
        )
        ON CONFLICT (user_id, comment_id, type)
        WHERE type = 'comment_reply' AND comment_id IS NOT NULL
        DO NOTHING;
    END LOOP;
END;
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

    IF NEW.parent_comment_id IS NOT NULL THEN
        PERFORM public.insert_explore_comment_reply_notifications(NEW.id);
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
    reaction_row RECORD;
    old_visible BOOLEAN := OLD.deleted_at IS NULL AND OLD.moderated_at IS NULL;
    new_visible BOOLEAN := NEW.deleted_at IS NULL AND NEW.moderated_at IS NULL;
BEGIN
    IF old_visible AND NOT new_visible THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = NEW.id
          AND type IN ('comment', 'comment_reply', 'comment_reaction');
    ELSIF NOT old_visible AND new_visible THEN
        IF NEW.parent_comment_id IS NOT NULL THEN
            PERFORM public.insert_explore_comment_reply_notifications(NEW.id);
        ELSE
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

        FOR reaction_row IN
            SELECT DISTINCT r.emoji
            FROM public.explore_comment_reactions r
            WHERE r.comment_id = NEW.id
        LOOP
            PERFORM public.sync_comment_reaction_notification_for_comment(
                NEW.id,
                reaction_row.emoji,
                TRUE
            );
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_comment_reaction_notification_for_comment(
    target_comment_id UUID,
    target_emoji TEXT,
    mark_unread BOOLEAN DEFAULT TRUE
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
    target_post_id UUID;
    total_count INTEGER;
    recent_actor_ids UUID[];
    latest_actor_id UUID;
BEGIN
    SELECT
        c.user_id,
        c.post_id
    INTO
        recipient_id,
        target_post_id
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    LEFT JOIN public.explore_post_comments parent
        ON parent.id = c.parent_comment_id
    WHERE c.id = target_comment_id
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND (
          c.parent_comment_id IS NULL
          OR (
              parent.parent_comment_id IS NULL
              AND parent.deleted_at IS NULL
              AND parent.moderated_at IS NULL
          )
      )
      AND ep.unshared_at IS NULL;

    IF recipient_id IS NULL OR target_post_id IS NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = target_comment_id
          AND type = 'comment_reaction'
          AND reaction_emoji = target_emoji;
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO total_count
    FROM public.explore_comment_reactions r
    WHERE r.comment_id = target_comment_id
      AND r.emoji = target_emoji
      AND r.user_id <> recipient_id;

    IF COALESCE(total_count, 0) = 0 THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = recipient_id
          AND comment_id = target_comment_id
          AND type = 'comment_reaction'
          AND reaction_emoji = target_emoji;
        RETURN;
    END IF;

    recent_actor_ids := COALESCE(ARRAY(
        SELECT r.user_id
        FROM public.explore_comment_reactions r
        WHERE r.comment_id = target_comment_id
          AND r.emoji = target_emoji
          AND r.user_id <> recipient_id
        ORDER BY r.created_at DESC
        LIMIT 3
    ), ARRAY[]::UUID[]);

    latest_actor_id := recent_actor_ids[1];

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
        recipient_id,
        target_post_id,
        'comment_reaction',
        target_comment_id,
        target_emoji,
        latest_actor_id,
        recent_actor_ids,
        total_count,
        FALSE,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, comment_id, reaction_emoji)
    WHERE type = 'comment_reaction' AND comment_id IS NOT NULL AND reaction_emoji IS NOT NULL
    DO UPDATE SET
        post_id = EXCLUDED.post_id,
        triggering_user_id = EXCLUDED.triggering_user_id,
        recent_actor_ids = EXCLUDED.recent_actor_ids,
        action_count = EXCLUDED.action_count,
        is_read = CASE
            WHEN mark_unread THEN FALSE
            ELSE explore_post_notifications.is_read
        END,
        updated_at = NOW();
END;
$$;

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
    parent_comment_id UUID,
    reaction_emoji TEXT,
    triggering_user_id UUID,
    triggering_user_name TEXT,
    comment_body TEXT,
    recent_actor_names TEXT[],
    action_count INTEGER,
    is_read BOOLEAN,
    is_reply_to_viewer_comment BOOLEAN,
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
        LEFT JOIN public.explore_post_comments parent
            ON parent.id = c.parent_comment_id
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
                              c.parent_comment_id IS NULL
                              OR (
                                  parent.id IS NOT NULL
                                  AND parent.parent_comment_id IS NULL
                                  AND parent.deleted_at IS NULL
                                  AND parent.moderated_at IS NULL
                              )
                          )
                          AND (
                              (
                                  n.type IN ('comment', 'comment_reply')
                                  AND n.triggering_user_id IS NOT NULL
                                  AND actor.id IS NOT NULL
                                  AND actor.is_shadowbanned = FALSE
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
        c.parent_comment_id,
        n.reaction_emoji,
        n.triggering_user_id,
        CASE
            WHEN n.type IN ('comment', 'comment_reply', 'follow') THEN actor.public_author_name
            WHEN COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0 THEN actor_names.recent_actor_names[1]
            ELSE NULL
        END AS triggering_user_name,
        c.body AS comment_body,
        COALESCE(actor_names.recent_actor_names, ARRAY[]::TEXT[]) AS recent_actor_names,
        n.action_count,
        n.is_read,
        (n.type = 'comment_reply' AND parent.user_id = self_id) AS is_reply_to_viewer_comment,
        n.created_at,
        n.updated_at
    FROM visible_notifications n
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
       AND c.deleted_at IS NULL
       AND c.moderated_at IS NULL
    LEFT JOIN public.explore_post_comments parent
        ON parent.id = c.parent_comment_id
       AND parent.deleted_at IS NULL
       AND parent.moderated_at IS NULL
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
    FROM public.get_explore_notifications(self_id, 1000000, NULL, NULL) n
    WHERE n.is_read = FALSE;
$$;

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    reaction_emoji TEXT,
    comment_body TEXT,
    triggering_user_name TEXT,
    recent_actor_names TEXT[],
    is_reply_to_viewer_comment BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        n.notification_id,
        epn.user_id AS recipient_user_id,
        n.post_id,
        n.type,
        n.action_count,
        n.reaction_emoji,
        n.comment_body,
        n.triggering_user_name,
        n.recent_actor_names,
        n.is_reply_to_viewer_comment
    FROM public.explore_post_notifications epn
    JOIN LATERAL public.get_explore_notifications(epn.user_id, 1000000, NULL, NULL) n
        ON n.notification_id = epn.id
    WHERE epn.id = target_notification_id
      AND n.type <> 'follow';
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

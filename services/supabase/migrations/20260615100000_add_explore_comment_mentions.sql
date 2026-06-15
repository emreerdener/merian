CREATE TABLE IF NOT EXISTS public.explore_comment_mentions (
    comment_id UUID NOT NULL REFERENCES public.explore_post_comments(id) ON DELETE CASCADE,
    mentioned_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    mention_username TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comment_id, mentioned_user_id),
    CONSTRAINT explore_comment_mentions_username_valid_check
        CHECK (public.is_valid_public_username(mention_username))
);

ALTER TABLE public.explore_comment_mentions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'explore_comment_mentions'
          AND policyname = 'Users can read mentions on visible comments through RPCs'
    ) THEN
        CREATE POLICY "Users can read mentions on visible comments through RPCs"
            ON public.explore_comment_mentions
            FOR SELECT
            USING (FALSE);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_explore_comment_mentions_user_created_at
    ON public.explore_comment_mentions(mentioned_user_id, created_at DESC, comment_id);

CREATE OR REPLACE FUNCTION public.normalize_explore_mention_query(raw_query TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT REGEXP_REPLACE(
        REGEXP_REPLACE(LOWER(REGEXP_REPLACE(BTRIM(COALESCE(raw_query, '')), '^@+', '')), '[^a-z0-9_]+', '', 'g'),
        '_{2,}',
        '_',
        'g'
    );
$$;

CREATE OR REPLACE FUNCTION public.can_mention_explore_user(
    self_id UUID,
    target_post_id UUID,
    target_user_id UUID,
    target_parent_comment_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT target_user_id <> self_id
      AND EXISTS (
          SELECT 1
          FROM public.users candidate
          WHERE candidate.id = target_user_id
            AND candidate.is_shadowbanned = FALSE
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = target_user_id)
             OR (ub.blocker_id = target_user_id AND ub.blocked_id = self_id)
      )
      AND public.can_view_explore_author_profile(self_id, target_user_id)
      AND (
          EXISTS (
              SELECT 1
              FROM public.explore_posts ep
              WHERE ep.id = target_post_id
                AND ep.user_id = target_user_id
          )
          OR EXISTS (
              SELECT 1
              FROM public.explore_post_comments c
              JOIN public.users author
                  ON author.id = c.user_id
              LEFT JOIN public.explore_post_comments parent
                  ON parent.id = c.parent_comment_id
              WHERE c.post_id = target_post_id
                AND c.user_id = target_user_id
                AND c.deleted_at IS NULL
                AND c.moderated_at IS NULL
                AND author.is_shadowbanned = FALSE
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
                    target_parent_comment_id IS NULL
                    OR c.id = target_parent_comment_id
                    OR c.parent_comment_id = target_parent_comment_id
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.user_blocks ub
                    WHERE (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
                       OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
                )
          )
          OR EXISTS (
              SELECT 1
              FROM public.user_follows uf
              WHERE uf.follower_user_id = self_id
                AND uf.followee_user_id = target_user_id
          )
      );
$$;

CREATE OR REPLACE FUNCTION public.get_explore_mention_suggestions(
    self_id UUID,
    target_post_id UUID,
    target_parent_comment_id UUID DEFAULT NULL,
    raw_query TEXT DEFAULT '',
    max_limit INTEGER DEFAULT 8
)
RETURNS TABLE(
    user_id UUID,
    username TEXT,
    display_name TEXT,
    avatar_url TEXT,
    source TEXT
)
LANGUAGE SQL
STABLE
AS $$
    WITH query_input AS (
        SELECT public.normalize_explore_mention_query(raw_query) AS query
    ),
    eligible_post AS (
        SELECT ep.id
        FROM public.explore_posts ep
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users owner
            ON owner.id = ep.user_id
        WHERE ep.id = target_post_id
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND owner.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
          )
    ),
    parent_guard AS (
        SELECT TRUE AS ok
        WHERE target_parent_comment_id IS NULL
        UNION ALL
        SELECT TRUE
        FROM public.explore_post_comments parent
        WHERE parent.id = target_parent_comment_id
          AND parent.post_id = target_post_id
          AND parent.parent_comment_id IS NULL
          AND parent.deleted_at IS NULL
          AND parent.moderated_at IS NULL
    ),
    candidates AS (
        SELECT ep.user_id, 1 AS priority, 'post_author'::TEXT AS source
        FROM public.explore_posts ep
        WHERE ep.id = target_post_id

        UNION ALL

        SELECT c.user_id, 2 AS priority, 'thread'::TEXT AS source
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
          AND (
              target_parent_comment_id IS NULL
              OR c.id = target_parent_comment_id
              OR c.parent_comment_id = target_parent_comment_id
          )

        UNION ALL

        SELECT uf.followee_user_id, 3 AS priority, 'following'::TEXT AS source
        FROM public.user_follows uf
        CROSS JOIN query_input qi
        WHERE uf.follower_user_id = self_id
          AND CHAR_LENGTH(qi.query) >= 2
    ),
    ranked AS (
        SELECT DISTINCT ON (candidate.id)
            candidate.id,
            candidate.public_username,
            candidate.public_author_name,
            candidate.public_avatar_url,
            c.source,
            c.priority
        FROM candidates c
        JOIN public.users candidate
            ON candidate.id = c.user_id
        CROSS JOIN query_input qi
        WHERE EXISTS (SELECT 1 FROM eligible_post)
          AND EXISTS (SELECT 1 FROM parent_guard)
          AND candidate.id <> self_id
          AND candidate.is_shadowbanned = FALSE
          AND public.can_mention_explore_user(self_id, target_post_id, candidate.id, target_parent_comment_id)
          AND (
              qi.query = ''
              OR candidate.public_username LIKE qi.query || '%'
          )
        ORDER BY candidate.id, c.priority
    )
    SELECT
        ranked.id AS user_id,
        ranked.public_username AS username,
        ranked.public_author_name AS display_name,
        ranked.public_avatar_url AS avatar_url,
        ranked.source
    FROM ranked
    ORDER BY ranked.priority, ranked.public_username
    LIMIT GREATEST(COALESCE(max_limit, 8), 0);
$$;

CREATE OR REPLACE FUNCTION public.comment_mention_projection(target_comment_id UUID)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'user_id', m.mentioned_user_id,
                'username', m.mention_username,
                'display_name', u.public_author_name,
                'avatar_url', u.public_avatar_url
            )
            ORDER BY m.created_at, m.mention_username
        ),
        '[]'::jsonb
    )
    FROM public.explore_comment_mentions m
    JOIN public.users u
        ON u.id = m.mentioned_user_id
    WHERE m.comment_id = target_comment_id
      AND u.is_shadowbanned = FALSE;
$$;

CREATE OR REPLACE FUNCTION public.insert_explore_comment_mention_notifications(target_comment_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    comment_row RECORD;
    mention_row RECORD;
BEGIN
    SELECT
        c.id,
        c.post_id,
        c.user_id,
        c.created_at,
        c.deleted_at,
        c.moderated_at,
        ep.unshared_at
    INTO comment_row
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    WHERE c.id = target_comment_id;

    IF comment_row.id IS NULL
       OR comment_row.deleted_at IS NOT NULL
       OR comment_row.moderated_at IS NOT NULL
       OR comment_row.unshared_at IS NOT NULL THEN
        RETURN;
    END IF;

    FOR mention_row IN
        SELECT m.mentioned_user_id
        FROM public.explore_comment_mentions m
        JOIN public.users recipient
            ON recipient.id = m.mentioned_user_id
        WHERE m.comment_id = target_comment_id
          AND recipient.is_shadowbanned = FALSE
          AND m.mentioned_user_id <> comment_row.user_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = m.mentioned_user_id AND ub.blocked_id = comment_row.user_id)
                 OR (ub.blocker_id = comment_row.user_id AND ub.blocked_id = m.mentioned_user_id)
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.explore_post_notifications existing
              WHERE existing.user_id = m.mentioned_user_id
                AND existing.comment_id = target_comment_id
                AND existing.type IN ('comment', 'comment_reply', 'comment_mention')
          )
    LOOP
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
            mention_row.mentioned_user_id,
            comment_row.post_id,
            'comment_mention',
            comment_row.id,
            NULL,
            comment_row.user_id,
            ARRAY[]::UUID[],
            1,
            FALSE,
            COALESCE(comment_row.created_at, NOW()),
            COALESCE(comment_row.created_at, NOW())
        )
        ON CONFLICT (user_id, comment_id, type)
        WHERE type = 'comment_mention' AND comment_id IS NOT NULL
        DO NOTHING;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.insert_explore_comment_mentions_from_body(
    target_comment_id UUID,
    actor_user_id UUID
)
RETURNS TABLE(
    user_id UUID,
    username TEXT,
    display_name TEXT,
    avatar_url TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    comment_row RECORD;
BEGIN
    SELECT
        c.id,
        c.post_id,
        c.parent_comment_id,
        c.user_id,
        c.body
    INTO comment_row
    FROM public.explore_post_comments c
    WHERE c.id = target_comment_id;

    IF comment_row.id IS NULL THEN
        RAISE EXCEPTION 'Explore comment not found.';
    END IF;

    IF comment_row.user_id <> actor_user_id THEN
        RAISE EXCEPTION 'Mention actor does not own this comment.';
    END IF;

    INSERT INTO public.explore_comment_mentions (
        comment_id,
        mentioned_user_id,
        mention_username,
        created_at
    )
    SELECT
        target_comment_id,
        resolved_mentions.id,
        resolved_mentions.public_username,
        NOW()
    FROM (
        SELECT
            resolved.id,
            resolved.public_username,
            mentions.first_ord
        FROM (
            SELECT parsed.username, MIN(parsed.ord) AS first_ord
            FROM (
                SELECT LOWER(match[2]) AS username, ord
                FROM regexp_matches(
                    comment_row.body,
                    '(^|[^A-Za-z0-9_])@([A-Za-z][A-Za-z0-9_]{1,22}[A-Za-z0-9])',
                    'g'
                ) WITH ORDINALITY AS mention_match(match, ord)
            ) parsed
            GROUP BY parsed.username
        ) mentions
        JOIN public.users resolved
            ON resolved.public_username = mentions.username
        WHERE public.can_mention_explore_user(
            actor_user_id,
            comment_row.post_id,
            resolved.id,
            comment_row.parent_comment_id
        )
        ORDER BY mentions.first_ord
        LIMIT 5
    ) resolved_mentions
    ON CONFLICT (comment_id, mentioned_user_id) DO NOTHING;

    PERFORM public.insert_explore_comment_mention_notifications(target_comment_id);

    RETURN QUERY
    SELECT
        m.mentioned_user_id AS user_id,
        m.mention_username AS username,
        u.public_author_name AS display_name,
        u.public_avatar_url AS avatar_url
    FROM public.explore_comment_mentions m
    JOIN public.users u
        ON u.id = m.mentioned_user_id
    WHERE m.comment_id = target_comment_id
    ORDER BY m.created_at, m.mention_username;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_comment_mention_unique
    ON public.explore_post_notifications(user_id, comment_id, type)
    WHERE type = 'comment_mention' AND comment_id IS NOT NULL;

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
        type = 'comment_mention'
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
    reactions JSONB,
    mentions JSONB
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
        ) AS reactions,
        public.comment_mention_projection(c.id) AS mentions
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

DROP FUNCTION IF EXISTS public.get_explore_comment_replies(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID);

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
    reactions JSONB,
    mentions JSONB
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
        ) AS reactions,
        public.comment_mention_projection(c.id) AS mentions
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
          AND type IN ('comment', 'comment_reply', 'comment_reaction', 'comment_mention');
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

        PERFORM public.insert_explore_comment_mention_notifications(NEW.id);

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
                                  n.type IN ('comment', 'comment_reply', 'comment_mention')
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
            WHEN n.type IN ('comment', 'comment_reply', 'comment_mention', 'follow') THEN actor.public_author_name
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

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    comment_id UUID,
    parent_comment_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    reaction_emoji TEXT,
    comment_body TEXT,
    triggering_user_name TEXT,
    recent_actor_names TEXT[],
    is_reply_to_viewer_comment BOOLEAN,
    unread_count INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        n.notification_id,
        epn.user_id AS recipient_user_id,
        n.post_id,
        n.comment_id,
        n.parent_comment_id,
        n.type,
        n.action_count,
        n.reaction_emoji,
        n.comment_body,
        n.triggering_user_name,
        n.recent_actor_names,
        n.is_reply_to_viewer_comment,
        public.get_unread_explore_notification_count(epn.user_id) AS unread_count
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
        service_role_key := current_setting('app.settings.supabase_service_role_key', true);
    END IF;

    IF project_url IS NULL OR service_role_key IS NULL THEN
        RAISE WARNING 'Explore push delivery skipped: missing Supabase URL or service role key.';
        RETURN NEW;
    END IF;

    edge_endpoint := RTRIM(project_url, '/') || '/functions/v1/send-push-notification';

    PERFORM net.http_post(
        url := edge_endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object('notification_id', NEW.id),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
END;
$$;

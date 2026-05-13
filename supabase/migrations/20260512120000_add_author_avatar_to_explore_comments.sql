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
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN,
    viewer_can_moderate BOOLEAN,
    viewer_can_report BOOLEAN,
    reactions JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.id AS comment_id,
        c.post_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        u.public_avatar_url AS author_avatar_url,
        c.body,
        c.created_at,
        (c.user_id = self_id) AS viewer_can_delete,
        (ep.user_id = self_id AND c.user_id <> self_id) AS viewer_can_moderate,
        (c.user_id <> self_id) AS viewer_can_report,
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

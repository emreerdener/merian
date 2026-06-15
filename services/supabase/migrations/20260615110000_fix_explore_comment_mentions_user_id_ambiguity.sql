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

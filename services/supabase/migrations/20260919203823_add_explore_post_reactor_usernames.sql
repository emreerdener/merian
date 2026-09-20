-- Add public usernames without changing existing names, visibility, pagination, or caller grants.
CREATE OR REPLACE FUNCTION public.get_explore_post_reactors(
    self_id UUID, target_post_id UUID, after_user_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.explore_reaction_post(self_id, 'post', target_post_id);
    RETURN (
        WITH source AS (
            SELECT r.user_id, r.emoji FROM public.explore_post_reactions r WHERE r.post_id = target_post_id
            UNION ALL
            SELECT l.user_id, '❤️'::TEXT FROM public.explore_post_likes l WHERE l.post_id = target_post_id
        ), visible AS MATERIALIZED (
            SELECT DISTINCT r.user_id, e.emoji, e.ordinal
            FROM source r
            JOIN internal.explore_emoji_catalog e ON e.emoji = r.emoji
            JOIN public.users u ON u.id = r.user_id AND NOT u.is_shadowbanned
            WHERE NOT EXISTS (SELECT 1 FROM public.user_blocks b
                WHERE (b.blocker_id = self_id AND b.blocked_id = r.user_id)
                   OR (b.blocked_id = self_id AND b.blocker_id = r.user_id))
        ), actors AS MATERIALIZED (
            SELECT DISTINCT v.user_id FROM visible v
        ), candidates AS (
            SELECT a.user_id FROM actors a
            WHERE after_user_id IS NULL OR a.user_id > after_user_id
            ORDER BY a.user_id LIMIT 33
        ), page AS (
            SELECT c.user_id FROM candidates c ORDER BY c.user_id LIMIT 32
        )
        SELECT jsonb_build_object(
            'total_count', (SELECT count(*) FROM actors),
            'preview_names', COALESCE((SELECT jsonb_agg(p.display_name ORDER BY p.user_id) FROM (
                SELECT a.user_id, COALESCE(NULLIF(btrim(u.public_author_name), ''), 'Nature lover') AS display_name
                FROM actors a JOIN public.users u ON u.id = a.user_id ORDER BY a.user_id LIMIT 2
            ) p), '[]'::JSONB),
            'reactors', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'user_id', p.user_id,
                'display_name', COALESCE(NULLIF(btrim(u.public_author_name), ''), 'Nature lover'),
                'username', u.public_username,
                'avatar_url', u.public_avatar_url,
                'emojis', (SELECT jsonb_agg(v.emoji ORDER BY v.ordinal) FROM visible v WHERE v.user_id = p.user_id)
            ) ORDER BY p.user_id) FROM page p JOIN public.users u ON u.id = p.user_id), '[]'::JSONB),
            'next_cursor', CASE WHEN (SELECT count(*) FROM candidates) > 32
                THEN (SELECT p.user_id FROM page p ORDER BY p.user_id DESC LIMIT 1) ELSE NULL END
        )
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_explore_post_reactors(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_post_reactors(UUID,UUID,UUID) TO service_role;

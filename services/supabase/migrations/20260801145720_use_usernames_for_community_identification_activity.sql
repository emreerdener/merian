-- Community Identify activity summaries identify people by their stable public
-- usernames rather than by profile/display names. Keep the existing
-- recent_actor_names wire field for compatibility; its values are usernames.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.get_community_identification_activity(
    self_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_activity_at TIMESTAMPTZ DEFAULT NULL,
    before_activity_id UUID DEFAULT NULL,
    request_scope TEXT DEFAULT 'all',
    request_group_filter TEXT DEFAULT 'all'
)
RETURNS TABLE(
    activity_id UUID,
    activity_type TEXT,
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    activity_at TIMESTAMPTZ,
    suggestion_count INTEGER,
    recent_actor_names TEXT[],
    taxon_id UUID,
    taxon_common_name TEXT,
    taxon_scientific_name TEXT,
    taxon_rank TEXT,
    consensus_score DOUBLE PRECISION,
    request_group TEXT,
    media_items JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    WITH visible_activity AS (
        SELECT
            activity_group.id AS activity_id,
            activity_group.activity_type,
            community_request.id AS request_id,
            explore_post.id AS post_id,
            explore_post.scan_id,
            public.explore_post_hero_image_url(explore_post.id)
                AS hero_image_url,
            activity_group.activity_at,
            CASE
                WHEN activity_group.activity_type = 'suggestion_burst'
                THEN visible_actor_count.suggestion_count
                ELSE 0
            END AS suggestion_count,
            CASE
                WHEN activity_group.activity_type = 'suggestion_burst'
                THEN recent_actors.actor_usernames
                ELSE ARRAY[]::TEXT[]
            END AS recent_actor_names,
            display_taxon.id AS taxon_id,
            display_taxon.common_name AS taxon_common_name,
            display_taxon.scientific_name AS taxon_scientific_name,
            display_taxon.rank AS taxon_rank,
            activity_group.consensus_score,
            public.community_identification_request_group(filter_taxon.id)
                AS request_group,
            public.explore_post_media_items(explore_post.id) AS media_items
        FROM internal.community_identification_activity_groups AS activity_group
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = activity_group.request_id
           AND community_request.post_id = activity_group.post_id
           AND community_request.requested_at
                = activity_group.request_generation_at
        INNER JOIN public.explore_observation_projection AS projection
            ON projection.community_request_id = community_request.id
        INNER JOIN public.explore_posts AS explore_post
            ON explore_post.id = community_request.post_id
        INNER JOIN public.scans AS scan
            ON scan.id = explore_post.scan_id
        INNER JOIN public.users AS request_owner
            ON request_owner.id = explore_post.user_id
        LEFT JOIN public.taxon_nodes AS filter_taxon
            ON filter_taxon.id = COALESCE(
                community_request.current_community_taxon_node_id,
                community_request.resolved_taxon_node_id,
                community_request.initial_taxon_node_id
            )
        LEFT JOIN public.taxon_nodes AS display_taxon
            ON display_taxon.id = COALESCE(
                activity_group.latest_taxon_node_id,
                community_request.current_community_taxon_node_id,
                community_request.resolved_taxon_node_id,
                community_request.initial_taxon_node_id
            )
        LEFT JOIN LATERAL (
            SELECT COALESCE(
                SUM(activity_actor.suggestion_count),
                0
            )::INTEGER AS suggestion_count
            FROM internal.community_identification_activity_actors
                AS activity_actor
            INNER JOIN public.users AS actor_user
                ON actor_user.id = activity_actor.user_id
            WHERE activity_actor.activity_group_id = activity_group.id
              AND actor_user.is_shadowbanned = FALSE
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks AS actor_block
                  WHERE (
                      actor_block.blocker_id = self_id
                      AND actor_block.blocked_id = actor_user.id
                  ) OR (
                      actor_block.blocker_id = actor_user.id
                      AND actor_block.blocked_id = self_id
                  )
              )
        ) AS visible_actor_count ON TRUE
        LEFT JOIN LATERAL (
            SELECT COALESCE(
                ARRAY_AGG(
                    recent_actor.actor_username
                    ORDER BY
                        recent_actor.last_suggested_at DESC,
                        recent_actor.user_id DESC
                ),
                ARRAY[]::TEXT[]
            ) AS actor_usernames
            FROM (
                SELECT
                    activity_actor.user_id,
                    actor_user.public_username AS actor_username,
                    activity_actor.last_suggested_at
                FROM internal.community_identification_activity_actors
                    AS activity_actor
                INNER JOIN public.users AS actor_user
                    ON actor_user.id = activity_actor.user_id
                WHERE activity_actor.activity_group_id = activity_group.id
                  AND actor_user.is_shadowbanned = FALSE
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks AS actor_block
                      WHERE (
                          actor_block.blocker_id = self_id
                          AND actor_block.blocked_id = actor_user.id
                      ) OR (
                          actor_block.blocker_id = actor_user.id
                          AND actor_block.blocked_id = self_id
                      )
                  )
                ORDER BY
                    activity_actor.last_suggested_at DESC,
                    activity_actor.user_id DESC
                LIMIT 3
            ) AS recent_actor
        ) AS recent_actors ON TRUE
        WHERE community_request.withdrawn_at IS NULL
          AND explore_post.unshared_at IS NULL
          AND explore_post.moderated_at IS NULL
          AND explore_post.media_health_status <> 'quarantined'
          AND scan.is_tombstoned = FALSE
          AND request_owner.is_shadowbanned = FALSE
          AND EXISTS (
              SELECT 1
              FROM public.explore_post_media AS visible_media
              WHERE visible_media.post_id = explore_post.id
                AND visible_media.health_status <> 'missing'
          )
          AND (
              activity_group.activity_type <> 'suggestion_burst'
              OR visible_actor_count.suggestion_count > 0
          )
          AND (
              COALESCE(request_scope, 'all') = 'all'
              OR (
                  request_scope = 'mine'
                  AND community_request.requested_by = self_id
              )
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks AS owner_block
              WHERE (
                  owner_block.blocker_id = self_id
                  AND owner_block.blocked_id = explore_post.user_id
              ) OR (
                  owner_block.blocker_id = explore_post.user_id
                  AND owner_block.blocked_id = self_id
              )
          )
          AND (
              before_activity_at IS NULL
              OR before_activity_id IS NULL
              OR activity_group.activity_at < before_activity_at
              OR (
                  activity_group.activity_at = before_activity_at
                  AND activity_group.id < before_activity_id
              )
          )
    )
    SELECT
        activity_id,
        activity_type,
        request_id,
        post_id,
        scan_id,
        hero_image_url,
        activity_at,
        suggestion_count,
        recent_actor_names,
        taxon_id,
        taxon_common_name,
        taxon_scientific_name,
        taxon_rank,
        consensus_score,
        request_group,
        media_items
    FROM visible_activity
    WHERE COALESCE(request_group_filter, 'all') = 'all'
       OR request_group = request_group_filter
    ORDER BY activity_at DESC, activity_id DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 30), 0), 100);
$function$;

REVOKE ALL ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) TO service_role;

COMMENT ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) IS
    'Service-only cursor feed of visible grouped Community Identify activity, attributed by public username.';

RESET lock_timeout;
RESET statement_timeout;

NOTIFY pgrst, 'reload schema';

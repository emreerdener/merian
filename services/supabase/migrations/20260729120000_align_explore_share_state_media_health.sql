-- Align the owner-facing scan share state with the same media-health and
-- moderation boundaries used by every public Explore projection.
--
-- Preserve the post/request identifiers for owner recovery even while a post
-- is hidden. `is_explore_feed_visible` is the authoritative public-projection
-- decision; publication intent alone must never be reported as visibility.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.get_scan_explore_share_state(
    self_id UUID,
    target_scan_id UUID
)
RETURNS TABLE(
    scan_id UUID,
    post_id UUID,
    shared_at TIMESTAMPTZ,
    community_request_id UUID,
    community_request_status TEXT,
    is_explore_feed_visible BOOLEAN,
    location_sharing TEXT
)
LANGUAGE SQL
STABLE
SET search_path = ''
AS $function$
    WITH state AS (
        SELECT
            scan.id AS scan_id,
            post.id AS post_id,
            post.shared_at,
            post.location_sharing AS post_location_sharing,
            community_request.id AS community_request_id,
            community_request.status AS community_request_status,
            community_request.explore_published_at,
            scan.geoprivacy::TEXT AS scan_geoprivacy,
            (
                post.id IS NOT NULL
                AND NOT scan.is_tombstoned
                AND EXISTS (
                    SELECT 1
                    FROM public.explore_post_media AS media
                    WHERE media.post_id = post.id
                )
                AND COALESCE(
                    scan.confirmed_species_id,
                    scan.species_id
                ) IS NOT NULL
                AND NOT scan_owner.is_shadowbanned
            ) AS has_live_post,
            (
                post.id IS NOT NULL
                AND post.moderated_at IS NULL
                AND post.media_health_status <> 'quarantined'
                AND EXISTS (
                    SELECT 1
                    FROM public.explore_post_media AS media
                    WHERE media.post_id = post.id
                      AND media.health_status <> 'missing'
                )
            ) AS is_projection_eligible
        FROM public.scans AS scan
        INNER JOIN public.users AS scan_owner
            ON scan_owner.id = scan.user_id
        LEFT JOIN LATERAL (
            SELECT
                candidate_post.id,
                candidate_post.shared_at,
                candidate_post.location_sharing,
                candidate_post.moderated_at,
                candidate_post.media_health_status
            FROM public.explore_posts AS candidate_post
            WHERE candidate_post.scan_id = scan.id
              AND candidate_post.user_id = self_id
              AND candidate_post.unshared_at IS NULL
            ORDER BY
                candidate_post.shared_at DESC NULLS LAST,
                candidate_post.id DESC
            LIMIT 1
        ) AS post
            ON TRUE
        LEFT JOIN LATERAL (
            SELECT
                candidate_request.id,
                candidate_request.status,
                candidate_request.explore_published_at
            FROM public.explore_community_requests AS candidate_request
            WHERE candidate_request.post_id = post.id
              AND candidate_request.requested_by = self_id
              AND candidate_request.status <> 'withdrawn'
            ORDER BY
                candidate_request.requested_at DESC,
                candidate_request.id DESC
            LIMIT 1
        ) AS community_request
            ON TRUE
        WHERE scan.id = target_scan_id
          AND scan.user_id = self_id
        LIMIT 1
    )
    SELECT
        state.scan_id,
        CASE
            WHEN state.has_live_post THEN state.post_id
            ELSE NULL
        END AS post_id,
        CASE
            WHEN state.has_live_post THEN state.shared_at
            ELSE NULL
        END AS shared_at,
        CASE
            WHEN state.has_live_post THEN state.community_request_id
            ELSE NULL
        END AS community_request_id,
        CASE
            WHEN state.has_live_post
                THEN state.community_request_status::TEXT
            ELSE NULL
        END AS community_request_status,
        (
            state.has_live_post
            AND state.is_projection_eligible
            AND (
                state.community_request_id IS NULL
                OR state.community_request_status = 'withdrawn'
                OR (
                    state.community_request_status = 'resolved'
                    AND state.explore_published_at IS NOT NULL
                )
            )
        ) AS is_explore_feed_visible,
        CASE
            WHEN state.has_live_post THEN state.post_location_sharing
            ELSE state.scan_geoprivacy
        END AS location_sharing
    FROM state;
$function$;

REVOKE ALL ON FUNCTION public.get_scan_explore_share_state(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_scan_explore_share_state(UUID, UUID)
    TO service_role;

COMMENT ON FUNCTION public.get_scan_explore_share_state(UUID, UUID) IS
    'Service-only invoker returning exact Edge-supplied JWT-owner publication intent plus authoritative public Explore visibility, including media-health and moderation state.';

RESET statement_timeout;
RESET lock_timeout;

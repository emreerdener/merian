DROP FUNCTION IF EXISTS public.get_scan_explore_share_state(UUID, UUID);

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
AS $$
    WITH state AS (
        SELECT
            s.id AS scan_id,
            ep.id AS post_id,
            ep.shared_at,
            ep.location_sharing AS post_location_sharing,
            ecr.id AS community_request_id,
            ecr.status AS community_request_status,
            ecr.explore_published_at,
            s.geoprivacy::TEXT AS scan_geoprivacy,
            (
                ep.id IS NOT NULL
                AND s.is_tombstoned = FALSE
                AND EXISTS (
                    SELECT 1
                    FROM public.explore_post_media epm
                    WHERE epm.post_id = ep.id
                )
                AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
                AND u.is_shadowbanned = FALSE
            ) AS has_live_post
        FROM public.scans s
        JOIN public.users u
            ON u.id = s.user_id
        LEFT JOIN LATERAL (
            SELECT
                id,
                shared_at,
                location_sharing
            FROM public.explore_posts
            WHERE scan_id = s.id
              AND user_id = self_id
              AND unshared_at IS NULL
            ORDER BY shared_at DESC NULLS LAST, id DESC
            LIMIT 1
        ) ep
            ON TRUE
        LEFT JOIN LATERAL (
            SELECT
                id,
                status,
                explore_published_at
            FROM public.explore_community_requests
            WHERE post_id = ep.id
              AND requested_by = self_id
              AND status <> 'withdrawn'
            ORDER BY requested_at DESC, id DESC
            LIMIT 1
        ) ecr
            ON TRUE
        WHERE s.id = target_scan_id
          AND s.user_id = self_id
        LIMIT 1
    )
    SELECT
        scan_id,
        CASE WHEN has_live_post THEN post_id ELSE NULL END AS post_id,
        CASE WHEN has_live_post THEN shared_at ELSE NULL END AS shared_at,
        CASE WHEN has_live_post THEN community_request_id ELSE NULL END AS community_request_id,
        CASE WHEN has_live_post THEN community_request_status::TEXT ELSE NULL END AS community_request_status,
        (
            has_live_post
            AND (
                community_request_id IS NULL
                OR community_request_status = 'withdrawn'
                OR (
                    community_request_status = 'resolved'
                    AND explore_published_at IS NOT NULL
                )
            )
        ) AS is_explore_feed_visible,
        CASE WHEN has_live_post THEN post_location_sharing ELSE scan_geoprivacy END AS location_sharing
    FROM state;
$$;

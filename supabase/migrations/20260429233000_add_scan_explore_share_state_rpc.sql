DROP FUNCTION IF EXISTS public.get_scan_explore_share_state(UUID, UUID);

CREATE OR REPLACE FUNCTION public.get_scan_explore_share_state(
    self_id UUID,
    target_scan_id UUID
)
RETURNS TABLE(
    scan_id UUID,
    post_id UUID,
    shared_at TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        s.id AS scan_id,
        CASE
            WHEN ep.id IS NOT NULL
             AND s.is_tombstoned = FALSE
             AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
             AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
             AND s.geoprivacy <> 'private'
             AND u.is_shadowbanned = FALSE
                THEN ep.id
            ELSE NULL
        END AS post_id,
        CASE
            WHEN ep.id IS NOT NULL
             AND s.is_tombstoned = FALSE
             AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
             AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
             AND s.geoprivacy <> 'private'
             AND u.is_shadowbanned = FALSE
                THEN ep.shared_at
            ELSE NULL
        END AS shared_at
    FROM public.scans s
    JOIN public.users u
        ON u.id = s.user_id
    LEFT JOIN LATERAL (
        SELECT
            id,
            shared_at
        FROM public.explore_posts
        WHERE scan_id = s.id
          AND user_id = self_id
          AND unshared_at IS NULL
        ORDER BY shared_at DESC NULLS LAST, id DESC
        LIMIT 1
    ) ep
        ON TRUE
    WHERE s.id = target_scan_id
      AND s.user_id = self_id
    LIMIT 1;
$$;

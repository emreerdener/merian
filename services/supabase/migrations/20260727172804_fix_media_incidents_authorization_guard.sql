-- Align the service_role branch of `get_owned_explore_media_incidents` with the
-- robust opaque-key impersonation logic from `internal.require_service_role()`.
-- This prevents the function from incorrectly falling through to the `ELSIF`
-- user ID check when called by an edge function using an opaque service_role key.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_owned_explore_media_incidents(
    self_id UUID
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    species_common_name TEXT,
    media_health_status TEXT,
    missing_media_count INTEGER,
    total_media_count INTEGER,
    media_quarantined_at TIMESTAMPTZ,
    media_health_updated_at TIMESTAMPTZ,
    missing_media_urls TEXT[]
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    IF auth.role() IS NOT DISTINCT FROM 'service_role'
       OR pg_catalog.CURRENT_SETTING('role', TRUE) IN ('service_role', 'postgres')
       OR (pg_catalog.CURRENT_SETTING('role', TRUE) = 'none' AND SESSION_USER IN ('postgres', 'service_role')) THEN
        PERFORM internal.require_service_role();
    ELSIF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM self_id THEN
        RAISE EXCEPTION 'Authenticated caller does not match self_id.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        post.id,
        post.scan_id,
        post.species_common_name,
        post.media_health_status,
        post.missing_media_count,
        post.total_media_count,
        post.media_quarantined_at,
        post.media_health_updated_at,
        COALESCE(
            ARRAY_AGG(media.url ORDER BY media.order_index, media.id)
                FILTER (WHERE media.health_status = 'missing'),
            ARRAY[]::TEXT[]
        )
    FROM public.explore_posts AS post
    INNER JOIN public.scans AS scan
        ON scan.id = post.scan_id
    LEFT JOIN public.explore_post_media AS media
        ON media.post_id = post.id
    WHERE post.user_id = self_id
      AND post.unshared_at IS NULL
      AND post.moderated_at IS NULL
      AND NOT scan.is_tombstoned
      AND post.media_health_status <> 'healthy'
    GROUP BY
        post.id,
        post.scan_id,
        post.species_common_name,
        post.media_health_status,
        post.missing_media_count,
        post.total_media_count,
        post.media_quarantined_at,
        post.media_health_updated_at
    ORDER BY post.media_health_updated_at DESC, post.id DESC;
END;
$$;

COMMIT;

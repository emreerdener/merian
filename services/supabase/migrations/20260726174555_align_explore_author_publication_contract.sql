-- Keep Explore author counts, previews, and paginated grids on the same
-- canonical visibility projection. Preserve the owner's publication intent as
-- a separate, owner-only summary instead of presenting hidden/quarantined rows
-- as publicly visible posts.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    count_statement_pattern TEXT :=
        E'[[:blank:]]*SELECT[[:space:]]+[^;]*'
        || E'INTO[[:space:]]+visible_post_count[[:space:]]+[^;]*;'
        || E'[[:space:]]*';
    canonical_count_fragment TEXT :=
        E'    SELECT pg_catalog.COUNT(*)::INTEGER\n'
        || E'    INTO visible_post_count\n'
        || E'    FROM public.explore_projected_post_cards(self_id) AS visible_post\n'
        || E'    WHERE visible_post.author_user_id = target_author_user_id;\n\n';
    eligibility_pattern TEXT :=
        E'IF[[:space:]]+visible_post_count[[:space:]]*=[[:space:]]*0'
        || E'[^;]*THEN[[:space:]]+RETURN;'
        || E'[[:space:]]+END[[:space:]]+IF;';
    owner_aware_eligibility_fragment TEXT :=
        E'    IF visible_post_count = 0\n'
        || E'       AND self_id IS DISTINCT FROM target_author_user_id\n'
        || E'       AND NOT public.user_has_visible_field_trip_profile(self_id, target_author_user_id) THEN\n'
        || E'        RETURN;\n'
        || E'    END IF;';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.get_explore_author_profile(uuid,uuid,integer)'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    -- Historical migrations have evolved this function, and
    -- pg_get_functiondef() text is not a stable byte-level contract across
    -- schema histories or PostgreSQL versions. Match the single PL/pgSQL
    -- statement by its semantic INTO target and semicolon boundary instead.
    patched_sql := pg_catalog.REGEXP_REPLACE(
        function_sql,
        count_statement_pattern,
        canonical_count_fragment,
        'i'
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'get_explore_author_profile has no visible_post_count SELECT statement';
    END IF;
    function_sql := patched_sql;

    patched_sql := pg_catalog.REGEXP_REPLACE(
        function_sql,
        eligibility_pattern,
        owner_aware_eligibility_fragment,
        'i'
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'get_explore_author_profile has no visible_post_count eligibility guard';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.get_owned_explore_publication_summary(
    self_id UUID
)
RETURNS TABLE(
    publication_intent_count INTEGER,
    visible_post_count INTEGER,
    recovery_needed_post_count INTEGER,
    degraded_post_count INTEGER,
    quarantined_post_count INTEGER
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    IF self_id IS NULL THEN
        RAISE EXCEPTION 'An owner id is required.'
            USING ERRCODE = '22023';
    END IF;

    IF auth.uid() IS NULL THEN
        PERFORM internal.require_service_role();
    ELSIF auth.uid() IS DISTINCT FROM self_id THEN
        RAISE EXCEPTION 'Authenticated caller does not match self_id.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH publication_intent AS (
        SELECT
            post.id,
            post.moderated_at,
            post.media_health_status
        FROM public.explore_posts AS post
        INNER JOIN public.scans AS scan
            ON scan.id = post.scan_id
        WHERE post.user_id = self_id
          AND post.unshared_at IS NULL
          AND NOT scan.is_tombstoned
    ),
    visible_posts AS (
        SELECT visible_post.post_id
        FROM public.explore_projected_post_cards(self_id) AS visible_post
        WHERE visible_post.author_user_id = self_id
    )
    SELECT
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM publication_intent
        ),
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM visible_posts
        ),
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM publication_intent
            WHERE moderated_at IS NULL
              AND media_health_status <> 'healthy'
        ),
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM publication_intent
            WHERE moderated_at IS NULL
              AND media_health_status = 'degraded'
        ),
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM publication_intent
            WHERE moderated_at IS NULL
              AND media_health_status = 'quarantined'
        );
END;
$$;

COMMENT ON FUNCTION public.get_owned_explore_publication_summary(UUID) IS
    'Owner-only publication intent, canonical visibility, and active media-recovery totals for the authenticated Explore author.';

REVOKE ALL ON FUNCTION public.get_owned_explore_publication_summary(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_explore_publication_summary(UUID)
    TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_explore_publication_health_summary()
RETURNS TABLE(
    active_publication_count INTEGER,
    healthy_post_count INTEGER,
    degraded_post_count INTEGER,
    quarantined_post_count INTEGER,
    affected_author_count INTEGER,
    missing_media_item_count INTEGER
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH active_posts AS (
        SELECT
            post.id,
            post.user_id,
            post.media_health_status
        FROM public.explore_posts AS post
        INNER JOIN public.scans AS scan
            ON scan.id = post.scan_id
        WHERE post.unshared_at IS NULL
          AND post.moderated_at IS NULL
          AND NOT scan.is_tombstoned
    ),
    post_totals AS (
        SELECT
            pg_catalog.COUNT(*)::INTEGER AS active_publication_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE media_health_status = 'healthy'
            )::INTEGER AS healthy_post_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE media_health_status = 'degraded'
            )::INTEGER AS degraded_post_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE media_health_status = 'quarantined'
            )::INTEGER AS quarantined_post_count,
            pg_catalog.COUNT(DISTINCT user_id) FILTER (
                WHERE media_health_status <> 'healthy'
            )::INTEGER AS affected_author_count
        FROM active_posts
    ),
    media_totals AS (
        SELECT pg_catalog.COUNT(*)::INTEGER AS missing_media_item_count
        FROM public.explore_post_media AS media
        INNER JOIN active_posts AS post
            ON post.id = media.post_id
        WHERE media.health_status = 'missing'
    )
    SELECT
        post_totals.active_publication_count,
        post_totals.healthy_post_count,
        post_totals.degraded_post_count,
        post_totals.quarantined_post_count,
        post_totals.affected_author_count,
        media_totals.missing_media_item_count
    FROM post_totals
    CROSS JOIN media_totals;
END;
$$;

COMMENT ON FUNCTION public.get_explore_publication_health_summary() IS
    'Service-only aggregate Explore media-health scope without owner identifiers or object keys.';

REVOKE ALL ON FUNCTION public.get_explore_publication_health_summary()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_explore_publication_health_summary()
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'authenticated',
        'public.get_owned_explore_publication_summary(uuid)',
        'Returns only the authenticated owner publication and media-recovery totals.'
    ),
    (
        'service_role',
        'public.get_owned_explore_publication_summary(uuid)',
        'Supports the authenticated Explore author profile Edge boundary using its auth-derived owner id.'
    ),
    (
        'service_role',
        'public.get_explore_publication_health_summary()',
        'Reports aggregate active Explore media-health scope without owner identifiers or object keys.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;

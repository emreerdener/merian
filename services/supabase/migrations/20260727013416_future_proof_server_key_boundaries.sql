-- Current `sb_secret_...` server API keys are opaque credentials. They belong
-- in `apikey`, while legacy service-role JWTs must remain in both `apikey` and
-- `Authorization` during the migration window.
BEGIN;

CREATE OR REPLACE FUNCTION internal.server_api_request_headers(
    server_api_key TEXT
)
RETURNS JSONB
LANGUAGE PLPGSQL
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    header_segment TEXT;
    payload_segment TEXT;
    header_json JSONB;
    payload_json JSONB;
BEGIN
    IF server_api_key ~ '^sb_secret_[A-Za-z0-9_-]{20,}$' THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'Content-Type', 'application/json',
            'apikey', server_api_key
        );
    END IF;

    IF server_api_key ~
       '^[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]{43}$' THEN
        header_segment := pg_catalog.SPLIT_PART(server_api_key, '.', 1);
        payload_segment := pg_catalog.SPLIT_PART(server_api_key, '.', 2);

        BEGIN
            header_json := pg_catalog.CONVERT_FROM(
                pg_catalog.DECODE(
                    pg_catalog.TRANSLATE(header_segment, '-_', '+/')
                    || pg_catalog.REPEAT(
                        '=',
                        (4 - pg_catalog.LENGTH(header_segment) % 4) % 4
                    ),
                    'base64'
                ),
                'UTF8'
            )::JSONB;
            payload_json := pg_catalog.CONVERT_FROM(
                pg_catalog.DECODE(
                    pg_catalog.TRANSLATE(payload_segment, '-_', '+/')
                    || pg_catalog.REPEAT(
                        '=',
                        (4 - pg_catalog.LENGTH(payload_segment) % 4) % 4
                    ),
                    'base64'
                ),
                'UTF8'
            )::JSONB;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION 'invalid server API key configuration'
                    USING ERRCODE = '22023';
        END;

        IF header_json ->> 'alg' = 'HS256'
           AND payload_json ->> 'role' = 'service_role' THEN
            RETURN pg_catalog.JSONB_BUILD_OBJECT(
                'Content-Type', 'application/json',
                'apikey', server_api_key,
                'Authorization', 'Bearer ' || server_api_key
            );
        END IF;
    END IF;

    RAISE EXCEPTION 'invalid server API key configuration'
        USING ERRCODE = '22023';
END;
$$;

COMMENT ON FUNCTION internal.server_api_request_headers(TEXT) IS
    'Private fail-closed pg_net transport policy that rejects missing or malformed configuration and supports opaque server API keys plus platform-issued legacy HS256 service-role JWTs.';

REVOKE ALL ON FUNCTION internal.server_api_request_headers(TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

-- Replace the mixed user/service dispatch with an identity-first branch.
-- A missing auth.uid() is a server call and must pass the shared guard, which
-- supports both legacy JWT claims and PostgREST's opaque-key database role.
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
    IF auth.uid() IS NULL THEN
        PERFORM internal.require_service_role();
    ELSIF auth.uid() IS DISTINCT FROM self_id THEN
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

REVOKE ALL ON FUNCTION public.get_owned_explore_media_incidents(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_explore_media_incidents(UUID)
    TO authenticated, service_role;

-- Replace every currently installed pg_net routine rather than duplicating
-- notification/export business logic here. The replacement is deliberately
-- strict: migration fails if any current routine still uses Bearer-only
-- service-key transport.
DO $migration$
DECLARE
    routine_row RECORD;
    routine_definition TEXT;
    patched_definition TEXT;
    unsafe_headers_pattern TEXT :=
        '(pg_catalog[.])?jsonb_build_object[[:space:]]*'
        || '[(][[:space:]]*''Content-Type''[[:space:]]*,[[:space:]]*'
        || '''application/json''[[:space:]]*,[[:space:]]*'
        || '''Authorization''[[:space:]]*,[[:space:]]*'
        || '''Bearer ''[[:space:]]*[|][|][[:space:]]*'
        || 'service_role_key[[:space:]]*[)]';
BEGIN
    FOR routine_row IN
        SELECT function_row.oid
        FROM pg_catalog.pg_proc AS function_row
        INNER JOIN pg_catalog.pg_namespace AS namespace_row
            ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname IN ('public', 'internal')
          AND function_row.prosrc ~* 'net[.]http_post'
          AND function_row.prosrc ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    LOOP
        routine_definition :=
            pg_catalog.PG_GET_FUNCTIONDEF(routine_row.oid);
        patched_definition := pg_catalog.REGEXP_REPLACE(
            routine_definition,
            unsafe_headers_pattern,
            'internal.server_api_request_headers(service_role_key)',
            'gi'
        );

        IF patched_definition = routine_definition THEN
            RAISE EXCEPTION
                'Could not migrate pg_net headers for routine oid %',
                routine_row.oid;
        END IF;
        EXECUTE patched_definition;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        INNER JOIN pg_catalog.pg_namespace AS namespace_row
            ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname IN ('public', 'internal')
          AND function_row.prosrc ~* 'net[.]http_post'
          AND function_row.prosrc ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    ) THEN
        RAISE EXCEPTION
            'A pg_net routine still uses Bearer-only server-key transport.';
    END IF;
END;
$migration$;

-- pg_cron persists command text, so historical migration files do not alter
-- deployed jobs. Patch every persisted HTTP command transactionally and verify
-- the active catalog before commit.
DO $migration$
DECLARE
    job_row RECORD;
    patched_command TEXT;
    unsafe_headers_pattern TEXT :=
        '(pg_catalog[.])?jsonb_build_object[[:space:]]*'
        || '[(][[:space:]]*''Content-Type''[[:space:]]*,[[:space:]]*'
        || '''application/json''[[:space:]]*,[[:space:]]*'
        || '''Authorization''[[:space:]]*,[[:space:]]*'
        || '''Bearer ''[[:space:]]*[|][|][[:space:]]*'
        || 'service_role_key[[:space:]]*[)]';
BEGIN
    FOR job_row IN
        SELECT jobid, command
        FROM cron.job
        WHERE command ~* 'net[.]http_post'
          AND command ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    LOOP
        patched_command := pg_catalog.REGEXP_REPLACE(
            job_row.command,
            unsafe_headers_pattern,
            'internal.server_api_request_headers(service_role_key)',
            'gi'
        );

        IF patched_command = job_row.command THEN
            RAISE EXCEPTION
                'Could not migrate pg_net headers for cron job %',
                job_row.jobid;
        END IF;

        PERFORM cron.alter_job(
            job_row.jobid,
            command := patched_command
        );
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE active
          AND command ~* 'net[.]http_post'
          AND command ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    ) THEN
        RAISE EXCEPTION
            'An active cron job still uses Bearer-only server-key transport.';
    END IF;
END;
$migration$;

NOTIFY pgrst, 'reload schema';

COMMIT;

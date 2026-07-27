\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
SELECT extensions.plan(1);

-- A function created after the hardening migration must inherit owner-only
-- EXECUTE. This exercises PostgreSQL's combined global and per-schema defaults.
CREATE FUNCTION public.privileged_routine_default_acl_probe()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT 1;
$$;

DO $$
DECLARE
    target_signature TEXT;
    static_issue RECORD;
    trigger_issue RECORD;
    invalid_server_key TEXT;
    invalid_server_key_rejected BOOLEAN := FALSE;
    current_server_key TEXT :=
        'sb_' || 'secret_catalog_probe_' || pg_catalog.REPEAT('a', 20);
    legacy_server_key TEXT :=
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        || '.'
        || 'eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ'
        || '.'
        || pg_catalog.REPEAT('a', 43);
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND EXISTS (
              SELECT 1
              FROM pg_catalog.ACLEXPLODE(
                  COALESCE(
                      function_row.proacl,
                      pg_catalog.ACLDEFAULT(
                          'f',
                          function_row.proowner
                      )
                  )
              ) AS acl_row
              WHERE acl_row.grantee = 0
                AND acl_row.privilege_type = 'EXECUTE'
          )
    ) THEN
        RAISE EXCEPTION
            'PUBLIC can execute a public SECURITY DEFINER function';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        CROSS JOIN (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
              api_role.role_name,
              function_row.oid,
              'EXECUTE'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.privileged_routine_grants AS allowlist
              WHERE allowlist.role_name = api_role.role_name
                AND pg_catalog.TO_REGPROCEDURE(
                    allowlist.routine_signature
                ) = function_row.oid
          )
    ) THEN
        RAISE EXCEPTION
            'an API role can execute a definer function outside the allowlist';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        LEFT JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        LEFT JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE function_row.oid IS NULL
           OR namespace_row.nspname <> 'public'
           OR NOT function_row.prosecdef
           OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
               allowlist.role_name,
               function_row.oid,
               'EXECUTE'
           )
    ) THEN
        RAISE EXCEPTION
            'the reviewed definer-function allowlist is stale or incomplete';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        WHERE allowlist.role_name = 'authenticated'
          AND function_row.prosrc !~ 'internal[.]require_admin[(]'
          AND function_row.prosrc !~ 'auth[.](uid|jwt)[(]'
    ) THEN
        RAISE EXCEPTION
            'an authenticated definer function lacks caller authorization';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS allowlist
        JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = pg_catalog.TO_REGPROCEDURE(
              allowlist.routine_signature
          )
        WHERE allowlist.role_name = 'service_role'
          AND function_row.prosrc NOT LIKE
              '%internal.require_service_role()%'
    ) THEN
        RAISE EXCEPTION
            'a service-role definer function lacks caller authorization';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        INNER JOIN pg_catalog.pg_namespace AS namespace_row
            ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND function_row.prosrc ~*
              'auth[.]role[(][)][[:space:]]*=[[:space:]]*''service_role'''
    ) THEN
        RAISE EXCEPTION
            'a public definer routine dispatches on a JWT-only service-role claim';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
          AND NOT (
              COALESCE(
                  function_row.proconfig,
                  ARRAY[]::TEXT[]
              ) @> ARRAY['search_path=""']::TEXT[]
          )
    ) THEN
        RAISE EXCEPTION
            'a public SECURITY DEFINER function has a non-empty search_path';
    END IF;

    SELECT
        pg_catalog.FORMAT(
            '%I.%I(%s)',
            namespace_row.nspname,
            function_row.proname,
            pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(function_row.oid)
        ) AS signature,
        issue.level,
        issue.sqlstate,
        issue.message,
        issue.detail,
        issue.hint,
        issue.lineno,
        issue.statement,
        issue.query
    INTO static_issue
    FROM pg_catalog.pg_proc AS function_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = function_row.pronamespace
    JOIN pg_catalog.pg_language AS language_row
      ON language_row.oid = function_row.prolang
    CROSS JOIN LATERAL extensions.plpgsql_check_function_tb(
        function_row.oid
    ) AS issue
    WHERE namespace_row.nspname = 'public'
      AND function_row.prosecdef
      AND language_row.lanname = 'plpgsql'
      AND function_row.prorettype <> 'pg_catalog.trigger'::REGTYPE
      AND issue.level IN ('error', 'fatal')
    ORDER BY signature, issue.lineno
    LIMIT 1;

    IF static_issue.signature IS NOT NULL THEN
        RAISE EXCEPTION
            'public definer function % fails plpgsql static validation at line % [%]: %',
            static_issue.signature,
            static_issue.lineno,
            static_issue.sqlstate,
            static_issue.message
            USING DETAIL = pg_catalog.FORMAT(
                'statement=%s; query=%s; detail=%s',
                COALESCE(static_issue.statement, '<unknown>'),
                COALESCE(static_issue.query, '<unknown>'),
                COALESCE(static_issue.detail, '<none>')
            ),
            HINT = COALESCE(
                static_issue.hint,
                'Run extensions.plpgsql_check_function_tb for this signature.'
            );
    END IF;

    SELECT
        pg_catalog.FORMAT(
            '%I.%I(%s)',
            namespace_row.nspname,
            function_row.proname,
            pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(function_row.oid)
        ) AS signature,
        trigger_row.tgrelid::REGCLASS::TEXT AS relation_name,
        issue.level,
        issue.sqlstate,
        issue.message,
        issue.detail,
        issue.hint,
        issue.lineno,
        issue.statement,
        issue.query
    INTO trigger_issue
    FROM pg_catalog.pg_trigger AS trigger_row
    JOIN pg_catalog.pg_proc AS function_row
      ON function_row.oid = trigger_row.tgfoid
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = function_row.pronamespace
    JOIN pg_catalog.pg_language AS language_row
      ON language_row.oid = function_row.prolang
    CROSS JOIN LATERAL extensions.plpgsql_check_function_tb(
        function_row.oid::REGPROCEDURE,
        trigger_row.tgrelid
    ) AS issue
    WHERE namespace_row.nspname = 'public'
      AND function_row.prosecdef
      AND language_row.lanname = 'plpgsql'
      AND NOT trigger_row.tgisinternal
      AND issue.level IN ('error', 'fatal')
    ORDER BY signature, relation_name, issue.lineno
    LIMIT 1;

    IF trigger_issue.signature IS NOT NULL THEN
        RAISE EXCEPTION
            'public definer trigger % on % fails plpgsql static validation at line % [%]: %',
            trigger_issue.signature,
            trigger_issue.relation_name,
            trigger_issue.lineno,
            trigger_issue.sqlstate,
            trigger_issue.message
            USING DETAIL = pg_catalog.FORMAT(
                'statement=%s; query=%s; detail=%s',
                COALESCE(trigger_issue.statement, '<unknown>'),
                COALESCE(trigger_issue.query, '<unknown>'),
                COALESCE(trigger_issue.detail, '<none>')
            ),
            HINT = COALESCE(
                trigger_issue.hint,
                'Run extensions.plpgsql_check_function_tb for this trigger.'
            );
    END IF;

    IF EXISTS (
        WITH creator_role AS (
            SELECT role_row.oid
            FROM pg_catalog.pg_roles AS role_row
            WHERE role_row.rolname = 'postgres'
        ),
        candidate_defaults AS (
            SELECT
                COALESCE(
                    default_acl.defaclacl,
                    pg_catalog.ACLDEFAULT('f', creator.oid)
                ) AS privilege_acl
            FROM creator_role AS creator
            LEFT JOIN pg_catalog.pg_default_acl AS default_acl
              ON default_acl.defaclrole = creator.oid
             AND default_acl.defaclnamespace = 0
             AND default_acl.defaclobjtype = 'f'

            UNION ALL

            SELECT default_acl.defaclacl AS privilege_acl
            FROM creator_role AS creator
            JOIN pg_catalog.pg_default_acl AS default_acl
              ON default_acl.defaclrole = creator.oid
             AND default_acl.defaclnamespace = (
                 SELECT namespace_row.oid
                 FROM pg_catalog.pg_namespace AS namespace_row
                 WHERE namespace_row.nspname = 'public'
             )
             AND default_acl.defaclobjtype = 'f'
        )
        SELECT 1
        FROM candidate_defaults AS candidate
        CROSS JOIN LATERAL pg_catalog.ACLEXPLODE(
            candidate.privilege_acl
        ) AS acl_row
        WHERE acl_row.privilege_type = 'EXECUTE'
          AND (
              acl_row.grantee = 0
              OR acl_row.grantee IN (
                  SELECT role_row.oid
                  FROM pg_catalog.pg_roles AS role_row
                  WHERE role_row.rolname IN (
                      'anon',
                      'authenticated',
                      'service_role'
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION
            'postgres still has an unsafe default function privilege';
    END IF;

    IF pg_catalog.HAS_SCHEMA_PRIVILEGE('anon', 'public', 'CREATE')
       OR pg_catalog.HAS_SCHEMA_PRIVILEGE(
           'authenticated',
           'public',
           'CREATE'
       )
       OR pg_catalog.HAS_SCHEMA_PRIVILEGE(
           'service_role',
           'public',
           'CREATE'
       ) THEN
        RAISE EXCEPTION 'an API role can create objects in public';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.privileged_routine_grants',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.privileged_routine_grants',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.privileged_routine_grants',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'an API role can read the private routine allowlist table';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated')
        ) AS api_role(role_name)
        CROSS JOIN (
            VALUES
                ('SELECT'),
                ('INSERT'),
                ('UPDATE'),
                ('DELETE'),
                ('TRUNCATE'),
                ('REFERENCES'),
                ('TRIGGER')
        ) AS table_privilege(privilege_name)
        WHERE pg_catalog.HAS_TABLE_PRIVILEGE(
            api_role.role_name,
            'public.taxonomy_import_runs',
            table_privilege.privilege_name
        )
    ) THEN
        RAISE EXCEPTION
            'a low-privilege API role can access taxonomy import history';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('SELECT'), ('INSERT'), ('UPDATE')
        ) AS required_privilege(privilege_name)
        WHERE NOT pg_catalog.HAS_TABLE_PRIVILEGE(
            'service_role',
            'public.taxonomy_import_runs',
            required_privilege.privilege_name
        )
    ) OR EXISTS (
        SELECT 1
        FROM (
            VALUES ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
        ) AS forbidden_privilege(privilege_name)
        WHERE pg_catalog.HAS_TABLE_PRIVILEGE(
            'service_role',
            'public.taxonomy_import_runs',
            forbidden_privilege.privilege_name
        )
    ) THEN
        RAISE EXCEPTION
            'taxonomy import history does not have its least-privilege service-role ACL';
    END IF;

    IF pg_catalog.TO_REGPROCEDURE(
        'internal.server_api_request_headers(text)'
    ) IS NULL THEN
        RAISE EXCEPTION
            'the shared pg_net server-key header policy is missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE pg_catalog.HAS_FUNCTION_PRIVILEGE(
            api_role.role_name,
            'internal.server_api_request_headers(text)',
            'EXECUTE'
        )
    ) THEN
        RAISE EXCEPTION
            'an API role can execute the private pg_net header helper';
    END IF;

    IF internal.server_api_request_headers(current_server_key)
       IS DISTINCT FROM pg_catalog.JSONB_BUILD_OBJECT(
           'Content-Type',
           'application/json',
           'apikey',
           current_server_key
       )
       OR internal.server_api_request_headers(legacy_server_key)
       IS DISTINCT FROM pg_catalog.JSONB_BUILD_OBJECT(
           'Content-Type',
           'application/json',
           'apikey',
           legacy_server_key,
           'Authorization',
           'Bearer ' || legacy_server_key
       )
    THEN
        RAISE EXCEPTION
            'the shared pg_net header helper violates current/legacy transport';
    END IF;

    FOREACH invalid_server_key IN ARRAY ARRAY[
        NULL::TEXT,
        'sb_publishable_catalog_probe',
        'sb_secret_placeholder',
        'sb_' || 'secret_' || pg_catalog.REPEAT('a', 20) || '!',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ.placeholder'
    ]
    LOOP
        invalid_server_key_rejected := FALSE;
        BEGIN
            PERFORM internal.server_api_request_headers(invalid_server_key);
        EXCEPTION
            WHEN SQLSTATE '22023' THEN
                invalid_server_key_rejected := TRUE;
        END;
        IF NOT invalid_server_key_rejected THEN
            RAISE EXCEPTION
                'the shared pg_net header helper accepts invalid key %',
                invalid_server_key;
        END IF;
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
            'an installed pg_net routine still uses Bearer-only server-key transport';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE command ~* 'net[.]http_post'
          AND command ~*
              '''Bearer ''[[:space:]]*[|][|][[:space:]]*service_role_key'
    ) THEN
        RAISE EXCEPTION
            'a persisted cron command still uses Bearer-only server-key transport';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.privileged_routine_default_acl_probe()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.privileged_routine_default_acl_probe()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.privileged_routine_default_acl_probe()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'new functions still inherit an API-role EXECUTE grant';
    END IF;

    FOREACH target_signature IN ARRAY ARRAY[
        'public.reparent_user_follows(uuid,uuid)',
        'public.refresh_all_explore_post_media()',
        'public.merge_common_name_en(uuid,text)'
    ]
    LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'service_role',
            target_signature,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'service_role unexpectedly retains EXECUTE on %',
                target_signature;
        END IF;
    END LOOP;
END;
$$;

SET LOCAL ROLE anon;

DO $$
BEGIN
    BEGIN
        PERFORM 1
        FROM public.taxonomy_import_runs
        LIMIT 1;
        RAISE EXCEPTION
            'anon unexpectedly selected taxonomy import history';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$$;

RESET ROLE;
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    BEGIN
        PERFORM 1
        FROM public.taxonomy_import_runs
        LIMIT 1;
        RAISE EXCEPTION
            'authenticated unexpectedly selected taxonomy import history';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        PERFORM public.merge_common_name_en_batch(
            '[{"id":"00000000-0000-4000-8000-000000000001","en_name":"Denied"}]'::JSONB
        );
        RAISE EXCEPTION
            'authenticated unexpectedly executed the common-name batch';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$$;

RESET ROLE;
SET LOCAL ROLE service_role;

DO $$
DECLARE
    oversized_batch JSONB;
BEGIN
    PERFORM 1
    FROM public.taxonomy_import_runs
    LIMIT 1;

    SELECT pg_catalog.JSONB_AGG(
        pg_catalog.JSONB_BUILD_OBJECT(
            'id',
            pg_catalog.FORMAT(
                '00000000-0000-4000-8000-%012s',
                series.value
            ),
            'en_name',
            'Bounded'
        )
    )
    INTO oversized_batch
    FROM pg_catalog.GENERATE_SERIES(1, 51) AS series(value);

    BEGIN
        PERFORM public.merge_common_name_en_batch(oversized_batch);
        RAISE EXCEPTION 'expected oversized common-name batch rejection';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN NULL;
    END;
END;
$$;

RESET ROLE;

-- User impersonation is carried by PostgreSQL's protected standard `role`
-- setting. Keep the test portable to pg_prove login roles that cannot change
-- session authorization while proving that an owner login cannot bypass the
-- guard after impersonating a lower-privilege role.
CREATE FUNCTION public.privileged_routine_role_guard_probe()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();
END;
$$;

GRANT EXECUTE ON FUNCTION public.privileged_routine_role_guard_probe()
    TO authenticated, service_role;

SET LOCAL ROLE authenticated;

DO $$
BEGIN
    BEGIN
        PERFORM public.privileged_routine_role_guard_probe();
        RAISE EXCEPTION
            'authenticated PostgREST role unexpectedly passed the service guard';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$$;

RESET ROLE;
SET LOCAL ROLE service_role;

DO $$
BEGIN
    PERFORM public.privileged_routine_role_guard_probe();
    PERFORM 1
    FROM public.get_owned_explore_media_incidents(
        '00000000-0000-0000-0000-000000000000'::UUID
    )
    LIMIT 1;
END;
$$;

RESET ROLE;

SELECT extensions.pass(
    'privileged routine ACL, search_path, role and key transport guards, allowlist, defaults, and batch bounds hold'
);
SELECT * FROM extensions.finish();
ROLLBACK;

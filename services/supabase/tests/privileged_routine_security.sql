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

    IF EXISTS (
        SELECT 1
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
    ) THEN
        RAISE EXCEPTION
            'a public definer function fails plpgsql static validation';
    END IF;

    IF EXISTS (
        SELECT 1
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
    ) THEN
        RAISE EXCEPTION
            'a public definer trigger fails plpgsql static validation';
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

SET LOCAL ROLE authenticated;

DO $$
BEGIN
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

SELECT extensions.pass(
    'privileged routine ACL, search_path, allowlist, defaults, and batch bounds hold'
);
SELECT * FROM extensions.finish();
ROLLBACK;

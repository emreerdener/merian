\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
SELECT
    '00000000-0000-0000-0000-000000000000',
    seed.user_id,
    'authenticated',
    'authenticated',
    seed.email,
    NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    NOW(),
    NOW(),
    FALSE
FROM (
    VALUES
        (
            '00000000-0000-4000-8000-00000000c101'::UUID,
            'collection-owner-a@naturebook.invalid'
        ),
        (
            '00000000-0000-4000-8000-00000000c102'::UUID,
            'collection-owner-b@naturebook.invalid'
        )
) AS seed(user_id, email);

INSERT INTO public.collections (id, user_id, name, created_at)
VALUES
    (
        '00000000-0000-4000-8000-00000000c201',
        '00000000-0000-4000-8000-00000000c101',
        'Owner A existing',
        NOW()
    ),
    (
        '00000000-0000-4000-8000-00000000c202',
        '00000000-0000-4000-8000-00000000c102',
        'Owner B foreign',
        NOW()
    );

INSERT INTO public.scans (id, user_id, ai_confidence_score)
VALUES
    (
        '00000000-0000-4000-8000-00000000c301',
        '00000000-0000-4000-8000-00000000c101',
        0.90
    ),
    (
        '00000000-0000-4000-8000-00000000c302',
        '00000000-0000-4000-8000-00000000c102',
        0.90
    );

DO $test$
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.upsert_owned_collections(uuid,jsonb)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.upsert_owned_collections(uuid,jsonb)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.upsert_owned_collections(uuid,jsonb)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.insert_owned_collection_scans(uuid,jsonb)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.insert_owned_collection_scans(uuid,jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'collection RPC ACLs are unsafe';
    END IF;

    IF pg_catalog.HAS_COLUMN_PRIVILEGE(
        'service_role',
        'public.collections',
        'user_id',
        'UPDATE'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'service_role',
        'public.collections',
        'name',
        'UPDATE'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'service_role',
        'public.collections',
        'created_at',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION 'collection column privileges are unsafe';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid IN (
            'public.upsert_owned_collections(uuid,jsonb)'::REGPROCEDURE,
            'public.insert_owned_collection_scans(uuid,jsonb)'::REGPROCEDURE,
            'public.enforce_collection_scan_owner_match()'::REGPROCEDURE
        )
          AND (
              routine.prosecdef
              OR NOT COALESCE(
                  routine.proconfig,
                  ARRAY[]::TEXT[]
              ) @> ARRAY['search_path=""']::TEXT[]
          )
    ) THEN
        RAISE EXCEPTION 'collection routines are not invoker-safe';
    END IF;

    IF NOT (
        SELECT routine.prosecdef
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid =
            'internal.reparent_ghost_user_foreign_keys(uuid,uuid)'::REGPROCEDURE
    ) THEN
        RAISE EXCEPTION 'ghost merge lost its privileged reparent boundary';
    END IF;
END;
$test$;

SET LOCAL ROLE service_role;

DO $test$
DECLARE
    upserted RECORD;
    accepted_count INTEGER := 0;
    rejected_count INTEGER := 0;
BEGIN
    FOR upserted IN
        SELECT *
        FROM public.upsert_owned_collections(
            '00000000-0000-4000-8000-00000000c101',
            '[
              {
                "id":"00000000-0000-4000-8000-00000000c203",
                "name":"Owner A new",
                "created_at":"2026-08-03T12:00:00Z"
              },
              {
                "id":"00000000-0000-4000-8000-00000000c202",
                "name":"Attempted reparent",
                "created_at":"2026-08-03T12:00:00Z"
              }
            ]'::JSONB
        )
    LOOP
        IF upserted.accepted THEN
            accepted_count := accepted_count + 1;
        ELSE
            rejected_count := rejected_count + 1;
        END IF;
    END LOOP;

    IF accepted_count <> 1 OR rejected_count <> 1 THEN
        RAISE EXCEPTION 'guarded collection upsert returned the wrong decisions';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.collections
        WHERE id = '00000000-0000-4000-8000-00000000c202'
          AND (
              user_id <> '00000000-0000-4000-8000-00000000c102'
              OR name <> 'Owner B foreign'
          )
    ) THEN
        RAISE EXCEPTION 'foreign collection was modified';
    END IF;

    PERFORM *
    FROM public.insert_owned_collection_scans(
        '00000000-0000-4000-8000-00000000c101',
        '[
          {
            "collection_id":"00000000-0000-4000-8000-00000000c201",
            "scan_id":"00000000-0000-4000-8000-00000000c301"
          },
          {
            "collection_id":"00000000-0000-4000-8000-00000000c201",
            "scan_id":"00000000-0000-4000-8000-00000000c302"
          }
        ]'::JSONB
    );

    IF (SELECT COUNT(*) FROM public.collection_scans) <> 1 THEN
        RAISE EXCEPTION 'owner-scoped membership RPC admitted a foreign scan';
    END IF;

    BEGIN
        UPDATE public.collections
        SET user_id = '00000000-0000-4000-8000-00000000c102'
        WHERE id = '00000000-0000-4000-8000-00000000c201';
        RAISE EXCEPTION 'service_role directly updated a collection owner';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        INSERT INTO public.collection_scans (collection_id, scan_id)
        VALUES (
            '00000000-0000-4000-8000-00000000c203',
            '00000000-0000-4000-8000-00000000c302'
        );
        RAISE EXCEPTION 'trigger admitted a cross-owner membership';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;

END;
$test$;

RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000c101","role":"authenticated"}',
    TRUE
);

DO $test$
BEGIN
    BEGIN
        INSERT INTO public.collection_scans (collection_id, scan_id)
        VALUES (
            '00000000-0000-4000-8000-00000000c201',
            '00000000-0000-4000-8000-00000000c302'
        );
        RAISE EXCEPTION 'authenticated RLS admitted a foreign scan';
    EXCEPTION
        WHEN SQLSTATE '23514' OR SQLSTATE '42501' THEN NULL;
    END;
END;
$test$;

RESET ROLE;

SELECT extensions.pass(
    'collection ownership, membership parents, RPC ACLs, and ghost merge privilege boundaries hold'
);
SELECT * FROM extensions.finish();
ROLLBACK;

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
            '00000000-0000-4000-8000-00000000d101'::UUID,
            'species-preference-owner-a@naturebook.invalid'
        ),
        (
            '00000000-0000-4000-8000-00000000d102'::UUID,
            'species-preference-owner-b@naturebook.invalid'
        )
) AS seed(user_id, email);

INSERT INTO public.user_species_preferences (
    user_id,
    scientific_name,
    preferred_common_name
)
VALUES
    (
        '00000000-0000-4000-8000-00000000d101',
        'Danaus plexippus',
        'Monarch'
    ),
    (
        '00000000-0000-4000-8000-00000000d102',
        'Bombus vosnesenskii',
        'Yellow-faced Bumble Bee'
    );

DO $catalog$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS relation
        JOIN pg_catalog.pg_namespace AS namespace
          ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND relation.relname = 'user_species_preferences'
          AND relation.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'user_species_preferences lost RLS';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_species_preferences'
          AND policyname = 'user_species_preferences_manage_own'
          AND cmd = 'ALL'
          AND roles = ARRAY['authenticated']::NAME[]
    ) <> 1 THEN
        RAISE EXCEPTION 'species preference owner policy is missing or too broad';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.user_species_preferences',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_species_preferences',
        'TRUNCATE'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_species_preferences',
        'SELECT, INSERT, UPDATE, DELETE'
    ) THEN
        RAISE EXCEPTION 'species preference table privileges are unsafe';
    END IF;
END;
$catalog$;

SET LOCAL ROLE authenticated;
SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000d101","role":"authenticated"}',
    TRUE
);

DO $owner_a$
DECLARE
    affected_rows INTEGER;
BEGIN
    IF (
        SELECT COUNT(*)
        FROM public.user_species_preferences
    ) <> 1 THEN
        RAISE EXCEPTION 'owner A can read another account preference';
    END IF;

    INSERT INTO public.user_species_preferences (
        user_id,
        scientific_name,
        preferred_common_name
    )
    VALUES (
        '00000000-0000-4000-8000-00000000d101',
        'Quercus macrocarpa',
        'Bur Oak'
    );

    UPDATE public.user_species_preferences
    SET preferred_common_name = 'Mossycup Oak'
    WHERE user_id = '00000000-0000-4000-8000-00000000d101'
      AND scientific_name = 'Quercus macrocarpa';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'owner A could not update an owned preference';
    END IF;

    UPDATE public.user_species_preferences
    SET preferred_common_name = 'Foreign mutation'
    WHERE user_id = '00000000-0000-4000-8000-00000000d102';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 0 THEN
        RAISE EXCEPTION 'owner A updated another account preference';
    END IF;

    DELETE FROM public.user_species_preferences
    WHERE user_id = '00000000-0000-4000-8000-00000000d102';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 0 THEN
        RAISE EXCEPTION 'owner A deleted another account preference';
    END IF;

    BEGIN
        INSERT INTO public.user_species_preferences (
            user_id,
            scientific_name,
            preferred_common_name
        )
        VALUES (
            '00000000-0000-4000-8000-00000000d102',
            'Quercus alba',
            'White Oak'
        );
        RAISE EXCEPTION 'owner A inserted another account preference';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        INSERT INTO public.user_species_preferences (
            user_id,
            scientific_name,
            preferred_common_name
        )
        VALUES (
            '00000000-0000-4000-8000-00000000d101',
            'Name length fixture',
            REPEAT('x', 201)
        );
        RAISE EXCEPTION 'preferred-name length constraint accepted 201 characters';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN NULL;
    END;

    DELETE FROM public.user_species_preferences
    WHERE user_id = '00000000-0000-4000-8000-00000000d101'
      AND scientific_name = 'Quercus macrocarpa';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'owner A could not delete an owned preference';
    END IF;
END;
$owner_a$;

SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000d102","role":"authenticated"}',
    TRUE
);

DO $owner_b$
BEGIN
    IF (
        SELECT COUNT(*)
        FROM public.user_species_preferences
    ) <> 1 THEN
        RAISE EXCEPTION 'owner B can read another account preference';
    END IF;
END;
$owner_b$;

RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_catalog.SET_CONFIG('request.jwt.claims', '{}', TRUE);

DO $anonymous$
BEGIN
    BEGIN
        PERFORM 1 FROM public.user_species_preferences LIMIT 1;
        RAISE EXCEPTION 'anonymous caller read account species preferences';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$anonymous$;

RESET ROLE;

SELECT extensions.pass(
    'species preferred names remain account-isolated and least-privilege'
);
SELECT * FROM extensions.finish();
ROLLBACK;

\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(7);

SELECT extensions.ok(
    public.is_reserved_public_username('admin')
    AND public.is_reserved_public_username('security')
    AND public.is_reserved_public_username('customer_support')
    AND public.is_reserved_public_username('naturebook'),
    'system roles and protected product namespaces are reserved'
);

SELECT extensions.ok(
    public.is_reserved_public_username(' NatureBook_Support ')
    AND public.is_reserved_public_username('support_naturebook')
    AND public.is_reserved_public_username('naturebook_customer_support')
    AND public.is_reserved_public_username('customer_support_naturebook'),
    'brand-role combinations are reserved in both directions after canonicalization'
);

SELECT extensions.ok(
    NOT public.is_reserved_public_username('naturebook_fan')
    AND NOT public.is_reserved_public_username('security_researcher')
    AND NOT public.is_reserved_public_username('team_wren')
    AND NOT public.is_reserved_public_username('naturebook_supporter'),
    'ordinary community handles are not captured by broad prefix matching'
);

SELECT extensions.ok(
    NOT public.is_valid_public_username('security')
    AND NOT public.is_valid_public_username('naturebook_support')
    AND NOT public.is_valid_public_username('support_naturebook')
    AND public.is_valid_public_username('naturebook_fan'),
    'the canonical username validator applies the expanded reserved policy'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_language AS language
          ON language.oid = routine.prolang
        WHERE routine.oid =
              'public.is_reserved_public_username(text)'::REGPROCEDURE
          AND routine.provolatile = 'i'
          AND language.lanname = 'plpgsql'
    ),
    'the reserved-name function remains immutable and uses the reviewed policy implementation'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.convalidated
          AND constraint_row.contype = 'c'
          AND constraint_row.conrelid = 'public.users'::REGCLASS
          AND constraint_row.conname = 'users_public_username_valid_check'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid, TRUE)
              LIKE '%is_valid_public_username%'
    )
    AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.convalidated
          AND constraint_row.contype = 'c'
          AND constraint_row.conrelid =
              'public.explore_comment_mentions'::REGCLASS
          AND constraint_row.conname =
              'explore_comment_mentions_username_valid_check'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid, TRUE)
              NOT LIKE '%is_valid_public_username%'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid, TRUE)
              LIKE '%char_length(mention_username)%'
    ),
    'profile handles enforce current reservations while historical mention snapshots enforce shape'
);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-4000-8000-000000000811'::UUID,
    'authenticated',
    'authenticated',
    'username-policy-811@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

UPDATE public.users
SET public_username = 'policy_tester_811',
    public_author_name = 'policy_tester_811',
    public_identity_source = 'alias'
WHERE id = '00000000-0000-4000-8000-000000000811'::UUID;

DO $$
BEGIN
    BEGIN
        UPDATE public.users
        SET public_username = 'security'
        WHERE id = '00000000-0000-4000-8000-000000000811'::UUID;

        RAISE EXCEPTION 'reserved profile username unexpectedly passed validation';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;
END;
$$;

SELECT extensions.pass(
    'the profile CHECK constraint rejects a newly reserved username on write'
);

SELECT * FROM extensions.finish();
ROLLBACK;

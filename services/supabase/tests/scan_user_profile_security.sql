\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(10);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.ensure_scan_user_profile(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.ensure_scan_user_profile(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.ensure_scan_user_profile(uuid)',
        'EXECUTE'
    ),
    'scan profile prerequisite has an exact service-only API ACL'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT public.ensure_scan_user_profile(
            '00000000-0000-4000-8000-000000000999'
        )
    $statement$,
    '23503',
    'scan_user_auth_identity_missing',
    'scan profile prerequisite refuses an identity absent from Auth'
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
VALUES
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000900',
        'authenticated',
        'authenticated',
        'scan-profile-900@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{"full_name":"River Tester"}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000901',
        'authenticated',
        'authenticated',
        NULL,
        NULL,
        pg_catalog.NOW(),
        '{"provider":"anonymous","providers":["anonymous"]}',
        '{}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        TRUE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000902',
        'authenticated',
        'authenticated',
        'scan-profile-902@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000903',
        'authenticated',
        'authenticated',
        'scan-profile-903@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000904',
        'authenticated',
        'authenticated',
        NULL,
        NULL,
        pg_catalog.NOW(),
        '{"provider":"anonymous","providers":["anonymous"]}',
        '{}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        TRUE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-000000000905',
        'authenticated',
        'authenticated',
        'scan-profile-905@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    );

-- Auth signup normally created these rows. Remove selected profiles to model
-- the production drift this boundary repairs.
DELETE FROM public.users
WHERE id IN (
    '00000000-0000-4000-8000-000000000900',
    '00000000-0000-4000-8000-000000000901',
    '00000000-0000-4000-8000-000000000903',
    '00000000-0000-4000-8000-000000000904'
);

SELECT extensions.is(
    public.ensure_scan_user_profile(
        '00000000-0000-4000-8000-000000000900'
    ),
    TRUE,
    'scan profile prerequisite creates a missing real Auth profile'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id =
              '00000000-0000-4000-8000-000000000900'
          AND profile.email =
              'scan-profile-900@naturebook.invalid'
          AND profile.subscription_tier = 'free'
          AND NULLIF(pg_catalog.BTRIM(profile.public_author_name), '')
              IS NOT NULL
          AND profile.public_identity_source IN (
              'alias',
              'derived_name',
              'display_name'
          )
          AND public.is_valid_public_username(profile.public_username)
    ),
    'repaired profile satisfies every mandatory public identity invariant'
);

SELECT extensions.is(
    public.ensure_scan_user_profile(
        '00000000-0000-4000-8000-000000000900'
    ),
    FALSE,
    'scan profile prerequisite is idempotent after repair'
);

UPDATE public.users
SET public_username = 'keeper_902',
    public_author_name = 'Keeper',
    public_identity_source = 'display_name'
WHERE id = '00000000-0000-4000-8000-000000000902';

SELECT extensions.ok(
    NOT public.ensure_scan_user_profile(
        '00000000-0000-4000-8000-000000000902'
    )
    AND EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id =
              '00000000-0000-4000-8000-000000000902'
          AND profile.public_username = 'keeper_902'
          AND profile.public_author_name = 'Keeper'
          AND profile.public_identity_source = 'display_name'
    ),
    'existing profile identity remains unchanged'
);

INSERT INTO internal.ghost_profile_merge_handoffs (
    ghost_user_id,
    target_user_id,
    expected_provider,
    expected_provider_subject,
    secret_hash,
    status,
    expires_at,
    merged_at
)
VALUES (
    '00000000-0000-4000-8000-000000000901',
    '00000000-0000-4000-8000-000000000905',
    'apple',
    'retired-profile-901',
    pg_catalog.REPEAT('9', 64),
    'merged',
    pg_catalog.NOW() + INTERVAL '30 days',
    pg_catalog.NOW()
);

SELECT extensions.throws_ok(
    $statement$
        SELECT public.ensure_scan_user_profile(
            '00000000-0000-4000-8000-000000000901'
        )
    $statement$,
    '55000',
    'scan_user_identity_retired',
    'scan profile prerequisite cannot resurrect a merged ghost identity'
);

DO $$
BEGIN
    PERFORM *
    FROM public.request_account_deletion(
        '00000000-0000-4000-8000-000000000903'
    );
END;
$$;

SELECT extensions.throws_ok(
    $statement$
        SELECT public.ensure_scan_user_profile(
            '00000000-0000-4000-8000-000000000903'
        )
    $statement$,
    '55000',
    'scan_user_account_deletion_in_progress',
    'scan profile prerequisite cannot race durable account deletion'
);

DO $$
BEGIN
    PERFORM public.reserve_ghost_user_bulk_cleanup(
        '00000000-0000-4000-8000-000000000904',
        15
    );
END;
$$;

SELECT extensions.throws_ok(
    $statement$
        SELECT public.ensure_scan_user_profile(
            '00000000-0000-4000-8000-000000000904'
        )
    $statement$,
    '55P03',
    'scan_user_cleanup_in_progress',
    'scan profile prerequisite cannot race empty-ghost cleanup'
);

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id IN (
            '00000000-0000-4000-8000-000000000901',
            '00000000-0000-4000-8000-000000000903',
            '00000000-0000-4000-8000-000000000904'
        )
    ),
    'all retirement fences leave blocked public profiles absent'
);

SELECT * FROM extensions.finish();
ROLLBACK;

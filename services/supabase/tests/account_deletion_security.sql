\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $$
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_sign_in_revocation_credentials',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.apple_sign_in_credential_registrations',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_recovery_capabilities',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_recovery_capabilities',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_recovery_capabilities',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_recovery_preparations',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_recovery_preparations',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_recovery_preparations',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_expired_preparation_proofs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_expired_preparation_proofs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_expired_preparation_proofs',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'API roles unexpectedly have direct account-deletion internals access';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.pending_storage_deletions',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.pending_storage_deletions',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.pending_storage_deletions',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'An API role can bypass the account-storage erasure worker';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_account_deletion_jobs(integer,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.store_apple_revocation_credential(uuid,uuid,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.apple_revocation_registration_exists(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_account_deletion_provider_token(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.complete_account_deletion_provider_revocation(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_account_deletion_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_account_deletion_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_account_deletion_with_recovery(uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_account_deletion_with_recovery(uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.recover_account_deletion(text,boolean)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_account_deletion(text,boolean)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_account_deletion_recovery_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_account_deletion_recovery_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.prepare_account_deletion_recovery_v2(uuid,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.prepare_account_deletion_recovery_v2(uuid,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_account_deletion_with_recovery_v2(uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_account_deletion_with_recovery_v2(uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.recover_account_deletion_v2(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_account_deletion_v2(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.acknowledge_account_deletion_recovery_v2(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.acknowledge_account_deletion_recovery_v2(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.prune_account_deletion_recovery_preparations(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.prune_account_deletion_recovery_preparations(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_account_deletion_recovery_preparation_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_account_deletion_recovery_preparation_health()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'A public client role can execute an account-deletion worker RPC';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_account_deletion_jobs(integer,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.store_apple_revocation_credential(uuid,uuid,text,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.apple_revocation_registration_exists(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_account_deletion_provider_token(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.complete_account_deletion_provider_revocation(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_account_deletion_health()',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_account_deletion_with_recovery(uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.recover_account_deletion(text,boolean)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_account_deletion_recovery_health()',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.prepare_account_deletion_recovery_v2(uuid,text,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_account_deletion_with_recovery_v2(uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.recover_account_deletion_v2(text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.acknowledge_account_deletion_recovery_v2(text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.prune_account_deletion_recovery_preparations(integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_account_deletion_recovery_preparation_health()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'service_role is missing an account-deletion worker or health RPC';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_pending_storage_deletions(integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.advance_pending_storage_deletion(uuid,uuid,text,boolean)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.fail_pending_storage_deletion(uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_pending_storage_deletions(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.claim_pending_storage_deletions(integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'Invalid account-storage erasure worker RPC grants';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS column_row
        WHERE column_row.attrelid = 'public.scans'::REGCLASS
          AND column_row.attname = 'user_id'
          AND column_row.attnotnull
          AND NOT column_row.attisdropped
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'public.scans'::REGCLASS
          AND constraint_row.conname =
              'scans_ownerless_requires_tombstone_check'
          AND constraint_row.contype = 'c'
          AND constraint_row.convalidated
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.conrelid = 'public.users'::REGCLASS
          AND constraint_row.confrelid = 'auth.users'::REGCLASS
          AND constraint_row.confdeltype = 'r'
          AND constraint_row.convalidated
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND source_column.attname = 'id'
          AND target_column.attname = 'id'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies AS policy_row
        WHERE policy_row.schemaname = 'public'
          AND policy_row.tablename = 'scans'
          AND policy_row.policyname =
              'Anyone can read open and live scans'
          AND policy_row.qual ~* 'is_tombstoned.*false'
    ) THEN
        RAISE EXCEPTION
            'Ownerless tombstone or Auth-profile catalog invariants are missing';
    END IF;
END;
$$;

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
    '00000000-0000-0000-0000-00000000d201'::UUID,
    'authenticated',
    'authenticated',
    'account-deletion-test@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
)
VALUES (
    'account-deletion-apple-subject',
    '00000000-0000-0000-0000-00000000d201'::UUID,
    '{"sub":"account-deletion-apple-subject"}'::JSONB,
    'apple',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    pg_catalog.NOW()
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
    '00000000-0000-0000-0000-00000000d202'::UUID,
    'authenticated',
    'authenticated',
    'legacy-apple-deletion-test@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"apple","providers":["apple"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
)
VALUES (
    'legacy-account-deletion-apple-subject',
    '00000000-0000-0000-0000-00000000d202'::UUID,
    '{"sub":"legacy-account-deletion-apple-subject"}'::JSONB,
    'apple',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    pg_catalog.NOW()
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
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-0000-0000-00000000d203'::UUID,
        'authenticated',
        'authenticated',
        'prepared-deletion-cancel@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-0000-0000-00000000d204'::UUID,
        'authenticated',
        'authenticated',
        'prepared-deletion-multidevice@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-0000-0000-00000000d205'::UUID,
        'authenticated',
        'authenticated',
        'prepared-deletion-commit@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-0000-0000-00000000d206'::UUID,
        'authenticated',
        'authenticated',
        'expired-preparation-cross-device@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-0000-0000-00000000d207'::UUID,
        'authenticated',
        'authenticated',
        'expired-preparation-recovery@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    );

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-0000-0000-00000000d201'::UUID,
    'account-deletion-test@naturebook.invalid',
    'delete_test_d201',
    'Deletion Test',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    timestamp,
    gps_lat_exact,
    gps_long_exact,
    gps_elevation,
    coordinate_uncertainty_in_meters,
    weather_condition,
    weather_temperature_f,
    semantic_location,
    public_location_label,
    human_intervention_notes,
    image_storage_urls,
    video_storage_urls,
    audio_storage_urls,
    captured_media
)
VALUES (
    '00000000-0000-0000-0000-00000000d211'::UUID,
    '00000000-0000-0000-0000-00000000d201'::UUID,
    0.91,
    TIMESTAMPTZ '2025-04-05 14:30:00+00',
    41.881832,
    -87.623177,
    181.0,
    12,
    'clear',
    68.5,
    'Account-linked test location',
    'Account-linked test location',
    'account deletion personal note',
    ARRAY[
        'https://media.example.invalid/public_uploads/free/'
            || '00000000-0000-0000-0000-00000000d201/image.jpg'
    ]::TEXT[],
    ARRAY[
        'https://media.example.invalid/public_uploads/free/'
            || '00000000-0000-0000-0000-00000000d201/video.mp4'
    ]::TEXT[],
    ARRAY[
        'https://media.example.invalid/public_uploads/free/'
            || '00000000-0000-0000-0000-00000000d201/audio.m4a'
    ]::TEXT[],
    '[{"kind":"image","url":"https://media.example.invalid/private.jpg"}]'::JSONB
);

-- Exercise the narrow collision path where an individual scan-erasure fence
-- already exists when account deletion detaches the observation.
INSERT INTO internal.scan_deletion_tombstones (
    scan_id,
    user_id
)
VALUES (
    '00000000-0000-0000-0000-00000000d211'::UUID,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

-- A stale outbox row for a live account must never authorize an R2 prefix
-- sweep. This row becomes valid only after the durable deletion workflow below
-- tombstones the profile and advances its matching job to storage_pending.
INSERT INTO public.pending_storage_deletions (
    target_user_id,
    status,
    prefixes,
    phase,
    prefix_index,
    verification_not_before
)
VALUES (
    '00000000-0000-0000-0000-00000000d201'::UUID,
    'pending',
    ARRAY[
        'public_uploads/free/00000000-0000-0000-0000-00000000d201/',
        'public_uploads/pro/00000000-0000-0000-0000-00000000d201/',
        'staging/00000000-0000-0000-0000-00000000d201/',
        'avatars/00000000-0000-0000-0000-00000000d201/',
        'exports/00000000-0000-0000-0000-00000000d201/'
    ]::TEXT[],
    'sweep',
    1,
    pg_catalog.NOW() + INTERVAL '25 hours'
);

SET LOCAL ROLE service_role;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.claim_pending_storage_deletions(100) AS storage_claim
        WHERE storage_claim.target_user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'An orphaned storage outbox row targeted a live account';
    END IF;
END;
$$;

RESET ROLE;

CREATE TEMP TABLE account_deletion_test_job (
    job_id UUID NOT NULL,
    job_status TEXT NOT NULL,
    manual_provider_revocation_required BOOLEAN NOT NULL
);
GRANT SELECT, INSERT ON account_deletion_test_job TO service_role;

CREATE TEMP TABLE account_deletion_test_claim (
    job_id UUID NOT NULL,
    user_id UUID NOT NULL,
    job_status TEXT NOT NULL,
    claim_token UUID NOT NULL,
    claim_expires_at TIMESTAMPTZ NOT NULL
);
GRANT SELECT, INSERT, DELETE ON account_deletion_test_claim TO service_role;

SET LOCAL ROLE service_role;

SELECT public.store_apple_revocation_credential(
    '00000000-0000-0000-0000-00000000d201'::UUID,
    '00000000-0000-0000-0000-00000000d221'::UUID,
    'account-deletion-apple-subject',
    'fixture-apple-refresh-token-123456789'
);

DO $$
BEGIN
    -- Two devices prepare independently. The first proof is made stale below
    -- to prove a later cross-device deletion can materialize only the live one.
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d206'::UUID,
        pg_catalog.REPEAT('5', 64),
        pg_catalog.REPEAT('6', 64)
    );
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d206'::UUID,
        pg_catalog.REPEAT('7', 64),
        pg_catalog.REPEAT('8', 64)
    );
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d207'::UUID,
        pg_catalog.REPEAT('9', 64),
        pg_catalog.REPEAT('0', 64)
    );
END;
$$;

RESET ROLE;

UPDATE internal.account_deletion_recovery_preparations AS preparation
SET prepared_at = pg_catalog.NOW() - INTERVAL '2 seconds',
    expires_at = pg_catalog.NOW() - INTERVAL '1 second'
WHERE preparation.user_id =
        '00000000-0000-0000-0000-00000000d206'::UUID
  AND preparation.recovery_secret_hash = pg_catalog.REPEAT('5', 64);

UPDATE internal.account_deletion_recovery_preparations AS preparation
SET prepared_at = pg_catalog.NOW() - INTERVAL '2 seconds',
    expires_at = pg_catalog.NOW() - INTERVAL '1 second'
WHERE preparation.user_id =
        '00000000-0000-0000-0000-00000000d207'::UUID
  AND preparation.recovery_secret_hash = pg_catalog.REPEAT('9', 64);

SET LOCAL ROLE service_role;

DO $$
DECLARE
    prepared BOOLEAN;
    preparation_expiry TIMESTAMPTZ;
    deletion_job_id UUID;
    replayed_job_id UUID;
    recovered_status TEXT;
    recovery_acknowledged BOOLEAN;
    wrong_proof_rejected BOOLEAN := FALSE;
    wrong_user_rejected BOOLEAN := FALSE;
    expired_proof_rejected BOOLEAN := FALSE;
BEGIN
    -- Public recovery retires an expired non-destructive preparation and must
    -- never stretch it into a deletion capability.
    SELECT recovery.deletion_status
    INTO STRICT recovered_status
    FROM public.recover_account_deletion_v2(
        pg_catalog.REPEAT('9', 64)
    ) AS recovery;
    IF recovered_status <> 'not_committed'
       OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id =
                '00000000-0000-0000-0000-00000000d207'::UUID
       ) OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_capabilities AS capability
            WHERE capability.secret_hash = pg_catalog.REPEAT('9', 64)
       ) OR NOT EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs AS expired
            WHERE expired.proof_hash = pg_catalog.REPEAT('9', 64)
              AND expired.proof_kind = 'recovery'
              AND NOT expired.deletion_committed
       ) THEN
        RAISE EXCEPTION
            'Public recovery promoted or retained an expired preparation';
    END IF;

    expired_proof_rejected := FALSE;
    BEGIN
        PERFORM 1
        FROM public.prepare_account_deletion_recovery_v2(
            '00000000-0000-0000-0000-00000000d207'::UUID,
            pg_catalog.REPEAT('9', 64),
            pg_catalog.REPEAT('0', 64)
        );
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            expired_proof_rejected := SQLERRM =
                'account_deletion_recovery_preparation_expired';
    END;
    IF NOT expired_proof_rejected THEN
        RAISE EXCEPTION
            'An expired proof hash was reused by a new preparation';
    END IF;

    -- A prepare is non-destructive. Recovering it before any commit cancels
    -- only that device proof and leaves both Auth and account data intact.
    SELECT preparation.recovery_prepared, preparation.recovery_expires_at
    INTO STRICT prepared, preparation_expiry
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d203'::UUID,
        pg_catalog.REPEAT('c', 64),
        pg_catalog.REPEAT('d', 64)
    ) AS preparation;

    IF NOT prepared
       OR preparation_expiry <= pg_catalog.NOW()
       OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_jobs AS jobs
            WHERE jobs.user_id =
                '00000000-0000-0000-0000-00000000d203'::UUID
       ) THEN
        RAISE EXCEPTION
            'Protocol-v2 preparation created destructive state';
    END IF;

    SELECT recovery.deletion_status
    INTO STRICT recovered_status
    FROM public.recover_account_deletion_v2(
        pg_catalog.REPEAT('c', 64)
    ) AS recovery;

    IF recovered_status <> 'not_committed'
       OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.recovery_secret_hash =
                pg_catalog.REPEAT('c', 64)
       ) OR NOT EXISTS (
            SELECT 1
            FROM auth.users AS auth_user
            WHERE auth_user.id =
                '00000000-0000-0000-0000-00000000d203'::UUID
       ) THEN
        RAISE EXCEPTION
            'Prepared recovery did not cancel without deleting the account';
    END IF;

    -- Two devices may prepare independently. If any path commits deletion,
    -- the account-deletion INSERT trigger must convert both preparations into
    -- durable receipts before either device can observe not_committed.
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d204'::UUID,
        pg_catalog.REPEAT('e', 64),
        pg_catalog.REPEAT('f', 64)
    );
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d204'::UUID,
        pg_catalog.REPEAT('1', 64),
        pg_catalog.REPEAT('2', 64)
    );

    SELECT deletion.job_id
    INTO STRICT deletion_job_id
    FROM public.request_account_deletion(
        '00000000-0000-0000-0000-00000000d204'::UUID
    ) AS deletion;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.user_id =
            '00000000-0000-0000-0000-00000000d204'::UUID
    ) OR (
        SELECT pg_catalog.COUNT(*)
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = deletion_job_id
          AND capability.protocol_version = 2
    ) <> 2 THEN
        RAISE EXCEPTION
            'Deletion commit did not materialize every device receipt';
    END IF;

    SELECT recovery.deletion_status
    INTO STRICT recovered_status
    FROM public.recover_account_deletion_v2(
        pg_catalog.REPEAT('e', 64)
    ) AS recovery;
    IF recovered_status <> 'pending' THEN
        RAISE EXCEPTION
            'A committed multi-device proof reported not_committed';
    END IF;

    -- A cross-device deletion must prune the expired preparation before it
    -- converts the still-live preparation into a durable 180-day receipt.
    SELECT deletion.job_id
    INTO STRICT deletion_job_id
    FROM public.request_account_deletion(
        '00000000-0000-0000-0000-00000000d206'::UUID
    ) AS deletion;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.user_id =
            '00000000-0000-0000-0000-00000000d206'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = deletion_job_id
          AND capability.secret_hash = pg_catalog.REPEAT('5', 64)
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = deletion_job_id
          AND capability.protocol_version = 2
          AND capability.secret_hash = pg_catalog.REPEAT('7', 64)
          AND capability.acknowledgement_secret_hash =
              pg_catalog.REPEAT('8', 64)
    ) THEN
        RAISE EXCEPTION
            'Cross-device deletion promoted an expired preparation or lost the live proof';
    END IF;

    SELECT recovery.deletion_status
    INTO STRICT recovered_status
    FROM public.recover_account_deletion_v2(
        pg_catalog.REPEAT('5', 64)
    ) AS recovery;
    expired_proof_rejected := recovered_status = 'preparation_expired';
    IF NOT expired_proof_rejected OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_expired_preparation_proofs AS expired
        WHERE expired.proof_hash = pg_catalog.REPEAT('5', 64)
          AND expired.proof_kind = 'recovery'
          AND expired.deletion_committed
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_expired_preparation_proofs AS expired
        WHERE expired.proof_hash = pg_catalog.REPEAT('6', 64)
          AND expired.proof_kind = 'acknowledgement'
          AND expired.deletion_committed
    ) THEN
        RAISE EXCEPTION
            'An expired preparation was resurrected after cross-device deletion';
    END IF;

    SELECT recovery.deletion_status
    INTO STRICT recovered_status
    FROM public.recover_account_deletion_v2(
        pg_catalog.REPEAT('7', 64)
    ) AS recovery;
    IF recovered_status <> 'pending' THEN
        RAISE EXCEPTION
            'The live cross-device preparation did not recover its committed receipt';
    END IF;

    BEGIN
        PERFORM 1
        FROM public.recover_account_deletion_v2(
            pg_catalog.REPEAT('f', 64)
        );
    EXCEPTION
        WHEN SQLSTATE 'P0002' THEN
            wrong_proof_rejected := SQLERRM =
                'account_deletion_recovery_invalid';
    END;
    IF NOT wrong_proof_rejected THEN
        RAISE EXCEPTION
            'Acknowledgement proof was accepted as a recovery proof';
    END IF;

    wrong_proof_rejected := FALSE;
    BEGIN
        PERFORM 1
        FROM public.acknowledge_account_deletion_recovery_v2(
            pg_catalog.REPEAT('e', 64)
        );
    EXCEPTION
        WHEN SQLSTATE 'P0002' THEN
            wrong_proof_rejected := SQLERRM =
                'account_deletion_recovery_invalid';
    END;
    IF NOT wrong_proof_rejected THEN
        RAISE EXCEPTION
            'Recovery proof was accepted as an acknowledgement proof';
    END IF;

    SELECT recovery.recovery_acknowledged
    INTO STRICT recovery_acknowledged
    FROM public.acknowledge_account_deletion_recovery_v2(
        pg_catalog.REPEAT('f', 64)
    ) AS recovery;
    IF NOT recovery_acknowledged THEN
        RAISE EXCEPTION
            'Independent protocol-v2 acknowledgement was not durable';
    END IF;

    SELECT deletion.job_id
    INTO STRICT replayed_job_id
    FROM public.request_account_deletion_with_recovery_v2(
        '00000000-0000-0000-0000-00000000d204'::UUID,
        pg_catalog.REPEAT('e', 64)
    ) AS deletion;
    IF replayed_job_id <> deletion_job_id THEN
        RAISE EXCEPTION
            'Protocol-v2 committed replay changed its deletion job';
    END IF;

    BEGIN
        PERFORM 1
        FROM public.request_account_deletion_with_recovery_v2(
            '00000000-0000-0000-0000-00000000d203'::UUID,
            pg_catalog.REPEAT('e', 64)
        );
    EXCEPTION
        WHEN SQLSTATE 'P0002' THEN
            wrong_user_rejected := SQLERRM =
                'account_deletion_recovery_invalid';
    END;
    IF NOT wrong_user_rejected THEN
        RAISE EXCEPTION
            'Authenticated commit replay accepted a different Auth user';
    END IF;

    -- Exercise the normal prepare -> authenticated commit path. The trigger
    -- materializes the proof inside request_account_deletion; the wrapper must
    -- return that receipt rather than attempting a duplicate insert.
    PERFORM 1
    FROM public.prepare_account_deletion_recovery_v2(
        '00000000-0000-0000-0000-00000000d205'::UUID,
        pg_catalog.REPEAT('3', 64),
        pg_catalog.REPEAT('4', 64)
    );
    SELECT deletion.job_id
    INTO STRICT deletion_job_id
    FROM public.request_account_deletion_with_recovery_v2(
        '00000000-0000-0000-0000-00000000d205'::UUID,
        pg_catalog.REPEAT('3', 64)
    ) AS deletion;
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = deletion_job_id
          AND capability.protocol_version = 2
          AND capability.secret_hash = pg_catalog.REPEAT('3', 64)
          AND capability.acknowledgement_secret_hash =
              pg_catalog.REPEAT('4', 64)
    ) THEN
        RAISE EXCEPTION
            'Normal protocol-v2 commit lost its two-proof receipt';
    END IF;
END;
$$;

DO $$
DECLARE
    manual_required BOOLEAN;
    recovery_expiry TIMESTAMPTZ;
    replayed_expiry TIMESTAMPTZ;
    recovered_status TEXT;
    recovered_manual_required BOOLEAN;
    recovered_acknowledged BOOLEAN;
    invalid_rejected BOOLEAN := FALSE;
BEGIN
    SELECT
        deletion.manual_provider_revocation_required,
        deletion.recovery_expires_at
    INTO STRICT manual_required, recovery_expiry
    FROM public.request_account_deletion_with_recovery(
        '00000000-0000-0000-0000-00000000d202'::UUID,
        pg_catalog.REPEAT('a', 64)
    ) AS deletion;

    IF manual_required IS NOT TRUE
       OR recovery_expiry <= pg_catalog.NOW() THEN
        RAISE EXCEPTION
            'Recovery intake did not atomically retain the deletion receipt';
    END IF;

    SELECT
        recovery.deletion_status,
        recovery.manual_provider_revocation_required,
        recovery.recovery_acknowledged
    INTO STRICT
        recovered_status,
        recovered_manual_required,
        recovered_acknowledged
    FROM public.recover_account_deletion(
        pg_catalog.REPEAT('a', 64),
        FALSE
    ) AS recovery;

    IF recovered_status <> 'pending'
       OR recovered_manual_required IS NOT TRUE
       OR recovered_acknowledged THEN
        RAISE EXCEPTION
            'Capability recovery changed or leaked the durable receipt';
    END IF;

    SELECT recovery.recovery_acknowledged
    INTO STRICT recovered_acknowledged
    FROM public.recover_account_deletion(
        pg_catalog.REPEAT('a', 64),
        TRUE
    ) AS recovery;

    IF NOT recovered_acknowledged THEN
        RAISE EXCEPTION 'Capability acknowledgement was not durable';
    END IF;

    -- A delayed duplicate authenticated intake can arrive after public
    -- acknowledgement. It must return the same receipt without reopening the
    -- proof or extending its expiry window.
    SELECT
        recovery.recovery_expires_at,
        recovery.recovery_acknowledged
    INTO STRICT recovery_expiry, recovered_acknowledged
    FROM public.recover_account_deletion(
        pg_catalog.REPEAT('a', 64),
        FALSE
    ) AS recovery;

    SELECT deletion.recovery_expires_at
    INTO STRICT replayed_expiry
    FROM public.request_account_deletion_with_recovery(
        '00000000-0000-0000-0000-00000000d202'::UUID,
        pg_catalog.REPEAT('a', 64)
    ) AS deletion;

    IF NOT recovered_acknowledged
       OR replayed_expiry <> recovery_expiry THEN
        RAISE EXCEPTION
            'Authenticated replay reopened an acknowledged recovery receipt';
    END IF;

    -- A random proof cannot select a job or target an Auth user.
    BEGIN
        PERFORM 1
        FROM public.recover_account_deletion(
            pg_catalog.REPEAT('b', 64),
            FALSE
        );
    EXCEPTION
        WHEN SQLSTATE 'P0002' THEN
            invalid_rejected := SQLERRM =
                'account_deletion_recovery_invalid';
    END;

    IF NOT invalid_rejected THEN
        RAISE EXCEPTION 'Unknown recovery capability was not rejected';
    END IF;

END;
$$;

RESET ROLE;

-- Acknowledgement is a permanent idempotency receipt. Losing that HTTP
-- response cannot become a wedge merely because the original inspection
-- window elapses.
UPDATE internal.account_deletion_recovery_capabilities AS capability
SET
    issued_at = pg_catalog.NOW() - INTERVAL '181 days',
    expires_at = pg_catalog.NOW() - INTERVAL '1 day'
WHERE capability.secret_hash = pg_catalog.REPEAT('a', 64);

SET LOCAL ROLE service_role;

DO $$
DECLARE
    acknowledged_replay BOOLEAN;
BEGIN
    SELECT recovery.recovery_acknowledged
    INTO STRICT acknowledged_replay
    FROM public.recover_account_deletion(
        pg_catalog.REPEAT('a', 64),
        FALSE
    ) AS recovery;

    IF NOT acknowledged_replay THEN
        RAISE EXCEPTION
            'Acknowledged recovery did not remain replayable after expiry';
    END IF;
END;
$$;

RESET ROLE;

-- An unacknowledged proof still emits the stable matched-expired result and is
-- retained indefinitely for an offline installation.
UPDATE internal.account_deletion_recovery_capabilities AS capability
SET acknowledged_at = NULL
WHERE capability.secret_hash = pg_catalog.REPEAT('a', 64);

SET LOCAL ROLE service_role;

DO $$
DECLARE
    expired_rejected BOOLEAN := FALSE;
    expired_count BIGINT;
    oldest_expired_age BIGINT;
    acknowledged_after_expiry BOOLEAN;
    acknowledged_count BIGINT;
BEGIN
    BEGIN
        PERFORM 1
        FROM public.recover_account_deletion(
            pg_catalog.REPEAT('a', 64),
            FALSE
        );
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            expired_rejected := SQLERRM =
                'account_deletion_recovery_expired';
    END;

    IF NOT expired_rejected THEN
        RAISE EXCEPTION
            'Expired matched recovery did not return its stable terminal code';
    END IF;

    SELECT
        health.expired_unacknowledged_count,
        health.oldest_expired_age_seconds
    INTO STRICT expired_count, oldest_expired_age
    FROM public.get_account_deletion_recovery_health() AS health;

    IF expired_count < 1 OR oldest_expired_age < 0 THEN
        RAISE EXCEPTION
            'Deletion-recovery health omitted an expired unacknowledged proof';
    END IF;

    SELECT recovery.recovery_acknowledged
    INTO STRICT acknowledged_after_expiry
    FROM public.recover_account_deletion(
        pg_catalog.REPEAT('a', 64),
        TRUE
    ) AS recovery;

    IF NOT acknowledged_after_expiry THEN
        RAISE EXCEPTION
            'Matched-expired recovery could not acknowledge completed local cleanup';
    END IF;

    SELECT
        health.expired_unacknowledged_count,
        health.acknowledged_retained_count
    INTO STRICT expired_count, acknowledged_count
    FROM public.get_account_deletion_recovery_health() AS health;

    IF expired_count <> 0 OR acknowledged_count < 1 THEN
        RAISE EXCEPTION
            'Matched-expired acknowledgement did not repair recovery health';
    END IF;
END;
$$;

INSERT INTO account_deletion_test_job
SELECT *
FROM public.request_account_deletion(
    '00000000-0000-0000-0000-00000000d201'::UUID
);

INSERT INTO account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.users AS app_user
        WHERE app_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_revocation_credentials AS credential
        WHERE credential.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS legacy_job
        WHERE legacy_job.user_id =
            '00000000-0000-0000-0000-00000000d202'::UUID
          AND legacy_job.provider_revocation_status = 'manual_required'
          AND legacy_job.manual_provider_revocation_required
    ) THEN
        RAISE EXCEPTION
            'Durable intake or claim mutated Auth or user data';
    END IF;
END;
$$;

DO $$
DECLARE
    auth_first_delete_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        DELETE FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID;
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            auth_first_delete_rejected := TRUE;
    END;

    IF NOT auth_first_delete_rejected THEN
        RAISE EXCEPTION
            'Profile foreign key allowed Auth deletion before cleanup';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
BEGIN
    BEGIN
        PERFORM public.finish_account_deletion_attempt(
            (SELECT job_id FROM account_deletion_test_claim),
            (SELECT claim_token FROM account_deletion_test_claim),
            TRUE,
            NULL
        );
        RAISE EXCEPTION
            'Auth completion succeeded before relational cleanup';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;
END;
$$;

SELECT public.complete_account_deletion_cleanup(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Relational cleanup deleted Auth before verification completed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users AS app_user
        WHERE app_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.id =
            '00000000-0000-0000-0000-00000000d211'::UUID
          AND scan.user_id IS NULL
          AND scan.is_tombstoned
          AND scan.gps_lat_exact = 41.881832
          AND scan.gps_long_exact = -87.623177
          AND scan.gps_elevation = 181.0
          AND scan.coordinate_uncertainty_in_meters = 12
          AND scan.timestamp =
              TIMESTAMPTZ '2025-04-05 14:30:00+00'
          AND scan.weather_condition = 'clear'
          AND scan.weather_temperature_f = 68.5
          AND scan.ai_confidence_score = 0.91
          AND scan.semantic_location IS NULL
          AND scan.public_location_label IS NULL
          AND scan.human_intervention_notes IS NULL
          AND scan.image_storage_urls = ARRAY[]::TEXT[]
          AND scan.video_storage_urls = ARRAY[]::TEXT[]
          AND scan.audio_storage_urls = ARRAY[]::TEXT[]
          AND scan.captured_media IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstone
        WHERE tombstone.scan_id =
            '00000000-0000-0000-0000-00000000d211'::UUID
          AND tombstone.user_id IS NULL
          AND tombstone.completed_at IS NOT NULL
          AND tombstone.claim_token IS NULL
          AND tombstone.lease_expires_at IS NULL
    ) OR EXISTS (
        SELECT 1
        FROM public.users AS invalid_sentinel
        WHERE invalid_sentinel.id =
            '00000000-0000-0000-0000-000000000000'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM auth.users AS invalid_auth_sentinel
        WHERE invalid_auth_sentinel.id =
            '00000000-0000-0000-0000-000000000000'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS deletion
        WHERE deletion.target_user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
          AND deletion.status = 'pending'
          AND deletion.phase = 'sweep'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'storage_pending'
          AND deletion_job.cleanup_completed_at IS NOT NULL
          AND deletion_job.storage_completed_at IS NULL
          AND deletion_job.claim_token IS NULL
    ) THEN
        RAISE EXCEPTION
            'Relational cleanup did not commit and verify the expected state';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
BEGIN
    IF public.complete_scan_deletion(
        '00000000-0000-0000-0000-00000000d211'::UUID,
        '00000000-0000-0000-0000-00000000d201'::UUID
    ) IS NOT TRUE THEN
        RAISE EXCEPTION
            'Terminal individual-deletion retry was not idempotent';
    END IF;
END;
$$;

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.id =
            '00000000-0000-0000-0000-00000000d211'::UUID
          AND scan.user_id IS NULL
          AND scan.is_tombstoned
          AND scan.gps_lat_exact = 41.881832
          AND scan.gps_long_exact = -87.623177
    ) THEN
        RAISE EXCEPTION
            'Stale individual-deletion retry removed retained Scientific Data';
    END IF;
END;
$$;

SET LOCAL ROLE anon;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.id =
            '00000000-0000-0000-0000-00000000d211'::UUID
    ) THEN
        RAISE EXCEPTION
            'Anonymous scan access exposed an ownerless scientific tombstone';
    END IF;
END;
$$;

RESET ROLE;

DO $$
BEGIN
    BEGIN
        UPDATE public.scans AS scan
        SET gps_lat_exact = 40.0
        WHERE scan.id =
            '00000000-0000-0000-0000-00000000d211'::UUID;
        RAISE EXCEPTION
            'Ownerless scientific tombstone allowed a stale location rewrite';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;
END;
$$;

DO $$
DECLARE
    recreation_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO public.users (
            id,
            email,
            public_username,
            public_author_name,
            public_identity_source
        )
        VALUES (
            '00000000-0000-0000-0000-00000000d201'::UUID,
            'account-deletion-resurrection@naturebook.invalid',
            'delete_again_d201',
            'Deletion Resurrection Test',
            'alias'
        );
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            recreation_rejected := TRUE;
    END;

    IF NOT recreation_rejected THEN
        RAISE EXCEPTION
            'Active deletion allowed the public profile to be recreated';
    END IF;
END;
$$;

-- Complete all five sweep prefixes and all five delayed verification prefixes.
-- The fixture shortens only the real-world signature-expiry delay after
-- relational cleanup has durably created the storage outbox.
UPDATE public.pending_storage_deletions AS deletion
SET verification_not_before = pg_catalog.NOW(),
    next_attempt_at = pg_catalog.NOW()
WHERE deletion.target_user_id =
    '00000000-0000-0000-0000-00000000d201'::UUID;

SET LOCAL ROLE service_role;

DO $$
DECLARE
    storage_claim RECORD;
    advancement TEXT;
    step_number INTEGER;
BEGIN
    FOR step_number IN 1..10 LOOP
        SELECT *
        INTO STRICT storage_claim
        FROM public.claim_pending_storage_deletions(1);

        advancement := public.advance_pending_storage_deletion(
            storage_claim.deletion_id,
            storage_claim.claim_token,
            NULL,
            TRUE
        );

        IF step_number < 5 AND advancement <> 'pending' THEN
            RAISE EXCEPTION 'storage sweep advanced to an invalid phase';
        ELSIF step_number = 5 AND advancement <> 'verifying' THEN
            RAISE EXCEPTION 'storage sweep skipped delayed verification';
        ELSIF step_number BETWEEN 6 AND 9
              AND advancement <> 'pending' THEN
            RAISE EXCEPTION 'storage verification advanced incorrectly';
        ELSIF step_number = 10 AND advancement <> 'completed' THEN
            RAISE EXCEPTION 'storage verification did not become terminal';
        END IF;
    END LOOP;
END;
$$;

DELETE FROM account_deletion_test_claim;

INSERT INTO account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

-- Auth is still present. Revalidate idempotent relational cleanup under the
-- new claim; only the terminal storage outbox permits auth_pending.
SELECT public.complete_account_deletion_cleanup(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);
SELECT public.complete_account_deletion_cleanup(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS deletion
        WHERE deletion.target_user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
          AND deletion.status = 'completed'
          AND deletion.phase = 'verification'
          AND deletion.completed_at IS NOT NULL
          AND deletion.claim_token IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM account_deletion_test_job
        )
          AND deletion_job.status = 'auth_pending'
          AND deletion_job.storage_completed_at IS NOT NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Verified storage completion did not gate auth_pending correctly';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
BEGIN
    BEGIN
        PERFORM public.finish_account_deletion_attempt(
            (SELECT job_id FROM account_deletion_test_claim),
            (SELECT claim_token FROM account_deletion_test_claim),
            TRUE,
            NULL
        );
        RAISE EXCEPTION
            'Auth completion succeeded before Apple provider revocation';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;
END;
$$;

DO $$
DECLARE
    stored_refresh_token TEXT;
BEGIN
    SELECT provider_token.refresh_token
    INTO STRICT stored_refresh_token
    FROM public.get_account_deletion_provider_token(
        (SELECT job_id FROM account_deletion_test_claim),
        (SELECT claim_token FROM account_deletion_test_claim)
    ) AS provider_token;

    IF stored_refresh_token <> 'fixture-apple-refresh-token-123456789' THEN
        RAISE EXCEPTION
            'Claimed Apple provider token did not match the Vault secret';
    END IF;
END;
$$;

-- The executable database fixture represents Apple's idempotent HTTP 200 by
-- committing the claimed provider transition. HTTP behavior is covered by the
-- Edge worker tests.
SELECT public.complete_account_deletion_provider_revocation(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);

RESET ROLE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_revocation_credentials AS credential
        WHERE credential.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_credential_registrations AS registration
        WHERE registration.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM account_deletion_test_job
        )
          AND deletion_job.provider_revocation_status = 'completed'
          AND deletion_job.provider_revocation_resolved_at IS NOT NULL
          AND deletion_job.manual_provider_revocation_required IS FALSE
    ) THEN
        RAISE EXCEPTION
            'Apple provider completion retained credentials or failed to commit';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    FALSE,
    'auth_http_503'
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.get_account_deletion_health() AS health
        WHERE health.active_job_count >= 1
          AND health.auth_pending_count >= 1
          AND health.failed_job_count >= 1
          AND health.oldest_pending_at IS NOT NULL
          AND health.oldest_pending_age_seconds IS NOT NULL
          AND health.orphaned_storage_job_count = 0
          AND health.reaper_cron_active IS NOT NULL
          AND health.reaper_credentials_configured IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Service-only account-deletion health omitted retry or SLA state';
    END IF;
END;
$$;

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'auth_pending'
          AND deletion_job.claim_token IS NULL
          AND deletion_job.next_attempt_at > pg_catalog.NOW()
          AND deletion_job.last_error_code = 'auth_http_503'
    ) OR NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Retry scheduling lost state or removed Auth prematurely';
    END IF;

    UPDATE internal.account_deletion_jobs AS deletion_job
    SET next_attempt_at = pg_catalog.NOW()
    WHERE deletion_job.id = (
        SELECT job_id
        FROM account_deletion_test_job
    );
END;
$$;

DELETE FROM account_deletion_test_claim;

SET LOCAL ROLE service_role;

INSERT INTO account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

RESET ROLE;

DELETE FROM auth.users
WHERE id = '00000000-0000-0000-0000-00000000d201'::UUID;

SET LOCAL ROLE service_role;

SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    TRUE,
    NULL
);

-- Lost-success retries are idempotent even after the terminal row erased its
-- direct user identifier and cleared the lease.
SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    TRUE,
    NULL
);

RESET ROLE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'completed'
          AND deletion_job.user_id IS NULL
          AND deletion_job.auth_deleted_at IS NOT NULL
          AND deletion_job.completed_at IS NOT NULL
          AND deletion_job.provider_revocation_status = 'completed'
          AND deletion_job.provider_revocation_resolved_at IS NOT NULL
          AND deletion_job.claim_token IS NULL
          AND deletion_job.last_error_code IS NULL
    ) THEN
        RAISE EXCEPTION
            'Terminal account-deletion state is incomplete or retains identity';
    END IF;
END;
$$;

SELECT extensions.pass(
    'account deletion persists intent, revokes Apple before Auth, records legacy fallback, retries, and minimizes terminal identity'
);
SELECT * FROM extensions.finish();
ROLLBACK;

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
        'authenticated',
        'public.get_account_deletion_manual_revocation_recipient(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.complete_account_deletion_manual_revocation_delivery(uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.prepare_account_deletion_manual_revocation_delivery(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.record_account_deletion_manual_revocation_acceptance(uuid,uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.record_account_deletion_manual_revocation_event(uuid,text,text,text,timestamptz)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_account_deletion_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_account_deletion_health()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'A public client role can execute an account-deletion worker RPC';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.apple_manual_revocation_delivery_requirements',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.apple_manual_revocation_delivery_requirements',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_manual_revocation_delivery_requirements',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_manual_revocation_delivery_attempts',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_manual_revocation_delivery_events',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'A Data API role can read the manual-delivery Auth fence';
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
        'public.get_account_deletion_manual_revocation_recipient(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.complete_account_deletion_manual_revocation_delivery(uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.prepare_account_deletion_manual_revocation_delivery(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.record_account_deletion_manual_revocation_acceptance(uuid,uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.record_account_deletion_manual_revocation_event(uuid,text,text,text,timestamptz)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_account_deletion_health()',
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

CREATE TEMP TABLE legacy_account_deletion_test_job (
    job_id UUID NOT NULL,
    job_status TEXT NOT NULL,
    manual_provider_revocation_required BOOLEAN NOT NULL
);
GRANT SELECT, INSERT ON legacy_account_deletion_test_job TO service_role;

CREATE TEMP TABLE legacy_account_deletion_test_claim (
    job_id UUID NOT NULL,
    user_id UUID NOT NULL,
    job_status TEXT NOT NULL,
    claim_token UUID NOT NULL,
    claim_expires_at TIMESTAMPTZ NOT NULL
);
GRANT SELECT, INSERT, DELETE ON legacy_account_deletion_test_claim
    TO service_role;

CREATE TEMP TABLE legacy_manual_delivery_attempt (
    attempt_number INTEGER PRIMARY KEY,
    recipient_email TEXT NOT NULL,
    attempt_token UUID NOT NULL,
    idempotency_key TEXT NOT NULL
);
GRANT SELECT, INSERT ON legacy_manual_delivery_attempt TO service_role;

SET LOCAL ROLE service_role;

SELECT public.store_apple_revocation_credential(
    '00000000-0000-0000-0000-00000000d201'::UUID,
    '00000000-0000-0000-0000-00000000d221'::UUID,
    'account-deletion-apple-subject',
    'fixture-apple-refresh-token-123456789'
);

INSERT INTO legacy_account_deletion_test_job
SELECT *
FROM public.request_account_deletion(
    '00000000-0000-0000-0000-00000000d202'::UUID
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM legacy_account_deletion_test_job AS legacy_job
        WHERE legacy_job.manual_provider_revocation_required
    ) THEN
        RAISE EXCEPTION
            'Legacy Apple deletion did not persist the manual fallback';
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
          AND legacy_job.manual_revocation_delivery_status = 'pending'
          AND legacy_job.manual_revocation_delivery_resolved_at IS NULL
    ) THEN
        RAISE EXCEPTION
            'Durable intake or claim mutated Auth or user data';
    END IF;
END;
$$;

-- Exercise the independent legacy-delivery stage without repeating the R2
-- cursor fixture. This represents an already verified empty storage prefix set
-- for the second user and retains Auth until Resend acceptance is committed.
INSERT INTO public.pending_storage_deletions (
    target_user_id,
    status,
    prefixes,
    phase,
    prefix_index,
    next_attempt_at,
    verification_not_before,
    completed_at,
    updated_at
)
VALUES (
    '00000000-0000-0000-0000-00000000d202'::UUID,
    'completed',
    ARRAY[
        'public_uploads/free/00000000-0000-0000-0000-00000000d202/',
        'public_uploads/pro/00000000-0000-0000-0000-00000000d202/',
        'staging/00000000-0000-0000-0000-00000000d202/',
        'avatars/00000000-0000-0000-0000-00000000d202/',
        'exports/00000000-0000-0000-0000-00000000d202/'
    ]::TEXT[],
    'verification',
    5,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    pg_catalog.NOW()
);

SET LOCAL ROLE service_role;

INSERT INTO legacy_account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d202'::UUID
);

DO $$
DECLARE
    resulting_phase TEXT;
BEGIN
    resulting_phase := public.complete_account_deletion_cleanup(
        (SELECT job_id FROM legacy_account_deletion_test_claim),
        (SELECT claim_token FROM legacy_account_deletion_test_claim)
    );
    IF resulting_phase <> 'manual_revocation_delivery_pending' THEN
        RAISE EXCEPTION
            'Legacy cleanup did not advance to instruction delivery';
    END IF;
END;
$$;

RESET ROLE;

DO $$
DECLARE
    auth_delete_rejected BOOLEAN := FALSE;
    rejected_constraint TEXT;
BEGIN
    BEGIN
        DELETE FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d202'::UUID;
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            GET STACKED DIAGNOSTICS
                rejected_constraint = CONSTRAINT_NAME;
            auth_delete_rejected := rejected_constraint =
                'apple_manual_delivery_requirement_user_fk';
    END;

    IF NOT auth_delete_rejected THEN
        RAISE EXCEPTION
            'Legacy delivery guard allowed Auth deletion before acceptance';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
DECLARE
    failure_message TEXT;
BEGIN
    BEGIN
        PERFORM public.finish_account_deletion_attempt(
            (SELECT job_id FROM legacy_account_deletion_test_claim),
            (SELECT claim_token FROM legacy_account_deletion_test_claim),
            TRUE,
            NULL
        );
        RAISE EXCEPTION
            'Legacy Auth completion succeeded before instruction delivery';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;

    BEGIN
        PERFORM 1
        FROM public.get_account_deletion_manual_revocation_recipient(
            (SELECT job_id FROM legacy_account_deletion_test_claim),
            (SELECT claim_token FROM legacy_account_deletion_test_claim)
        );
        RAISE EXCEPTION 'Legacy recipient RPC did not fail closed';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
            IF failure_message <>
               'account_deletion_manual_delivery_upgrade_required' THEN
                RAISE EXCEPTION
                    'Legacy recipient RPC failed for an unexpected reason';
            END IF;
    END;

    BEGIN
        PERFORM public.complete_account_deletion_manual_revocation_delivery(
            (SELECT job_id FROM legacy_account_deletion_test_claim),
            (SELECT claim_token FROM legacy_account_deletion_test_claim),
            'resend-account-deletion-legacy-worker'
        );
        RAISE EXCEPTION 'Legacy acceptance RPC did not fail closed';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
            IF failure_message <>
               'account_deletion_manual_delivery_confirmation_required' THEN
                RAISE EXCEPTION
                    'Legacy acceptance RPC failed for an unexpected reason';
            END IF;
    END;
END;
$$;

INSERT INTO legacy_manual_delivery_attempt (
    attempt_number,
    recipient_email,
    attempt_token,
    idempotency_key
)
SELECT
    1,
    attempt.recipient_email,
    attempt.attempt_token,
    attempt.idempotency_key
FROM public.prepare_account_deletion_manual_revocation_delivery(
    (SELECT job_id FROM legacy_account_deletion_test_claim),
    (SELECT claim_token FROM legacy_account_deletion_test_claim)
) AS attempt;

DO $$
DECLARE
    outcome TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM legacy_manual_delivery_attempt AS attempt
        WHERE attempt.attempt_number = 1
          AND attempt.recipient_email =
              'legacy-apple-deletion-test@naturebook.invalid'
          AND attempt.idempotency_key =
              'account-deletion-manual-apple/' ||
                attempt.attempt_token::TEXT
    ) THEN
        RAISE EXCEPTION
            'Prepared manual-delivery attempt was invalid';
    END IF;

    outcome := public.record_account_deletion_manual_revocation_event(
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 1),
        'evt_delivery_delayed_fixture_1',
        'resend-account-deletion-fixture-1',
        'email.delivery_delayed',
        TIMESTAMPTZ '2026-08-07 12:00:00+00'
    );
    IF outcome <> 'delivery_pending' THEN
        RAISE EXCEPTION
            'Out-of-order delayed event was not journaled pending acceptance';
    END IF;

    outcome := public.record_account_deletion_manual_revocation_acceptance(
        (SELECT job_id FROM legacy_account_deletion_test_claim),
        (SELECT claim_token FROM legacy_account_deletion_test_claim),
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 1),
        'resend-account-deletion-fixture-1'
    );
    IF outcome <> 'delivery_pending' THEN
        RAISE EXCEPTION
            'Send acceptance incorrectly resolved provider delivery';
    END IF;
END;
$$;

RESET ROLE;

DO $$
DECLARE
    auth_delete_rejected BOOLEAN := FALSE;
    rejected_constraint TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM legacy_account_deletion_test_job
        )
          AND deletion_job.manual_revocation_delivery_status =
              'delivery_delayed'
          AND deletion_job.manual_revocation_delivery_resolved_at IS NULL
          AND deletion_job.manual_revocation_delivery_provider_id =
              'resend-account-deletion-fixture-1'
          AND deletion_job.claim_token IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id =
            '00000000-0000-0000-0000-00000000d202'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_events AS event
        WHERE event.provider_event_id = 'evt_delivery_delayed_fixture_1'
          AND event.reduced_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Acceptance or delayed-event reduction released the Auth fence';
    END IF;

    BEGIN
        DELETE FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d202'::UUID;
    EXCEPTION
        WHEN SQLSTATE '23503' THEN
            GET STACKED DIAGNOSTICS
                rejected_constraint = CONSTRAINT_NAME;
            auth_delete_rejected := rejected_constraint =
                'apple_manual_delivery_requirement_user_fk';
    END;
    IF NOT auth_delete_rejected THEN
        RAISE EXCEPTION
            'Provider acceptance allowed Auth deletion before delivery';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
DECLARE
    outcome TEXT;
BEGIN
    outcome := public.record_account_deletion_manual_revocation_event(
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 1),
        'evt_bounced_fixture_1',
        'resend-account-deletion-fixture-1',
        'email.bounced',
        TIMESTAMPTZ '2026-08-07 12:01:00+00'
    );
    IF outcome <> 'retry_required' THEN
        RAISE EXCEPTION 'Terminal event did not require a new attempt';
    END IF;
END;
$$;

DELETE FROM legacy_account_deletion_test_claim;

INSERT INTO legacy_account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d202'::UUID
);

DO $$
DECLARE
    resulting_phase TEXT;
BEGIN
    resulting_phase := public.complete_account_deletion_cleanup(
        (SELECT job_id FROM legacy_account_deletion_test_claim),
        (SELECT claim_token FROM legacy_account_deletion_test_claim)
    );
    IF resulting_phase <> 'manual_revocation_delivery_pending' THEN
        RAISE EXCEPTION 'Terminal delivery did not enter retry dispatch';
    END IF;
END;
$$;

INSERT INTO legacy_manual_delivery_attempt (
    attempt_number,
    recipient_email,
    attempt_token,
    idempotency_key
)
SELECT
    2,
    attempt.recipient_email,
    attempt.attempt_token,
    attempt.idempotency_key
FROM public.prepare_account_deletion_manual_revocation_delivery(
    (SELECT job_id FROM legacy_account_deletion_test_claim),
    (SELECT claim_token FROM legacy_account_deletion_test_claim)
) AS attempt;

DO $$
DECLARE
    outcome TEXT;
BEGIN
    IF (
        SELECT first_attempt.attempt_token = second_attempt.attempt_token
        FROM legacy_manual_delivery_attempt AS first_attempt
        CROSS JOIN legacy_manual_delivery_attempt AS second_attempt
        WHERE first_attempt.attempt_number = 1
          AND second_attempt.attempt_number = 2
    ) THEN
        RAISE EXCEPTION 'Retry reused a terminal delivery attempt';
    END IF;

    outcome := public.record_account_deletion_manual_revocation_acceptance(
        (SELECT job_id FROM legacy_account_deletion_test_claim),
        (SELECT claim_token FROM legacy_account_deletion_test_claim),
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 2),
        'resend-account-deletion-fixture-2'
    );
    IF outcome <> 'delivery_pending' THEN
        RAISE EXCEPTION 'Acceptance without delivery did not remain pending';
    END IF;
END;
$$;

RESET ROLE;

DO $$
DECLARE
    auth_delete_rejected BOOLEAN := FALSE;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM legacy_account_deletion_test_job
        )
          AND deletion_job.manual_revocation_delivery_status = 'accepted'
          AND deletion_job.manual_revocation_delivery_resolved_at IS NULL
          AND deletion_job.manual_revocation_delivery_provider_id =
              'resend-account-deletion-fixture-2'
          AND deletion_job.claim_token IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id =
            '00000000-0000-0000-0000-00000000d202'::UUID
    ) THEN
        RAISE EXCEPTION 'Unconfirmed retry did not retain delivery state';
    END IF;

    BEGIN
        DELETE FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d202'::UUID;
    EXCEPTION
        WHEN SQLSTATE '23503' THEN auth_delete_rejected := TRUE;
    END;
    IF NOT auth_delete_rejected THEN
        RAISE EXCEPTION
            'Second provider acceptance allowed Auth deletion';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
DECLARE
    outcome TEXT;
    failure_message TEXT;
BEGIN
    outcome := public.record_account_deletion_manual_revocation_event(
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 2),
        'evt_delivered_fixture_2',
        'resend-account-deletion-fixture-2',
        'email.delivered',
        TIMESTAMPTZ '2026-08-07 12:02:00+00'
    );
    IF outcome <> 'delivered' THEN
        RAISE EXCEPTION 'Matching delivered event did not resolve delivery';
    END IF;

    outcome := public.record_account_deletion_manual_revocation_event(
        (SELECT attempt_token
         FROM legacy_manual_delivery_attempt
         WHERE attempt_number = 2),
        'evt_delivered_fixture_2',
        'resend-account-deletion-fixture-2',
        'email.delivered',
        TIMESTAMPTZ '2026-08-07 12:02:00+00'
    );
    IF outcome <> 'duplicate' THEN
        RAISE EXCEPTION 'Webhook replay was not idempotent';
    END IF;

    BEGIN
        PERFORM public.record_account_deletion_manual_revocation_event(
            (SELECT attempt_token
             FROM legacy_manual_delivery_attempt
             WHERE attempt_number = 2),
            'evt_delivered_fixture_2',
            'resend-account-deletion-fixture-2',
            'email.bounced',
            TIMESTAMPTZ '2026-08-07 12:02:00+00'
        );
        RAISE EXCEPTION 'Conflicting event identifier was accepted';
    EXCEPTION
        WHEN SQLSTATE '23505' THEN
            GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
            IF failure_message <> 'manual_revocation_event_id_conflict' THEN
                RAISE EXCEPTION
                    'Event identifier conflict returned the wrong failure';
            END IF;
    END;

    -- Duplicate intake after delivery must not recreate the Auth fence.
    PERFORM 1
    FROM public.request_account_deletion(
        '00000000-0000-0000-0000-00000000d202'::UUID
    );
END;
$$;

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM legacy_account_deletion_test_job
        )
          AND deletion_job.status = 'auth_pending'
          AND deletion_job.manual_revocation_delivery_status = 'delivered'
          AND deletion_job.manual_revocation_delivery_provider_id =
              'resend-account-deletion-fixture-2'
    ) OR EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id =
            '00000000-0000-0000-0000-00000000d202'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_events AS event
        JOIN internal.apple_manual_revocation_delivery_attempts AS attempt
          ON attempt.attempt_token = event.attempt_token
        WHERE attempt.job_id = (
            SELECT job_id FROM legacy_account_deletion_test_job
        )
          AND attempt.status = 'delivered'
          AND event.event_type = 'email.delivered'
          AND event.reduced_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Delivered event did not transactionally release the Auth fence';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DELETE FROM legacy_account_deletion_test_claim;

INSERT INTO legacy_account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d202'::UUID
);

DO $$
DECLARE
    resulting_phase TEXT;
BEGIN
    resulting_phase := public.complete_account_deletion_cleanup(
        (SELECT job_id FROM legacy_account_deletion_test_claim),
        (SELECT claim_token FROM legacy_account_deletion_test_claim)
    );
    IF resulting_phase <> 'auth_pending' THEN
        RAISE EXCEPTION
            'Confirmed manual delivery did not authorize Auth deletion';
    END IF;
END;
$$;

RESET ROLE;

DELETE FROM auth.users
WHERE id = '00000000-0000-0000-0000-00000000d202'::UUID;

SET LOCAL ROLE service_role;

SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM legacy_account_deletion_test_claim),
    (SELECT claim_token FROM legacy_account_deletion_test_claim),
    TRUE,
    NULL
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id FROM legacy_account_deletion_test_job
        )
          AND deletion_job.status = 'completed'
          AND deletion_job.user_id IS NULL
          AND deletion_job.provider_revocation_status = 'manual_required'
          AND deletion_job.manual_revocation_delivery_status = 'delivered'
          AND deletion_job.manual_revocation_delivery_provider_id =
              'resend-account-deletion-fixture-2'
    ) THEN
        RAISE EXCEPTION
            'Legacy deletion did not preserve confirmed delivery evidence';
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
          AND health.manual_revocation_delivery_pending_count = 0
          AND health.manual_revocation_delivery_accepted_count = 0
          AND health.manual_revocation_delivery_delayed_count = 0
          AND health.manual_revocation_delivery_retry_required_count = 0
          AND health.manual_revocation_delivery_delivered_count >= 1
          AND health.manual_revocation_delivery_unverifiable_count = 0
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
    'account deletion persists intent, revokes Apple or independently delivers legacy instructions before Auth, retries, and minimizes terminal identity'
);
SELECT * FROM extensions.finish();
ROLLBACK;

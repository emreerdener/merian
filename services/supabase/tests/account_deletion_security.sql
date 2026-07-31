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
    job_status TEXT NOT NULL
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
          AND deletion_job.claim_token IS NULL
          AND deletion_job.last_error_code IS NULL
    ) THEN
        RAISE EXCEPTION
            'Terminal account-deletion state is incomplete or retains identity';
    END IF;
END;
$$;

SELECT extensions.pass(
    'account deletion persists intent, cleans before Auth, retries, and minimizes terminal identity'
);
SELECT * FROM extensions.finish();
ROLLBACK;

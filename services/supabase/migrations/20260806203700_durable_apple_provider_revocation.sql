-- Sign in with Apple authorization is an external account resource. Capture
-- the refresh token in Vault when Apple sign-in succeeds, then make provider
-- revocation a durable, database-fenced prerequisite of Supabase Auth removal.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- Supabase CLI owns the migration and migration-history transaction boundary.
-- Keep the table locks and every statement that depends on them in one
-- anonymous block so LOCK TABLE runs inside a transaction without introducing
-- top-level transaction control.
DO $apple_revocation_schema$
BEGIN
LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE auth.identities IN SHARE MODE;
LOCK TABLE internal.account_deletion_jobs IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE internal.apple_sign_in_revocation_credentials (
    user_id UUID PRIMARY KEY
        REFERENCES auth.users(id) ON DELETE RESTRICT,
    refresh_token_secret_id UUID NOT NULL UNIQUE
        REFERENCES vault.secrets(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

COMMENT ON TABLE internal.apple_sign_in_revocation_credentials IS
    'Private mapping from an Auth user to a Vault-encrypted Apple refresh token. The restrictive Auth FK prevents bypassing provider revocation.';

ALTER TABLE internal.apple_sign_in_revocation_credentials
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.apple_sign_in_revocation_credentials
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.apple_sign_in_credential_registrations (
    registration_id UUID PRIMARY KEY,
    user_id UUID NOT NULL
        REFERENCES auth.users(id) ON DELETE CASCADE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT apple_sign_in_registration_id_check
        CHECK (
            registration_id <>
                '00000000-0000-0000-0000-000000000000'::UUID
        )
);

CREATE INDEX apple_sign_in_credential_registrations_user_idx
    ON internal.apple_sign_in_credential_registrations (
        user_id,
        registered_at DESC
    );

COMMENT ON TABLE internal.apple_sign_in_credential_registrations IS
    'Short idempotency receipts for Apple authorization-code capture. Receipts contain no Apple token and are removed with the Auth user.';

ALTER TABLE internal.apple_sign_in_credential_registrations
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.apple_sign_in_credential_registrations
    FROM PUBLIC, anon, authenticated, service_role;

-- Credential capture requires a non-anonymous Auth user with the matching
-- Apple identity. A Ghost source holding either row is invariant drift: never
-- move provider custody or its authorization-code receipt to another account.
INSERT INTO internal.ghost_profile_merge_reference_policies (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column,
    strategy,
    execution_order,
    handler_key,
    purpose
)
VALUES
    (
        'internal',
        'apple_sign_in_revocation_credentials',
        'user_id',
        'auth',
        'users',
        'id',
        'preserve',
        900,
        NULL,
        'Apple refresh-token custody belongs to the permanent provider identity and must never move from a Ghost source.'
    ),
    (
        'internal',
        'apple_sign_in_credential_registrations',
        'user_id',
        'auth',
        'users',
        'id',
        'preserve',
        900,
        NULL,
        'Apple authorization-code receipts belong to the permanent provider identity and must never move from a Ghost source.'
    )
ON CONFLICT (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column
) DO UPDATE
SET strategy = EXCLUDED.strategy,
    execution_order = EXCLUDED.execution_order,
    handler_key = EXCLUDED.handler_key,
    purpose = EXCLUDED.purpose;

ALTER TABLE internal.account_deletion_jobs
    ADD COLUMN provider_revocation_status TEXT NOT NULL
        DEFAULT 'not_required',
    ADD COLUMN provider_revocation_resolved_at TIMESTAMPTZ
        DEFAULT pg_catalog.NOW(),
    ADD COLUMN manual_provider_revocation_required BOOLEAN NOT NULL
        DEFAULT FALSE;

-- The credential table is new, so every Apple-linked account already inside
-- the deletion queue is a legacy account. Record the manual outcome instead
-- of allowing the rollout to imply that a programmatic revocation happened.
UPDATE internal.account_deletion_jobs AS deletion_job
SET provider_revocation_status = CASE
        WHEN deletion_job.user_id IS NOT NULL
         AND EXISTS (
             SELECT 1
             FROM internal.apple_sign_in_revocation_credentials AS credential
             WHERE credential.user_id = deletion_job.user_id
         ) THEN 'pending'
        WHEN deletion_job.user_id IS NOT NULL
         AND EXISTS (
             SELECT 1
             FROM auth.identities AS identity
             WHERE identity.user_id = deletion_job.user_id
               AND identity.provider = 'apple'
         ) THEN 'manual_required'
        ELSE 'not_required'
    END,
    provider_revocation_resolved_at = CASE
        WHEN deletion_job.user_id IS NOT NULL
         AND EXISTS (
             SELECT 1
             FROM internal.apple_sign_in_revocation_credentials AS credential
             WHERE credential.user_id = deletion_job.user_id
         ) THEN NULL
        ELSE pg_catalog.NOW()
    END,
    manual_provider_revocation_required =
        deletion_job.user_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM internal.apple_sign_in_revocation_credentials AS credential
            WHERE credential.user_id = deletion_job.user_id
        )
        AND EXISTS (
            SELECT 1
            FROM auth.identities AS identity
            WHERE identity.user_id = deletion_job.user_id
              AND identity.provider = 'apple'
        ),
    updated_at = pg_catalog.NOW();

ALTER TABLE internal.account_deletion_jobs
    DROP CONSTRAINT IF EXISTS account_deletion_jobs_state_check;

ALTER TABLE internal.account_deletion_jobs
    ADD CONSTRAINT account_deletion_jobs_provider_revocation_status_check
        CHECK (
            provider_revocation_status IN (
                'pending',
                'completed',
                'manual_required',
                'not_required'
            )
        ),
    ADD CONSTRAINT account_deletion_jobs_provider_revocation_state_check
        CHECK (
            (
                provider_revocation_status = 'pending'
                AND provider_revocation_resolved_at IS NULL
                AND manual_provider_revocation_required IS FALSE
            )
            OR (
                provider_revocation_status = 'completed'
                AND provider_revocation_resolved_at IS NOT NULL
                AND manual_provider_revocation_required IS FALSE
            )
            OR (
                provider_revocation_status = 'manual_required'
                AND provider_revocation_resolved_at IS NOT NULL
                AND manual_provider_revocation_required IS TRUE
            )
            OR (
                provider_revocation_status = 'not_required'
                AND provider_revocation_resolved_at IS NOT NULL
                AND manual_provider_revocation_required IS FALSE
            )
        ),
    ADD CONSTRAINT account_deletion_jobs_state_check
        CHECK (
            (
                status = 'pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NULL
                AND storage_completed_at IS NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'storage_pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'auth_pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NOT NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'completed'
                AND user_id IS NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NOT NULL
                AND auth_deleted_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND claim_token IS NULL
                AND claimed_at IS NULL
                AND claim_expires_at IS NULL
                AND last_error_code IS NULL
            )
        );

PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage();

END;
$apple_revocation_schema$;

CREATE OR REPLACE FUNCTION public.apple_revocation_registration_exists(
    p_user_id UUID,
    p_registration_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID
       OR p_registration_id IS NULL
       OR p_registration_id =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'apple_revocation_registration_invalid'
            USING ERRCODE = '22023';
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_credential_registrations AS registration
        WHERE registration.registration_id = p_registration_id
          AND registration.user_id = p_user_id
    );
END;
$$;

COMMENT ON FUNCTION public.apple_revocation_registration_exists(UUID, UUID) IS
    'Service-only idempotency lookup for an Apple authorization-code capture receipt.';

CREATE OR REPLACE FUNCTION public.store_apple_revocation_credential(
    p_user_id UUID,
    p_registration_id UUID,
    p_apple_subject TEXT,
    p_refresh_token TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    existing_credential
        internal.apple_sign_in_revocation_credentials%ROWTYPE;
    secret_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID
       OR p_registration_id IS NULL
       OR p_registration_id =
            '00000000-0000-0000-0000-000000000000'::UUID
       OR p_apple_subject IS NULL
       OR pg_catalog.CHAR_LENGTH(p_apple_subject) NOT BETWEEN 1 AND 255
       OR p_apple_subject ~ '[[:cntrl:]]'
       OR p_refresh_token IS NULL
       OR pg_catalog.CHAR_LENGTH(p_refresh_token) NOT BETWEEN 16 AND 8192
       OR p_refresh_token ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'apple_revocation_credential_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
      AND auth_user.is_anonymous IS FALSE
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'apple_revocation_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id = p_user_id
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    ) THEN
        RAISE EXCEPTION 'account_deletion_in_progress'
            USING ERRCODE = '55000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.identities AS identity
        WHERE identity.user_id = p_user_id
          AND identity.provider = 'apple'
          AND (
              identity.provider_id = p_apple_subject
              OR identity.identity_data ->> 'sub' = p_apple_subject
          )
    ) THEN
        RAISE EXCEPTION 'apple_revocation_identity_mismatch'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_credential_registrations AS registration
        WHERE registration.registration_id = p_registration_id
          AND registration.user_id = p_user_id
    ) THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_credential_registrations AS registration
        WHERE registration.registration_id = p_registration_id
          AND registration.user_id <> p_user_id
    ) THEN
        RAISE EXCEPTION 'apple_revocation_registration_conflict'
            USING ERRCODE = '23505';
    END IF;

    SELECT credential.*
    INTO existing_credential
    FROM internal.apple_sign_in_revocation_credentials AS credential
    WHERE credential.user_id = p_user_id
    FOR UPDATE;

    IF FOUND THEN
        PERFORM vault.update_secret(
            existing_credential.refresh_token_secret_id,
            p_refresh_token
        );

        UPDATE internal.apple_sign_in_revocation_credentials AS credential
        SET updated_at = pg_catalog.NOW()
        WHERE credential.user_id = p_user_id;
    ELSE
        secret_id := vault.create_secret(
            p_refresh_token,
            NULL,
            'Sign in with Apple refresh token for account-deletion revocation'
        );

        INSERT INTO internal.apple_sign_in_revocation_credentials (
            user_id,
            refresh_token_secret_id
        )
        VALUES (p_user_id, secret_id);
    END IF;

    INSERT INTO internal.apple_sign_in_credential_registrations (
        registration_id,
        user_id
    )
    VALUES (p_registration_id, p_user_id);

    DELETE FROM internal.apple_sign_in_credential_registrations AS registration
    WHERE registration.user_id = p_user_id
      AND registration.registered_at <
          pg_catalog.NOW() - INTERVAL '24 hours';
END;
$$;

COMMENT ON FUNCTION public.store_apple_revocation_credential(UUID, UUID, TEXT, TEXT) IS
    'Service-only atomic persistence of an Apple refresh token into Vault after binding the Apple subject to the permanent Auth user.';

CREATE OR REPLACE FUNCTION public.get_account_deletion_provider_token(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    refresh_token TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
      AND jobs.claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF deletion_job.status <> 'auth_pending'
       OR deletion_job.storage_completed_at IS NULL
       OR deletion_job.provider_revocation_status <> 'pending'
       OR deletion_job.provider_revocation_resolved_at IS NOT NULL
       OR deletion_job.user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_provider_revocation_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    SELECT secret.decrypted_secret
    FROM internal.apple_sign_in_revocation_credentials AS credential
    INNER JOIN vault.decrypted_secrets AS secret
        ON secret.id = credential.refresh_token_secret_id
    WHERE credential.user_id = deletion_job.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_provider_token_missing'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.get_account_deletion_provider_token(UUID, UUID) IS
    'Service-only claimed read of the Vault-decrypted Apple refresh token. The token is returned only while the durable provider stage is pending.';

CREATE OR REPLACE FUNCTION public.complete_account_deletion_provider_revocation(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    secret_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
      AND jobs.claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF deletion_job.status <> 'auth_pending'
       OR deletion_job.storage_completed_at IS NULL
       OR deletion_job.provider_revocation_status <> 'pending'
       OR deletion_job.provider_revocation_resolved_at IS NOT NULL
       OR deletion_job.user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_provider_revocation_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    DELETE FROM internal.apple_sign_in_revocation_credentials AS credential
    WHERE credential.user_id = deletion_job.user_id
    RETURNING credential.refresh_token_secret_id INTO secret_id;

    IF secret_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_provider_token_missing'
            USING ERRCODE = 'P0002';
    END IF;

    DELETE FROM internal.apple_sign_in_credential_registrations AS registration
    WHERE registration.user_id = deletion_job.user_id;

    DELETE FROM vault.secrets AS secret
    WHERE secret.id = secret_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_provider_secret_missing'
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE internal.account_deletion_jobs AS jobs
    SET provider_revocation_status = 'completed',
        provider_revocation_resolved_at = pg_catalog.NOW(),
        manual_provider_revocation_required = FALSE,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id
      AND jobs.claim_token = p_claim_token;
END;
$$;

COMMENT ON FUNCTION public.complete_account_deletion_provider_revocation(UUID, UUID) IS
    'Service-only claimed transition after Apple returns HTTP 200. It destroys the Vault token before authorizing Auth deletion.';

DROP FUNCTION public.request_account_deletion(UUID);
CREATE FUNCTION public.request_account_deletion(
    p_user_id UUID
)
RETURNS TABLE (
    job_id UUID,
    job_status TEXT,
    manual_provider_revocation_required BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    has_apple_identity BOOLEAN;
    has_apple_credential BOOLEAN;
    provider_status TEXT;
    provider_resolved_at TIMESTAMPTZ;
    manual_revocation_required BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
           '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM auth.identities AS identity
        WHERE identity.user_id = p_user_id
          AND identity.provider = 'apple'
    ) INTO has_apple_identity;

    SELECT EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_revocation_credentials AS credential
        WHERE credential.user_id = p_user_id
    ) INTO has_apple_credential;

    IF has_apple_credential THEN
        provider_status := 'pending';
        provider_resolved_at := NULL;
        manual_revocation_required := FALSE;
    ELSIF has_apple_identity THEN
        provider_status := 'manual_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := TRUE;
    ELSE
        provider_status := 'not_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := FALSE;
    END IF;

    RETURN QUERY
    INSERT INTO internal.account_deletion_jobs AS deletion_job (
        user_id,
        status,
        provider_revocation_status,
        provider_revocation_resolved_at,
        manual_provider_revocation_required,
        next_attempt_at
    )
    VALUES (
        p_user_id,
        'pending',
        provider_status,
        provider_resolved_at,
        manual_revocation_required,
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET updated_at = pg_catalog.NOW()
    RETURNING
        deletion_job.id,
        deletion_job.status,
        deletion_job.manual_provider_revocation_required;
END;
$$;

COMMENT ON FUNCTION public.request_account_deletion(UUID) IS
    'Service-only idempotent deletion intake. It records whether Apple revocation is pending, unnecessary, or requires legacy manual action before destructive work.';

CREATE OR REPLACE FUNCTION public.complete_account_deletion_cleanup(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    storage_status TEXT;
BEGIN
    PERFORM internal.require_service_role();

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
      AND jobs.claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF deletion_job.status NOT IN (
        'pending',
        'storage_pending',
        'auth_pending'
    )
       OR deletion_job.user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.pending_storage_deletions AS existing_deletion (
        target_user_id,
        status,
        prefixes,
        phase,
        prefix_index,
        next_attempt_at,
        verification_not_before,
        updated_at
    )
    VALUES (
        deletion_job.user_id,
        'pending',
        ARRAY[
            'public_uploads/free/' || deletion_job.user_id::TEXT || '/',
            'public_uploads/pro/' || deletion_job.user_id::TEXT || '/',
            'staging/' || deletion_job.user_id::TEXT || '/',
            'avatars/' || deletion_job.user_id::TEXT || '/',
            'exports/' || deletion_job.user_id::TEXT || '/'
        ]::TEXT[],
        'sweep',
        1,
        pg_catalog.NOW(),
        pg_catalog.NOW() + INTERVAL '25 hours',
        pg_catalog.NOW()
    )
    ON CONFLICT (target_user_id) DO NOTHING;

    PERFORM public.apply_user_tombstone(deletion_job.user_id);

    IF EXISTS (
        SELECT 1
        FROM public.users AS users
        WHERE users.id = deletion_job.user_id
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.user_id = deletion_job.user_id
    ) THEN
        RAISE EXCEPTION 'account_deletion_cleanup_verification_failed'
            USING ERRCODE = 'P0004';
    END IF;

    SELECT storage.status
    INTO storage_status
    FROM public.pending_storage_deletions AS storage
    WHERE storage.target_user_id = deletion_job.user_id
    FOR UPDATE;

    IF storage_status = 'completed' THEN
        UPDATE internal.account_deletion_jobs AS jobs
        SET status = 'auth_pending',
            cleanup_completed_at = COALESCE(
                jobs.cleanup_completed_at,
                pg_catalog.NOW()
            ),
            storage_completed_at = COALESCE(
                jobs.storage_completed_at,
                pg_catalog.NOW()
            ),
            next_attempt_at = pg_catalog.NOW(),
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;

        IF deletion_job.provider_revocation_status = 'pending' THEN
            RETURN 'provider_revocation_pending';
        END IF;
        RETURN 'auth_pending';
    END IF;

    UPDATE internal.account_deletion_jobs AS jobs
    SET status = 'storage_pending',
        cleanup_completed_at = COALESCE(
            jobs.cleanup_completed_at,
            pg_catalog.NOW()
        ),
        storage_completed_at = NULL,
        next_attempt_at = pg_catalog.NOW() + INTERVAL '5 minutes',
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id
      AND jobs.claim_token = p_claim_token;

    RETURN 'storage_pending';
END;
$$;

COMMENT ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID) IS
    'Service-only claimed relational cleanup. Verified storage advances to the durable provider-revocation phase before Auth can be removed.';

CREATE OR REPLACE FUNCTION public.finish_account_deletion_attempt(
    p_job_id UUID,
    p_claim_token UUID,
    p_auth_deleted BOOLEAN,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    retry_delay INTERVAL;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_deleted IS NULL THEN
        RAISE EXCEPTION 'account_deletion_attempt_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_job_not_found'
            USING ERRCODE = 'P0002';
    END IF;
    IF deletion_job.status = 'completed' AND p_auth_deleted IS TRUE THEN
        RETURN;
    END IF;
    IF deletion_job.claim_token IS NULL
       OR deletion_job.claim_token <> p_claim_token
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_auth_deleted IS TRUE THEN
        IF deletion_job.status <> 'auth_pending'
           OR deletion_job.storage_completed_at IS NULL
           OR NOT EXISTS (
               SELECT 1
               FROM public.pending_storage_deletions AS storage
               WHERE storage.target_user_id = deletion_job.user_id
                 AND storage.status = 'completed'
                 AND storage.completed_at IS NOT NULL
           ) THEN
            RAISE EXCEPTION 'account_deletion_storage_required'
                USING ERRCODE = '55000';
        END IF;

        IF deletion_job.provider_revocation_status = 'pending'
           OR deletion_job.provider_revocation_resolved_at IS NULL
           OR EXISTS (
               SELECT 1
               FROM internal.apple_sign_in_revocation_credentials AS credential
               WHERE credential.user_id = deletion_job.user_id
           ) THEN
            RAISE EXCEPTION 'account_deletion_provider_revocation_required'
                USING ERRCODE = '55000';
        END IF;

        UPDATE internal.account_deletion_jobs AS jobs
        SET user_id = NULL,
            status = 'completed',
            auth_deleted_at = pg_catalog.NOW(),
            completed_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    ELSE
        retry_delay := CASE
            WHEN deletion_job.attempt_count <= 1 THEN INTERVAL '1 minute'
            WHEN deletion_job.attempt_count = 2 THEN INTERVAL '2 minutes'
            WHEN deletion_job.attempt_count = 3 THEN INTERVAL '5 minutes'
            WHEN deletion_job.attempt_count = 4 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END;

        UPDATE internal.account_deletion_jobs AS jobs
        SET next_attempt_at = pg_catalog.NOW() + retry_delay,
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = pg_catalog.LEFT(
                COALESCE(
                    NULLIF(pg_catalog.BTRIM(p_error_code), ''),
                    'retryable_failure'
                ),
                120
            ),
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.apple_revocation_registration_exists(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.store_apple_revocation_credential(UUID, UUID, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_account_deletion_provider_token(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_provider_revocation(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.request_account_deletion(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.finish_account_deletion_attempt(UUID, UUID, BOOLEAN, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.apple_revocation_registration_exists(uuid,uuid)',
        'Authenticated Apple sign-in retries check a server-owned idempotency receipt before consuming a one-use authorization code.'
    ),
    (
        'service_role',
        'public.store_apple_revocation_credential(uuid,uuid,text,text)',
        'The authenticated Apple registration endpoint binds the verified subject and stores its refresh token in Vault.'
    ),
    (
        'service_role',
        'public.get_account_deletion_provider_token(uuid,uuid)',
        'A claim-fenced account-deletion worker reads the Vault token only during the pending provider-revocation phase.'
    ),
    (
        'service_role',
        'public.complete_account_deletion_provider_revocation(uuid,uuid)',
        'A claim-fenced account-deletion worker destroys the Apple token and commits provider success before Auth deletion.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

GRANT EXECUTE ON FUNCTION public.apple_revocation_registration_exists(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.store_apple_revocation_credential(UUID, UUID, TEXT, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_provider_token(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_provider_revocation(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_account_deletion_attempt(UUID, UUID, BOOLEAN, TEXT)
    TO service_role;

DO $migration_acl_audit$
DECLARE
    routine_signature TEXT;
BEGIN
    FOREACH routine_signature IN ARRAY ARRAY[
        'public.apple_revocation_registration_exists(uuid,uuid)',
        'public.store_apple_revocation_credential(uuid,uuid,text,text)',
        'public.get_account_deletion_provider_token(uuid,uuid)',
        'public.complete_account_deletion_provider_revocation(uuid,uuid)',
        'public.request_account_deletion(uuid)',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)'
    ] LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'anon',
            routine_signature,
            'EXECUTE'
        ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'authenticated',
            routine_signature,
            'EXECUTE'
        ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'service_role',
            routine_signature,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'apple_revocation_rpc_acl_invalid:%',
                routine_signature;
        END IF;
    END LOOP;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_sign_in_revocation_credentials',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.apple_sign_in_revocation_credentials',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.apple_sign_in_credential_registrations',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'apple_revocation_table_acl_invalid';
    END IF;
END;
$migration_acl_audit$;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;

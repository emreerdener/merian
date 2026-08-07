-- Legacy Sign in with Apple accounts have no refresh token to revoke. Deliver
-- Apple's manual-removal instructions through a durable, provider-confirmed
-- server-side stage so account deletion does not depend on the initiating iOS
-- binary receiving or understanding a response field.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- Keep the delivery-state backfill, attempt journal, and constraints under the
-- same locks. Supabase CLI owns the outer migration transaction.
DO $manual_revocation_delivery_schema$
BEGIN
LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE internal.account_deletion_jobs IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE internal.account_deletion_jobs
    ADD COLUMN manual_revocation_delivery_status TEXT NOT NULL
        DEFAULT 'not_required',
    ADD COLUMN manual_revocation_delivery_resolved_at TIMESTAMPTZ
        DEFAULT pg_catalog.NOW(),
    ADD COLUMN manual_revocation_delivery_provider_id TEXT;

CREATE TABLE internal.apple_manual_revocation_delivery_requirements (
    user_id UUID PRIMARY KEY,
    job_id UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT apple_manual_delivery_requirement_user_fk
        FOREIGN KEY (user_id)
        REFERENCES auth.users(id) ON DELETE RESTRICT,
    CONSTRAINT apple_manual_delivery_requirement_job_fk
        FOREIGN KEY (job_id)
        REFERENCES internal.account_deletion_jobs(id) ON DELETE RESTRICT
);

CREATE TABLE internal.apple_manual_revocation_delivery_attempts (
    attempt_token UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    job_id UUID NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'prepared',
    provider_delivery_id TEXT,
    last_event_type TEXT,
    prepared_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    accepted_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    terminal_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT apple_manual_delivery_attempt_job_fk
        FOREIGN KEY (job_id)
        REFERENCES internal.account_deletion_jobs(id) ON DELETE RESTRICT,
    CONSTRAINT apple_manual_delivery_attempt_idempotency_key_check
        CHECK (
            idempotency_key =
                'account-deletion-manual-apple/' || attempt_token::TEXT
        ),
    CONSTRAINT apple_manual_delivery_attempt_status_check
        CHECK (
            status IN (
                'prepared',
                'accepted',
                'delivery_delayed',
                'delivered',
                'retry_required'
            )
        ),
    CONSTRAINT apple_manual_delivery_attempt_provider_id_check
        CHECK (
            provider_delivery_id IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(provider_delivery_id)
                    BETWEEN 1 AND 255
                AND provider_delivery_id !~ '[[:cntrl:]]'
            )
        ),
    CONSTRAINT apple_manual_delivery_attempt_event_type_check
        CHECK (
            last_event_type IS NULL
            OR last_event_type IN (
                'email.delivered',
                'email.delivery_delayed',
                'email.bounced',
                'email.failed',
                'email.suppressed'
            )
        ),
    CONSTRAINT apple_manual_delivery_attempt_state_check
        CHECK (
            (
                status = 'prepared'
                AND provider_delivery_id IS NULL
                AND accepted_at IS NULL
                AND delivered_at IS NULL
                AND terminal_at IS NULL
                AND last_event_type IS NULL
            )
            OR (
                status = 'accepted'
                AND provider_delivery_id IS NOT NULL
                AND accepted_at IS NOT NULL
                AND delivered_at IS NULL
                AND terminal_at IS NULL
                AND last_event_type IS NULL
            )
            OR (
                status = 'delivery_delayed'
                AND provider_delivery_id IS NOT NULL
                AND accepted_at IS NOT NULL
                AND delivered_at IS NULL
                AND terminal_at IS NULL
                AND last_event_type = 'email.delivery_delayed'
            )
            OR (
                status = 'delivered'
                AND provider_delivery_id IS NOT NULL
                AND accepted_at IS NOT NULL
                AND delivered_at IS NOT NULL
                AND terminal_at IS NULL
                AND last_event_type = 'email.delivered'
            )
            OR (
                status = 'retry_required'
                AND provider_delivery_id IS NOT NULL
                AND accepted_at IS NOT NULL
                AND delivered_at IS NULL
                AND terminal_at IS NOT NULL
                AND last_event_type IN (
                    'email.bounced',
                    'email.failed',
                    'email.suppressed'
                )
            )
        )
);

CREATE UNIQUE INDEX apple_manual_delivery_attempts_active_job_idx
    ON internal.apple_manual_revocation_delivery_attempts (job_id)
    WHERE status IN ('prepared', 'accepted', 'delivery_delayed');

CREATE INDEX apple_manual_delivery_attempts_job_idx
    ON internal.apple_manual_revocation_delivery_attempts (job_id);

CREATE UNIQUE INDEX apple_manual_delivery_attempts_provider_id_idx
    ON internal.apple_manual_revocation_delivery_attempts (
        provider_delivery_id
    )
    WHERE provider_delivery_id IS NOT NULL;

CREATE TABLE internal.apple_manual_revocation_delivery_events (
    provider_event_id TEXT PRIMARY KEY,
    attempt_token UUID NOT NULL,
    provider_delivery_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    provider_created_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    reduced_at TIMESTAMPTZ,
    CONSTRAINT apple_manual_delivery_event_attempt_fk
        FOREIGN KEY (attempt_token)
        REFERENCES internal.apple_manual_revocation_delivery_attempts(
            attempt_token
        ) ON DELETE RESTRICT,
    CONSTRAINT apple_manual_delivery_event_id_check
        CHECK (
            pg_catalog.CHAR_LENGTH(provider_event_id) BETWEEN 1 AND 255
            AND provider_event_id !~ '[[:cntrl:]]'
        ),
    CONSTRAINT apple_manual_delivery_event_provider_id_check
        CHECK (
            pg_catalog.CHAR_LENGTH(provider_delivery_id) BETWEEN 1 AND 255
            AND provider_delivery_id !~ '[[:cntrl:]]'
        ),
    CONSTRAINT apple_manual_delivery_event_type_check
        CHECK (
            event_type IN (
                'email.delivered',
                'email.delivery_delayed',
                'email.bounced',
                'email.failed',
                'email.suppressed'
            )
        )
);

CREATE INDEX apple_manual_delivery_events_attempt_idx
    ON internal.apple_manual_revocation_delivery_events (
        attempt_token,
        provider_delivery_id,
        received_at
    );

-- An active manual-delivery requirement belongs to the source Auth deletion
-- lifecycle. Moving it to the permanent destination would transfer deletion
-- authority across identities, so any Ghost source that owns one must fail
-- before the merge mutates either profile.
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
VALUES (
    'internal',
    'apple_manual_revocation_delivery_requirements',
    'user_id',
    'auth',
    'users',
    'id',
    'preserve',
    900,
    NULL,
    'An active manual Apple delivery fence belongs to the source Auth deletion lifecycle and must block Ghost merge rather than move to another identity.'
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

-- Active legacy jobs still retain Auth and can be delivered safely. A legacy
-- job that completed before this migration no longer has an address to which
-- instructions can be sent, so preserve that historical gap explicitly and
-- make the independent health monitor treat it as a production blocker.
UPDATE internal.account_deletion_jobs AS deletion_job
SET manual_revocation_delivery_status = CASE
        WHEN deletion_job.manual_provider_revocation_required
         AND deletion_job.status = 'completed' THEN 'unverifiable'
        WHEN deletion_job.manual_provider_revocation_required THEN 'pending'
        ELSE 'not_required'
    END,
    manual_revocation_delivery_resolved_at = CASE
        WHEN deletion_job.manual_provider_revocation_required THEN NULL
        ELSE pg_catalog.NOW()
    END,
    manual_revocation_delivery_provider_id = NULL,
    updated_at = pg_catalog.NOW();

-- Mirror the stored-refresh-token Auth fence for every active legacy job. The
-- requirement is removed only in the same transaction that records a matching
-- signed email.delivered event, so neither a worker nor an operator can delete
-- Auth after dispatch acceptance alone.
INSERT INTO internal.apple_manual_revocation_delivery_requirements (
    user_id,
    job_id
)
SELECT
    deletion_job.user_id,
    deletion_job.id
FROM internal.account_deletion_jobs AS deletion_job
WHERE deletion_job.manual_revocation_delivery_status = 'pending'
  AND deletion_job.status IN ('pending', 'storage_pending', 'auth_pending')
  AND deletion_job.user_id IS NOT NULL;

ALTER TABLE internal.account_deletion_jobs
    ADD CONSTRAINT account_deletion_jobs_manual_delivery_status_check
        CHECK (
            manual_revocation_delivery_status IN (
                'pending',
                'accepted',
                'delivery_delayed',
                'retry_required',
                'delivered',
                'unverifiable',
                'not_required'
            )
        ),
    ADD CONSTRAINT account_deletion_jobs_manual_delivery_provider_id_check
        CHECK (
            manual_revocation_delivery_provider_id IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(
                    manual_revocation_delivery_provider_id
                ) BETWEEN 1 AND 255
                AND manual_revocation_delivery_provider_id
                    !~ '[[:cntrl:]]'
            )
        ),
    ADD CONSTRAINT account_deletion_jobs_manual_delivery_state_check
        CHECK (
            (
                manual_revocation_delivery_status = 'pending'
                AND manual_provider_revocation_required IS TRUE
                AND status IN (
                    'pending',
                    'storage_pending',
                    'auth_pending'
                )
                AND manual_revocation_delivery_resolved_at IS NULL
                AND manual_revocation_delivery_provider_id IS NULL
            )
            OR (
                manual_revocation_delivery_status IN (
                    'accepted',
                    'delivery_delayed'
                )
                AND manual_provider_revocation_required IS TRUE
                AND status = 'auth_pending'
                AND manual_revocation_delivery_resolved_at IS NULL
                AND manual_revocation_delivery_provider_id IS NOT NULL
            )
            OR (
                manual_revocation_delivery_status = 'retry_required'
                AND manual_provider_revocation_required IS TRUE
                AND status = 'auth_pending'
                AND manual_revocation_delivery_resolved_at IS NULL
                AND manual_revocation_delivery_provider_id IS NULL
            )
            OR (
                manual_revocation_delivery_status = 'delivered'
                AND manual_provider_revocation_required IS TRUE
                AND status IN ('auth_pending', 'completed')
                AND manual_revocation_delivery_resolved_at IS NOT NULL
                AND manual_revocation_delivery_provider_id IS NOT NULL
            )
            OR (
                manual_revocation_delivery_status = 'unverifiable'
                AND manual_provider_revocation_required IS TRUE
                AND status = 'completed'
                AND manual_revocation_delivery_resolved_at IS NULL
                AND manual_revocation_delivery_provider_id IS NULL
            )
            OR (
                manual_revocation_delivery_status = 'not_required'
                AND manual_provider_revocation_required IS FALSE
                AND manual_revocation_delivery_resolved_at IS NOT NULL
                AND manual_revocation_delivery_provider_id IS NULL
            )
        );

CREATE INDEX account_deletion_jobs_manual_delivery_pending_idx
    ON internal.account_deletion_jobs (next_attempt_at, requested_at, id)
    WHERE manual_revocation_delivery_status IN (
        'pending',
        'accepted',
        'delivery_delayed',
        'retry_required'
    )
      AND status IN ('pending', 'storage_pending', 'auth_pending');

PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage();

END;
$manual_revocation_delivery_schema$;

COMMENT ON TABLE internal.apple_manual_revocation_delivery_requirements IS
    'Private restrictive Auth fence for legacy Apple jobs until a matching signed Resend email.delivered event is committed.';

COMMENT ON TABLE internal.apple_manual_revocation_delivery_attempts IS
    'Private PII-free dispatch attempts for legacy Apple instructions. Provider acceptance is not delivery authority.';

COMMENT ON TABLE internal.apple_manual_revocation_delivery_events IS
    'Private bounded Resend event journal keyed by svix-id; stores no recipient, sender, subject, headers, or raw payload.';

ALTER TABLE internal.apple_manual_revocation_delivery_requirements
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.apple_manual_revocation_delivery_attempts
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.apple_manual_revocation_delivery_events
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.apple_manual_revocation_delivery_requirements
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE internal.apple_manual_revocation_delivery_attempts
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE internal.apple_manual_revocation_delivery_events
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_account_deletion_manual_revocation_recipient(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    recipient_email TEXT
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

    -- Compatibility fence for the prior worker during migration-first rollout.
    -- It must fail before dispatch because the old request has no opaque
    -- attempt tag and therefore cannot be authorized by a later webhook.
    -- RETURNS TABLE exposes recipient_email as an OUT variable. Assigning its
    -- fail-closed value keeps plpgsql_check warning-clean without making this
    -- compatibility routine capable of returning an address.
    recipient_email := NULL;

    RAISE EXCEPTION 'account_deletion_manual_delivery_upgrade_required'
        USING ERRCODE = '55000';
END;
$$;

COMMENT ON FUNCTION public.get_account_deletion_manual_revocation_recipient(UUID, UUID) IS
    'Fail-closed compatibility fence for workers that predate durable tagged delivery attempts.';

CREATE OR REPLACE FUNCTION public.complete_account_deletion_manual_revocation_delivery(
    p_job_id UUID,
    p_claim_token UUID,
    p_provider_delivery_id TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    provider_delivery_id TEXT := pg_catalog.BTRIM(p_provider_delivery_id);
BEGIN
    PERFORM internal.require_service_role();

    IF provider_delivery_id IS NULL
       OR pg_catalog.CHAR_LENGTH(provider_delivery_id) NOT BETWEEN 1 AND 255
       OR provider_delivery_id ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_id_invalid'
            USING ERRCODE = '22023';
    END IF;

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

    -- A send API response proves dispatch acceptance only. Keep the Auth fence
    -- and force the old worker onto its normal retry path until the tagged
    -- attempt-aware worker is deployed.
    RAISE EXCEPTION 'account_deletion_manual_delivery_confirmation_required'
        USING ERRCODE = '55000';
END;
$$;

COMMENT ON FUNCTION public.complete_account_deletion_manual_revocation_delivery(UUID, UUID, TEXT) IS
    'Fail-closed compatibility fence: transactional-email acceptance cannot complete legacy Apple delivery.';

CREATE OR REPLACE FUNCTION public.prepare_account_deletion_manual_revocation_delivery(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    recipient_email TEXT,
    attempt_token UUID,
    idempotency_key TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    delivery_attempt internal.apple_manual_revocation_delivery_attempts%ROWTYPE;
    delivery_email TEXT;
    new_attempt_token UUID;
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
       OR deletion_job.provider_revocation_status <> 'manual_required'
       OR deletion_job.manual_provider_revocation_required IS FALSE
       OR deletion_job.manual_revocation_delivery_status NOT IN (
           'pending',
           'retry_required'
       )
       OR deletion_job.manual_revocation_delivery_resolved_at IS NOT NULL
       OR deletion_job.manual_revocation_delivery_provider_id IS NOT NULL
       OR deletion_job.user_id IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM internal.apple_manual_revocation_delivery_requirements
               AS requirement
           WHERE requirement.user_id = deletion_job.user_id
             AND requirement.job_id = deletion_job.id
       ) THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    SELECT attempts.*
    INTO delivery_attempt
    FROM internal.apple_manual_revocation_delivery_attempts AS attempts
    WHERE attempts.job_id = deletion_job.id
      AND attempts.status IN (
          'prepared',
          'accepted',
          'delivery_delayed'
      )
    FOR UPDATE;

    IF FOUND THEN
        IF delivery_attempt.status <> 'prepared'
           OR deletion_job.manual_revocation_delivery_status <> 'pending' THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_attempt_busy'
                USING ERRCODE = '55000';
        END IF;
    ELSE
        new_attempt_token := pg_catalog.GEN_RANDOM_UUID();

        INSERT INTO internal.apple_manual_revocation_delivery_attempts AS attempts (
            attempt_token,
            job_id,
            idempotency_key
        )
        VALUES (
            new_attempt_token,
            deletion_job.id,
            'account-deletion-manual-apple/' || new_attempt_token::TEXT
        )
        RETURNING attempts.* INTO delivery_attempt;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'pending',
            manual_revocation_delivery_resolved_at = NULL,
            manual_revocation_delivery_provider_id = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    END IF;

    SELECT pg_catalog.BTRIM(auth_user.email)
    INTO delivery_email
    FROM auth.users AS auth_user
    WHERE auth_user.id = deletion_job.user_id
      AND auth_user.email_confirmed_at IS NOT NULL;

    IF delivery_email IS NULL
       OR pg_catalog.CHAR_LENGTH(delivery_email) NOT BETWEEN 3 AND 320
       OR delivery_email ~ '[[:cntrl:]]'
       OR delivery_email !~ '^[^[:space:]@]+@[^[:space:]@]+$' THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_email_missing'
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY SELECT
        delivery_email,
        delivery_attempt.attempt_token,
        delivery_attempt.idempotency_key;
END;
$$;

COMMENT ON FUNCTION public.prepare_account_deletion_manual_revocation_delivery(UUID, UUID) IS
    'Service-only claimed creation/read of one durable tagged Resend attempt and the confirmed Auth email, which is never stored in the attempt.';

CREATE OR REPLACE FUNCTION public.record_account_deletion_manual_revocation_acceptance(
    p_job_id UUID,
    p_claim_token UUID,
    p_attempt_token UUID,
    p_provider_delivery_id TEXT
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    delivery_attempt internal.apple_manual_revocation_delivery_attempts%ROWTYPE;
    normalized_provider_delivery_id TEXT := p_provider_delivery_id;
    terminal_event_type TEXT;
    removed_requirement_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF normalized_provider_delivery_id IS NULL
       OR pg_catalog.CHAR_LENGTH(normalized_provider_delivery_id)
           NOT BETWEEN 1 AND 255
       OR normalized_provider_delivery_id <>
           pg_catalog.BTRIM(normalized_provider_delivery_id)
       OR normalized_provider_delivery_id !~ '^[A-Za-z0-9_-]+$' THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_id_invalid'
            USING ERRCODE = '22023';
    END IF;

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

    SELECT attempts.*
    INTO delivery_attempt
    FROM internal.apple_manual_revocation_delivery_attempts AS attempts
    WHERE attempts.attempt_token = p_attempt_token
      AND attempts.job_id = deletion_job.id
    FOR UPDATE;

    IF NOT FOUND
       OR delivery_attempt.status <> 'prepared'
       OR deletion_job.status <> 'auth_pending'
       OR deletion_job.storage_completed_at IS NULL
       OR deletion_job.provider_revocation_status <> 'manual_required'
       OR deletion_job.manual_provider_revocation_required IS FALSE
       OR deletion_job.manual_revocation_delivery_status <> 'pending'
       OR deletion_job.manual_revocation_delivery_resolved_at IS NOT NULL
       OR deletion_job.manual_revocation_delivery_provider_id IS NOT NULL
       OR deletion_job.user_id IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM internal.apple_manual_revocation_delivery_requirements
               AS requirement
           WHERE requirement.user_id = deletion_job.user_id
             AND requirement.job_id = deletion_job.id
       ) THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_attempts AS other_attempt
        WHERE other_attempt.provider_delivery_id =
                normalized_provider_delivery_id
          AND other_attempt.attempt_token <> delivery_attempt.attempt_token
    ) THEN
        RAISE EXCEPTION 'manual_revocation_delivery_id_conflict'
            USING ERRCODE = '23505';
    END IF;

    BEGIN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'accepted',
            provider_delivery_id = normalized_provider_delivery_id,
            accepted_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'manual_revocation_delivery_id_conflict'
                USING ERRCODE = '23505';
    END;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_events AS event
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id = normalized_provider_delivery_id
          AND event.event_type = 'email.delivered'
    ) THEN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'delivered',
            last_event_type = 'email.delivered',
            delivered_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;

        DELETE FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id = deletion_job.user_id
          AND requirement.job_id = deletion_job.id;
        GET DIAGNOSTICS removed_requirement_count = ROW_COUNT;
        IF removed_requirement_count <> 1 THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_guard_missing'
                USING ERRCODE = '55000';
        END IF;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'delivered',
            manual_revocation_delivery_resolved_at = pg_catalog.NOW(),
            manual_revocation_delivery_provider_id =
                normalized_provider_delivery_id,
            next_attempt_at = pg_catalog.NOW(),
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;

        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = COALESCE(event.reduced_at, pg_catalog.NOW())
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id = normalized_provider_delivery_id;

        RETURN 'delivered';
    END IF;

    SELECT event.event_type
    INTO terminal_event_type
    FROM internal.apple_manual_revocation_delivery_events AS event
    WHERE event.attempt_token = delivery_attempt.attempt_token
      AND event.provider_delivery_id = normalized_provider_delivery_id
      AND event.event_type IN (
          'email.bounced',
          'email.failed',
          'email.suppressed'
      )
    ORDER BY event.provider_created_at, event.provider_event_id
    LIMIT 1;

    IF terminal_event_type IS NOT NULL THEN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'retry_required',
            last_event_type = terminal_event_type,
            terminal_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'retry_required',
            manual_revocation_delivery_resolved_at = NULL,
            manual_revocation_delivery_provider_id = NULL,
            next_attempt_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = pg_catalog.LEFT(
                pg_catalog.REPLACE(terminal_event_type, '.', '_'),
                120
            ),
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;

        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = COALESCE(event.reduced_at, pg_catalog.NOW())
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id = normalized_provider_delivery_id;

        RETURN 'retry_required';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_events AS event
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id = normalized_provider_delivery_id
          AND event.event_type = 'email.delivery_delayed'
    ) THEN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'delivery_delayed',
            last_event_type = 'email.delivery_delayed',
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'delivery_delayed',
            manual_revocation_delivery_resolved_at = NULL,
            manual_revocation_delivery_provider_id =
                normalized_provider_delivery_id,
            next_attempt_at = pg_catalog.NOW() + INTERVAL '1 hour',
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;

        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = COALESCE(event.reduced_at, pg_catalog.NOW())
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id = normalized_provider_delivery_id;

        RETURN 'delivery_pending';
    END IF;

    UPDATE internal.account_deletion_jobs AS jobs
    SET manual_revocation_delivery_status = 'accepted',
        manual_revocation_delivery_resolved_at = NULL,
        manual_revocation_delivery_provider_id =
            normalized_provider_delivery_id,
        next_attempt_at = pg_catalog.NOW() + INTERVAL '1 hour',
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id
      AND jobs.claim_token = p_claim_token;

    RETURN 'delivery_pending';
END;
$$;

COMMENT ON FUNCTION public.record_account_deletion_manual_revocation_acceptance(UUID, UUID, UUID, TEXT) IS
    'Service-only claimed binding of Resend send acceptance to a pre-created attempt; only an already-journaled matching delivery event can release Auth.';

CREATE OR REPLACE FUNCTION public.record_account_deletion_manual_revocation_event(
    p_attempt_token UUID,
    p_provider_event_id TEXT,
    p_provider_delivery_id TEXT,
    p_event_type TEXT,
    p_provider_created_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    delivery_job_id UUID;
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    delivery_attempt internal.apple_manual_revocation_delivery_attempts%ROWTYPE;
    existing_event internal.apple_manual_revocation_delivery_events%ROWTYPE;
    normalized_provider_event_id TEXT := p_provider_event_id;
    normalized_provider_delivery_id TEXT := p_provider_delivery_id;
    removed_requirement_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_attempt_token IS NULL
       OR p_attempt_token =
           '00000000-0000-0000-0000-000000000000'::UUID
       OR normalized_provider_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(normalized_provider_event_id)
           NOT BETWEEN 1 AND 255
       OR normalized_provider_event_id <>
           pg_catalog.BTRIM(normalized_provider_event_id)
       OR normalized_provider_event_id !~ '^[A-Za-z0-9_-]+$'
       OR normalized_provider_delivery_id IS NULL
       OR pg_catalog.CHAR_LENGTH(normalized_provider_delivery_id)
           NOT BETWEEN 1 AND 255
       OR normalized_provider_delivery_id <>
           pg_catalog.BTRIM(normalized_provider_delivery_id)
       OR normalized_provider_delivery_id !~ '^[A-Za-z0-9_-]+$'
       OR p_event_type NOT IN (
           'email.delivered',
           'email.delivery_delayed',
           'email.bounced',
           'email.failed',
           'email.suppressed'
       )
       OR p_provider_created_at IS NULL
       OR p_provider_created_at < TIMESTAMPTZ '2020-01-01 00:00:00+00'
       OR p_provider_created_at >
           pg_catalog.CLOCK_TIMESTAMP() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'manual_revocation_event_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT attempts.job_id
    INTO delivery_job_id
    FROM internal.apple_manual_revocation_delivery_attempts AS attempts
    WHERE attempts.attempt_token = p_attempt_token;

    IF NOT FOUND THEN
        RETURN 'ignored_unknown_attempt';
    END IF;

    -- All routines lock the account job before its attempt/event rows.
    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = delivery_job_id
    FOR UPDATE;

    SELECT attempts.*
    INTO delivery_attempt
    FROM internal.apple_manual_revocation_delivery_attempts AS attempts
    WHERE attempts.attempt_token = p_attempt_token
      AND attempts.job_id = deletion_job.id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'ignored_unknown_attempt';
    END IF;

    SELECT event.*
    INTO existing_event
    FROM internal.apple_manual_revocation_delivery_events AS event
    WHERE event.provider_event_id = normalized_provider_event_id
    FOR UPDATE;

    IF FOUND THEN
        IF existing_event.attempt_token IS DISTINCT FROM p_attempt_token
           OR existing_event.provider_delivery_id IS DISTINCT FROM
               normalized_provider_delivery_id
           OR existing_event.event_type IS DISTINCT FROM p_event_type
           OR existing_event.provider_created_at IS DISTINCT FROM
               p_provider_created_at THEN
            RAISE EXCEPTION 'manual_revocation_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;
        RETURN 'duplicate';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_attempts AS other_attempt
        WHERE other_attempt.provider_delivery_id =
                normalized_provider_delivery_id
          AND other_attempt.attempt_token <> delivery_attempt.attempt_token
    ) THEN
        RAISE EXCEPTION 'manual_revocation_delivery_id_conflict'
            USING ERRCODE = '23505';
    END IF;

    BEGIN
        INSERT INTO internal.apple_manual_revocation_delivery_events (
            provider_event_id,
            attempt_token,
            provider_delivery_id,
            event_type,
            provider_created_at
        ) VALUES (
            normalized_provider_event_id,
            delivery_attempt.attempt_token,
            normalized_provider_delivery_id,
            p_event_type,
            p_provider_created_at
        );
    EXCEPTION
        WHEN unique_violation THEN
            SELECT event.*
            INTO existing_event
            FROM internal.apple_manual_revocation_delivery_events AS event
            WHERE event.provider_event_id = normalized_provider_event_id
            FOR UPDATE;

            IF NOT FOUND
               OR existing_event.attempt_token IS DISTINCT FROM
                    p_attempt_token
               OR existing_event.provider_delivery_id IS DISTINCT FROM
                    normalized_provider_delivery_id
               OR existing_event.event_type IS DISTINCT FROM p_event_type
               OR existing_event.provider_created_at IS DISTINCT FROM
                    p_provider_created_at THEN
                RAISE EXCEPTION 'manual_revocation_event_id_conflict'
                    USING ERRCODE = '23505';
            END IF;
            RETURN 'duplicate';
    END;

    IF delivery_attempt.status NOT IN (
        'prepared',
        'accepted',
        'delivery_delayed'
    )
       OR deletion_job.status <> 'auth_pending'
       OR deletion_job.storage_completed_at IS NULL
       OR deletion_job.provider_revocation_status <> 'manual_required'
       OR deletion_job.manual_provider_revocation_required IS FALSE
       OR deletion_job.manual_revocation_delivery_status IN (
           'delivered',
           'unverifiable',
           'not_required'
       )
       OR deletion_job.user_id IS NULL THEN
        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = pg_catalog.NOW()
        WHERE event.provider_event_id = normalized_provider_event_id;
        RETURN 'ignored_stale_attempt';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id = deletion_job.user_id
          AND requirement.job_id = deletion_job.id
    ) THEN
        RAISE EXCEPTION 'account_deletion_manual_delivery_guard_missing'
            USING ERRCODE = '55000';
    END IF;

    -- A signed event may win the race with the send response. Journal it now,
    -- but do not reduce it until acceptance binds the same provider email ID.
    IF delivery_attempt.provider_delivery_id IS NULL THEN
        RETURN 'delivery_pending';
    END IF;

    IF delivery_attempt.provider_delivery_id <>
       normalized_provider_delivery_id THEN
        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = pg_catalog.NOW()
        WHERE event.provider_event_id = normalized_provider_event_id;
        RETURN 'ignored_stale_attempt';
    END IF;

    IF p_event_type = 'email.delivered' THEN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'delivered',
            last_event_type = p_event_type,
            delivered_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;

        DELETE FROM internal.apple_manual_revocation_delivery_requirements
            AS requirement
        WHERE requirement.user_id = deletion_job.user_id
          AND requirement.job_id = deletion_job.id;
        GET DIAGNOSTICS removed_requirement_count = ROW_COUNT;
        IF removed_requirement_count <> 1 THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_guard_missing'
                USING ERRCODE = '55000';
        END IF;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'delivered',
            manual_revocation_delivery_resolved_at = pg_catalog.NOW(),
            manual_revocation_delivery_provider_id =
                normalized_provider_delivery_id,
            next_attempt_at = pg_catalog.NOW(),
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id;

        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = COALESCE(event.reduced_at, pg_catalog.NOW())
        WHERE event.attempt_token = delivery_attempt.attempt_token
          AND event.provider_delivery_id =
                normalized_provider_delivery_id;

        RETURN 'delivered';
    END IF;

    IF p_event_type = 'email.delivery_delayed' THEN
        UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
        SET status = 'delivery_delayed',
            last_event_type = p_event_type,
            updated_at = pg_catalog.NOW()
        WHERE attempts.attempt_token = delivery_attempt.attempt_token;

        UPDATE internal.account_deletion_jobs AS jobs
        SET manual_revocation_delivery_status = 'delivery_delayed',
            manual_revocation_delivery_resolved_at = NULL,
            manual_revocation_delivery_provider_id =
                normalized_provider_delivery_id,
            next_attempt_at = pg_catalog.NOW() + INTERVAL '1 hour',
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id;

        UPDATE internal.apple_manual_revocation_delivery_events AS event
        SET reduced_at = pg_catalog.NOW()
        WHERE event.provider_event_id = normalized_provider_event_id;

        RETURN 'delivery_pending';
    END IF;

    UPDATE internal.apple_manual_revocation_delivery_attempts AS attempts
    SET status = 'retry_required',
        last_event_type = p_event_type,
        terminal_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE attempts.attempt_token = delivery_attempt.attempt_token;

    UPDATE internal.account_deletion_jobs AS jobs
    SET manual_revocation_delivery_status = 'retry_required',
        manual_revocation_delivery_resolved_at = NULL,
        manual_revocation_delivery_provider_id = NULL,
        next_attempt_at = pg_catalog.NOW(),
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = pg_catalog.LEFT(
            pg_catalog.REPLACE(p_event_type, '.', '_'),
            120
        ),
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id;

    UPDATE internal.apple_manual_revocation_delivery_events AS event
    SET reduced_at = pg_catalog.NOW()
    WHERE event.provider_event_id = normalized_provider_event_id;

    RETURN 'retry_required';
END;
$$;

COMMENT ON FUNCTION public.record_account_deletion_manual_revocation_event(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) IS
    'Service-only PII-free Resend event journal and reducer. Only a matching delivered event for the current bound attempt removes the Auth fence.';

CREATE OR REPLACE FUNCTION public.request_account_deletion(
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
    delivery_status TEXT;
    delivery_resolved_at TIMESTAMPTZ;
    requested_job_id UUID;
    requested_job_status TEXT;
    requested_manual_revocation_required BOOLEAN;
    requested_delivery_status TEXT;
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
        delivery_status := 'not_required';
        delivery_resolved_at := pg_catalog.NOW();
    ELSIF has_apple_identity THEN
        provider_status := 'manual_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := TRUE;
        delivery_status := 'pending';
        delivery_resolved_at := NULL;
    ELSE
        provider_status := 'not_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := FALSE;
        delivery_status := 'not_required';
        delivery_resolved_at := pg_catalog.NOW();
    END IF;

    INSERT INTO internal.account_deletion_jobs AS deletion_job (
        user_id,
        status,
        provider_revocation_status,
        provider_revocation_resolved_at,
        manual_provider_revocation_required,
        manual_revocation_delivery_status,
        manual_revocation_delivery_resolved_at,
        manual_revocation_delivery_provider_id,
        next_attempt_at
    )
    VALUES (
        p_user_id,
        'pending',
        provider_status,
        provider_resolved_at,
        manual_revocation_required,
        delivery_status,
        delivery_resolved_at,
        NULL,
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET updated_at = pg_catalog.NOW()
    RETURNING
        deletion_job.id,
        deletion_job.status,
        deletion_job.manual_provider_revocation_required,
        deletion_job.manual_revocation_delivery_status
    INTO
        requested_job_id,
        requested_job_status,
        requested_manual_revocation_required,
        requested_delivery_status;

    IF requested_manual_revocation_required
       AND requested_job_status IN (
           'pending',
           'storage_pending',
           'auth_pending'
       )
       AND requested_delivery_status IN (
           'pending',
           'accepted',
           'delivery_delayed',
           'retry_required'
       ) THEN
        INSERT INTO internal.apple_manual_revocation_delivery_requirements (
            user_id,
            job_id
        )
        VALUES (
            p_user_id,
            requested_job_id
        )
        ON CONFLICT (user_id) DO NOTHING;

        IF NOT EXISTS (
            SELECT 1
            FROM internal.apple_manual_revocation_delivery_requirements
                AS requirement
            WHERE requirement.user_id = p_user_id
              AND requirement.job_id = requested_job_id
        ) THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_guard_conflict'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    RETURN QUERY SELECT
        requested_job_id,
        requested_job_status,
        requested_manual_revocation_required;
END;
$$;

COMMENT ON FUNCTION public.request_account_deletion(UUID) IS
    'Service-only idempotent deletion intake. A legacy Apple disposition creates a mandatory server-delivery stage before Auth removal.';

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

        IF deletion_job.manual_revocation_delivery_status IN (
            'accepted',
            'delivery_delayed'
        ) THEN
            UPDATE internal.account_deletion_jobs AS jobs
            SET next_attempt_at = pg_catalog.NOW() + INTERVAL '1 hour',
                claim_token = NULL,
                claimed_at = NULL,
                claim_expires_at = NULL,
                last_error_code = NULL,
                updated_at = pg_catalog.NOW()
            WHERE jobs.id = deletion_job.id
              AND jobs.claim_token = p_claim_token;

            RETURN 'manual_revocation_delivery_waiting';
        END IF;

        IF deletion_job.manual_revocation_delivery_status IN (
            'pending',
            'retry_required'
        ) THEN
            RETURN 'manual_revocation_delivery_pending';
        END IF;

        IF deletion_job.manual_provider_revocation_required
           AND deletion_job.manual_revocation_delivery_status <> 'delivered'
        THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_invalid_state'
                USING ERRCODE = '55000';
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
    'Service-only claimed relational cleanup. Verified storage advances to automatic Apple revocation, legacy instruction delivery, or Auth removal.';

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

        IF deletion_job.manual_provider_revocation_required
           AND (
               deletion_job.manual_revocation_delivery_status <> 'delivered'
               OR deletion_job.manual_revocation_delivery_resolved_at IS NULL
               OR deletion_job.manual_revocation_delivery_provider_id IS NULL
               OR EXISTS (
                   SELECT 1
                   FROM internal.apple_manual_revocation_delivery_requirements
                       AS requirement
                   WHERE requirement.user_id = deletion_job.user_id
                     AND requirement.job_id = deletion_job.id
               )
               OR NOT EXISTS (
                   SELECT 1
                   FROM internal.apple_manual_revocation_delivery_attempts
                       AS attempt
                   WHERE attempt.job_id = deletion_job.id
                     AND attempt.status = 'delivered'
                     AND attempt.provider_delivery_id =
                        deletion_job.manual_revocation_delivery_provider_id
                     AND attempt.delivered_at IS NOT NULL
                     AND EXISTS (
                         SELECT 1
                         FROM internal.apple_manual_revocation_delivery_events
                             AS delivery_event
                         WHERE delivery_event.attempt_token =
                                attempt.attempt_token
                           AND delivery_event.provider_delivery_id =
                                attempt.provider_delivery_id
                           AND delivery_event.event_type = 'email.delivered'
                           AND delivery_event.reduced_at IS NOT NULL
                     )
               )
           ) THEN
            RAISE EXCEPTION 'account_deletion_manual_delivery_required'
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

-- Add delivery-specific aggregate state without exposing the recipient, user
-- identifier, provider delivery ID, or raw failure code.
DROP FUNCTION public.get_account_deletion_health();
CREATE FUNCTION public.get_account_deletion_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    active_job_count BIGINT,
    pending_cleanup_count BIGINT,
    storage_pending_count BIGINT,
    auth_pending_count BIGINT,
    manual_revocation_delivery_pending_count BIGINT,
    manual_revocation_delivery_accepted_count BIGINT,
    manual_revocation_delivery_delayed_count BIGINT,
    manual_revocation_delivery_retry_required_count BIGINT,
    manual_revocation_delivery_delivered_count BIGINT,
    manual_revocation_delivery_unverifiable_count BIGINT,
    due_job_count BIGINT,
    failed_job_count BIGINT,
    active_lease_count BIGINT,
    expired_lease_count BIGINT,
    oldest_pending_at TIMESTAMPTZ,
    oldest_pending_age_seconds BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT,
    storage_backlog_count BIGINT,
    storage_due_count BIGINT,
    storage_failed_job_count BIGINT,
    storage_active_lease_count BIGINT,
    storage_expired_lease_count BIGINT,
    verification_waiting_count BIGINT,
    orphaned_storage_job_count BIGINT,
    oldest_storage_pending_at TIMESTAMPTZ,
    oldest_storage_pending_age_seconds BIGINT,
    oldest_storage_due_at TIMESTAMPTZ,
    oldest_storage_due_age_seconds BIGINT,
    reaper_cron_active BOOLEAN,
    reaper_credentials_configured BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH health_clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    ),
    account_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) AS active_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'pending'
            ) AS pending_cleanup_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'storage_pending'
            ) AS storage_pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'auth_pending'
            ) AS auth_pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status IN (
                    'pending',
                    'accepted',
                    'delivery_delayed',
                    'retry_required'
                )
            ) AS manual_revocation_delivery_pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status IN (
                    'accepted',
                    'delivery_delayed'
                )
            ) AS manual_revocation_delivery_accepted_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status =
                    'delivery_delayed'
            ) AS manual_revocation_delivery_delayed_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status =
                    'retry_required'
            ) AS manual_revocation_delivery_retry_required_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.next_attempt_at <= clock.observed_at
                  AND (
                      deletion_job.claim_token IS NULL
                      OR deletion_job.claim_expires_at <= clock.observed_at
                  )
            ) AS due_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.last_error_code IS NOT NULL
            ) AS failed_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.claim_token IS NOT NULL
                  AND deletion_job.claim_expires_at > clock.observed_at
            ) AS active_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.claim_token IS NOT NULL
                  AND deletion_job.claim_expires_at <= clock.observed_at
            ) AS expired_lease_count,
            pg_catalog.MIN(deletion_job.requested_at) AS oldest_pending_at,
            pg_catalog.MIN(deletion_job.next_attempt_at) FILTER (
                WHERE deletion_job.next_attempt_at <= clock.observed_at
                  AND (
                      deletion_job.claim_token IS NULL
                      OR deletion_job.claim_expires_at <= clock.observed_at
                  )
            ) AS oldest_due_at
        FROM internal.account_deletion_jobs AS deletion_job
        CROSS JOIN health_clock AS clock
        WHERE deletion_job.status IN (
            'pending',
            'storage_pending',
            'auth_pending'
        )
    ),
    delivery_history AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status =
                    'delivered'
            ) AS delivered_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.manual_revocation_delivery_status =
                    'unverifiable'
            ) AS unverifiable_count
        FROM internal.account_deletion_jobs AS deletion_job
    ),
    storage_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) AS storage_backlog_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.next_attempt_at <= clock.observed_at
                  AND (
                      storage.claim_token IS NULL
                      OR storage.claim_expires_at <= clock.observed_at
                  )
            ) AS storage_due_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.last_error_code IS NOT NULL
            ) AS storage_failed_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.claim_token IS NOT NULL
                  AND storage.claim_expires_at > clock.observed_at
            ) AS storage_active_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.claim_token IS NOT NULL
                  AND storage.claim_expires_at <= clock.observed_at
            ) AS storage_expired_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.phase = 'verification'
                  AND storage.next_attempt_at > clock.observed_at
                  AND storage.claim_token IS NULL
            ) AS verification_waiting_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM internal.account_deletion_jobs AS deletion_job
                    WHERE deletion_job.user_id = storage.target_user_id
                      AND deletion_job.status = 'storage_pending'
                      AND deletion_job.cleanup_completed_at IS NOT NULL
                      AND deletion_job.storage_completed_at IS NULL
                )
            ) AS orphaned_storage_job_count,
            pg_catalog.MIN(storage.created_at) AS oldest_storage_pending_at,
            pg_catalog.MIN(storage.next_attempt_at) FILTER (
                WHERE storage.next_attempt_at <= clock.observed_at
                  AND (
                      storage.claim_token IS NULL
                      OR storage.claim_expires_at <= clock.observed_at
                  )
            ) AS oldest_storage_due_at
        FROM public.pending_storage_deletions AS storage
        CROSS JOIN health_clock AS clock
        WHERE storage.status IN ('pending', 'processing')
    ),
    scheduler_health AS MATERIALIZED (
        SELECT EXISTS (
            SELECT 1
            FROM cron.job AS scheduled_job
            WHERE scheduled_job.jobname =
                'reconcile_account_deletions_every_five_minutes'
              AND scheduled_job.active
        ) AS reaper_cron_active
    ),
    configuration_values AS MATERIALIZED (
        SELECT
            COALESCE(
                (
                    SELECT secret.decrypted_secret
                    FROM vault.decrypted_secrets AS secret
                    WHERE secret.name = 'SUPABASE_URL'
                    LIMIT 1
                ),
                pg_catalog.CURRENT_SETTING(
                    'app.settings.supabase_url',
                    TRUE
                )
            ) AS project_url,
            COALESCE(
                (
                    SELECT secret.decrypted_secret
                    FROM vault.decrypted_secrets AS secret
                    WHERE secret.name = 'SUPABASE_SERVICE_ROLE_KEY'
                    LIMIT 1
                ),
                pg_catalog.CURRENT_SETTING(
                    'app.settings.service_role_key',
                    TRUE
                )
            ) AS service_role_key
    ),
    configuration_health AS MATERIALIZED (
        SELECT
            NULLIF(
                pg_catalog.BTRIM(configuration.project_url),
                ''
            ) IS NOT NULL
            AND NULLIF(
                pg_catalog.BTRIM(configuration.service_role_key),
                ''
            ) IS NOT NULL AS reaper_credentials_configured
        FROM configuration_values AS configuration
    )
    SELECT
        clock.observed_at,
        accounts.active_job_count,
        accounts.pending_cleanup_count,
        accounts.storage_pending_count,
        accounts.auth_pending_count,
        accounts.manual_revocation_delivery_pending_count,
        accounts.manual_revocation_delivery_accepted_count,
        accounts.manual_revocation_delivery_delayed_count,
        accounts.manual_revocation_delivery_retry_required_count,
        delivery_history.delivered_count,
        delivery_history.unverifiable_count,
        accounts.due_job_count,
        accounts.failed_job_count,
        accounts.active_lease_count,
        accounts.expired_lease_count,
        accounts.oldest_pending_at,
        CASE
            WHEN accounts.oldest_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - accounts.oldest_pending_at
                    )
                )::BIGINT
            )
        END,
        accounts.oldest_due_at,
        CASE
            WHEN accounts.oldest_due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - accounts.oldest_due_at
                    )
                )::BIGINT
            )
        END,
        storage.storage_backlog_count,
        storage.storage_due_count,
        storage.storage_failed_job_count,
        storage.storage_active_lease_count,
        storage.storage_expired_lease_count,
        storage.verification_waiting_count,
        storage.orphaned_storage_job_count,
        storage.oldest_storage_pending_at,
        CASE
            WHEN storage.oldest_storage_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at -
                            storage.oldest_storage_pending_at
                    )
                )::BIGINT
            )
        END,
        storage.oldest_storage_due_at,
        CASE
            WHEN storage.oldest_storage_due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - storage.oldest_storage_due_at
                    )
                )::BIGINT
            )
        END,
        scheduler.reaper_cron_active,
        configuration.reaper_credentials_configured
    FROM health_clock AS clock
    CROSS JOIN account_health AS accounts
    CROSS JOIN delivery_history
    CROSS JOIN storage_health AS storage
    CROSS JOIN scheduler_health AS scheduler
    CROSS JOIN configuration_health AS configuration;
END;
$$;

COMMENT ON FUNCTION public.get_account_deletion_health() IS
    'Returns aggregate service-only account-erasure, manual Apple instruction delivery, lease, retry, scheduler, credential, and SLA health without user identifiers.';

REVOKE ALL ON FUNCTION public.get_account_deletion_manual_revocation_recipient(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_manual_revocation_delivery(UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.prepare_account_deletion_manual_revocation_delivery(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_account_deletion_manual_revocation_acceptance(UUID, UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_account_deletion_manual_revocation_event(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.request_account_deletion(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.finish_account_deletion_attempt(UUID, UUID, BOOLEAN, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_account_deletion_health()
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_account_deletion_manual_revocation_recipient(uuid,uuid)',
        'A migration-first compatibility fence rejects legacy workers that cannot emit a durable opaque delivery-attempt tag.'
    ),
    (
        'service_role',
        'public.complete_account_deletion_manual_revocation_delivery(uuid,uuid,text)',
        'A migration-first compatibility fence rejects send acceptance as proof of delivery.'
    ),
    (
        'service_role',
        'public.prepare_account_deletion_manual_revocation_delivery(uuid,uuid)',
        'A claim-fenced worker creates or resumes a PII-free tagged delivery attempt and transiently reads the confirmed Auth email.'
    ),
    (
        'service_role',
        'public.record_account_deletion_manual_revocation_acceptance(uuid,uuid,uuid,text)',
        'A claim-fenced worker binds provider send acceptance to its pre-created delivery attempt without releasing Auth.'
    ),
    (
        'service_role',
        'public.record_account_deletion_manual_revocation_event(uuid,text,text,text,timestamp with time zone)',
        'A signature-verifying webhook journals and reduces bounded provider events; only matching delivery confirmation releases Auth.'
    ),
    (
        'service_role',
        'public.get_account_deletion_health()',
        'Reads aggregate account-erasure and legacy Apple instruction-delivery health for independent production alerting.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

GRANT EXECUTE ON FUNCTION public.get_account_deletion_manual_revocation_recipient(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_manual_revocation_delivery(UUID, UUID, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion_manual_revocation_delivery(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.record_account_deletion_manual_revocation_acceptance(UUID, UUID, UUID, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.record_account_deletion_manual_revocation_event(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_account_deletion_attempt(UUID, UUID, BOOLEAN, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_health()
    TO service_role;

DO $manual_delivery_acl_audit$
DECLARE
    routine_signature TEXT;
    private_table TEXT;
    grantee_role TEXT;
    table_privilege TEXT;
BEGIN
    FOREACH routine_signature IN ARRAY ARRAY[
        'public.get_account_deletion_manual_revocation_recipient(uuid,uuid)',
        'public.complete_account_deletion_manual_revocation_delivery(uuid,uuid,text)',
        'public.prepare_account_deletion_manual_revocation_delivery(uuid,uuid)',
        'public.record_account_deletion_manual_revocation_acceptance(uuid,uuid,uuid,text)',
        'public.record_account_deletion_manual_revocation_event(uuid,text,text,text,timestamp with time zone)',
        'public.request_account_deletion(uuid)',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'public.get_account_deletion_health()'
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
            RAISE EXCEPTION 'manual_revocation_delivery_rpc_acl_invalid:%',
                routine_signature;
        END IF;
    END LOOP;

    FOREACH private_table IN ARRAY ARRAY[
        'internal.apple_manual_revocation_delivery_requirements',
        'internal.apple_manual_revocation_delivery_attempts',
        'internal.apple_manual_revocation_delivery_events'
    ] LOOP
        FOREACH grantee_role IN ARRAY ARRAY[
            'anon',
            'authenticated',
            'service_role'
        ] LOOP
            FOREACH table_privilege IN ARRAY ARRAY[
                'SELECT',
                'INSERT',
                'UPDATE',
                'DELETE',
                'TRUNCATE',
                'REFERENCES',
                'TRIGGER'
            ] LOOP
                IF pg_catalog.HAS_TABLE_PRIVILEGE(
                    grantee_role,
                    private_table,
                    table_privilege
                ) THEN
                    RAISE EXCEPTION
                        'manual_revocation_delivery_table_acl_invalid:%:%:%',
                        grantee_role,
                        private_table,
                        table_privilege;
                END IF;
            END LOOP;
        END LOOP;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_class AS relation
            JOIN pg_catalog.pg_namespace AS namespace
              ON namespace.oid = relation.relnamespace
            WHERE namespace.nspname = 'internal'
              AND relation.relname = pg_catalog.SPLIT_PART(
                  private_table,
                  '.',
                  2
              )
              AND relation.relrowsecurity
        ) THEN
            RAISE EXCEPTION
                'manual_revocation_delivery_table_rls_invalid:%',
                private_table;
        END IF;
    END LOOP;
END;
$manual_delivery_acl_audit$;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;

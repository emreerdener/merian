-- Separate the RevenueCat purchase customer from the disposable Supabase Auth
-- principal. Existing RevenueCat customers are adopted in place: their current
-- canonical custom ID becomes an immutable purchase-principal identifier, so
-- sign-out never needs a provider transfer and non-renewing purchases remain
-- available. New-device collisions receive an opaque server-generated ID and
-- require an explicit App Store restore.
--
-- Account-issued access is represented independently. RevenueCat promotional
-- state is imported into an account-owned grant row during adoption and kept
-- synchronized while legacy provider grants remain in use. The effective
-- public.users projection is recomputed from StoreKit state on every actively
-- bound purchase principal plus account-owned grants.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE internal.purchase_identity_rollout_config (
    config_key TEXT PRIMARY KEY DEFAULT 'current'
        CHECK (config_key = 'current'),
    principal_mode TEXT NOT NULL DEFAULT 'legacy'
        CHECK (principal_mode IN ('legacy', 'stable')),
    account_grant_mode TEXT NOT NULL DEFAULT 'dual_read'
        CHECK (account_grant_mode IN ('dual_read', 'authoritative')),
    minimum_client_protocol INTEGER NOT NULL DEFAULT 1
        CHECK (minimum_client_protocol BETWEEN 1 AND 1000),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP()
);

INSERT INTO internal.purchase_identity_rollout_config (
    config_key,
    principal_mode,
    account_grant_mode,
    minimum_client_protocol
)
VALUES ('current', 'legacy', 'dual_read', 1);

ALTER TABLE internal.purchase_identity_rollout_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_identity_rollout_config
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.purchase_identity_rollout_config IS
    'Owner-only rollout state for stable purchase principals. dual_read retains legacy account-grant comparison until migration evidence authorizes the authoritative cutover.';

CREATE TABLE internal.purchase_principals (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    revenuecat_app_user_id TEXT NOT NULL UNIQUE,
    capability_hash TEXT NOT NULL UNIQUE,
    latest_binding_intent_generation BIGINT NOT NULL DEFAULT 0
        CHECK (
            latest_binding_intent_generation BETWEEN 0 AND 9007199254740991
        ),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'revoked')),
    account_grant_owner_user_id UUID
        REFERENCES public.users(id) ON DELETE SET NULL,
    provider_account_grant_frozen BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    activated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_principals_app_user_id_check CHECK (
        pg_catalog.CHAR_LENGTH(revenuecat_app_user_id) BETWEEN 1 AND 255
        AND revenuecat_app_user_id !~ '[[:cntrl:]]'
        AND revenuecat_app_user_id !~ '^\$RCAnonymousID:'
    ),
    CONSTRAINT purchase_principals_capability_hash_check CHECK (
        capability_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT purchase_principals_lifecycle_check CHECK (
        (status = 'pending' AND activated_at IS NULL AND revoked_at IS NULL)
        OR (status = 'active' AND activated_at IS NOT NULL AND revoked_at IS NULL)
        OR (status = 'revoked' AND activated_at IS NOT NULL AND revoked_at IS NOT NULL)
    )
);

CREATE INDEX purchase_principals_grant_owner_idx
    ON internal.purchase_principals (account_grant_owner_user_id);

ALTER TABLE internal.purchase_principals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principals
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.purchase_principals IS
    'Server-issued RevenueCat purchase identities. The capability is stored only as SHA-256; the provider ID is immutable after creation and is never selected by a client.';

CREATE TABLE internal.purchase_principal_bindings (
    purchase_principal_id UUID PRIMARY KEY
        REFERENCES internal.purchase_principals(id) ON DELETE CASCADE,
    auth_user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    binding_generation BIGINT NOT NULL DEFAULT 1
        CHECK (binding_generation > 0),
    bound_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP()
);

CREATE INDEX purchase_principal_bindings_auth_user_idx
    ON internal.purchase_principal_bindings (auth_user_id, purchase_principal_id);

ALTER TABLE internal.purchase_principal_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principal_bindings
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.normalize_purchase_principal_binding()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
        NEW.binding_generation := GREATEST(
            NEW.binding_generation,
            OLD.binding_generation + 1
        );
        NEW.bound_at := pg_catalog.CLOCK_TIMESTAMP();
    END IF;
    NEW.updated_at := pg_catalog.CLOCK_TIMESTAMP();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.normalize_purchase_principal_binding()
    FROM PUBLIC, anon, authenticated, service_role;


CREATE TRIGGER normalize_purchase_principal_binding
BEFORE INSERT OR UPDATE ON internal.purchase_principal_bindings
FOR EACH ROW
EXECUTE FUNCTION internal.normalize_purchase_principal_binding();

CREATE TABLE internal.purchase_principal_binding_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_principal_id UUID NOT NULL
        REFERENCES internal.purchase_principals(id) ON DELETE CASCADE,
    previous_auth_user_id UUID,
    next_auth_user_id UUID,
    binding_generation BIGINT NOT NULL CHECK (binding_generation > 0),
    reason TEXT NOT NULL DEFAULT 'session_resolution'
        CHECK (reason ~ '^[a-z][a-z0-9_]{2,63}$'),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_principal_binding_history_transition_check CHECK (
        next_auth_user_id IS NULL
        OR previous_auth_user_id IS NULL
        OR previous_auth_user_id <> next_auth_user_id
    )
);

CREATE INDEX purchase_principal_binding_history_principal_idx
    ON internal.purchase_principal_binding_history (
        purchase_principal_id,
        binding_generation DESC
    );

CREATE INDEX purchase_principal_binding_history_previous_user_idx
    ON internal.purchase_principal_binding_history (previous_auth_user_id)
    WHERE previous_auth_user_id IS NOT NULL;

CREATE INDEX purchase_principal_binding_history_next_user_idx
    ON internal.purchase_principal_binding_history (next_auth_user_id)
    WHERE next_auth_user_id IS NOT NULL;

ALTER TABLE internal.purchase_principal_binding_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principal_binding_history
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.audit_purchase_principal_binding()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'INSERT'
       OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
        INSERT INTO internal.purchase_principal_binding_history (
            purchase_principal_id,
            previous_auth_user_id,
            next_auth_user_id,
            binding_generation
        )
        VALUES (
            NEW.purchase_principal_id,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.auth_user_id ELSE NULL END,
            NEW.auth_user_id,
            NEW.binding_generation
        );
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.audit_purchase_principal_binding()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER audit_purchase_principal_binding
AFTER INSERT OR UPDATE ON internal.purchase_principal_bindings
FOR EACH ROW
EXECUTE FUNCTION internal.audit_purchase_principal_binding();

CREATE TABLE internal.purchase_principal_store_state (
    purchase_principal_id UUID PRIMARY KEY
        REFERENCES internal.purchase_principals(id) ON DELETE CASCADE,
    target_tier public.subscription_tier_enum NOT NULL,
    target_expires_at TIMESTAMPTZ,
    allow_non_subscription_pass_grant BOOLEAN NOT NULL DEFAULT FALSE,
    authoritative_snapshot_at_ms BIGINT NOT NULL,
    last_event_id TEXT,
    last_event_timestamp_ms BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_principal_store_state_expiry_check CHECK (
        (target_tier = 'free'::public.subscription_tier_enum
            AND target_expires_at IS NULL)
        OR target_tier = 'pro'::public.subscription_tier_enum
    ),
    CONSTRAINT purchase_principal_store_state_snapshot_check CHECK (
        authoritative_snapshot_at_ms BETWEEN 0 AND 253402300799999
        AND last_event_timestamp_ms BETWEEN 0 AND 253402300799999
    ),
    CONSTRAINT purchase_principal_store_state_event_check CHECK (
        last_event_id IS NULL
        OR (
            pg_catalog.CHAR_LENGTH(last_event_id) BETWEEN 1 AND 255
            AND last_event_id !~ '[[:cntrl:]]'
        )
    )
);

ALTER TABLE internal.purchase_principal_store_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principal_store_state
    FROM PUBLIC, anon, authenticated, service_role;

-- During the compatibility window a user can have both an old UUID customer
-- and one or more stable purchase principals. Preserve the legacy provider
-- projection as an input instead of allowing either lane to overwrite the
-- effective public.users row directly.
CREATE TABLE internal.legacy_revenuecat_entitlement_state (
    merian_user_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE,
    target_tier public.subscription_tier_enum NOT NULL,
    target_expires_at TIMESTAMPTZ,
    authoritative_snapshot_at_ms BIGINT NOT NULL,
    last_event_id TEXT,
    last_event_timestamp_ms BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT legacy_revenuecat_entitlement_expiry_check CHECK (
        (target_tier = 'free'::public.subscription_tier_enum
            AND target_expires_at IS NULL)
        OR target_tier = 'pro'::public.subscription_tier_enum
    ),
    CONSTRAINT legacy_revenuecat_entitlement_snapshot_check CHECK (
        authoritative_snapshot_at_ms BETWEEN 0 AND 253402300799999
        AND last_event_timestamp_ms BETWEEN 0 AND 253402300799999
    )
);

ALTER TABLE internal.legacy_revenuecat_entitlement_state
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.legacy_revenuecat_entitlement_state
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.legacy_revenuecat_entitlement_state (
    merian_user_id,
    target_tier,
    target_expires_at,
    authoritative_snapshot_at_ms,
    last_event_id,
    last_event_timestamp_ms
)
SELECT
    users.id,
    users.subscription_tier,
    users.subscription_expires_at,
    COALESCE(states.last_authoritative_snapshot_at_ms, 0),
    states.last_event_id,
    COALESCE(states.last_event_timestamp_ms, 0)
FROM public.users AS users
LEFT JOIN internal.revenuecat_customer_state AS states
  ON states.merian_user_id = users.id
WHERE states.merian_user_id IS NOT NULL
   OR users.subscription_tier = 'pro'::public.subscription_tier_enum;

CREATE TABLE internal.account_access_grants (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    account_user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    grant_kind TEXT NOT NULL
        CHECK (grant_kind IN ('beta', 'promotion', 'support')),
    grant_tier public.subscription_tier_enum NOT NULL DEFAULT 'pro'
        CHECK (grant_tier = 'pro'::public.subscription_tier_enum),
    starts_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    source_kind TEXT NOT NULL
        CHECK (source_kind IN ('revenuecat_legacy', 'operator', 'migration')),
    source_reference_hash TEXT NOT NULL,
    source_snapshot_at_ms BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT account_access_grants_source_unique UNIQUE (
        source_kind,
        source_reference_hash
    ),
    CONSTRAINT account_access_grants_source_hash_check CHECK (
        source_reference_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT account_access_grants_time_check CHECK (
        expires_at IS NULL OR expires_at > starts_at
    ),
    CONSTRAINT account_access_grants_revocation_check CHECK (
        revoked_at IS NULL OR revoked_at >= starts_at
    ),
    CONSTRAINT account_access_grants_snapshot_check CHECK (
        source_snapshot_at_ms IS NULL
        OR source_snapshot_at_ms BETWEEN 0 AND 253402300799999
    )
);

CREATE INDEX account_access_grants_active_account_idx
    ON internal.account_access_grants (account_user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE INDEX account_access_grants_account_user_idx
    ON internal.account_access_grants (account_user_id);

ALTER TABLE internal.account_access_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.account_access_grants
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.account_access_grant_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grant_id UUID NOT NULL
        REFERENCES internal.account_access_grants(id) ON DELETE CASCADE,
    account_user_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('created', 'updated', 'revoked')),
    expires_at TIMESTAMPTZ,
    source_snapshot_at_ms BIGINT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP()
);

CREATE INDEX account_access_grant_audit_grant_idx
    ON internal.account_access_grant_audit (grant_id, id DESC);

ALTER TABLE internal.account_access_grant_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.account_access_grant_audit
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.purchase_principal_reconciliation_queue (
    purchase_principal_id UUID PRIMARY KEY
        REFERENCES internal.purchase_principals(id) ON DELETE CASCADE,
    lookup_app_user_id TEXT NOT NULL,
    next_reconcile_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    claim_token UUID,
    claimed_at TIMESTAMPTZ,
    claim_expires_at TIMESTAMPTZ,
    last_snapshot_at_ms BIGINT,
    last_reconciled_at TIMESTAMPTZ,
    last_error_code TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_principal_reconciliation_lookup_check CHECK (
        pg_catalog.CHAR_LENGTH(lookup_app_user_id) BETWEEN 1 AND 255
        AND lookup_app_user_id !~ '[[:cntrl:]]'
    ),
    CONSTRAINT purchase_principal_reconciliation_claim_check CHECK (
        (claim_token IS NULL AND claimed_at IS NULL AND claim_expires_at IS NULL)
        OR (claim_token IS NOT NULL AND claimed_at IS NOT NULL
            AND claim_expires_at > claimed_at)
    ),
    CONSTRAINT purchase_principal_reconciliation_snapshot_check CHECK (
        last_snapshot_at_ms IS NULL
        OR last_snapshot_at_ms BETWEEN 0 AND 253402300799999
    ),
    CONSTRAINT purchase_principal_reconciliation_error_check CHECK (
        last_error_code IS NULL
        OR pg_catalog.CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
    )
);

CREATE INDEX purchase_principal_reconciliation_due_idx
    ON internal.purchase_principal_reconciliation_queue (
        next_reconcile_at,
        purchase_principal_id
    )
    WHERE claim_token IS NULL;

CREATE INDEX purchase_principal_reconciliation_expired_claim_idx
    ON internal.purchase_principal_reconciliation_queue (
        claim_expires_at,
        purchase_principal_id
    )
    WHERE claim_token IS NOT NULL;

ALTER TABLE internal.purchase_principal_reconciliation_queue
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principal_reconciliation_queue
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.purchase_principal_webhook_event_subjects (
    event_id TEXT NOT NULL
        REFERENCES internal.revenuecat_webhook_events(event_id)
        ON DELETE CASCADE,
    purchase_principal_id UUID NOT NULL
        REFERENCES internal.purchase_principals(id) ON DELETE CASCADE,
    subject_kind TEXT NOT NULL CHECK (
        subject_kind IN ('customer', 'transfer_source', 'transfer_destination')
    ),
    authoritative_snapshot_at_ms BIGINT NOT NULL,
    target_store_tier public.subscription_tier_enum NOT NULL,
    target_store_expires_at TIMESTAMPTZ,
    allow_non_subscription_pass_grant BOOLEAN,
    target_account_grant_tier public.subscription_tier_enum NOT NULL,
    target_account_grant_expires_at TIMESTAMPTZ,
    account_grant_update_applied BOOLEAN NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('applied', 'stale')),
    projected_auth_user_id UUID,
    entitlement_version BIGINT,
    PRIMARY KEY (event_id, purchase_principal_id),
    UNIQUE (event_id, subject_kind),
    CONSTRAINT purchase_principal_webhook_snapshot_check CHECK (
        authoritative_snapshot_at_ms BETWEEN 0 AND 253402300799999
    ),
    CONSTRAINT purchase_principal_webhook_store_expiry_check CHECK (
        (target_store_tier = 'free'::public.subscription_tier_enum
            AND target_store_expires_at IS NULL)
        OR target_store_tier = 'pro'::public.subscription_tier_enum
    ),
    CONSTRAINT purchase_principal_webhook_grant_expiry_check CHECK (
        (target_account_grant_tier = 'free'::public.subscription_tier_enum
            AND target_account_grant_expires_at IS NULL)
        OR target_account_grant_tier = 'pro'::public.subscription_tier_enum
    )
);

CREATE INDEX purchase_principal_webhook_subject_principal_idx
    ON internal.purchase_principal_webhook_event_subjects (
        purchase_principal_id,
        authoritative_snapshot_at_ms DESC
    );

CREATE INDEX purchase_principal_webhook_subject_projected_user_idx
    ON internal.purchase_principal_webhook_event_subjects (
        projected_auth_user_id
    )
    WHERE projected_auth_user_id IS NOT NULL;

ALTER TABLE internal.purchase_principal_webhook_event_subjects
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_principal_webhook_event_subjects
    FROM PUBLIC, anon, authenticated, service_role;

-- Provider/customer history is operational evidence, not a reason to retain a
-- deleted Merian account identifier. These fields intentionally have no user
-- foreign key because an anonymous-to-account merge may otherwise collapse a
-- transition onto one UUID. Scrub both private evidence surfaces immediately
-- before the profile row is deleted instead.
CREATE OR REPLACE FUNCTION internal.scrub_purchase_identity_auth_references()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    -- A deleted account's provider promotion must never become claimable by a
    -- later account merely because ON DELETE clears the recorded owner. The
    -- StoreKit principal survives; only temporary provider-grant import is
    -- permanently fenced.
    UPDATE internal.purchase_principals AS principal
    SET provider_account_grant_frozen = TRUE,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE principal.account_grant_owner_user_id = OLD.id;

    UPDATE internal.purchase_principal_binding_history AS history
    SET previous_auth_user_id = CASE
            WHEN history.previous_auth_user_id = OLD.id THEN NULL
            ELSE history.previous_auth_user_id
        END,
        next_auth_user_id = CASE
            WHEN history.next_auth_user_id = OLD.id THEN NULL
            ELSE history.next_auth_user_id
        END
    WHERE history.previous_auth_user_id = OLD.id
       OR history.next_auth_user_id = OLD.id;

    UPDATE internal.purchase_principal_webhook_event_subjects AS subject
    SET projected_auth_user_id = NULL
    WHERE subject.projected_auth_user_id = OLD.id;

    RETURN OLD;
END;
$function$;

REVOKE ALL ON FUNCTION internal.scrub_purchase_identity_auth_references()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER scrub_purchase_identity_auth_references
BEFORE DELETE ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.scrub_purchase_identity_auth_references();

CREATE OR REPLACE FUNCTION internal.lock_purchase_principals_for_auth_users(
    p_user_ids UUID[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    IF p_user_ids IS NULL
       OR pg_catalog.ARRAY_NDIMS(p_user_ids) <> 1
       OR pg_catalog.CARDINALITY(p_user_ids) = 0
       OR EXISTS (
           SELECT 1
           FROM pg_catalog.UNNEST(p_user_ids) AS requested(user_id)
           WHERE requested.user_id IS NULL
       ) THEN
        RAISE EXCEPTION 'purchase_principal_invalid_auth_transition'
            USING ERRCODE = '22023';
    END IF;

    -- Webhooks, reconciliation, resolver completion, account deletion, and
    -- profile merge all acquire related purchase principals before Auth/public
    -- user rows. Include fixed grant owners and active bindings on either side
    -- so two different principals cannot deadlock through one shared account.
    PERFORM principal.id
    FROM internal.purchase_principals AS principal
    LEFT JOIN internal.purchase_principal_bindings AS binding
      ON binding.purchase_principal_id = principal.id
    WHERE principal.account_grant_owner_user_id = ANY(p_user_ids)
       OR binding.auth_user_id = ANY(p_user_ids)
    ORDER BY principal.id
    FOR UPDATE OF principal;
END;
$function$;

REVOKE ALL ON FUNCTION
    internal.lock_purchase_principals_for_auth_users(UUID[])
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
internal.prepare_purchase_principals_for_account_deletion(
    p_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.lock_purchase_principals_for_auth_users(
        ARRAY[p_user_id]::UUID[]
    );

    UPDATE internal.purchase_principals AS principal
    SET account_grant_owner_user_id = NULL,
        provider_account_grant_frozen = TRUE,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE principal.account_grant_owner_user_id = p_user_id;

    DELETE FROM internal.purchase_principal_bindings AS binding
    WHERE binding.auth_user_id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION
    internal.prepare_purchase_principals_for_account_deletion(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

DO $extend_account_deletion$
DECLARE
    function_definition TEXT;
    anchor TEXT :=
        '    PERFORM public.apply_user_tombstone(deletion_job.user_id);';
    replacement TEXT :=
        '    PERFORM internal.prepare_purchase_principals_for_account_deletion('
        || pg_catalog.CHR(10)
        || '        deletion_job.user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || anchor;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.complete_account_deletion_cleanup(uuid,uuid)'::REGPROCEDURE
    ) INTO STRICT function_definition;
    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_definition, anchor, '')
        )
    ) / pg_catalog.LENGTH(anchor) <> 1
       OR pg_catalog.STRPOS(
           function_definition,
           'prepare_purchase_principals_for_account_deletion('
       ) <> 0 THEN
        RAISE EXCEPTION 'account_deletion_purchase_principal_source_drift'
            USING ERRCODE = '55000';
    END IF;
    EXECUTE pg_catalog.REPLACE(
        function_definition,
        anchor,
        replacement
    );
END;
$extend_account_deletion$;

CREATE OR REPLACE FUNCTION internal.recompute_purchase_principal_entitlement(
    p_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    has_lifetime_access BOOLEAN;
    latest_expiry TIMESTAMPTZ;
    resolved_tier public.subscription_tier_enum;
    resolved_expiry TIMESTAMPTZ;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN;
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT
        pg_catalog.BOOL_OR(access.expires_at IS NULL),
        pg_catalog.MAX(access.expires_at)
    INTO has_lifetime_access, latest_expiry
    FROM (
        SELECT legacy.target_expires_at AS expires_at
        FROM internal.legacy_revenuecat_entitlement_state AS legacy
        WHERE legacy.merian_user_id = p_user_id
          AND legacy.target_tier = 'pro'::public.subscription_tier_enum
          AND (
              legacy.target_expires_at IS NULL
              OR legacy.target_expires_at > pg_catalog.NOW()
          )
        UNION ALL
        SELECT state.target_expires_at AS expires_at
        FROM internal.purchase_principal_bindings AS binding
        JOIN internal.purchase_principal_store_state AS state
          ON state.purchase_principal_id = binding.purchase_principal_id
        WHERE binding.auth_user_id = p_user_id
          AND state.target_tier = 'pro'::public.subscription_tier_enum
          AND (
              state.target_expires_at IS NULL
              OR state.target_expires_at > pg_catalog.NOW()
          )
        UNION ALL
        SELECT grant_row.expires_at
        FROM internal.account_access_grants AS grant_row
        WHERE grant_row.account_user_id = p_user_id
          AND grant_row.grant_tier = 'pro'::public.subscription_tier_enum
          AND grant_row.starts_at <= pg_catalog.NOW()
          AND grant_row.revoked_at IS NULL
          AND (
              grant_row.expires_at IS NULL
              OR grant_row.expires_at > pg_catalog.NOW()
          )
    ) AS access;

    IF COALESCE(has_lifetime_access, FALSE) THEN
        resolved_tier := 'pro'::public.subscription_tier_enum;
        resolved_expiry := NULL;
    ELSIF latest_expiry IS NOT NULL THEN
        resolved_tier := 'pro'::public.subscription_tier_enum;
        resolved_expiry := latest_expiry;
    ELSE
        resolved_tier := 'free'::public.subscription_tier_enum;
        resolved_expiry := NULL;
    END IF;

    UPDATE public.users AS users
    SET subscription_tier = resolved_tier,
        subscription_expires_at = resolved_expiry
    WHERE users.id = p_user_id
      AND (
          users.subscription_tier IS DISTINCT FROM resolved_tier
          OR users.subscription_expires_at IS DISTINCT FROM resolved_expiry
      );
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_expired_entitlement_projection(
    p_user_id UUID,
    p_boundary TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    previous_tier public.subscription_tier_enum;
    previous_expiry TIMESTAMPTZ;
    refreshed_tier public.subscription_tier_enum;
    refreshed_expiry TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL OR p_boundary IS NULL
       OR p_boundary > pg_catalog.NOW() + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'invalid_entitlement_expiry_refresh'
            USING ERRCODE = '22023';
    END IF;

    SELECT users.subscription_tier, users.subscription_expires_at
    INTO STRICT previous_tier, previous_expiry
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF previous_expiry IS NULL OR previous_expiry > p_boundary THEN
        RETURN FALSE;
    END IF;

    PERFORM internal.recompute_purchase_principal_entitlement(p_user_id);
    SELECT users.subscription_tier, users.subscription_expires_at
    INTO STRICT refreshed_tier, refreshed_expiry
    FROM public.users AS users
    WHERE users.id = p_user_id;
    RETURN previous_tier IS DISTINCT FROM refreshed_tier
        OR previous_expiry IS DISTINCT FROM refreshed_expiry;
END;
$function$;

REVOKE ALL ON FUNCTION
    internal.recompute_purchase_principal_entitlement(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.audit_account_access_grant()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    INSERT INTO internal.account_access_grant_audit (
        grant_id,
        account_user_id,
        action,
        expires_at,
        source_snapshot_at_ms
    )
    VALUES (
        NEW.id,
        NEW.account_user_id,
        CASE
            WHEN TG_OP = 'INSERT' THEN 'created'
            WHEN NEW.revoked_at IS NOT NULL
              AND OLD.revoked_at IS NULL THEN 'revoked'
            ELSE 'updated'
        END,
        NEW.expires_at,
        NEW.source_snapshot_at_ms
    );

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.audit_account_access_grant()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER audit_account_access_grant
AFTER INSERT OR UPDATE ON internal.account_access_grants
FOR EACH ROW
EXECUTE FUNCTION internal.audit_account_access_grant();

CREATE OR REPLACE FUNCTION internal.refresh_purchase_projection_from_binding()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            OLD.auth_user_id
        );
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE')
       AND (TG_OP = 'INSERT' OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id)
    THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            NEW.auth_user_id
        );
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_binding()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER refresh_purchase_projection_from_binding
AFTER INSERT OR UPDATE OR DELETE ON internal.purchase_principal_bindings
FOR EACH ROW
EXECUTE FUNCTION internal.refresh_purchase_projection_from_binding();

CREATE OR REPLACE FUNCTION internal.refresh_purchase_projection_from_state()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    principal_id UUID;
    bound_user_id UUID;
BEGIN
    principal_id := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.purchase_principal_id
        ELSE NEW.purchase_principal_id
    END;
    SELECT binding.auth_user_id
    INTO bound_user_id
    FROM internal.purchase_principal_bindings AS binding
    WHERE binding.purchase_principal_id = principal_id;
    PERFORM internal.recompute_purchase_principal_entitlement(bound_user_id);
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_state()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER refresh_purchase_projection_from_state
AFTER INSERT OR UPDATE OR DELETE ON internal.purchase_principal_store_state
FOR EACH ROW
EXECUTE FUNCTION internal.refresh_purchase_projection_from_state();

CREATE OR REPLACE FUNCTION internal.refresh_purchase_projection_from_grant()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            OLD.account_user_id
        );
        RETURN OLD;
    ELSIF TG_OP = 'INSERT' THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            NEW.account_user_id
        );
        RETURN NEW;
    END IF;

    PERFORM internal.recompute_purchase_principal_entitlement(
        OLD.account_user_id
    );
    IF NEW.account_user_id IS DISTINCT FROM OLD.account_user_id THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            NEW.account_user_id
        );
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_grant()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER refresh_purchase_projection_from_grant
AFTER INSERT OR UPDATE OR DELETE ON internal.account_access_grants
FOR EACH ROW
EXECUTE FUNCTION internal.refresh_purchase_projection_from_grant();

CREATE OR REPLACE FUNCTION public.begin_purchase_principal_resolution(
    p_auth_user_id UUID,
    p_capability_hash TEXT,
    p_client_protocol INTEGER,
    p_binding_intent_generation BIGINT
)
RETURNS TABLE (
    resolution_mode TEXT,
    purchase_principal_id UUID,
    revenuecat_app_user_id TEXT,
    minimum_client_protocol INTEGER,
    requires_attestation BOOLEAN,
    binding_intent_generation BIGINT,
    allow_non_subscription_pass_grant BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    principal internal.purchase_principals%ROWTYPE;
    proposed_app_user_id TEXT;
    existing_pass_grant_policy BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_user_id IS NULL
       OR p_capability_hash IS NULL
       OR p_capability_hash !~ '^[0-9a-f]{64}$'
       OR p_client_protocol IS NULL
       OR p_client_protocol NOT BETWEEN 1 AND 1000
       OR p_binding_intent_generation IS NULL
       OR p_binding_intent_generation NOT BETWEEN 1 AND 9007199254740991 THEN
        RAISE EXCEPTION 'purchase_principal_invalid_resolution'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-capability:' || p_capability_hash,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO principal
    FROM internal.purchase_principals AS principals
    WHERE principals.capability_hash = p_capability_hash
    FOR UPDATE;

    IF FOUND THEN
        IF principal.status = 'revoked' THEN
            RAISE EXCEPTION 'purchase_principal_capability_revoked'
                USING ERRCODE = '42501';
        END IF;

        -- Rollback disables new adoption; it must never rotate an already
        -- activated installation back to an Auth-UUID customer. Existing
        -- principals therefore remain resolvable and rebindable while the
        -- global mode is legacy.
        IF principal.status = 'active'
           AND p_client_protocol < rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_principal_client_upgrade_required'
                USING ERRCODE = '22023';
        END IF;

        IF principal.status <> 'active'
           AND (
               rollout.principal_mode = 'legacy'
               OR p_client_protocol < rollout.minimum_client_protocol
           ) THEN
            RETURN QUERY SELECT
                'legacy'::TEXT,
                NULL::UUID,
                NULL::TEXT,
                rollout.minimum_client_protocol,
                FALSE,
                NULL::BIGINT,
                NULL::BOOLEAN;
            RETURN;
        END IF;

        IF p_binding_intent_generation <=
                principal.latest_binding_intent_generation THEN
            RAISE EXCEPTION 'purchase_principal_binding_intent_stale'
                USING ERRCODE = '40001';
        END IF;
        UPDATE internal.purchase_principals AS principals
        SET latest_binding_intent_generation = p_binding_intent_generation,
            updated_at = pg_catalog.CLOCK_TIMESTAMP()
        WHERE principals.id = principal.id;
        principal.latest_binding_intent_generation :=
            p_binding_intent_generation;

        -- Resolution and completion use the same principal -> auth-user lock
        -- order. The inverse order would let completion hold the principal
        -- while a resolver held the user row, deadlocking both transactions.
        PERFORM auth_user.id
        FROM auth.users AS auth_user
        JOIN public.users AS profile ON profile.id = auth_user.id
        WHERE auth_user.id = p_auth_user_id
        FOR UPDATE OF auth_user, profile;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'purchase_principal_user_not_available'
                USING ERRCODE = 'P0002';
        END IF;
        IF EXISTS (
            SELECT 1
            FROM internal.account_deletion_jobs AS deletion_job
            WHERE deletion_job.user_id = p_auth_user_id
              AND deletion_job.status IN (
                  'pending',
                  'storage_pending',
                  'auth_pending'
              )
        ) THEN
            RAISE EXCEPTION 'purchase_principal_account_deletion_in_progress'
                USING ERRCODE = 'P0002';
        END IF;
    ELSE
        IF rollout.principal_mode = 'legacy'
           OR p_client_protocol < rollout.minimum_client_protocol THEN
            RETURN QUERY SELECT
                'legacy'::TEXT,
                NULL::UUID,
                NULL::TEXT,
                rollout.minimum_client_protocol,
                FALSE,
                NULL::BIGINT,
                NULL::BOOLEAN;
            RETURN;
        END IF;

        -- Different capabilities can be presented concurrently by one auth
        -- session. Serialize only the new-principal branch before inspecting
        -- abandoned preparations; no user row is held while waiting for a
        -- principal row that completion may already own.
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED(
                'purchase-principal-auth-user:' || p_auth_user_id::TEXT,
                0::BIGINT
            )
        );

        -- An abandoned prepare has never configured or mutated RevenueCat and
        -- can be removed after a bounded retry window. This prevents a lost
        -- device capability from consuming the legacy-ID adoption slot forever.
        DELETE FROM internal.purchase_principals AS abandoned
        WHERE abandoned.status = 'pending'
          AND abandoned.account_grant_owner_user_id = p_auth_user_id
          AND abandoned.updated_at < pg_catalog.NOW() - INTERVAL '30 minutes'
          AND NOT EXISTS (
              SELECT 1
              FROM internal.purchase_principal_bindings AS binding
              WHERE binding.purchase_principal_id = abandoned.id
          );

        PERFORM auth_user.id
        FROM auth.users AS auth_user
        JOIN public.users AS profile ON profile.id = auth_user.id
        WHERE auth_user.id = p_auth_user_id
        FOR UPDATE OF auth_user, profile;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'purchase_principal_user_not_available'
                USING ERRCODE = 'P0002';
        END IF;
        IF EXISTS (
            SELECT 1
            FROM internal.account_deletion_jobs AS deletion_job
            WHERE deletion_job.user_id = p_auth_user_id
              AND deletion_job.status IN (
                  'pending',
                  'storage_pending',
                  'auth_pending'
              )
        ) THEN
            RAISE EXCEPTION 'purchase_principal_account_deletion_in_progress'
                USING ERRCODE = 'P0002';
        END IF;

        proposed_app_user_id := pg_catalog.UPPER(p_auth_user_id::TEXT);
        IF EXISTS (
            SELECT 1
            FROM internal.purchase_principals AS existing
            WHERE existing.revenuecat_app_user_id = proposed_app_user_id
        ) THEN
            proposed_app_user_id := 'MERIAN_PP_' || pg_catalog.REPLACE(
                pg_catalog.UPPER(extensions.gen_random_uuid()::TEXT),
                '-',
                ''
            );
        END IF;

        INSERT INTO internal.purchase_principals (
            revenuecat_app_user_id,
            capability_hash,
            account_grant_owner_user_id,
            latest_binding_intent_generation
        )
        VALUES (
            proposed_app_user_id,
            p_capability_hash,
            p_auth_user_id,
            p_binding_intent_generation
        )
        RETURNING * INTO principal;
    END IF;

    IF principal.status = 'active' THEN
        SELECT state.allow_non_subscription_pass_grant
        INTO existing_pass_grant_policy
        FROM internal.purchase_principal_store_state AS state
        WHERE state.purchase_principal_id = principal.id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'purchase_principal_invalid_resolution'
                USING ERRCODE = '55000';
        END IF;
    ELSE
        existing_pass_grant_policy := NULL;
    END IF;

    RETURN QUERY SELECT
        'stable'::TEXT,
        principal.id,
        principal.revenuecat_app_user_id,
        rollout.minimum_client_protocol,
        TRUE,
        p_binding_intent_generation,
        existing_pass_grant_policy;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_purchase_principal_resolution(
    p_auth_user_id UUID,
    p_purchase_principal_id UUID,
    p_capability_hash TEXT,
    p_binding_intent_generation BIGINT,
    p_authoritative_snapshot_at_ms BIGINT,
    p_store_tier TEXT,
    p_store_expires_at TIMESTAMPTZ,
    p_allow_non_subscription_pass_grant BOOLEAN,
    p_account_grant_tier TEXT,
    p_account_grant_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    purchase_principal_id UUID,
    revenuecat_app_user_id TEXT,
    binding_generation BIGINT,
    account_grants_allowed BOOLEAN,
    already_bound BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    principal internal.purchase_principals%ROWTYPE;
    existing_binding internal.purchase_principal_bindings%ROWTYPE;
    next_generation BIGINT;
    binding_unchanged BOOLEAN;
    store_tier public.subscription_tier_enum;
    account_grant_tier public.subscription_tier_enum;
    account_grant_expires_at TIMESTAMPTZ;
    promotion_source_hash TEXT;
    affected_user_ids UUID[];
    locked_user_count INTEGER;
    current_user_is_anonymous BOOLEAN;
    grant_owner_is_anonymous BOOLEAN;
    principal_was_pending BOOLEAN;
    current_projection_tier public.subscription_tier_enum;
    current_projection_expires_at TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_user_id IS NULL
       OR p_purchase_principal_id IS NULL
       OR p_capability_hash IS NULL
       OR p_capability_hash !~ '^[0-9a-f]{64}$'
       OR p_binding_intent_generation IS NULL
       OR p_binding_intent_generation NOT BETWEEN 1 AND 9007199254740991
       OR p_authoritative_snapshot_at_ms IS NULL
       OR p_authoritative_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_store_tier NOT IN ('free', 'pro')
       OR p_allow_non_subscription_pass_grant IS NULL
       OR p_account_grant_tier NOT IN ('free', 'pro') THEN
        RAISE EXCEPTION 'purchase_principal_invalid_resolution'
            USING ERRCODE = '22023';
    END IF;

    store_tier := p_store_tier::public.subscription_tier_enum;
    account_grant_tier := p_account_grant_tier::public.subscription_tier_enum;
    account_grant_expires_at := p_account_grant_expires_at;
    IF (store_tier = 'free'::public.subscription_tier_enum
            AND p_store_expires_at IS NOT NULL)
       OR (store_tier = 'pro'::public.subscription_tier_enum
            AND p_store_expires_at IS NOT NULL
            AND p_store_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            ))
       OR (account_grant_tier = 'free'::public.subscription_tier_enum
            AND p_account_grant_expires_at IS NOT NULL)
       OR (account_grant_tier = 'pro'::public.subscription_tier_enum
            AND p_account_grant_expires_at IS NOT NULL
            AND p_account_grant_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            )) THEN
        RAISE EXCEPTION 'purchase_principal_invalid_entitlement_state'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';

    -- Previous-bundle webhook compatibility calls can still address the
    -- destination by its Auth UUID before this completion creates the stable
    -- binding. Serialize that cutover before taking any principal/user row
    -- locks so neither side can make its legacy-versus-stable decision from a
    -- relationship that changes underneath it.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-legacy-compatibility',
            0::BIGINT
        )
    );
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal:' || p_purchase_principal_id::TEXT,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = p_purchase_principal_id
      AND principals.capability_hash = p_capability_hash
      AND principals.status IN ('pending', 'active')
    FOR UPDATE;
    principal_was_pending := principal.status = 'pending';

    IF principal.latest_binding_intent_generation <>
            p_binding_intent_generation THEN
        RAISE EXCEPTION 'purchase_principal_binding_intent_stale'
            USING ERRCODE = '40001';
    END IF;

    IF rollout.principal_mode <> 'stable'
       AND principal.status <> 'active' THEN
        RAISE EXCEPTION 'purchase_principal_rollout_changed'
            USING ERRCODE = '40001';
    END IF;
    IF rollout.account_grant_mode = 'authoritative' THEN
        -- After cutover, only the private account-grant ledger is authority.
        -- Provider promotional records are still observed but cannot recreate
        -- or extend a retired compatibility grant.
        account_grant_tier := 'free'::public.subscription_tier_enum;
        account_grant_expires_at := NULL;
    END IF;

    SELECT binding.*
    INTO existing_binding
    FROM internal.purchase_principal_bindings AS binding
    WHERE binding.purchase_principal_id = principal.id;

    affected_user_ids := ARRAY(
        SELECT DISTINCT user_id
        FROM pg_catalog.UNNEST(ARRAY[
            p_auth_user_id,
            existing_binding.auth_user_id,
            principal.account_grant_owner_user_id
        ]::UUID[]) AS users(user_id)
        WHERE user_id IS NOT NULL
        ORDER BY user_id
    );

    PERFORM users.id
    FROM public.users AS users
    JOIN auth.users AS auth_user ON auth_user.id = users.id
    WHERE users.id = ANY(affected_user_ids)
    ORDER BY users.id
    FOR UPDATE OF users, auth_user;
    GET DIAGNOSTICS locked_user_count = ROW_COUNT;
    IF locked_user_count <> pg_catalog.CARDINALITY(affected_user_ids) THEN
        RAISE EXCEPTION 'purchase_principal_user_not_available'
            USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id = ANY(affected_user_ids)
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    ) THEN
        RAISE EXCEPTION 'purchase_principal_account_deletion_in_progress'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT auth_user.is_anonymous
    INTO STRICT current_user_is_anonymous
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_auth_user_id;

    IF principal_was_pending AND p_allow_non_subscription_pass_grant THEN
        SELECT users.subscription_tier, users.subscription_expires_at
        INTO STRICT current_projection_tier, current_projection_expires_at
        FROM public.users AS users
        WHERE users.id = p_auth_user_id;
        IF current_projection_tier <> 'pro'::public.subscription_tier_enum
           OR current_projection_expires_at IS NULL
           OR current_projection_expires_at IS DISTINCT FROM
                p_store_expires_at THEN
            RAISE EXCEPTION 'purchase_principal_entitlement_projection_changed'
                USING ERRCODE = '40001';
        END IF;
    END IF;

    IF principal.account_grant_owner_user_id IS NOT NULL THEN
        SELECT auth_user.is_anonymous
        INTO grant_owner_is_anonymous
        FROM auth.users AS auth_user
        WHERE auth_user.id = principal.account_grant_owner_user_id;
    END IF;

    -- A principal first created while signed out may nominate the first linked
    -- account as its legacy-promotion owner, but only before any account grant
    -- exists. Once a grant has been recorded, its account ownership is frozen
    -- and ordinary account switching cannot move it.
    IF current_user_is_anonymous IS FALSE
       AND principal.account_grant_owner_user_id IS DISTINCT FROM p_auth_user_id
       AND (
           principal.account_grant_owner_user_id IS NULL
           OR grant_owner_is_anonymous IS TRUE
       )
       AND NOT EXISTS (
           SELECT 1
           FROM internal.account_access_grants AS grant_row
           WHERE grant_row.source_kind = 'revenuecat_legacy'
             AND grant_row.source_reference_hash = pg_catalog.ENCODE(
                 extensions.digest(
                     'revenuecat-legacy-promotion:' || principal.id::TEXT,
                     'sha256'
                 ),
                 'hex'
             )
       ) THEN
        UPDATE internal.purchase_principals AS principals
        SET account_grant_owner_user_id = p_auth_user_id,
            updated_at = pg_catalog.CLOCK_TIMESTAMP()
        WHERE principals.id = principal.id;
        principal.account_grant_owner_user_id := p_auth_user_id;
    END IF;

    INSERT INTO internal.purchase_principal_store_state (
        purchase_principal_id,
        target_tier,
        target_expires_at,
        allow_non_subscription_pass_grant,
        authoritative_snapshot_at_ms,
        last_event_timestamp_ms,
        updated_at
    )
    VALUES (
        principal.id,
        store_tier,
        p_store_expires_at,
        p_allow_non_subscription_pass_grant,
        p_authoritative_snapshot_at_ms,
        0,
        pg_catalog.CLOCK_TIMESTAMP()
    )
    ON CONFLICT (purchase_principal_id) DO UPDATE
    SET target_tier = EXCLUDED.target_tier,
        target_expires_at = EXCLUDED.target_expires_at,
        allow_non_subscription_pass_grant = CASE
            WHEN principal_was_pending
                THEN EXCLUDED.allow_non_subscription_pass_grant
            ELSE internal.purchase_principal_store_state
                .allow_non_subscription_pass_grant
        END,
        authoritative_snapshot_at_ms = EXCLUDED.authoritative_snapshot_at_ms,
        updated_at = EXCLUDED.updated_at
    WHERE EXCLUDED.authoritative_snapshot_at_ms >=
        internal.purchase_principal_store_state.authoritative_snapshot_at_ms;

    promotion_source_hash := pg_catalog.ENCODE(
        extensions.digest(
            'revenuecat-legacy-promotion:' || principal.id::TEXT,
            'sha256'
        ),
        'hex'
    );

    IF principal.account_grant_owner_user_id IS NOT NULL
       AND (
           rollout.account_grant_mode = 'authoritative'
           OR principal.provider_account_grant_frozen IS FALSE
       ) THEN
        IF account_grant_tier = 'pro'::public.subscription_tier_enum THEN
            INSERT INTO internal.account_access_grants (
                account_user_id,
                grant_kind,
                grant_tier,
                starts_at,
                expires_at,
                revoked_at,
                source_kind,
                source_reference_hash,
                source_snapshot_at_ms,
                updated_at
            )
            VALUES (
                principal.account_grant_owner_user_id,
                'promotion',
                'pro'::public.subscription_tier_enum,
                LEAST(
                    pg_catalog.CLOCK_TIMESTAMP(),
                    pg_catalog.TO_TIMESTAMP(
                        p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
                    )
                ),
                account_grant_expires_at,
                NULL,
                'revenuecat_legacy',
                promotion_source_hash,
                p_authoritative_snapshot_at_ms,
                pg_catalog.CLOCK_TIMESTAMP()
            )
            ON CONFLICT (source_kind, source_reference_hash) DO UPDATE
            SET account_user_id = EXCLUDED.account_user_id,
                expires_at = EXCLUDED.expires_at,
                revoked_at = NULL,
                source_snapshot_at_ms = EXCLUDED.source_snapshot_at_ms,
                updated_at = EXCLUDED.updated_at
            WHERE internal.account_access_grants.source_snapshot_at_ms IS NULL
               OR EXCLUDED.source_snapshot_at_ms >=
                    internal.account_access_grants.source_snapshot_at_ms;
        ELSE
            UPDATE internal.account_access_grants AS grant_row
            SET revoked_at = COALESCE(
                    grant_row.revoked_at,
                    pg_catalog.CLOCK_TIMESTAMP()
                ),
                source_snapshot_at_ms = p_authoritative_snapshot_at_ms,
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE grant_row.source_kind = 'revenuecat_legacy'
              AND grant_row.source_reference_hash = promotion_source_hash
              AND (
                  grant_row.source_snapshot_at_ms IS NULL
                  OR p_authoritative_snapshot_at_ms >=
                        grant_row.source_snapshot_at_ms
              );
        END IF;
    END IF;

    binding_unchanged := existing_binding.purchase_principal_id IS NOT NULL
        AND existing_binding.auth_user_id = p_auth_user_id;
    next_generation := CASE
        WHEN existing_binding.purchase_principal_id IS NULL THEN 1
        WHEN binding_unchanged THEN existing_binding.binding_generation
        ELSE existing_binding.binding_generation + 1
    END;

    INSERT INTO internal.purchase_principal_bindings (
        purchase_principal_id,
        auth_user_id,
        binding_generation,
        bound_at,
        updated_at
    )
    VALUES (
        principal.id,
        p_auth_user_id,
        next_generation,
        pg_catalog.CLOCK_TIMESTAMP(),
        pg_catalog.CLOCK_TIMESTAMP()
    )
    ON CONFLICT (purchase_principal_id) DO UPDATE
    SET auth_user_id = EXCLUDED.auth_user_id,
        binding_generation = EXCLUDED.binding_generation,
        bound_at = CASE
            WHEN internal.purchase_principal_bindings.auth_user_id
                    IS DISTINCT FROM EXCLUDED.auth_user_id
                THEN EXCLUDED.bound_at
            ELSE internal.purchase_principal_bindings.bound_at
        END,
        updated_at = EXCLUDED.updated_at;

    UPDATE internal.purchase_principals AS principals
    SET status = 'active',
        activated_at = COALESCE(
            principals.activated_at,
            pg_catalog.CLOCK_TIMESTAMP()
        ),
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE principals.id = principal.id;

    INSERT INTO internal.purchase_principal_reconciliation_queue (
        purchase_principal_id,
        lookup_app_user_id,
        next_reconcile_at,
        updated_at
    )
    VALUES (
        principal.id,
        principal.revenuecat_app_user_id,
        pg_catalog.NOW() + INTERVAL '6 hours',
        pg_catalog.CLOCK_TIMESTAMP()
    )
    ON CONFLICT (purchase_principal_id) DO UPDATE
    SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
        next_reconcile_at = LEAST(
            internal.purchase_principal_reconciliation_queue.next_reconcile_at,
            EXCLUDED.next_reconcile_at
        ),
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        updated_at = EXCLUDED.updated_at;

    -- Once this provider identity is principal-owned, the legacy per-user
    -- reconciler must not project its mixed StoreKit/promotion state back onto
    -- the former Auth UUID.
    DELETE FROM internal.revenuecat_reconciliation_queue AS legacy_queue
    WHERE legacy_queue.lookup_app_user_id = principal.revenuecat_app_user_id;

    IF principal.account_grant_owner_user_id IS NOT NULL
       AND principal.revenuecat_app_user_id =
            pg_catalog.UPPER(
                principal.account_grant_owner_user_id::TEXT
            ) THEN
        DELETE FROM internal.legacy_revenuecat_entitlement_state AS legacy
        WHERE legacy.merian_user_id =
            principal.account_grant_owner_user_id;
    END IF;

    IF existing_binding.auth_user_id IS NOT NULL
       AND existing_binding.auth_user_id <> p_auth_user_id THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            existing_binding.auth_user_id
        );
    END IF;
    PERFORM internal.recompute_purchase_principal_entitlement(p_auth_user_id);
    IF principal.account_grant_owner_user_id IS NOT NULL
       AND principal.account_grant_owner_user_id <> p_auth_user_id
       AND principal.account_grant_owner_user_id IS DISTINCT FROM
            existing_binding.auth_user_id THEN
        PERFORM internal.recompute_purchase_principal_entitlement(
            principal.account_grant_owner_user_id
        );
    END IF;

    RETURN QUERY SELECT
        principal.id,
        principal.revenuecat_app_user_id,
        next_generation,
        rollout.account_grant_mode = 'dual_read'
            AND principal.provider_account_grant_frozen IS FALSE
            AND current_user_is_anonymous IS FALSE
            AND principal.account_grant_owner_user_id = p_auth_user_id,
        binding_unchanged;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_account_access_grant(
    p_account_user_id UUID,
    p_grant_kind TEXT,
    p_expires_at TIMESTAMPTZ,
    p_source_reference_hash TEXT
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    grant_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_account_user_id IS NULL
       OR p_grant_kind NOT IN ('beta', 'promotion', 'support')
       OR p_source_reference_hash IS NULL
       OR p_source_reference_hash !~ '^[0-9a-f]{64}$'
       OR (p_expires_at IS NOT NULL AND p_expires_at <= pg_catalog.NOW()) THEN
        RAISE EXCEPTION 'account_access_grant_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_account_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_access_grant_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO internal.account_access_grants (
        account_user_id,
        grant_kind,
        expires_at,
        source_kind,
        source_reference_hash
    )
    VALUES (
        p_account_user_id,
        p_grant_kind,
        p_expires_at,
        'operator',
        p_source_reference_hash
    )
    ON CONFLICT (source_kind, source_reference_hash) DO UPDATE
    SET grant_kind = EXCLUDED.grant_kind,
        expires_at = EXCLUDED.expires_at,
        revoked_at = NULL,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE internal.account_access_grants.account_user_id =
            EXCLUDED.account_user_id
    RETURNING internal.account_access_grants.id INTO grant_id;

    IF grant_id IS NULL THEN
        RAISE EXCEPTION 'account_access_grant_source_conflict'
            USING ERRCODE = '23505';
    END IF;

    PERFORM internal.recompute_purchase_principal_entitlement(
        p_account_user_id
    );
    RETURN grant_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_account_access_grant(
    p_grant_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    affected_user_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    SELECT grant_row.account_user_id
    INTO affected_user_id
    FROM internal.account_access_grants AS grant_row
    WHERE grant_row.id = p_grant_id;
    IF affected_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Grant writers lock the owning user before the grant row. Match that
    -- order here; updating first would let the projection trigger hold the
    -- grant while waiting on a user owned by reconciliation.
    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = affected_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    UPDATE internal.account_access_grants AS grant_row
    SET revoked_at = COALESCE(
            grant_row.revoked_at,
            pg_catalog.CLOCK_TIMESTAMP()
        ),
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE grant_row.id = p_grant_id
      AND grant_row.account_user_id = affected_user_id;

    IF NOT FOUND THEN
        IF EXISTS (
            SELECT 1
            FROM internal.account_access_grants AS grant_row
            WHERE grant_row.id = p_grant_id
        ) THEN
            RAISE EXCEPTION 'account_access_grant_changed'
                USING ERRCODE = '40001';
        END IF;
        RETURN FALSE;
    END IF;

    PERFORM internal.recompute_purchase_principal_entitlement(
        affected_user_id
    );
    RETURN TRUE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_revenuecat_identity_subjects(
    p_subjects JSONB
)
RETURNS TABLE (
    subject_position INTEGER,
    subject_kind TEXT,
    lookup_app_user_id TEXT,
    identity_kind TEXT,
    identity_id UUID,
    allow_non_subscription_pass_grant BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    subject RECORD;
    identifier RECORD;
    subject_identifiers TEXT[];
    seen_subject_kinds TEXT[] := ARRAY[]::TEXT[];
    seen_identity_keys TEXT[] := ARRAY[]::TEXT[];
    resolved_principal_id UUID;
    resolved_principal_app_user_id TEXT;
    resolved_user_id UUID;
    principal_match_count INTEGER;
    user_match_count INTEGER;
    valid_uuid_identifier_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 2 THEN
        RAISE EXCEPTION 'revenuecat_invalid_identity_subjects'
            USING ERRCODE = '22023';
    END IF;

    FOR subject IN
        SELECT item.value, item.position::INTEGER
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        IF pg_catalog.JSONB_TYPEOF(subject.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'identifiers'
           ) IS DISTINCT FROM 'array'
           OR pg_catalog.JSONB_ARRAY_LENGTH(
               subject.value -> 'identifiers'
           ) NOT BETWEEN 1 AND 100 THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_subjects'
                USING ERRCODE = '22023';
        END IF;

        subject_kind := subject.value ->> 'subject_kind';
        IF subject_kind NOT IN (
            'customer',
            'transfer_source',
            'transfer_destination'
        ) OR subject_kind = ANY(seen_subject_kinds) THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_subjects'
                USING ERRCODE = '22023';
        END IF;
        seen_subject_kinds := pg_catalog.ARRAY_APPEND(
            seen_subject_kinds,
            subject_kind
        );

        subject_identifiers := ARRAY[]::TEXT[];
        FOR identifier IN
            SELECT item.value, item.position
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                subject.value -> 'identifiers'
            ) WITH ORDINALITY AS item(value, position)
            ORDER BY item.position
        LOOP
            IF pg_catalog.CHAR_LENGTH(identifier.value) NOT BETWEEN 1 AND 1500
               OR identifier.value ~ '[[:cntrl:]]'
               OR identifier.value = ANY(subject_identifiers) THEN
                RAISE EXCEPTION 'revenuecat_invalid_identity_subjects'
                    USING ERRCODE = '22023';
            END IF;
            subject_identifiers := pg_catalog.ARRAY_APPEND(
                subject_identifiers,
                identifier.value
            );
        END LOOP;

        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            (pg_catalog.ARRAY_AGG(
                principals.id
                ORDER BY principals.id
            ))[1],
            (pg_catalog.ARRAY_AGG(
                principals.revenuecat_app_user_id
                ORDER BY principals.id
            ))[1]
        INTO
            principal_match_count,
            resolved_principal_id,
            resolved_principal_app_user_id
        FROM internal.purchase_principals AS principals
        WHERE principals.status = 'active'
          AND principals.revenuecat_app_user_id = ANY(subject_identifiers);

        IF principal_match_count > 1 THEN
            RAISE EXCEPTION 'revenuecat_identity_mapping_ambiguous'
                USING ERRCODE = 'P0001';
        END IF;
        IF principal_match_count = 1 THEN
            IF 'purchase_principal:' || resolved_principal_id::TEXT =
                    ANY(seen_identity_keys) THEN
                RAISE EXCEPTION 'revenuecat_identity_mapping_ambiguous'
                    USING ERRCODE = 'P0001';
            END IF;
            seen_identity_keys := pg_catalog.ARRAY_APPEND(
                seen_identity_keys,
                'purchase_principal:' || resolved_principal_id::TEXT
            );
            SELECT state.allow_non_subscription_pass_grant
            INTO STRICT allow_non_subscription_pass_grant
            FROM internal.purchase_principal_store_state AS state
            WHERE state.purchase_principal_id = resolved_principal_id;
            subject_position := subject.position;
            lookup_app_user_id := resolved_principal_app_user_id;
            identity_kind := 'purchase_principal';
            identity_id := resolved_principal_id;
            RETURN NEXT;
            CONTINUE;
        END IF;

        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE candidate.value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                  AND pg_catalog.LOWER(candidate.value) <>
                      '00000000-0000-0000-0000-000000000000'
            )::INTEGER,
            pg_catalog.COUNT(DISTINCT users.id)::INTEGER,
            (pg_catalog.ARRAY_AGG(
                users.id
                ORDER BY candidate.position
            ) FILTER (WHERE users.id IS NOT NULL))[1]
        INTO
            valid_uuid_identifier_count,
            user_match_count,
            resolved_user_id
        FROM pg_catalog.UNNEST(subject_identifiers)
            WITH ORDINALITY AS candidate(value, position)
        LEFT JOIN public.users AS users
          ON users.id = CASE
              WHEN candidate.value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                  THEN candidate.value::UUID
              ELSE NULL
          END;

        IF user_match_count > 1 THEN
            RAISE EXCEPTION 'revenuecat_identity_mapping_ambiguous'
                USING ERRCODE = 'P0001';
        END IF;
        IF user_match_count = 1 THEN
            IF 'legacy_user:' || resolved_user_id::TEXT =
                    ANY(seen_identity_keys) THEN
                RAISE EXCEPTION 'revenuecat_identity_mapping_ambiguous'
                    USING ERRCODE = 'P0001';
            END IF;
            seen_identity_keys := pg_catalog.ARRAY_APPEND(
                seen_identity_keys,
                'legacy_user:' || resolved_user_id::TEXT
            );
            subject_position := subject.position;
            lookup_app_user_id := COALESCE(
                (
                    SELECT candidates.value
                    FROM pg_catalog.UNNEST(subject_identifiers)
                        WITH ORDINALITY AS candidates(value, position)
                    WHERE CASE
                        WHEN candidates.value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                            THEN candidates.value::UUID
                        ELSE NULL
                    END = resolved_user_id
                    ORDER BY candidates.position
                    LIMIT 1
                ),
                resolved_user_id::TEXT
            );
            identity_kind := 'legacy_user';
            identity_id := resolved_user_id;
            allow_non_subscription_pass_grant := NULL;
            RETURN NEXT;
            CONTINUE;
        END IF;

        -- Opaque customers unrelated to Merian are ignored. A UUID-shaped
        -- normal/destination subject can be a profile-creation race and stays
        -- retryable; a deleted transfer source has nothing left to revoke.
        IF valid_uuid_identifier_count > 0
           AND subject_kind <> 'transfer_source' THEN
            RAISE EXCEPTION 'revenuecat_user_not_found'
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.resolve_revenuecat_identity_subjects(JSONB) IS
    'Service-only resolver that maps verified RevenueCat identifiers to an active stable purchase principal before considering legacy UUID profiles. Callers cannot select the resolved identity.';

CREATE OR REPLACE FUNCTION internal.apply_purchase_principal_snapshot(
    p_purchase_principal_id UUID,
    p_event_id TEXT,
    p_event_timestamp_ms BIGINT,
    p_authoritative_snapshot_at_ms BIGINT,
    p_store_tier TEXT,
    p_store_expires_at TIMESTAMPTZ,
    p_allow_non_subscription_pass_grant BOOLEAN,
    p_preserve_account_grant BOOLEAN,
    p_account_grant_tier TEXT,
    p_account_grant_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    state_applied BOOLEAN,
    account_grant_update_applied BOOLEAN,
    projected_auth_user_id UUID,
    projected_entitlement_version BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    account_grant_mode_value TEXT;
    principal internal.purchase_principals%ROWTYPE;
    state internal.purchase_principal_store_state%ROWTYPE;
    store_tier public.subscription_tier_enum;
    grant_tier public.subscription_tier_enum;
    grant_expires_at TIMESTAMPTZ;
    promotion_source_hash TEXT;
    incoming_is_newer BOOLEAN;
    affected_user_ids UUID[];
BEGIN
    PERFORM internal.require_service_role();
    account_grant_update_applied := FALSE;

    IF p_purchase_principal_id IS NULL
       OR p_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_id) NOT BETWEEN 1 AND 255
       OR p_event_id ~ '[[:cntrl:]]'
       OR p_event_timestamp_ms IS NULL
       OR p_event_timestamp_ms NOT BETWEEN 0 AND 253402300799999
       OR p_authoritative_snapshot_at_ms IS NULL
       OR p_authoritative_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_store_tier NOT IN ('free', 'pro')
       OR p_preserve_account_grant IS NULL
       OR p_account_grant_tier NOT IN ('free', 'pro') THEN
        RAISE EXCEPTION 'purchase_principal_invalid_snapshot'
            USING ERRCODE = '22023';
    END IF;

    store_tier := p_store_tier::public.subscription_tier_enum;
    grant_tier := p_account_grant_tier::public.subscription_tier_enum;
    grant_expires_at := p_account_grant_expires_at;
    IF (store_tier = 'free'::public.subscription_tier_enum
            AND p_store_expires_at IS NOT NULL)
       OR (store_tier = 'pro'::public.subscription_tier_enum
            AND p_store_expires_at IS NOT NULL
            AND p_store_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            ))
       OR (grant_tier = 'free'::public.subscription_tier_enum
            AND p_account_grant_expires_at IS NOT NULL)
       OR (grant_tier = 'pro'::public.subscription_tier_enum
            AND p_account_grant_expires_at IS NOT NULL
            AND p_account_grant_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            )) THEN
        RAISE EXCEPTION 'purchase_principal_invalid_snapshot'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.account_grant_mode
    INTO STRICT account_grant_mode_value
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';
    IF account_grant_mode_value = 'authoritative' THEN
        grant_tier := 'free'::public.subscription_tier_enum;
        grant_expires_at := NULL;
    END IF;

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = p_purchase_principal_id
      AND principals.status = 'active'
    FOR UPDATE;

    affected_user_ids := ARRAY(
        SELECT DISTINCT user_id
        FROM (
            SELECT binding.auth_user_id AS user_id
            FROM internal.purchase_principal_bindings AS binding
            WHERE binding.purchase_principal_id = principal.id
            UNION ALL
            SELECT principal.account_grant_owner_user_id
        ) AS affected
        WHERE user_id IS NOT NULL
        ORDER BY user_id
    );

    IF pg_catalog.CARDINALITY(affected_user_ids) > 0 THEN
        PERFORM users.id
        FROM public.users AS users
        WHERE users.id = ANY(affected_user_ids)
        ORDER BY users.id
        FOR UPDATE;
    END IF;

    SELECT states.*
    INTO state
    FROM internal.purchase_principal_store_state AS states
    WHERE states.purchase_principal_id = principal.id
    FOR UPDATE;

    incoming_is_newer :=
        NOT FOUND
        OR (
            p_authoritative_snapshot_at_ms >
                state.authoritative_snapshot_at_ms
        )
        OR (
            p_authoritative_snapshot_at_ms =
                state.authoritative_snapshot_at_ms
            AND p_event_timestamp_ms > state.last_event_timestamp_ms
        )
        OR (
            p_authoritative_snapshot_at_ms =
                state.authoritative_snapshot_at_ms
            AND p_event_timestamp_ms = state.last_event_timestamp_ms
            AND p_event_id COLLATE pg_catalog."C" >
                COALESCE(state.last_event_id, '') COLLATE pg_catalog."C"
        );

    IF incoming_is_newer THEN
        INSERT INTO internal.purchase_principal_store_state (
            purchase_principal_id,
            target_tier,
            target_expires_at,
            allow_non_subscription_pass_grant,
            authoritative_snapshot_at_ms,
            last_event_id,
            last_event_timestamp_ms,
            updated_at
        )
        VALUES (
            principal.id,
            store_tier,
            p_store_expires_at,
            COALESCE(p_allow_non_subscription_pass_grant, FALSE),
            p_authoritative_snapshot_at_ms,
            p_event_id,
            p_event_timestamp_ms,
            pg_catalog.CLOCK_TIMESTAMP()
        )
        ON CONFLICT (purchase_principal_id) DO UPDATE
        SET target_tier = EXCLUDED.target_tier,
            target_expires_at = EXCLUDED.target_expires_at,
            allow_non_subscription_pass_grant = CASE
                WHEN p_allow_non_subscription_pass_grant IS NULL THEN
                    internal.purchase_principal_store_state
                        .allow_non_subscription_pass_grant
                ELSE EXCLUDED.allow_non_subscription_pass_grant
            END,
            authoritative_snapshot_at_ms =
                EXCLUDED.authoritative_snapshot_at_ms,
            last_event_id = CASE
                WHEN EXCLUDED.last_event_timestamp_ms = 0
                    THEN internal.purchase_principal_store_state.last_event_id
                ELSE EXCLUDED.last_event_id
            END,
            last_event_timestamp_ms = CASE
                WHEN EXCLUDED.last_event_timestamp_ms = 0
                    THEN internal.purchase_principal_store_state
                        .last_event_timestamp_ms
                ELSE EXCLUDED.last_event_timestamp_ms
            END,
            updated_at = EXCLUDED.updated_at;

        -- A RevenueCat TRANSFER is a StoreKit/customer-identity signal. The
        -- provider can move promotional records with that customer, but those
        -- grants are account-owned in Merian and must neither follow the
        -- destination nor disappear from the source account.
        IF account_grant_mode_value = 'authoritative'
           OR (
               NOT p_preserve_account_grant
               AND principal.provider_account_grant_frozen IS FALSE
           ) THEN
            promotion_source_hash := pg_catalog.ENCODE(
                extensions.digest(
                    'revenuecat-legacy-promotion:' || principal.id::TEXT,
                    'sha256'
                ),
                'hex'
            );
            IF grant_tier = 'pro'::public.subscription_tier_enum THEN
                IF principal.account_grant_owner_user_id IS NULL THEN
                    RAISE EXCEPTION 'purchase_principal_grant_owner_required'
                        USING ERRCODE = '55000';
                END IF;
                INSERT INTO internal.account_access_grants (
                    account_user_id,
                    grant_kind,
                    grant_tier,
                    starts_at,
                    expires_at,
                    revoked_at,
                    source_kind,
                    source_reference_hash,
                    source_snapshot_at_ms,
                    updated_at
                )
                VALUES (
                    principal.account_grant_owner_user_id,
                    'promotion',
                    'pro'::public.subscription_tier_enum,
                    LEAST(
                        pg_catalog.CLOCK_TIMESTAMP(),
                        pg_catalog.TO_TIMESTAMP(
                            p_authoritative_snapshot_at_ms::DOUBLE PRECISION /
                                1000.0
                        )
                    ),
                    grant_expires_at,
                    NULL,
                    'revenuecat_legacy',
                    promotion_source_hash,
                    p_authoritative_snapshot_at_ms,
                    pg_catalog.CLOCK_TIMESTAMP()
                )
                ON CONFLICT (source_kind, source_reference_hash) DO UPDATE
                SET expires_at = EXCLUDED.expires_at,
                    revoked_at = NULL,
                    source_snapshot_at_ms = EXCLUDED.source_snapshot_at_ms,
                    updated_at = EXCLUDED.updated_at
                WHERE internal.account_access_grants.account_user_id =
                        EXCLUDED.account_user_id
                  AND (
                      internal.account_access_grants.source_snapshot_at_ms IS NULL
                      OR EXCLUDED.source_snapshot_at_ms >=
                            internal.account_access_grants.source_snapshot_at_ms
                  );
            ELSE
                UPDATE internal.account_access_grants AS grant_row
                SET revoked_at = COALESCE(
                        grant_row.revoked_at,
                        pg_catalog.CLOCK_TIMESTAMP()
                    ),
                    source_snapshot_at_ms = p_authoritative_snapshot_at_ms,
                    updated_at = pg_catalog.CLOCK_TIMESTAMP()
                WHERE grant_row.source_kind = 'revenuecat_legacy'
                  AND grant_row.source_reference_hash = promotion_source_hash
                  AND (
                      grant_row.source_snapshot_at_ms IS NULL
                      OR p_authoritative_snapshot_at_ms >=
                            grant_row.source_snapshot_at_ms
              );
            END IF;
            account_grant_update_applied :=
                account_grant_mode_value = 'dual_read';
        END IF;

        FOREACH projected_auth_user_id IN ARRAY affected_user_ids LOOP
            PERFORM internal.recompute_purchase_principal_entitlement(
                projected_auth_user_id
            );
        END LOOP;
    END IF;

    SELECT binding.auth_user_id
    INTO projected_auth_user_id
    FROM internal.purchase_principal_bindings AS binding
    WHERE binding.purchase_principal_id = principal.id;

    IF projected_auth_user_id IS NOT NULL THEN
        SELECT users.entitlement_version
        INTO projected_entitlement_version
        FROM public.users AS users
        WHERE users.id = projected_auth_user_id;
    ELSE
        projected_entitlement_version := NULL;
    END IF;
    state_applied := incoming_is_newer;
    RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION internal.apply_purchase_principal_snapshot(
    UUID,
    TEXT,
    BIGINT,
    BIGINT,
    TEXT,
    TIMESTAMPTZ,
    BOOLEAN,
    BOOLEAN,
    TEXT,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_revenuecat_identity_state(
    p_event_id TEXT,
    p_event_timestamp_ms BIGINT,
    p_event_type TEXT,
    p_payload_sha256 TEXT,
    p_signature_timestamp_s BIGINT,
    p_subjects JSONB
)
RETURNS TABLE (
    outcome TEXT,
    subject_count INTEGER,
    applied_count INTEGER,
    stale_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    existing_event internal.revenuecat_webhook_events%ROWTYPE;
    legacy_state internal.legacy_revenuecat_entitlement_state%ROWTYPE;
    subject RECORD;
    helper_result RECORD;
    identity_kinds TEXT[] := ARRAY[]::TEXT[];
    identity_ids UUID[] := ARRAY[]::UUID[];
    subject_kinds TEXT[] := ARRAY[]::TEXT[];
    lookup_app_user_ids TEXT[] := ARRAY[]::TEXT[];
    snapshot_times BIGINT[] := ARRAY[]::BIGINT[];
    store_tiers public.subscription_tier_enum[] :=
        ARRAY[]::public.subscription_tier_enum[];
    store_expiries TIMESTAMPTZ[] := ARRAY[]::TIMESTAMPTZ[];
    pass_grant_policy_updates BOOLEAN[] := ARRAY[]::BOOLEAN[];
    grant_tiers public.subscription_tier_enum[] :=
        ARRAY[]::public.subscription_tier_enum[];
    grant_expiries TIMESTAMPTZ[] := ARRAY[]::TIMESTAMPTZ[];
    affected_user_ids UUID[];
    identity_id UUID;
    subject_kind_value TEXT;
    identity_kind_value TEXT;
    lookup_app_user_id_value TEXT;
    store_tier public.subscription_tier_enum;
    store_expiry TIMESTAMPTZ;
    pass_grant_policy_update BOOLEAN;
    grant_tier public.subscription_tier_enum;
    grant_expiry TIMESTAMPTZ;
    snapshot_time BIGINT;
    subject_total INTEGER;
    subject_index INTEGER;
    locked_user_count INTEGER;
    resulting_applied_count INTEGER := 0;
    resulting_stale_count INTEGER := 0;
    resulting_outcome TEXT;
    resolved_entitlement_version BIGINT;
    event_inserted BOOLEAN;
    incoming_is_newer BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_id) NOT BETWEEN 1 AND 255
       OR p_event_id ~ '[[:cntrl:]]'
       OR p_event_timestamp_ms IS NULL
       OR p_event_timestamp_ms NOT BETWEEN 0 AND 253402300799999
       OR p_event_type IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_type) NOT BETWEEN 1 AND 100
       OR p_event_type ~ '[[:cntrl:]]'
       OR p_payload_sha256 IS NULL
       OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
       OR p_signature_timestamp_s IS NULL
       OR p_signature_timestamp_s NOT BETWEEN 0 AND 253402300799
       OR pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 2
       OR (
           p_event_type <> 'TRANSFER'
           AND pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 1
       ) THEN
        RAISE EXCEPTION 'revenuecat_invalid_identity_state'
            USING ERRCODE = '22023';
    END IF;

    SELECT events.*
    INTO existing_event
    FROM internal.revenuecat_webhook_events AS events
    WHERE events.event_id = p_event_id;
    IF FOUND THEN
        IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
           OR existing_event.event_type <> p_event_type
           OR existing_event.payload_sha256 <> p_payload_sha256 THEN
            RAISE EXCEPTION 'revenuecat_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;
        RETURN QUERY SELECT
            'duplicate'::TEXT,
            existing_event.subject_count::INTEGER,
            existing_event.applied_count::INTEGER,
            existing_event.stale_count::INTEGER;
        RETURN;
    END IF;

    FOR subject IN
        SELECT item.value, item.position
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        IF pg_catalog.JSONB_TYPEOF(subject.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'authoritative_snapshot_at_ms'
           ) IS DISTINCT FROM 'number'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_store_tier'
           ) IS DISTINCT FROM 'string'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_account_grant_tier'
           ) IS DISTINCT FROM 'string'
           OR NOT subject.value ? 'allow_non_subscription_pass_grant'
           OR NOT subject.value ? 'target_store_expires_at'
           OR NOT subject.value ? 'target_account_grant_expires_at'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'allow_non_subscription_pass_grant'
           ) NOT IN ('boolean', 'null')
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_store_expires_at'
           ) NOT IN ('string', 'null')
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_account_grant_expires_at'
           ) NOT IN ('string', 'null') THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_state'
                USING ERRCODE = '22023';
        END IF;

        subject_kind_value := subject.value ->> 'subject_kind';
        identity_kind_value := subject.value ->> 'identity_kind';
        lookup_app_user_id_value := subject.value ->> 'lookup_app_user_id';
        IF subject_kind_value IS NULL
           OR subject_kind_value NOT IN (
            'customer',
            'transfer_source',
            'transfer_destination'
        ) OR subject_kind_value = ANY(subject_kinds)
           OR (p_event_type = 'TRANSFER' AND subject_kind_value = 'customer')
           OR (p_event_type <> 'TRANSFER' AND subject_kind_value <> 'customer')
           OR identity_kind_value IS NULL
           OR identity_kind_value NOT IN (
               'legacy_user',
               'purchase_principal'
           )
           OR (
               identity_kind_value = 'legacy_user'
               AND pg_catalog.JSONB_TYPEOF(
                   subject.value -> 'allow_non_subscription_pass_grant'
               ) <> 'null'
           )
           OR subject.value ->> 'identity_id' !~*
                '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           OR lookup_app_user_id_value IS NULL
           OR (
               identity_kind_value = 'legacy_user'
               AND pg_catalog.CHAR_LENGTH(lookup_app_user_id_value)
                    NOT BETWEEN 1 AND 1500
           )
           OR (
               identity_kind_value = 'purchase_principal'
               AND pg_catalog.CHAR_LENGTH(lookup_app_user_id_value)
                    NOT BETWEEN 1 AND 255
           )
           OR lookup_app_user_id_value ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_state'
                USING ERRCODE = '22023';
        END IF;
        identity_id := (subject.value ->> 'identity_id')::UUID;
        snapshot_time :=
            (subject.value ->> 'authoritative_snapshot_at_ms')::BIGINT;
        IF snapshot_time NOT BETWEEN 0 AND 253402300799999
           OR subject.value ->> 'target_store_tier' NOT IN ('free', 'pro')
           OR subject.value ->> 'target_account_grant_tier'
                NOT IN ('free', 'pro') THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_state'
                USING ERRCODE = '22023';
        END IF;
        store_tier := (subject.value ->> 'target_store_tier')::
            public.subscription_tier_enum;
        grant_tier := (subject.value ->> 'target_account_grant_tier')::
            public.subscription_tier_enum;
        store_expiry := CASE
            WHEN pg_catalog.JSONB_TYPEOF(
                subject.value -> 'target_store_expires_at'
            ) = 'string'
                THEN (subject.value ->> 'target_store_expires_at')::
                    TIMESTAMPTZ
            ELSE NULL
        END;
        grant_expiry := CASE
            WHEN pg_catalog.JSONB_TYPEOF(
                subject.value -> 'target_account_grant_expires_at'
            ) = 'string'
                THEN (subject.value ->> 'target_account_grant_expires_at')::
                    TIMESTAMPTZ
            ELSE NULL
        END;
        pass_grant_policy_update := CASE
            WHEN pg_catalog.JSONB_TYPEOF(
                subject.value -> 'allow_non_subscription_pass_grant'
            ) = 'boolean'
                THEN (subject.value ->>
                    'allow_non_subscription_pass_grant')::BOOLEAN
            ELSE NULL
        END;
        IF (store_tier = 'free'::public.subscription_tier_enum
                AND store_expiry IS NOT NULL)
           OR (store_tier = 'pro'::public.subscription_tier_enum
                AND store_expiry IS NOT NULL
                AND store_expiry <= pg_catalog.TO_TIMESTAMP(
                    snapshot_time::DOUBLE PRECISION / 1000.0
                ))
           OR (grant_tier = 'free'::public.subscription_tier_enum
                AND grant_expiry IS NOT NULL)
           OR (grant_tier = 'pro'::public.subscription_tier_enum
                AND grant_expiry IS NOT NULL
                AND grant_expiry <= pg_catalog.TO_TIMESTAMP(
                    snapshot_time::DOUBLE PRECISION / 1000.0
                )) THEN
            RAISE EXCEPTION 'revenuecat_invalid_identity_state'
                USING ERRCODE = '22023';
        END IF;

        IF identity_kind_value = 'purchase_principal' THEN
            PERFORM principals.id
            FROM internal.purchase_principals AS principals
            WHERE principals.id = identity_id
              AND principals.status = 'active'
              AND principals.revenuecat_app_user_id =
                    lookup_app_user_id_value;
        ELSE
            PERFORM users.id
            FROM public.users AS users
            WHERE users.id = identity_id;
        END IF;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'revenuecat_identity_not_found'
                USING ERRCODE = 'P0001';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(identity_kinds, identity_ids)
                AS prior(kind, id)
            WHERE prior.kind = identity_kind_value
              AND prior.id = identity_id
        ) THEN
            RAISE EXCEPTION 'revenuecat_identity_mapping_ambiguous'
                USING ERRCODE = 'P0001';
        END IF;

        identity_kinds := pg_catalog.ARRAY_APPEND(
            identity_kinds,
            identity_kind_value
        );
        identity_ids := pg_catalog.ARRAY_APPEND(identity_ids, identity_id);
        subject_kinds := pg_catalog.ARRAY_APPEND(
            subject_kinds,
            subject_kind_value
        );
        lookup_app_user_ids := pg_catalog.ARRAY_APPEND(
            lookup_app_user_ids,
            lookup_app_user_id_value
        );
        snapshot_times := pg_catalog.ARRAY_APPEND(
            snapshot_times,
            snapshot_time
        );
        store_tiers := pg_catalog.ARRAY_APPEND(store_tiers, store_tier);
        store_expiries := pg_catalog.ARRAY_APPEND(
            store_expiries,
            store_expiry
        );
        pass_grant_policy_updates := pg_catalog.ARRAY_APPEND(
            pass_grant_policy_updates,
            pass_grant_policy_update
        );
        grant_tiers := pg_catalog.ARRAY_APPEND(grant_tiers, grant_tier);
        grant_expiries := pg_catalog.ARRAY_APPEND(
            grant_expiries,
            grant_expiry
        );
    END LOOP;

    subject_total := pg_catalog.CARDINALITY(identity_ids);

    -- All stable-principal mutations use principal -> affected users -> state.
    -- Lock every principal in UUID order before any public user row so a
    -- webhook TRANSFER cannot deadlock activation or reconciliation by taking
    -- the inverse user -> principal order.
    PERFORM principals.id
    FROM internal.purchase_principals AS principals
    JOIN pg_catalog.UNNEST(identity_kinds, identity_ids)
        AS ids(identity_kind, identity_id)
      ON ids.identity_kind = 'purchase_principal'
     AND ids.identity_id = principals.id
    ORDER BY principals.id
    FOR UPDATE OF principals;

    -- Once RevenueCat reports a customer transfer, provider promotional state
    -- is no longer a trustworthy account-grant stream for either stable
    -- principal. Freeze dual-read import on both sides permanently; StoreKit
    -- reconciliation continues, and an authoritative ledger cutover can still
    -- retire the old compatibility row explicitly.
    IF p_event_type = 'TRANSFER' THEN
        UPDATE internal.purchase_principals AS principals
        SET provider_account_grant_frozen = TRUE,
            updated_at = pg_catalog.CLOCK_TIMESTAMP()
        WHERE principals.id IN (
            SELECT ids.identity_id
            FROM pg_catalog.UNNEST(identity_kinds, identity_ids)
                AS ids(identity_kind, identity_id)
            WHERE ids.identity_kind = 'purchase_principal'
        );
    END IF;

    affected_user_ids := ARRAY(
        SELECT DISTINCT affected.user_id
        FROM (
            SELECT ids.identity_id AS user_id
            FROM pg_catalog.UNNEST(identity_kinds, identity_ids)
                AS ids(identity_kind, identity_id)
            WHERE ids.identity_kind = 'legacy_user'
            UNION ALL
            SELECT binding.auth_user_id
            FROM pg_catalog.UNNEST(identity_kinds, identity_ids)
                AS ids(identity_kind, identity_id)
            JOIN internal.purchase_principal_bindings AS binding
              ON ids.identity_kind = 'purchase_principal'
             AND binding.purchase_principal_id = ids.identity_id
            UNION ALL
            SELECT principals.account_grant_owner_user_id
            FROM pg_catalog.UNNEST(identity_kinds, identity_ids)
                AS ids(identity_kind, identity_id)
            JOIN internal.purchase_principals AS principals
              ON ids.identity_kind = 'purchase_principal'
             AND principals.id = ids.identity_id
        ) AS affected
        WHERE affected.user_id IS NOT NULL
        ORDER BY affected.user_id
    );

    IF pg_catalog.CARDINALITY(affected_user_ids) > 0 THEN
        PERFORM users.id
        FROM public.users AS users
        WHERE users.id = ANY(affected_user_ids)
        ORDER BY users.id
        FOR UPDATE;
        GET DIAGNOSTICS locked_user_count = ROW_COUNT;
        IF locked_user_count <> pg_catalog.CARDINALITY(affected_user_ids) THEN
            RAISE EXCEPTION 'revenuecat_user_not_found'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    resulting_outcome := CASE
        WHEN subject_total = 0 THEN 'ignored'
        ELSE 'stale'
    END;
    INSERT INTO internal.revenuecat_webhook_events (
        event_id,
        event_timestamp_ms,
        event_type,
        payload_sha256,
        signature_timestamp_s,
        outcome,
        subject_count,
        applied_count,
        stale_count
    )
    VALUES (
        p_event_id,
        p_event_timestamp_ms,
        p_event_type,
        p_payload_sha256,
        p_signature_timestamp_s,
        resulting_outcome,
        subject_total,
        0,
        subject_total
    )
    ON CONFLICT (event_id) DO NOTHING
    RETURNING TRUE INTO event_inserted;

    IF event_inserted IS NOT TRUE THEN
        SELECT events.*
        INTO STRICT existing_event
        FROM internal.revenuecat_webhook_events AS events
        WHERE events.event_id = p_event_id;
        IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
           OR existing_event.event_type <> p_event_type
           OR existing_event.payload_sha256 <> p_payload_sha256 THEN
            RAISE EXCEPTION 'revenuecat_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;
        RETURN QUERY SELECT
            'duplicate'::TEXT,
            existing_event.subject_count::INTEGER,
            existing_event.applied_count::INTEGER,
            existing_event.stale_count::INTEGER;
        RETURN;
    END IF;

    IF subject_total = 0 THEN
        RETURN QUERY SELECT 'ignored'::TEXT, 0, 0, 0;
        RETURN;
    END IF;

    FOR subject_index IN 1..subject_total LOOP
        identity_kind_value := identity_kinds[subject_index];
        identity_id := identity_ids[subject_index];
        subject_kind_value := subject_kinds[subject_index];
        snapshot_time := snapshot_times[subject_index];
        store_tier := store_tiers[subject_index];
        store_expiry := store_expiries[subject_index];
        pass_grant_policy_update :=
            pass_grant_policy_updates[subject_index];
        grant_tier := grant_tiers[subject_index];
        grant_expiry := grant_expiries[subject_index];

        IF identity_kind_value = 'purchase_principal' THEN
            SELECT result.*
            INTO STRICT helper_result
            FROM internal.apply_purchase_principal_snapshot(
                identity_id,
                p_event_id,
                p_event_timestamp_ms,
                snapshot_time,
                store_tier::TEXT,
                store_expiry,
                pass_grant_policy_update,
                p_event_type = 'TRANSFER',
                grant_tier::TEXT,
                grant_expiry
            ) AS result;
            incoming_is_newer := helper_result.state_applied;

            INSERT INTO internal.purchase_principal_webhook_event_subjects (
                event_id,
                purchase_principal_id,
                subject_kind,
                authoritative_snapshot_at_ms,
                target_store_tier,
                target_store_expires_at,
                allow_non_subscription_pass_grant,
                target_account_grant_tier,
                target_account_grant_expires_at,
                account_grant_update_applied,
                outcome,
                projected_auth_user_id,
                entitlement_version
            )
            VALUES (
                p_event_id,
                identity_id,
                subject_kind_value,
                snapshot_time,
                store_tier,
                store_expiry,
                pass_grant_policy_update,
                grant_tier,
                grant_expiry,
                helper_result.account_grant_update_applied,
                CASE WHEN incoming_is_newer THEN 'applied' ELSE 'stale' END,
                helper_result.projected_auth_user_id,
                helper_result.projected_entitlement_version
            );
        ELSE
            SELECT states.*
            INTO legacy_state
            FROM internal.legacy_revenuecat_entitlement_state AS states
            WHERE states.merian_user_id = identity_id
            FOR UPDATE;
            incoming_is_newer :=
                NOT FOUND
                OR snapshot_time >
                    legacy_state.authoritative_snapshot_at_ms
                OR (
                    snapshot_time =
                        legacy_state.authoritative_snapshot_at_ms
                    AND p_event_timestamp_ms >
                        legacy_state.last_event_timestamp_ms
                )
                OR (
                    snapshot_time =
                        legacy_state.authoritative_snapshot_at_ms
                    AND p_event_timestamp_ms =
                        legacy_state.last_event_timestamp_ms
                    AND p_event_id COLLATE pg_catalog."C" >
                        COALESCE(legacy_state.last_event_id, '')
                            COLLATE pg_catalog."C"
                );
            IF incoming_is_newer THEN
                INSERT INTO internal.legacy_revenuecat_entitlement_state (
                    merian_user_id,
                    target_tier,
                    target_expires_at,
                    authoritative_snapshot_at_ms,
                    last_event_id,
                    last_event_timestamp_ms,
                    updated_at
                )
                VALUES (
                    identity_id,
                    store_tier,
                    store_expiry,
                    snapshot_time,
                    p_event_id,
                    p_event_timestamp_ms,
                    pg_catalog.CLOCK_TIMESTAMP()
                )
                ON CONFLICT (merian_user_id) DO UPDATE
                SET target_tier = EXCLUDED.target_tier,
                    target_expires_at = EXCLUDED.target_expires_at,
                    authoritative_snapshot_at_ms =
                        EXCLUDED.authoritative_snapshot_at_ms,
                    last_event_id = EXCLUDED.last_event_id,
                    last_event_timestamp_ms =
                        EXCLUDED.last_event_timestamp_ms,
                    updated_at = EXCLUDED.updated_at;

                INSERT INTO internal.revenuecat_customer_state (
                    merian_user_id,
                    last_event_id,
                    last_event_timestamp_ms,
                    last_authoritative_snapshot_at_ms,
                    updated_at
                )
                VALUES (
                    identity_id,
                    p_event_id,
                    p_event_timestamp_ms,
                    snapshot_time,
                    pg_catalog.CLOCK_TIMESTAMP()
                )
                ON CONFLICT (merian_user_id) DO UPDATE
                SET last_event_id = EXCLUDED.last_event_id,
                    last_event_timestamp_ms =
                        EXCLUDED.last_event_timestamp_ms,
                    last_authoritative_snapshot_at_ms =
                        EXCLUDED.last_authoritative_snapshot_at_ms,
                    updated_at = EXCLUDED.updated_at;

                PERFORM internal.recompute_purchase_principal_entitlement(
                    identity_id
                );
            END IF;
            SELECT users.entitlement_version
            INTO STRICT resolved_entitlement_version
            FROM public.users AS users
            WHERE users.id = identity_id;

            INSERT INTO internal.revenuecat_webhook_event_subjects (
                event_id,
                merian_user_id,
                subject_kind,
                authoritative_snapshot_at_ms,
                target_tier,
                target_expires_at,
                outcome,
                entitlement_version
            )
            VALUES (
                p_event_id,
                identity_id,
                subject_kind_value,
                snapshot_time,
                store_tier,
                store_expiry,
                CASE WHEN incoming_is_newer THEN 'applied' ELSE 'stale' END,
                resolved_entitlement_version
            );
        END IF;

        IF incoming_is_newer THEN
            resulting_applied_count := resulting_applied_count + 1;
        ELSE
            resulting_stale_count := resulting_stale_count + 1;
        END IF;
    END LOOP;

    resulting_outcome := CASE
        WHEN resulting_applied_count = subject_total THEN 'applied'
        WHEN resulting_stale_count = subject_total THEN 'stale'
        ELSE 'mixed'
    END;
    UPDATE internal.revenuecat_webhook_events AS events
    SET outcome = resulting_outcome,
        applied_count = resulting_applied_count,
        stale_count = resulting_stale_count
    WHERE events.event_id = p_event_id;

    RETURN QUERY SELECT
        resulting_outcome,
        subject_total,
        resulting_applied_count,
        resulting_stale_count;
END;
$function$;

COMMENT ON FUNCTION public.apply_revenuecat_identity_state(
    TEXT,
    BIGINT,
    TEXT,
    TEXT,
    BIGINT,
    JSONB
) IS
    'Service-only atomic webhook ledger for legacy UUID customers and stable purchase principals. Store-backed and account-grant state remain separate for stable identities.';

-- Legacy compatibility callers must serialize with principal completion before
-- they decide that a UUID is still legacy-owned. The shared cutover advisory
-- lock is acquired before either side takes principal or user row locks. This
-- also covers a destination that is not related to the principal until the
-- completion transaction creates its binding. The helper then follows the
-- principal-before-user row-lock order and rechecks under lock.
CREATE OR REPLACE FUNCTION
internal.lock_legacy_revenuecat_compatibility_users(
    p_user_ids UUID[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    locked_user_count INTEGER;
BEGIN
    IF p_user_ids IS NULL
       OR COALESCE(pg_catalog.ARRAY_NDIMS(p_user_ids), 1) <> 1
       OR pg_catalog.CARDINALITY(p_user_ids) > 2
       OR EXISTS (
           SELECT 1
           FROM pg_catalog.UNNEST(p_user_ids) AS requested(user_id)
           WHERE requested.user_id IS NULL
       )
       OR pg_catalog.CARDINALITY(p_user_ids) <> (
           SELECT pg_catalog.COUNT(DISTINCT requested.user_id)::INTEGER
           FROM pg_catalog.UNNEST(p_user_ids) AS requested(user_id)
       ) THEN
        RAISE EXCEPTION 'revenuecat_invalid_legacy_compatibility_users'
            USING ERRCODE = '22023';
    END IF;
    IF pg_catalog.CARDINALITY(p_user_ids) = 0 THEN
        RETURN;
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-legacy-compatibility',
            0::BIGINT
        )
    );

    PERFORM principal.id
    FROM internal.purchase_principals AS principal
    LEFT JOIN internal.purchase_principal_bindings AS binding
      ON binding.purchase_principal_id = principal.id
    WHERE principal.account_grant_owner_user_id = ANY(p_user_ids)
       OR binding.auth_user_id = ANY(p_user_ids)
       OR CASE
           WHEN principal.revenuecat_app_user_id ~*
                '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
               THEN principal.revenuecat_app_user_id::UUID = ANY(p_user_ids)
           ELSE FALSE
       END
    ORDER BY principal.id
    FOR UPDATE OF principal;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = ANY(p_user_ids)
    ORDER BY users.id
    FOR UPDATE OF users;
    GET DIAGNOSTICS locked_user_count = ROW_COUNT;
    IF locked_user_count <> pg_catalog.CARDINALITY(p_user_ids) THEN
        RAISE EXCEPTION 'revenuecat_user_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principals AS principal
        LEFT JOIN internal.purchase_principal_bindings AS binding
          ON binding.purchase_principal_id = principal.id
        WHERE principal.status = 'active'
          AND (
              principal.account_grant_owner_user_id = ANY(p_user_ids)
              OR binding.auth_user_id = ANY(p_user_ids)
              OR CASE
                  WHEN principal.revenuecat_app_user_id ~*
                        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                      THEN principal.revenuecat_app_user_id::UUID =
                        ANY(p_user_ids)
                  ELSE FALSE
              END
          )
    ) THEN
        RAISE EXCEPTION 'revenuecat_legacy_identity_conflict'
            USING ERRCODE = '55000';
    END IF;
END;
$function$;

COMMENT ON FUNCTION
internal.lock_legacy_revenuecat_compatibility_users(UUID[]) IS
    'Serializes stable cutover, locks related purchase principals before legacy users, and rejects an active stable relationship under lock. Used only by previous-bundle compatibility adapters.';

REVOKE ALL ON FUNCTION
    internal.lock_legacy_revenuecat_compatibility_users(UUID[])
    FROM PUBLIC, anon, authenticated, service_role;

-- The previous webhook bundle remains live while this additive migration is
-- applied. Preserve its exact RPC shape, but route resolved legacy UUID
-- customers through the new ledger so an old bundle cannot write the effective
-- public.users projection directly. If an old payload resolves to a stable
-- purchase principal, fail closed: that payload combines StoreKit and
-- promotional access and cannot safely populate the separated stable state.
CREATE OR REPLACE FUNCTION public.apply_revenuecat_customer_state(
    p_event_id TEXT,
    p_event_timestamp_ms BIGINT,
    p_event_type TEXT,
    p_payload_sha256 TEXT,
    p_signature_timestamp_s BIGINT,
    p_subjects JSONB
)
RETURNS TABLE (
    outcome TEXT,
    subject_count INTEGER,
    applied_count INTEGER,
    stale_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    existing_event internal.revenuecat_webhook_events%ROWTYPE;
    subject RECORD;
    resolved RECORD;
    source_subject JSONB;
    resolver_subjects JSONB := '[]'::JSONB;
    identity_subjects JSONB := '[]'::JSONB;
    legacy_user_ids UUID[] := ARRAY[]::UUID[];
    seen_subject_kinds TEXT[] := ARRAY[]::TEXT[];
    subject_kind_value TEXT;
    input_subject_total INTEGER;
    distinct_candidate_count INTEGER;
    snapshot_time BIGINT;
    target_tier public.subscription_tier_enum;
    target_expiry TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_id) NOT BETWEEN 1 AND 255
       OR p_event_id ~ '[[:cntrl:]]'
       OR p_event_timestamp_ms IS NULL
       OR p_event_timestamp_ms NOT BETWEEN 0 AND 253402300799999
       OR p_event_type IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_type) NOT BETWEEN 1 AND 100
       OR p_event_type ~ '[[:cntrl:]]'
       OR p_payload_sha256 IS NULL
       OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
       OR p_signature_timestamp_s IS NULL
       OR p_signature_timestamp_s NOT BETWEEN 0 AND 253402300799
       OR pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'revenuecat_invalid_customer_state'
            USING ERRCODE = '22023';
    END IF;

    input_subject_total := pg_catalog.JSONB_ARRAY_LENGTH(p_subjects);
    IF input_subject_total > 2
       OR (p_event_type <> 'TRANSFER' AND input_subject_total > 1) THEN
        RAISE EXCEPTION 'revenuecat_invalid_customer_state'
            USING ERRCODE = '22023';
    END IF;

    -- Preserve the old bundle's durable retry boundary even if a referenced
    -- Auth profile has since been deleted.
    SELECT events.*
    INTO existing_event
    FROM internal.revenuecat_webhook_events AS events
    WHERE events.event_id = p_event_id;
    IF FOUND THEN
        IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
           OR existing_event.event_type <> p_event_type
           OR existing_event.payload_sha256 <> p_payload_sha256 THEN
            RAISE EXCEPTION 'revenuecat_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;
        RETURN QUERY SELECT
            'duplicate'::TEXT,
            existing_event.subject_count::INTEGER,
            existing_event.applied_count::INTEGER,
            existing_event.stale_count::INTEGER;
        RETURN;
    END IF;

    FOR subject IN
        SELECT item.value, item.position::INTEGER
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        IF pg_catalog.JSONB_TYPEOF(subject.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'candidate_user_ids'
           ) IS DISTINCT FROM 'array'
           OR pg_catalog.JSONB_ARRAY_LENGTH(
               subject.value -> 'candidate_user_ids'
           ) NOT BETWEEN 1 AND 32
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'authoritative_snapshot_at_ms'
           ) IS DISTINCT FROM 'number'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_tier'
           ) IS DISTINCT FROM 'string'
           OR (
               subject.value ? 'target_expires_at'
               AND pg_catalog.JSONB_TYPEOF(
                   subject.value -> 'target_expires_at'
               ) NOT IN ('null', 'string')
           )
           OR EXISTS (
               SELECT 1
               FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                   subject.value -> 'candidate_user_ids'
               ) AS candidate(value)
               WHERE candidate.value !~*
                    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                  OR pg_catalog.LOWER(candidate.value) =
                    '00000000-0000-0000-0000-000000000000'
           ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        subject_kind_value := subject.value ->> 'subject_kind';
        IF subject_kind_value IS NULL
           OR subject_kind_value NOT IN (
            'customer',
            'transfer_source',
            'transfer_destination'
        ) OR subject_kind_value = ANY(seen_subject_kinds)
           OR (p_event_type = 'TRANSFER' AND subject_kind_value = 'customer')
           OR (p_event_type <> 'TRANSFER' AND subject_kind_value <> 'customer')
        THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;
        seen_subject_kinds := pg_catalog.ARRAY_APPEND(
            seen_subject_kinds,
            subject_kind_value
        );

        SELECT pg_catalog.COUNT(DISTINCT candidate.value::UUID)::INTEGER
        INTO distinct_candidate_count
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            subject.value -> 'candidate_user_ids'
        ) AS candidate(value);
        IF distinct_candidate_count <>
                pg_catalog.JSONB_ARRAY_LENGTH(
                    subject.value -> 'candidate_user_ids'
                ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        snapshot_time :=
            (subject.value ->> 'authoritative_snapshot_at_ms')::BIGINT;
        IF snapshot_time NOT BETWEEN 0 AND 253402300799999
           OR subject.value ->> 'target_tier' NOT IN ('free', 'pro') THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;
        target_tier := (subject.value ->> 'target_tier')::
            public.subscription_tier_enum;
        target_expiry := CASE
            WHEN pg_catalog.JSONB_TYPEOF(
                subject.value -> 'target_expires_at'
            ) = 'string'
                THEN (subject.value ->> 'target_expires_at')::TIMESTAMPTZ
            ELSE NULL
        END;
        IF (target_tier = 'free'::public.subscription_tier_enum
                AND target_expiry IS NOT NULL)
           OR (target_tier = 'pro'::public.subscription_tier_enum
                AND target_expiry IS NOT NULL
                AND target_expiry <= pg_catalog.TO_TIMESTAMP(
                    snapshot_time::DOUBLE PRECISION / 1000.0
                )) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        resolver_subjects := resolver_subjects ||
            pg_catalog.JSONB_BUILD_ARRAY(
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', subject_kind_value,
                    'identifiers', subject.value -> 'candidate_user_ids'
                )
            );
    END LOOP;

    BEGIN
        FOR resolved IN
            SELECT result.*
            FROM public.resolve_revenuecat_identity_subjects(
                resolver_subjects
            ) AS result
            ORDER BY result.subject_position
        LOOP
            IF resolved.identity_kind <> 'legacy_user' THEN
                RAISE EXCEPTION 'revenuecat_legacy_identity_conflict'
                    USING ERRCODE = '55000';
            END IF;
            legacy_user_ids := pg_catalog.ARRAY_APPEND(
                legacy_user_ids,
                resolved.identity_id
            );
            source_subject := p_subjects -> (resolved.subject_position - 1);
            identity_subjects := identity_subjects ||
                pg_catalog.JSONB_BUILD_ARRAY(
                    pg_catalog.JSONB_BUILD_OBJECT(
                        'subject_kind', resolved.subject_kind,
                        'identity_kind', 'legacy_user',
                        'identity_id', resolved.identity_id,
                        'lookup_app_user_id',
                            internal.canonical_revenuecat_app_user_id(
                                resolved.identity_id
                            ),
                        'authoritative_snapshot_at_ms',
                            source_subject -> 'authoritative_snapshot_at_ms',
                        'target_store_tier',
                            source_subject -> 'target_tier',
                        'target_store_expires_at',
                            source_subject -> 'target_expires_at',
                        'allow_non_subscription_pass_grant', NULL,
                        'target_account_grant_tier', 'free',
                        'target_account_grant_expires_at', NULL
                    )
                );
        END LOOP;
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM = 'revenuecat_identity_mapping_ambiguous' THEN
                RAISE EXCEPTION 'revenuecat_user_mapping_ambiguous'
                    USING ERRCODE = 'P0001';
            END IF;
            RAISE;
    END;

    PERFORM internal.lock_legacy_revenuecat_compatibility_users(
        legacy_user_ids
    );

    RETURN QUERY
    SELECT result.outcome,
           result.subject_count,
           result.applied_count,
           result.stale_count
    FROM public.apply_revenuecat_identity_state(
        p_event_id,
        p_event_timestamp_ms,
        p_event_type,
        p_payload_sha256,
        p_signature_timestamp_s,
        identity_subjects
    ) AS result;
END;
$function$;

COMMENT ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT,
    BIGINT,
    TEXT,
    TEXT,
    BIGINT,
    JSONB
) IS
    'Service-only compatibility RPC for the previous webhook bundle. It validates the legacy payload, resolves legacy UUID subjects, and delegates to the separated identity ledger; stable-principal matches fail closed.';

CREATE OR REPLACE FUNCTION public.schedule_revenuecat_identity_reconciliation(
    p_subjects JSONB
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    subject JSONB;
    identity_kind TEXT;
    identity_id UUID;
    lookup_id_value TEXT;
    scheduled_count INTEGER := 0;
    seen_identity_ids UUID[] := ARRAY[]::UUID[];
BEGIN
    PERFORM internal.require_service_role();
    IF pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 2 THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
            USING ERRCODE = '22023';
    END IF;

    FOR subject IN
        SELECT item.value
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        identity_kind := subject ->> 'identity_kind';
        lookup_id_value := subject ->> 'lookup_app_user_id';
        IF identity_kind IS NULL
           OR identity_kind NOT IN ('legacy_user', 'purchase_principal')
           OR subject ->> 'identity_id' !~*
                '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           OR lookup_id_value IS NULL
           OR (
               identity_kind = 'legacy_user'
               AND pg_catalog.CHAR_LENGTH(lookup_id_value)
                    NOT BETWEEN 1 AND 1500
           )
           OR (
               identity_kind = 'purchase_principal'
               AND pg_catalog.CHAR_LENGTH(lookup_id_value)
                    NOT BETWEEN 1 AND 255
           )
           OR lookup_id_value ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;
        identity_id := (subject ->> 'identity_id')::UUID;
        IF identity_id = ANY(seen_identity_ids) THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;
        seen_identity_ids := pg_catalog.ARRAY_APPEND(
            seen_identity_ids,
            identity_id
        );

        IF identity_kind = 'purchase_principal' THEN
            INSERT INTO internal.purchase_principal_reconciliation_queue (
                purchase_principal_id,
                lookup_app_user_id,
                next_reconcile_at,
                updated_at
            )
            SELECT
                principals.id,
                principals.revenuecat_app_user_id,
                pg_catalog.NOW(),
                pg_catalog.CLOCK_TIMESTAMP()
            FROM internal.purchase_principals AS principals
            WHERE principals.id = identity_id
              AND principals.status = 'active'
              AND principals.revenuecat_app_user_id = lookup_id_value
            ON CONFLICT (purchase_principal_id) DO UPDATE
            SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
                next_reconcile_at = LEAST(
                    internal.purchase_principal_reconciliation_queue
                        .next_reconcile_at,
                    EXCLUDED.next_reconcile_at
                ),
                claim_token = NULL,
                claimed_at = NULL,
                claim_expires_at = NULL,
                updated_at = EXCLUDED.updated_at;
        ELSE
            INSERT INTO internal.revenuecat_reconciliation_queue (
                merian_user_id,
                lookup_app_user_id,
                next_reconcile_at,
                updated_at
            )
            SELECT
                users.id,
                lookup_id_value,
                pg_catalog.NOW(),
                pg_catalog.CLOCK_TIMESTAMP()
            FROM public.users AS users
            WHERE users.id = identity_id
            ON CONFLICT (merian_user_id) DO UPDATE
            SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
                next_reconcile_at = LEAST(
                    internal.revenuecat_reconciliation_queue.next_reconcile_at,
                    EXCLUDED.next_reconcile_at
                ),
                claim_token = NULL,
                claimed_at = NULL,
                claim_expires_at = NULL,
                updated_at = EXCLUDED.updated_at;
        END IF;

        IF FOUND THEN
            scheduled_count := scheduled_count + 1;
        END IF;
    END LOOP;
    RETURN scheduled_count;
END;
$function$;

-- The previous webhook bundle schedules by UUID candidates after every apply
-- and again on durable duplicate delivery. Preserve that signature, but route
-- only still-legacy identities through the new scheduler. The shared lock and
-- recheck prevent an old bundle from recreating a legacy queue after stable
-- principal activation.
CREATE OR REPLACE FUNCTION public.schedule_revenuecat_reconciliation(
    p_subjects JSONB
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    subject RECORD;
    resolved RECORD;
    source_subject JSONB;
    resolver_subjects JSONB := '[]'::JSONB;
    identity_subjects JSONB := '[]'::JSONB;
    legacy_user_ids UUID[] := ARRAY[]::UUID[];
    seen_subject_kinds TEXT[] := ARRAY[]::TEXT[];
    subject_kind_value TEXT;
    lookup_app_user_id_value TEXT;
    distinct_candidate_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    IF pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 2 THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
            USING ERRCODE = '22023';
    END IF;

    FOR subject IN
        SELECT item.value, item.position::INTEGER
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        IF pg_catalog.JSONB_TYPEOF(subject.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'candidate_user_ids'
           ) IS DISTINCT FROM 'array'
           OR pg_catalog.JSONB_ARRAY_LENGTH(
               subject.value -> 'candidate_user_ids'
           ) NOT BETWEEN 1 AND 32
           OR EXISTS (
               SELECT 1
               FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                   subject.value -> 'candidate_user_ids'
               ) AS candidate(value)
               WHERE candidate.value !~*
                    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                  OR pg_catalog.LOWER(candidate.value) =
                    '00000000-0000-0000-0000-000000000000'
           ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;

        subject_kind_value := subject.value ->> 'subject_kind';
        lookup_app_user_id_value := subject.value ->> 'lookup_app_user_id';
        IF subject_kind_value IS NULL
           OR subject_kind_value NOT IN (
               'customer',
               'transfer_source',
               'transfer_destination'
           )
           OR subject_kind_value = ANY(seen_subject_kinds)
           OR lookup_app_user_id_value IS NULL
           OR pg_catalog.CHAR_LENGTH(lookup_app_user_id_value)
                NOT BETWEEN 1 AND 1500
           OR lookup_app_user_id_value ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;
        seen_subject_kinds := pg_catalog.ARRAY_APPEND(
            seen_subject_kinds,
            subject_kind_value
        );

        SELECT pg_catalog.COUNT(DISTINCT candidate.value::UUID)::INTEGER
        INTO distinct_candidate_count
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            subject.value -> 'candidate_user_ids'
        ) AS candidate(value);
        IF distinct_candidate_count <>
                pg_catalog.JSONB_ARRAY_LENGTH(
                    subject.value -> 'candidate_user_ids'
                ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;

        resolver_subjects := resolver_subjects ||
            pg_catalog.JSONB_BUILD_ARRAY(
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', subject_kind_value,
                    'identifiers', subject.value -> 'candidate_user_ids'
                )
            );
    END LOOP;

    BEGIN
        FOR resolved IN
            SELECT result.*
            FROM public.resolve_revenuecat_identity_subjects(
                resolver_subjects
            ) AS result
            ORDER BY result.subject_position
        LOOP
            IF resolved.identity_kind <> 'legacy_user' THEN
                RAISE EXCEPTION 'revenuecat_legacy_identity_conflict'
                    USING ERRCODE = '55000';
            END IF;
            legacy_user_ids := pg_catalog.ARRAY_APPEND(
                legacy_user_ids,
                resolved.identity_id
            );
            source_subject := p_subjects -> (resolved.subject_position - 1);
            identity_subjects := identity_subjects ||
                pg_catalog.JSONB_BUILD_ARRAY(
                    pg_catalog.JSONB_BUILD_OBJECT(
                        'subject_kind', resolved.subject_kind,
                        'identity_kind', 'legacy_user',
                        'identity_id', resolved.identity_id,
                        'lookup_app_user_id',
                            source_subject ->> 'lookup_app_user_id'
                    )
                );
        END LOOP;
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM = 'revenuecat_identity_mapping_ambiguous' THEN
                RAISE EXCEPTION 'revenuecat_user_mapping_ambiguous'
                    USING ERRCODE = 'P0001';
            END IF;
            RAISE;
        WHEN SQLSTATE '22023' THEN
            IF SQLERRM = 'revenuecat_invalid_identity_subjects' THEN
                RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                    USING ERRCODE = '22023';
            END IF;
            RAISE;
    END;

    PERFORM internal.lock_legacy_revenuecat_compatibility_users(
        legacy_user_ids
    );
    RETURN public.schedule_revenuecat_identity_reconciliation(
        identity_subjects
    );
END;
$function$;

COMMENT ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB) IS
    'Service-only compatibility scheduler for the previous webhook bundle. It preserves the verified provider lookup, routes still-legacy UUIDs through the identity scheduler, and rejects active stable-principal relationships under the shared cutover and principal-before-user locks.';

CREATE OR REPLACE FUNCTION public.claim_purchase_principal_reconciliations(
    p_limit INTEGER DEFAULT 6
)
RETURNS TABLE (
    purchase_principal_id UUID,
    lookup_app_user_id TEXT,
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    allow_non_subscription_pass_grant BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
        RAISE EXCEPTION 'purchase_principal_invalid_reconciliation_limit'
            USING ERRCODE = '22023';
    END IF;

    -- A pending row has not mutated RevenueCat and has no durable StoreKit
    -- state. If its device disappears before completion, reclaim it after a
    -- full day so a lost capability cannot create a permanent health alert or
    -- reserve an Auth-UUID provider ID forever. Completion and cleanup contend
    -- on the same principal row; SKIP LOCKED never interrupts active work.
    WITH abandoned AS (
        SELECT principal.id
        FROM internal.purchase_principals AS principal
        WHERE principal.status = 'pending'
          AND principal.updated_at < pg_catalog.NOW() - INTERVAL '24 hours'
          AND NOT EXISTS (
              SELECT 1
              FROM internal.purchase_principal_bindings AS binding
              WHERE binding.purchase_principal_id = principal.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.purchase_principal_store_state AS state
              WHERE state.purchase_principal_id = principal.id
          )
        ORDER BY principal.updated_at, principal.id
        FOR UPDATE OF principal SKIP LOCKED
        LIMIT 100
    )
    DELETE FROM internal.purchase_principals AS principal
    USING abandoned
    WHERE principal.id = abandoned.id;

    UPDATE internal.purchase_principal_reconciliation_queue AS queue
    SET claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        next_reconcile_at = LEAST(
            queue.next_reconcile_at,
            pg_catalog.NOW()
        ),
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE queue.claim_token IS NOT NULL
      AND queue.claim_expires_at <= pg_catalog.NOW();

    RETURN QUERY
    WITH due AS (
        SELECT queue.purchase_principal_id
        FROM internal.purchase_principal_reconciliation_queue AS queue
        JOIN internal.purchase_principals AS principal
          ON principal.id = queue.purchase_principal_id
         AND principal.status = 'active'
        WHERE queue.claim_token IS NULL
          AND queue.next_reconcile_at <= pg_catalog.NOW()
        ORDER BY queue.next_reconcile_at, queue.purchase_principal_id
        FOR UPDATE OF queue SKIP LOCKED
        LIMIT p_limit
    ),
    claimed AS (
        UPDATE internal.purchase_principal_reconciliation_queue AS queue
        SET claim_token = extensions.gen_random_uuid(),
            claimed_at = pg_catalog.NOW(),
            claim_expires_at = pg_catalog.NOW() + INTERVAL '2 minutes',
            updated_at = pg_catalog.CLOCK_TIMESTAMP()
        FROM due
        WHERE queue.purchase_principal_id = due.purchase_principal_id
        RETURNING
            queue.purchase_principal_id,
            queue.lookup_app_user_id,
            queue.claim_token,
            queue.claim_expires_at
    )
    SELECT
        claimed.purchase_principal_id,
        claimed.lookup_app_user_id,
        claimed.claim_token,
        claimed.claim_expires_at,
        state.allow_non_subscription_pass_grant
    FROM claimed
    JOIN internal.purchase_principal_store_state AS state
      ON state.purchase_principal_id = claimed.purchase_principal_id
    ORDER BY claimed.purchase_principal_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.apply_purchase_principal_reconciliation(
    p_purchase_principal_id UUID,
    p_claim_token UUID,
    p_authoritative_snapshot_at_ms BIGINT,
    p_store_tier TEXT,
    p_store_expires_at TIMESTAMPTZ,
    p_account_grant_tier TEXT,
    p_account_grant_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    principal internal.purchase_principals%ROWTYPE;
    queue_row internal.purchase_principal_reconciliation_queue%ROWTYPE;
    helper_result RECORD;
BEGIN
    PERFORM internal.require_service_role();
    IF p_purchase_principal_id IS NULL OR p_claim_token IS NULL THEN
        RAISE EXCEPTION 'purchase_principal_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = p_purchase_principal_id
      AND principals.status = 'active'
    FOR UPDATE;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id IN (
        SELECT binding.auth_user_id
        FROM internal.purchase_principal_bindings AS binding
        WHERE binding.purchase_principal_id = principal.id
        UNION
        SELECT principal.account_grant_owner_user_id
    )
    ORDER BY users.id
    FOR UPDATE;

    SELECT queue.*
    INTO STRICT queue_row
    FROM internal.purchase_principal_reconciliation_queue AS queue
    WHERE queue.purchase_principal_id = principal.id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()
    FOR UPDATE;

    SELECT result.*
    INTO STRICT helper_result
    FROM internal.apply_purchase_principal_snapshot(
        principal.id,
        'principal-reconcile:' || principal.id::TEXT || ':' ||
            p_authoritative_snapshot_at_ms::TEXT,
        0,
        p_authoritative_snapshot_at_ms,
        p_store_tier,
        p_store_expires_at,
        NULL,
        FALSE,
        p_account_grant_tier,
        p_account_grant_expires_at
    ) AS result;

    UPDATE internal.purchase_principal_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW() + CASE
            WHEN p_store_tier = 'pro' OR p_account_grant_tier = 'pro'
                THEN INTERVAL '6 hours'
            ELSE INTERVAL '24 hours'
        END,
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_snapshot_at_ms = GREATEST(
            COALESCE(queue.last_snapshot_at_ms, 0),
            p_authoritative_snapshot_at_ms
        ),
        last_reconciled_at = pg_catalog.NOW(),
        last_error_code = NULL,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE queue.purchase_principal_id = principal.id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_principal_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;
    RETURN helper_result.state_applied;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fail_purchase_principal_reconciliation(
    p_purchase_principal_id UUID,
    p_claim_token UUID,
    p_error_code TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();
    IF p_purchase_principal_id IS NULL
       OR p_claim_token IS NULL
       OR p_error_code IS NULL
       OR pg_catalog.CHAR_LENGTH(p_error_code) NOT BETWEEN 1 AND 120
       OR p_error_code ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'purchase_principal_invalid_reconciliation_failure'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.purchase_principal_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW() + CASE
            WHEN queue.attempt_count < 2 THEN INTERVAL '1 minute'
            WHEN queue.attempt_count < 5 THEN INTERVAL '5 minutes'
            WHEN queue.attempt_count < 10 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END,
        attempt_count = LEAST(queue.attempt_count + 1, 100),
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = p_error_code,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE queue.purchase_principal_id = p_purchase_principal_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.NOW();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_principal_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_purchase_principal_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    active_principal_count BIGINT,
    pending_principal_count BIGINT,
    unbound_active_principal_count BIGINT,
    due_reconciliation_count BIGINT,
    expired_claim_count BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT,
    oldest_pending_at TIMESTAMPTZ,
    oldest_pending_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();
    RETURN QUERY
    WITH clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    ),
    principal_counts AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE principal.status = 'active'
            ) AS active_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE principal.status = 'pending'
            ) AS pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE principal.status = 'active'
                  AND binding.purchase_principal_id IS NULL
                  AND store_state.target_tier = 'pro'::public.subscription_tier_enum
                  AND (
                      store_state.target_expires_at IS NULL
                      OR store_state.target_expires_at > clock.observed_at
                  )
            ) AS unbound_count,
            pg_catalog.MIN(principal.created_at) FILTER (
                WHERE principal.status = 'pending'
            ) AS oldest_pending
        FROM internal.purchase_principals AS principal
        LEFT JOIN internal.purchase_principal_bindings AS binding
          ON binding.purchase_principal_id = principal.id
        LEFT JOIN internal.purchase_principal_store_state AS store_state
          ON store_state.purchase_principal_id = principal.id
        CROSS JOIN clock
    ),
    queue_health AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE queue.next_reconcile_at <= clock.observed_at
                  AND (
                      queue.claim_token IS NULL
                      OR queue.claim_expires_at <= clock.observed_at
                  )
            ) AS due_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE queue.claim_token IS NOT NULL
                  AND queue.claim_expires_at <= clock.observed_at
            ) AS expired_count,
            pg_catalog.MIN(queue.next_reconcile_at) FILTER (
                WHERE queue.next_reconcile_at <= clock.observed_at
                  AND (
                      queue.claim_token IS NULL
                      OR queue.claim_expires_at <= clock.observed_at
                  )
            ) AS oldest_due
        FROM internal.purchase_principal_reconciliation_queue AS queue
        CROSS JOIN clock
    )
    SELECT
        clock.observed_at,
        counts.active_count,
        counts.pending_count,
        counts.unbound_count,
        queue_health.due_count,
        queue_health.expired_count,
        queue_health.oldest_due,
        CASE WHEN queue_health.oldest_due IS NULL THEN NULL ELSE
            GREATEST(
                0,
                pg_catalog.FLOOR(EXTRACT(
                    EPOCH FROM (clock.observed_at - queue_health.oldest_due)
                ))::BIGINT
            )
        END,
        counts.oldest_pending,
        CASE WHEN counts.oldest_pending IS NULL THEN NULL ELSE
            GREATEST(
                0,
                pg_catalog.FLOOR(EXTRACT(
                    EPOCH FROM (clock.observed_at - counts.oldest_pending)
                ))::BIGINT
            )
        END
    FROM clock
    CROSS JOIN principal_counts AS counts
    CROSS JOIN queue_health;
END;
$function$;

-- During dual-read, the legacy worker writes its own provider input and then
-- recomputes the effective projection. This prevents a UUID customer repair
-- from overwriting a concurrently bound stable principal or account grant.
CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation(
    p_user_id UUID,
    p_claim_token UUID,
    p_authoritative_snapshot_at_ms BIGINT,
    p_target_tier TEXT,
    p_target_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    legacy_state internal.legacy_revenuecat_entitlement_state%ROWTYPE;
    target_tier public.subscription_tier_enum;
    seed_event_id TEXT;
    state_applied BOOLEAN := FALSE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL
       OR p_claim_token IS NULL
       OR p_authoritative_snapshot_at_ms IS NULL
       OR p_authoritative_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_target_tier NOT IN ('free', 'pro') THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;
    target_tier := p_target_tier::public.subscription_tier_enum;
    IF (target_tier = 'free'::public.subscription_tier_enum
            AND p_target_expires_at IS NOT NULL)
       OR (target_tier = 'pro'::public.subscription_tier_enum
            AND p_target_expires_at IS NOT NULL
            AND p_target_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            )) THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_user_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM 1
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    SELECT state.*
    INTO legacy_state
    FROM internal.legacy_revenuecat_entitlement_state AS state
    WHERE state.merian_user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND OR p_authoritative_snapshot_at_ms >
            legacy_state.authoritative_snapshot_at_ms THEN
        INSERT INTO internal.legacy_revenuecat_entitlement_state (
            merian_user_id,
            target_tier,
            target_expires_at,
            authoritative_snapshot_at_ms,
            last_event_id,
            last_event_timestamp_ms,
            updated_at
        )
        VALUES (
            p_user_id,
            target_tier,
            p_target_expires_at,
            p_authoritative_snapshot_at_ms,
            legacy_state.last_event_id,
            COALESCE(legacy_state.last_event_timestamp_ms, 0),
            pg_catalog.CLOCK_TIMESTAMP()
        )
        ON CONFLICT (merian_user_id) DO UPDATE
        SET target_tier = EXCLUDED.target_tier,
            target_expires_at = EXCLUDED.target_expires_at,
            authoritative_snapshot_at_ms =
                EXCLUDED.authoritative_snapshot_at_ms,
            updated_at = EXCLUDED.updated_at;

        IF legacy_state.merian_user_id IS NULL THEN
            seed_event_id := 'reconcile-seed:' || p_user_id::TEXT;
            INSERT INTO internal.revenuecat_webhook_events (
                event_id,
                event_timestamp_ms,
                event_type,
                payload_sha256,
                signature_timestamp_s,
                outcome,
                subject_count,
                applied_count,
                stale_count
            )
            VALUES (
                seed_event_id,
                p_authoritative_snapshot_at_ms,
                'RECONCILIATION',
                pg_catalog.REPEAT('0', 64),
                pg_catalog.FLOOR(
                    p_authoritative_snapshot_at_ms::NUMERIC / 1000
                )::BIGINT,
                'ignored',
                0,
                0,
                0
            )
            ON CONFLICT (event_id) DO NOTHING;
        END IF;

        INSERT INTO internal.revenuecat_customer_state (
            merian_user_id,
            last_event_id,
            last_event_timestamp_ms,
            last_authoritative_snapshot_at_ms,
            updated_at
        )
        VALUES (
            p_user_id,
            COALESCE(legacy_state.last_event_id, seed_event_id),
            COALESCE(
                legacy_state.last_event_timestamp_ms,
                p_authoritative_snapshot_at_ms
            ),
            p_authoritative_snapshot_at_ms,
            pg_catalog.CLOCK_TIMESTAMP()
        )
        ON CONFLICT (merian_user_id) DO UPDATE
        SET last_authoritative_snapshot_at_ms =
                EXCLUDED.last_authoritative_snapshot_at_ms,
            updated_at = EXCLUDED.updated_at;

        PERFORM internal.recompute_purchase_principal_entitlement(p_user_id);
        state_applied := TRUE;
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW() + CASE
            WHEN target_tier = 'pro'::public.subscription_tier_enum
                THEN INTERVAL '6 hours'
            ELSE INTERVAL '24 hours'
        END,
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_snapshot_at_ms = GREATEST(
            COALESCE(queue.last_snapshot_at_ms, 0),
            p_authoritative_snapshot_at_ms
        ),
        last_reconciled_at = pg_catalog.NOW(),
        last_error_code = NULL,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;
    RETURN state_applied;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_legacy_purchase_state(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.legacy_revenuecat_entitlement_state AS target_state
    SET target_tier = source_state.target_tier,
        target_expires_at = source_state.target_expires_at,
        authoritative_snapshot_at_ms =
            source_state.authoritative_snapshot_at_ms,
        last_event_id = source_state.last_event_id,
        last_event_timestamp_ms = source_state.last_event_timestamp_ms,
        updated_at = GREATEST(
            target_state.updated_at,
            source_state.updated_at
        )
    FROM internal.legacy_revenuecat_entitlement_state AS source_state
    WHERE target_state.merian_user_id = p_target_user_id
      AND source_state.merian_user_id = p_ghost_user_id
      AND (
          source_state.authoritative_snapshot_at_ms >
              target_state.authoritative_snapshot_at_ms
          OR (
              source_state.authoritative_snapshot_at_ms =
                  target_state.authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms >
                  target_state.last_event_timestamp_ms
          )
          OR (
              source_state.authoritative_snapshot_at_ms =
                  target_state.authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms =
                  target_state.last_event_timestamp_ms
              AND COALESCE(source_state.last_event_id, '')
                    COLLATE pg_catalog."C" >
                  COALESCE(target_state.last_event_id, '')
                    COLLATE pg_catalog."C"
          )
      );

    DELETE FROM internal.legacy_revenuecat_entitlement_state AS source_state
    USING internal.legacy_revenuecat_entitlement_state AS target_state
    WHERE source_state.merian_user_id = p_ghost_user_id
      AND target_state.merian_user_id = p_target_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION internal.merge_ghost_legacy_purchase_state(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

DO $extend_revenuecat_merge$
DECLARE
    function_definition TEXT;
    anchor TEXT :=
        '    DELETE FROM internal.revenuecat_reconciliation_queue AS source_queue';
    replacement TEXT :=
        '    PERFORM internal.merge_ghost_legacy_purchase_state('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id,'
        || pg_catalog.CHR(10)
        || '        p_target_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || anchor;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'internal.merge_ghost_revenuecat_state(uuid,uuid)'::REGPROCEDURE
    ) INTO STRICT function_definition;
    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_definition, anchor, '')
        )
    ) / pg_catalog.LENGTH(anchor) <> 1
       OR pg_catalog.STRPOS(
           function_definition,
           'merge_ghost_legacy_purchase_state('
       ) <> 0 THEN
        RAISE EXCEPTION 'ghost_merge_revenuecat_source_drift'
            USING ERRCODE = '55000';
    END IF;
    EXECUTE pg_catalog.REPLACE(
        function_definition,
        anchor,
        replacement
    );
END;
$extend_revenuecat_merge$;

-- The merge consumer historically locked Auth users before the policy-driven
-- reparent pass reached purchase-principal rows. Stable webhooks and resolver
-- completion use the opposite, principal-first order. Install the shared lock
-- helper before the existing Auth-row lock so concurrent delivery, resolution,
-- deletion, and Apple/Google continuation cannot deadlock or partially reorder.
DO $extend_ghost_merge_lock_order$
DECLARE
    function_definition TEXT;
    anchor TEXT :=
        '    PERFORM auth_user.id'
        || pg_catalog.CHR(10)
        || '    FROM auth.users AS auth_user'
        || pg_catalog.CHR(10)
        || '    WHERE auth_user.id IN (handoff_record.ghost_user_id, caller_id)';
    replacement TEXT :=
        '    PERFORM internal.lock_purchase_principals_for_auth_users('
        || pg_catalog.CHR(10)
        || '        ARRAY['
        || pg_catalog.CHR(10)
        || '            handoff_record.ghost_user_id,'
        || pg_catalog.CHR(10)
        || '            caller_id'
        || pg_catalog.CHR(10)
        || '        ]::UUID[]'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || anchor;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.consume_ghost_profile_merge_handoff(uuid,text)'::REGPROCEDURE
    ) INTO STRICT function_definition;
    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_definition, anchor, '')
        )
    ) / pg_catalog.LENGTH(anchor) <> 1
       OR pg_catalog.STRPOS(
           function_definition,
           'lock_purchase_principals_for_auth_users('
       ) <> 0 THEN
        RAISE EXCEPTION 'ghost_merge_purchase_principal_source_drift'
            USING ERRCODE = '55000';
    END IF;
    EXECUTE pg_catalog.REPLACE(
        function_definition,
        anchor,
        replacement
    );
END;
$extend_ghost_merge_lock_order$;

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
        'internal', 'legacy_revenuecat_entitlement_state', 'merian_user_id',
        'public', 'users', 'id', 'handler_then_reparent', 251,
        'revenuecat_state',
        'The RevenueCat merge handler first coalesces legacy input watermarks; any non-conflicting source row then follows the permanent profile.'
    ),
    (
        'internal', 'purchase_principals', 'account_grant_owner_user_id',
        'public', 'users', 'id', 'reparent', 505, NULL,
        'A purchase principal created while signed out adopts the permanent account as the fixed owner of any imported legacy promotion.'
    ),
    (
        'internal', 'purchase_principal_bindings', 'auth_user_id',
        'public', 'users', 'id', 'reparent', 506, NULL,
        'The stable purchase principal follows the permanent Auth profile; a binding trigger advances generation and records the transition.'
    ),
    (
        'internal', 'account_access_grants', 'account_user_id',
        'public', 'users', 'id', 'reparent', 507, NULL,
        'Account-scoped beta, promotion, and support grants follow the permanent account during an authorized profile upgrade.'
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

SELECT internal.assert_ghost_profile_merge_reference_policy_coverage();

REVOKE ALL ON FUNCTION public.begin_purchase_principal_resolution(
    UUID, TEXT, INTEGER, BIGINT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_purchase_principal_resolution(
    UUID, UUID, TEXT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN, TEXT,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_account_access_grant(
    UUID, TEXT, TIMESTAMPTZ, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.revoke_account_access_grant(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.resolve_revenuecat_identity_subjects(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_revenuecat_identity_state(
    TEXT, BIGINT, TEXT, TEXT, BIGINT, JSONB
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT, BIGINT, TEXT, TEXT, BIGINT, JSONB
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.schedule_revenuecat_identity_reconciliation(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_purchase_principal_reconciliations(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_purchase_principal_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fail_purchase_principal_reconciliation(
    UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_purchase_principal_health()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.refresh_expired_entitlement_projection(
    UUID, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.begin_purchase_principal_resolution(
    UUID, TEXT, INTEGER, BIGINT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_purchase_principal_resolution(
    UUID, UUID, TEXT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN, TEXT,
    TIMESTAMPTZ
) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_account_access_grant(
    UUID, TEXT, TIMESTAMPTZ, TEXT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_account_access_grant(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.resolve_revenuecat_identity_subjects(JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_identity_state(
    TEXT, BIGINT, TEXT, TEXT, BIGINT, JSONB
) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT, BIGINT, TEXT, TEXT, BIGINT, JSONB
) TO service_role;
GRANT EXECUTE ON FUNCTION public.schedule_revenuecat_identity_reconciliation(JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_purchase_principal_reconciliations(INTEGER)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_purchase_principal_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ, TEXT, TIMESTAMPTZ
) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_purchase_principal_reconciliation(
    UUID, UUID, TEXT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_purchase_principal_health()
    TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_expired_entitlement_projection(
    UUID, TIMESTAMPTZ
) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.begin_purchase_principal_resolution(uuid,text,integer,bigint)',
        'Authenticated resolver prepares or reuses a server-owned stable purchase principal from a hashed installation capability.'
    ),
    (
        'service_role',
        'public.complete_purchase_principal_resolution(uuid,uuid,text,bigint,bigint,text,timestamp with time zone,boolean,text,timestamp with time zone)',
        'Authenticated resolver attests provider state and atomically binds the stable purchase principal to the JWT-derived Auth user.'
    ),
    (
        'service_role',
        'public.record_account_access_grant(uuid,text,timestamp with time zone,text)',
        'Reviewed operator workflow records one audited account-scoped beta, promotion, or support grant.'
    ),
    (
        'service_role',
        'public.revoke_account_access_grant(uuid)',
        'Reviewed operator workflow revokes one audited account-scoped access grant.'
    ),
    (
        'service_role',
        'public.resolve_revenuecat_identity_subjects(jsonb)',
        'Signed webhook resolves provider identifiers through private purchase-principal mappings before legacy UUID fallback.'
    ),
    (
        'service_role',
        'public.apply_revenuecat_identity_state(text,bigint,text,text,bigint,jsonb)',
        'Signed webhook atomically records stable StoreKit/account-grant state or legacy provider state.'
    ),
    (
        'service_role',
        'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)',
        'Previous webhook bundles delegate legacy UUID payloads into the separated identity ledger and fail closed on stable-principal matches.'
    ),
    (
        'service_role',
        'public.schedule_revenuecat_identity_reconciliation(jsonb)',
        'Webhook schedules repair in the correct stable-principal or legacy-user queue.'
    ),
    (
        'service_role',
        'public.schedule_revenuecat_reconciliation(jsonb)',
        'Previous webhook bundles route still-legacy UUIDs through the identity scheduler and fail closed after stable-principal activation.'
    ),
    (
        'service_role',
        'public.claim_purchase_principal_reconciliations(integer)',
        'Scheduled worker leases one bounded SKIP LOCKED wave of stable purchase principals.'
    ),
    (
        'service_role',
        'public.apply_purchase_principal_reconciliation(uuid,uuid,bigint,text,timestamp with time zone,text,timestamp with time zone)',
        'Scheduled worker applies a claim-fenced authoritative stable-principal snapshot.'
    ),
    (
        'service_role',
        'public.fail_purchase_principal_reconciliation(uuid,uuid,text)',
        'Scheduled worker releases a failed stable-principal lease with bounded backoff.'
    ),
    (
        'service_role',
        'public.get_purchase_principal_health()',
        'Scheduled monitor reads aggregate stable-principal lifecycle and reconciliation health without identity data.'
    ),
    (
        'service_role',
        'public.refresh_expired_entitlement_projection(uuid,timestamp with time zone)',
        'Expiration worker recomputes effective access across legacy, stable StoreKit, and account-grant inputs.'
    ),
    (
        'service_role',
        'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)',
        'Legacy reconciliation writes a separate provider input before recomputing the dual-read effective entitlement.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;

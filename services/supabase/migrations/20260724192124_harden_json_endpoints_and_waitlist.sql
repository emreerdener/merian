-- Bound the public waitlist at the database boundary. PostgreSQL rate-limits
-- the pre-Turnstile claim, then the web route validates Turnstile before
-- calling the service-only insertion routine. PostgreSQL owns atomic
-- uniqueness and request-growth limits.

ALTER TABLE public.beta_waitlist_signups
    ADD CONSTRAINT beta_waitlist_signups_email_shape_check
    CHECK (
        email = pg_catalog.LOWER(pg_catalog.BTRIM(email))
        AND pg_catalog.CHAR_LENGTH(email) BETWEEN 3 AND 254
        AND email !~ '[[:cntrl:][:space:]]'
        AND email !~ '\.\.'
        AND email ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9][a-z0-9.-]*\.[a-z]{2,63}$'
        AND pg_catalog.CHAR_LENGTH(
            pg_catalog.SPLIT_PART(email, '@', 1)
        ) BETWEEN 1 AND 64
        AND pg_catalog.SPLIT_PART(email, '@', 1) !~ '(^\.|\.$)'
        AND pg_catalog.CHAR_LENGTH(
            pg_catalog.SPLIT_PART(email, '@', 2)
        ) BETWEEN 3 AND 253
        AND pg_catalog.SPLIT_PART(email, '@', 2)
            !~ '(^|\.)-|-(\.|$)'
        AND pg_catalog.SPLIT_PART(email, '@', 2) !~ '[^.]{64}'
    ) NOT VALID,
    ADD CONSTRAINT beta_waitlist_signups_source_shape_check
    CHECK (
        pg_catalog.CHAR_LENGTH(source) BETWEEN 1 AND 64
        AND source !~ '[[:cntrl:]]'
    ) NOT VALID,
    ADD CONSTRAINT beta_waitlist_signups_user_agent_shape_check
    CHECK (
        user_agent IS NULL
        OR (
            pg_catalog.CHAR_LENGTH(user_agent) BETWEEN 1 AND 512
            AND user_agent !~ '[[:cntrl:]]'
        )
    ) NOT VALID;

COMMENT ON CONSTRAINT beta_waitlist_signups_email_shape_check
    ON public.beta_waitlist_signups IS
    'New waitlist rows must contain one canonical, bounded email address. The constraint is NOT VALID only to avoid blocking deployment on historical data; it still protects every new write.';

REVOKE ALL ON TABLE public.beta_waitlist_signups
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.beta_waitlist_rate_counters (
    scope_type TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    window_started_at TIMESTAMPTZ NOT NULL,
    request_count INTEGER NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (scope_type, scope_key, window_started_at),
    CONSTRAINT beta_waitlist_rate_counters_scope_type_check
        CHECK (
            scope_type IN (
                'challenge_ip_10m',
                'challenge_ip_day',
                'ip_10m',
                'ip_day',
                'global_day'
            )
        ),
    CONSTRAINT beta_waitlist_rate_counters_scope_key_check
        CHECK (pg_catalog.CHAR_LENGTH(scope_key) BETWEEN 1 AND 64),
    CONSTRAINT beta_waitlist_rate_counters_request_count_check
        CHECK (request_count > 0)
);

CREATE INDEX beta_waitlist_rate_counters_updated_at_idx
    ON internal.beta_waitlist_rate_counters (updated_at);

ALTER TABLE internal.beta_waitlist_rate_counters
    ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE internal.beta_waitlist_rate_counters IS
    'Transactionally enforced public waitlist growth limits. IP scope keys are daily rotating HMACs; raw client addresses and Turnstile tokens are never stored.';

REVOKE ALL ON TABLE internal.beta_waitlist_rate_counters
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_beta_waitlist_challenge_attempt(
    p_ip_hash TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
    request_timestamp TIMESTAMPTZ := pg_catalog.NOW();
    ten_minute_window TIMESTAMPTZ;
    day_window TIMESTAMPTZ;
    new_counter_value INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_waitlist_ip_hash'
            USING ERRCODE = '22023';
    END IF;

    ten_minute_window := pg_catalog.DATE_BIN(
        INTERVAL '10 minutes',
        request_timestamp,
        TIMESTAMPTZ '2001-01-01 00:00:00+00'
    );
    day_window := pg_catalog.DATE_TRUNC(
        'day',
        request_timestamp AT TIME ZONE 'UTC'
    ) AT TIME ZONE 'UTC';

    new_counter_value := NULL;
    INSERT INTO internal.beta_waitlist_rate_counters AS counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        'challenge_ip_10m',
        p_ip_hash,
        ten_minute_window,
        1,
        request_timestamp
    )
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = counters.request_count + 1,
        updated_at = EXCLUDED.updated_at
    WHERE counters.request_count < 20
    RETURNING request_count INTO new_counter_value;

    IF new_counter_value IS NULL THEN
        RAISE EXCEPTION 'waitlist_challenge_rate_limited'
            USING ERRCODE = 'P0001';
    END IF;

    new_counter_value := NULL;
    INSERT INTO internal.beta_waitlist_rate_counters AS counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        'challenge_ip_day',
        p_ip_hash,
        day_window,
        1,
        request_timestamp
    )
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = counters.request_count + 1,
        updated_at = EXCLUDED.updated_at
    WHERE counters.request_count < 100
    RETURNING request_count INTO new_counter_value;

    IF new_counter_value IS NULL THEN
        RAISE EXCEPTION 'waitlist_challenge_rate_limited'
            USING ERRCODE = 'P0001';
    END IF;

    WITH expired_counters AS (
        SELECT counters.ctid
        FROM internal.beta_waitlist_rate_counters AS counters
        WHERE counters.updated_at < request_timestamp - INTERVAL '2 days'
        ORDER BY counters.updated_at
        LIMIT 500
        FOR UPDATE SKIP LOCKED
    )
    DELETE FROM internal.beta_waitlist_rate_counters AS counters
    USING expired_counters
    WHERE counters.ctid = expired_counters.ctid;
END;
$$;

COMMENT ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT)
    IS 'Service-only distributed preflight limiting how often one HMAC-scoped network may invoke Turnstile Siteverify.';

REVOKE ALL ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.claim_beta_waitlist_challenge_attempt(TEXT)
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.claim_beta_waitlist_challenge_attempt(text)',
    'Naturebook web waitlist; distributed pre-Turnstile request limiter.'
)
ON CONFLICT (role_name, routine_signature)
DO UPDATE SET purpose = EXCLUDED.purpose;

CREATE OR REPLACE FUNCTION public.submit_beta_waitlist_signup(
    p_email TEXT,
    p_ip_hash TEXT,
    p_user_agent TEXT,
    p_source TEXT DEFAULT 'web_waitlist'
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
    request_timestamp TIMESTAMPTZ := pg_catalog.NOW();
    ten_minute_window TIMESTAMPTZ;
    day_window TIMESTAMPTZ;
    inserted_count INTEGER := 0;
    new_counter_value INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_email IS NULL
       OR p_email IS DISTINCT FROM pg_catalog.LOWER(pg_catalog.BTRIM(p_email))
       OR pg_catalog.CHAR_LENGTH(p_email) NOT BETWEEN 3 AND 254
       OR p_email ~ '[[:cntrl:][:space:]]'
       OR p_email ~ '\.\.'
       OR p_email !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9][a-z0-9.-]*\.[a-z]{2,63}$'
       OR pg_catalog.CHAR_LENGTH(
           pg_catalog.SPLIT_PART(p_email, '@', 1)
       ) NOT BETWEEN 1 AND 64
       OR pg_catalog.SPLIT_PART(p_email, '@', 1) ~ '(^\.|\.$)'
       OR pg_catalog.CHAR_LENGTH(
           pg_catalog.SPLIT_PART(p_email, '@', 2)
       ) NOT BETWEEN 3 AND 253
       OR pg_catalog.SPLIT_PART(p_email, '@', 2)
            ~ '(^|\.)-|-(\.|$)'
       OR pg_catalog.SPLIT_PART(p_email, '@', 2) ~ '[^.]{64}' THEN
        RAISE EXCEPTION 'invalid_waitlist_email'
            USING ERRCODE = '22023';
    END IF;

    IF p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_waitlist_ip_hash'
            USING ERRCODE = '22023';
    END IF;

    IF p_source IS DISTINCT FROM 'web_waitlist' THEN
        RAISE EXCEPTION 'invalid_waitlist_source'
            USING ERRCODE = '22023';
    END IF;

    IF p_user_agent IS NOT NULL
       AND (
           pg_catalog.CHAR_LENGTH(p_user_agent) NOT BETWEEN 1 AND 512
           OR p_user_agent ~ '[[:cntrl:]]'
       ) THEN
        RAISE EXCEPTION 'invalid_waitlist_user_agent'
            USING ERRCODE = '22023';
    END IF;

    ten_minute_window := pg_catalog.DATE_BIN(
        INTERVAL '10 minutes',
        request_timestamp,
        TIMESTAMPTZ '2001-01-01 00:00:00+00'
    );
    day_window := pg_catalog.DATE_TRUNC(
        'day',
        request_timestamp AT TIME ZONE 'UTC'
    ) AT TIME ZONE 'UTC';

    new_counter_value := NULL;
    INSERT INTO internal.beta_waitlist_rate_counters AS counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES ('ip_10m', p_ip_hash, ten_minute_window, 1, request_timestamp)
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = counters.request_count + 1,
        updated_at = EXCLUDED.updated_at
    WHERE counters.request_count < 5
    RETURNING request_count INTO new_counter_value;

    IF new_counter_value IS NULL THEN
        RAISE EXCEPTION 'waitlist_ip_rate_limited'
            USING ERRCODE = 'P0001';
    END IF;

    new_counter_value := NULL;
    INSERT INTO internal.beta_waitlist_rate_counters AS counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES ('ip_day', p_ip_hash, day_window, 1, request_timestamp)
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = counters.request_count + 1,
        updated_at = EXCLUDED.updated_at
    WHERE counters.request_count < 20
    RETURNING request_count INTO new_counter_value;

    IF new_counter_value IS NULL THEN
        RAISE EXCEPTION 'waitlist_ip_rate_limited'
            USING ERRCODE = 'P0001';
    END IF;

    WITH expired_counters AS (
        SELECT counters.ctid
        FROM internal.beta_waitlist_rate_counters AS counters
        WHERE counters.updated_at < request_timestamp - INTERVAL '2 days'
        ORDER BY counters.updated_at
        LIMIT 500
        FOR UPDATE SKIP LOCKED
    )
    DELETE FROM internal.beta_waitlist_rate_counters AS counters
    USING expired_counters
    WHERE counters.ctid = expired_counters.ctid;

    -- Count every verified attempt against the IP budget, but count only newly
    -- inserted addresses against the finite database-growth budget.
    INSERT INTO public.beta_waitlist_signups (
        email,
        source,
        user_agent
    )
    VALUES (
        p_email,
        p_source,
        p_user_agent
    )
    ON CONFLICT (email_normalized) DO NOTHING;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;

    -- The public response is identical for new and existing addresses.
    IF inserted_count = 0 THEN
        RETURN 'already_joined';
    END IF;

    new_counter_value := NULL;
    INSERT INTO internal.beta_waitlist_rate_counters AS counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES ('global_day', 'global', day_window, 1, request_timestamp)
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = counters.request_count + 1,
        updated_at = EXCLUDED.updated_at
    WHERE counters.request_count < 2000
    RETURNING request_count INTO new_counter_value;

    IF new_counter_value IS NULL THEN
        RAISE EXCEPTION 'waitlist_global_rate_limited'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN 'inserted';
END;
$$;

COMMENT ON FUNCTION public.submit_beta_waitlist_signup(TEXT, TEXT, TEXT, TEXT)
    IS 'Service-only waitlist insertion boundary with canonical field limits and transactional per-IP/global growth caps. The caller must verify Turnstile before invocation.';

REVOKE ALL ON FUNCTION public.submit_beta_waitlist_signup(
    TEXT,
    TEXT,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.submit_beta_waitlist_signup(
    TEXT,
    TEXT,
    TEXT,
    TEXT
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.submit_beta_waitlist_signup(text,text,text,text)',
    'Naturebook web waitlist; Turnstile-verified, HMAC-scoped, atomic bounded insertion.'
)
ON CONFLICT (role_name, routine_signature)
DO UPDATE SET purpose = EXCLUDED.purpose;

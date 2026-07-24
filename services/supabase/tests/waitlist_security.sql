\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_ip_hash TEXT := pg_catalog.REPEAT('a', 64);
    global_test_ip_hash TEXT := pg_catalog.REPEAT('b', 64);
    daily_test_ip_hash TEXT := pg_catalog.REPEAT('c', 64);
    challenge_test_ip_hash TEXT := pg_catalog.REPEAT('d', 64);
    challenge_daily_test_ip_hash TEXT := pg_catalog.REPEAT('e', 64);
    result TEXT;
    ten_minute_window TIMESTAMPTZ;
    day_window TIMESTAMPTZ;
    counter_value INTEGER;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.submit_beta_waitlist_signup(text,text,text,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_beta_waitlist_challenge_attempt(text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'waitlist RPC has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.beta_waitlist_signups',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.beta_waitlist_rate_counters',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.beta_waitlist_signups',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'waitlist tables are directly exposed to API roles';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS relations
        JOIN pg_catalog.pg_namespace AS namespaces
          ON namespaces.oid = relations.relnamespace
        WHERE namespaces.nspname = 'internal'
          AND relations.relname = 'beta_waitlist_rate_counters'
          AND relations.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'waitlist rate counters do not have RLS enabled';
    END IF;

    DELETE FROM public.beta_waitlist_signups
    WHERE email IN (
        'waitlist-contract@example.invalid',
        'waitlist-blocked@example.invalid',
        'waitlist-daily-blocked@example.invalid',
        'waitlist-global-blocked@example.invalid',
        'INVALID WAITLIST EMAIL',
        'invalid-source@example.invalid',
        'invalid-agent@example.invalid'
    );
    DELETE FROM internal.beta_waitlist_rate_counters
    WHERE scope_key IN (
        test_ip_hash,
        daily_test_ip_hash,
        global_test_ip_hash,
        challenge_test_ip_hash,
        challenge_daily_test_ip_hash,
        'global'
    );

    BEGIN
        INSERT INTO public.beta_waitlist_signups (email, source)
        VALUES ('INVALID WAITLIST EMAIL', 'web_waitlist');
        RAISE EXCEPTION 'invalid waitlist row bypassed schema checks';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    BEGIN
        INSERT INTO public.beta_waitlist_signups (email, source)
        VALUES ('invalid-source@example.invalid', '');
        RAISE EXCEPTION 'invalid waitlist source bypassed schema checks';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    BEGIN
        INSERT INTO public.beta_waitlist_signups (email, source, user_agent)
        VALUES (
            'invalid-agent@example.invalid',
            'web_waitlist',
            E'invalid\nagent'
        );
        RAISE EXCEPTION 'invalid waitlist user agent bypassed schema checks';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    result := public.submit_beta_waitlist_signup(
        'waitlist-contract@example.invalid',
        test_ip_hash,
        'pgTAP waitlist contract',
        'web_waitlist'
    );
    IF result <> 'inserted' THEN
        RAISE EXCEPTION 'first waitlist signup was not inserted';
    END IF;

    FOR counter_value IN 1..4 LOOP
        result := public.submit_beta_waitlist_signup(
            'waitlist-contract@example.invalid',
            test_ip_hash,
            'pgTAP waitlist contract',
            'web_waitlist'
        );
        IF result <> 'already_joined' THEN
            RAISE EXCEPTION 'duplicate waitlist signup changed public outcome';
        END IF;
    END LOOP;

    BEGIN
        PERFORM public.submit_beta_waitlist_signup(
            'waitlist-blocked@example.invalid',
            test_ip_hash,
            'pgTAP waitlist contract',
            'web_waitlist'
        );
        RAISE EXCEPTION 'sixth ten-minute request bypassed IP rate limit';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'waitlist_ip_rate_limited' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (
        SELECT 1
        FROM public.beta_waitlist_signups AS signups
        WHERE signups.email = 'waitlist-blocked@example.invalid'
    ) THEN
        RAISE EXCEPTION 'rate-limited signup was not rolled back';
    END IF;

    ten_minute_window := pg_catalog.DATE_BIN(
        INTERVAL '10 minutes',
        pg_catalog.NOW(),
        TIMESTAMPTZ '2001-01-01 00:00:00+00'
    );
    day_window := pg_catalog.DATE_TRUNC(
        'day',
        pg_catalog.NOW() AT TIME ZONE 'UTC'
    ) AT TIME ZONE 'UTC';

    FOR counter_value IN 1..20 LOOP
        PERFORM public.claim_beta_waitlist_challenge_attempt(
            challenge_test_ip_hash
        );
    END LOOP;

    BEGIN
        PERFORM public.claim_beta_waitlist_challenge_attempt(
            challenge_test_ip_hash
        );
        RAISE EXCEPTION 'pre-Turnstile ten-minute limit was bypassed';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'waitlist_challenge_rate_limited' THEN
                RAISE;
            END IF;
    END;

    SELECT counters.request_count
    INTO STRICT counter_value
    FROM internal.beta_waitlist_rate_counters AS counters
    WHERE counters.scope_type = 'challenge_ip_10m'
      AND counters.scope_key = challenge_test_ip_hash
      AND counters.window_started_at = ten_minute_window;
    IF counter_value <> 20 THEN
        RAISE EXCEPTION 'pre-Turnstile counter exceeded its hard limit';
    END IF;

    INSERT INTO internal.beta_waitlist_rate_counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        'challenge_ip_day',
        challenge_daily_test_ip_hash,
        day_window,
        100,
        pg_catalog.NOW()
    );

    BEGIN
        PERFORM public.claim_beta_waitlist_challenge_attempt(
            challenge_daily_test_ip_hash
        );
        RAISE EXCEPTION 'pre-Turnstile daily limit was bypassed';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'waitlist_challenge_rate_limited' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (
        SELECT 1
        FROM internal.beta_waitlist_rate_counters AS counters
        WHERE counters.scope_type = 'challenge_ip_10m'
          AND counters.scope_key = challenge_daily_test_ip_hash
    ) THEN
        RAISE EXCEPTION 'daily challenge denial left a partial counter';
    END IF;

    SELECT counters.request_count
    INTO STRICT counter_value
    FROM internal.beta_waitlist_rate_counters AS counters
    WHERE counters.scope_type = 'ip_10m'
      AND counters.scope_key = test_ip_hash
      AND counters.window_started_at = ten_minute_window;
    IF counter_value <> 5 THEN
        RAISE EXCEPTION 'ten-minute counter did not charge every attempt';
    END IF;

    INSERT INTO internal.beta_waitlist_rate_counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        'ip_day',
        daily_test_ip_hash,
        day_window,
        20,
        pg_catalog.NOW()
    );

    BEGIN
        PERFORM public.submit_beta_waitlist_signup(
            'waitlist-daily-blocked@example.invalid',
            daily_test_ip_hash,
            'pgTAP waitlist contract',
            'web_waitlist'
        );
        RAISE EXCEPTION 'daily request bypassed IP rate limit';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'waitlist_ip_rate_limited' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (
        SELECT 1
        FROM public.beta_waitlist_signups AS signups
        WHERE signups.email = 'waitlist-daily-blocked@example.invalid'
    ) OR EXISTS (
        SELECT 1
        FROM internal.beta_waitlist_rate_counters AS counters
        WHERE counters.scope_type = 'ip_10m'
          AND counters.scope_key = daily_test_ip_hash
    ) THEN
        RAISE EXCEPTION 'daily-rate-limited transaction left partial state';
    END IF;

    INSERT INTO internal.beta_waitlist_rate_counters (
        scope_type,
        scope_key,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        'global_day',
        'global',
        day_window,
        2000,
        pg_catalog.NOW()
    )
    ON CONFLICT (scope_type, scope_key, window_started_at)
    DO UPDATE
    SET request_count = EXCLUDED.request_count,
        updated_at = EXCLUDED.updated_at;

    BEGIN
        PERFORM public.submit_beta_waitlist_signup(
            'waitlist-global-blocked@example.invalid',
            global_test_ip_hash,
            'pgTAP waitlist contract',
            'web_waitlist'
        );
        RAISE EXCEPTION 'global daily growth cap was bypassed';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'waitlist_global_rate_limited' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (
        SELECT 1
        FROM public.beta_waitlist_signups AS signups
        WHERE signups.email = 'waitlist-global-blocked@example.invalid'
    ) OR EXISTS (
        SELECT 1
        FROM internal.beta_waitlist_rate_counters AS counters
        WHERE counters.scope_key = global_test_ip_hash
    ) THEN
        RAISE EXCEPTION 'global-rate-limited transaction left partial state';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'waitlist RPC enforces schema, ACL, and transactional rate boundaries'
);

ROLLBACK;

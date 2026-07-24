-- Bound the intentionally public species-observation stats endpoint.
--
-- Public callers may request only a canonical Merian dictionary species.
-- Database counters bound cache and cold-population traffic, while a fenced
-- lease guarantees that at most one Edge isolate owns provider population for
-- a species. Cache finalization compares the lease token transactionally so a
-- delayed owner cannot overwrite a newer generation.

CREATE TABLE internal.species_observation_stats_rate_counters (
    scope_type TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    bucket TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    window_seconds INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (scope_type, scope_key, bucket, window_start),
    CONSTRAINT species_observation_stats_rate_scope_type_check
        CHECK (
            scope_type IN (
                'request_user',
                'request_ip',
                'population_user',
                'population_ip',
                'population_global'
            )
        ),
    CONSTRAINT species_observation_stats_rate_scope_key_check
        CHECK (NULLIF(pg_catalog.BTRIM(scope_key), '') IS NOT NULL),
    CONSTRAINT species_observation_stats_rate_bucket_check
        CHECK (NULLIF(pg_catalog.BTRIM(bucket), '') IS NOT NULL),
    CONSTRAINT species_observation_stats_rate_window_check
        CHECK (window_seconds BETWEEN 1 AND 3600),
    CONSTRAINT species_observation_stats_rate_count_check
        CHECK (request_count >= 0)
);

CREATE INDEX species_observation_stats_rate_cleanup_idx
    ON internal.species_observation_stats_rate_counters (updated_at);

CREATE TABLE internal.species_observation_stats_population_leases (
    species_id UUID PRIMARY KEY
        REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    lease_token UUID NOT NULL DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    lease_started_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    lease_expires_at TIMESTAMPTZ NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT species_observation_stats_population_attempt_check
        CHECK (attempt_count > 0),
    CONSTRAINT species_observation_stats_population_lease_order_check
        CHECK (lease_expires_at > lease_started_at)
);

CREATE INDEX species_observation_stats_population_expiry_idx
    ON internal.species_observation_stats_population_leases (
        lease_expires_at,
        species_id
    );

REVOKE ALL ON TABLE
    internal.species_observation_stats_rate_counters,
    internal.species_observation_stats_population_leases
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.consume_species_observation_stats_rate(
    p_scope_type TEXT,
    p_scope_key TEXT,
    p_bucket TEXT,
    p_window_start TIMESTAMPTZ,
    p_window_seconds INTEGER,
    p_limit INTEGER,
    p_error_code TEXT
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    resulting_count INTEGER;
BEGIN
    INSERT INTO internal.species_observation_stats_rate_counters (
        scope_type,
        scope_key,
        bucket,
        window_start,
        window_seconds,
        request_count
    )
    VALUES (
        p_scope_type,
        p_scope_key,
        p_bucket,
        p_window_start,
        p_window_seconds,
        1
    )
    ON CONFLICT (scope_type, scope_key, bucket, window_start)
    DO UPDATE
    SET
        request_count =
            internal.species_observation_stats_rate_counters.request_count + 1,
        updated_at = pg_catalog.NOW()
    WHERE
        internal.species_observation_stats_rate_counters.request_count < p_limit
    RETURNING request_count INTO resulting_count;

    IF resulting_count IS NULL THEN
        RAISE EXCEPTION '%', p_error_code
            USING ERRCODE = 'P0001';
    END IF;

    RETURN resulting_count;
END;
$$;

REVOKE ALL ON FUNCTION internal.consume_species_observation_stats_rate(
    TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.preflight_species_observation_stats_request(
    p_ip_hash TEXT
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    quota_now TIMESTAMPTZ;
    rate_window_start TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'species_stats_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    quota_now := pg_catalog.CLOCK_TIMESTAMP();
    rate_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', quota_now) / 60
        ) * 60
    );

    RETURN internal.consume_species_observation_stats_rate(
        'request_ip',
        p_ip_hash,
        'species_stats_request',
        rate_window_start,
        60,
        120,
        'species_stats_request_ip_rate_limited'
    );
END;
$$;

COMMENT ON FUNCTION public.preflight_species_observation_stats_request(TEXT) IS
    'Service-only IP request budget charged before optional user-token validation for the public species-stats endpoint.';

REVOKE ALL ON FUNCTION public.preflight_species_observation_stats_request(TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
    public.preflight_species_observation_stats_request(TEXT)
    TO service_role;

CREATE OR REPLACE FUNCTION public.authorize_species_observation_stats_request(
    p_species_id UUID,
    p_scientific_name TEXT,
    p_user_id UUID
)
RETURNS TABLE (
    species_id UUID,
    scientific_name TEXT,
    inaturalist_taxon_id INTEGER,
    denial_code TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    species_row public.species_dictionary%ROWTYPE;
    normalized_requested_name TEXT;
    normalized_canonical_name TEXT;
    quota_now TIMESTAMPTZ;
    rate_window_start TIMESTAMPTZ;
    ignored_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    normalized_requested_name := pg_catalog.REGEXP_REPLACE(
        pg_catalog.BTRIM(p_scientific_name),
        '[[:space:]]+',
        ' ',
        'g'
    );
    IF p_species_id IS NULL
       OR p_scientific_name IS NULL
       OR normalized_requested_name = ''
       OR pg_catalog.CHAR_LENGTH(normalized_requested_name) > 160 THEN
        RAISE EXCEPTION 'species_stats_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    quota_now := pg_catalog.CLOCK_TIMESTAMP();
    rate_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', quota_now) / 60
        ) * 60
    );

    IF p_user_id IS NOT NULL THEN
        ignored_count := internal.consume_species_observation_stats_rate(
            'request_user',
            p_user_id::TEXT,
            'species_stats_request',
            rate_window_start,
            60,
            60,
            'species_stats_request_user_rate_limited'
        );
    END IF;

    SELECT species.*
    INTO species_row
    FROM public.species_dictionary AS species
    WHERE species.id = p_species_id
    FOR SHARE;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT
            NULL::UUID,
            NULL::TEXT,
            NULL::INTEGER,
            'species_stats_species_not_found'::TEXT;
        RETURN;
    END IF;

    normalized_canonical_name := pg_catalog.REGEXP_REPLACE(
        pg_catalog.BTRIM(species_row.scientific_name),
        '[[:space:]]+',
        ' ',
        'g'
    );
    IF pg_catalog.LOWER(normalized_requested_name)
       <> pg_catalog.LOWER(normalized_canonical_name) THEN
        RETURN QUERY
        SELECT
            NULL::UUID,
            NULL::TEXT,
            NULL::INTEGER,
            'species_stats_species_mismatch'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        species_row.id,
        normalized_canonical_name,
        species_row.inaturalist_taxon_id,
        NULL::TEXT;
END;
$$;

COMMENT ON FUNCTION public.authorize_species_observation_stats_request(
    UUID, TEXT, UUID
) IS
    'Service-only canonical dictionary resolution plus the verified-user request budget for the public species-stats Edge endpoint.';

REVOKE ALL ON FUNCTION public.authorize_species_observation_stats_request(
    UUID, TEXT, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_species_observation_stats_request(
    UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_species_observation_stats_population(
    p_species_id UUID,
    p_user_id UUID,
    p_ip_hash TEXT
)
RETURNS TABLE (
    claimed BOOLEAN,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    retry_after_seconds INTEGER,
    cache_available BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    lease_row internal.species_observation_stats_population_leases%ROWTYPE;
    quota_now TIMESTAMPTZ;
    rate_window_start TIMESTAMPTZ;
    next_lease_token UUID;
    next_lease_expiry TIMESTAMPTZ;
    ignored_count INTEGER;
    lease_found BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_species_id IS NULL
       OR p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'species_stats_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM public.species_dictionary AS species
    WHERE species.id = p_species_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'species_stats_species_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    -- The transaction lock serializes only the short claim decision. The
    -- durable UUID lease below fences provider work after this RPC returns.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'species-observation-stats:' || p_species_id::TEXT,
            0::BIGINT
        )
    );

    SELECT leases.*
    INTO lease_row
    FROM internal.species_observation_stats_population_leases AS leases
    WHERE leases.species_id = p_species_id
    FOR UPDATE;
    lease_found := FOUND;
    quota_now := pg_catalog.CLOCK_TIMESTAMP();

    IF EXISTS (
        SELECT 1
        FROM public.species_observation_stats_cache AS cache
        WHERE cache.species_id = p_species_id
          AND cache.source = 'inaturalist'
          AND cache.scope = 'global'
          AND cache.expires_at > quota_now
          AND cache.payload IS NOT NULL
    ) THEN
        RETURN QUERY
        SELECT FALSE, NULL::UUID, quota_now, 1, TRUE;
        RETURN;
    END IF;

    IF lease_found AND lease_row.lease_expires_at > quota_now THEN
        RETURN QUERY
        SELECT
            FALSE,
            NULL::UUID,
            lease_row.lease_expires_at,
            pg_catalog.CEIL(
                pg_catalog.DATE_PART(
                    'epoch',
                    lease_row.lease_expires_at - quota_now
                )
            )::INTEGER,
            FALSE;
        RETURN;
    END IF;

    rate_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', quota_now) / 60
        ) * 60
    );
    IF p_user_id IS NOT NULL THEN
        ignored_count := internal.consume_species_observation_stats_rate(
            'population_user',
            p_user_id::TEXT,
            'species_stats_population',
            rate_window_start,
            60,
            12,
            'species_stats_population_user_rate_limited'
        );
    END IF;
    ignored_count := internal.consume_species_observation_stats_rate(
        'population_ip',
        p_ip_hash,
        'species_stats_population',
        rate_window_start,
        60,
        30,
        'species_stats_population_ip_rate_limited'
    );
    ignored_count := internal.consume_species_observation_stats_rate(
        'population_global',
        'global',
        'species_stats_population',
        rate_window_start,
        60,
        4,
        'species_stats_population_global_rate_limited'
    );

    next_lease_token := pg_catalog.GEN_RANDOM_UUID();
    next_lease_expiry := quota_now + INTERVAL '90 seconds';

    INSERT INTO internal.species_observation_stats_population_leases (
        species_id,
        lease_token,
        lease_started_at,
        lease_expires_at,
        attempt_count,
        updated_at
    )
    VALUES (
        p_species_id,
        next_lease_token,
        quota_now,
        next_lease_expiry,
        1,
        quota_now
    )
    ON CONFLICT (species_id)
    DO UPDATE
    SET
        lease_token = EXCLUDED.lease_token,
        lease_started_at = EXCLUDED.lease_started_at,
        lease_expires_at = EXCLUDED.lease_expires_at,
        attempt_count =
            internal.species_observation_stats_population_leases.attempt_count
            + 1,
        updated_at = EXCLUDED.updated_at;

    RETURN QUERY
    SELECT TRUE, next_lease_token, next_lease_expiry, 90, FALSE;
END;
$$;

COMMENT ON FUNCTION public.claim_species_observation_stats_population(
    UUID, UUID, TEXT
) IS
    'Service-only distributed cold-population lease with separate per-user/IP provider-work budgets.';

REVOKE ALL ON FUNCTION public.claim_species_observation_stats_population(
    UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_species_observation_stats_population(
    UUID, UUID, TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.finalize_species_observation_stats_population(
    p_species_id UUID,
    p_lease_token UUID,
    p_inaturalist_taxon_id INTEGER,
    p_payload JSONB,
    p_status TEXT,
    p_provider_error TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    lease_row internal.species_observation_stats_population_leases%ROWTYPE;
    species_row public.species_dictionary%ROWTYPE;
    finalized_at TIMESTAMPTZ;
    cache_expires_at TIMESTAMPTZ;
    finalized_payload JSONB;
    normalized_payload_name TEXT;
    normalized_canonical_name TEXT;
    preserved_status TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_species_id IS NULL
       OR p_lease_token IS NULL
       OR p_payload IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_payload) <> 'object'
       OR p_status IS NULL
       OR p_status NOT IN ('fresh', 'no_data', 'unavailable', 'partial')
       OR (
           p_inaturalist_taxon_id IS NOT NULL
           AND p_inaturalist_taxon_id <= 0
       )
       OR (
           p_status IN ('fresh', 'partial')
           AND p_inaturalist_taxon_id IS NULL
       ) THEN
        RAISE EXCEPTION 'species_stats_invalid_finalization'
            USING ERRCODE = '22023';
    END IF;

    SELECT leases.*
    INTO lease_row
    FROM internal.species_observation_stats_population_leases AS leases
    WHERE leases.species_id = p_species_id
    FOR UPDATE;

    IF NOT FOUND OR lease_row.lease_token <> p_lease_token THEN
        RETURN FALSE;
    END IF;

    SELECT species.*
    INTO species_row
    FROM public.species_dictionary AS species
    WHERE species.id = p_species_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'species_stats_species_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    normalized_payload_name := pg_catalog.REGEXP_REPLACE(
        pg_catalog.BTRIM(p_payload ->> 'scientific_name'),
        '[[:space:]]+',
        ' ',
        'g'
    );
    normalized_canonical_name := pg_catalog.REGEXP_REPLACE(
        pg_catalog.BTRIM(species_row.scientific_name),
        '[[:space:]]+',
        ' ',
        'g'
    );

    IF p_payload ->> 'species_id' IS DISTINCT FROM p_species_id::TEXT
       OR pg_catalog.LOWER(normalized_payload_name) IS DISTINCT FROM
          pg_catalog.LOWER(normalized_canonical_name)
       OR p_payload #>> '{source,provider}' IS DISTINCT FROM 'inaturalist'
       OR p_payload #>> '{source,scope}' IS DISTINCT FROM 'global'
       OR (
           p_inaturalist_taxon_id IS NULL
           AND p_payload #>> '{source,inaturalist_taxon_id}' IS NOT NULL
       )
       OR (
           p_inaturalist_taxon_id IS NOT NULL
           AND p_payload #>> '{source,inaturalist_taxon_id}'
               IS DISTINCT FROM p_inaturalist_taxon_id::TEXT
       ) THEN
        RAISE EXCEPTION 'species_stats_invalid_finalization'
            USING ERRCODE = '22023';
    END IF;

    IF species_row.inaturalist_taxon_id IS NOT NULL
       AND p_inaturalist_taxon_id IS NOT NULL
       AND species_row.inaturalist_taxon_id
           <> p_inaturalist_taxon_id THEN
        RAISE EXCEPTION 'species_stats_taxon_conflict'
            USING ERRCODE = 'P0001';
    END IF;

    finalized_at := pg_catalog.CLOCK_TIMESTAMP();
    cache_expires_at := finalized_at + CASE p_status
        WHEN 'fresh' THEN INTERVAL '7 days'
        WHEN 'no_data' THEN INTERVAL '24 hours'
        WHEN 'partial' THEN INTERVAL '1 hour'
        ELSE INTERVAL '5 minutes'
    END;
    finalized_payload := pg_catalog.JSONB_SET(
        p_payload,
        '{status}',
        pg_catalog.TO_JSONB(p_status),
        TRUE
    );
    finalized_payload := pg_catalog.JSONB_SET(
        finalized_payload,
        '{fetched_at}',
        pg_catalog.TO_JSONB(finalized_at),
        TRUE
    );
    finalized_payload := pg_catalog.JSONB_SET(
        finalized_payload,
        '{source,fetched_at}',
        pg_catalog.TO_JSONB(finalized_at),
        TRUE
    );

    IF p_inaturalist_taxon_id IS NOT NULL
       AND species_row.inaturalist_taxon_id IS NULL THEN
        UPDATE public.species_dictionary AS species
        SET inaturalist_taxon_id = p_inaturalist_taxon_id
        WHERE species.id = p_species_id
          AND species.inaturalist_taxon_id IS NULL;
    END IF;

    -- A transient refresh failure must not destroy still-usable positive data.
    -- Mark that payload stale and extend only the short retry-backoff window;
    -- keep its original fetched_at so the Edge stale-retention ceiling remains
    -- authoritative. Cold misses and expired no-data rows still receive the
    -- normal five-minute unavailable negative cache below.
    IF p_status = 'unavailable' THEN
        UPDATE public.species_observation_stats_cache AS cache
        SET
            payload = pg_catalog.JSONB_SET(
                cache.payload,
                '{status}',
                pg_catalog.TO_JSONB('stale'::TEXT),
                TRUE
            ),
            status = 'stale',
            provider_error = NULLIF(
                pg_catalog.LEFT(
                    pg_catalog.BTRIM(p_provider_error),
                    1000
                ),
                ''
            ),
            expires_at = finalized_at + INTERVAL '5 minutes',
            updated_at = finalized_at
        WHERE cache.species_id = p_species_id
          AND cache.source = 'inaturalist'
          AND cache.scope = 'global'
          AND cache.payload IS NOT NULL
          AND cache.status IN ('fresh', 'partial', 'stale')
          AND cache.fetched_at
              >= finalized_at - INTERVAL '37 days'
        RETURNING cache.status INTO preserved_status;

        IF preserved_status = 'stale' THEN
            DELETE FROM
                internal.species_observation_stats_population_leases AS leases
            WHERE leases.species_id = p_species_id
              AND leases.lease_token = p_lease_token;

            RETURN TRUE;
        END IF;
    END IF;

    INSERT INTO public.species_observation_stats_cache (
        species_id,
        source,
        scope,
        scientific_name,
        payload,
        status,
        provider_error,
        fetched_at,
        expires_at
    )
    VALUES (
        p_species_id,
        'inaturalist',
        'global',
        normalized_canonical_name,
        finalized_payload,
        p_status,
        NULLIF(
            pg_catalog.LEFT(
                pg_catalog.BTRIM(p_provider_error),
                1000
            ),
            ''
        ),
        finalized_at,
        cache_expires_at
    )
    ON CONFLICT (species_id, source, scope)
    DO UPDATE
    SET
        scientific_name = EXCLUDED.scientific_name,
        payload = EXCLUDED.payload,
        status = EXCLUDED.status,
        provider_error = EXCLUDED.provider_error,
        fetched_at = EXCLUDED.fetched_at,
        expires_at = EXCLUDED.expires_at,
        updated_at = finalized_at;

    DELETE FROM internal.species_observation_stats_population_leases AS leases
    WHERE leases.species_id = p_species_id
      AND leases.lease_token = p_lease_token;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.finalize_species_observation_stats_population(
    UUID, UUID, INTEGER, JSONB, TEXT, TEXT
) IS
    'Service-only fenced cache finalization. A stale lease token cannot update provider identity or overwrite a newer cache generation.';

REVOKE ALL ON FUNCTION public.finalize_species_observation_stats_population(
    UUID, UUID, INTEGER, JSONB, TEXT, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_species_observation_stats_population(
    UUID, UUID, INTEGER, JSONB, TEXT, TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION internal.prune_species_observation_stats_guards()
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '30s'
AS $$
DECLARE
    deleted_counter_count INTEGER;
    deleted_lease_count INTEGER;
BEGIN
    WITH expired_counters AS (
        SELECT counters.ctid
        FROM internal.species_observation_stats_rate_counters AS counters
        WHERE counters.updated_at
            < pg_catalog.NOW() - INTERVAL '2 days'
        ORDER BY counters.updated_at
        LIMIT 5000
    )
    DELETE FROM internal.species_observation_stats_rate_counters AS counters
    USING expired_counters
    WHERE counters.ctid = expired_counters.ctid;
    GET DIAGNOSTICS deleted_counter_count = ROW_COUNT;

    WITH expired_leases AS (
        SELECT leases.ctid
        FROM internal.species_observation_stats_population_leases AS leases
        WHERE leases.lease_expires_at
            < pg_catalog.NOW() - INTERVAL '10 minutes'
        ORDER BY leases.lease_expires_at
        LIMIT 5000
    )
    DELETE FROM internal.species_observation_stats_population_leases AS leases
    USING expired_leases
    WHERE leases.ctid = expired_leases.ctid;
    GET DIAGNOSTICS deleted_lease_count = ROW_COUNT;

    RETURN deleted_counter_count + deleted_lease_count;
END;
$$;

REVOKE ALL ON FUNCTION internal.prune_species_observation_stats_guards()
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.preflight_species_observation_stats_request(text)',
        'Public species-stats Edge Function pre-authentication IP request budget.'
    ),
    (
        'service_role',
        'public.authorize_species_observation_stats_request(uuid,text,uuid)',
        'Public species-stats Edge Function canonical dictionary and verified-user boundary.'
    ),
    (
        'service_role',
        'public.claim_species_observation_stats_population(uuid,uuid,text)',
        'Public species-stats Edge Function distributed provider-population lease.'
    ),
    (
        'service_role',
        'public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)',
        'Public species-stats Edge Function fenced cache finalization.'
    )
ON CONFLICT (role_name, routine_signature)
DO UPDATE SET purpose = EXCLUDED.purpose;

DO $migration$
BEGIN
    PERFORM cron.unschedule('prune_species_observation_stats_guards_hourly');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$migration$;

SELECT cron.schedule(
    'prune_species_observation_stats_guards_hourly',
    '23 * * * *',
    $cron$
        SELECT internal.prune_species_observation_stats_guards();
    $cron$
);

NOTIFY pgrst, 'reload schema';

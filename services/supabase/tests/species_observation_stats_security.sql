\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    native_region,
    inaturalist_taxon_id
)
VALUES
    (
        '00000000-0000-4000-8000-00000000c901',
        'Contractus observationis',
        '{"en":"Observation contract species"}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Contractidae',
        'Contractus',
        'Test region',
        NULL
    ),
    (
        '00000000-0000-4000-8000-00000000c903',
        'Contractus absentis',
        '{"en":"Negative cache contract species"}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Contractidae',
        'Contractus',
        'Test region',
        NULL
    );

DO $test$
DECLARE
    test_species_id UUID := '00000000-0000-4000-8000-00000000c901';
    test_user_id UUID := '00000000-0000-4000-8000-00000000c902';
    first_lease RECORD;
    concurrent_claim RECORD;
    second_lease RECORD;
    refresh_lease RECORD;
    negative_lease RECORD;
    authorized_row RECORD;
    denied_row RECORD;
    cache_claim RECORD;
    first_token UUID;
    finalized BOOLEAN;
    rate_window_start TIMESTAMPTZ;
    payload JSONB;
    unavailable_payload JSONB;
    negative_payload JSONB;
    positive_fetched_at TIMESTAMPTZ;
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.species_observation_stats_rate_counters',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.species_observation_stats_population_leases',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.species_observation_stats_rate_counters',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'species stats guard tables are visible to API roles';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.preflight_species_observation_stats_request(text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.preflight_species_observation_stats_request(text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.preflight_species_observation_stats_request(text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'species stats preflight RPC has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.authorize_species_observation_stats_request(uuid,text,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.authorize_species_observation_stats_request(uuid,text,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.authorize_species_observation_stats_request(uuid,text,uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'species stats authorization RPC has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.claim_species_observation_stats_population(uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_species_observation_stats_population(uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_species_observation_stats_population(uuid,uuid,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'species stats claim RPC has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'species stats finalization RPC has an unsafe ACL';
    END IF;

    PERFORM public.preflight_species_observation_stats_request(
        pg_catalog.REPEAT('a', 64)
    );
    SELECT *
    INTO STRICT authorized_row
    FROM public.authorize_species_observation_stats_request(
        test_species_id,
        '  Contractus   observationis ',
        test_user_id
    );
    IF authorized_row.species_id <> test_species_id
       OR authorized_row.scientific_name <> 'Contractus observationis'
       OR authorized_row.denial_code IS NOT NULL THEN
        RAISE EXCEPTION 'canonical species authorization failed';
    END IF;

    PERFORM public.preflight_species_observation_stats_request(
        pg_catalog.REPEAT('a', 64)
    );
    SELECT *
    INTO STRICT denied_row
    FROM public.authorize_species_observation_stats_request(
        test_species_id,
        'Attacker supplied name',
        NULL
    );
    IF denied_row.denial_code <> 'species_stats_species_mismatch' THEN
        RAISE EXCEPTION 'dictionary mismatch did not fail closed';
    END IF;

    IF (
        SELECT counters.request_count
        FROM internal.species_observation_stats_rate_counters AS counters
        WHERE counters.scope_type = 'request_ip'
          AND counters.scope_key = pg_catalog.REPEAT('a', 64)
          AND counters.bucket = 'species_stats_request'
        ORDER BY counters.window_start DESC
        LIMIT 1
    ) <> 2 THEN
        RAISE EXCEPTION 'denied dictionary requests do not retain rate usage';
    END IF;

    IF (
        SELECT counters.request_count
        FROM internal.species_observation_stats_rate_counters AS counters
        WHERE counters.scope_type = 'request_user'
          AND counters.scope_key = test_user_id::TEXT
          AND counters.bucket = 'species_stats_request'
        ORDER BY counters.window_start DESC
        LIMIT 1
    ) <> 1 THEN
        RAISE EXCEPTION 'verified-user request rate usage was not retained';
    END IF;

    SELECT *
    INTO STRICT first_lease
    FROM public.claim_species_observation_stats_population(
        test_species_id,
        NULL,
        pg_catalog.REPEAT('a', 64)
    );
    IF NOT first_lease.claimed
       OR first_lease.lease_token IS NULL
       OR first_lease.cache_available THEN
        RAISE EXCEPTION 'first cold population did not acquire a lease';
    END IF;
    first_token := first_lease.lease_token;

    SELECT *
    INTO STRICT concurrent_claim
    FROM public.claim_species_observation_stats_population(
        test_species_id,
        NULL,
        pg_catalog.REPEAT('a', 64)
    );
    IF concurrent_claim.claimed
       OR concurrent_claim.lease_token IS NOT NULL
       OR concurrent_claim.cache_available
       OR concurrent_claim.retry_after_seconds < 1 THEN
        RAISE EXCEPTION 'active distributed lease did not suppress a stampede';
    END IF;

    UPDATE internal.species_observation_stats_population_leases AS leases
    SET
        lease_started_at = pg_catalog.NOW() - INTERVAL '2 seconds',
        lease_expires_at = pg_catalog.NOW() - INTERVAL '1 second'
    WHERE leases.species_id = test_species_id;

    SELECT *
    INTO STRICT second_lease
    FROM public.claim_species_observation_stats_population(
        test_species_id,
        NULL,
        pg_catalog.REPEAT('a', 64)
    );
    IF NOT second_lease.claimed
       OR second_lease.lease_token IS NULL
       OR second_lease.lease_token = first_token THEN
        RAISE EXCEPTION 'expired lease did not advance its fencing token';
    END IF;

    payload := pg_catalog.JSONB_BUILD_OBJECT(
        'species_id', test_species_id,
        'scientific_name', 'Contractus observationis',
        'source', pg_catalog.JSONB_BUILD_OBJECT(
            'provider', 'inaturalist',
            'scope', 'global',
            'inaturalist_taxon_id', 424242,
            'fetched_at', pg_catalog.NOW()
        ),
        'status', 'fresh',
        'total_observations', 99,
        'provider_errors', '[]'::JSONB
    );

    finalized := public.finalize_species_observation_stats_population(
        test_species_id,
        first_token,
        424242,
        payload,
        'fresh',
        NULL
    );
    IF finalized THEN
        RAISE EXCEPTION 'stale population generation overwrote newer work';
    END IF;

    finalized := public.finalize_species_observation_stats_population(
        test_species_id,
        second_lease.lease_token,
        424242,
        payload,
        'fresh',
        NULL
    );
    IF NOT finalized THEN
        RAISE EXCEPTION 'current population generation did not finalize';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.species_observation_stats_cache AS cache
        WHERE cache.species_id = test_species_id
          AND cache.status = 'fresh'
          AND cache.expires_at
              BETWEEN pg_catalog.NOW() + INTERVAL '6 days 23 hours'
                  AND pg_catalog.NOW() + INTERVAL '7 days 1 hour'
          AND cache.payload #>> '{source,inaturalist_taxon_id}' = '424242'
    ) OR (
        SELECT species.inaturalist_taxon_id
        FROM public.species_dictionary AS species
        WHERE species.id = test_species_id
    ) <> 424242 THEN
        RAISE EXCEPTION 'fenced finalization did not persist canonical cache state';
    END IF;

    SELECT *
    INTO STRICT cache_claim
    FROM public.claim_species_observation_stats_population(
        test_species_id,
        NULL,
        pg_catalog.REPEAT('a', 64)
    );
    IF cache_claim.claimed
       OR NOT cache_claim.cache_available
       OR cache_claim.lease_token IS NOT NULL THEN
        RAISE EXCEPTION 'claim RPC did not close the post-cache race';
    END IF;

    SELECT cache.fetched_at
    INTO STRICT positive_fetched_at
    FROM public.species_observation_stats_cache AS cache
    WHERE cache.species_id = test_species_id
      AND cache.source = 'inaturalist'
      AND cache.scope = 'global';

    UPDATE public.species_observation_stats_cache AS cache
    SET expires_at = pg_catalog.NOW() - INTERVAL '1 second'
    WHERE cache.species_id = test_species_id
      AND cache.source = 'inaturalist'
      AND cache.scope = 'global';

    SELECT *
    INTO STRICT refresh_lease
    FROM public.claim_species_observation_stats_population(
        test_species_id,
        NULL,
        pg_catalog.REPEAT('a', 64)
    );
    IF NOT refresh_lease.claimed
       OR refresh_lease.lease_token IS NULL THEN
        RAISE EXCEPTION 'expired positive cache did not acquire a refresh lease';
    END IF;

    unavailable_payload := pg_catalog.JSONB_BUILD_OBJECT(
        'species_id', test_species_id,
        'scientific_name', 'Contractus observationis',
        'source', pg_catalog.JSONB_BUILD_OBJECT(
            'provider', 'inaturalist',
            'scope', 'global',
            'inaturalist_taxon_id', 424242,
            'fetched_at', pg_catalog.NOW()
        ),
        'status', 'unavailable',
        'total_observations', 0,
        'provider_errors', '["provider timeout"]'::JSONB
    );
    finalized := public.finalize_species_observation_stats_population(
        test_species_id,
        refresh_lease.lease_token,
        424242,
        unavailable_payload,
        'unavailable',
        'provider timeout'
    );
    IF NOT finalized THEN
        RAISE EXCEPTION 'failed refresh did not finalize its current lease';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.species_observation_stats_cache AS cache
        WHERE cache.species_id = test_species_id
          AND cache.status = 'stale'
          AND cache.payload ->> 'status' = 'stale'
          AND cache.payload ->> 'total_observations' = '99'
          AND cache.fetched_at = positive_fetched_at
          AND cache.provider_error = 'provider timeout'
          AND cache.expires_at
              BETWEEN pg_catalog.NOW() + INTERVAL '4 minutes'
                  AND pg_catalog.NOW() + INTERVAL '6 minutes'
    ) OR EXISTS (
        SELECT 1
        FROM internal.species_observation_stats_population_leases AS leases
        WHERE leases.species_id = test_species_id
    ) THEN
        RAISE EXCEPTION 'failed refresh destroyed stale positive cache state';
    END IF;

    SELECT *
    INTO STRICT negative_lease
    FROM public.claim_species_observation_stats_population(
        '00000000-0000-4000-8000-00000000c903'::UUID,
        NULL,
        pg_catalog.REPEAT('b', 64)
    );
    IF NOT negative_lease.claimed
       OR negative_lease.lease_token IS NULL THEN
        RAISE EXCEPTION 'negative-cache population did not acquire a lease';
    END IF;

    negative_payload := pg_catalog.JSONB_BUILD_OBJECT(
        'species_id', '00000000-0000-4000-8000-00000000c903'::UUID,
        'scientific_name', 'Contractus absentis',
        'source', pg_catalog.JSONB_BUILD_OBJECT(
            'provider', 'inaturalist',
            'scope', 'global',
            'inaturalist_taxon_id', NULL,
            'fetched_at', pg_catalog.NOW()
        ),
        'status', 'no_data',
        'total_observations', 0,
        'provider_errors', '["exact match not found"]'::JSONB
    );
    finalized := public.finalize_species_observation_stats_population(
        '00000000-0000-4000-8000-00000000c903'::UUID,
        negative_lease.lease_token,
        NULL,
        negative_payload,
        'no_data',
        'exact match not found'
    );
    IF NOT finalized OR NOT EXISTS (
        SELECT 1
        FROM public.species_observation_stats_cache AS cache
        WHERE cache.species_id =
              '00000000-0000-4000-8000-00000000c903'::UUID
          AND cache.status = 'no_data'
          AND cache.expires_at
              BETWEEN pg_catalog.NOW() + INTERVAL '23 hours'
                  AND pg_catalog.NOW() + INTERVAL '25 hours'
    ) THEN
        RAISE EXCEPTION 'exact provider miss did not receive its negative TTL';
    END IF;

    rate_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', pg_catalog.NOW()) / 60
        ) * 60
    );
    UPDATE internal.species_observation_stats_rate_counters AS counters
    SET request_count = 60
    WHERE counters.scope_type = 'request_user'
      AND counters.scope_key = test_user_id::TEXT
      AND counters.bucket = 'species_stats_request'
      AND counters.window_start = rate_window_start;

    BEGIN
        PERFORM public.authorize_species_observation_stats_request(
            test_species_id,
            'Contractus observationis',
            test_user_id
        );
        RAISE EXCEPTION 'expected species stats user rate denial';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM
               NOT LIKE '%species_stats_request_user_rate_limited%' THEN
                RAISE;
            END IF;
    END;

    UPDATE internal.species_observation_stats_rate_counters AS counters
    SET request_count = 120
    WHERE counters.scope_type = 'request_ip'
      AND counters.scope_key = pg_catalog.REPEAT('a', 64)
      AND counters.bucket = 'species_stats_request'
      AND counters.window_start = rate_window_start;

    BEGIN
        PERFORM public.preflight_species_observation_stats_request(
            pg_catalog.REPEAT('a', 64)
        );
        RAISE EXCEPTION 'expected species stats IP rate denial';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM NOT LIKE '%species_stats_request_ip_rate_limited%' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

SELECT extensions.pass(
    'species stats requests are dictionary-bound, user/IP-rate-limited, leased, negatively cacheable, and generation-fenced'
);
SELECT * FROM extensions.finish();
ROLLBACK;

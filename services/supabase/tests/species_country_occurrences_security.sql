\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(21);

SELECT extensions.ok(
    (
        SELECT relation.relrowsecurity
        FROM pg_catalog.pg_class AS relation
        INNER JOIN pg_catalog.pg_namespace AS namespace
            ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND relation.relname = 'species_country_occurrences'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policy AS policy
        INNER JOIN pg_catalog.pg_class AS relation
            ON relation.oid = policy.polrelid
        INNER JOIN pg_catalog.pg_namespace AS namespace
            ON namespace.oid = relation.relnamespace
        WHERE namespace.nspname = 'public'
          AND relation.relname = 'species_country_occurrences'
    ),
    'country occurrence storage enables RLS without public policies'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_country_occurrences',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_country_occurrences',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_country_occurrences',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_country_occurrences',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_country_occurrences',
        'DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_country_occurrences',
        'UPDATE'
    ),
    'country occurrence storage has the exact service-only table ACL'
);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.replace_species_country_occurrences(uuid,bigint,jsonb,timestamp with time zone)',
        'EXECUTE'
    )
    AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_species_dictionary_country_summaries(text,bigint,integer)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.replace_species_country_occurrences(uuid,bigint,jsonb,timestamp with time zone)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_species_dictionary_country_summaries(text,bigint,integer)',
        'EXECUTE'
    ),
    'country occurrence RPCs are executable only by the service boundary'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary',
        'UPDATE'
    )
    AND NOT (
        SELECT function_row.prosecdef
        FROM pg_catalog.pg_proc AS function_row
        WHERE function_row.oid =
            'public.replace_species_country_occurrences(uuid,bigint,jsonb,timestamp with time zone)'::REGPROCEDURE
    ),
    'replacement synchronization preserves the invoker and read-only dictionary boundary'
);

SELECT extensions.ok(
    (
        SELECT COALESCE(
            function_row.proconfig,
            ARRAY[]::TEXT[]
        ) @> ARRAY['search_path=""']::TEXT[]
        FROM pg_catalog.pg_proc AS function_row
        WHERE function_row.oid =
            'public.species_dictionary_missing_enrichment_groups(public.species_dictionary)'::REGPROCEDURE
    ),
    'the country-aware public definer helper has an empty search path'
);

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
    wikipedia_overview,
    reference_image_url,
    gbif_taxon_key
)
VALUES
    (
        '00000000-0000-4000-8000-00000000cc01',
        'Regionalis exacta',
        '{"en":"Exact regional contract species"}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Regionalidae',
        'Regionalis',
        'This sufficiently long encyclopedic overview satisfies the public species content contract for testing.',
        'https://example.invalid/regionalis-exacta.jpg',
        910001
    ),
    (
        '00000000-0000-4000-8000-00000000cc02',
        'Regionalis secunda',
        '{"en":"Second regional contract species"}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Regionalidae',
        'Regionalis',
        'This second sufficiently long encyclopedic overview satisfies the public species content contract for testing.',
        'https://example.invalid/regionalis-secunda.jpg',
        910002
    );

SELECT extensions.is(
    (
        SELECT species.native_region
        FROM public.species_dictionary AS species
        WHERE species.id = '00000000-0000-4000-8000-00000000cc01'
    ),
    'Unknown'::TEXT,
    'new dictionary rows can omit the legacy native-region value'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.replace_species_country_occurrences(
        '00000000-0000-4000-8000-00000000cc01',
        910001,
        '[
          {"country_code":"us","occurrence_count":7},
          {"country_code":"US","occurrence_count":11},
          {"country_code":"ca","occurrence_count":15}
        ]'::JSONB,
        '2026-07-31T12:00:00Z'
    ),
    2,
    'the service role can atomically replace and deduplicate a country facet'
);
RESET ROLE;

SELECT extensions.ok(
    (
        SELECT pg_catalog.COUNT(*) = 2
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
    )
    AND (
        SELECT occurrence.occurrence_count = 11
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
          AND occurrence.country_code = 'US'
    ),
    'replacement stores uppercase countries and the greatest duplicate count'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.replace_species_country_occurrences(
        '00000000-0000-4000-8000-00000000cc02',
        910002,
        '[{"country_code":"CA","occurrence_count":20}]'::JSONB,
        '2026-07-31T12:00:00Z'
    ),
    1,
    'a second species can contribute exact occurrence evidence'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT summary.species_count
        FROM public.get_species_dictionary_country_summaries('US', 1, 24) AS summary
    ),
    1,
    'an exact US summary excludes Canadian-only evidence'
);

SELECT extensions.ok(
    (
        SELECT summary.species_count = 2
           AND summary.representative_species_id = '00000000-0000-4000-8000-00000000cc02'
        FROM public.get_species_dictionary_country_summaries('CA', 1, 24) AS summary
    ),
    'a Canadian summary counts exact species and picks the strongest representative'
);

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.replace_species_country_occurrences(
            '00000000-0000-4000-8000-00000000cc01',
            999999,
            '[{"country_code":"US","occurrence_count":1}]'::JSONB
        )
    $statement$,
    '23503',
    'species_country_occurrences_taxon_mismatch',
    'a replacement rejects evidence for a non-current GBIF identity'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
    ),
    2,
    'a GBIF identity mismatch preserves the prior complete facet'
);

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.replace_species_country_occurrences(
            '00000000-0000-4000-8000-00000000cc01',
            910001,
            '[{"country_code":"USA","occurrence_count":1}]'::JSONB
        )
    $statement$,
    '22023',
    'species_country_occurrences_invalid_entry',
    'a malformed country facet fails validation before replacement'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
    ),
    2,
    'a malformed facet preserves the prior complete facet'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.replace_species_country_occurrences(
        '00000000-0000-4000-8000-00000000cc01',
        910001,
        '[]'::JSONB
    ),
    0,
    'a valid empty GBIF facet is a successful atomic replacement'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
    ),
    0,
    'a valid empty facet clears stale occurrence rows'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.replace_species_country_occurrences(
        '00000000-0000-4000-8000-00000000cc01',
        910001,
        '[{"country_code":"US","occurrence_count":3}]'::JSONB
    ),
    1,
    'country evidence can be restored before a GBIF rematch'
);
RESET ROLE;

INSERT INTO public.species_content_provenance (
    species_id,
    content_key,
    source,
    source_detail,
    confidence,
    metadata,
    last_refreshed_at,
    refresh_after
)
VALUES (
    '00000000-0000-4000-8000-00000000cc01',
    'country_occurrences',
    'gbif',
    'country facet contract fixture',
    0.8500,
    '{"gbif_taxon_key":910001,"country_count":1}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW() + INTERVAL '180 days'
);

UPDATE public.species_dictionary AS species
SET gbif_taxon_key = 910003
WHERE species.id = '00000000-0000-4000-8000-00000000cc01';

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = '00000000-0000-4000-8000-00000000cc01'
    )
    AND EXISTS (
        SELECT 1
        FROM public.species_content_provenance AS provenance
        WHERE provenance.species_id = '00000000-0000-4000-8000-00000000cc01'
          AND provenance.content_key = 'country_occurrences'
          AND provenance.refresh_after <= pg_catalog.NOW()
          AND provenance.metadata ->> 'invalidated_by' = 'gbif_taxon_key_change'
          AND provenance.metadata ->> 'current_gbif_taxon_key' = '910003'
    )
    AND EXISTS (
        SELECT 1
        FROM public.species_enrichment_jobs AS job
        WHERE job.species_id = '00000000-0000-4000-8000-00000000cc01'
          AND job.content_group = 'gbif_wikipedia_reference'
          AND job.source_trigger = 'species_gbif_taxon_key_change'
          AND job.status = 'queued'
    ),
    'a GBIF rematch purges stale rows, invalidates provenance, and queues repair'
);

INSERT INTO public.species_content_provenance (
    species_id,
    content_key,
    source,
    source_detail,
    confidence,
    metadata,
    last_refreshed_at,
    refresh_after
)
VALUES (
    '00000000-0000-4000-8000-00000000cc01',
    'country_occurrences',
    'gbif',
    'successful empty country facet',
    0.8500,
    '{"gbif_taxon_key":910003,"country_count":0}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW() + INTERVAL '180 days'
)
ON CONFLICT (species_id, content_key) DO UPDATE
SET
    source = EXCLUDED.source,
    source_detail = EXCLUDED.source_detail,
    confidence = EXCLUDED.confidence,
    metadata = EXCLUDED.metadata,
    last_refreshed_at = EXCLUDED.last_refreshed_at,
    refresh_after = EXCLUDED.refresh_after;

SELECT extensions.ok(
    NOT (
        'gbif_wikipedia_reference' = ANY(
            public.species_dictionary_missing_enrichment_groups(species)
        )
    ),
    'a successful empty current facet counts as hydrated country coverage'
)
FROM public.species_dictionary AS species
WHERE species.id = '00000000-0000-4000-8000-00000000cc01';

UPDATE public.species_dictionary AS species
SET gbif_taxon_key = 910004
WHERE species.id = '00000000-0000-4000-8000-00000000cc01';

SELECT extensions.ok(
    'gbif_wikipedia_reference' = ANY(
        public.species_dictionary_missing_enrichment_groups(species)
    ),
    'empty-facet provenance for an old GBIF identity cannot mask a new gap'
)
FROM public.species_dictionary AS species
WHERE species.id = '00000000-0000-4000-8000-00000000cc01';

SELECT * FROM extensions.finish();
ROLLBACK;

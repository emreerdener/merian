\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(10);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.claim_species_model_enrichment_jobs(integer,timestamptz,text[],boolean)', 'EXECUTE')
    AND pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', 'public.claim_species_model_enrichment_jobs(integer,timestamptz,text[],boolean)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.enqueue_species_dictionary_enrichment_jobs()', 'EXECUTE'),
    'recovery RPCs are service-only and the insert trigger remains owner-only'
);

SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok(
    'SELECT * FROM public.claim_species_model_enrichment_jobs()',
    '42501', NULL,
    'authenticated clients cannot claim or preview enrichment jobs'
);
SELECT extensions.throws_ok(
    $$SELECT * FROM public.persist_species_model_lookalikes('00000000-0000-4000-8000-00000000fa01', '[]')$$,
    '42501', NULL,
    'authenticated clients cannot materialize model candidates'
);
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    'SELECT * FROM public.claim_species_model_enrichment_jobs(51)',
    '22023', 'invalid_species_model_job_request',
    'model claims are capped at fifty jobs'
);
SELECT extensions.throws_ok(
    $$SELECT * FROM public.claim_species_model_enrichment_jobs(target_content_groups => ARRAY['gbif_wikipedia_reference'])$$,
    '22023', 'invalid_species_model_job_request',
    'model claims cannot take jobs owned by another worker'
);
RESET ROLE;

-- All identities and GBIF proofs below are synthetic disposable fixtures.
CREATE FUNCTION pg_temp.lookalike_fixture_id(value INTEGER)
RETURNS UUID LANGUAGE SQL IMMUTABLE AS $$
    SELECT ('00000000-0000-4000-8000-00000000fa' || pg_catalog.LPAD(value::TEXT, 2, '0'))::UUID;
$$;
CREATE FUNCTION pg_temp.lookalike_fixture_candidate(
    name TEXT,
    taxon_key INTEGER,
    genus TEXT DEFAULT 'Comparatus'
)
RETURNS JSONB LANGUAGE SQL IMMUTABLE AS $$
    SELECT pg_catalog.JSONB_BUILD_OBJECT(
        'scientific_name', name, 'common_name', 'Shared name',
        'reason', 'Model field marks', 'visual_traits', ARRAY['leaf shape'], 'confidence', 0.9,
        'gbif', pg_catalog.JSONB_BUILD_OBJECT(
            'scientific_name', name, 'gbif_taxon_key', taxon_key,
            'rank', 'SPECIES', 'status', 'ACCEPTED', 'kingdom', 'Plantae',
            'phylum', 'Tracheophyta', 'class', 'Magnoliopsida',
            'order', 'Rosales', 'family', 'Rosaceae', 'genus', genus
        )
    );
$$;

INSERT INTO public.species_dictionary (
    id, scientific_name, common_names, gbif_taxon_key,
    kingdom, phylum, class, "order", family, genus
)
SELECT pg_temp.lookalike_fixture_id(value), 'Recoveryfixture species' || value,
    '{"en":"Shared name"}'::JSONB, 920000 + value,
    'Plantae', 'Tracheophyta', 'Magnoliopsida', 'Rosales', 'Rosaceae', 'Unknown'
FROM pg_catalog.GENERATE_SERIES(1, 18) AS series(value);

UPDATE public.species_dictionary SET genus = 'Fixturegenus'
WHERE id IN (pg_temp.lookalike_fixture_id(1), pg_temp.lookalike_fixture_id(8));
UPDATE public.species_dictionary
SET gbif_taxon_key = NULL, kingdom = 'Unknown', phylum = 'Unknown', class = 'Unknown',
    "order" = 'Unknown', family = 'Unknown'
WHERE id IN (pg_temp.lookalike_fixture_id(5), pg_temp.lookalike_fixture_id(18));

INSERT INTO public.species_lookalikes (
    species_id, lookalike_id, source, review_status, reason, visual_traits,
    confidence, sort_order, is_bidirectional
) VALUES
    (pg_temp.lookalike_fixture_id(1), pg_temp.lookalike_fixture_id(2),
     'manual_curation', 'approved', 'Curated field marks', ARRAY['curated trait'], 0.95, 17, TRUE),
    (pg_temp.lookalike_fixture_id(1), pg_temp.lookalike_fixture_id(3),
     'user_review', 'rejected', 'Reviewed rejection', ARRAY['reviewed trait'], 0.5, 25, FALSE);
INSERT INTO public.species_content_provenance (species_id, content_key, source, source_detail)
VALUES (pg_temp.lookalike_fixture_id(1), 'lookalikes', 'manual_curation', 'Reviewed fixture');

-- Isolate queue selection inside this rolled-back fixture; no pre-existing
-- scheduled work should affect ordering assertions in a disposable database.
UPDATE public.species_enrichment_jobs SET status = 'cancelled'
WHERE content_group IN ('habitat', 'lookalikes', 'group_tags');
INSERT INTO public.species_enrichment_jobs (
    species_id, content_group, status, priority, attempts, max_attempts,
    source_trigger, metadata, next_run_at
)
SELECT pg_temp.lookalike_fixture_id(value), content_group, status, priority, attempts, 5,
    'lookalike_recovery_fixture', metadata, next_run_at::TIMESTAMPTZ
FROM (VALUES
    (10, 'lookalikes', 'succeeded', 10, 5, '{"preserved":true}'::JSONB, '2000-01-01'),
    (11, 'lookalikes', 'failed', 20, 5, '{}'::JSONB, '2100-01-01'),
    (12, 'lookalikes', 'failed', 30, 1, '{"lookalike_resolution_version":1}'::JSONB, '2000-01-01'),
    (13, 'lookalikes', 'succeeded', 40, 2, '{"lookalike_resolution_version":1}'::JSONB, '2000-01-01'),
    (14, 'lookalikes', 'running', 40, 2, '{}'::JSONB, '2000-01-01'),
    (15, 'lookalikes', 'failed', 40, 1, '{}'::JSONB, '2100-01-01'),
    (1, 'lookalikes', 'succeeded', 40, 5, '{}'::JSONB, '2000-01-01'),
    (18, 'lookalikes', 'succeeded', 40, 5, '{}'::JSONB, '2000-01-01'),
    (16, 'habitat', 'queued', 1, 0, '{}'::JSONB, '2000-01-01'),
    (17, 'group_tags', 'queued', 2, 0, '{}'::JSONB, '2000-01-01')
) AS fixture(value, content_group, status, priority, attempts, metadata, next_run_at)
ON CONFLICT (species_id, content_group) DO UPDATE
SET status = EXCLUDED.status, priority = EXCLUDED.priority,
    attempts = EXCLUDED.attempts, max_attempts = EXCLUDED.max_attempts,
    metadata = EXCLUDED.metadata, next_run_at = EXCLUDED.next_run_at;

DO $$
DECLARE
    preview_ids UUID[];
    claimed_ids UUID[];
    claimed_groups TEXT[];
    selected_job RECORD;
BEGIN
    SELECT pg_catalog.ARRAY_AGG(species_id ORDER BY priority) INTO preview_ids
    FROM public.claim_species_model_enrichment_jobs(50, '2001-01-01', ARRAY['lookalikes'], TRUE);
    IF preview_ids IS DISTINCT FROM ARRAY[
        pg_temp.lookalike_fixture_id(10), pg_temp.lookalike_fixture_id(11), pg_temp.lookalike_fixture_id(12)
    ] THEN RAISE EXCEPTION 'preview selected ineligible or omitted eligible lookalike jobs'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.species_enrichment_jobs
        WHERE species_id IN (pg_temp.lookalike_fixture_id(10), pg_temp.lookalike_fixture_id(11))
          AND content_group = 'lookalikes'
          AND (status = 'running' OR attempts <> 5 OR metadata ? 'lookalike_resolution_version')
    ) THEN RAISE EXCEPTION 'preview mutated legacy recovery state'; END IF;

    SELECT pg_catalog.ARRAY_AGG(content_group ORDER BY priority) INTO claimed_groups
    FROM public.claim_species_model_enrichment_jobs(2, '2001-01-01');
    IF claimed_groups IS DISTINCT FROM ARRAY['habitat', 'group_tags']::TEXT[] THEN
        RAISE EXCEPTION 'model groups did not share one global priority-ordered claim limit';
    END IF;

    SELECT pg_catalog.ARRAY_AGG(species_id ORDER BY priority) INTO claimed_ids
    FROM public.claim_species_model_enrichment_jobs(50, '2001-01-01', ARRAY['lookalikes']);
    IF claimed_ids IS DISTINCT FROM preview_ids THEN RAISE EXCEPTION 'preview and claim eligibility drifted'; END IF;
    IF (SELECT COUNT(*) FROM public.species_enrichment_jobs
        WHERE species_id IN (pg_temp.lookalike_fixture_id(10), pg_temp.lookalike_fixture_id(11))
          AND content_group = 'lookalikes' AND status = 'running' AND attempts = 1
          AND locked_at IS NOT NULL AND metadata ->> 'lookalike_resolution_version' = '1') <> 2 THEN
        RAISE EXCEPTION 'legacy jobs did not atomically acquire a fresh bounded attempt budget and marker';
    END IF;
    IF NOT (SELECT metadata @> '{"preserved":true}'::JSONB FROM public.species_enrichment_jobs
        WHERE species_id = pg_temp.lookalike_fixture_id(10) AND content_group = 'lookalikes') THEN
        RAISE EXCEPTION 'claim discarded existing metadata';
    END IF;
    IF (SELECT attempts FROM public.species_enrichment_jobs
        WHERE species_id = pg_temp.lookalike_fixture_id(12) AND content_group = 'lookalikes') <> 2 THEN
        RAISE EXCEPTION 'ordinary retries incorrectly reset their attempt budget';
    END IF;

    FOR selected_job IN SELECT id FROM public.species_enrichment_jobs
        WHERE species_id = ANY(claimed_ids) AND content_group = 'lookalikes'
    LOOP
        PERFORM public.complete_species_enrichment_job(selected_job.id, TRUE);
    END LOOP;
    UPDATE public.species_enrichment_jobs SET status = 'failed', attempts = max_attempts
    WHERE species_id = pg_temp.lookalike_fixture_id(11) AND content_group = 'lookalikes';
    IF EXISTS (SELECT 1 FROM public.claim_species_model_enrichment_jobs(50, '2001-01-01', ARRAY['lookalikes'])) THEN
        RAISE EXCEPTION 'recovery repeated a terminal versioned result, stole a running job, or bypassed backoff';
    END IF;
END;
$$;
SELECT extensions.pass('preview, grouped ordering, backoff, active leases and one-time legacy recovery hold');

DO $$
DECLARE
    outcome RECORD;
    invalid_input JSONB;
    rejected BOOLEAN;
BEGIN
    UPDATE public.species_dictionary
    SET similar_species = ARRAY['Obsolete name'], lookalikes_flash_attempted = FALSE
    WHERE id IN (pg_temp.lookalike_fixture_id(6), pg_temp.lookalike_fixture_id(7));
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(7), '[]', FALSE);
    IF outcome IS DISTINCT FROM ROW(0, 0, 0)
       OR (SELECT lookalikes_flash_attempted FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(7)) THEN
        RAISE EXCEPTION 'an unresolved empty result suppressed future enrichment';
    END IF;
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(6), '[]', TRUE);
    IF outcome IS DISTINCT FROM ROW(0, 0, 0)
       OR NOT (SELECT lookalikes_flash_attempted AND similar_species = ARRAY[]::TEXT[]
               FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(6)) THEN
        RAISE EXCEPTION 'a settled empty result did not clear stale names and remember its attempt';
    END IF;
    FOREACH invalid_input IN ARRAY ARRAY[
        '[{}, {}, {}, {}]'::JSONB,
        pg_catalog.JSONB_BUILD_ARRAY(pg_catalog.JSONB_BUILD_OBJECT('scientific_name', 'Missing proof')),
        pg_catalog.JSONB_BUILD_ARRAY(pg_temp.lookalike_fixture_candidate('Invalid key', 0))
    ] LOOP
        rejected := FALSE;
        BEGIN
            PERFORM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(1), invalid_input);
        EXCEPTION WHEN SQLSTATE '22023' THEN rejected := TRUE;
        END;
        IF NOT rejected THEN RAISE EXCEPTION 'persistence accepted an unbounded or unverified candidate'; END IF;
    END LOOP;
END;
$$;
SELECT extensions.pass('settled empty outcomes are cached while unresolved and invalid input stays retryable');

DO $$
DECLARE
    outcome RECORD;
    materialized_id UUID;
    generated_name TEXT;
    generated_genus TEXT;
BEGIN
    FOR generated_name, generated_genus IN VALUES
        ('Fixturegenus candidate', 'Fixturegenus'), ('Comparatus candidate', 'Comparatus')
    LOOP
        SELECT * INTO outcome FROM public.persist_species_model_lookalikes(
            pg_temp.lookalike_fixture_id(1),
            pg_catalog.JSONB_BUILD_ARRAY(pg_temp.lookalike_fixture_candidate(
                generated_name, CASE WHEN generated_genus = 'Fixturegenus' THEN 930001 ELSE 930002 END, generated_genus
            ))
        );
        IF outcome IS DISTINCT FROM ROW(1, 0, 0) THEN RAISE EXCEPTION 'verified missing candidate was not persisted'; END IF;
        SELECT id INTO materialized_id FROM public.species_dictionary
        WHERE scientific_name = generated_name AND gbif_taxon_key > 0 AND "order" = 'Rosales';
        IF materialized_id IS NULL THEN RAISE EXCEPTION 'candidate lacks its authoritative dictionary identity'; END IF;
        IF EXISTS (SELECT 1 FROM public.species_lookalikes
            WHERE species_id = materialized_id OR (lookalike_id = materialized_id AND species_id <> pg_temp.lookalike_fixture_id(1))) THEN
            RAISE EXCEPTION 'materialization fanned out into unvalidated reciprocal or same-genus relations';
        END IF;
        IF EXISTS (SELECT 1 FROM public.species_enrichment_jobs
            WHERE species_id = materialized_id AND content_group = 'lookalikes') THEN
            RAISE EXCEPTION 'materialization recursively queued another generation';
        END IF;
        IF (SELECT COUNT(*) FROM public.species_enrichment_jobs
            WHERE species_id = materialized_id AND content_group IN ('habitat', 'group_tags', 'gbif_wikipedia_reference')) <> 3 THEN
            RAISE EXCEPTION 'materialization lost the other dictionary hydration jobs';
        END IF;
    END LOOP;
    IF pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE) = 'on' THEN
        RAISE EXCEPTION 'materialization marker leaked outside its insert';
    END IF;
    INSERT INTO public.species_dictionary (scientific_name, kingdom, "order", family, genus)
    VALUES ('Ordinaryfixture first', 'Plantae', 'Rosales', 'Rosaceae', 'Ordinaryfixture');
    INSERT INTO public.species_dictionary (scientific_name, kingdom, "order", family, genus)
    VALUES ('Ordinaryfixture second', 'Plantae', 'Rosales', 'Rosaceae', 'Ordinaryfixture');
    IF NOT EXISTS (SELECT 1 FROM public.species_enrichment_jobs AS job
        JOIN public.species_dictionary AS species ON species.id = job.species_id
        WHERE species.scientific_name = 'Ordinaryfixture first' AND job.content_group = 'lookalikes') THEN
        RAISE EXCEPTION 'ordinary inserts lost automatic lookalike jobs';
    END IF;
    IF (SELECT COUNT(*) FROM public.species_lookalikes AS relation
        JOIN public.species_dictionary AS species ON species.id = relation.species_id
        WHERE species.genus = 'Ordinaryfixture') <> 2 THEN
        RAISE EXCEPTION 'ordinary inserts lost reciprocal same-genus links';
    END IF;
END;
$$;
SELECT extensions.pass('same-genus and cross-genus materialization is bounded while ordinary insert behavior is preserved');

DO $$
DECLARE
    outcome RECORD;
    initial_relation JSONB;
    repeated_relation JSONB;
BEGIN
    SELECT pg_catalog.JSONB_AGG(pg_catalog.TO_JSONB(relation) ORDER BY lookalike_id) INTO initial_relation
    FROM public.species_lookalikes AS relation
    WHERE species_id = pg_temp.lookalike_fixture_id(1)
      AND lookalike_id IN (pg_temp.lookalike_fixture_id(2), pg_temp.lookalike_fixture_id(3));
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(
        pg_temp.lookalike_fixture_id(1), pg_catalog.JSONB_BUILD_ARRAY(
            pg_temp.lookalike_fixture_candidate('Recoveryfixture species2', 920002),
            pg_temp.lookalike_fixture_candidate('Recoveryfixture species3', 920003)
        )
    );
    IF outcome IS DISTINCT FROM ROW(1, 0, 1) THEN RAISE EXCEPTION 'reviewed rejection was revived or valid curation was lost'; END IF;
    SELECT pg_catalog.JSONB_AGG(pg_catalog.TO_JSONB(relation) ORDER BY lookalike_id) INTO repeated_relation
    FROM public.species_lookalikes AS relation
    WHERE species_id = pg_temp.lookalike_fixture_id(1)
      AND lookalike_id IN (pg_temp.lookalike_fixture_id(2), pg_temp.lookalike_fixture_id(3));
    IF repeated_relation IS DISTINCT FROM initial_relation THEN RAISE EXCEPTION 'model persistence changed reviewed relationship data'; END IF;
    IF NOT (SELECT similar_species @> ARRAY['Fixturegenus candidate', 'Comparatus candidate', 'Recoveryfixture species2']::TEXT[]
        AND NOT similar_species @> ARRAY['Recoveryfixture species3']::TEXT[]
        FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(1)) THEN
        RAISE EXCEPTION 'compatibility cache omitted earlier model or curated edges, or exposed a rejected edge';
    END IF;
    IF NOT (SELECT source = 'manual_curation' AND source_detail = 'Reviewed fixture'
        FROM public.species_content_provenance
        WHERE species_id = pg_temp.lookalike_fixture_id(1) AND content_key = 'lookalikes') THEN
        RAISE EXCEPTION 'model persistence overwrote curated provenance';
    END IF;
    PERFORM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(1),
        pg_catalog.JSONB_BUILD_ARRAY(pg_temp.lookalike_fixture_candidate('Comparatus candidate', 930002)));
    IF (SELECT COUNT(*) FROM public.species_lookalikes AS relation
        JOIN public.species_dictionary AS species ON species.id = relation.lookalike_id
        WHERE relation.species_id = pg_temp.lookalike_fixture_id(1) AND species.scientific_name = 'Comparatus candidate') <> 1 THEN
        RAISE EXCEPTION 'replaying a candidate produced duplicate relationships';
    END IF;
END;
$$;
SELECT extensions.pass('reviewed decisions, curated provenance, all cached edges and idempotent replay are preserved');

DO $$
DECLARE
    outcome RECORD;
    hydrated JSONB;
    incompatible JSONB;
    rejected BOOLEAN := FALSE;
BEGIN
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(7),
        pg_catalog.JSONB_BUILD_ARRAY(pg_temp.lookalike_fixture_candidate('Recoveryfixture species4', 920044)));
    IF outcome IS DISTINCT FROM ROW(0, 1, 0)
       OR (SELECT lookalikes_flash_attempted FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(7))
       OR (SELECT gbif_taxon_key FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(4)) <> 920004 THEN
        RAISE EXCEPTION 'a conflicting stored identity was overwritten or became a terminal empty result';
    END IF;
    hydrated := pg_temp.lookalike_fixture_candidate('Recoveryfixture species5', 920005);
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(1), pg_catalog.JSONB_BUILD_ARRAY(hydrated, hydrated));
    IF outcome IS DISTINCT FROM ROW(1, 0, 1)
       OR NOT (SELECT gbif_taxon_key = 920005 AND kingdom = 'Plantae' AND "order" = 'Rosales'
               FROM public.species_dictionary WHERE id = pg_temp.lookalike_fixture_id(5)) THEN
        RAISE EXCEPTION 'missing taxonomy was not hydrated or duplicate input was not fully accounted for';
    END IF;
    incompatible := pg_catalog.JSONB_SET(
        pg_temp.lookalike_fixture_candidate('Incompatible fixture', 930003), '{gbif,order}', '"Pinales"'
    );
    SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(1), pg_catalog.JSONB_BUILD_ARRAY(
        incompatible, pg_temp.lookalike_fixture_candidate('Selfalias fixture', 920001)
    ));
    IF outcome IS DISTINCT FROM ROW(0, 0, 2)
       OR EXISTS (SELECT 1 FROM public.species_dictionary WHERE scientific_name IN ('Incompatible fixture', 'Selfalias fixture')) THEN
        RAISE EXCEPTION 'incompatible or self identities were materialized';
    END IF;
    BEGIN
        PERFORM public.persist_species_model_lookalikes(pg_temp.lookalike_fixture_id(18), '[]');
    EXCEPTION WHEN SQLSTATE '55000' THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'a primary taxonomy race was mistaken for successful no-data'; END IF;
END;
$$;
SELECT extensions.pass('identity conflicts retry, missing taxonomy hydrates, and duplicate/self/incompatible candidates cannot create false links');

SELECT * FROM extensions.finish();
ROLLBACK;

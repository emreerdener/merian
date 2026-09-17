\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(7);
-- BEGIN SYNTHETIC FIXTURE
-- Synthetic fixtures shared by pgTAP and disposable before/after benchmarks.
-- The caller owns the transaction and must roll it back.
CREATE FUNCTION pg_temp.io_species_id(value INTEGER)
RETURNS UUID LANGUAGE SQL IMMUTABLE AS $$
    SELECT ('00000000-0000-4000-8000-00000000fd' || pg_catalog.LPAD(value::TEXT, 2, '0'))::UUID;
$$;

CREATE FUNCTION pg_temp.io_candidate(value INTEGER)
RETURNS JSONB LANGUAGE SQL IMMUTABLE AS $$
    SELECT pg_catalog.JSONB_BUILD_OBJECT(
        'scientific_name', 'Iofixture species' || value,
        'reason', 'Synthetic field marks', 'visual_traits', ARRAY['leaf shape'], 'confidence', 0.9,
        'gbif', pg_catalog.JSONB_BUILD_OBJECT(
            'scientific_name', 'Iofixture species' || value, 'gbif_taxon_key', 940000 + value,
            'rank', 'SPECIES', 'status', 'ACCEPTED', 'kingdom', 'Plantae',
            'phylum', 'Tracheophyta', 'class', 'Magnoliopsida',
            'order', 'Rosales', 'family', 'Rosaceae', 'genus', 'Iofixture' || value
        )
    );
$$;

INSERT INTO public.species_dictionary (
    id, scientific_name, common_names, gbif_taxon_key,
    kingdom, phylum, class, "order", family, genus
)
SELECT pg_temp.io_species_id(value), 'Iofixture species' || value,
    '{"en":"Synthetic species"}'::JSONB, 940000 + value,
    'Plantae', 'Tracheophyta', 'Magnoliopsida', 'Rosales', 'Rosaceae', 'Iofixture' || value
FROM pg_catalog.GENERATE_SERIES(1, 4) AS series(value);

CREATE TEMP TABLE io_row_updates (relation_name TEXT NOT NULL);
CREATE FUNCTION pg_temp.count_io_updates()
RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO pg_temp.io_row_updates VALUES (TG_TABLE_NAME);
    RETURN NULL;
END;
$$;
CREATE TRIGGER io_fixture_dictionary_updates AFTER UPDATE ON public.species_dictionary
FOR EACH ROW EXECUTE FUNCTION pg_temp.count_io_updates();
CREATE TRIGGER io_fixture_relation_updates AFTER UPDATE ON public.species_lookalikes
FOR EACH ROW EXECUTE FUNCTION pg_temp.count_io_updates();
CREATE TRIGGER io_fixture_provenance_updates AFTER UPDATE ON public.species_content_provenance
FOR EACH ROW EXECUTE FUNCTION pg_temp.count_io_updates();
-- END SYNTHETIC FIXTURE

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('authenticated', 'public.persist_species_model_lookalikes(uuid,jsonb,boolean)', 'EXECUTE'),
    'optimized persistence retains its service-only boundary'
);

SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(1),
    pg_catalog.JSONB_BUILD_ARRAY(pg_temp.io_candidate(2)));
CREATE TEMP TABLE io_initial_state AS
SELECT 'dictionary' AS kind, id, ctid AS tuple_id, pg_catalog.TO_JSONB(species) AS value
FROM public.species_dictionary AS species WHERE id IN (pg_temp.io_species_id(1), pg_temp.io_species_id(2))
UNION ALL
SELECT 'relation', species_id, ctid, pg_catalog.TO_JSONB(relation)
FROM public.species_lookalikes AS relation
WHERE species_id = pg_temp.io_species_id(1) AND lookalike_id = pg_temp.io_species_id(2);
UPDATE public.species_content_provenance SET last_refreshed_at = '2000-01-01', refresh_after = '2000-02-01'
WHERE species_id = pg_temp.io_species_id(1) AND content_key = 'lookalikes';
TRUNCATE pg_temp.io_row_updates;

DO $$
DECLARE outcome RECORD;
BEGIN
    FOR repetition IN 1..50 LOOP
        SELECT * INTO outcome FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(1),
            pg_catalog.JSONB_BUILD_ARRAY(pg_temp.io_candidate(2)));
        IF outcome IS DISTINCT FROM ROW(1, 0, 0) THEN
            RAISE EXCEPTION 'unchanged replay lost persisted accounting';
        END IF;
    END LOOP;
END;
$$;
SELECT extensions.ok(
    NOT EXISTS (SELECT 1 FROM pg_temp.io_row_updates WHERE relation_name IN ('species_dictionary', 'species_lookalikes'))
    AND NOT EXISTS (
        SELECT 1 FROM pg_temp.io_initial_state AS initial
        JOIN public.species_dictionary AS species ON initial.kind = 'dictionary' AND species.id = initial.id
        WHERE species.ctid <> initial.tuple_id OR pg_catalog.TO_JSONB(species) IS DISTINCT FROM initial.value
    )
    AND NOT EXISTS (
        SELECT 1 FROM pg_temp.io_initial_state AS initial
        JOIN public.species_lookalikes AS relation ON initial.kind = 'relation' AND relation.species_id = initial.id
        WHERE relation.ctid <> initial.tuple_id OR pg_catalog.TO_JSONB(relation) IS DISTINCT FROM initial.value
    ),
    'fifty identical results preserve accounting, row versions, and data timestamps without dictionary/relation updates'
);
SELECT extensions.ok(
    (SELECT COUNT(*) = 50 FROM pg_temp.io_row_updates WHERE relation_name = 'species_content_provenance')
    AND (SELECT last_refreshed_at = NOW() AND refresh_after = NOW() + INTERVAL '30 days'
         FROM public.species_content_provenance WHERE species_id = pg_temp.io_species_id(1) AND content_key = 'lookalikes'),
    'unchanged valid model refreshes still advance provenance freshness'
);

TRUNCATE pg_temp.io_row_updates;
SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(1),
    pg_catalog.JSONB_BUILD_ARRAY(pg_catalog.JSONB_SET(pg_temp.io_candidate(2), '{reason}', '"Changed field marks"')));
SELECT extensions.ok(
    (SELECT COUNT(*) = 1 FROM pg_temp.io_row_updates WHERE relation_name = 'species_lookalikes')
    AND NOT EXISTS (SELECT 1 FROM pg_temp.io_row_updates WHERE relation_name = 'species_dictionary')
    AND (SELECT reason = 'Changed field marks' FROM public.species_lookalikes
         WHERE species_id = pg_temp.io_species_id(1) AND lookalike_id = pg_temp.io_species_id(2)),
    'changed relationship values persist without rewriting unchanged dictionary rows'
);

UPDATE public.species_dictionary SET gbif_taxon_key = NULL, kingdom = 'Unknown', "order" = NULL, family = 'Unknown'
WHERE id = pg_temp.io_species_id(3);
TRUNCATE pg_temp.io_row_updates;
SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(1),
    pg_catalog.JSONB_BUILD_ARRAY(pg_temp.io_candidate(3)));
SELECT extensions.ok(
    (SELECT gbif_taxon_key = 940003 AND kingdom = 'Plantae' AND "order" = 'Rosales' AND family = 'Rosaceae'
     FROM public.species_dictionary WHERE id = pg_temp.io_species_id(3))
    AND (SELECT similar_species @> ARRAY['Iofixture species2', 'Iofixture species3']::TEXT[]
         FROM public.species_dictionary WHERE id = pg_temp.io_species_id(1)),
    'placeholder taxonomy hydrates and compatibility cache retains all nonrejected edges'
);

SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(4), '[]', TRUE);
TRUNCATE pg_temp.io_row_updates;
SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(4), '[]', TRUE);
SELECT extensions.ok(
    NOT EXISTS (SELECT 1 FROM pg_temp.io_row_updates)
    AND (SELECT lookalikes_flash_attempted AND similar_species = ARRAY[]::TEXT[]
         FROM public.species_dictionary WHERE id = pg_temp.io_species_id(4)),
    'repeated verified empty result performs no updates'
);

UPDATE public.species_lookalikes SET source = 'manual_curation', review_status = 'approved'
WHERE species_id = pg_temp.io_species_id(1) AND lookalike_id = pg_temp.io_species_id(2);
UPDATE public.species_content_provenance SET source = 'manual_curation', last_refreshed_at = '2000-01-01'
WHERE species_id = pg_temp.io_species_id(1) AND content_key = 'lookalikes';
TRUNCATE pg_temp.io_row_updates;
SELECT * FROM public.persist_species_model_lookalikes(pg_temp.io_species_id(1),
    pg_catalog.JSONB_BUILD_ARRAY(pg_temp.io_candidate(2)));
SELECT extensions.ok(
    NOT EXISTS (SELECT 1 FROM pg_temp.io_row_updates)
    AND (SELECT source = 'manual_curation' AND last_refreshed_at = '2000-01-01'
         FROM public.species_content_provenance WHERE species_id = pg_temp.io_species_id(1) AND content_key = 'lookalikes'),
    'reviewed relationship and curated freshness remain untouched'
);

SELECT * FROM extensions.finish();
ROLLBACK;

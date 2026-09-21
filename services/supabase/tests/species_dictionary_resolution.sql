\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(17);

SELECT extensions.ok(EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS c ON c.oid = i.indexrelid
    WHERE c.oid = 'public.idx_species_dictionary_resolution_gbif_key'::regclass
      AND i.indisvalid
      AND pg_catalog.pg_get_indexdef(c.oid) LIKE '%(gbif_taxon_key)%WHERE (gbif_taxon_key IS NOT NULL)%'
), 'GBIF identity lookup has a valid partial index');

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.resolve_verified_dictionary_species(jsonb)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', 'public.resolve_verified_dictionary_species(jsonb)', 'EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('authenticated', 'public.admit_species_dictionary_resolution(uuid)', 'EXECUTE'),
    'resolution routines are service-only'
);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.resolve_verified_dictionary_species('{}')$$, '42501', NULL, 'clients cannot forge GBIF proof');
RESET ROLE;

CREATE FUNCTION pg_temp.resolution_taxon() RETURNS JSONB LANGUAGE SQL AS $$
    SELECT '{"scientific_name":"Resolutionfixture species","gbif_taxon_key":987000001,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae","phylum":"Tracheophyta","class":"Magnoliopsida","order":"Rosales","family":"Rosaceae","genus":"Resolutionfixture"}'::JSONB;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.resolution_taxon() TO service_role;
CREATE TEMP TABLE resolution_ids(id UUID);
GRANT ALL ON resolution_ids TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.resolve_verified_dictionary_species('{}')$$, '22023', 'invalid_verified_species', 'invalid proof fails closed');
INSERT INTO resolution_ids SELECT public.resolve_verified_dictionary_species(pg_temp.resolution_taxon());
SELECT extensions.is(public.resolve_verified_dictionary_species(pg_temp.resolution_taxon()), (SELECT id FROM resolution_ids), 'duplicate resolution reuses canonical UUID');
SELECT extensions.is(public.resolve_verified_dictionary_species(pg_temp.resolution_taxon() || '{"scientific_name":"Resolutionfixture accepted"}'::JSONB), (SELECT id FROM resolution_ids), 'accepted-name changes reuse the existing GBIF identity');
SELECT extensions.throws_ok($$SELECT public.resolve_verified_dictionary_species(pg_temp.resolution_taxon() || '{"gbif_taxon_key":987000002}'::JSONB)$$, '22023', 'species_resolution_identity_conflict', 'conflicting identity cannot replace the record');
SELECT extensions.ok(pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE) IS DISTINCT FROM 'on', 'transaction flag is restored');
RESET ROLE;
SELECT extensions.is((SELECT COUNT(*)::INTEGER FROM public.species_dictionary WHERE scientific_name = 'Resolutionfixture species'), 1, 'one canonical row exists');
INSERT INTO public.species_dictionary(scientific_name, common_names, gbif_taxon_key, kingdom, phylum, class, "order", family, genus, native_region)
SELECT 'Resolutionfixture duplicate', common_names, gbif_taxon_key, kingdom, phylum, class, "order", family, 'Differentfixture', native_region
FROM public.species_dictionary WHERE id IN (SELECT id FROM resolution_ids);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.resolve_verified_dictionary_species(pg_temp.resolution_taxon())$$, '22023', 'species_resolution_ambiguous_identity', 'preexisting duplicate taxon IDs require explicit repair');
RESET ROLE;
DELETE FROM public.species_dictionary WHERE scientific_name = 'Resolutionfixture duplicate';
SELECT extensions.is((SELECT COUNT(*)::INTEGER FROM public.species_lookalikes WHERE species_id IN (SELECT id FROM resolution_ids) OR lookalike_id IN (SELECT id FROM resolution_ids)), 0, 'resolution creates no speculative relationships');
SELECT extensions.is((SELECT COUNT(*)::INTEGER FROM public.species_enrichment_jobs WHERE species_id IN (SELECT id FROM resolution_ids) AND content_group = 'lookalikes'), 0, 'resolution does not recursively generate species');
UPDATE public.species_dictionary SET common_names = '{"en":"Curated fixture"}', wikipedia_overview = 'Curated overview' WHERE id IN (SELECT id FROM resolution_ids);
SET LOCAL ROLE service_role;
SELECT public.resolve_verified_dictionary_species(pg_temp.resolution_taxon());
SELECT public.admit_species_dictionary_resolution('00000000-0000-4000-8000-000000000099') FROM pg_catalog.GENERATE_SERIES(1,6);
SELECT extensions.throws_ok($$SELECT public.admit_species_dictionary_resolution('00000000-0000-4000-8000-000000000099')$$, 'P0001', 'species_resolution_rate_limited', 'seventh request is denied');
RESET ROLE;
SELECT extensions.is((SELECT wikipedia_overview FROM public.species_dictionary WHERE id IN (SELECT id FROM resolution_ids)), 'Curated overview', 'existing curated content is unchanged');
UPDATE public.species_dictionary SET gbif_taxon_key = NULL WHERE id IN (SELECT id FROM resolution_ids);
SET LOCAL ROLE service_role;
SELECT extensions.is(public.resolve_verified_dictionary_species(pg_temp.resolution_taxon()), (SELECT id FROM resolution_ids), 'legacy exact-name row retains its UUID');
SELECT extensions.is((SELECT gbif_taxon_key FROM public.species_dictionary WHERE id IN (SELECT id FROM resolution_ids)), 987000001, 'legacy row remembers the verified GBIF key');
SELECT extensions.is(public.resolve_verified_dictionary_species(pg_temp.resolution_taxon() || '{"scientific_name":"Resolutionfixture renamed"}'::JSONB), (SELECT id FROM resolution_ids), 'later accepted-name change reuses the verified legacy row');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

-- Ensure every species dictionary row has durable background hydration work.
--
-- New rows can be created by scans, Community ID materialization, taxonomy
-- imports, or manual service-role repair. Centralizing the enqueue step at the
-- database layer keeps those creation paths from drifting.

CREATE OR REPLACE FUNCTION public.species_dictionary_taxonomy_value_is_usable(raw_value TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT NULLIF(BTRIM(COALESCE(raw_value, '')), '') IS NOT NULL
       AND LOWER(BTRIM(raw_value)) NOT IN (
            'unknown',
            'unavailable',
            'not available',
            'n/a',
            'none',
            'null',
            'undefined'
       );
$$;

CREATE OR REPLACE FUNCTION public.species_dictionary_missing_enrichment_groups(
    species_row public.species_dictionary
)
RETURNS TEXT[]
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    missing_groups TEXT[] := ARRAY[]::TEXT[];
    has_reference_imagery BOOLEAN := FALSE;
    has_public_overview BOOLEAN := FALSE;
    has_habitat_description BOOLEAN := FALSE;
    has_gbif_taxon BOOLEAN := FALSE;
    has_meaningful_taxonomy BOOLEAN := FALSE;
    has_group_tags BOOLEAN := FALSE;
    has_lookalikes BOOLEAN := FALSE;
BEGIN
    IF (species_row).id IS NULL
       OR NULLIF(BTRIM(COALESCE((species_row).scientific_name, '')), '') IS NULL THEN
        RETURN missing_groups;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.species_reference_images ref
        WHERE ref.species_id = (species_row).id
          AND NULLIF(BTRIM(COALESCE(ref.url, '')), '') IS NOT NULL
        LIMIT 1
    )
    INTO has_reference_imagery;

    has_reference_imagery := has_reference_imagery
        OR NULLIF(BTRIM(COALESCE((species_row).reference_image_url, '')), '') IS NOT NULL;
    has_public_overview := LENGTH(BTRIM(COALESCE((species_row).wikipedia_overview, ''))) >= 60;
    has_habitat_description := NULLIF(BTRIM(COALESCE((species_row).habitat_description, '')), '') IS NOT NULL;
    has_gbif_taxon := COALESCE((species_row).gbif_taxon_key, 0) > 0;
    has_meaningful_taxonomy :=
        public.species_dictionary_taxonomy_value_is_usable((species_row).kingdom)
        AND (
            public.species_dictionary_taxonomy_value_is_usable((species_row).phylum)
            OR public.species_dictionary_taxonomy_value_is_usable((species_row)."class")
            OR public.species_dictionary_taxonomy_value_is_usable((species_row)."order")
            OR public.species_dictionary_taxonomy_value_is_usable((species_row).family)
            OR public.species_dictionary_taxonomy_value_is_usable((species_row).genus)
        );
    has_group_tags := COALESCE(ARRAY_LENGTH((species_row).group_tags, 1), 0) > 0;

    SELECT EXISTS (
        SELECT 1
        FROM public.species_lookalikes lookalike
        WHERE lookalike.species_id = (species_row).id
          AND COALESCE(lookalike.review_status, '') <> 'rejected'
        LIMIT 1
    )
    INTO has_lookalikes;

    IF NOT (
        has_reference_imagery
        AND has_public_overview
        AND has_gbif_taxon
        AND has_meaningful_taxonomy
    ) THEN
        missing_groups := missing_groups || 'gbif_wikipedia_reference';
    END IF;

    IF NOT has_habitat_description THEN
        missing_groups := missing_groups || 'habitat';
    END IF;

    IF NOT has_lookalikes THEN
        missing_groups := missing_groups || 'lookalikes';
    END IF;

    IF NOT has_group_tags THEN
        missing_groups := missing_groups || 'group_tags';
    END IF;

    RETURN missing_groups;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_species_dictionary_enrichment_jobs()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    missing_groups TEXT[];
BEGIN
    missing_groups := public.species_dictionary_missing_enrichment_groups(NEW);

    IF COALESCE(ARRAY_LENGTH(missing_groups, 1), 0) > 0 THEN
        PERFORM public.enqueue_species_enrichment_jobs(
            NEW.id,
            'species_dictionary_insert',
            90,
            missing_groups
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_species_dictionary_enqueue_enrichment_jobs
    ON public.species_dictionary;

CREATE TRIGGER trg_species_dictionary_enqueue_enrichment_jobs
AFTER INSERT ON public.species_dictionary
FOR EACH ROW
EXECUTE FUNCTION public.enqueue_species_dictionary_enrichment_jobs();

DO $$
DECLARE
    queued_count BIGINT := 0;
BEGIN
    WITH sparse_rows AS (
        SELECT
            sd.id,
            public.species_dictionary_missing_enrichment_groups(sd) AS missing_groups
        FROM public.species_dictionary sd
    )
    SELECT COALESCE(SUM(public.enqueue_species_enrichment_jobs(
        sparse_rows.id,
        'species_dictionary_sparse_backfill',
        80,
        sparse_rows.missing_groups
    )), 0)
    INTO queued_count
    FROM sparse_rows
    WHERE COALESCE(ARRAY_LENGTH(sparse_rows.missing_groups, 1), 0) > 0;

    RAISE NOTICE 'Queued % species dictionary enrichment jobs during sparse backfill.', queued_count;
END;
$$;

REVOKE ALL ON FUNCTION public.species_dictionary_taxonomy_value_is_usable(TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.species_dictionary_missing_enrichment_groups(public.species_dictionary)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_species_dictionary_enrichment_jobs()
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.species_dictionary_taxonomy_value_is_usable(TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.species_dictionary_missing_enrichment_groups(public.species_dictionary)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_species_dictionary_enrichment_jobs()
    TO service_role;

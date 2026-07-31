-- Build a canonical, service-owned country occurrence index for the species
-- dictionary. GBIF occurrence facets are evidence that a taxon has been
-- recorded in a country; they are intentionally not described as native range.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE public.species_country_occurrences (
    species_id UUID NOT NULL
        REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    country_code TEXT NOT NULL,
    occurrence_count BIGINT NOT NULL,
    gbif_taxon_key BIGINT NOT NULL,
    source TEXT NOT NULL DEFAULT 'gbif_occurrence',
    last_refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (species_id, country_code),
    CONSTRAINT species_country_occurrences_country_code_check
        CHECK (
            country_code = UPPER(country_code)
            AND country_code ~ '^[A-Z]{2}$'
        ),
    CONSTRAINT species_country_occurrences_count_check
        CHECK (occurrence_count > 0),
    CONSTRAINT species_country_occurrences_gbif_key_check
        CHECK (gbif_taxon_key > 0),
    CONSTRAINT species_country_occurrences_source_check
        CHECK (source = 'gbif_occurrence')
);

COMMENT ON TABLE public.species_country_occurrences IS
    'Service-owned GBIF occurrence counts by species and ISO 3166-1 alpha-2 country; occurrence evidence is not a native-range assertion.';

CREATE INDEX idx_species_country_occurrences_country
    ON public.species_country_occurrences (
        country_code,
        occurrence_count DESC,
        species_id
    );

ALTER TABLE public.species_country_occurrences
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES
    ON TABLE public.species_country_occurrences
    FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, DELETE
    ON TABLE public.species_country_occurrences
    TO service_role;

-- New dictionary rows still need a value for the legacy free-text column, but
-- callers can now omit it. On conflict, omission preserves any curated value
-- rather than replacing it with the old "Unknown" sentinel.
ALTER TABLE public.species_dictionary
    ALTER COLUMN native_region SET DEFAULT 'Unknown';

ALTER TABLE public.species_content_provenance
    DROP CONSTRAINT IF EXISTS species_content_provenance_content_key_check;

ALTER TABLE public.species_content_provenance
    ADD CONSTRAINT species_content_provenance_content_key_check
    CHECK (content_key IN (
        'common_names',
        'alternative_common_names',
        'taxonomy',
        'wikipedia_url',
        'wikipedia_overview',
        'habitat_description',
        'gbif_taxon_key',
        'reference_images',
        'country_occurrences',
        'lookalikes',
        'group_tags',
        'iucn_red_list_status',
        'hazard_type'
    )) NOT VALID;

ALTER TABLE public.species_content_provenance
    VALIDATE CONSTRAINT species_content_provenance_content_key_check;

CREATE OR REPLACE FUNCTION public.replace_species_country_occurrences(
    p_species_id UUID,
    p_gbif_taxon_key BIGINT,
    p_occurrences JSONB,
    p_refreshed_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    replaced_count INTEGER := 0;
BEGIN
    IF p_species_id IS NULL
       OR p_gbif_taxon_key IS NULL
       OR p_gbif_taxon_key <= 0
       OR p_occurrences IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_occurrences) <> 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_occurrences) > 300 THEN
        RAISE EXCEPTION 'species_country_occurrences_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    -- Serialize against taxon rematches without requiring UPDATE privilege on
    -- the read-only dictionary table merely to take a row lock. The GBIF-key
    -- invalidation trigger takes this same transaction-scoped lock.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-species-country-occurrence:' || p_species_id::TEXT,
            0::BIGINT
        )
    );

    PERFORM 1
    FROM public.species_dictionary AS species
    WHERE species.id = p_species_id
      AND species.gbif_taxon_key::BIGINT = p_gbif_taxon_key;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'species_country_occurrences_taxon_mismatch'
            USING ERRCODE = '23503';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_occurrences) AS item(value)
        WHERE pg_catalog.JSONB_TYPEOF(item.value) <> 'object'
           OR COALESCE(item.value ->> 'country_code', '') !~ '^[A-Za-z]{2}$'
           OR pg_catalog.JSONB_TYPEOF(item.value -> 'occurrence_count') <> 'number'
           OR COALESCE(item.value ->> 'occurrence_count', '') !~ '^[0-9]+$'
           OR (item.value ->> 'occurrence_count')::NUMERIC <= 0
           OR (item.value ->> 'occurrence_count')::NUMERIC
                > 9223372036854775807::NUMERIC
    ) THEN
        RAISE EXCEPTION 'species_country_occurrences_invalid_entry'
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.species_country_occurrences AS occurrence
    WHERE occurrence.species_id = p_species_id;

    INSERT INTO public.species_country_occurrences (
        species_id,
        country_code,
        occurrence_count,
        gbif_taxon_key,
        source,
        last_refreshed_at,
        updated_at
    )
    SELECT
        p_species_id,
        UPPER(item.value ->> 'country_code'),
        MAX((item.value ->> 'occurrence_count')::BIGINT),
        p_gbif_taxon_key,
        'gbif_occurrence',
        COALESCE(p_refreshed_at, NOW()),
        COALESCE(p_refreshed_at, NOW())
    FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_occurrences) AS item(value)
    GROUP BY UPPER(item.value ->> 'country_code');

    GET DIAGNOSTICS replaced_count = ROW_COUNT;
    RETURN replaced_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_species_dictionary_country_summaries(
    p_country_code TEXT DEFAULT NULL,
    p_min_occurrence_count BIGINT DEFAULT 1,
    p_max_rows INTEGER DEFAULT 24
)
RETURNS TABLE (
    country_code TEXT,
    species_count INTEGER,
    representative_species_id UUID
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    SELECT
        occurrence.country_code,
        pg_catalog.COUNT(*)::INTEGER AS species_count,
        (
            pg_catalog.ARRAY_AGG(
                occurrence.species_id
                ORDER BY
                    occurrence.occurrence_count DESC,
                    occurrence.species_id
            )
        )[1] AS representative_species_id
    FROM public.species_country_occurrences AS occurrence
    INNER JOIN public.species_dictionary AS species
        ON species.id = occurrence.species_id
       AND species.gbif_taxon_key::BIGINT = occurrence.gbif_taxon_key
    WHERE occurrence.occurrence_count >= GREATEST(
            COALESCE(p_min_occurrence_count, 1),
            1
        )
      AND NULLIF(pg_catalog.BTRIM(species.scientific_name), '') IS NOT NULL
      AND (
            p_country_code IS NULL
            OR occurrence.country_code = UPPER(pg_catalog.BTRIM(p_country_code))
      )
    GROUP BY occurrence.country_code
    ORDER BY
        pg_catalog.COUNT(*) DESC,
        occurrence.country_code
    LIMIT LEAST(
        GREATEST(COALESCE(p_max_rows, 24), 1),
        250
    );
$function$;

CREATE OR REPLACE FUNCTION public.invalidate_species_country_occurrences_on_gbif_change()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-species-country-occurrence:' || NEW.id::TEXT,
            0::BIGINT
        )
    );

    DELETE FROM public.species_country_occurrences AS occurrence
    WHERE occurrence.species_id = NEW.id;

    UPDATE public.species_content_provenance AS provenance
    SET
        refresh_after = pg_catalog.NOW(),
        metadata = provenance.metadata || pg_catalog.JSONB_BUILD_OBJECT(
            'invalidated_by', 'gbif_taxon_key_change',
            'previous_gbif_taxon_key', OLD.gbif_taxon_key,
            'current_gbif_taxon_key', NEW.gbif_taxon_key
        )
    WHERE provenance.species_id = NEW.id
      AND provenance.content_key = 'country_occurrences';

    PERFORM public.enqueue_species_enrichment_jobs(
        NEW.id,
        'species_gbif_taxon_key_change',
        70,
        ARRAY['gbif_wikipedia_reference']::TEXT[]
    );

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_species_country_occurrences_invalidate_gbif_change
    ON public.species_dictionary;

CREATE TRIGGER trg_species_country_occurrences_invalidate_gbif_change
AFTER UPDATE OF gbif_taxon_key ON public.species_dictionary
FOR EACH ROW
WHEN (OLD.gbif_taxon_key IS DISTINCT FROM NEW.gbif_taxon_key)
EXECUTE FUNCTION public.invalidate_species_country_occurrences_on_gbif_change();

REVOKE ALL
    ON FUNCTION public.replace_species_country_occurrences(
        UUID,
        BIGINT,
        JSONB,
        TIMESTAMPTZ
    )
    FROM PUBLIC, anon, authenticated;
REVOKE ALL
    ON FUNCTION public.get_species_dictionary_country_summaries(
        TEXT,
        BIGINT,
        INTEGER
    )
    FROM PUBLIC, anon, authenticated;
REVOKE ALL
    ON FUNCTION public.invalidate_species_country_occurrences_on_gbif_change()
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
    ON FUNCTION public.replace_species_country_occurrences(
        UUID,
        BIGINT,
        JSONB,
        TIMESTAMPTZ
    )
    TO service_role;
GRANT EXECUTE
    ON FUNCTION public.get_species_dictionary_country_summaries(
        TEXT,
        BIGINT,
        INTEGER
    )
    TO service_role;
GRANT EXECUTE
    ON FUNCTION public.invalidate_species_country_occurrences_on_gbif_change()
    TO service_role;

-- Country occurrence coverage is part of the existing GBIF/Wikipedia worker
-- group, so both new rows and this migration's backfill use the durable queue
-- that is already scheduled and retried.
CREATE OR REPLACE FUNCTION public.species_dictionary_missing_enrichment_groups(
    species_row public.species_dictionary
)
RETURNS TEXT[]
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    missing_groups TEXT[] := ARRAY[]::TEXT[];
    has_reference_imagery BOOLEAN := FALSE;
    has_public_overview BOOLEAN := FALSE;
    has_habitat_description BOOLEAN := FALSE;
    has_gbif_taxon BOOLEAN := FALSE;
    has_meaningful_taxonomy BOOLEAN := FALSE;
    has_country_occurrences BOOLEAN := FALSE;
    has_group_tags BOOLEAN := FALSE;
    has_lookalikes BOOLEAN := FALSE;
BEGIN
    IF (species_row).id IS NULL
       OR NULLIF(BTRIM(COALESCE((species_row).scientific_name, '')), '') IS NULL THEN
        RETURN missing_groups;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.species_reference_images AS ref
        WHERE ref.species_id = (species_row).id
          AND NULLIF(BTRIM(COALESCE(ref.url, '')), '') IS NOT NULL
        LIMIT 1
    )
    INTO has_reference_imagery;

    SELECT EXISTS (
        SELECT 1
        FROM public.species_country_occurrences AS occurrence
        WHERE occurrence.species_id = (species_row).id
          AND occurrence.occurrence_count > 0
          AND occurrence.gbif_taxon_key = (species_row).gbif_taxon_key::BIGINT
        LIMIT 1
    )
    INTO has_country_occurrences;

    has_country_occurrences := has_country_occurrences OR EXISTS (
        SELECT 1
        FROM public.species_content_provenance AS provenance
        WHERE provenance.species_id = (species_row).id
          AND provenance.content_key = 'country_occurrences'
          AND provenance.metadata ->> 'gbif_taxon_key'
                = (species_row).gbif_taxon_key::TEXT
        LIMIT 1
    );

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
        FROM public.species_lookalikes AS lookalike
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
        AND has_country_occurrences
    ) THEN
        missing_groups := ARRAY_APPEND(
            missing_groups,
            'gbif_wikipedia_reference'
        );
    END IF;

    IF NOT has_habitat_description THEN
        missing_groups := ARRAY_APPEND(missing_groups, 'habitat');
    END IF;

    IF NOT has_lookalikes THEN
        missing_groups := ARRAY_APPEND(missing_groups, 'lookalikes');
    END IF;

    IF NOT has_group_tags THEN
        missing_groups := ARRAY_APPEND(missing_groups, 'group_tags');
    END IF;

    RETURN missing_groups;
END;
$function$;

DO $backfill$
DECLARE
    queued_count BIGINT := 0;
BEGIN
    SELECT COALESCE(SUM(public.enqueue_species_enrichment_jobs(
        species.id,
        'species_country_occurrence_backfill',
        85,
        ARRAY['gbif_wikipedia_reference']::TEXT[]
    )), 0)
    INTO queued_count
    FROM public.species_dictionary AS species
    WHERE NULLIF(BTRIM(COALESCE(species.scientific_name, '')), '') IS NOT NULL
      AND (
            COALESCE(species.gbif_taxon_key, 0) > 0
            OR public.species_dictionary_taxonomy_value_is_usable(species.kingdom)
      )
      AND NOT EXISTS (
            SELECT 1
            FROM public.species_country_occurrences AS occurrence
            WHERE occurrence.species_id = species.id
              AND occurrence.occurrence_count > 0
              AND occurrence.gbif_taxon_key = species.gbif_taxon_key::BIGINT
      );

    RAISE NOTICE
        'Queued % GBIF species country-occurrence refresh jobs.',
        queued_count;
END;
$backfill$;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;

-- Make the public biological-species boundary a database-owned invariant so
-- catalog pagination and overview counts operate on the same eligible set.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

ALTER TABLE public.species_dictionary
    ADD COLUMN is_public_biological BOOLEAN GENERATED ALWAYS AS (
        NULLIF(pg_catalog.BTRIM(scientific_name), '') IS NOT NULL
        AND (
            COALESCE(gbif_taxon_key, 0) > 0
            OR (
                NULLIF(pg_catalog.BTRIM(kingdom), '') IS NOT NULL
                AND pg_catalog.LOWER(pg_catalog.BTRIM(kingdom)) NOT IN (
                    'unknown',
                    'unavailable',
                    'not available',
                    'n/a',
                    'none',
                    'null',
                    'undefined'
                )
                AND (
                    (
                        NULLIF(pg_catalog.BTRIM(phylum), '') IS NOT NULL
                        AND pg_catalog.LOWER(pg_catalog.BTRIM(phylum)) NOT IN (
                            'unknown',
                            'unavailable',
                            'not available',
                            'n/a',
                            'none',
                            'null',
                            'undefined'
                        )
                    )
                    OR (
                        NULLIF(pg_catalog.BTRIM(class), '') IS NOT NULL
                        AND pg_catalog.LOWER(pg_catalog.BTRIM(class)) NOT IN (
                            'unknown',
                            'unavailable',
                            'not available',
                            'n/a',
                            'none',
                            'null',
                            'undefined'
                        )
                    )
                    OR (
                        NULLIF(pg_catalog.BTRIM("order"), '') IS NOT NULL
                        AND pg_catalog.LOWER(pg_catalog.BTRIM("order")) NOT IN (
                            'unknown',
                            'unavailable',
                            'not available',
                            'n/a',
                            'none',
                            'null',
                            'undefined'
                        )
                    )
                    OR (
                        NULLIF(pg_catalog.BTRIM(family), '') IS NOT NULL
                        AND pg_catalog.LOWER(pg_catalog.BTRIM(family)) NOT IN (
                            'unknown',
                            'unavailable',
                            'not available',
                            'n/a',
                            'none',
                            'null',
                            'undefined'
                        )
                    )
                    OR (
                        NULLIF(pg_catalog.BTRIM(genus), '') IS NOT NULL
                        AND pg_catalog.LOWER(pg_catalog.BTRIM(genus)) NOT IN (
                            'unknown',
                            'unavailable',
                            'not available',
                            'n/a',
                            'none',
                            'null',
                            'undefined'
                        )
                    )
                )
            )
        )
    ) STORED;

COMMENT ON COLUMN public.species_dictionary.is_public_biological IS
    'Canonical database-owned eligibility used by public Species Dictionary catalogs and overview counts.';

CREATE INDEX idx_species_dictionary_public_biological_name
    ON public.species_dictionary (scientific_name, id)
    WHERE is_public_biological;

CREATE INDEX idx_species_dictionary_public_biological_created_at
    ON public.species_dictionary (created_at DESC, id DESC)
    WHERE is_public_biological;

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
       AND species.is_public_biological
    WHERE occurrence.occurrence_count >= GREATEST(
            COALESCE(p_min_occurrence_count, 1),
            1
        )
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

REVOKE ALL
    ON FUNCTION public.get_species_dictionary_country_summaries(
        TEXT,
        BIGINT,
        INTEGER
    )
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
    ON FUNCTION public.get_species_dictionary_country_summaries(
        TEXT,
        BIGINT,
        INTEGER
    )
    TO service_role;

RESET statement_timeout;
RESET lock_timeout;

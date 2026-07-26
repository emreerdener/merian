BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- PostgreSQL cannot use a subquery directly in a CHECK expression. Keep the
-- array walk in one immutable, side-effect-free internal predicate so both
-- cardinality and every element's encoded length are enforced at write time.
CREATE OR REPLACE FUNCTION internal.text_array_elements_are_bounded(
    p_values TEXT[],
    p_max_cardinality INTEGER,
    p_max_element_octets INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
RETURNS NULL ON NULL INPUT
SET search_path = ''
AS $$
    SELECT
        p_max_cardinality >= 0
        AND p_max_element_octets >= 0
        AND pg_catalog.CARDINALITY(p_values) <= p_max_cardinality
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(p_values) AS elements(element_value)
            WHERE elements.element_value IS NULL
               OR pg_catalog.OCTET_LENGTH(elements.element_value)
                    > p_max_element_octets
               OR elements.element_value ~ '[[:cntrl:]]'
        );
$$;

REVOKE ALL ON FUNCTION internal.text_array_elements_are_bounded(
    TEXT[], INTEGER, INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.text_array_elements_are_bounded(
    TEXT[], INTEGER, INTEGER
) TO anon, authenticated, service_role;

-- Install new-row enforcement without scanning either existing table while
-- this migration holds the stronger ALTER TABLE lock. The following ordered
-- migration validates legacy rows before it activates the export source RPC.
ALTER TABLE public.scans
    ADD CONSTRAINT scans_dwca_image_urls_bounded_check
        CHECK (
            internal.text_array_elements_are_bounded(
                image_storage_urls,
                24,
                4096
            )
        ) NOT VALID,
    ADD CONSTRAINT scans_dwca_interactions_bounded_check
        CHECK (
            ecological_interactions IS NULL
            OR internal.text_array_elements_are_bounded(
                ecological_interactions,
                10,
                2048
            )
        ) NOT VALID;

ALTER TABLE public.species_dictionary
    ADD CONSTRAINT species_dictionary_dwca_taxonomy_bounded_check
        CHECK (
            pg_catalog.OCTET_LENGTH(scientific_name) <= 1024
            AND pg_catalog.OCTET_LENGTH(kingdom) <= 512
            AND pg_catalog.OCTET_LENGTH(phylum) <= 512
            AND pg_catalog.OCTET_LENGTH(class) <= 512
            AND pg_catalog.OCTET_LENGTH("order") <= 512
            AND pg_catalog.OCTET_LENGTH(family) <= 512
            AND pg_catalog.OCTET_LENGTH(genus) <= 512
            AND (
                iucn_red_list_status IS NULL
                OR pg_catalog.OCTET_LENGTH(iucn_red_list_status) <= 128
            )
        ) NOT VALID;

COMMENT ON CONSTRAINT scans_dwca_image_urls_bounded_check
    ON public.scans IS
    'Bounds every DwC-A multimedia source array before an Edge worker reads it.';
COMMENT ON CONSTRAINT scans_dwca_interactions_bounded_check
    ON public.scans IS
    'Bounds every DwC-A associatedTaxa source array before CSV encoding.';
COMMENT ON CONSTRAINT species_dictionary_dwca_taxonomy_bounded_check
    ON public.species_dictionary IS
    'Bounds taxonomy text selected into a DwC-A occurrence source row.';

COMMIT;

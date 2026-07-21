-- Keep an Explore post's own scan media in the primary gallery only. Reference
-- imagery from other Naturebook scans and external providers remains visible.

CREATE OR REPLACE FUNCTION public.public_species_reference_image_urls_excluding_media(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL,
    excluded_image_urls TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    WITH projected AS (
        SELECT
            NULLIF(BTRIM(split.raw_url), '') AS url,
            split.ordinality
        FROM regexp_split_to_table(
            COALESCE(
                public.public_species_reference_image_urls(
                    target_species_id,
                    legacy_reference_image_url
                ),
                ''
            ),
            '\s*,\s*'
        ) WITH ORDINALITY AS split(raw_url, ordinality)
    ),
    excluded AS (
        SELECT NULLIF(BTRIM(media.raw_url), '') AS url
        FROM UNNEST(COALESCE(excluded_image_urls, ARRAY[]::TEXT[])) AS media(raw_url)
    )
    SELECT STRING_AGG(projected.url, ',' ORDER BY projected.ordinality)
    FROM projected
    WHERE projected.url IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM excluded
          WHERE excluded.url = projected.url
      );
$$;

COMMENT ON FUNCTION public.public_species_reference_image_urls_excluding_media(UUID, TEXT, TEXT[]) IS
  'Returns ordered public species reference image URLs after excluding the current scan media URLs.';

CREATE OR REPLACE FUNCTION public.get_explore_post_detail(
    self_id UUID,
    target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    location_sharing TEXT,
    hashtags TEXT[],
    species_dictionary_id UUID,
    alternative_common_names TEXT[],
    pet_identification JSONB,
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT,
    ai_reasoning TEXT,
    habitat_description TEXT,
    gbif_taxon_key INTEGER,
    iucn_red_list_status TEXT,
    hazard_type TEXT,
    wikipedia_url TEXT,
    reference_image_url TEXT,
    wikipedia_overview TEXT,
    similar_species JSONB
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        NULLIF(BTRIM(COALESCE(ep.field_notes, '')), '') AS field_notes,
        ep.location_sharing,
        ARRAY(
            SELECT eph.tag
            FROM public.explore_post_hashtags eph
            WHERE eph.post_id = ep.id
            ORDER BY eph.tag
        ) AS hashtags,
        sd.id AS species_dictionary_id,
        ARRAY(
            SELECT NULLIF(BTRIM(names.raw_name), '')
            FROM UNNEST(COALESCE(sd.alternative_common_names, ARRAY[]::TEXT[]))
                WITH ORDINALITY AS names(raw_name, ordinality)
            WHERE NULLIF(BTRIM(names.raw_name), '') IS NOT NULL
            ORDER BY names.ordinality
        ) AS alternative_common_names,
        s.pet_identification,
        sd.kingdom AS taxonomy_kingdom,
        sd.phylum AS taxonomy_phylum,
        sd."class" AS taxonomy_class,
        sd."order" AS taxonomy_order,
        sd.family AS taxonomy_family,
        sd.genus AS taxonomy_genus,
        CASE
            WHEN COALESCE(s.user_review_state, 'unreviewed'::public.user_review_state) <> 'user_overridden'::public.user_review_state
             AND s.user_identification_override IS NULL
             AND NULLIF(BTRIM(COALESCE(s.ai_reasoning, '')), '') IS NOT NULL
                THEN s.ai_reasoning
            ELSE NULL
        END AS ai_reasoning,
        sd.habitat_description,
        sd.gbif_taxon_key,
        sd.iucn_red_list_status,
        COALESCE(NULLIF(BTRIM(sd.hazard_type), ''), 'none') AS hazard_type,
        sd.wikipedia_url,
        public.public_species_reference_image_urls_excluding_media(
            sd.id,
            sd.reference_image_url,
            s.image_storage_urls
        ) AS reference_image_url,
        sd.wikipedia_overview,
        public.public_species_similar_species(sd.id) AS similar_species
    FROM public.explore_posts ep
    JOIN public.scans s ON s.id = ep.scan_id
    JOIN public.users u ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE ep.id = target_post_id
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_explore_post_detail(UUID, UUID) IS
  'Returns privacy-safe public Explore detail without repeating the current scan media as reference imagery.';

NOTIFY pgrst, 'reload schema';

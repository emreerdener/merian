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
            WHEN s.is_flagged = FALSE
             AND COALESCE(s.user_review_state, 'unreviewed'::public.user_review_state) <> 'user_overridden'::public.user_review_state
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
        public.public_species_reference_image_urls(sd.id, sd.reference_image_url) AS reference_image_url,
        sd.wikipedia_overview,
        public.public_species_similar_species(sd.id) AS similar_species
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE ep.id = target_post_id
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
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

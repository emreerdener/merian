-- Shared SQL helpers for public species projections.
--
-- Keep Explore detail similar-species hydration aligned with the Deno public
-- species projection used by /species-dictionary.

CREATE OR REPLACE FUNCTION public.public_species_common_name(
    common_names JSONB,
    fallback_name TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(common_names ->> 'en'), ''),
        (
            SELECT NULLIF(BTRIM(common_name_value), '')
            FROM jsonb_each_text(COALESCE(common_names, '{}'::jsonb)) AS names(common_name_key, common_name_value)
            WHERE NULLIF(BTRIM(common_name_value), '') IS NOT NULL
            LIMIT 1
        ),
        NULLIF(BTRIM(COALESCE(fallback_name, '')), '')
    );
$$;

CREATE OR REPLACE FUNCTION public.public_species_reference_image_urls(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT STRING_AGG(ref.url, ',' ORDER BY ref.sort_order, ref.created_at, ref.id)
            FROM public.species_reference_images ref
            WHERE ref.species_id = target_species_id
        ),
        NULLIF(BTRIM(COALESCE(legacy_reference_image_url, '')), '')
    );
$$;

CREATE OR REPLACE FUNCTION public.public_species_first_reference_image_url(
    target_species_id UUID,
    legacy_reference_image_url TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT ref.url
            FROM public.species_reference_images ref
            WHERE ref.species_id = target_species_id
            ORDER BY ref.sort_order, ref.created_at, ref.id
            LIMIT 1
        ),
        (
            SELECT NULLIF(BTRIM(split.raw_url), '')
            FROM regexp_split_to_table(COALESCE(legacy_reference_image_url, ''), '\s*,\s*')
                WITH ORDINALITY AS split(raw_url, ordinality)
            WHERE NULLIF(BTRIM(split.raw_url), '') IS NOT NULL
            ORDER BY split.ordinality
            LIMIT 1
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.public_species_similar_species(
    target_species_id UUID
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'species_id', lookalike.id,
                'scientific_name', lookalike.scientific_name,
                'common_name', public.public_species_common_name(lookalike.common_names),
                'reference_image_url', public.public_species_first_reference_image_url(
                    lookalike.id,
                    lookalike.reference_image_url
                ),
                'iucn_red_list_status', NULLIF(BTRIM(COALESCE(lookalike.iucn_red_list_status, '')), '')
            )
            ORDER BY lookalike.scientific_name
        )
        FROM public.species_lookalikes sl
        JOIN public.species_dictionary lookalike
            ON lookalike.id = sl.lookalike_id
        WHERE sl.species_id = target_species_id
    ), '[]'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_post_detail(
    self_id UUID,
    target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    species_dictionary_id UUID,
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
        sd.id AS species_dictionary_id,
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
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    LIMIT 1;
$$;

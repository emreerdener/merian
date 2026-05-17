-- Normalized public reference imagery for species dictionary rows.
--
-- species_dictionary.reference_image_url remains as a comma-separated compatibility
-- cache while clients migrate to this table-backed projection.

CREATE TABLE IF NOT EXISTS public.species_reference_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    species_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'gbif',
    license TEXT,
    attribution TEXT,
    width INTEGER,
    height INTEGER,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_verified_at TIMESTAMPTZ,
    CONSTRAINT species_reference_images_source_check
        CHECK (source IN ('wikipedia', 'gbif')),
    CONSTRAINT species_reference_images_url_nonempty_check
        CHECK (BTRIM(url) <> ''),
    CONSTRAINT species_reference_images_width_positive_check
        CHECK (width IS NULL OR width > 0),
    CONSTRAINT species_reference_images_height_positive_check
        CHECK (height IS NULL OR height > 0),
    CONSTRAINT species_reference_images_species_url_key
        UNIQUE (species_id, url)
);

CREATE INDEX IF NOT EXISTS idx_species_reference_images_species_order
    ON public.species_reference_images(species_id, sort_order, id);

ALTER TABLE public.species_reference_images ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'species_reference_images'
          AND policyname = 'Anyone can read species reference images'
    ) THEN
        CREATE POLICY "Anyone can read species reference images"
            ON public.species_reference_images
            FOR SELECT
            USING (true);
    END IF;
END $$;

WITH split_images AS (
    SELECT
        sd.id AS species_id,
        NULLIF(BTRIM(split.raw_url), '') AS url,
        sd.wikipedia_url,
        split.ordinality
    FROM public.species_dictionary sd
    CROSS JOIN LATERAL regexp_split_to_table(COALESCE(sd.reference_image_url, ''), '\s*,\s*')
        WITH ORDINALITY AS split(raw_url, ordinality)
),
deduped_images AS (
    SELECT DISTINCT ON (species_id, url)
        species_id,
        url,
        wikipedia_url,
        ordinality
    FROM split_images
    WHERE url IS NOT NULL
    ORDER BY species_id, url, ordinality
)
INSERT INTO public.species_reference_images (
    species_id,
    url,
    source,
    sort_order,
    created_at,
    last_verified_at
)
SELECT
    species_id,
    url,
    CASE
        WHEN LOWER(url) LIKE '%wikipedia%' OR LOWER(url) LIKE '%wikimedia%' THEN 'wikipedia'
        WHEN ordinality = 1 AND NULLIF(BTRIM(COALESCE(wikipedia_url, '')), '') IS NOT NULL THEN 'wikipedia'
        ELSE 'gbif'
    END AS source,
    GREATEST(ordinality::INTEGER - 1, 0) AS sort_order,
    NOW(),
    NOW()
FROM deduped_images
ON CONFLICT (species_id, url) DO NOTHING;

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
        COALESCE(
            (
                SELECT STRING_AGG(ref.url, ',' ORDER BY ref.sort_order, ref.created_at, ref.id)
                FROM public.species_reference_images ref
                WHERE ref.species_id = sd.id
            ),
            sd.reference_image_url
        ) AS reference_image_url,
        sd.wikipedia_overview,
        COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'species_id', lookalike.id,
                    'scientific_name', lookalike.scientific_name,
                    'common_name', COALESCE(
                        NULLIF(BTRIM(lookalike.common_names ->> 'en'), ''),
                        (
                            SELECT NULLIF(BTRIM(common_name_value), '')
                            FROM jsonb_each_text(COALESCE(lookalike.common_names, '{}'::jsonb)) AS names(common_name_key, common_name_value)
                            WHERE NULLIF(BTRIM(common_name_value), '') IS NOT NULL
                            LIMIT 1
                        )
                    ),
                    'reference_image_url', COALESCE(
                        (
                            SELECT ref.url
                            FROM public.species_reference_images ref
                            WHERE ref.species_id = lookalike.id
                            ORDER BY ref.sort_order, ref.created_at, ref.id
                            LIMIT 1
                        ),
                        NULLIF(BTRIM(SPLIT_PART(COALESCE(lookalike.reference_image_url, ''), ',', 1)), '')
                    ),
                    'iucn_red_list_status', NULLIF(BTRIM(COALESCE(lookalike.iucn_red_list_status, '')), '')
                )
                ORDER BY lookalike.scientific_name
            )
            FROM public.species_lookalikes sl
            JOIN public.species_dictionary lookalike
                ON lookalike.id = sl.lookalike_id
            WHERE sl.species_id = sd.id
        ), '[]'::jsonb) AS similar_species
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

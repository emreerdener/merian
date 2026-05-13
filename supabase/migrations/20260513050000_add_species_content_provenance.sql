-- Species content provenance and refresh metadata.
--
-- Tracks where species-level dictionary fields came from and when they should be
-- revisited. This is intentionally species-level only; it must not reference scans,
-- users, locations, comments, or Explore posts.

CREATE TABLE IF NOT EXISTS public.species_content_provenance (
    species_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    content_key TEXT NOT NULL,
    source TEXT NOT NULL,
    source_detail TEXT,
    confidence NUMERIC(5,4),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    refresh_after TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (species_id, content_key),
    CONSTRAINT species_content_provenance_content_key_check
        CHECK (content_key IN (
            'common_names',
            'alternative_common_names',
            'taxonomy',
            'wikipedia_url',
            'wikipedia_overview',
            'habitat_description',
            'gbif_taxon_key',
            'reference_images',
            'lookalikes',
            'group_tags',
            'iucn_red_list_status',
            'hazard_type'
        )),
    CONSTRAINT species_content_provenance_source_check
        CHECK (source IN (
            'gbif',
            'wikipedia',
            'model_enrichment',
            'user_review',
            'manual_curation',
            'system_backfill',
            'taxonomy_trigger',
            'mixed',
            'unknown'
        )),
    CONSTRAINT species_content_provenance_confidence_check
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT species_content_provenance_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_species_content_provenance_refresh_after
    ON public.species_content_provenance(refresh_after)
    WHERE refresh_after IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_species_content_provenance_source_key
    ON public.species_content_provenance(source, content_key);

ALTER TABLE public.species_content_provenance ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'species_content_provenance'
          AND policyname = 'Anyone can read species content provenance'
    ) THEN
        CREATE POLICY "Anyone can read species content provenance"
            ON public.species_content_provenance
            FOR SELECT
            USING (true);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_species_content_provenance_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_species_content_provenance_set_updated_at
    ON public.species_content_provenance;

CREATE TRIGGER trg_species_content_provenance_set_updated_at
BEFORE UPDATE ON public.species_content_provenance
FOR EACH ROW
EXECUTE FUNCTION public.trg_species_content_provenance_set_updated_at();

WITH provenance_backfill AS (
    SELECT
        sd.id AS species_id,
        'common_names'::text AS content_key,
        'system_backfill'::text AS source,
        0.5000::numeric AS confidence,
        jsonb_build_object('backfilled_from', 'species_dictionary.common_names') AS metadata
    FROM public.species_dictionary sd
    WHERE COALESCE(sd.common_names, '{}'::jsonb) <> '{}'::jsonb

    UNION ALL
    SELECT
        sd.id,
        'alternative_common_names',
        'gbif',
        0.7000::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.alternative_common_names')
    FROM public.species_dictionary sd
    WHERE COALESCE(ARRAY_LENGTH(sd.alternative_common_names, 1), 0) > 0

    UNION ALL
    SELECT
        sd.id,
        'taxonomy',
        'model_enrichment',
        0.6500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary taxonomy columns')
    FROM public.species_dictionary sd
    WHERE NULLIF(BTRIM(COALESCE(sd.kingdom, '')), '') IS NOT NULL
       OR NULLIF(BTRIM(COALESCE(sd.phylum, '')), '') IS NOT NULL
       OR NULLIF(BTRIM(COALESCE(sd."class", '')), '') IS NOT NULL
       OR NULLIF(BTRIM(COALESCE(sd."order", '')), '') IS NOT NULL
       OR NULLIF(BTRIM(COALESCE(sd.family, '')), '') IS NOT NULL
       OR NULLIF(BTRIM(COALESCE(sd.genus, '')), '') IS NOT NULL

    UNION ALL
    SELECT
        sd.id,
        'wikipedia_url',
        'wikipedia',
        0.8500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.wikipedia_url')
    FROM public.species_dictionary sd
    WHERE NULLIF(BTRIM(COALESCE(sd.wikipedia_url, '')), '') IS NOT NULL

    UNION ALL
    SELECT
        sd.id,
        'wikipedia_overview',
        'wikipedia',
        0.8500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.wikipedia_overview')
    FROM public.species_dictionary sd
    WHERE NULLIF(BTRIM(COALESCE(sd.wikipedia_overview, '')), '') IS NOT NULL

    UNION ALL
    SELECT
        sd.id,
        'habitat_description',
        'model_enrichment',
        0.6500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.habitat_description')
    FROM public.species_dictionary sd
    WHERE NULLIF(BTRIM(COALESCE(sd.habitat_description, '')), '') IS NOT NULL

    UNION ALL
    SELECT
        sd.id,
        'gbif_taxon_key',
        'gbif',
        0.8500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.gbif_taxon_key')
    FROM public.species_dictionary sd
    WHERE sd.gbif_taxon_key IS NOT NULL

    UNION ALL
    SELECT
        sd.id,
        'reference_images',
        'mixed',
        0.8000::numeric,
        jsonb_build_object('backfilled_from', 'species_reference_images or species_dictionary.reference_image_url')
    FROM public.species_dictionary sd
    WHERE NULLIF(BTRIM(COALESCE(sd.reference_image_url, '')), '') IS NOT NULL
       OR EXISTS (
            SELECT 1
            FROM public.species_reference_images ref
            WHERE ref.species_id = sd.id
       )

    UNION ALL
    SELECT
        sd.id,
        'lookalikes',
        'system_backfill',
        0.5000::numeric,
        jsonb_build_object('backfilled_from', 'species_lookalikes')
    FROM public.species_dictionary sd
    WHERE EXISTS (
        SELECT 1
        FROM public.species_lookalikes sl
        WHERE sl.species_id = sd.id
    )

    UNION ALL
    SELECT
        sd.id,
        'group_tags',
        'model_enrichment',
        0.6500::numeric,
        jsonb_build_object('backfilled_from', 'species_dictionary.group_tags')
    FROM public.species_dictionary sd
    WHERE COALESCE(ARRAY_LENGTH(sd.group_tags, 1), 0) > 0
)
INSERT INTO public.species_content_provenance (
    species_id,
    content_key,
    source,
    source_detail,
    confidence,
    metadata,
    last_refreshed_at,
    refresh_after
)
SELECT
    species_id,
    content_key,
    source,
    'legacy backfill; original freshness unknown',
    confidence,
    metadata,
    NOW(),
    NOW() + INTERVAL '30 days'
FROM provenance_backfill
ON CONFLICT (species_id, content_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_species_content_refresh_queue(
    max_rows INTEGER DEFAULT 100,
    as_of TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE(
    species_id UUID,
    scientific_name TEXT,
    content_key TEXT,
    source TEXT,
    source_detail TEXT,
    confidence NUMERIC,
    last_refreshed_at TIMESTAMPTZ,
    refresh_after TIMESTAMPTZ,
    reason TEXT
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        p.species_id,
        sd.scientific_name,
        p.content_key,
        p.source,
        p.source_detail,
        p.confidence,
        p.last_refreshed_at,
        p.refresh_after,
        CASE
            WHEN p.confidence IS NOT NULL AND p.confidence < 0.6000 THEN 'low_confidence'
            WHEN p.refresh_after IS NOT NULL AND p.refresh_after <= as_of THEN 'stale'
            ELSE 'unknown'
        END AS reason
    FROM public.species_content_provenance p
    JOIN public.species_dictionary sd
        ON sd.id = p.species_id
    WHERE (p.refresh_after IS NOT NULL AND p.refresh_after <= as_of)
       OR (p.confidence IS NOT NULL AND p.confidence < 0.6000)
    ORDER BY
        CASE
            WHEN p.confidence IS NOT NULL AND p.confidence < 0.6000 THEN 0
            ELSE 1
        END,
        p.refresh_after ASC NULLS LAST,
        p.updated_at ASC
    LIMIT GREATEST(LEAST(max_rows, 500), 1);
$$;

REVOKE ALL ON FUNCTION public.get_species_content_refresh_queue(INTEGER, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_species_content_refresh_queue(INTEGER, TIMESTAMPTZ) TO service_role;

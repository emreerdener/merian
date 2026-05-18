-- Public species observation stats cache.
--
-- Stores global public-provider aggregates only. User-local Merian logs stay
-- on device and are never written to this cache.

ALTER TABLE public.species_dictionary
    ADD COLUMN IF NOT EXISTS inaturalist_taxon_id INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'species_dictionary_inaturalist_taxon_id_positive_check'
    ) THEN
        ALTER TABLE public.species_dictionary
            ADD CONSTRAINT species_dictionary_inaturalist_taxon_id_positive_check
            CHECK (inaturalist_taxon_id IS NULL OR inaturalist_taxon_id > 0);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.species_observation_stats_cache (
    species_id UUID NOT NULL REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    source TEXT NOT NULL DEFAULT 'inaturalist',
    scope TEXT NOT NULL DEFAULT 'global',
    scientific_name TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'fresh',
    provider_error TEXT,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (species_id, source, scope),
    CONSTRAINT species_observation_stats_cache_source_check
        CHECK (source IN ('inaturalist')),
    CONSTRAINT species_observation_stats_cache_scope_check
        CHECK (scope IN ('global')),
    CONSTRAINT species_observation_stats_cache_status_check
        CHECK (status IN ('fresh', 'stale', 'no_data', 'unavailable', 'partial')),
    CONSTRAINT species_observation_stats_cache_payload_object_check
        CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT species_observation_stats_cache_name_nonempty_check
        CHECK (BTRIM(scientific_name) <> '')
);

CREATE INDEX IF NOT EXISTS idx_species_observation_stats_cache_expires_at
    ON public.species_observation_stats_cache(expires_at);

ALTER TABLE public.species_observation_stats_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'species_observation_stats_cache'
          AND policyname = 'Anyone can read species observation stats cache'
    ) THEN
        CREATE POLICY "Anyone can read species observation stats cache"
            ON public.species_observation_stats_cache
            FOR SELECT
            USING (true);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.trg_species_observation_stats_cache_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_species_observation_stats_cache_set_updated_at
    ON public.species_observation_stats_cache;

CREATE TRIGGER trg_species_observation_stats_cache_set_updated_at
BEFORE UPDATE ON public.species_observation_stats_cache
FOR EACH ROW
EXECUTE FUNCTION public.trg_species_observation_stats_cache_set_updated_at();

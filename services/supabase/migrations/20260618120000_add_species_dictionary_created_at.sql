ALTER TABLE public.species_dictionary
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;

WITH earliest_provenance AS (
    SELECT
        species_id,
        MIN(created_at) AS created_at
    FROM public.species_content_provenance
    GROUP BY species_id
)
UPDATE public.species_dictionary sd
SET created_at = COALESCE(ep.created_at, NOW())
FROM earliest_provenance ep
WHERE sd.id = ep.species_id
  AND sd.created_at IS NULL;

UPDATE public.species_dictionary
SET created_at = NOW()
WHERE created_at IS NULL;

ALTER TABLE public.species_dictionary
    ALTER COLUMN created_at SET DEFAULT NOW(),
    ALTER COLUMN created_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_species_dictionary_created_at_id
    ON public.species_dictionary (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_species_dictionary_native_region
    ON public.species_dictionary (native_region);

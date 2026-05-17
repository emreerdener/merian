-- Drop global_distribution_regions from species_dictionary.
-- This column was populated by Gemini Flash estimates that proved inaccurate —
-- species range is now communicated exclusively through the GBIF occurrence
-- density tile overlay (driven by gbif_taxon_key).
ALTER TABLE public.species_dictionary DROP COLUMN IF EXISTS global_distribution_regions;

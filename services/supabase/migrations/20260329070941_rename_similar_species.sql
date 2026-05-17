-- Rename the array column to fit the new Similar Species Gallery nomenclature
ALTER TABLE public.species_dictionary
    RENAME COLUMN diagnostic_lookalikes TO similar_species;

-- Drop obsolete ML rationale properties since `ai_reasoning` on the primary scan supersedes it
ALTER TABLE public.species_dictionary
    DROP COLUMN IF EXISTS diagnostic_primary_rationale,
    DROP COLUMN IF EXISTS diagnostic_differentiators_json;

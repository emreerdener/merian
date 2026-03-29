-- Drop the old comma-separated text column
ALTER TABLE public.species_dictionary DROP COLUMN IF EXISTS diagnostic_lookalike_name;

-- Add the new native Postgres text array column
ALTER TABLE public.species_dictionary ADD COLUMN diagnostic_lookalikes text[];

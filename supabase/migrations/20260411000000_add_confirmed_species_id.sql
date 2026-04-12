-- 20260411000000_add_confirmed_species_id.sql
-- Add confirmed_species_id to scans table for efficient querying of reference imagery

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS confirmed_species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_scans_confirmed_species_id ON public.scans(confirmed_species_id);

-- Add AI reasoning to the scans table for specific scan logic
ALTER TABLE public.scans ADD COLUMN ai_reasoning TEXT;

-- Add general habitat and distribution data to the species dictionary
ALTER TABLE public.species_dictionary ADD COLUMN habitat_description TEXT;
ALTER TABLE public.species_dictionary ADD COLUMN global_distribution_regions JSONB DEFAULT '[]'::jsonb;

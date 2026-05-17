-- Add group_tags array to species_dictionary for categorical search (e.g. "bird", "songbird").
-- Populated once per species by a follow-up Gemini Flash call in the identify Edge Function.
ALTER TABLE public.species_dictionary ADD COLUMN IF NOT EXISTS group_tags TEXT[] NOT NULL DEFAULT '{}';

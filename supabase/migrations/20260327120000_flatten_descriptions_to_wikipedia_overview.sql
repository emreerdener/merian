-- The descriptions JSONB column was used solely to store Wikipedia text at
-- descriptions["en"]["wikipedia"]. Flatten it into a dedicated wikipedia_overview TEXT
-- column for consistency with the API response and Swift model naming.

ALTER TABLE public.species_dictionary ADD COLUMN IF NOT EXISTS wikipedia_overview TEXT;

UPDATE public.species_dictionary
SET wikipedia_overview = descriptions -> 'en' ->> 'wikipedia'
WHERE descriptions -> 'en' ->> 'wikipedia' IS NOT NULL;

ALTER TABLE public.species_dictionary DROP COLUMN IF EXISTS descriptions;

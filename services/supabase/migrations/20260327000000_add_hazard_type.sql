-- Replace is_poisonous (Bool) with hazard_type (TEXT) on species_dictionary.
-- Migrates existing poisonous data: is_poisonous = true → hazard_type = 'poisonous'.
-- Valid values: none | poisonous | venomous | allergenic | irritant
-- Note: scans never had is_poisonous. hazard_type is a species-level property
-- owned by species_dictionary and read via join — no column needed on scans.

ALTER TABLE public.species_dictionary
    ADD COLUMN hazard_type TEXT NOT NULL DEFAULT 'none'
        CHECK (hazard_type IN ('none', 'poisonous', 'venomous', 'allergenic', 'irritant'));

UPDATE public.species_dictionary
    SET hazard_type = 'poisonous'
    WHERE is_poisonous = true;

ALTER TABLE public.species_dictionary
    DROP COLUMN is_poisonous;

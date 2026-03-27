-- Replace is_poisonous (Bool) with hazard_type (TEXT) on both species_dictionary and scans.
-- Migrates existing poisonous data: is_poisonous = true → hazard_type = 'poisonous'.
-- Valid values: none | poisonous | venomous | allergenic | irritant

-- species_dictionary
ALTER TABLE public.species_dictionary
    ADD COLUMN hazard_type TEXT NOT NULL DEFAULT 'none'
        CHECK (hazard_type IN ('none', 'poisonous', 'venomous', 'allergenic', 'irritant'));

UPDATE public.species_dictionary
    SET hazard_type = 'poisonous'
    WHERE is_poisonous = true;

ALTER TABLE public.species_dictionary
    DROP COLUMN is_poisonous;

-- scans
ALTER TABLE public.scans
    ADD COLUMN hazard_type TEXT NOT NULL DEFAULT 'none'
        CHECK (hazard_type IN ('none', 'poisonous', 'venomous', 'allergenic', 'irritant'));

UPDATE public.scans
    SET hazard_type = 'poisonous'
    WHERE is_poisonous = true;

ALTER TABLE public.scans
    DROP COLUMN is_poisonous;

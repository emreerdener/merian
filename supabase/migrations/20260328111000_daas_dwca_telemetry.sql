CREATE TYPE life_stage_enum AS ENUM ('egg', 'larva', 'juvenile', 'adult', 'unknown');
CREATE TYPE reproductive_condition_enum AS ENUM ('flowering', 'fruiting', 'sporing', 'dormant', 'not_applicable');

ALTER TABLE public.scans 
    ADD COLUMN life_stage life_stage_enum DEFAULT 'unknown',
    ADD COLUMN reproductive_condition reproductive_condition_enum DEFAULT 'not_applicable',
    ADD COLUMN individual_count INTEGER,
    ADD COLUMN ecological_interactions TEXT[],
    ADD COLUMN estimated_size_cm DOUBLE PRECISION;

-- Expands life_stage_enum and reproductive_condition_enum to match the full
-- value sets defined in identify/schema.ts (the Gemini response schema).
--
-- The Postgres enums were created in 20260328111000_daas_dwca_telemetry.sql
-- with a minimal set of values. The Gemini schema was subsequently expanded
-- to cover the full biological range, but the DB enums were never updated.
-- This mismatch caused every plant scan (vegetative/budding) and many animal
-- scans (subadult, sapling) to fail with 22P02 invalid_text_representation,
-- silently dropping the scan row from the DB.

ALTER TYPE life_stage_enum ADD VALUE IF NOT EXISTS 'pupa';
ALTER TYPE life_stage_enum ADD VALUE IF NOT EXISTS 'nymph';
ALTER TYPE life_stage_enum ADD VALUE IF NOT EXISTS 'subadult';
ALTER TYPE life_stage_enum ADD VALUE IF NOT EXISTS 'seedling';
ALTER TYPE life_stage_enum ADD VALUE IF NOT EXISTS 'sapling';

ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'budding';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'vegetative';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'pregnant';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'gravid';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'mating';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'spawning';
ALTER TYPE reproductive_condition_enum ADD VALUE IF NOT EXISTS 'nesting';

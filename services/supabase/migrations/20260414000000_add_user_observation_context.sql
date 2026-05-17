-- Add user_observation_context JSONB column to scans.
--
-- Stores the structured ObservationContext staged by the user before submission.
-- NULL for image-only scans. Present for combined image+description scans and
-- description-only describe scans.
--
-- JSONB is chosen over separate columns because ObservationContext has 7 array/enum
-- fields. A single nullable JSONB column is the simplest schema that keeps the
-- structure queryable (via jsonb operators) without requiring a 1:1 child table.

ALTER TABLE public.scans
  ADD COLUMN user_observation_context JSONB NULL;

COMMENT ON COLUMN public.scans.user_observation_context IS
  'Structured observation context staged by the user before submission. '
  'JSON object matching the iOS ObservationContext model fields: '
  'organism_class, colors, size, habitats, behaviors, markings, textures, free_text. '
  'NULL for image-only scans.';

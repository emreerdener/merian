-- Allow user_species_preferences to carry soft-delete tombstones so preference
-- clears propagate across devices. A hard delete cannot distinguish "never set"
-- from "cleared on another device" during client reconciliation.

ALTER TABLE public.user_species_preferences
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE public.user_species_preferences
ALTER COLUMN preferred_common_name DROP NOT NULL;

ALTER TABLE public.user_species_preferences
DROP CONSTRAINT IF EXISTS user_species_preferences_preferred_common_name_check;

ALTER TABLE public.user_species_preferences
ADD CONSTRAINT user_species_preferences_preferred_common_name_check
CHECK (
  (
    deleted_at IS NULL
    AND preferred_common_name IS NOT NULL
    AND char_length(preferred_common_name) BETWEEN 1 AND 200
  )
  OR
  (
    deleted_at IS NOT NULL
    AND preferred_common_name IS NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_user_species_preferences_user_updated_at
ON public.user_species_preferences (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_species_preferences_user_deleted_at
ON public.user_species_preferences (user_id, deleted_at)
WHERE deleted_at IS NOT NULL;

NOTIFY pgrst, 'reload schema';

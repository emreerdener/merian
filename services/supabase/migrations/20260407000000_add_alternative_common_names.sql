-- Adds alternative_common_names (TEXT[]) to species_dictionary.
--
-- Stores all known English vernacular synonyms for a species beyond the primary
-- canonical name stored in common_names->>'en'. Sourced from the GBIF vernacular
-- names endpoint (/v1/species/{key}/vernacularNames?language=eng) during background
-- enrichment. The primary name is never duplicated in this array — it is deduplicated
-- at write time in the edge function.
--
-- Array is intentionally NULL for species not yet enriched rather than defaulting
-- to {} so the iOS client can distinguish "no synonyms exist" (empty array after
-- enrichment) from "enrichment hasn't run yet" (NULL).

ALTER TABLE species_dictionary
  ADD COLUMN IF NOT EXISTS alternative_common_names TEXT[];

-- Index allows fast lookups when searching across all synonyms (future feature).
CREATE INDEX IF NOT EXISTS idx_species_dict_alt_common_names
  ON species_dictionary USING GIN (alternative_common_names);

-- Stores a user's preferred common name choice for a species.
-- When populated, this overrides species_dictionary.common_names->>'en' in all
-- display contexts for that user. The iOS client writes this table when the user
-- selects an alternative name from the synonym list in the insight sheet.
--
-- preferred_common_name is constrained to 200 chars to prevent abuse while
-- comfortably fitting the longest real vernacular names (e.g. "Great Crested
-- Flycatcher" is 23 chars; the hard upper bound is a safety net, not a design limit).

CREATE TABLE IF NOT EXISTS user_species_preferences (
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scientific_name     TEXT        NOT NULL,
  preferred_common_name TEXT      NOT NULL CHECK (char_length(preferred_common_name) BETWEEN 1 AND 200),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, scientific_name)
);

-- RLS: users can only read and write their own preferences.
ALTER TABLE user_species_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own species preferences"
  ON user_species_preferences
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Keep updated_at current on upsert.
CREATE OR REPLACE FUNCTION touch_user_species_preference_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_user_species_preferences_updated_at
  BEFORE UPDATE ON user_species_preferences
  FOR EACH ROW EXECUTE FUNCTION touch_user_species_preference_updated_at();

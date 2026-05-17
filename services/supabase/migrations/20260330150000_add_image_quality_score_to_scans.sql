-- image_quality_score: Gemini's photographic quality score for the submitted image.
-- Emitted as image_quality.overall_score (0–100) from the identify Edge Function.
-- Stored here for future community reference-photo curation (e.g. per-species best-photo
-- selection ranked by score). NULL for all scans captured before this migration.
--
-- SMALLINT (2 bytes, range -32768–32767) is sufficient for a 0–100 integer and avoids
-- unnecessary INTEGER overhead on a high-write table.

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS image_quality_score SMALLINT DEFAULT NULL
    CONSTRAINT image_quality_score_range CHECK (image_quality_score BETWEEN 0 AND 100);

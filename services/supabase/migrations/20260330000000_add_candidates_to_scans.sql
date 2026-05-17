-- candidates: per-scan JSONB array of alternative species the model considered when confidence
-- fell below the tier-specific diagnosticTrigger threshold (0.99 for both Flash and Pro).
-- NULL for high-confidence scans (≥ 0.99) and all scans captured before this migration.
-- Shape: [{"scientific_name": "...", "confidence_score": 0.71, "distinguishing_feature": "..."}, ...]
-- distinguishing_feature added in identify schema update (2026-04-07); older rows have the two-field shape.

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS candidates JSONB DEFAULT NULL;

-- Partial index: only scans with candidates data will ever be queried by this column.
-- Keeps index size minimal since the majority of scans are high-confidence (NULL).
CREATE INDEX IF NOT EXISTS idx_scans_candidates_not_null
    ON public.scans (id)
    WHERE candidates IS NOT NULL;

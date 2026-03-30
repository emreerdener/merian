-- candidates: per-scan JSONB array of alternative species the model considered when confidence
-- fell below the tier-specific diagnosticTrigger threshold (0.88 Flash / 0.80 Pro).
-- NULL for high-confidence scans and all scans captured before this migration.
-- Shape: [{"scientific_name": "...", "confidence_score": 0.71}, ...]

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS candidates JSONB DEFAULT NULL;

-- Partial index: only scans with candidates data will ever be queried by this column.
-- Keeps index size minimal since the majority of scans are high-confidence (NULL).
CREATE INDEX IF NOT EXISTS idx_scans_candidates_not_null
    ON public.scans (id)
    WHERE candidates IS NOT NULL;

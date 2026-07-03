ALTER TABLE public.scans
ADD COLUMN IF NOT EXISTS invasive_status_region TEXT,
ADD COLUMN IF NOT EXISTS invasive_rationale TEXT,
ADD COLUMN IF NOT EXISTS invasive_confidence DOUBLE PRECISION;

ALTER TABLE public.scans
DROP CONSTRAINT IF EXISTS scans_invasive_confidence_range;

ALTER TABLE public.scans
ADD CONSTRAINT scans_invasive_confidence_range
CHECK (
    invasive_confidence IS NULL
    OR (invasive_confidence >= 0.0 AND invasive_confidence <= 1.0)
);

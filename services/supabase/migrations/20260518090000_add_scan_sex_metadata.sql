ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS sex TEXT,
  ADD COLUMN IF NOT EXISTS sex_confidence DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS sex_evidence TEXT;

DO $$
BEGIN
  ALTER TABLE public.scans
    ADD CONSTRAINT scans_sex_value_check
    CHECK (
      sex IS NULL OR sex IN (
        'female',
        'male',
        'hermaphrodite',
        'mixed',
        'cannot_determine',
        'not_applicable'
      )
    );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.scans
    ADD CONSTRAINT scans_sex_confidence_range_check
    CHECK (sex_confidence IS NULL OR (sex_confidence >= 0 AND sex_confidence <= 1));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.scans
    ADD CONSTRAINT scans_sex_evidence_length_check
    CHECK (sex_evidence IS NULL OR length(sex_evidence) <= 500);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

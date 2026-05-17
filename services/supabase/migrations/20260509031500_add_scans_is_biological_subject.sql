-- Persist the model's biological/non-biological classification so lifecycle
-- workers can purge non-biological scans without relying on response payloads.
ALTER TABLE public.scans
ADD COLUMN IF NOT EXISTS is_biological_subject BOOLEAN NOT NULL DEFAULT true;

-- Historical non-biological scans were intentionally inserted without a
-- species_dictionary row. New writes persist the explicit model boolean.
UPDATE public.scans
SET is_biological_subject = false
WHERE species_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_scans_nonbio_lifecycle
ON public.scans (timestamp)
WHERE is_biological_subject = false;

NOTIFY pgrst, 'reload schema';

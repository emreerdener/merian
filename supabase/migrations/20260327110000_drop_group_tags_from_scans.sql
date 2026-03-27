-- group_tags was mistakenly added to scans (20260324120000). It belongs on
-- species_dictionary (20260327100000) since these are species-level, not per-scan values.
ALTER TABLE public.scans DROP COLUMN IF EXISTS group_tags;

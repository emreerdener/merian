-- Narrow the domesticated media purge scan to rows the worker can actually
-- reclaim. The existing broad lifecycle index covers "has any media", but this
-- partial index matches the 90-day domesticated purge predicate directly.
--
-- CONCURRENTLY is intentionally omitted because fresh Supabase migration
-- replays execute through a statement pipeline.
CREATE INDEX IF NOT EXISTS idx_scans_domesticated_purge
ON public.scans (timestamp)
WHERE ecology_type = 'domesticated'
  AND image_storage_urls <> '{}';

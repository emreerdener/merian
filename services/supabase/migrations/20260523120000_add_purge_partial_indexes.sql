-- Narrow the domesticated media purge scan to rows the worker can actually
-- reclaim. The existing broad lifecycle index covers "has any media", but this
-- partial index matches the 90-day domesticated purge predicate directly.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scans_domesticated_purge
ON public.scans (timestamp)
WHERE ecology_type = 'domesticated'
  AND image_storage_urls <> '{}';

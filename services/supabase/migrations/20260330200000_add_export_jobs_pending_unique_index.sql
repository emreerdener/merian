-- Partial unique index on export_jobs to enforce at most one non-terminal job
-- per user at the database level. This hardens the TOCTOU race condition in
-- request-export-dwca: two concurrent requests can both pass the application-level
-- hasRecentExportJob SELECT before either INSERT commits. The unique constraint
-- makes the second INSERT fail with error code 23505, which queueExportJob
-- already catches and converts to a 429 Too Many Requests response.
--
-- Only rows with status 'pending' or 'processing' are included — completed and
-- failed jobs are excluded so historical records are preserved and the user can
-- request a new export after a prior one finishes.
--
-- CONCURRENTLY is intentionally omitted because fresh Supabase migration
-- replays execute through a statement pipeline.
CREATE UNIQUE INDEX IF NOT EXISTS idx_export_jobs_user_pending
  ON public.export_jobs (user_id)
  WHERE status NOT IN ('completed', 'failed');

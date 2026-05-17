-- Migration: 20260405000004_add_export_jobs_watchdog_cron.sql
-- Description: Watchdog cron job that expires export_jobs stuck in 'processing' state.
--
-- The export-dwca edge function updates job status to 'completed' or 'failed' when it
-- finishes. If the function is killed mid-run (edge timeout, OOM, cold-start restart),
-- the job remains 'processing' indefinitely — the iOS client shows an infinite loading
-- state and the user's only recovery is to manually retry. This cron tombstones any job
-- that has been processing for more than 30 minutes, which is well beyond the longest
-- realistic export run (10,000 rows × sub-second DwCA rows = a few minutes at most).

-- Tombstones stuck processing jobs with a human-readable error message.
CREATE OR REPLACE FUNCTION public.expire_stuck_export_jobs()
RETURNS void AS $$
BEGIN
    UPDATE public.export_jobs
    SET
        status       = 'failed',
        error_message = 'Export timed out — the processing function did not send a completion signal within 30 minutes. Please retry.',
        completed_at = NOW()
    WHERE
        status     = 'processing'
        AND created_at < NOW() - INTERVAL '30 minutes';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule the watchdog to run every 5 minutes.
-- pg_cron must be enabled on the project (Supabase enables it by default on Pro+).
SELECT cron.schedule(
    'expire-stuck-export-jobs',   -- job name (idempotent: re-running this migration updates the schedule)
    '*/5 * * * *',
    'SELECT public.expire_stuck_export_jobs()'
);

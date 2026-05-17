-- Enable pg_cron if not already explicitly available
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- 1. Create the Postgres function to scrub expired free-tier image URLs
CREATE OR REPLACE FUNCTION public.scrub_expired_free_tier_urls() 
RETURNS void 
LANGUAGE plpgsql
SECURITY DEFINER   -- Run with privileges of the creator (postgres) to bypass RLS locally on the server job
SET search_path = public
AS $$
BEGIN
    UPDATE public.scans s
    SET image_storage_urls = ARRAY[]::text[]
    FROM public.users u
    WHERE s.user_id = u.id
      AND u.subscription_tier = 'free'
      AND s.timestamp < NOW() - INTERVAL '90 days'
      AND s.image_storage_urls != '{}';
END;
$$;

-- 3. Create the pg_cron job to execute this function exactly once a day at 02:00 AM UTC
-- We unschedule first to ensure this migration is idempotent
DO $$
BEGIN
    PERFORM cron.unschedule('scrub_expired_free_urls_job');
EXCEPTION WHEN OTHERS THEN
    -- ignore error
END;
$$;
SELECT cron.schedule('scrub_expired_free_urls_job', '0 2 * * *', $$ SELECT public.scrub_expired_free_tier_urls(); $$);

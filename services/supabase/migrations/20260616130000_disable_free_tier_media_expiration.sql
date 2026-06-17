-- Biological scan media is durable regardless of subscription tier.
-- Keep temporary/staging and non-biological cleanup policies, but stop clearing
-- successful biological evidence from Free users after an age window.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
    PERFORM cron.unschedule('scrub_expired_free_urls_job');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so this migration remains idempotent across projects.
END;
$$;

DO $$
BEGIN
    PERFORM cron.unschedule('auto_purge_domesticated_daily');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so this migration remains idempotent across projects.
END;
$$;

DROP FUNCTION IF EXISTS public.scrub_expired_free_tier_urls();

DROP INDEX IF EXISTS public.idx_scans_domesticated_purge;

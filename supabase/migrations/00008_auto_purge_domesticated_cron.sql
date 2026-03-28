-- 1. Enable required network and scheduling extensions
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

-- 2. Clean previous schedules to execute idempotently
DO $$
BEGIN
    PERFORM cron.unschedule('scrub_expired_free_urls_job');
EXCEPTION WHEN OTHERS THEN
    -- Ignore error if job doesn't exist
END;
$$;

DO $$
BEGIN
    PERFORM cron.unschedule('auto_purge_domesticated_daily');
EXCEPTION WHEN OTHERS THEN
    -- Ignore error if job doesn't exist
END;
$$;

-- 3. Schedule the Edge Function invocation
-- Executing every day at 04:00 UTC (running after auto-purge-nonbio which is at 03:00)
SELECT cron.schedule(
    'auto_purge_domesticated_daily',
    '0 4 * * *',
    $$
    DO $job$
    DECLARE
        project_url text;
        service_role_key text;
        edge_endpoint text;
    BEGIN
        -- Retrieve native PostgreSQL secrets via Vault
        SELECT decrypted_secret INTO project_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
        SELECT decrypted_secret INTO service_role_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;
        
        -- Fallback to native postgrest config settings if Vault wasn't manually primed
        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', true);
        END IF;
        
        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.service_role_key', true);
        END IF;

        -- Formulate the target Edge Function endpoint
        edge_endpoint := project_url || '/functions/v1/auto-purge-domesticated';

        -- Fire async POST safely bridging S3/R2 deletions
        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            )
        );
    END;
    $job$;
    $$
);

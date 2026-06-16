ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS subscription_expires_at timestamp with time zone;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

DO $$
BEGIN
    PERFORM cron.unschedule('expire_subscription_passes_hourly');
EXCEPTION WHEN OTHERS THEN
END;
$$;

SELECT cron.schedule(
    'expire_subscription_passes_hourly',
    '5 * * * *',
    $$
    DO $job$
    DECLARE
        project_url text;
        service_role_key text;
        edge_endpoint text;
    BEGIN
        SELECT decrypted_secret INTO project_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
        SELECT decrypted_secret INTO service_role_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', true);
        END IF;

        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.service_role_key', true);
        END IF;

        edge_endpoint := project_url || '/functions/v1/expire-subscription-passes';

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

DO $$
BEGIN
    PERFORM cron.unschedule('refresh_species_model_content_hourly');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so re-running the migration remains idempotent.
END;
$$;

SELECT cron.schedule(
    'refresh_species_model_content_hourly',
    '47 * * * *',
    $$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
        edge_endpoint TEXT;
    BEGIN
        SELECT decrypted_secret INTO project_url
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT decrypted_secret INTO service_role_key
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', true);
        END IF;

        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.service_role_key', true);
        END IF;

        edge_endpoint := project_url || '/functions/v1/refresh-species-model-content';

        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := jsonb_build_object('limit', 12)
        );
    END;
    $job$;
    $$
);

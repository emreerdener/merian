-- Temporarily lower the Merian-sourced reference-image quality gate so more
-- published community photos can supplement weaker external reference imagery.

DO $$
DECLARE
    function_definition TEXT;
BEGIN
    SELECT pg_get_functiondef(
        'public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::regprocedure
    )
    INTO function_definition;

    IF function_definition IS NULL THEN
        RAISE EXCEPTION 'public.refresh_merian_reference_images(integer,integer,boolean,double precision) does not exist';
    END IF;

    function_definition := regexp_replace(
        function_definition,
        'p_quality_threshold integer DEFAULT 90',
        'p_quality_threshold integer DEFAULT 80',
        'i'
    );

    IF function_definition !~* 'p_quality_threshold integer DEFAULT 80' THEN
        RAISE EXCEPTION 'Failed to update refresh_merian_reference_images quality threshold default';
    END IF;

    EXECUTE function_definition;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images(INTEGER, INTEGER, BOOLEAN, DOUBLE PRECISION) TO service_role;

DO $$
BEGIN
    PERFORM cron.unschedule('refresh_merian_reference_images_hourly');
EXCEPTION WHEN OTHERS THEN
    -- Ignore missing jobs so re-running the migration remains idempotent.
END;
$$;

SELECT cron.schedule(
    'refresh_merian_reference_images_hourly',
    '37 * * * *',
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

        edge_endpoint := project_url || '/functions/v1/refresh-merian-reference-images';

        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := jsonb_build_object(
                'quality_threshold', 80,
                'species_confidence_threshold', 0.95,
                'per_species_limit', 8
            )
        );
    END;
    $job$;
    $$
);

NOTIFY pgrst, 'reload schema';

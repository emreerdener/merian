-- Retain the five-minute due-work cadence and the existing 15-minute health
-- alert, but dispatch an empty-queue heartbeat only on ten-minute boundaries.
-- Alter the existing job in place: a paused job must remain paused.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $migration$
DECLARE
    media_job RECORD;
BEGIN
    SELECT jobid, schedule, command INTO STRICT media_job
    FROM cron.job
    WHERE jobname = 'reconcile_explore_media_health_every_five_minutes';

    IF media_job.schedule <> '*/5 * * * *'
       OR pg_catalog.STRPOS(media_job.command, '/functions/v1/reconcile-explore-media-health') = 0
       OR pg_catalog.STRPOS(media_job.command, 'internal.server_api_request_headers(service_role_key)') = 0 THEN
        RAISE EXCEPTION 'Unexpected Explore media-health cron contract';
    END IF;

    PERFORM cron.alter_job(media_job.jobid, command := $command$
    DO $job$
    DECLARE
        dispatch_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        -- This read-only predicate mirrors claim_explore_media_health_checks.
        -- The RPC remains the sole owner of claiming, locks and lease fencing.
        -- A row becoming due after this check waits at most one normal tick.
        IF pg_catalog.DATE_PART('minute', dispatch_at)::INTEGER % 10 <> 0
           AND NOT EXISTS (
               SELECT 1
               FROM public.explore_post_media AS media
               INNER JOIN public.explore_posts AS post ON post.id = media.post_id
               INNER JOIN public.scans AS scan ON scan.id = post.scan_id
               LEFT JOIN internal.explore_media_health_check_claims AS existing_claim
                   ON existing_claim.media_id = media.id
                  AND existing_claim.claimed_until > dispatch_at
               WHERE media.next_health_check_at <= dispatch_at
                 AND post.unshared_at IS NULL
                 AND post.moderated_at IS NULL
                 AND NOT scan.is_tombstoned
                 AND existing_claim.media_id IS NULL
           ) THEN
            RETURN;
        END IF;

        SELECT decrypted_secret INTO project_url
        FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
        SELECT decrypted_secret INTO service_role_key
        FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', TRUE);
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.supabase_service_role_key', TRUE);
        END IF;
        IF project_url IS NULL OR service_role_key IS NULL THEN
            RAISE WARNING 'Explore media reconciliation skipped: missing Supabase URL or service role key.';
            RETURN;
        END IF;

        PERFORM net.http_post(
            url := pg_catalog.RTRIM(project_url, '/') || '/functions/v1/reconcile-explore-media-health',
            headers := internal.server_api_request_headers(service_role_key),
            body := pg_catalog.JSONB_BUILD_OBJECT('limit', 200, 'leaseSeconds', 300),
            timeout_milliseconds := 120000
        );
    END;
    $job$;
    $command$);
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;

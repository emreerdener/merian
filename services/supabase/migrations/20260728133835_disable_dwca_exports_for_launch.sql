-- Keep Darwin Core Archive exports unavailable for the initial production
-- launch without relying on a particular iOS or Edge bundle. The private
-- singleton is the canonical release state; a BEFORE INSERT trigger fences old
-- bundles and unexpected service-role inserts, while the request RPC combines
-- release-state enforcement, the rolling rate window, and job creation in one
-- transaction.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE TABLE internal.dwca_export_release_control (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE
        CHECK (singleton),
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

INSERT INTO internal.dwca_export_release_control (
    singleton,
    enabled,
    updated_at
)
VALUES (
    TRUE,
    FALSE,
    pg_catalog.NOW()
)
ON CONFLICT (singleton) DO UPDATE
SET enabled = FALSE,
    updated_at = pg_catalog.NOW();

ALTER TABLE internal.dwca_export_release_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.dwca_export_release_control
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.dwca_export_release_control IS
    'Private reviewed release gate for DwC-A intake, processing, delivery, and downloads. Missing state is interpreted as disabled.';
COMMENT ON COLUMN internal.dwca_export_release_control.enabled IS
    'False for the initial launch. Re-enable only through a reviewed migration after the deferred export release gates pass.';

CREATE OR REPLACE FUNCTION internal.dwca_exports_are_enabled()
RETURNS BOOLEAN
LANGUAGE PLPGSQL
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    release_enabled BOOLEAN;
BEGIN
    -- The shared singleton lock lasts until the caller transaction ends.
    -- Reviewed enable/disable migrations update this row, so intake and direct
    -- legacy inserts must either commit before the state change or observe the
    -- new state afterward.
    SELECT release_control.enabled
    INTO release_enabled
    FROM internal.dwca_export_release_control AS release_control
    WHERE release_control.singleton
    FOR SHARE;

    RETURN COALESCE(release_enabled, FALSE);
END;
$$;

REVOKE ALL ON FUNCTION internal.dwca_exports_are_enabled()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.enforce_dwca_export_intake_gate()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT internal.dwca_exports_are_enabled() THEN
        RAISE EXCEPTION 'dwca_exports_disabled'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_dwca_export_intake_gate()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS a_enforce_dwca_export_intake_gate
    ON public.export_jobs;
CREATE TRIGGER a_enforce_dwca_export_intake_gate
BEFORE INSERT ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_dwca_export_intake_gate();

CREATE OR REPLACE FUNCTION public.get_dwca_export_release_state()
RETURNS JSONB
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'enabled',
        internal.dwca_exports_are_enabled()
    );
END;
$$;

COMMENT ON FUNCTION public.get_dwca_export_release_state() IS
    'Returns the service-only canonical DwC-A release state. Missing private state fails closed.';

REVOKE ALL ON FUNCTION public.get_dwca_export_release_state()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dwca_export_release_state()
    TO service_role;

CREATE OR REPLACE FUNCTION public.request_dwca_export_job(
    p_user_id UUID,
    p_export_scope TEXT,
    p_include_precise_coordinates BOOLEAN
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    requested_job_id UUID;
    violated_constraint TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_export_scope IS DISTINCT FROM 'personal'
       OR p_include_precise_coordinates IS NULL THEN
        RAISE EXCEPTION 'invalid_dwca_export_request'
            USING ERRCODE = '22023';
    END IF;

    IF NOT internal.dwca_exports_are_enabled() THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('status', 'disabled');
    END IF;

    -- The release helper retains a shared lock on the canonical singleton.
    -- Serialize both the rolling window and partial-unique-index check for one
    -- account only after the feature is enabled. Hash collisions only reduce
    -- concurrency; they cannot weaken the release or rate-limit fences.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-dwca-export-request:' || p_user_id::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM public.export_jobs AS jobs
        WHERE jobs.user_id = p_user_id
          AND jobs.status <> 'failed'
          AND jobs.created_at >=
                pg_catalog.NOW() - INTERVAL '24 hours'
    ) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('status', 'rate_limited');
    END IF;

    requested_job_id := extensions.gen_random_uuid();

    BEGIN
        INSERT INTO public.export_jobs (
            id,
            user_id,
            export_scope,
            include_precise_coordinates,
            status
        )
        VALUES (
            requested_job_id,
            p_user_id,
            p_export_scope,
            p_include_precise_coordinates,
            'pending'
        );
    EXCEPTION
        WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS
                violated_constraint = CONSTRAINT_NAME;
            IF violated_constraint IS DISTINCT FROM
                    'idx_export_jobs_user_pending' THEN
                RAISE;
            END IF;
            RETURN pg_catalog.JSONB_BUILD_OBJECT(
                'status',
                'already_pending'
            );
    END;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'status',
        'queued',
        'job_id',
        requested_job_id
    );
END;
$$;

COMMENT ON FUNCTION public.request_dwca_export_job(UUID, TEXT, BOOLEAN) IS
    'Service-only atomic release-gated and account-serialized DwC-A job request. User scope is canonicalized by the authenticated Edge route.';

REVOKE ALL ON FUNCTION public.request_dwca_export_job(
    UUID,
    TEXT,
    BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_dwca_export_job(
    UUID,
    TEXT,
    BOOLEAN
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_dwca_export_release_state()',
        'Reads the canonical default-off DwC-A release state for reviewed Edge routes.'
    ),
    (
        'service_role',
        'public.request_dwca_export_job(uuid,text,boolean)',
        'Atomically enforces the DwC-A release gate and rolling account limit before queue insertion.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- Stop new scheduled processing before making the existing queue terminal.
-- The independent archive-cleanup schedule intentionally remains active.
DO $schedule$
DECLARE
    scheduled_job RECORD;
BEGIN
    FOR scheduled_job IN
        SELECT jobs.jobid
        FROM cron.job AS jobs
        WHERE jobs.jobname = 'resume_dwca_exports_every_minute'
        ORDER BY jobs.jobid
    LOOP
        PERFORM cron.unschedule(scheduled_job.jobid);
    END LOOP;
END;
$schedule$;

-- Wait for any transaction that currently owns a job row, then make every
-- nonterminal generation fail closed. The existing terminal-transition trigger
-- revokes staged grants, enqueues known final archives, and purges snapshots.
UPDATE public.export_jobs AS jobs
SET status = 'failed',
    failure_code = 'feature_disabled',
    error_message = 'Export processing is not available.',
    completed_at = pg_catalog.NOW()
WHERE jobs.status IN ('pending', 'processing');

-- Completed jobs are historical records, but their capabilities must no longer
-- authorize storage. Lock parent rows in a canonical order before revocation
-- and durable cleanup enqueue so this migration follows the runtime protocol.
DO $retire$
DECLARE
    export_row RECORD;
BEGIN
    FOR export_row IN
        SELECT
            jobs.id AS job_id,
            jobs.user_id,
            jobs.archive_object_key
        FROM public.export_jobs AS jobs
        WHERE (
                jobs.archive_object_key IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM internal.export_archive_cleanup_jobs AS cleanup
                    WHERE cleanup.object_key = jobs.archive_object_key
                      AND cleanup.status = 'completed'
                )
              )
           OR EXISTS (
                SELECT 1
                FROM internal.export_download_grants AS grants
                WHERE grants.job_id = jobs.id
                  AND grants.cleaned_at IS NULL
           )
        ORDER BY jobs.id
        FOR UPDATE
    LOOP
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED(
                'merian-dwca-export:' || export_row.job_id::TEXT,
                0::BIGINT
            )
        );

        UPDATE internal.export_download_grants AS grants
        SET revoked_at = COALESCE(
                grants.revoked_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            revocation_reason = COALESCE(
                grants.revocation_reason,
                'feature_disabled'
            )
        WHERE grants.job_id = export_row.job_id
          AND grants.cleaned_at IS NULL;

        IF export_row.archive_object_key IS NOT NULL
           AND export_row.archive_object_key ~ (
                '^exports/'
                || export_row.user_id::TEXT
                || '/'
                || export_row.job_id::TEXT
                || '/[0-9a-f-]{36}[.]zip$'
           ) THEN
            PERFORM internal.enqueue_dwca_archive_cleanup(
                export_row.job_id,
                export_row.archive_object_key,
                'feature_disabled'
            );
        END IF;
    END LOOP;
END;
$retire$;

-- Database manifests and leases are no longer useful once all jobs are
-- terminal. Physical temporary work objects remain private and are bounded by
-- the checked-in one-day R2 lifecycle safety net.
DELETE FROM internal.export_job_claims;
DELETE FROM internal.export_job_chunks;
DELETE FROM internal.export_job_work;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;

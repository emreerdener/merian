-- Make Identify idempotency return the original successful payload.
--
-- The AI quota ledger correctly prevented a second provider call, but a retry
-- after a lost HTTP response received 409 ai_request_already_completed. Current
-- iOS interpreted that conflict as a network failure even though the scan row
-- was already durable, which stranded Share and Field Chat behind a local
-- error placeholder. Persist the validated response at the same transactional
-- boundary as scan/media completion so any retry can replay HTTP 200.

ALTER TABLE public.scan_ingestion_jobs
    ADD COLUMN IF NOT EXISTS response_envelope JSONB;

ALTER TABLE public.scan_ingestion_jobs
    DROP CONSTRAINT IF EXISTS scan_ingestion_jobs_response_envelope_check;
ALTER TABLE public.scan_ingestion_jobs
    ADD CONSTRAINT scan_ingestion_jobs_response_envelope_check CHECK (
        response_envelope IS NULL
        OR (
            pg_catalog.JSONB_TYPEOF(response_envelope) = 'object'
            AND pg_catalog.JSONB_TYPEOF(response_envelope -> 'data') = 'object'
            AND pg_catalog.JSONB_TYPEOF(response_envelope -> 'success') = 'boolean'
            AND response_envelope -> 'success' = 'true'::JSONB
            AND pg_catalog.JSONB_TYPEOF(
                response_envelope #> '{data,scan_id}'
            ) = 'string'
            AND response_envelope #>> '{data,scan_id}' = scan_id
            AND pg_catalog.OCTET_LENGTH(response_envelope::TEXT) <= 262144
        ) IS TRUE
    );

COMMENT ON COLUMN public.scan_ingestion_jobs.response_envelope IS
    'Validated canonical Identify success envelope replayed after an ambiguous/lost client response; contains no raw media bytes.';

CREATE OR REPLACE FUNCTION public.complete_scan_ingestion_finalization_with_response(
    p_scan_id UUID,
    p_user_id UUID,
    p_response_envelope JSONB,
    p_promoted_urls_by_storage_key JSONB,
    p_deleted_storage_keys TEXT[]
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    finalization_result TEXT;
    response_is_required BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR (
           pg_catalog.JSONB_TYPEOF(p_response_envelope) = 'object'
           AND pg_catalog.JSONB_TYPEOF(
               p_response_envelope -> 'data'
           ) = 'object'
           AND pg_catalog.JSONB_TYPEOF(
               p_response_envelope -> 'success'
           ) = 'boolean'
           AND p_response_envelope -> 'success' = 'true'::JSONB
           AND pg_catalog.JSONB_TYPEOF(
               p_response_envelope #> '{data,scan_id}'
           ) = 'string'
           AND p_response_envelope #>> '{data,scan_id}' = p_scan_id::TEXT
           AND pg_catalog.OCTET_LENGTH(
               p_response_envelope::TEXT
           ) <= 262144
       ) IS NOT TRUE THEN
        RAISE EXCEPTION 'invalid_scan_response_envelope'
            USING ERRCODE = '22023';
    END IF;

    finalization_result := public.complete_scan_ingestion_finalization(
        p_scan_id,
        p_user_id,
        COALESCE(p_promoted_urls_by_storage_key, '{}'::JSONB),
        COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
    );

    response_is_required := finalization_result IN (
        'completed',
        'already_complete'
    ) AND EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
    );

    IF response_is_required THEN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET response_envelope = COALESCE(
                jobs.response_envelope,
                p_response_envelope
            ),
            updated_at = CASE
                WHEN jobs.response_envelope IS NULL
                    THEN pg_catalog.NOW()
                ELSE jobs.updated_at
            END
        WHERE jobs.scan_id = p_scan_id::TEXT
          AND jobs.user_id = p_user_id
          AND jobs.status = 'complete';

        IF NOT EXISTS (
            SELECT 1
            FROM public.scan_ingestion_jobs AS jobs
            WHERE jobs.scan_id = p_scan_id::TEXT
              AND jobs.user_id = p_user_id
              AND jobs.status = 'complete'
              AND jobs.response_envelope IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'scan_response_persistence_failed'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    RETURN finalization_result;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_scan_ingestion_finalization_with_response(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_scan_ingestion_finalization_with_response(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.complete_scan_ingestion_finalization_with_response(uuid,uuid,jsonb,jsonb,text[])',
    'Atomically finalizes required scan media and immutably persists the canonical Identify response for idempotent replay.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

COMMENT ON FUNCTION public.complete_scan_ingestion_finalization_with_response(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) IS
    'Service-only atomic scan/media completion plus immutable canonical Identify response persistence.';

CREATE OR REPLACE FUNCTION internal.clear_scan_ingestion_response_on_owner_removal()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET response_envelope = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.scan_id = OLD.id::TEXT
          AND jobs.user_id = OLD.user_id
          AND jobs.response_envelope IS NOT NULL;
    ELSIF OLD.user_id IS DISTINCT FROM NEW.user_id THEN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET response_envelope = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.scan_id = OLD.id::TEXT
          AND jobs.user_id = OLD.user_id
          AND jobs.response_envelope IS NOT NULL;
    END IF;
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION internal.clear_scan_ingestion_response_on_owner_removal()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS clear_scan_ingestion_response_on_owner_removal
    ON public.scans;
CREATE TRIGGER clear_scan_ingestion_response_on_owner_removal
AFTER UPDATE OF user_id OR DELETE
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION internal.clear_scan_ingestion_response_on_owner_removal();

CREATE OR REPLACE FUNCTION internal.clear_scan_ingestion_response_on_deletion_request()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    UPDATE public.scan_ingestion_jobs AS jobs
    SET response_envelope = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.scan_id = NEW.scan_id::TEXT
      AND jobs.user_id = NEW.user_id
      AND jobs.response_envelope IS NOT NULL;
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION internal.clear_scan_ingestion_response_on_deletion_request()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS clear_scan_ingestion_response_on_deletion_request
    ON internal.scan_deletion_tombstones;
CREATE TRIGGER clear_scan_ingestion_response_on_deletion_request
AFTER INSERT
ON internal.scan_deletion_tombstones
FOR EACH ROW
EXECUTE FUNCTION internal.clear_scan_ingestion_response_on_deletion_request();

NOTIFY pgrst, 'reload schema';

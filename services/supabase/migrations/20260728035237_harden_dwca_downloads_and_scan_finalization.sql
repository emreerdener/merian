SET lock_timeout = '10s';
SET statement_timeout = '10min';

-- ---------------------------------------------------------------------------
-- Scan ingestion and owner-row recovery
-- ---------------------------------------------------------------------------

ALTER TABLE public.scan_ingestion_jobs
    ADD COLUMN terminal_reason_code TEXT,
    ADD CONSTRAINT scan_ingestion_jobs_terminal_reason_code_check
        CHECK (
            terminal_reason_code IS NULL
            OR terminal_reason_code ~ '^[a-z][a-z0-9_]{1,63}$'
        );

UPDATE public.scan_ingestion_jobs AS jobs
SET terminal_reason_code = CASE
    WHEN jobs.stage = 'moderation_rejected'
        THEN 'content_policy_rejected'
    WHEN jobs.stage = 'ai_inference_non_stop_finish'
        THEN 'provider_policy_rejected'
    WHEN jobs.stage = 'server_replay_limit_reached'
        THEN 'replay_exhausted'
    WHEN jobs.stage = 'media_reconciliation_abandoned'
        THEN 'media_reconciliation_abandoned'
    ELSE 'legacy_terminal_unknown'
END
WHERE jobs.status = 'failed_terminal'
  AND jobs.terminal_reason_code IS NULL;

COMMENT ON COLUMN public.scan_ingestion_jobs.terminal_reason_code IS
    'Stable machine-readable terminal outcome. Recovery fails closed unless this code is explicitly allowlisted.';

-- Public-schema grants and owner RLS do not make service-role R2 deletion safe
-- when callers can write arbitrary media URLs into their own rows. Remove all
-- broad Data API mutation rights and retain only the review/tag columns used by
-- the iOS application. Service-owned ingestion remains the sole writer of
-- identity, ownership, media, privacy, and model-result fields.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON TABLE public.scans
    FROM PUBLIC, anon, authenticated;
-- Rolling compatibility for already-installed clients. New clients use the
-- owner-derived RPCs below. Remove these column grants only after the minimum
-- supported iOS version contains those RPC call sites.
GRANT UPDATE (
    custom_tags,
    user_identification_override,
    user_confirmed_identification,
    confirmed_species_id,
    user_review_state
) ON TABLE public.scans TO authenticated;

ALTER TABLE public.scans
    ADD CONSTRAINT scans_scan_media_video_urls_bounded_check
        CHECK (
            internal.text_array_elements_are_bounded(
                video_storage_urls,
                5,
                4096
            )
        ) NOT VALID,
    ADD CONSTRAINT scans_scan_media_audio_urls_bounded_check
        CHECK (
            internal.text_array_elements_are_bounded(
                audio_storage_urls,
                5,
                4096
            )
        ) NOT VALID,
    ADD CONSTRAINT scans_custom_tags_bounded_check
        CHECK (
            internal.text_array_elements_are_bounded(
                custom_tags,
                50,
                256
            )
        ) NOT VALID,
    ADD CONSTRAINT scans_identification_override_bounded_check
        CHECK (
            user_identification_override IS NULL
            OR pg_catalog.OCTET_LENGTH(user_identification_override) <= 1024
        ) NOT VALID;

-- Fail the deployment before privileged routines become reachable if legacy
-- data violates the same limits enforced on all new writes.
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_scan_media_video_urls_bounded_check;
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_scan_media_audio_urls_bounded_check;
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_custom_tags_bounded_check;
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_identification_override_bounded_check;

COMMENT ON CONSTRAINT scans_scan_media_video_urls_bounded_check
    ON public.scans IS
    'Bounds canonical video references before service-owned fetch or deletion.';
COMMENT ON CONSTRAINT scans_scan_media_audio_urls_bounded_check
    ON public.scans IS
    'Bounds canonical audio references before service-owned fetch or deletion.';
COMMENT ON CONSTRAINT scans_custom_tags_bounded_check
    ON public.scans IS
    'Bounds the only caller-written scan array exposed through the Data API.';
COMMENT ON CONSTRAINT scans_identification_override_bounded_check
    ON public.scans IS
    'Bounds caller-written identification text before downstream prompts and exports.';

CREATE OR REPLACE FUNCTION public.update_owned_scan_custom_tags(
    p_scan_id UUID,
    p_custom_tags TEXT[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    caller_user_id UUID;
BEGIN
    caller_user_id := auth.uid();
    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;
    IF p_scan_id IS NULL
       OR p_custom_tags IS NULL
       OR NOT internal.text_array_elements_are_bounded(
            p_custom_tags,
            50,
            256
       ) THEN
        RAISE EXCEPTION 'invalid_custom_tags'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.scans AS scans
    SET custom_tags = p_custom_tags
    WHERE scans.id = p_scan_id
      AND scans.user_id = caller_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'scan_not_owned_or_missing'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_owned_scan_custom_tags(UUID, TEXT[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_owned_scan_custom_tags(UUID, TEXT[])
    TO authenticated;
COMMENT ON FUNCTION public.update_owned_scan_custom_tags(UUID, TEXT[]) IS
    'Authenticated owner-only custom-tag update. Caller identity is derived from auth.uid; direct scan-table mutation remains revoked.';

CREATE OR REPLACE FUNCTION public.update_owned_scan_identification_review(
    p_scan_id UUID,
    p_override TEXT,
    p_confirmed BOOLEAN,
    p_confirmed_species_id UUID,
    p_user_review_state public.user_review_state
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    caller_user_id UUID;
BEGIN
    caller_user_id := auth.uid();
    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;
    IF p_scan_id IS NULL
       OR p_confirmed IS NULL
       OR p_user_review_state IS NULL
       OR (
            p_override IS NOT NULL
            AND (
                pg_catalog.OCTET_LENGTH(p_override) > 1024
                OR p_override ~ '[[:cntrl:]]'
                OR pg_catalog.BTRIM(p_override) = ''
            )
       )
       OR (
            p_user_review_state = 'unreviewed'::public.user_review_state
            AND (
                p_override IS NOT NULL
                OR p_confirmed
                OR p_confirmed_species_id IS NOT NULL
            )
       )
       OR (
            p_user_review_state = 'ai_confirmed'::public.user_review_state
            AND (
                p_override IS NOT NULL
                OR NOT p_confirmed
            )
       )
       OR (
            p_user_review_state = 'user_overridden'::public.user_review_state
            AND (
                p_override IS NULL
                OR p_confirmed
            )
       ) THEN
        RAISE EXCEPTION 'invalid_identification_review'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.scans AS scans
    SET user_identification_override = p_override,
        user_confirmed_identification = p_confirmed,
        confirmed_species_id = p_confirmed_species_id,
        user_review_state = p_user_review_state
    WHERE scans.id = p_scan_id
      AND scans.user_id = caller_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'scan_not_owned_or_missing'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_owned_scan_identification_review(
    UUID,
    TEXT,
    BOOLEAN,
    UUID,
    public.user_review_state
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_owned_scan_identification_review(
    UUID,
    TEXT,
    BOOLEAN,
    UUID,
    public.user_review_state
) TO authenticated;
COMMENT ON FUNCTION public.update_owned_scan_identification_review(
    UUID,
    TEXT,
    BOOLEAN,
    UUID,
    public.user_review_state
) IS
    'Authenticated owner-only coherent identification-review update. Caller identity is derived from auth.uid.';

-- A scan UUID is a durable generation identifier. Once its owner asks for
-- erasure, no delayed inference, replay, or second device may reconstruct that
-- generation from a completed ingestion ledger. Keep the tombstone private and
-- indefinitely durable; it contains no observation content.
CREATE TABLE internal.scan_deletion_tombstones (
    scan_id UUID PRIMARY KEY,
    user_id UUID,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    completed_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    claim_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error_code TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CHECK (
        completed_at IS NULL
        OR completed_at >= requested_at
    ),
    CHECK (
        attempt_count >= 0
        AND attempt_count <= 1000000
    ),
    CHECK (
        (claim_token IS NULL) = (lease_expires_at IS NULL)
    ),
    CHECK (
        completed_at IS NULL
        OR (
            claim_token IS NULL
            AND lease_expires_at IS NULL
        )
    ),
    CHECK (
        last_error_code IS NULL
        OR last_error_code ~ '^[a-z][a-z0-9_]{1,63}$'
    )
);

REVOKE ALL ON TABLE internal.scan_deletion_tombstones
    FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE internal.scan_deletion_tombstones ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE internal.scan_deletion_tombstones IS
    'Private permanent scan-generation fences plus leased pending erasure state. Completed rows retain no owner identifier or observation content.';
COMMENT ON COLUMN internal.scan_deletion_tombstones.user_id IS
    'Owner binding while erasure is pending; cleared transactionally when erasure or account anonymization completes.';
COMMENT ON COLUMN internal.scan_deletion_tombstones.claim_token IS
    'Compare-before-release generation for the independent scan-erasure reaper.';

CREATE INDEX scan_deletion_tombstones_pending_idx
    ON internal.scan_deletion_tombstones (
        next_attempt_at,
        requested_at,
        scan_id
    )
    WHERE completed_at IS NULL;

CREATE OR REPLACE FUNCTION internal.reject_deleted_scan_generation_mutation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = NEW.id
    ) THEN
        -- Durable account deletion supersedes an incomplete individual
        -- deletion. Permit only the exact ownerless, media-free, location-free
        -- tombstone shape written by apply_user_tombstone; ordinary delayed
        -- scan writes remain rejected.
        IF TG_OP = 'UPDATE' THEN
            IF NEW.id IS NOT DISTINCT FROM OLD.id
               AND NEW.user_id IS NULL
               AND NEW.is_tombstoned IS TRUE
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.image_storage_urls, '{}'::TEXT[])
               ) = 0
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.video_storage_urls, '{}'::TEXT[])
               ) = 0
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.audio_storage_urls, '{}'::TEXT[])
               ) = 0
               AND NEW.captured_media IS NULL
               AND NEW.gps_lat_exact IS NULL
               AND NEW.gps_long_exact IS NULL
               AND NEW.gps_elevation IS NULL
               AND NEW.semantic_location IS NULL
               AND NEW.device_locale IS NULL
               AND NEW.device_time_zone IS NULL
               AND NEW.user_observation_context IS NULL
               AND pg_catalog.CARDINALITY(
                    COALESCE(NEW.custom_tags, '{}'::TEXT[])
               ) = 0
               AND NEW.human_intervention_notes IS NULL THEN
                RETURN NEW;
            END IF;
        END IF;

        RAISE EXCEPTION 'scan_generation_deleted'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.reject_deleted_scan_generation_mutation()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reject_deleted_scan_generation_mutation
    ON public.scans;
CREATE TRIGGER reject_deleted_scan_generation_mutation
BEFORE INSERT OR UPDATE ON public.scans
FOR EACH ROW
EXECUTE FUNCTION internal.reject_deleted_scan_generation_mutation();

CREATE OR REPLACE FUNCTION internal.record_deleted_scan_generation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO internal.scan_deletion_tombstones AS tombstones (
        scan_id,
        user_id,
        requested_at,
        completed_at,
        claim_token,
        lease_expires_at,
        last_error_code,
        updated_at
    )
    VALUES (
        OLD.id,
        NULL,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        NULL,
        NULL,
        NULL,
        pg_catalog.NOW()
    )
    ON CONFLICT (scan_id) DO UPDATE
    SET user_id = NULL,
        completed_at = COALESCE(
            tombstones.completed_at,
            EXCLUDED.completed_at
        ),
        claim_token = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW();
    RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION internal.record_deleted_scan_generation()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS record_deleted_scan_generation ON public.scans;
CREATE TRIGGER record_deleted_scan_generation
AFTER DELETE ON public.scans
FOR EACH ROW
EXECUTE FUNCTION internal.record_deleted_scan_generation();

CREATE OR REPLACE FUNCTION internal.unlink_deleted_user_scan_tombstones()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE internal.scan_deletion_tombstones AS tombstones
    SET user_id = NULL,
        completed_at = COALESCE(
            tombstones.completed_at,
            pg_catalog.NOW()
        ),
        claim_token = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE tombstones.user_id = OLD.id;
    RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION internal.unlink_deleted_user_scan_tombstones()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS unlink_deleted_user_scan_tombstones
    ON public.users;
CREATE TRIGGER unlink_deleted_user_scan_tombstones
AFTER DELETE ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.unlink_deleted_user_scan_tombstones();

CREATE OR REPLACE FUNCTION public.request_scan_deletion(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    scan_owner UUID;
    tombstone_owner UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_deletion_identity'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    SELECT scans.user_id
    INTO scan_owner
    FROM public.scans AS scans
    WHERE scans.id = p_scan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        SELECT tombstones.user_id
        INTO tombstone_owner
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id;

        IF FOUND AND tombstone_owner IS NOT DISTINCT FROM p_user_id THEN
            RETURN 'already_deleted';
        END IF;
        RETURN 'not_found';
    END IF;

    IF scan_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'forbidden';
    END IF;

    INSERT INTO internal.scan_deletion_tombstones (
        scan_id,
        user_id
    )
    VALUES (
        p_scan_id,
        p_user_id
    )
    ON CONFLICT (scan_id) DO NOTHING;

    SELECT tombstones.user_id
    INTO STRICT tombstone_owner
    FROM internal.scan_deletion_tombstones AS tombstones
    WHERE tombstones.scan_id = p_scan_id;

    IF tombstone_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'forbidden';
    END IF;

    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'failed_terminal',
        stage = 'user_deleted',
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = NULL,
        last_error = NULL,
        terminal_reason_code = 'user_deleted',
        completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status <> 'complete';

    RETURN 'accepted';
END;
$$;

REVOKE ALL ON FUNCTION public.request_scan_deletion(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_scan_deletion(UUID, UUID)
    TO service_role;
COMMENT ON FUNCTION public.request_scan_deletion(UUID, UUID) IS
    'Service-only owner verification and permanent scan-generation fence written before external media erasure.';

CREATE OR REPLACE FUNCTION public.complete_scan_deletion(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    tombstone_owner UUID;
    tombstone_completed_at TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_deletion_identity'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    SELECT
        tombstones.user_id,
        tombstones.completed_at
    INTO
        tombstone_owner,
        tombstone_completed_at
    FROM internal.scan_deletion_tombstones AS tombstones
    WHERE tombstones.scan_id = p_scan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    IF tombstone_owner IS NULL
       AND tombstone_completed_at IS NOT NULL THEN
        RETURN TRUE;
    END IF;
    IF tombstone_owner IS DISTINCT FROM p_user_id THEN
        RETURN FALSE;
    END IF;

    DELETE FROM public.scans AS scans
    WHERE scans.id = p_scan_id
      AND scans.user_id = p_user_id;

    UPDATE internal.scan_deletion_tombstones AS tombstones
    SET user_id = NULL,
        completed_at = COALESCE(
            tombstones.completed_at,
            pg_catalog.NOW()
        ),
        claim_token = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE tombstones.scan_id = p_scan_id;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_scan_deletion(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_scan_deletion(UUID, UUID)
    TO service_role;
COMMENT ON FUNCTION public.complete_scan_deletion(UUID, UUID) IS
    'Service-only idempotent owner-row removal after all canonical scan media deletion is verified.';

-- Retention selection and erasure are intentionally separate transactions.
-- This routine does only the short database-side portion: select a bounded,
-- oldest-first candidate set, acquire scan-generation locks in UUID order,
-- recheck eligibility under the row lock, and write the permanent deletion
-- fences. The independent scan-deletion reaper owns all R2 work. This prevents
-- a finalizer from appending media after a retention worker has captured an
-- older URL list and before it deletes the row.
CREATE OR REPLACE FUNCTION public.request_nonbiological_scan_retention_deletions(
    p_limit INTEGER DEFAULT 500
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '30s'
AS $$
DECLARE
    batch_limit INTEGER := LEAST(
        GREATEST(COALESCE(p_limit, 500), 1),
        500
    );
    candidate_scan RECORD;
    scan_owner UUID;
    request_status TEXT;
    accepted_count INTEGER := 0;
BEGIN
    PERFORM internal.require_service_role();

    FOR candidate_scan IN
        WITH candidates AS MATERIALIZED (
            SELECT scans.id AS scan_id
            FROM public.scans AS scans
            WHERE scans.is_biological_subject IS FALSE
              AND scans.is_tombstoned IS FALSE
              AND scans.timestamp
                  < pg_catalog.NOW()
                    - pg_catalog.MAKE_INTERVAL(days => 30)
              AND scans.user_id IS NOT NULL
              AND scans.user_id
                  <> '00000000-0000-0000-0000-000000000000'::UUID
              AND NOT EXISTS (
                  SELECT 1
                  FROM internal.scan_deletion_tombstones AS tombstones
                  WHERE tombstones.scan_id = scans.id
              )
            ORDER BY scans.timestamp, scans.id
            LIMIT batch_limit
        )
        SELECT candidates.scan_id
        FROM candidates
        ORDER BY candidates.scan_id
    LOOP
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED(
                'merian-scan-ingestion:'
                    || candidate_scan.scan_id::TEXT,
                0::BIGINT
            )
        );

        -- A service finalizer or correction may have changed this row after
        -- candidate discovery. Recheck every retention predicate while the
        -- canonical generation lock and row lock are both held.
        SELECT scans.user_id
        INTO scan_owner
        FROM public.scans AS scans
        WHERE scans.id = candidate_scan.scan_id
          AND scans.is_biological_subject IS FALSE
          AND scans.is_tombstoned IS FALSE
          AND scans.timestamp
              < pg_catalog.NOW()
                - pg_catalog.MAKE_INTERVAL(days => 30)
          AND scans.user_id IS NOT NULL
          AND scans.user_id
              <> '00000000-0000-0000-0000-000000000000'::UUID
          AND NOT EXISTS (
              SELECT 1
              FROM internal.scan_deletion_tombstones AS tombstones
              WHERE tombstones.scan_id = scans.id
          )
        FOR UPDATE;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        SELECT public.request_scan_deletion(
            candidate_scan.scan_id,
            scan_owner
        )
        INTO STRICT request_status;

        IF request_status <> 'accepted' THEN
            RAISE EXCEPTION 'retention_scan_deletion_not_accepted'
                USING ERRCODE = '55000';
        END IF;
        accepted_count := accepted_count + 1;
    END LOOP;

    RETURN accepted_count;
END;
$$;

REVOKE ALL ON FUNCTION
    public.request_nonbiological_scan_retention_deletions(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
    public.request_nonbiological_scan_retention_deletions(INTEGER)
    TO service_role;
COMMENT ON FUNCTION
    public.request_nonbiological_scan_retention_deletions(INTEGER) IS
    'Service-only bounded retention selector that generation-locks, revalidates, and durably fences expired non-biological scans for the independent erasure reaper.';

CREATE OR REPLACE FUNCTION public.claim_scan_deletion_jobs(
    p_claim_token UUID,
    p_limit INTEGER DEFAULT 25,
    p_lease_seconds INTEGER DEFAULT 120
)
RETURNS TABLE (
    scan_id UUID,
    user_id UUID,
    attempt_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    batch_limit INTEGER := LEAST(
        GREATEST(COALESCE(p_limit, 25), 1),
        100
    );
    lease_seconds INTEGER := LEAST(
        GREATEST(COALESCE(p_lease_seconds, 120), 30),
        600
    );
BEGIN
    PERFORM internal.require_service_role();

    IF p_claim_token IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_deletion_claim_token'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH due AS (
        SELECT tombstones.scan_id
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.completed_at IS NULL
          AND tombstones.user_id IS NOT NULL
          AND tombstones.next_attempt_at <= pg_catalog.NOW()
          AND (
              tombstones.claim_token IS NULL
              OR tombstones.lease_expires_at <= pg_catalog.NOW()
          )
        ORDER BY
            tombstones.next_attempt_at,
            tombstones.requested_at,
            tombstones.scan_id
        FOR UPDATE SKIP LOCKED
        LIMIT batch_limit
    )
    UPDATE internal.scan_deletion_tombstones AS tombstones
    SET claim_token = p_claim_token,
        lease_expires_at = pg_catalog.NOW()
            + pg_catalog.MAKE_INTERVAL(secs => lease_seconds),
        attempt_count = tombstones.attempt_count + 1,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    FROM due
    WHERE tombstones.scan_id = due.scan_id
    RETURNING
        tombstones.scan_id,
        tombstones.user_id,
        tombstones.attempt_count;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_scan_deletion_jobs(
    UUID,
    INTEGER,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_scan_deletion_jobs(
    UUID,
    INTEGER,
    INTEGER
) TO service_role;
COMMENT ON FUNCTION public.claim_scan_deletion_jobs(
    UUID,
    INTEGER,
    INTEGER
) IS
    'Service-only bounded oldest-due scan erasure leases using SKIP LOCKED.';

CREATE OR REPLACE FUNCTION public.release_scan_deletion_job(
    p_scan_id UUID,
    p_user_id UUID,
    p_claim_token UUID,
    p_error_code TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    released BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR p_claim_token IS NULL
       OR p_error_code IS NULL
       OR p_error_code !~ '^[a-z][a-z0-9_]{1,63}$' THEN
        RAISE EXCEPTION 'invalid_scan_deletion_release'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.scan_deletion_tombstones AS tombstones
    SET claim_token = NULL,
        lease_expires_at = NULL,
        next_attempt_at = pg_catalog.NOW()
            + pg_catalog.MAKE_INTERVAL(
                secs => LEAST(
                    3600,
                    30 * (
                        1 << LEAST(
                            GREATEST(tombstones.attempt_count - 1, 0),
                            7
                        )
                    )
                )
            ),
        last_error_code = p_error_code,
        updated_at = pg_catalog.NOW()
    WHERE tombstones.scan_id = p_scan_id
      AND tombstones.user_id = p_user_id
      AND tombstones.completed_at IS NULL
      AND tombstones.claim_token = p_claim_token
    RETURNING TRUE INTO released;

    RETURN COALESCE(released, FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.release_scan_deletion_job(
    UUID,
    UUID,
    UUID,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_scan_deletion_job(
    UUID,
    UUID,
    UUID,
    TEXT
) TO service_role;
COMMENT ON FUNCTION public.release_scan_deletion_job(
    UUID,
    UUID,
    UUID,
    TEXT
) IS
    'Service-only compare-before-release with bounded exponential retry for interrupted scan erasure.';

CREATE OR REPLACE FUNCTION public.get_scan_deletion_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    pending_count BIGINT,
    processing_count BIGINT,
    expired_lease_count BIGINT,
    oldest_pending_at TIMESTAMPTZ,
    oldest_pending_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH health AS (
        SELECT
            COUNT(*) FILTER (
                WHERE tombstones.completed_at IS NULL
                  AND (
                      tombstones.claim_token IS NULL
                      OR tombstones.lease_expires_at
                          <= pg_catalog.NOW()
                  )
            ) AS pending_count,
            COUNT(*) FILTER (
                WHERE tombstones.completed_at IS NULL
                  AND tombstones.claim_token IS NOT NULL
                  AND tombstones.lease_expires_at
                      > pg_catalog.NOW()
            ) AS processing_count,
            COUNT(*) FILTER (
                WHERE tombstones.completed_at IS NULL
                  AND tombstones.claim_token IS NOT NULL
                  AND tombstones.lease_expires_at
                      <= pg_catalog.NOW()
            ) AS expired_lease_count,
            MIN(tombstones.requested_at) FILTER (
                WHERE tombstones.completed_at IS NULL
            ) AS oldest_pending_at
        FROM internal.scan_deletion_tombstones AS tombstones
    )
    SELECT
        pg_catalog.CLOCK_TIMESTAMP(),
        health.pending_count,
        health.processing_count,
        health.expired_lease_count,
        health.oldest_pending_at,
        CASE
            WHEN health.oldest_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                EXTRACT(
                    EPOCH FROM (
                        pg_catalog.CLOCK_TIMESTAMP()
                        - health.oldest_pending_at
                    )
                )::BIGINT
            )
        END
    FROM health;
END;
$$;

REVOKE ALL ON FUNCTION public.get_scan_deletion_health()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_scan_deletion_health()
    TO service_role;
COMMENT ON FUNCTION public.get_scan_deletion_health() IS
    'Service-only aggregate scan-erasure backlog, lease, and oldest-pending SLA health.';

-- Claim creation and owner-row recovery serialize on this transaction-scoped
-- advisory lock. If claim wins, recovery observes active ingestion and defers.
-- If recovery wins, it writes both the row and a complete recovery ledger;
-- claim then observes complete and never calls the AI provider.
CREATE OR REPLACE FUNCTION public.claim_scan_ingestion_job(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_upload_session_ids UUID[] DEFAULT '{}'::UUID[],
    p_manifest_checksum TEXT DEFAULT NULL,
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS public.scan_ingestion_jobs
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    claimed public.scan_ingestion_jobs;
    lease_seconds INTEGER := LEAST(
        GREATEST(
            COALESCE(p_lease_seconds, 300),
            30
        ),
        3600
    );
    scan_id_uuid UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF COALESCE(pg_catalog.BTRIM(p_scan_id), '')
        !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_ingestion_identity'
            USING ERRCODE = '22023';
    END IF;
    scan_id_uuid := p_scan_id::UUID;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || scan_id_uuid::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = scan_id_uuid
    ) THEN
        RAISE EXCEPTION 'scan_generation_deleted'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.scan_ingestion_jobs AS existing_job (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        attempt_count,
        media_counts,
        media_object_keys,
        upload_session_ids,
        manifest_checksum,
        locked_at,
        lock_expires_at,
        retry_after,
        last_error,
        terminal_reason_code,
        completed_at,
        updated_at
    )
    VALUES (
        scan_id_uuid::TEXT,
        p_user_id,
        COALESCE(
            NULLIF(pg_catalog.BTRIM(p_endpoint), ''),
            'identify-multimodal'
        ),
        'processing',
        'request_received',
        1,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        COALESCE(p_upload_session_ids, '{}'::UUID[]),
        NULLIF(
            pg_catalog.BTRIM(
                COALESCE(p_manifest_checksum, '')
            ),
            ''
        ),
        pg_catalog.NOW(),
        pg_catalog.NOW()
            + pg_catalog.MAKE_INTERVAL(secs => lease_seconds),
        NULL,
        NULL,
        NULL,
        NULL,
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET endpoint = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.endpoint
            ELSE EXCLUDED.endpoint
        END,
        status = CASE
            WHEN existing_job.status = 'complete'
                THEN 'complete'
            ELSE 'processing'
        END,
        stage = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.stage
            ELSE 'request_received'
        END,
        attempt_count = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.attempt_count
            ELSE existing_job.attempt_count + 1
        END,
        media_counts = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.media_counts
            ELSE EXCLUDED.media_counts
        END,
        media_object_keys = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.media_object_keys
            ELSE EXCLUDED.media_object_keys
        END,
        upload_session_ids = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.upload_session_ids
            ELSE EXCLUDED.upload_session_ids
        END,
        manifest_checksum = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.manifest_checksum
            ELSE COALESCE(
                EXCLUDED.manifest_checksum,
                existing_job.manifest_checksum
            )
        END,
        locked_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.locked_at
            ELSE EXCLUDED.locked_at
        END,
        lock_expires_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.lock_expires_at
            ELSE EXCLUDED.lock_expires_at
        END,
        retry_after = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.retry_after
            ELSE NULL
        END,
        last_error = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.last_error
            ELSE NULL
        END,
        terminal_reason_code = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.terminal_reason_code
            ELSE NULL
        END,
        completed_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.completed_at
            ELSE NULL
        END,
        updated_at = pg_catalog.NOW()
    RETURNING existing_job.* INTO STRICT claimed;

    RETURN claimed;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    TEXT,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    TEXT,
    INTEGER
) TO service_role;

CREATE OR REPLACE FUNCTION public.begin_scan_ingestion(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_request_payload JSONB,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_storage_keys TEXT[] DEFAULT '{}'::TEXT[],
    p_manifest_checksum TEXT DEFAULT NULL,
    p_payload_checksum TEXT DEFAULT NULL,
    p_resumable BOOLEAN DEFAULT TRUE,
    p_inline_media_redacted BOOLEAN DEFAULT FALSE,
    p_redacted_media_counts JSONB DEFAULT '{}'::JSONB,
    p_payload_schema_version INTEGER DEFAULT 1,
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    resolved_upload_session_ids UUID[] := '{}'::UUID[];
    lease_seconds INTEGER := LEAST(
        GREATEST(
            COALESCE(p_lease_seconds, 300),
            30
        ),
        3600
    );
    scan_id_uuid UUID;
    manifest_payload JSONB;
    resolved_manifest_checksum TEXT;
    resolved_payload_checksum TEXT;
    stored_payload JSONB;
    ledger_status TEXT;
    ledger_stage TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF COALESCE(pg_catalog.BTRIM(p_scan_id), '')
        !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_ingestion_identity'
            USING ERRCODE = '22023';
    END IF;
    scan_id_uuid := p_scan_id::UUID;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || scan_id_uuid::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = scan_id_uuid
    ) THEN
        RAISE EXCEPTION 'scan_generation_deleted'
            USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(
        pg_catalog.ARRAY_AGG(
            DISTINCT asset.upload_session_id
            ORDER BY asset.upload_session_id
        ),
        '{}'::UUID[]
    )
    INTO resolved_upload_session_ids
    FROM public.scan_media_assets AS asset
    WHERE asset.user_id = p_user_id
      AND asset.client_scan_id = scan_id_uuid
      AND asset.source = 'capture_upload'
      AND asset.storage_key = ANY(
          COALESCE(p_storage_keys, '{}'::TEXT[])
      );

    manifest_payload := pg_catalog.JSONB_BUILD_OBJECT(
        'mediaCounts',
        COALESCE(p_media_counts, '{}'::JSONB),
        'mediaObjectKeys',
        COALESCE(p_media_object_keys, '{}'::JSONB),
        'uploadSessionIds',
        pg_catalog.TO_JSONB(resolved_upload_session_ids)
    );
    resolved_manifest_checksum := pg_catalog.ENCODE(
        pg_catalog.SHA256(
            pg_catalog.CONVERT_TO(manifest_payload::TEXT, 'UTF8')
        ),
        'hex'
    );

    stored_payload := pg_catalog.JSONB_SET(
        pg_catalog.JSONB_SET(
            COALESCE(p_request_payload, '{}'::JSONB),
            '{uploadSessionIds}',
            pg_catalog.TO_JSONB(resolved_upload_session_ids),
            TRUE
        ),
        '{manifestChecksum}',
        pg_catalog.TO_JSONB(resolved_manifest_checksum),
        TRUE
    );
    resolved_payload_checksum := pg_catalog.ENCODE(
        pg_catalog.SHA256(
            pg_catalog.CONVERT_TO(stored_payload::TEXT, 'UTF8')
        ),
        'hex'
    );

    INSERT INTO public.scan_ingestion_jobs AS existing_job (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        attempt_count,
        media_counts,
        media_object_keys,
        upload_session_ids,
        manifest_checksum,
        locked_at,
        lock_expires_at,
        retry_after,
        last_error,
        terminal_reason_code,
        completed_at,
        updated_at
    )
    VALUES (
        scan_id_uuid::TEXT,
        p_user_id,
        COALESCE(
            NULLIF(pg_catalog.BTRIM(p_endpoint), ''),
            'identify-multimodal'
        ),
        'processing',
        'ai_inference_started',
        1,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        resolved_upload_session_ids,
        resolved_manifest_checksum,
        pg_catalog.NOW(),
        pg_catalog.NOW()
            + pg_catalog.MAKE_INTERVAL(secs => lease_seconds),
        NULL,
        NULL,
        NULL,
        NULL,
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET endpoint = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.endpoint
            ELSE EXCLUDED.endpoint
        END,
        status = CASE
            WHEN existing_job.status = 'complete'
                THEN 'complete'
            ELSE 'processing'
        END,
        stage = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.stage
            ELSE 'ai_inference_started'
        END,
        attempt_count = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.attempt_count
            ELSE existing_job.attempt_count + 1
        END,
        media_counts = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.media_counts
            ELSE EXCLUDED.media_counts
        END,
        media_object_keys = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.media_object_keys
            ELSE EXCLUDED.media_object_keys
        END,
        upload_session_ids = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.upload_session_ids
            ELSE EXCLUDED.upload_session_ids
        END,
        manifest_checksum = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.manifest_checksum
            ELSE COALESCE(
                EXCLUDED.manifest_checksum,
                existing_job.manifest_checksum
            )
        END,
        locked_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.locked_at
            ELSE EXCLUDED.locked_at
        END,
        lock_expires_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.lock_expires_at
            ELSE EXCLUDED.lock_expires_at
        END,
        retry_after = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.retry_after
            ELSE NULL
        END,
        last_error = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.last_error
            ELSE NULL
        END,
        terminal_reason_code = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.terminal_reason_code
            ELSE NULL
        END,
        completed_at = CASE
            WHEN existing_job.status = 'complete'
                THEN existing_job.completed_at
            ELSE NULL
        END,
        updated_at = pg_catalog.NOW()
    RETURNING existing_job.status, existing_job.stage
    INTO STRICT ledger_status, ledger_stage;

    IF ledger_status = 'complete' THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'upload_session_ids',
            pg_catalog.TO_JSONB(resolved_upload_session_ids),
            'manifest_checksum',
            resolved_manifest_checksum,
            'payload_checksum',
            resolved_payload_checksum,
            'stage',
            ledger_stage,
            'already_complete',
            TRUE
        );
    END IF;

    INSERT INTO public.scan_ingestion_intents AS existing_intent (
        scan_id,
        user_id,
        endpoint,
        payload_schema_version,
        request_payload,
        media_counts,
        media_object_keys,
        upload_session_ids,
        manifest_checksum,
        payload_checksum,
        resumable,
        inline_media_redacted,
        redacted_media_counts,
        claimed_at,
        updated_at
    )
    VALUES (
        scan_id_uuid::TEXT,
        p_user_id,
        COALESCE(
            NULLIF(pg_catalog.BTRIM(p_endpoint), ''),
            'identify-multimodal'
        ),
        GREATEST(
            COALESCE(p_payload_schema_version, 1),
            1
        ),
        stored_payload,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        resolved_upload_session_ids,
        resolved_manifest_checksum,
        resolved_payload_checksum,
        COALESCE(p_resumable, TRUE),
        COALESCE(p_inline_media_redacted, FALSE),
        COALESCE(p_redacted_media_counts, '{}'::JSONB),
        pg_catalog.NOW(),
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET endpoint = EXCLUDED.endpoint,
        payload_schema_version = EXCLUDED.payload_schema_version,
        request_payload = EXCLUDED.request_payload,
        media_counts = EXCLUDED.media_counts,
        media_object_keys = EXCLUDED.media_object_keys,
        upload_session_ids = EXCLUDED.upload_session_ids,
        manifest_checksum = COALESCE(
            EXCLUDED.manifest_checksum,
            existing_intent.manifest_checksum
        ),
        payload_checksum = COALESCE(
            EXCLUDED.payload_checksum,
            existing_intent.payload_checksum
        ),
        resumable = EXCLUDED.resumable,
        inline_media_redacted = EXCLUDED.inline_media_redacted,
        redacted_media_counts = EXCLUDED.redacted_media_counts,
        claimed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW();

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'upload_session_ids',
        pg_catalog.TO_JSONB(resolved_upload_session_ids),
        'manifest_checksum',
        resolved_manifest_checksum,
        'payload_checksum',
        resolved_payload_checksum,
        'stage',
        ledger_stage,
        'already_complete',
        FALSE
    );
END;
$$;

REVOKE ALL ON FUNCTION public.begin_scan_ingestion(
    TEXT, UUID, TEXT, JSONB, JSONB, JSONB, TEXT[], TEXT, TEXT,
    BOOLEAN, BOOLEAN, JSONB, INTEGER, INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.begin_scan_ingestion(
    TEXT, UUID, TEXT, JSONB, JSONB, JSONB, TEXT[], TEXT, TEXT,
    BOOLEAN, BOOLEAN, JSONB, INTEGER, INTEGER
) TO service_role;

CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan(
    p_scan_id UUID,
    p_user_id UUID,
    p_recovery_scan JSONB
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    recovered RECORD;
    ingestion_job RECORD;
    inserted_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_recovery_scan) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_recovery_scan::TEXT) > 65536 THEN
        RAISE EXCEPTION 'invalid_scan_recovery'
            USING ERRCODE = '22023';
    END IF;

    SELECT payload.*
    INTO STRICT recovered
    FROM pg_catalog.JSONB_TO_RECORD(p_recovery_scan) AS payload(
        id UUID,
        user_id UUID,
        species_id UUID,
        confirmed_species_id UUID,
        image_storage_urls TEXT[],
        "timestamp" TIMESTAMPTZ,
        gps_lat_exact DOUBLE PRECISION,
        gps_long_exact DOUBLE PRECISION,
        gps_elevation DOUBLE PRECISION,
        geoprivacy TEXT,
        weather_condition TEXT,
        weather_temperature_f DOUBLE PRECISION,
        ai_confidence_score DOUBLE PRECISION,
        ecology_type TEXT,
        is_invasive BOOLEAN,
        invasive_status_region TEXT,
        invasive_rationale TEXT,
        invasive_confidence DOUBLE PRECISION,
        is_live_capture BOOLEAN,
        is_biological_subject BOOLEAN,
        ai_reasoning TEXT,
        semantic_location TEXT,
        public_location_label TEXT,
        inference_tier TEXT,
        image_quality_score INTEGER,
        user_identification_override TEXT,
        user_confirmed_identification BOOLEAN,
        user_review_state TEXT
    );

    IF recovered.id IS DISTINCT FROM p_scan_id
       OR recovered.user_id IS DISTINCT FROM p_user_id
       OR recovered.image_storage_urls IS DISTINCT FROM '{}'::TEXT[]
       OR recovered."timestamp" IS NULL
       OR recovered.geoprivacy IS NULL
       OR recovered.geoprivacy NOT IN ('open', 'obscured', 'private')
       OR recovered.ecology_type IS NULL
       OR recovered.ecology_type NOT IN (
            'wild',
            'urban',
            'domesticated',
            'unknown'
       )
       OR recovered.user_review_state IS NULL
       OR recovered.user_review_state NOT IN (
            'unreviewed',
            'ai_confirmed',
            'user_overridden'
       )
       OR recovered.ai_confidence_score IS NULL
       OR recovered.ai_confidence_score NOT BETWEEN 0 AND 1
       OR recovered.is_invasive IS NULL
       OR recovered.is_live_capture IS NULL
       OR recovered.is_biological_subject IS NULL
       OR recovered.user_confirmed_identification IS NULL
       OR (
            recovered.gps_lat_exact IS NULL
            AND recovered.gps_long_exact IS NOT NULL
       )
       OR (
            recovered.gps_lat_exact IS NOT NULL
            AND recovered.gps_long_exact IS NULL
       )
       OR recovered.gps_lat_exact NOT BETWEEN -90 AND 90
       OR recovered.gps_long_exact NOT BETWEEN -180 AND 180
       OR recovered.gps_elevation NOT BETWEEN -500 AND 9500
       OR recovered.weather_temperature_f NOT BETWEEN -200 AND 200
       OR recovered.invasive_confidence NOT BETWEEN 0 AND 1
       OR recovered.image_quality_score NOT BETWEEN 0 AND 100
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.inference_tier, '')
       ) NOT BETWEEN 1 AND 64
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.weather_condition, '')
       ) > 200
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.invasive_status_region, '')
       ) > 500
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.invasive_rationale, '')
       ) > 2000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.ai_reasoning, '')
       ) > 10000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.semantic_location, '')
       ) > 1000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.public_location_label, '')
       ) > 500
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(
                recovered.user_identification_override,
                ''
            )
       ) > 500 THEN
        RAISE EXCEPTION 'invalid_scan_recovery'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id
    ) THEN
        RETURN 'deleted';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
    ) THEN
        RETURN 'already_present';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id IS DISTINCT FROM p_user_id
    ) THEN
        RETURN 'id_collision';
    END IF;

    SELECT jobs.status, jobs.terminal_reason_code
    INTO ingestion_job
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'deferred';
    END IF;
    IF ingestion_job.status <> 'complete'
       AND NOT (
           ingestion_job.status = 'failed_terminal'
           AND ingestion_job.terminal_reason_code = 'replay_exhausted'
       ) THEN
        RETURN 'deferred';
    END IF;

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        confirmed_species_id,
        image_storage_urls,
        "timestamp",
        gps_lat_exact,
        gps_long_exact,
        gps_lat_public,
        gps_long_public,
        gps_elevation,
        geoprivacy,
        weather_condition,
        weather_temperature_f,
        ai_confidence_score,
        ecology_type,
        is_invasive,
        invasive_status_region,
        invasive_rationale,
        invasive_confidence,
        is_live_capture,
        is_biological_subject,
        ai_reasoning,
        semantic_location,
        public_location_label,
        inference_tier,
        image_quality_score,
        user_identification_override,
        user_confirmed_identification,
        user_review_state
    )
    VALUES (
        recovered.id,
        recovered.user_id,
        recovered.species_id,
        recovered.confirmed_species_id,
        '{}'::TEXT[],
        recovered."timestamp",
        recovered.gps_lat_exact,
        recovered.gps_long_exact,
        CASE
            WHEN recovered.geoprivacy = 'open'
                THEN recovered.gps_lat_exact
            ELSE NULL
        END,
        CASE
            WHEN recovered.geoprivacy = 'open'
                THEN recovered.gps_long_exact
            ELSE NULL
        END,
        recovered.gps_elevation,
        recovered.geoprivacy::public.geoprivacy_enum,
        recovered.weather_condition,
        recovered.weather_temperature_f,
        recovered.ai_confidence_score,
        recovered.ecology_type::public.ecology_type_enum,
        recovered.is_invasive,
        recovered.invasive_status_region,
        recovered.invasive_rationale,
        recovered.invasive_confidence,
        recovered.is_live_capture,
        recovered.is_biological_subject,
        recovered.ai_reasoning,
        recovered.semantic_location,
        CASE
            WHEN recovered.geoprivacy = 'private' THEN NULL
            ELSE recovered.public_location_label
        END,
        recovered.inference_tier,
        recovered.image_quality_score,
        recovered.user_identification_override,
        recovered.user_confirmed_identification,
        recovered.user_review_state::public.user_review_state
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id INTO inserted_id;

    IF inserted_id IS NULL THEN
        RETURN 'id_collision';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.scan_ingestion_completion_fence',
        p_user_id::TEXT || ':' || p_scan_id::TEXT,
        TRUE
    );

    INSERT INTO public.scan_ingestion_jobs AS existing_job (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        attempt_count,
        media_counts,
        media_object_keys,
        upload_session_ids,
        locked_at,
        lock_expires_at,
        retry_after,
        last_error,
        terminal_reason_code,
        completed_at,
        updated_at
    )
    VALUES (
        p_scan_id::TEXT,
        p_user_id,
        'client-recovery',
        'complete',
        'client_recovery_complete',
        0,
        '{}'::JSONB,
        '{}'::JSONB,
        '{}'::UUID[],
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        pg_catalog.NOW(),
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET status = 'complete',
        stage = 'client_recovery_complete',
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = NULL,
        last_error = NULL,
        terminal_reason_code = NULL,
        completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW();

    RETURN 'recovered';
END;
$$;

REVOKE ALL ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_missing_owned_scan(
    UUID,
    UUID,
    JSONB
) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_scan_ingestion_finalization(
    p_scan_id UUID,
    p_user_id UUID,
    p_promoted_urls_by_storage_key JSONB DEFAULT '{}'::JSONB,
    p_deleted_storage_keys TEXT[] DEFAULT '{}'::TEXT[]
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    job_status TEXT;
    job_media_object_keys JSONB;
    scan_owner UUID;
    affected_rows INTEGER;
    expected_promotions INTEGER;
    expected_deletions INTEGER;
    expected_storage_keys INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR pg_catalog.JSONB_TYPEOF(
            COALESCE(
                p_promoted_urls_by_storage_key,
                '{}'::JSONB
            )
       ) <> 'object'
       OR pg_catalog.CARDINALITY(
            COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
       ) > 128 THEN
        RAISE EXCEPTION 'invalid_scan_finalization'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO STRICT expected_promotions
    FROM pg_catalog.JSONB_OBJECT_KEYS(
        COALESCE(
            p_promoted_urls_by_storage_key,
            '{}'::JSONB
        )
    ) AS keys(storage_key);

    SELECT pg_catalog.COUNT(DISTINCT deleted.storage_key)::INTEGER
    INTO STRICT expected_deletions
    FROM pg_catalog.UNNEST(
        COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
    ) AS deleted(storage_key);

    IF expected_promotions > 128
       OR expected_deletions > 128
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.JSONB_OBJECT_KEYS(
                COALESCE(
                    p_promoted_urls_by_storage_key,
                    '{}'::JSONB
                )
            ) AS promoted(storage_key)
            WHERE promoted.storage_key = ANY(
                COALESCE(
                    p_deleted_storage_keys,
                    '{}'::TEXT[]
                )
            )
       ) THEN
        RAISE EXCEPTION 'invalid_scan_finalization'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.JSONB_EACH_TEXT(
            COALESCE(
                p_promoted_urls_by_storage_key,
                '{}'::JSONB
            )
        ) AS promoted(storage_key, public_url)
        WHERE pg_catalog.CHAR_LENGTH(promoted.storage_key)
                NOT BETWEEN 1 AND 512
           OR promoted.storage_key !~ '^staging/'
           OR pg_catalog.CHAR_LENGTH(promoted.public_url)
                NOT BETWEEN 1 AND 2048
           OR promoted.public_url !~ '^https://media[.]merian[.]app/'
    ) OR EXISTS (
        SELECT 1
        FROM pg_catalog.UNNEST(
            COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
        ) AS deleted(storage_key)
        WHERE pg_catalog.CHAR_LENGTH(deleted.storage_key)
                NOT BETWEEN 1 AND 512
           OR deleted.storage_key !~ '^staging/'
    ) THEN
        RAISE EXCEPTION 'invalid_scan_finalization'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id
    ) THEN
        RETURN 'deleted';
    END IF;

    SELECT jobs.status, jobs.media_object_keys
    INTO job_status, job_media_object_keys
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'job_not_found';
    END IF;
    IF job_status = 'complete' THEN
        RETURN 'already_complete';
    END IF;
    IF job_status = 'failed_terminal' THEN
        RETURN 'terminal';
    END IF;

    WITH expected AS (
        SELECT 'image'::TEXT AS kind, keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            COALESCE(
                job_media_object_keys -> 'image',
                '[]'::JSONB
            )
        ) AS keys(storage_key)
        UNION ALL
        SELECT 'video'::TEXT, keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            COALESCE(
                job_media_object_keys -> 'video',
                '[]'::JSONB
            )
        ) AS keys(storage_key)
        UNION ALL
        SELECT 'audio'::TEXT, keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            COALESCE(
                job_media_object_keys -> 'audio',
                '[]'::JSONB
            )
        ) AS keys(storage_key)
    )
    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO STRICT expected_storage_keys
    FROM expected;

    IF expected_storage_keys > 128
       OR (
            SELECT pg_catalog.COUNT(DISTINCT expected.storage_key)
            FROM (
                SELECT keys.storage_key
                FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                    COALESCE(
                        job_media_object_keys -> 'image',
                        '[]'::JSONB
                    )
                ) AS keys(storage_key)
                UNION ALL
                SELECT keys.storage_key
                FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                    COALESCE(
                        job_media_object_keys -> 'video',
                        '[]'::JSONB
                    )
                ) AS keys(storage_key)
                UNION ALL
                SELECT keys.storage_key
                FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                    COALESCE(
                        job_media_object_keys -> 'audio',
                        '[]'::JSONB
                    )
                ) AS keys(storage_key)
            ) AS expected
       ) <> expected_storage_keys
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.JSONB_OBJECT_KEYS(
                COALESCE(
                    p_promoted_urls_by_storage_key,
                    '{}'::JSONB
                )
            ) AS promoted(storage_key)
            WHERE NOT (
                COALESCE(
                    job_media_object_keys -> 'image',
                    '[]'::JSONB
                ) ? promoted.storage_key
                OR COALESCE(
                    job_media_object_keys -> 'video',
                    '[]'::JSONB
                ) ? promoted.storage_key
                OR COALESCE(
                    job_media_object_keys -> 'audio',
                    '[]'::JSONB
                ) ? promoted.storage_key
            )
       )
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(
                COALESCE(
                    p_deleted_storage_keys,
                    '{}'::TEXT[]
                )
            ) AS deleted(storage_key)
            WHERE NOT (
                COALESCE(
                    job_media_object_keys -> 'audio',
                    '[]'::JSONB
                ) ? deleted.storage_key
            )
       ) THEN
        RAISE EXCEPTION 'scan_media_manifest_invalid'
            USING ERRCODE = '55000';
    END IF;

    SELECT scans.user_id
    INTO scan_owner
    FROM public.scans AS scans
    WHERE scans.id = p_scan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'scan_not_found';
    END IF;
    IF scan_owner IS NULL THEN
        PERFORM pg_catalog.SET_CONFIG(
            'merian.scan_ingestion_completion_fence',
            p_user_id::TEXT || ':' || p_scan_id::TEXT,
            TRUE
        );

        UPDATE public.scan_ingestion_jobs AS jobs
        SET status = 'complete',
            stage = 'owner_tombstoned',
            locked_at = NULL,
            lock_expires_at = NULL,
            retry_after = NULL,
            last_error = NULL,
            terminal_reason_code = NULL,
            completed_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE jobs.scan_id = p_scan_id::TEXT
          AND jobs.user_id = p_user_id
          AND jobs.status <> 'complete';
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        IF affected_rows <> 1 THEN
            RAISE EXCEPTION 'scan_finalization_claim_lost'
                USING ERRCODE = '55000';
        END IF;
        RETURN 'completed';
    END IF;
    IF scan_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'scan_not_found';
    END IF;

    UPDATE public.scan_media_assets AS assets
    SET scan_id = p_scan_id,
        status = 'promoted',
        url = promoted.public_url,
        failure_reason = NULL,
        deleted_at = NULL,
        updated_at = pg_catalog.NOW()
    FROM pg_catalog.JSONB_EACH_TEXT(
        COALESCE(
            p_promoted_urls_by_storage_key,
            '{}'::JSONB
        )
    ) AS promoted(storage_key, public_url)
    WHERE assets.user_id = p_user_id
      AND assets.client_scan_id = p_scan_id
      AND assets.source = 'capture_upload'
      AND assets.status IN ('staged', 'promoted')
      AND assets.storage_key = promoted.storage_key;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;

    IF affected_rows <> expected_promotions THEN
        RAISE EXCEPTION 'scan_media_promotion_incomplete'
            USING ERRCODE = '55000';
    END IF;

    UPDATE public.scan_media_assets AS assets
    SET scan_id = p_scan_id,
        status = 'deleted',
        failure_reason = NULL,
        deleted_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE assets.user_id = p_user_id
      AND assets.client_scan_id = p_scan_id
      AND assets.source = 'capture_upload'
      AND assets.status IN ('staged', 'deleted')
      AND assets.storage_key = ANY(
          COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
      );
    GET DIAGNOSTICS affected_rows = ROW_COUNT;

    IF affected_rows <> expected_deletions THEN
        RAISE EXCEPTION 'scan_media_deletion_incomplete'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        WITH expected AS (
            SELECT 'image'::TEXT AS kind, keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                COALESCE(
                    job_media_object_keys -> 'image',
                    '[]'::JSONB
                )
            ) AS keys(storage_key)
            UNION ALL
            SELECT 'video'::TEXT, keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                COALESCE(
                    job_media_object_keys -> 'video',
                    '[]'::JSONB
                )
            ) AS keys(storage_key)
            UNION ALL
            SELECT 'audio'::TEXT, keys.storage_key
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                COALESCE(
                    job_media_object_keys -> 'audio',
                    '[]'::JSONB
                )
            ) AS keys(storage_key)
        )
        SELECT 1
        FROM expected
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.scan_media_assets AS assets
            WHERE assets.user_id = p_user_id
              AND assets.client_scan_id = p_scan_id
              AND assets.source = 'capture_upload'
              AND assets.storage_key = expected.storage_key
              AND assets.kind = expected.kind
              AND (
                  assets.status = 'promoted'
                  OR (
                      expected.kind = 'audio'
                      AND assets.status = 'deleted'
                  )
              )
        )
    ) THEN
        RAISE EXCEPTION 'scan_media_manifest_incomplete'
            USING ERRCODE = '55000';
    END IF;

    PERFORM public.refresh_scan_media_assets(p_scan_id);

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.image_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'image'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.video_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'video'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.audio_storage_urls, '{}'::TEXT[])
        ) AS expected(url)
        WHERE scans.id = p_scan_id
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS assets
              WHERE assets.scan_id = p_scan_id
                AND assets.kind = 'audio'
                AND assets.status = 'ready'
                AND assets.url = expected.url
          )
    ) THEN
        RAISE EXCEPTION 'canonical_scan_media_incomplete'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS captured
        WHERE captured.user_id = p_user_id
          AND captured.client_scan_id = p_scan_id
          AND captured.source = 'capture_upload'
          AND captured.status = 'promoted'
          AND (
              COALESCE(
                  job_media_object_keys -> 'image',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'video',
                  '[]'::JSONB
              ) ? captured.storage_key
              OR COALESCE(
                  job_media_object_keys -> 'audio',
                  '[]'::JSONB
              ) ? captured.storage_key
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.scan_media_assets AS canonical
              WHERE canonical.scan_id = p_scan_id
                AND canonical.kind = captured.kind
                AND canonical.status = 'ready'
                AND canonical.url = captured.url
          )
    ) THEN
        RAISE EXCEPTION 'canonical_scan_media_manifest_incomplete'
            USING ERRCODE = '55000';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.scan_ingestion_completion_fence',
        p_user_id::TEXT || ':' || p_scan_id::TEXT,
        TRUE
    );

    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'complete',
        stage = 'media_finalization_complete',
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = NULL,
        last_error = NULL,
        terminal_reason_code = NULL,
        completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status <> 'complete';
    GET DIAGNOSTICS affected_rows = ROW_COUNT;

    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'scan_finalization_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    RETURN 'completed';
END;
$$;

REVOKE ALL ON FUNCTION public.complete_scan_ingestion_finalization(
    UUID,
    UUID,
    JSONB,
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_scan_ingestion_finalization(
    UUID,
    UUID,
    JSONB,
    TEXT[]
) TO service_role;

-- Completion is a database invariant, not an Edge convention. Even a stale
-- rolling-deployment isolate with service-key table authority must not mark a
-- ledger complete without passing the transactional media finalizer (or the
-- atomic no-media recovery path). The transaction-local fence is bound to the
-- exact owner and normalized scan UUID, so it cannot authorize another row.
CREATE OR REPLACE FUNCTION internal.enforce_scan_ingestion_completion_fence()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    expected_fence TEXT;
    active_fence TEXT;
    reparenting_enabled BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status = 'complete' THEN
        IF NEW.status <> 'complete'
           OR NEW.scan_id IS DISTINCT FROM OLD.scan_id THEN
            RAISE EXCEPTION 'scan_ingestion_completed_generation_immutable'
                USING ERRCODE = '55000';
        END IF;

        -- The atomic ghost-profile merge is the only legitimate completed-row
        -- owner transition. Its privileged transaction already publishes the
        -- exact source and target identities for the catalog-driven FK pass.
        -- Bind this exception to all three markers so a generic service-key
        -- update cannot reassign historical ingestion evidence.
        IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
            reparenting_enabled :=
                pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparenting',
                    TRUE
                ) = 'on'
                AND pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparent_source',
                    TRUE
                ) = OLD.user_id::TEXT
                AND pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparent_target',
                    TRUE
                ) = NEW.user_id::TEXT;
            IF NOT COALESCE(reparenting_enabled, FALSE) THEN
                RAISE EXCEPTION
                    'scan_ingestion_completed_generation_immutable'
                    USING ERRCODE = '55000';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.status <> 'complete' THEN
        RETURN NEW;
    END IF;

    expected_fence := NEW.user_id::TEXT || ':' || (NEW.scan_id::UUID)::TEXT;
    active_fence := pg_catalog.CURRENT_SETTING(
        'merian.scan_ingestion_completion_fence',
        TRUE
    );
    IF active_fence IS DISTINCT FROM expected_fence THEN
        RAISE EXCEPTION 'scan_ingestion_completion_requires_finalization'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
EXCEPTION
    WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'scan_ingestion_completion_requires_finalization'
            USING ERRCODE = '55000';
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_scan_ingestion_completion_fence()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enforce_scan_ingestion_completion_fence
    ON public.scan_ingestion_jobs;
CREATE TRIGGER enforce_scan_ingestion_completion_fence
BEFORE INSERT OR UPDATE OF status, scan_id, user_id
ON public.scan_ingestion_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_scan_ingestion_completion_fence();

-- ---------------------------------------------------------------------------
-- State-validating DwC-A downloads and durable archive deletion
-- ---------------------------------------------------------------------------

CREATE TABLE internal.export_download_grants (
    job_id UUID PRIMARY KEY
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    token_sha256 TEXT NOT NULL UNIQUE
        CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,
    cleaned_at TIMESTAMPTZ,
    CHECK (
        expires_at > created_at
        AND expires_at <= created_at + INTERVAL '2 days'
    ),
    CHECK (
        (
            revoked_at IS NULL
            AND revocation_reason IS NULL
        )
        OR (
            revoked_at IS NOT NULL
            AND revocation_reason ~ '^[a-z][a-z0-9_]{1,63}$'
        )
    ),
    CHECK (cleaned_at IS NULL OR cleaned_at >= created_at)
);

CREATE INDEX export_download_grants_due_idx
    ON internal.export_download_grants (expires_at, job_id)
    WHERE cleaned_at IS NULL;

CREATE INDEX export_download_grants_revoked_due_idx
    ON internal.export_download_grants (revoked_at, job_id)
    WHERE cleaned_at IS NULL
      AND revoked_at IS NOT NULL;

CREATE INDEX export_job_source_state_invalidated_cleanup_idx
    ON internal.export_job_source_state (invalidated_at, job_id)
    WHERE invalidated_at IS NOT NULL
      AND purged_at IS NULL;

ALTER TABLE internal.export_download_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.export_download_grants
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.export_download_grants IS
    'Private hashes for opaque DwC-A download capabilities. Authorization revalidates the complete source fence before issuing a short-lived R2 redirect.';

CREATE TABLE internal.export_archive_cleanup_jobs (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    job_id UUID REFERENCES public.export_jobs(id) ON DELETE SET NULL,
    object_key TEXT NOT NULL UNIQUE
        CHECK (
            pg_catalog.CHAR_LENGTH(object_key) BETWEEN 1 AND 512
            AND object_key ~ '^exports/'
            AND object_key !~ '/work/'
            AND object_key NOT LIKE '%..%'
            AND object_key !~ '[[:cntrl:]]'
        ),
    reason_code TEXT NOT NULL
        CHECK (reason_code ~ '^[a-z][a-z0-9_]{1,63}$'),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed')),
    attempt_count INTEGER NOT NULL DEFAULT 0
        CHECK (attempt_count BETWEEN 0 AND 1000000),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    claim_token UUID,
    lease_expires_at TIMESTAMPTZ,
    last_error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    completed_at TIMESTAMPTZ,
    CHECK (
        last_error_code IS NULL
        OR last_error_code ~ '^[a-z][a-z0-9_]{1,63}$'
    ),
    CHECK (
        (
            status = 'processing'
            AND claim_token IS NOT NULL
            AND lease_expires_at IS NOT NULL
        )
        OR (
            status <> 'processing'
            AND claim_token IS NULL
            AND lease_expires_at IS NULL
        )
    ),
    CHECK (
        (
            status = 'completed'
            AND completed_at IS NOT NULL
        )
        OR (
            status <> 'completed'
            AND completed_at IS NULL
        )
    )
);

CREATE INDEX export_archive_cleanup_due_idx
    ON internal.export_archive_cleanup_jobs (
        next_attempt_at,
        created_at,
        id
    )
    WHERE status = 'pending';

CREATE INDEX export_archive_cleanup_expired_lease_idx
    ON internal.export_archive_cleanup_jobs (lease_expires_at, id)
    WHERE status = 'processing';

ALTER TABLE internal.export_archive_cleanup_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.export_archive_cleanup_jobs
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.export_archive_cleanup_jobs IS
    'Durable retrying outbox for private DwC-A archive deletion. Storage outages never weaken source-revocation terminality.';

CREATE TABLE internal.export_download_rate_windows (
    ip_hash TEXT NOT NULL
        CHECK (ip_hash ~ '^[0-9a-f]{64}$'),
    window_started_at TIMESTAMPTZ NOT NULL,
    request_count INTEGER NOT NULL
        CHECK (request_count BETWEEN 1 AND 1000000),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (ip_hash, window_started_at)
);

CREATE INDEX export_download_rate_windows_expiry_idx
    ON internal.export_download_rate_windows (window_started_at);

ALTER TABLE internal.export_download_rate_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.export_download_rate_windows
    FROM PUBLIC, anon, authenticated, service_role;

-- Every runtime transition that combines an export job with its source
-- snapshot, grant, or cleanup outbox takes the parent row lock first and this
-- transaction-scoped generation lock second. The parent-first order matches
-- DELETE/UPDATE row locking, while the advisory lock serializes the otherwise
-- conflicting source -> grant -> outbox and outbox -> grant -> source paths.
-- This prevents privacy updates, delivery completion, and stale cleanup
-- workers from deadlocking or crossing generations.
CREATE OR REPLACE FUNCTION internal.lock_dwca_export_generation(
    p_job_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    IF p_job_id IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM 1
    FROM public.export_jobs AS jobs
    WHERE jobs.id = p_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-dwca-export:' || p_job_id::TEXT,
            0::BIGINT
        )
    );
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION internal.lock_dwca_export_generation(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.enqueue_dwca_archive_cleanup(
    p_job_id UUID,
    p_object_key TEXT,
    p_reason_code TEXT
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    cleanup_id UUID;
    owner_id UUID;
BEGIN
    IF p_job_id IS NULL
       OR p_object_key IS NULL
       OR p_reason_code IS NULL
       OR p_reason_code !~ '^[a-z][a-z0-9_]{1,63}$' THEN
        RAISE EXCEPTION 'invalid_dwca_archive_cleanup'
            USING ERRCODE = '22023';
    END IF;

    IF NOT internal.lock_dwca_export_generation(p_job_id) THEN
        RAISE EXCEPTION 'invalid_dwca_archive_cleanup'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.user_id
    INTO owner_id
    FROM public.export_jobs AS jobs
    WHERE jobs.id = p_job_id;

    IF owner_id IS NULL
       OR p_object_key !~ (
            '^exports/' || owner_id::TEXT || '/' || p_job_id::TEXT || '/'
       )
       OR p_object_key ~ '/work/'
       OR pg_catalog.CHAR_LENGTH(p_object_key) NOT BETWEEN 1 AND 512
       OR p_object_key LIKE '%..%'
       OR p_object_key ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'invalid_dwca_archive_cleanup'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO internal.export_archive_cleanup_jobs AS cleanup (
        job_id,
        object_key,
        reason_code,
        status,
        next_attempt_at,
        updated_at
    )
    VALUES (
        p_job_id,
        p_object_key,
        p_reason_code,
        'pending',
        pg_catalog.NOW(),
        pg_catalog.NOW()
    )
    ON CONFLICT (object_key) DO UPDATE
    SET reason_code = EXCLUDED.reason_code,
        status = CASE
            WHEN cleanup.status = 'completed' THEN 'completed'
            ELSE 'pending'
        END,
        next_attempt_at = CASE
            WHEN cleanup.status = 'completed'
                THEN cleanup.next_attempt_at
            ELSE LEAST(
                cleanup.next_attempt_at,
                pg_catalog.NOW()
            )
        END,
        claim_token = CASE
            WHEN cleanup.status = 'completed' THEN cleanup.claim_token
            ELSE NULL
        END,
        lease_expires_at = CASE
            WHEN cleanup.status = 'completed' THEN cleanup.lease_expires_at
            ELSE NULL
        END,
        updated_at = pg_catalog.NOW()
    RETURNING cleanup.id INTO STRICT cleanup_id;

    RETURN cleanup_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.enqueue_dwca_archive_cleanup(
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;

-- Replace the prior multi-table FOR SHARE query with the canonical
-- parent-first generation lock. Worker pre-assembly/pre-delivery checks now
-- follow the same order as staging, completion, privacy revocation, and
-- cleanup, eliminating the last source-state -> parent inversion.
CREATE OR REPLACE FUNCTION public.check_dwca_export_source_fence(
    p_job_id UUID,
    p_claim_token UUID,
    p_expected_phase TEXT
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_expected_phase IS NULL
       OR p_expected_phase NOT IN ('assembling', 'delivering') THEN
        RAISE EXCEPTION 'invalid_dwca_export_source_fence'
            USING ERRCODE = '22023';
    END IF;

    IF NOT internal.lock_dwca_export_generation(p_job_id) THEN
        RETURN 'claim_lost';
    END IF;

    PERFORM 1
    FROM internal.export_job_claims AS claims
    INNER JOIN internal.export_job_work AS work
        ON work.job_id = claims.job_id
    INNER JOIN internal.export_job_source_state AS source_state
        ON source_state.job_id = claims.job_id
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.phase = p_expected_phase
      AND source_state.purged_at IS NULL
    FOR SHARE OF claims, work, source_state;

    IF NOT FOUND THEN
        RETURN 'claim_lost';
    END IF;

    IF NOT internal.dwca_export_source_is_current(p_job_id) THEN
        RETURN 'source_snapshot_changed';
    END IF;

    RETURN 'current';
END;
$$;

REVOKE ALL ON FUNCTION public.check_dwca_export_source_fence(
    UUID,
    UUID,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_dwca_export_source_fence(
    UUID,
    UUID,
    TEXT
) TO service_role;

-- The earlier snapshot invalidation triggers intentionally covered only queued
-- work. Completed exports now retain their private source DTOs for the lifetime
-- of an opaque grant, so privacy changes must proactively revoke those grants
-- and enqueue their archives as part of the same database transaction. The
-- download endpoint still repeats the full live fence on every click. Row
-- events revoke and enqueue in the same transaction; TRUNCATE first persists
-- source invalidation without taking parent locks, then the independent
-- claimant performs parent-first revocation and enqueue after commit.
CREATE OR REPLACE FUNCTION internal.revoke_completed_dwca_exports_for_scan()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '30s'
AS $$
DECLARE
    target_scan_id UUID;
    revoke_all_scopes BOOLEAN := FALSE;
    revoke_global_scope BOOLEAN := FALSE;
    affected_job RECORD;
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        -- TRUNCATE already holds ACCESS EXCLUSIVE on the source table. Taking
        -- export-job row locks from this trigger would invert a worker that
        -- owns the parent generation and is waiting for source-table
        -- ACCESS SHARE. Persist authorization revocation only; click-time
        -- checks fail closed on invalidated_at, and the cleanup claimant later
        -- discovers these rows and acquires every parent in canonical order.
        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'scan_catalog_replaced'
            )
        WHERE source_state.purged_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM internal.export_job_source_rows AS source_rows
              WHERE source_rows.job_id = source_state.job_id
          );
        RETURN NULL;
    ELSIF TG_OP = 'DELETE' THEN
        target_scan_id := OLD.id;
        revoke_all_scopes := TRUE;
    ELSE
        target_scan_id := NEW.id;
        revoke_all_scopes :=
            NEW.user_id IS DISTINCT FROM OLD.user_id
            OR NEW.is_live_capture IS DISTINCT FROM OLD.is_live_capture
            OR NEW.is_tombstoned IS DISTINCT FROM OLD.is_tombstoned
            OR NEW.ecology_type IS DISTINCT FROM OLD.ecology_type
            OR NEW.species_id IS DISTINCT FROM OLD.species_id
            OR NEW.confirmed_species_id
                IS DISTINCT FROM OLD.confirmed_species_id;
        revoke_global_scope := revoke_all_scopes
            OR NEW.geoprivacy IS DISTINCT FROM OLD.geoprivacy;
    END IF;

    IF NOT revoke_all_scopes AND NOT revoke_global_scope THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    -- Do not filter on the job status. A privacy statement can begin while a
    -- delivery transaction is still processing and resume after that worker
    -- has committed completion. Monotonically invalidating every unpurged
    -- source state, and revoking any grant that already exists, closes that
    -- statement-snapshot race.
    FOR affected_job IN
        SELECT DISTINCT
            jobs.id AS job_id,
            jobs.archive_object_key
        FROM public.export_jobs AS jobs
        INNER JOIN internal.export_job_source_state AS source_state
            ON source_state.job_id = jobs.id
        INNER JOIN internal.export_job_source_rows AS source_rows
            ON source_rows.job_id = jobs.id
        WHERE source_state.purged_at IS NULL
          AND (
              source_rows.scan_id = target_scan_id
          )
          AND (
              revoke_all_scopes
              OR jobs.export_scope = 'global'
          )
        ORDER BY jobs.id
    LOOP
        IF NOT internal.lock_dwca_export_generation(
            affected_job.job_id
        ) THEN
            CONTINUE;
        END IF;

        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'scan_eligibility_changed'
            )
        WHERE source_state.job_id = affected_job.job_id
          AND source_state.purged_at IS NULL;

        UPDATE internal.export_download_grants AS grants
        SET revoked_at = COALESCE(
                grants.revoked_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            revocation_reason = COALESCE(
                grants.revocation_reason,
                'source_snapshot_changed'
            )
        WHERE grants.job_id = affected_job.job_id
          AND grants.cleaned_at IS NULL;

        IF affected_job.archive_object_key IS NOT NULL THEN
            PERFORM internal.enqueue_dwca_archive_cleanup(
                affected_job.job_id,
                affected_job.archive_object_key,
                'source_snapshot_changed'
            );
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.revoke_completed_dwca_exports_for_scan()
    FROM PUBLIC, anon, authenticated, service_role;

-- Retire the preceding source-state-first invalidation triggers before
-- installing the parent-first generation-fenced replacement. Leaving both
-- active would allow the older trigger to lock source state before the new
-- trigger requests the export-job row, inverting delivery's lock order.
DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan
    ON public.scans;
DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan_truncate
    ON public.scans;

DROP TRIGGER IF EXISTS revoke_completed_dwca_exports_for_scan
    ON public.scans;
CREATE TRIGGER revoke_completed_dwca_exports_for_scan
AFTER DELETE OR UPDATE OF
    user_id,
    is_live_capture,
    is_tombstoned,
    ecology_type,
    geoprivacy,
    species_id,
    confirmed_species_id
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION internal.revoke_completed_dwca_exports_for_scan();

DROP TRIGGER IF EXISTS revoke_completed_dwca_exports_for_scan_truncate
    ON public.scans;
CREATE TRIGGER revoke_completed_dwca_exports_for_scan_truncate
AFTER TRUNCATE ON public.scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.revoke_completed_dwca_exports_for_scan();

CREATE OR REPLACE FUNCTION internal.revoke_completed_dwca_exports_for_species()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '30s'
AS $$
DECLARE
    target_species_id UUID;
    protection_required BOOLEAN;
    affected_job RECORD;
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        -- Use the same lock-safe truncation protocol as the scan trigger:
        -- source invalidation is immediate and monotonic, while the cleanup
        -- claimant performs parent-first grant revocation and archive enqueue.
        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'species_catalog_replaced'
            )
        WHERE source_state.purged_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM internal.export_job_source_rows AS source_rows
              WHERE source_rows.job_id = source_state.job_id
                AND source_rows.effective_species_id IS NOT NULL
          );
        RETURN NULL;
    ELSIF TG_OP = 'DELETE' THEN
        target_species_id := OLD.id;
        protection_required := NULL;
    ELSE
        target_species_id := NEW.id;
        protection_required := COALESCE(
            NEW.iucn_red_list_status IN (
                'vulnerable',
                'endangered',
                'critically_endangered',
                'near_threatened'
            ),
            FALSE
        );
    END IF;

    -- As above, fence every unpurged snapshot rather than trusting a
    -- snapshot-visible job status during a concurrent delivery transition.
    FOR affected_job IN
        SELECT DISTINCT
            jobs.id AS job_id,
            jobs.archive_object_key
        FROM public.export_jobs AS jobs
        INNER JOIN internal.export_job_source_state AS source_state
            ON source_state.job_id = jobs.id
        INNER JOIN internal.export_job_source_rows AS source_rows
            ON source_rows.job_id = jobs.id
        WHERE source_state.purged_at IS NULL
          AND (
              source_rows.effective_species_id = target_species_id
              AND (
                  TG_OP = 'DELETE'
                  OR source_rows.coordinate_protection_required
                      IS DISTINCT FROM protection_required
              )
          )
        ORDER BY jobs.id
    LOOP
        IF NOT internal.lock_dwca_export_generation(
            affected_job.job_id
        ) THEN
            CONTINUE;
        END IF;

        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'species_protection_changed'
            )
        WHERE source_state.job_id = affected_job.job_id
          AND source_state.purged_at IS NULL;

        UPDATE internal.export_download_grants AS grants
        SET revoked_at = COALESCE(
                grants.revoked_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            revocation_reason = COALESCE(
                grants.revocation_reason,
                'source_snapshot_changed'
            )
        WHERE grants.job_id = affected_job.job_id
          AND grants.cleaned_at IS NULL;

        IF affected_job.archive_object_key IS NOT NULL THEN
            PERFORM internal.enqueue_dwca_archive_cleanup(
                affected_job.job_id,
                affected_job.archive_object_key,
                'source_snapshot_changed'
            );
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.revoke_completed_dwca_exports_for_species()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species
    ON public.species_dictionary;
DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species_truncate
    ON public.species_dictionary;

DROP TRIGGER IF EXISTS revoke_completed_dwca_exports_for_species
    ON public.species_dictionary;
CREATE TRIGGER revoke_completed_dwca_exports_for_species
AFTER DELETE OR UPDATE OF iucn_red_list_status
ON public.species_dictionary
FOR EACH ROW
EXECUTE FUNCTION internal.revoke_completed_dwca_exports_for_species();

DROP TRIGGER IF EXISTS revoke_completed_dwca_exports_for_species_truncate
    ON public.species_dictionary;
CREATE TRIGGER revoke_completed_dwca_exports_for_species_truncate
AFTER TRUNCATE ON public.species_dictionary
FOR EACH STATEMENT
EXECUTE FUNCTION internal.revoke_completed_dwca_exports_for_species();

-- The replacement triggers above use parent-first generation locking. Remove
-- the retired source-state-first routines as well as their triggers so future
-- catalog checks cannot accidentally validate or reuse the unsafe lock order.
DROP FUNCTION IF EXISTS internal.invalidate_dwca_exports_for_scan();
DROP FUNCTION IF EXISTS internal.invalidate_dwca_exports_for_species();

-- Existing completed jobs may contain a one-day direct R2 signature generated
-- by the previous worker. Scrub every database copy and enqueue every known
-- archive key before the application-grant protocol becomes reachable.
INSERT INTO internal.export_archive_cleanup_jobs (
    job_id,
    object_key,
    reason_code,
    status,
    next_attempt_at,
    updated_at
)
SELECT
    jobs.id,
    jobs.archive_object_key,
    'legacy_direct_storage_url',
    'pending',
    pg_catalog.NOW(),
    pg_catalog.NOW()
FROM public.export_jobs AS jobs
WHERE jobs.status = 'completed'
  AND jobs.archive_object_key IS NOT NULL
  AND jobs.archive_object_key ~ (
        '^exports/'
        || jobs.user_id::TEXT
        || '/'
        || jobs.id::TEXT
        || '/[0-9a-f-]{36}[.]zip$'
  )
ON CONFLICT ON CONSTRAINT
    export_archive_cleanup_jobs_object_key_key
DO NOTHING;

ALTER TABLE public.export_jobs
    DISABLE TRIGGER enforce_export_job_update;

UPDATE public.export_jobs AS jobs
SET file_url = NULL
WHERE jobs.status = 'completed'
  AND jobs.file_url IS NOT NULL;

ALTER TABLE public.export_jobs
    ENABLE TRIGGER enforce_export_job_update;

UPDATE internal.export_job_work AS work
SET delivery_file_url = NULL,
    updated_at = pg_catalog.NOW()
FROM public.export_jobs AS jobs
WHERE jobs.id = work.job_id
  AND jobs.status = 'completed'
  AND work.delivery_file_url IS NOT NULL;

-- Completed snapshots remain available only while their opaque grant is live.
-- Failed jobs cannot be downloaded, so their source DTOs can be purged
-- immediately after an archive cleanup has been enqueued.
CREATE OR REPLACE FUNCTION internal.purge_dwca_export_source_snapshot()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    terminal_object_key TEXT;
BEGIN
    IF OLD.status NOT IN ('completed', 'failed')
       AND NEW.status IN ('completed', 'failed') THEN
        IF NOT internal.lock_dwca_export_generation(NEW.id) THEN
            RETURN NEW;
        END IF;

        terminal_object_key := COALESCE(
            NEW.archive_object_key,
            OLD.archive_object_key
        );

        UPDATE internal.export_job_work AS work
        SET delivery_file_url = NULL,
            updated_at = pg_catalog.NOW()
        WHERE work.job_id = NEW.id
          AND work.delivery_file_url IS NOT NULL;

        IF NEW.status = 'failed' THEN
            UPDATE internal.export_download_grants AS grants
            SET revoked_at = COALESCE(
                    grants.revoked_at,
                    pg_catalog.CLOCK_TIMESTAMP()
                ),
                revocation_reason = COALESCE(
                    grants.revocation_reason,
                    'job_failed'
                )
            WHERE grants.job_id = NEW.id
              AND grants.cleaned_at IS NULL;

            IF terminal_object_key IS NOT NULL THEN
                PERFORM internal.enqueue_dwca_archive_cleanup(
                    NEW.id,
                    terminal_object_key,
                    'job_failed'
                );
            END IF;

            DELETE FROM internal.export_job_source_rows AS source_rows
            WHERE source_rows.job_id = NEW.id;

            UPDATE internal.export_job_source_state AS source_state
            SET purged_at = COALESCE(
                source_state.purged_at,
                pg_catalog.CLOCK_TIMESTAMP()
            )
            WHERE source_state.job_id = NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.purge_dwca_export_source_snapshot()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.enqueue_dwca_cleanup_before_job_delete()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF OLD.archive_object_key IS NOT NULL THEN
        PERFORM internal.enqueue_dwca_archive_cleanup(
            OLD.id,
            OLD.archive_object_key,
            'job_deleted'
        );
    END IF;
    RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION internal.enqueue_dwca_cleanup_before_job_delete()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enqueue_dwca_cleanup_before_job_delete
    ON public.export_jobs;
CREATE TRIGGER enqueue_dwca_cleanup_before_job_delete
BEFORE DELETE ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.enqueue_dwca_cleanup_before_job_delete();

CREATE OR REPLACE FUNCTION public.stage_prepared_export_archive_with_download_grant(
    p_job_id UUID,
    p_claim_token UUID,
    p_archive_object_key TEXT,
    p_download_url TEXT,
    p_download_token TEXT,
    p_download_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    staged BOOLEAN;
    token_hash TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_download_token IS NULL
       OR p_download_token !~ '^[A-Za-z0-9_-]{43}$'
       OR p_download_url IS NULL
       OR p_download_url
            !~ '^https://[^/?#]+/functions/v1/download-dwca[?]token=[A-Za-z0-9_-]{43}$'
       OR pg_catalog.RIGHT(p_download_url, 43)
            IS DISTINCT FROM p_download_token
       OR p_download_expires_at IS NULL
       OR p_download_expires_at
            <= pg_catalog.NOW() + INTERVAL '1 minute'
       OR p_download_expires_at
            > pg_catalog.NOW() + INTERVAL '2 days' THEN
        RAISE EXCEPTION 'invalid_dwca_download_grant'
            USING ERRCODE = '22023';
    END IF;

    token_hash := pg_catalog.ENCODE(
        extensions.digest(
            pg_catalog.CONVERT_TO(p_download_token, 'UTF8'),
            'sha256'
        ),
        'hex'
    );

    IF NOT internal.lock_dwca_export_generation(p_job_id) THEN
        RETURN FALSE;
    END IF;

    staged := public.stage_prepared_export_archive(
        p_job_id,
        p_claim_token,
        p_archive_object_key,
        p_download_url
    );
    IF NOT staged THEN
        RETURN FALSE;
    END IF;

    INSERT INTO internal.export_download_grants AS grants (
        job_id,
        token_sha256,
        expires_at
    )
    VALUES (
        p_job_id,
        token_hash,
        p_download_expires_at
    )
    ON CONFLICT (job_id) DO UPDATE
    SET token_sha256 = EXCLUDED.token_sha256,
        created_at = pg_catalog.NOW(),
        expires_at = EXCLUDED.expires_at,
        revoked_at = NULL,
        revocation_reason = NULL,
        cleaned_at = NULL;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.stage_prepared_export_archive(
    UUID,
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.stage_prepared_export_archive_with_download_grant(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.stage_prepared_export_archive_with_download_grant(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    TIMESTAMPTZ
) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_prepared_export_job_with_download_grant(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    completed BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF NOT internal.lock_dwca_export_generation(p_job_id) THEN
        RETURN FALSE;
    END IF;

    PERFORM 1
    FROM internal.export_download_grants AS grants
    WHERE grants.job_id = p_job_id
      AND grants.expires_at > pg_catalog.NOW()
      AND grants.revoked_at IS NULL
      AND grants.cleaned_at IS NULL
    FOR SHARE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    completed := public.complete_prepared_export_job(
        p_job_id,
        p_claim_token
    );
    RETURN completed;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_prepared_export_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_prepared_export_job_with_download_grant(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_prepared_export_job_with_download_grant(
    UUID,
    UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_dwca_archive_cleanup(
    p_job_id UUID,
    p_object_key TEXT,
    p_reason_code TEXT
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.enqueue_dwca_archive_cleanup(
        p_job_id,
        p_object_key,
        p_reason_code
    );
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_dwca_archive_cleanup(
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_dwca_archive_cleanup(
    UUID,
    TEXT,
    TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.authorize_dwca_archive_download(
    p_token_sha256 TEXT,
    p_ip_hash TEXT
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    rate_window TIMESTAMPTZ;
    rate_count INTEGER;
    grant_row RECORD;
    source_current BOOLEAN;
    target_job_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_token_sha256 IS NULL
       OR p_token_sha256 !~ '^[0-9a-f]{64}$'
       OR p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_dwca_download_authorization'
            USING ERRCODE = '22023';
    END IF;

    rate_window := pg_catalog.DATE_BIN(
        INTERVAL '5 minutes',
        pg_catalog.CLOCK_TIMESTAMP(),
        '2000-01-01 00:00:00+00'::TIMESTAMPTZ
    );

    INSERT INTO internal.export_download_rate_windows AS windows (
        ip_hash,
        window_started_at,
        request_count,
        updated_at
    )
    VALUES (
        p_ip_hash,
        rate_window,
        1,
        pg_catalog.NOW()
    )
    ON CONFLICT (ip_hash, window_started_at) DO UPDATE
    SET request_count = LEAST(
            windows.request_count + 1,
            1000000
        ),
        updated_at = pg_catalog.NOW()
    RETURNING windows.request_count INTO STRICT rate_count;

    IF rate_count > 60 THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'status',
            'rate_limited',
            'retry_after_seconds',
            300
        );
    END IF;

    SELECT grants.job_id
    INTO target_job_id
    FROM internal.export_download_grants AS grants
    WHERE grants.token_sha256 = p_token_sha256;

    IF NOT FOUND
       OR NOT internal.lock_dwca_export_generation(target_job_id) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('status', 'not_found');
    END IF;

    SELECT
        grants.job_id,
        grants.expires_at,
        grants.revoked_at,
        grants.cleaned_at,
        jobs.status AS job_status,
        jobs.archive_object_key
    INTO grant_row
    FROM internal.export_download_grants AS grants
    INNER JOIN public.export_jobs AS jobs
        ON jobs.id = grants.job_id
    WHERE grants.token_sha256 = p_token_sha256
    FOR UPDATE OF grants;

    IF NOT FOUND THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT('status', 'not_found');
    END IF;

    source_current := internal.dwca_export_source_is_current(
        grant_row.job_id
    );

    IF grant_row.job_status = 'completed'
       AND grant_row.archive_object_key IS NOT NULL
       AND grant_row.expires_at > pg_catalog.NOW()
       AND grant_row.revoked_at IS NULL
       AND grant_row.cleaned_at IS NULL
       AND source_current THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'status',
            'authorized',
            'object_key',
            grant_row.archive_object_key,
            'grant_expires_at',
            grant_row.expires_at
        );
    END IF;

    -- Resend acceptance and the final database transition cannot be atomic.
    -- A recipient who follows the URL in that narrow window must not revoke
    -- the grant or delete the archive that completion is about to publish.
    IF grant_row.job_status NOT IN ('completed', 'failed')
       AND grant_row.archive_object_key IS NOT NULL
       AND grant_row.expires_at > pg_catalog.NOW()
       AND grant_row.revoked_at IS NULL
       AND grant_row.cleaned_at IS NULL
       AND source_current THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'status',
            'not_ready',
            'retry_after_seconds',
            5
        );
    END IF;

    UPDATE internal.export_download_grants AS grants
    SET revoked_at = COALESCE(
            grants.revoked_at,
            pg_catalog.CLOCK_TIMESTAMP()
        ),
        revocation_reason = COALESCE(
            grants.revocation_reason,
            CASE
                WHEN grants.expires_at <= pg_catalog.NOW()
                    THEN 'grant_expired'
                WHEN NOT source_current
                    THEN 'source_snapshot_changed'
                ELSE 'job_unavailable'
            END
        )
    WHERE grants.job_id = grant_row.job_id
      AND grants.cleaned_at IS NULL;

    IF grant_row.archive_object_key IS NOT NULL THEN
        PERFORM internal.enqueue_dwca_archive_cleanup(
            grant_row.job_id,
            grant_row.archive_object_key,
            CASE
                WHEN grant_row.expires_at <= pg_catalog.NOW()
                    THEN 'grant_expired'
                WHEN NOT source_current
                    THEN 'source_snapshot_changed'
                ELSE 'job_unavailable'
            END
        );
    END IF;

    RETURN pg_catalog.JSONB_BUILD_OBJECT('status', 'gone');
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_dwca_archive_download(TEXT, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_dwca_archive_download(
    TEXT,
    TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.claim_dwca_archive_cleanup_jobs(
    p_claim_token UUID,
    p_limit INTEGER DEFAULT 25,
    p_lease_seconds INTEGER DEFAULT 120
)
RETURNS TABLE (
    cleanup_id UUID,
    job_id UUID,
    object_key TEXT,
    attempt_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    claim_limit INTEGER := LEAST(
        GREATEST(COALESCE(p_limit, 25), 1),
        100
    );
    lease_seconds INTEGER := LEAST(
        GREATEST(COALESCE(p_lease_seconds, 120), 30),
        600
    );
    due_grant RECORD;
BEGIN
    PERFORM internal.require_service_role();

    DELETE FROM internal.export_download_rate_windows AS windows
    WHERE windows.window_started_at
        < pg_catalog.NOW() - INTERVAL '2 days';

    IF p_claim_token IS NULL
       OR p_claim_token =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'invalid_dwca_cleanup_claim'
            USING ERRCODE = '22023';
    END IF;

    -- Expiry is itself a durable cleanup source. Discover a bounded wave and
    -- acquire each parent generation in deterministic order before touching
    -- the child outbox. A set-based INSERT would take the child/FK lock first
    -- and invert every privacy/delivery transition's parent-first order.
    FOR due_grant IN
        SELECT
            grants.job_id,
            jobs.archive_object_key,
            CASE
                WHEN grants.revoked_at IS NOT NULL
                    THEN COALESCE(
                        grants.revocation_reason,
                        'grant_revoked'
                    )
                WHEN grants.expires_at <= pg_catalog.NOW()
                    THEN 'grant_expired'
                ELSE 'source_snapshot_changed'
            END AS reason_code
        FROM internal.export_download_grants AS grants
        INNER JOIN public.export_jobs AS jobs
            ON jobs.id = grants.job_id
        INNER JOIN internal.export_job_source_state AS source_state
            ON source_state.job_id = grants.job_id
        WHERE grants.cleaned_at IS NULL
          AND jobs.archive_object_key IS NOT NULL
          AND (
              grants.revoked_at IS NOT NULL
              OR grants.expires_at <= pg_catalog.NOW()
              OR source_state.invalidated_at IS NOT NULL
              OR source_state.purged_at IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.export_archive_cleanup_jobs AS existing_cleanup
              WHERE existing_cleanup.object_key = jobs.archive_object_key
          )
        ORDER BY grants.job_id
        LIMIT 100
    LOOP
        PERFORM internal.enqueue_dwca_archive_cleanup(
            due_grant.job_id,
            due_grant.archive_object_key,
            due_grant.reason_code
        );
    END LOOP;

    UPDATE internal.export_archive_cleanup_jobs AS cleanup
    SET status = 'pending',
        claim_token = NULL,
        lease_expires_at = NULL,
        next_attempt_at = LEAST(
            cleanup.next_attempt_at,
            pg_catalog.NOW()
        ),
        last_error_code = COALESCE(
            cleanup.last_error_code,
            'lease_expired'
        ),
        updated_at = pg_catalog.NOW()
    WHERE cleanup.status = 'processing'
      AND cleanup.lease_expires_at <= pg_catalog.NOW();

    RETURN QUERY
    WITH candidates AS (
        SELECT cleanup.id
        FROM internal.export_archive_cleanup_jobs AS cleanup
        WHERE cleanup.status = 'pending'
          AND cleanup.next_attempt_at <= pg_catalog.NOW()
        ORDER BY cleanup.next_attempt_at, cleanup.created_at, cleanup.id
        LIMIT claim_limit
        FOR UPDATE SKIP LOCKED
    ),
    claimed AS (
        UPDATE internal.export_archive_cleanup_jobs AS cleanup
        SET status = 'processing',
            attempt_count = LEAST(
                cleanup.attempt_count + 1,
                1000000
            ),
            claim_token = p_claim_token,
            lease_expires_at = pg_catalog.NOW()
                + pg_catalog.MAKE_INTERVAL(secs => lease_seconds),
            updated_at = pg_catalog.NOW()
        FROM candidates
        WHERE cleanup.id = candidates.id
        RETURNING
            cleanup.id,
            cleanup.job_id,
            cleanup.object_key,
            cleanup.attempt_count
    )
    SELECT
        claimed.id,
        claimed.job_id,
        claimed.object_key,
        claimed.attempt_count
    FROM claimed
    ORDER BY claimed.attempt_count, claimed.id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_dwca_archive_cleanup_jobs(
    UUID,
    INTEGER,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_dwca_archive_cleanup_jobs(
    UUID,
    INTEGER,
    INTEGER
) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_dwca_archive_cleanup_job(
    p_cleanup_id UUID,
    p_claim_token UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    cleanup_row RECORD;
    target_job_id UUID;
    current_archive_object_key TEXT;
    current_job_status TEXT;
    current_job_found BOOLEAN := FALSE;
BEGIN
    PERFORM internal.require_service_role();

    -- Lock the parent before the leased cleanup row. Job deletion follows
    -- that same parent-to-child order through its BEFORE DELETE enqueue
    -- trigger, avoiding a cleanup/delete deadlock.
    SELECT cleanup.job_id
    INTO target_job_id
    FROM internal.export_archive_cleanup_jobs AS cleanup
    WHERE cleanup.id = p_cleanup_id;

    IF target_job_id IS NOT NULL THEN
        current_job_found := internal.lock_dwca_export_generation(
            target_job_id
        );

        IF current_job_found THEN
            SELECT jobs.archive_object_key, jobs.status
            INTO current_archive_object_key, current_job_status
            FROM public.export_jobs AS jobs
            WHERE jobs.id = target_job_id;
        END IF;
    END IF;

    SELECT cleanup.id, cleanup.job_id, cleanup.object_key
    INTO cleanup_row
    FROM internal.export_archive_cleanup_jobs AS cleanup
    WHERE cleanup.id = p_cleanup_id
      AND cleanup.status = 'processing'
      AND cleanup.claim_token = p_claim_token
      AND cleanup.lease_expires_at > pg_catalog.NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    UPDATE internal.export_archive_cleanup_jobs AS cleanup
    SET status = 'completed',
        claim_token = NULL,
        lease_expires_at = NULL,
        last_error_code = NULL,
        completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE cleanup.id = p_cleanup_id;

    IF cleanup_row.job_id IS NOT NULL AND current_job_found THEN
        -- Attempt archives are keyed by the claim generation. An old cleanup
        -- lease may finish after a replacement claim has staged a new archive
        -- and grant for the same job. Only the cleanup for the job's current
        -- archive may revoke that grant or purge its retained source snapshot.
        IF current_archive_object_key
                IS DISTINCT FROM cleanup_row.object_key THEN
            RETURN TRUE;
        END IF;

        UPDATE internal.export_download_grants AS grants
        SET revoked_at = COALESCE(
                grants.revoked_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            revocation_reason = COALESCE(
                grants.revocation_reason,
                'archive_cleaned'
            ),
            cleaned_at = pg_catalog.NOW()
        WHERE grants.job_id = cleanup_row.job_id
          AND grants.cleaned_at IS NULL;

        IF current_job_status IN ('completed', 'failed') THEN
            DELETE FROM internal.export_job_source_rows AS source_rows
            WHERE source_rows.job_id = cleanup_row.job_id;

            UPDATE internal.export_job_source_state AS source_state
            SET purged_at = COALESCE(
                source_state.purged_at,
                pg_catalog.CLOCK_TIMESTAMP()
            )
            WHERE source_state.job_id = cleanup_row.job_id;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_dwca_archive_cleanup_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_dwca_archive_cleanup_job(
    UUID,
    UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.release_dwca_archive_cleanup_job(
    p_cleanup_id UUID,
    p_claim_token UUID,
    p_error_code TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_error_code IS NULL
       OR p_error_code !~ '^[a-z][a-z0-9_]{1,63}$' THEN
        RAISE EXCEPTION 'invalid_dwca_cleanup_error'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.export_archive_cleanup_jobs AS cleanup
    SET status = 'pending',
        claim_token = NULL,
        lease_expires_at = NULL,
        next_attempt_at = pg_catalog.NOW() + CASE
            WHEN cleanup.attempt_count < 3 THEN INTERVAL '1 minute'
            WHEN cleanup.attempt_count < 10 THEN INTERVAL '5 minutes'
            WHEN cleanup.attempt_count < 25 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END,
        last_error_code = p_error_code,
        updated_at = pg_catalog.NOW()
    WHERE cleanup.id = p_cleanup_id
      AND cleanup.status = 'processing'
      AND cleanup.claim_token = p_claim_token;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;

    RETURN affected_rows = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.release_dwca_archive_cleanup_job(
    UUID,
    UUID,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_dwca_archive_cleanup_job(
    UUID,
    UUID,
    TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.get_dwca_archive_cleanup_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    pending_count BIGINT,
    processing_count BIGINT,
    expired_lease_count BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH outbox_health AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE cleanup.status = 'pending'
            ) AS pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE cleanup.status = 'processing'
            ) AS processing_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE cleanup.status = 'processing'
                  AND cleanup.lease_expires_at <= pg_catalog.NOW()
            ) AS expired_lease_count,
            pg_catalog.MIN(cleanup.next_attempt_at) FILTER (
                WHERE cleanup.status = 'pending'
                  AND cleanup.next_attempt_at <= pg_catalog.NOW()
            ) AS oldest_due_at
        FROM internal.export_archive_cleanup_jobs AS cleanup
        WHERE cleanup.status <> 'completed'
    ),
    unenqueued_grants AS (
        SELECT
            pg_catalog.COUNT(*) AS pending_count,
            pg_catalog.MIN(LEAST(
                grants.revoked_at,
                CASE
                    WHEN grants.expires_at <= pg_catalog.NOW()
                        THEN grants.expires_at
                    ELSE NULL
                END,
                source_state.invalidated_at,
                source_state.purged_at
            )) AS oldest_due_at
        FROM internal.export_download_grants AS grants
        INNER JOIN public.export_jobs AS jobs
            ON jobs.id = grants.job_id
        INNER JOIN internal.export_job_source_state AS source_state
            ON source_state.job_id = grants.job_id
        WHERE grants.cleaned_at IS NULL
          AND jobs.archive_object_key IS NOT NULL
          AND (
              grants.revoked_at IS NOT NULL
              OR grants.expires_at <= pg_catalog.NOW()
              OR source_state.invalidated_at IS NOT NULL
              OR source_state.purged_at IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.export_archive_cleanup_jobs AS cleanup
              WHERE cleanup.object_key = jobs.archive_object_key
          )
    ),
    combined AS (
        SELECT
            outbox_health.pending_count
                + unenqueued_grants.pending_count AS pending_count,
            outbox_health.processing_count,
            outbox_health.expired_lease_count,
            LEAST(
                outbox_health.oldest_due_at,
                unenqueued_grants.oldest_due_at
            ) AS oldest_due_at
        FROM outbox_health
        CROSS JOIN unenqueued_grants
    )
    SELECT
        pg_catalog.CLOCK_TIMESTAMP(),
        combined.pending_count,
        combined.processing_count,
        combined.expired_lease_count,
        combined.oldest_due_at,
        EXTRACT(
            EPOCH FROM (
                pg_catalog.CLOCK_TIMESTAMP()
                - combined.oldest_due_at
            )
        )::BIGINT
    FROM combined;
END;
$$;

REVOKE ALL ON FUNCTION public.get_dwca_archive_cleanup_health()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dwca_archive_cleanup_health()
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'authenticated',
        'public.update_owned_scan_custom_tags(uuid,text[])',
        'Updates only a caller-owned scan custom-tag array after deriving identity from auth.uid and validating bounds.'
    ),
    (
        'authenticated',
        'public.update_owned_scan_identification_review(uuid,text,boolean,uuid,public.user_review_state)',
        'Atomically updates a coherent caller-owned identification review after deriving identity from auth.uid.'
    ),
    (
        'service_role',
        'public.request_scan_deletion(uuid,uuid)',
        'Durably fences an owner scan generation before any external media erasure begins.'
    ),
    (
        'service_role',
        'public.complete_scan_deletion(uuid,uuid)',
        'Deletes the canonical owner row only after the caller confirms external media erasure.'
    ),
    (
        'service_role',
        'public.request_nonbiological_scan_retention_deletions(integer)',
        'Generation-locks and revalidates expired non-biological scans before enqueuing durable erasure work.'
    ),
    (
        'service_role',
        'public.claim_scan_deletion_jobs(uuid,integer,integer)',
        'Leases owner-requested scan erasure jobs to the independent bounded cleanup worker.'
    ),
    (
        'service_role',
        'public.release_scan_deletion_job(uuid,uuid,uuid,text)',
        'Compare-before-releases a failed scan erasure lease with bounded exponential retry.'
    ),
    (
        'service_role',
        'public.get_scan_deletion_health()',
        'Returns service-only pending, processing, expired-lease, and oldest-pending scan erasure health.'
    ),
    (
        'service_role',
        'public.claim_scan_ingestion_job(text,uuid,text,jsonb,jsonb,uuid[],text,integer)',
        'Compatibility ingestion claim serialized against owner-row recovery by the shared per-scan generation lock.'
    ),
    (
        'service_role',
        'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)',
        'Atomically serializes a scan ingestion claim against owner-row recovery before any provider call.'
    ),
    (
        'service_role',
        'public.recover_missing_owned_scan(uuid,uuid,jsonb)',
        'Atomically validates and reconstructs a missing owner scan only when structured ingestion state permits recovery.'
    ),
    (
        'service_role',
        'public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])',
        'Transactionally normalizes required media and writes scan-ingestion completion last.'
    ),
    (
        'service_role',
        'public.stage_prepared_export_archive_with_download_grant(uuid,uuid,text,text,text,timestamp with time zone)',
        'Stages a private archive and hashed opaque application download grant after full source revalidation.'
    ),
    (
        'service_role',
        'public.complete_prepared_export_job_with_download_grant(uuid,uuid)',
        'Completes delivery only when an unexpired private application download grant exists.'
    ),
    (
        'service_role',
        'public.enqueue_dwca_archive_cleanup(uuid,text,text)',
        'Durably enqueues attempt-scoped private archive deletion without exposing storage authority.'
    ),
    (
        'service_role',
        'public.authorize_dwca_archive_download(text,text)',
        'Rate-limits and fully revalidates an opaque completed export before a short storage redirect.'
    ),
    (
        'service_role',
        'public.claim_dwca_archive_cleanup_jobs(uuid,integer,integer)',
        'Leases due private archive deletion outbox rows to the scheduled cleanup worker.'
    ),
    (
        'service_role',
        'public.complete_dwca_archive_cleanup_job(uuid,uuid)',
        'Records verified archive deletion and purges the retained private source snapshot.'
    ),
    (
        'service_role',
        'public.release_dwca_archive_cleanup_job(uuid,uuid,text)',
        'Releases failed archive deletion attempts with durable exponential retry.'
    ),
    (
        'service_role',
        'public.get_dwca_archive_cleanup_health()',
        'Returns service-only backlog, oldest-due, and expired-lease health for archive cleanup.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

DELETE FROM internal.privileged_routine_grants AS grants
WHERE grants.role_name = 'service_role'
  AND grants.routine_signature IN (
      'public.stage_prepared_export_archive(uuid,uuid,text,text)',
      'public.complete_prepared_export_job(uuid,uuid)'
  );

DO $schedule$
BEGIN
    PERFORM cron.unschedule('reconcile_dwca_archive_cleanup_every_five_minutes');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$schedule$;

SELECT cron.schedule(
    'reconcile_dwca_archive_cleanup_every_five_minutes',
    '*/5 * * * *',
    $cron$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT secrets.decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT secrets.decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := pg_catalog.CURRENT_SETTING(
                'app.settings.supabase_url',
                TRUE
            );
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key := pg_catalog.CURRENT_SETTING(
                'app.settings.service_role_key',
                TRUE
            );
        END IF;

        IF NULLIF(pg_catalog.BTRIM(project_url), '') IS NOT NULL
           AND NULLIF(
                pg_catalog.BTRIM(service_role_key),
                ''
           ) IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url
                    || '/functions/v1/reconcile-dwca-archive-cleanup',
                headers := internal.server_api_request_headers(
                    service_role_key
                ),
                body := pg_catalog.JSONB_BUILD_OBJECT('limit', 25),
                timeout_milliseconds := 120000
            );
        END IF;
    END;
    $job$;
    $cron$
);

DO $schedule$
BEGIN
    PERFORM cron.unschedule('reconcile_scan_deletions_every_five_minutes');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$schedule$;

SELECT cron.schedule(
    'reconcile_scan_deletions_every_five_minutes',
    '*/5 * * * *',
    $cron$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT secrets.decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT secrets.decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := pg_catalog.CURRENT_SETTING(
                'app.settings.supabase_url',
                TRUE
            );
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key := pg_catalog.CURRENT_SETTING(
                'app.settings.service_role_key',
                TRUE
            );
        END IF;

        IF NULLIF(pg_catalog.BTRIM(project_url), '') IS NOT NULL
           AND NULLIF(
                pg_catalog.BTRIM(service_role_key),
                ''
           ) IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url
                    || '/functions/v1/reconcile-scan-deletions',
                headers := internal.server_api_request_headers(
                    service_role_key
                ),
                body := '{}'::JSONB,
                timeout_milliseconds := 120000
            );
        END IF;
    END;
    $job$;
    $cron$
);

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;

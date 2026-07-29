-- Harden the media-abandoned owner-row recovery authority added by
-- 20260729173000_recover_media_abandoned_owned_scans.sql.
--
-- A failed_scan_ingestions row proves that some provider result reached the
-- post-result durability path, but it does not by itself prove that a later
-- retry was not permanently rejected. Before the July 29 worker fix, the media
-- reconciler could overwrite that later policy terminal state with
-- media_reconciliation_abandoned.
--
-- There are two producer generations to support:
--
-- 1. Historical identify-multimodal committed quota before provider dispatch
--    and wrote the dead letter after owner-row failure, but did not transition
--    the reservation to `failed`. A committed normal reservation that predates
--    the matching dead letter is therefore legacy success evidence, not
--    automatically a policy veto. The legacy message must also match the
--    audited producer's post-safety throwing path.
-- 2. The hardened producer records exact reservation/request identity and
--    completed safety evaluation in the dead letter. Structured evidence is
--    mandatory for failures written after this migration begins.
--
-- Use every deterministic normal/replay quota key, the latest charged-attempt
-- timestamp, exact structured evidence when available, and the full capture
-- lifecycle. Explicit moderation rejection and moderation infrastructure
-- failure both remain non-recoverable.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

ALTER TABLE public.failed_scan_ingestions
    ADD COLUMN IF NOT EXISTS quota_reservation_id UUID,
    ADD COLUMN IF NOT EXISTS quota_request_id UUID,
    ADD COLUMN IF NOT EXISTS failure_kind TEXT,
    ADD COLUMN IF NOT EXISTS provider_result_validated BOOLEAN,
    ADD COLUMN IF NOT EXISTS identify_safety_evaluation_completed BOOLEAN;

ALTER TABLE public.failed_scan_ingestions
    DROP CONSTRAINT IF EXISTS
        failed_scan_ingestions_structured_recovery_evidence_check;
ALTER TABLE public.failed_scan_ingestions
    ADD CONSTRAINT
        failed_scan_ingestions_structured_recovery_evidence_check
    CHECK (
        (
            quota_reservation_id IS NULL
            AND quota_request_id IS NULL
            AND failure_kind IS NULL
            AND provider_result_validated IS NULL
            AND identify_safety_evaluation_completed IS NULL
        )
        OR (
            quota_reservation_id IS NOT NULL
            AND quota_request_id IS NOT NULL
            AND failure_kind = 'post_result_scan_durability_failure'
            AND provider_result_validated IS TRUE
            AND identify_safety_evaluation_completed IS NOT NULL
        )
    );

CREATE INDEX IF NOT EXISTS
    failed_scan_ingestions_recovery_proof_idx
    ON public.failed_scan_ingestions (user_id, scan_id, failed_at DESC);
DROP INDEX IF EXISTS public.failed_scan_ingestions_user_scan_idx;

COMMENT ON COLUMN public.failed_scan_ingestions.quota_reservation_id IS
    'Exact server quota reservation for structured post-result recovery evidence. NULL only for historical producers.';
COMMENT ON COLUMN public.failed_scan_ingestions.quota_request_id IS
    'Exact normal/replay AI request key for structured post-result recovery evidence. NULL only for historical producers.';
COMMENT ON COLUMN public.failed_scan_ingestions.failure_kind IS
    'Machine-readable recovery evidence kind. Historical operational rows remain NULL.';
COMMENT ON COLUMN public.failed_scan_ingestions.provider_result_validated IS
    'TRUE only after the identify provider response passed finish-reason and response-schema validation.';
COMMENT ON COLUMN
    public.failed_scan_ingestions.identify_safety_evaluation_completed IS
    'TRUE only after required identify media safety evaluation completed; audio-only Explore publication is independently moderated.';

-- Freeze both the rollout boundary and the exact historical dead-letter row
-- identities. `failed_at` historically defaulted to transaction_timestamp(),
-- so a producer insert blocked behind this migration could carry a timestamp
-- earlier than the migration even though its row becomes visible afterward.
-- Timestamp comparison alone is therefore not a safe immutable cutoff.
CREATE TABLE IF NOT EXISTS internal.scan_recovery_evidence_control (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    legacy_unstructured_before TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

ALTER TABLE internal.scan_recovery_evidence_control
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.scan_recovery_evidence_control
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS internal.scan_recovery_legacy_dead_letters (
    failed_scan_ingestion_id UUID PRIMARY KEY
        REFERENCES public.failed_scan_ingestions(id)
        ON DELETE CASCADE,
    captured_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE internal.scan_recovery_legacy_dead_letters
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.scan_recovery_legacy_dead_letters
    FROM PUBLIC, anon, authenticated, service_role;

WITH inserted_control AS (
    INSERT INTO internal.scan_recovery_evidence_control (
        singleton,
        legacy_unstructured_before
    )
    VALUES (TRUE, pg_catalog.CLOCK_TIMESTAMP())
    ON CONFLICT (singleton) DO NOTHING
    RETURNING legacy_unstructured_before
)
INSERT INTO internal.scan_recovery_legacy_dead_letters (
    failed_scan_ingestion_id,
    captured_at
)
SELECT
    failures.id,
    inserted_control.legacy_unstructured_before
FROM inserted_control
CROSS JOIN public.failed_scan_ingestions AS failures
WHERE failures.quota_reservation_id IS NULL
  AND failures.quota_request_id IS NULL
  AND failures.failure_kind IS NULL
  AND failures.provider_result_validated IS NULL
  AND failures.identify_safety_evaluation_completed IS NULL
ON CONFLICT (failed_scan_ingestion_id) DO NOTHING;

COMMENT ON TABLE internal.scan_recovery_evidence_control IS
    'Private immutable rollout boundary paired with an exact row-identity snapshot. Timestamp is an additional validation bound, never the sole legacy recovery authority.';
COMMENT ON TABLE internal.scan_recovery_legacy_dead_letters IS
    'Private immutable identities of unstructured failed-scan rows visible during the first hardening migration transaction. Later or lock-blocked inserts never gain legacy recovery authority regardless of transaction timestamp.';

CREATE OR REPLACE FUNCTION internal.derive_ai_quota_request_id(
    p_parent_request_id UUID,
    p_discriminator TEXT
)
RETURNS UUID
LANGUAGE SQL
IMMUTABLE
STRICT
PARALLEL SAFE
SET search_path = ''
AS $$
    WITH digest_bytes AS (
        SELECT pg_catalog.SUBSTRING(
            pg_catalog.SHA256(
                pg_catalog.CONVERT_TO(
                    pg_catalog.LOWER(p_parent_request_id::TEXT)
                        || ':' || p_discriminator,
                    'UTF8'
                )
            ),
            1,
            16
        ) AS value
    ),
    versioned AS (
        SELECT pg_catalog.SET_BYTE(
            pg_catalog.SET_BYTE(
                digest_bytes.value,
                6,
                (
                    pg_catalog.GET_BYTE(digest_bytes.value, 6) & 15
                ) | 128
            ),
            8,
            (
                pg_catalog.GET_BYTE(digest_bytes.value, 8) & 63
            ) | 128
        ) AS value
        FROM digest_bytes
    ),
    encoded AS (
        SELECT pg_catalog.ENCODE(versioned.value, 'hex') AS value
        FROM versioned
    )
    SELECT (
        pg_catalog.SUBSTRING(encoded.value, 1, 8)
            || '-'
            || pg_catalog.SUBSTRING(encoded.value, 9, 4)
            || '-'
            || pg_catalog.SUBSTRING(encoded.value, 13, 4)
            || '-'
            || pg_catalog.SUBSTRING(encoded.value, 17, 4)
            || '-'
            || pg_catalog.SUBSTRING(encoded.value, 21, 12)
    )::UUID
    FROM encoded;
$$;

REVOKE ALL ON FUNCTION internal.derive_ai_quota_request_id(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.derive_ai_quota_request_id(UUID, TEXT) IS
    'Internal SQL mirror of the Edge UUIDv8 SHA-256 AI request-id derivation. Not an API surface.';

CREATE OR REPLACE FUNCTION internal.media_abandoned_scan_has_recovery_proof(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
    WITH intent_state AS (
        SELECT COALESCE(
            pg_catalog.MAX(intents.replay_attempt_count),
            0
        ) AS replay_attempt_count
        FROM public.scan_ingestion_intents AS intents
        WHERE intents.scan_id = p_scan_id::TEXT
          AND intents.user_id = p_user_id
    ),
    exact_request_ids(attempt, request_id) AS (
        SELECT 0, p_scan_id
        UNION ALL
        -- Inspect every possible replay key even if an old intent is absent or
        -- stale. The replay claim routine cannot issue an attempt above ten;
        -- an out-of-range intent fails closed below.
        SELECT
            attempts.attempt,
            internal.derive_ai_quota_request_id(
                p_scan_id,
                'scan-ingestion-replay:' || attempts.attempt::TEXT
            )
        FROM pg_catalog.GENERATE_SERIES(1, 10) AS attempts(attempt)
    ),
    exact_reservations AS (
        SELECT
            exact_request_ids.attempt,
            reservations.id,
            reservations.request_id,
            reservations.state,
            reservations.attempt_count,
            reservations.reserved_at,
            reservations.committed_at,
            reservations.failed_at,
            CASE
                WHEN reservations.state = 'failed'
                    THEN reservations.failed_at
                WHEN reservations.state = 'committed'
                    THEN reservations.committed_at
                ELSE NULL
            END AS authority_at
        FROM internal.ai_quota_reservations AS reservations
        JOIN exact_request_ids
          ON exact_request_ids.request_id = reservations.request_id
        WHERE reservations.user_id = p_user_id
          AND reservations.operation = 'scan_identification'
    ),
    latest_authority AS (
        SELECT exact_reservations.*
        FROM exact_reservations
        WHERE exact_reservations.state IN ('failed', 'committed')
        ORDER BY
            exact_reservations.authority_at DESC NULLS FIRST,
            exact_reservations.attempt DESC,
            exact_reservations.id
        LIMIT 1
    ),
    evidence_control AS (
        SELECT controls.legacy_unstructured_before
        FROM internal.scan_recovery_evidence_control AS controls
        WHERE controls.singleton
    )
    SELECT p_scan_id IS NOT NULL
       AND p_user_id IS NOT NULL
       AND (
            SELECT intent_state.replay_attempt_count <= 10
            FROM intent_state
       )
       AND EXISTS (
            SELECT 1
            FROM public.scan_ingestion_jobs AS jobs
            WHERE jobs.scan_id = p_scan_id::TEXT
              AND jobs.user_id = p_user_id
              AND jobs.endpoint = 'identify-multimodal'
              AND jobs.status = 'failed_terminal'
              AND jobs.terminal_reason_code =
                  'media_reconciliation_abandoned'
       )
       AND EXISTS (
            SELECT 1
            FROM latest_authority
            JOIN public.failed_scan_ingestions AS failures
              ON failures.scan_id = p_scan_id::TEXT
             AND failures.user_id = p_user_id
             AND failures.failed_at >= latest_authority.authority_at
            CROSS JOIN evidence_control
            WHERE (
                (
                    failures.quota_reservation_id = latest_authority.id
                    AND failures.quota_request_id =
                        latest_authority.request_id
                    AND failures.failure_kind =
                        'post_result_scan_durability_failure'
                    AND failures.provider_result_validated IS TRUE
                    AND failures.identify_safety_evaluation_completed IS TRUE
                )
                OR (
                    failures.quota_reservation_id IS NULL
                    AND failures.quota_request_id IS NULL
                    AND failures.failure_kind IS NULL
                    AND failures.provider_result_validated IS NULL
                    AND failures.identify_safety_evaluation_completed IS NULL
                    AND EXISTS (
                        SELECT 1
                        FROM internal.scan_recovery_legacy_dead_letters
                            AS legacy_failures
                        WHERE legacy_failures.failed_scan_ingestion_id =
                            failures.id
                    )
                    AND failures.failed_at <
                        evidence_control.legacy_unstructured_before
                    -- Every quota-era unstructured multimodal producer used
                    -- this control flow: the only throwing operation between
                    -- provider validation and image safety evaluation was the
                    -- user prerequisite. Moderation rejection/infrastructure
                    -- errors included "moderation"; non-video branches
                    -- returned without writing a dead letter. Exclude both
                    -- lineages so a pre-safety operational failure cannot be
                    -- mistaken for a completed safe result.
                    AND failures.error_message IS NOT NULL
                    AND pg_catalog.LOWER(failures.error_message) NOT LIKE
                        'failed to ensure scan user exists:%'
                    AND pg_catalog.LOWER(failures.error_message) NOT LIKE
                        '%moderation%'
                    AND (
                        latest_authority.state = 'failed'
                        OR (
                            -- The vulnerable producer could leave its first
                            -- normal attempt committed after owner-row failure.
                            -- An unstructured committed replay or repeated
                            -- normal attempt is ambiguous and remains closed.
                            latest_authority.state = 'committed'
                            AND latest_authority.attempt = 0
                            AND latest_authority.attempt_count = 1
                            AND NOT EXISTS (
                                SELECT 1
                                FROM exact_reservations AS replay_authority
                                WHERE replay_authority.attempt > 0
                                  AND replay_authority.state IN (
                                      'failed',
                                      'committed'
                                  )
                            )
                        )
                    )
                )
            )
       )
       AND NOT EXISTS (
            SELECT 1
            FROM exact_reservations
            WHERE exact_reservations.state = 'reserved'
       )
       AND NOT EXISTS (
            -- Corrupt or manually forged terminal timestamps are not recovery
            -- authority. Every charge must follow its reservation, and a
            -- failed lease must retain its preceding ordered commit.
            SELECT 1
            FROM exact_reservations
            WHERE (
                exact_reservations.state = 'committed'
                AND (
                    exact_reservations.committed_at IS NULL
                    OR exact_reservations.committed_at <
                        exact_reservations.reserved_at
                )
            )
            OR (
                exact_reservations.state = 'failed'
                AND (
                    exact_reservations.committed_at IS NULL
                    OR exact_reservations.failed_at IS NULL
                    OR exact_reservations.committed_at <
                        exact_reservations.reserved_at
                    OR exact_reservations.failed_at <
                        exact_reservations.committed_at
                )
            )
       )
       AND NOT EXISTS (
            SELECT 1
            FROM public.scan_media_assets AS assets
            WHERE assets.user_id = p_user_id
              AND assets.client_scan_id = p_scan_id
              AND assets.source = 'capture_upload'
              AND assets.failure_reason IN (
                  'moderation_rejected',
                  'moderation_pipeline_error'
              )
       );
$$;

REVOKE ALL ON FUNCTION
    internal.media_abandoned_scan_has_recovery_proof(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION
    internal.media_abandoned_scan_has_recovery_proof(UUID, UUID) IS
    'Internal exact recovery proof: a structured matching post-result dead letter (or migration-snapshotted and cutoff-bounded audited legacy post-safety evidence) after the latest charged normal/replay attempt, no active attempt or invalid timestamp lineage, and no moderation rejection/infrastructure failure.';

-- The quota ledger normally retains terminal reservations for thirty days.
-- A media-abandonment recovery may be discovered much later when an older
-- library item is opened. Retain every exact normal/replay reservation while
-- that terminal ledger is unresolved: both failed proof and committed
-- chronological authority are durable security evidence. Preserve all ten
-- possible replay keys even when an old intent row is absent or stale. Once
-- recovery marks the job complete (or an operator resolves its terminal
-- reason), ordinary pruning resumes.
CREATE OR REPLACE FUNCTION internal.prune_ai_quota_state()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.refund_expired_ai_quota_reservations(1000);

    DELETE FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.id IN (
        WITH protected_reservations AS MATERIALIZED (
            -- Expand every unresolved media-abandoned job once. Avoid a
            -- candidate-by-job correlated scan when the ordinary cleanup
            -- batch contains thousands of old quota rows.
            SELECT
                jobs.user_id,
                CASE
                    -- scan_id predates UUID enforcement. Keep the cast inside
                    -- the conditional expression so one malformed legacy row
                    -- cannot abort hourly quota maintenance.
                    WHEN jobs.scan_id ~
                        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                        THEN CASE
                            WHEN attempts.attempt = 0
                                THEN jobs.scan_id::UUID
                            ELSE internal.derive_ai_quota_request_id(
                                jobs.scan_id::UUID,
                                'scan-ingestion-replay:'
                                    || attempts.attempt::TEXT
                            )
                        END
                    ELSE NULL
                END AS request_id
            FROM public.scan_ingestion_jobs AS jobs
            CROSS JOIN LATERAL pg_catalog.GENERATE_SERIES(
                0,
                10
            ) AS attempts(attempt)
            WHERE jobs.status = 'failed_terminal'
              AND jobs.terminal_reason_code =
                  'media_reconciliation_abandoned'
        )
        SELECT candidates.id
        FROM internal.ai_quota_reservations AS candidates
        WHERE candidates.state IN ('committed', 'failed', 'refunded')
          AND candidates.updated_at <
              pg_catalog.NOW() - INTERVAL '30 days'
          AND NOT (
              candidates.operation = 'scan_identification'
              AND candidates.state IN ('failed', 'committed')
              AND EXISTS (
                  SELECT 1
                  FROM protected_reservations AS protected
                  WHERE protected.user_id = candidates.user_id
                    AND protected.request_id = candidates.request_id
              )
          )
        ORDER BY candidates.updated_at, candidates.id
        LIMIT 10000
    );

    DELETE FROM internal.ai_quota_counters AS counters
    WHERE (
        counters.scope_type,
        counters.scope_key,
        counters.bucket,
        counters.window_start
    ) IN (
        SELECT
            candidates.scope_type,
            candidates.scope_key,
            candidates.bucket,
            candidates.window_start
        FROM internal.ai_quota_counters AS candidates
        WHERE candidates.window_start <
              pg_catalog.NOW() - INTERVAL '2 days'
          AND NOT EXISTS (
              SELECT 1
              FROM internal.ai_quota_reservation_counters AS links
              WHERE links.scope_type = candidates.scope_type
                AND links.scope_key = candidates.scope_key
                AND links.bucket = candidates.bucket
                AND links.window_start = candidates.window_start
          )
        ORDER BY candidates.window_start
        LIMIT 10000
    );
END;
$$;

REVOKE ALL ON FUNCTION internal.prune_ai_quota_state()
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.prune_ai_quota_state() IS
    'Refunds expired AI leases and prunes ordinary terminal quota state while retaining every possible exact failed/committed normal or replay reservation for unresolved media-abandoned scan ledgers.';

CREATE OR REPLACE FUNCTION public.get_media_abandoned_scan_recovery_proofs(
    p_user_id UUID,
    p_scan_ids UUID[]
)
RETURNS TABLE (
    scan_id UUID
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_scan_ids IS NULL
       OR pg_catalog.CARDINALITY(p_scan_ids) NOT BETWEEN 1 AND 20
       OR pg_catalog.ARRAY_POSITION(p_scan_ids, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'invalid_media_abandoned_recovery_proof_request'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT DISTINCT requested.scan_id
    FROM pg_catalog.UNNEST(p_scan_ids) AS requested(scan_id)
    WHERE internal.media_abandoned_scan_has_recovery_proof(
        requested.scan_id,
        p_user_id
    );
END;
$$;

REVOKE ALL ON FUNCTION
    public.get_media_abandoned_scan_recovery_proofs(UUID, UUID[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
    public.get_media_abandoned_scan_recovery_proofs(UUID, UUID[])
    TO service_role;

COMMENT ON FUNCTION
    public.get_media_abandoned_scan_recovery_proofs(UUID, UUID[]) IS
    'Service-only bounded proof lookup used by restore signing. Returns only exact owner/scan media-abandonment recoveries whose latest charged attempt has matching safe post-result or audited legacy post-safety evidence.';

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])',
        'Returns a bounded set of exact owner/scan media-abandonment recoveries whose chronological quota, structured/legacy dead-letter, replay, and safety authority remains safe to reopen.'
    ),
    (
        'service_role',
        'public.recover_missing_owned_scan(uuid,uuid,jsonb)',
        'Atomically validates and reconstructs a missing owner scan only when structured completion or composite retryable recovery authority permits it.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

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
           AND (
                ingestion_job.terminal_reason_code = 'replay_exhausted'
                OR (
                    ingestion_job.terminal_reason_code =
                        'media_reconciliation_abandoned'
                    AND internal.media_abandoned_scan_has_recovery_proof(
                        p_scan_id,
                        p_user_id
                    )
                )
           )
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

COMMENT ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB) IS
    'Service-only, per-scan-locked reconstruction of an absent authenticated-owner scan from a normalized non-media payload. Allows complete, replay_exhausted, or exactly proven retryable media_reconciliation_abandoned ledgers; later policy authority, moderation rejection, deletion tombstones, active/retryable/unproven/unknown terminal jobs, and ID collisions fail closed.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

-- Prevent an anonymous-profile merge from stranding an in-flight scan.
--
-- Identify commits quota immediately before provider dispatch, then persists
-- the scan in later database transactions. A Ghost profile can be merged in
-- that interval. The catalog-driven merge reparents the job, intent, media
-- rows, and quota reservation to the permanent account, while the old Edge
-- invocation continues to address the retired source UUID. Historically this
-- left a committed reservation with no scan and made every retry replay an
-- answer that could never exist.
--
-- This migration adds two narrow boundaries:
--   * the merge transaction fences every non-terminal source scan, refunds an
--     undispatched reservation or marks a dispatched reservation failed, and
--     makes pre-scan staged media explicitly require re-upload;
--   * a service-only recovery RPC repairs historical rows using the exact
--     owner/job/reservation/tombstone evidence and an expired lease (or a
--     proven merged-source lineage).
--
-- Failed/committed usage is never decremented. A retry is newly metered.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION internal.prepare_scan_ingestions_for_identity_merge(
    p_source_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    quota_row RECORD;
    collision_row RECORD;
    transition_now TIMESTAMPTZ :=
        pg_catalog.CLOCK_TIMESTAMP();
BEGIN
    IF p_source_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_source_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'invalid_identity_merge_scan_owners'
            USING ERRCODE = '22023';
    END IF;

    -- The caller already holds both profile rows and the source Ghost advisory
    -- lock. Mark every unfinished generation before generic FK reparenting so
    -- a callback carrying the source UUID cannot silently mutate the moved row.
    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'failed_retryable',
        stage = 'identity_merge_interrupted',
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = transition_now,
        last_error =
            'Saving was interrupted while account ownership changed.',
        terminal_reason_code = NULL,
        completed_at = NULL,
        response_envelope = NULL,
        updated_at = transition_now
    WHERE jobs.user_id = p_source_user_id
      AND jobs.endpoint IN (
          'identify',
          'identify-multimodal',
          'identify-describe',
          'audio-spec'
      )
      AND jobs.status IN (
          'processing',
          'finalizing',
          'retrying',
          'failed_retryable'
      )
      AND jobs.scan_id
          ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      AND NOT EXISTS (
          SELECT 1
          FROM internal.scan_deletion_tombstones AS tombstones
          WHERE tombstones.scan_id = jobs.scan_id::UUID
      );

    -- Inline intents cannot be server-replayed, and staged intents may point
    -- at an object that the interrupted invocation already consumed. Require
    -- the owning client to establish a fresh target-owned staging manifest.
    UPDATE public.scan_ingestion_intents AS intents
    SET resumable = FALSE,
        last_replay_error = 'identity_merge_interrupted',
        updated_at = transition_now
    WHERE intents.user_id = p_source_user_id
      AND intents.endpoint IN (
          'identify',
          'identify-multimodal',
          'identify-describe',
          'audio-spec'
      )
      AND intents.scan_id
          ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      AND EXISTS (
          SELECT 1
          FROM public.scan_ingestion_jobs AS jobs
          WHERE jobs.user_id = p_source_user_id
            AND jobs.scan_id = intents.scan_id
            AND jobs.status = 'failed_retryable'
            AND jobs.stage = 'identity_merge_interrupted'
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.scans AS scans
          WHERE scans.id = intents.scan_id::UUID
      );

    -- A pre-scan capture may have been fetched, copied, or deleted between
    -- provider completion and the merge. Do not guess whether its object still
    -- exists. Retire only source-owned, unbound capture rows for the exact
    -- interrupted generation; signing retry creates a new target manifest.
    UPDATE public.scan_media_assets AS assets
    SET status = 'failed',
        failure_reason = 'superseded_identity_merge_staging',
        deleted_at = NULL,
        updated_at = transition_now
    WHERE assets.user_id = p_source_user_id
      AND assets.source = 'capture_upload'
      AND assets.scan_id IS NULL
      AND assets.client_scan_id IS NOT NULL
      AND assets.status IN ('staged', 'failed')
      AND EXISTS (
          SELECT 1
          FROM public.scan_ingestion_jobs AS jobs
          WHERE jobs.user_id = p_source_user_id
            AND jobs.scan_id = assets.client_scan_id::TEXT
            AND jobs.status = 'failed_retryable'
            AND jobs.stage = 'identity_merge_interrupted'
      );

    -- Fence quota for generations with no durable scan. Reserved means the
    -- provider was not successfully dispatched and its counters are released.
    -- Committed means provider work happened: retain consumed counters, but
    -- make the idempotency key eligible for a newly charged retry.
    FOR quota_row IN
        SELECT
            reservations.id,
            reservations.state
        FROM internal.ai_quota_reservations AS reservations
        JOIN public.scan_ingestion_jobs AS jobs
          ON jobs.user_id = p_source_user_id
         AND jobs.scan_id = reservations.request_id::TEXT
        WHERE reservations.user_id = p_source_user_id
          AND (
              (
                  jobs.endpoint IN (
                      'identify',
                      'identify-multimodal',
                      'identify-describe'
                  )
                  AND reservations.operation = 'scan_identification'
              )
              OR (
                  jobs.endpoint = 'audio-spec'
                  AND reservations.operation =
                      'scan_audio_identification'
              )
          )
          AND reservations.state IN ('reserved', 'committed')
          AND jobs.status = 'failed_retryable'
          AND jobs.stage = 'identity_merge_interrupted'
          AND NOT EXISTS (
              SELECT 1
              FROM public.scans AS scans
              WHERE scans.id = reservations.request_id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM internal.scan_deletion_tombstones AS tombstones
              WHERE tombstones.scan_id = reservations.request_id
          )
        ORDER BY reservations.id
        FOR UPDATE OF reservations
    LOOP
        IF quota_row.state = 'reserved' THEN
            PERFORM internal.release_ai_quota_reservation_counters(
                quota_row.id
            );

            UPDATE internal.ai_quota_reservations AS reservations
            SET state = 'refunded',
                refund_count = reservations.refund_count + 1,
                refunded_at = transition_now,
                updated_at = transition_now
            WHERE reservations.id = quota_row.id
              AND reservations.state = 'reserved';
        ELSE
            UPDATE internal.ai_quota_reservations AS reservations
            SET state = 'failed',
                failed_at = transition_now,
                updated_at = transition_now
            WHERE reservations.id = quota_row.id
              AND reservations.state = 'committed';
        END IF;
    END LOOP;

    -- The existing merge policy lets a destination job win an identical
    -- (owner, scan_id) conflict. Apply the same policy to its quota key before
    -- generic FK reparenting, otherwise the reservation UNIQUE constraint can
    -- abort the entire account merge. If the source already owns a scan and
    -- its provider call committed, retain that committed fence on the target
    -- row. Quota reservations are operational records; immutable attribution
    -- remains in ai_usage_events.
    FOR collision_row IN
        SELECT
            source_reservation.id AS source_id,
            source_reservation.state AS source_state,
            target_reservation.id AS target_id,
            target_reservation.state AS target_state,
            source_reservation.request_id,
            EXISTS (
                SELECT 1
                FROM public.scans AS scans
                WHERE scans.id = source_reservation.request_id
                  AND scans.user_id = p_source_user_id
            ) AS source_scan_exists
        FROM internal.ai_quota_reservations AS source_reservation
        JOIN internal.ai_quota_reservations AS target_reservation
          ON target_reservation.user_id = p_target_user_id
         AND target_reservation.operation =
                source_reservation.operation
         AND target_reservation.request_id =
                source_reservation.request_id
        WHERE source_reservation.user_id = p_source_user_id
          AND source_reservation.operation IN (
              'scan_identification',
              'scan_audio_identification'
          )
          AND EXISTS (
              SELECT 1
              FROM public.scan_ingestion_jobs AS jobs
              WHERE jobs.user_id = p_source_user_id
                AND jobs.scan_id =
                    source_reservation.request_id::TEXT
                AND (
                    (
                        jobs.endpoint IN (
                            'identify',
                            'identify-multimodal',
                            'identify-describe'
                        )
                        AND source_reservation.operation =
                            'scan_identification'
                    )
                    OR (
                        jobs.endpoint = 'audio-spec'
                        AND source_reservation.operation =
                            'scan_audio_identification'
                    )
                )
          )
        ORDER BY source_reservation.id
        FOR UPDATE OF source_reservation, target_reservation
    LOOP
        IF collision_row.source_state = 'reserved' THEN
            PERFORM internal.release_ai_quota_reservation_counters(
                collision_row.source_id
            );
        END IF;

        IF collision_row.source_state = 'committed'
           AND collision_row.source_scan_exists
           AND collision_row.target_state <> 'committed' THEN
            -- Any destination reservation counters stay consumed. The source
            -- committed call was also consumed; no usage is refunded.
            DELETE FROM internal.ai_quota_reservation_counters AS links
            WHERE links.reservation_id = collision_row.target_id;

            UPDATE internal.ai_quota_reservations AS reservations
            SET state = 'committed',
                committed_at = COALESCE(
                    reservations.committed_at,
                    transition_now
                ),
                failed_at = NULL,
                refunded_at = NULL,
                updated_at = transition_now
            WHERE reservations.id = collision_row.target_id;
        END IF;

        DELETE FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.id = collision_row.source_id;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION internal.prepare_scan_ingestions_for_identity_merge(
    UUID,
    UUID
) IS
    'Trusted Ghost-merge hook that fences unfinished Identify generations, retires ambiguous pre-scan staging, and reconciles quota without refunding dispatched provider usage.';

REVOKE ALL ON FUNCTION internal.prepare_scan_ingestions_for_identity_merge(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

-- Insert the scan fence into the already-reviewed atomic merge implementation.
-- Rewriting the current catalog definition preserves subsequent trusted
-- dependency rewires (for example internal author-identity refresh).
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT :=
        '    -- Prevent uniqueness conflicts in operational ledgers before their new';
    replacement_fragment TEXT :=
        '    PERFORM internal.prepare_scan_ingestions_for_identity_merge('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id,'
        || pg_catalog.CHR(10)
        || '        p_target_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || '    -- Prevent uniqueness conflicts in operational ledgers before their new';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'internal.perform_ghost_profile_merge(uuid,uuid)'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF rewritten_definition IS NOT DISTINCT FROM function_definition
       OR (
           pg_catalog.LENGTH(rewritten_definition)
           - pg_catalog.LENGTH(
               pg_catalog.REPLACE(
                   rewritten_definition,
                   'PERFORM internal.prepare_scan_ingestions_for_identity_merge(',
                   ''
               )
           )
       ) / pg_catalog.LENGTH(
           'PERFORM internal.prepare_scan_ingestions_for_identity_merge('
       ) <> 1 THEN
        RAISE EXCEPTION
            'Could not install the exact identity-merge scan fence';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

REVOKE ALL ON FUNCTION internal.perform_ghost_profile_merge(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.recover_stranded_scan_ingestion_attempt(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    job_row public.scan_ingestion_jobs%ROWTYPE;
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    scan_owner UUID;
    candidate_source_ids UUID[];
    merged_source_user_id UUID;
    recovery_now TIMESTAMPTZ;
    attempt_recoverable BOOLEAN := FALSE;
    outcome TEXT := 'not_applicable';
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_stranded_scan_recovery_identity'
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
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            'deleted',
            'authorized_source_user_id',
            NULL
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users AS profiles
        WHERE profiles.id = p_user_id
    ) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            'not_applicable',
            'authorized_source_user_id',
            NULL
        );
    END IF;

    SELECT jobs.*
    INTO job_row
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            'job_not_found',
            'authorized_source_user_id',
            NULL
        );
    END IF;
    IF job_row.endpoint NOT IN (
        'identify',
        'identify-multimodal',
        'identify-describe',
        'audio-spec'
    ) THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            'not_applicable',
            'authorized_source_user_id',
            NULL
        );
    END IF;

    -- Recover the source owner only from canonical staging/public URL shapes.
    -- Every non-target candidate must collapse to one UUID and that UUID must
    -- have an exact completed handoff into this target account.
    WITH media_keys(storage_key) AS (
        SELECT image_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    job_row.media_object_keys -> 'image'
                ) = 'array'
                    THEN job_row.media_object_keys -> 'image'
                ELSE '[]'::JSONB
            END
        ) AS image_keys(storage_key)
        UNION ALL
        SELECT audio_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    job_row.media_object_keys -> 'audio'
                ) = 'array'
                    THEN job_row.media_object_keys -> 'audio'
                ELSE '[]'::JSONB
            END
        ) AS audio_keys(storage_key)
        UNION ALL
        SELECT video_keys.storage_key
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
            CASE
                WHEN pg_catalog.JSONB_TYPEOF(
                    job_row.media_object_keys -> 'video'
                ) = 'array'
                    THEN job_row.media_object_keys -> 'video'
                ELSE '[]'::JSONB
            END
        ) AS video_keys(storage_key)
    ),
    media_urls(url) AS (
        SELECT image_urls.url
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.image_storage_urls, '{}'::TEXT[])
        ) AS image_urls(url)
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
        UNION ALL
        SELECT video_urls.url
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.video_storage_urls, '{}'::TEXT[])
        ) AS video_urls(url)
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
        UNION ALL
        SELECT audio_urls.url
        FROM public.scans AS scans
        CROSS JOIN LATERAL pg_catalog.UNNEST(
            COALESCE(scans.audio_storage_urls, '{}'::TEXT[])
        ) AS audio_urls(url)
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
    ),
    owner_texts(owner_text) AS (
        SELECT pg_catalog.SUBSTRING(
            media_keys.storage_key
            FROM (
                '^staging/('
                || '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'
                || '[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                || '[0-9a-fA-F]{12}'
                || ')/[A-Za-z0-9._-]+$'
            )
        )
        FROM media_keys
        UNION ALL
        SELECT pg_catalog.SUBSTRING(
            media_urls.url
            FROM (
                '^https://media[.]merian[.]app/'
                || 'public_uploads/[^/]+/('
                || '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'
                || '[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                || '[0-9a-fA-F]{12}'
                || ')/[A-Za-z0-9._-]+$'
            )
        )
        FROM media_urls
    )
    SELECT COALESCE(
        pg_catalog.ARRAY_AGG(
            DISTINCT owner_texts.owner_text::UUID
            ORDER BY owner_texts.owner_text::UUID
        ) FILTER (
            WHERE owner_texts.owner_text IS NOT NULL
              AND owner_texts.owner_text::UUID <> p_user_id
        ),
        '{}'::UUID[]
    )
    INTO STRICT candidate_source_ids
    FROM owner_texts;

    IF pg_catalog.CARDINALITY(candidate_source_ids) = 1
       AND EXISTS (
           SELECT 1
           FROM internal.ghost_profile_merge_handoffs AS handoff
           WHERE handoff.ghost_user_id = candidate_source_ids[1]
             AND handoff.target_user_id = p_user_id
             AND handoff.status = 'merged'
             AND handoff.merged_at IS NOT NULL
       ) THEN
        merged_source_user_id := candidate_source_ids[1];
    END IF;

    recovery_now := pg_catalog.CLOCK_TIMESTAMP();
    attempt_recoverable :=
        job_row.status = 'failed_retryable'
        OR (
            job_row.status IN (
                'processing',
                'finalizing',
                'retrying'
            )
            AND (
                (
                    job_row.lock_expires_at IS NOT NULL
                    AND job_row.lock_expires_at <= recovery_now
                )
                OR (
                    job_row.lock_expires_at IS NULL
                    AND job_row.updated_at
                        <= recovery_now - INTERVAL '10 minutes'
                )
            )
        );

    SELECT scans.user_id
    INTO scan_owner
    FROM public.scans AS scans
    WHERE scans.id = p_scan_id
    FOR UPDATE;

    IF FOUND THEN
        IF scan_owner IS DISTINCT FROM p_user_id THEN
            outcome := 'not_applicable';
        ELSIF job_row.status = 'complete' THEN
            outcome := 'already_complete';
        ELSE
            -- The moderated provider result and all promoted legacy media URLs
            -- are committed in the scan insert transaction. Never reopen quota
            -- once that owner row exists. Mark only a proven abandoned attempt
            -- retryable so canonical recovery can run; response reconstruction
            -- may immediately replay the owned analysis in parallel.
            IF attempt_recoverable
               AND job_row.status <> 'failed_terminal' THEN
                UPDATE public.scan_ingestion_jobs AS jobs
                SET status = 'failed_retryable',
                    stage = CASE
                        WHEN merged_source_user_id IS NOT NULL
                          OR jobs.stage = 'identity_merge_interrupted'
                            THEN 'identity_merge_interrupted'
                        ELSE 'background_ingestion_failed'
                    END,
                    locked_at = NULL,
                    lock_expires_at = NULL,
                    retry_after = recovery_now,
                    last_error = COALESCE(
                        jobs.last_error,
                        'Durable scan finalization requires recovery.'
                    ),
                    terminal_reason_code = NULL,
                    completed_at = NULL,
                    updated_at = recovery_now
                WHERE jobs.id = job_row.id
                  AND jobs.status <> 'failed_terminal';
            END IF;
            outcome := 'scan_durable';
        END IF;

        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            outcome,
            'authorized_source_user_id',
            merged_source_user_id
        );
    END IF;

    IF job_row.status IN ('complete', 'failed_terminal')
       OR NOT attempt_recoverable THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            CASE
                WHEN job_row.status = 'complete'
                    THEN 'complete_without_scan'
                WHEN job_row.status = 'failed_terminal'
                    THEN 'terminal'
                ELSE 'active'
            END,
            'authorized_source_user_id',
            merged_source_user_id
        );
    END IF;

    SELECT reservations.*
    INTO reservation_row
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.user_id = p_user_id
      AND reservations.operation = CASE job_row.endpoint
          WHEN 'audio-spec' THEN 'scan_audio_identification'
          ELSE 'scan_identification'
      END
      AND reservations.request_id = p_scan_id
    FOR UPDATE;

    IF FOUND AND reservation_row.state = 'committed' THEN
        -- Provider usage remains consumed. Only reopen the exact idempotency
        -- key; reserve_ai_quota will meter its next attempt independently.
        UPDATE internal.ai_quota_reservations AS reservations
        SET state = 'failed',
            failed_at = recovery_now,
            updated_at = recovery_now
        WHERE reservations.id = reservation_row.id
          AND reservations.state = 'committed';

        DELETE FROM internal.ai_quota_reservation_counters AS links
        WHERE links.reservation_id = reservation_row.id;
    ELSIF FOUND
          AND reservation_row.state = 'reserved'
          AND reservation_row.lease_expires_at > recovery_now THEN
        -- Any live reservation may still dispatch provider work. Even exact
        -- merge lineage cannot prove that a concurrent target invocation is
        -- abandoned, so wait for its lease rather than risk double inference.
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'outcome',
            'active',
            'authorized_source_user_id',
            NULL
        );
    END IF;

    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'failed_retryable',
        stage = CASE
            WHEN merged_source_user_id IS NOT NULL
              OR jobs.stage = 'identity_merge_interrupted'
                THEN 'identity_merge_interrupted'
            ELSE 'background_ingestion_failed'
        END,
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = recovery_now,
        last_error = COALESCE(
            jobs.last_error,
            'Provider result was not durably saved; retry is safe.'
        ),
        terminal_reason_code = NULL,
        completed_at = NULL,
        response_envelope = NULL,
        updated_at = recovery_now
    WHERE jobs.id = job_row.id;

    IF merged_source_user_id IS NOT NULL
       OR job_row.stage = 'identity_merge_interrupted' THEN
        UPDATE public.scan_ingestion_intents AS intents
        SET resumable = FALSE,
            last_replay_error = 'identity_merge_interrupted',
            updated_at = recovery_now
        WHERE intents.user_id = p_user_id
          AND intents.scan_id = p_scan_id::TEXT;

        UPDATE public.scan_media_assets AS assets
        SET status = 'failed',
            failure_reason = 'superseded_identity_merge_staging',
            deleted_at = NULL,
            updated_at = recovery_now
        WHERE assets.user_id = p_user_id
          AND assets.client_scan_id = p_scan_id
          AND assets.scan_id IS NULL
          AND assets.source = 'capture_upload'
          AND assets.status IN ('staged', 'failed')
          AND (
              assets.storage_key LIKE (
                  'staging/'
                  || COALESCE(
                      merged_source_user_id::TEXT,
                      ''
                  )
                  || '/%'
              )
              OR (
                  job_row.stage = 'identity_merge_interrupted'
                  AND EXISTS (
                      SELECT 1
                      FROM internal.ghost_profile_merge_handoffs AS handoff
                      WHERE handoff.target_user_id = p_user_id
                        AND handoff.status = 'merged'
                        AND assets.storage_key LIKE (
                            'staging/'
                            || handoff.ghost_user_id::TEXT
                            || '/%'
                        )
                  )
              )
          );

        outcome := 'media_restage_required';
    ELSE
        outcome := 'quota_retry_ready';
    END IF;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'outcome',
        outcome,
        'authorized_source_user_id',
        merged_source_user_id
    );
END;
$$;

COMMENT ON FUNCTION public.recover_stranded_scan_ingestion_attempt(
    UUID,
    UUID
) IS
    'Service-only exact-owner recovery for scan-less committed quota attempts and identity-merge staging interruptions; deletion tombstones and active leases win.';

REVOKE ALL ON FUNCTION public.recover_stranded_scan_ingestion_attempt(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_stranded_scan_ingestion_attempt(
    UUID,
    UUID
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)',
    'Reopens only exact scan-less failed/expired/identity-merged ingestion attempts without refunding dispatched provider usage; retires ambiguous merged staging for client re-upload.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;

NOTIFY pgrst, 'reload schema';

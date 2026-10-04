SET lock_timeout = '5s';
SET statement_timeout = '2min';

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

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'scan_deletion_user_unavailable'
            USING ERRCODE = 'P0001';
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

    -- A legacy request may be a queued replacement deletion from an older
    -- device. It is never explicit authorization to erase retained history.
    IF EXISTS (
        SELECT 1 FROM internal.observation_histories
        WHERE observation_id = p_scan_id
    ) THEN
        RETURN 'legacy_observation_delete_requires_upgrade';
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

    PERFORM public.fail_scan_ingestion_terminal(
        p_scan_id,
        p_user_id,
        'user_deleted',
        NULL,
        'user_deleted'
    );

    UPDATE public.scan_ingestion_jobs AS jobs
    SET completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status = 'failed_terminal'
      AND jobs.terminal_reason_code = 'user_deleted';

    RETURN 'accepted';
END;
$$;

REVOKE ALL ON FUNCTION public.request_scan_deletion(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_scan_deletion(UUID, UUID)
    TO service_role;

COMMENT ON FUNCTION public.request_scan_deletion(UUID, UUID) IS
    'Service-only user-first owner verification, terminal settlement, and permanent scan-generation fence before media erasure.';

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

    -- DELETE triggers reconcile owner statistics. Acquire that owner before
    -- the generation/tombstone locks, matching request and account deletion.
    -- An already detached owner may be absent; completed receipts still replay.
    PERFORM users.id FROM public.users AS users
    WHERE users.id = p_user_id FOR UPDATE;

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

CREATE OR REPLACE FUNCTION public.request_nonbiological_scan_retention_deletions(
    p_limit INTEGER DEFAULT 500
)
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '30s' AS $$
DECLARE
    batch_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 500), 1), 500);
    candidate_ids UUID[];
    candidate_owners UUID[];
    candidate_id UUID;
    scan_owner UUID;
    request_status TEXT;
    accepted_count INTEGER := 0;
BEGIN
    PERFORM internal.require_service_role();
    SELECT pg_catalog.ARRAY_AGG(candidate.id), pg_catalog.ARRAY_AGG(candidate.user_id)
    INTO candidate_ids, candidate_owners
    FROM (
        SELECT scans.id, scans.user_id
        FROM public.scans AS scans
        WHERE scans.is_biological_subject IS FALSE AND scans.is_tombstoned IS FALSE
          AND scans.timestamp < pg_catalog.NOW() - pg_catalog.MAKE_INTERVAL(days => 30)
          AND scans.user_id IS NOT NULL
          AND scans.user_id <> '00000000-0000-0000-0000-000000000000'::UUID
          AND NOT EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = scans.id)
          AND NOT EXISTS (SELECT 1 FROM internal.observation_histories WHERE observation_id = scans.id)
        ORDER BY scans.timestamp, scans.id LIMIT batch_limit
    ) AS candidate;

    -- Lock all owners first, in the same order as account merge, before any
    -- generation or scan lock. Recheck ownership after acquiring these locks.
    PERFORM users.id FROM public.users AS users
    WHERE users.id = ANY(candidate_owners) ORDER BY users.id FOR UPDATE;
    FOR candidate_id IN SELECT id FROM pg_catalog.UNNEST(candidate_ids) AS id ORDER BY id
    LOOP
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || candidate_id::TEXT, 0::BIGINT));
        SELECT scans.user_id INTO scan_owner FROM public.scans AS scans
        WHERE scans.id = candidate_id
          AND scans.user_id = ANY(candidate_owners)
          AND scans.is_biological_subject IS FALSE AND scans.is_tombstoned IS FALSE
          AND scans.timestamp < pg_catalog.NOW() - pg_catalog.MAKE_INTERVAL(days => 30)
          AND scans.user_id <> '00000000-0000-0000-0000-000000000000'::UUID
          AND NOT EXISTS (SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = scans.id)
          AND NOT EXISTS (SELECT 1 FROM internal.observation_histories WHERE observation_id = scans.id)
        FOR UPDATE;
        IF NOT FOUND THEN CONTINUE; END IF;
        request_status := public.request_scan_deletion(candidate_id, scan_owner);
        IF request_status <> 'accepted' THEN
            RAISE EXCEPTION 'retention_scan_deletion_not_accepted' USING ERRCODE = '55000';
        END IF;
        accepted_count := accepted_count + 1;
    END LOOP;
    RETURN accepted_count;
END;
$$;
REVOKE ALL ON FUNCTION public.request_nonbiological_scan_retention_deletions(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_nonbiological_scan_retention_deletions(INTEGER) TO service_role;
COMMENT ON FUNCTION public.request_nonbiological_scan_retention_deletions(INTEGER) IS
    'Service-only bounded user-first retention selector; enrolled history is excluded at discovery and locked revalidation.';

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    -- Deletion, history and entitlement work lock the owner before any scan.
    -- Account detachment must use that same order to avoid a user/scan cycle.
    PERFORM users.id FROM public.users AS users
    WHERE users.id = target_user_id FOR UPDATE;

    UPDATE public.scans AS scans
    SET user_id = NULL,
        is_tombstoned = TRUE,
        image_storage_urls = ARRAY[]::TEXT[],
        video_storage_urls = ARRAY[]::TEXT[],
        audio_storage_urls = ARRAY[]::TEXT[],
        captured_media = NULL,
        semantic_location = NULL,
        public_location_label = NULL,
        device_locale = NULL,
        device_time_zone = NULL,
        user_observation_context = NULL,
        custom_tags = ARRAY[]::TEXT[],
        human_intervention_notes = NULL
    WHERE scans.user_id = target_user_id;

    DELETE FROM public.users AS users
    WHERE users.id = target_user_id;
END;
$$;

COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only account detachment. It removes account linkage, media, free-form notes, and device/semantic-location context while retaining the ownerless scientific observation, including exact coordinates and elevation.';

REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID)
    TO service_role;

RESET statement_timeout;
RESET lock_timeout;

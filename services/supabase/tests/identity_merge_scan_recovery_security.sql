\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    source_user_id UUID :=
        '00000000-0000-4000-8000-00000000d801';
    target_user_id UUID :=
        '00000000-0000-4000-8000-00000000d802';
    scan_id UUID :=
        '00000000-0000-4000-8000-00000000d803';
    upload_session_id UUID :=
        '00000000-0000-4000-8000-00000000d804';
    first_reservation RECORD;
    retried_reservation RECORD;
    recovery_result JSONB;
    charged_before BIGINT;
    charged_after BIGINT;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'stranded scan recovery does not have an exact service-only ACL';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE pg_catalog.HAS_FUNCTION_PRIVILEGE(
            api_role.role_name,
            'internal.prepare_scan_ingestions_for_identity_merge(uuid,uuid)',
            'EXECUTE'
        )
    ) THEN
        RAISE EXCEPTION
            'an API role can execute the trusted identity-merge scan hook';
    END IF;

    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        email_confirmed_at,
        last_sign_in_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        is_anonymous
    )
    VALUES
        (
            '00000000-0000-0000-0000-000000000000',
            source_user_id,
            'authenticated',
            'authenticated',
            NULL,
            NULL,
            pg_catalog.NOW(),
            '{"provider":"anonymous","providers":["anonymous"]}',
            '{}',
            pg_catalog.NOW() - INTERVAL '1 day',
            pg_catalog.NOW(),
            TRUE
        ),
        (
            '00000000-0000-0000-0000-000000000000',
            target_user_id,
            'authenticated',
            'authenticated',
            'identity-merge-target@naturebook.invalid',
            pg_catalog.NOW(),
            pg_catalog.NOW(),
            '{"provider":"email","providers":["email"]}',
            '{"full_name":"Identity Merge Target"}',
            pg_catalog.NOW() - INTERVAL '30 days',
            pg_catalog.NOW(),
            FALSE
        );

    INSERT INTO public.users (
        id,
        email,
        public_username,
        public_author_name,
        public_identity_source,
        subscription_tier,
        created_at
    )
    VALUES
        (
            source_user_id,
            NULL,
            'identity_source_d801',
            'Identity Merge Source',
            'alias',
            'free',
            pg_catalog.NOW() - INTERVAL '1 day'
        ),
        (
            target_user_id,
            'identity-merge-target@naturebook.invalid',
            'identity_target_d802',
            'Identity Merge Target',
            'display_name',
            'pro',
            pg_catalog.NOW() - INTERVAL '30 days'
        )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        subscription_tier = EXCLUDED.subscription_tier,
        created_at = EXCLUDED.created_at;

    INSERT INTO public.scan_ingestion_jobs (
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
        lock_expires_at
    )
    VALUES (
        scan_id::TEXT,
        source_user_id,
        'identify-multimodal',
        'finalizing',
        'ai_inference_complete',
        1,
        '{
          "image_count":1,
          "audio_count":0,
          "video_count":0,
          "required_video_count":0,
          "video_frame_count":0,
          "video_inference_frame_count":0
        }',
        pg_catalog.JSONB_BUILD_OBJECT(
            'image',
            pg_catalog.JSONB_BUILD_ARRAY(
                'staging/'
                || source_user_id::TEXT
                || '/capture.webp'
            ),
            'audio',
            '[]'::JSONB,
            'video',
            '[]'::JSONB
        ),
        ARRAY[upload_session_id],
        pg_catalog.NOW(),
        pg_catalog.NOW() + INTERVAL '10 minutes'
    );

    INSERT INTO public.scan_ingestion_intents (
        scan_id,
        user_id,
        endpoint,
        request_payload,
        media_counts,
        media_object_keys,
        upload_session_ids,
        resumable
    )
    SELECT
        jobs.scan_id,
        jobs.user_id,
        jobs.endpoint,
        pg_catalog.JSONB_BUILD_OBJECT(
            'clientScanId',
            scan_id::TEXT
        ),
        jobs.media_counts,
        jobs.media_object_keys,
        jobs.upload_session_ids,
        TRUE
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.user_id = source_user_id
      AND jobs.scan_id = scan_id::TEXT;

    INSERT INTO public.scan_media_assets (
        scan_id,
        client_scan_id,
        upload_session_id,
        user_id,
        kind,
        role,
        status,
        source,
        url,
        storage_key,
        order_index,
        content_type
    )
    VALUES (
        NULL,
        scan_id,
        upload_session_id,
        source_user_id,
        'image',
        'display',
        'staged',
        'capture_upload',
        NULL,
        'staging/'
            || source_user_id::TEXT
            || '/capture.webp',
        0,
        'image/webp'
    );

    SELECT *
    INTO STRICT first_reservation
    FROM public.reserve_ai_quota(
        source_user_id,
        'scan_identification',
        scan_id,
        pg_catalog.REPEAT('d', 64)
    );

    PERFORM public.finalize_ai_quota_reservation(
        first_reservation.reservation_id,
        source_user_id,
        first_reservation.lease_token,
        'committed'
    );

    SELECT COALESCE(
        pg_catalog.SUM(counters.request_count),
        0
    )
    INTO STRICT charged_before
    FROM internal.ai_quota_counters AS counters
    WHERE counters.scope_type IN ('user_daily', 'user_rate')
      AND counters.scope_key = source_user_id::TEXT;

    -- Exercise the actual patched merge function. It must fence the scan before
    -- generic FK ownership changes and profile deletion.
    PERFORM internal.perform_ghost_profile_merge(
        source_user_id,
        target_user_id
    );

    IF EXISTS (
        SELECT 1
        FROM public.users AS profiles
        WHERE profiles.id = source_user_id
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scan_ingestion_jobs AS jobs
        WHERE jobs.user_id = target_user_id
          AND jobs.scan_id = scan_id::TEXT
          AND jobs.status = 'failed_retryable'
          AND jobs.stage = 'identity_merge_interrupted'
          AND jobs.locked_at IS NULL
          AND jobs.lock_expires_at IS NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scan_ingestion_intents AS intents
        WHERE intents.user_id = target_user_id
          AND intents.scan_id = scan_id::TEXT
          AND intents.resumable = FALSE
          AND intents.last_replay_error =
              'identity_merge_interrupted'
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scan_media_assets AS assets
        WHERE assets.user_id = target_user_id
          AND assets.client_scan_id = scan_id
          AND assets.status = 'failed'
          AND assets.failure_reason =
              'superseded_identity_merge_staging'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.user_id = target_user_id
          AND reservations.operation = 'scan_identification'
          AND reservations.request_id = scan_id
          AND reservations.state = 'failed'
    ) THEN
        RAISE EXCEPTION
            'atomic Ghost merge did not fence every scan dependency';
    END IF;

    SELECT COALESCE(
        pg_catalog.SUM(counters.request_count),
        0
    )
    INTO STRICT charged_after
    FROM internal.ai_quota_counters AS counters
    WHERE counters.scope_type IN ('user_daily', 'user_rate')
      AND counters.scope_key = source_user_id::TEXT;

    IF charged_after <> charged_before OR charged_before < 1 THEN
        RAISE EXCEPTION
            'committed provider usage was refunded during merge: % -> %',
            charged_before,
            charged_after;
    END IF;

    INSERT INTO internal.ghost_profile_merge_handoffs (
        ghost_user_id,
        target_user_id,
        expected_provider,
        expected_provider_subject,
        secret_hash,
        status,
        expires_at,
        merged_at
    )
    VALUES (
        source_user_id,
        target_user_id,
        'google',
        'identity-merge-recovery-subject',
        pg_catalog.REPEAT('e', 64),
        'merged',
        pg_catalog.NOW() + INTERVAL '30 days',
        pg_catalog.NOW()
    );

    -- Exact merge lineage does not override a live target-owned job lease. A
    -- concurrent target retry must win rather than being interrupted and
    -- charged twice.
    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'processing',
        stage = 'ai_inference',
        locked_at = pg_catalog.NOW(),
        lock_expires_at = pg_catalog.NOW() + INTERVAL '10 minutes'
    WHERE jobs.user_id = target_user_id
      AND jobs.scan_id = scan_id::TEXT;

    SET LOCAL ROLE service_role;
    SELECT public.recover_stranded_scan_ingestion_attempt(
        scan_id,
        target_user_id
    )
    INTO STRICT recovery_result;
    RESET ROLE;

    IF recovery_result ->> 'outcome' <> 'active' THEN
        RAISE EXCEPTION
            'exact merge lineage overrode a live target lease: %',
            recovery_result;
    END IF;

    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'failed_retryable',
        stage = 'identity_merge_interrupted',
        locked_at = NULL,
        lock_expires_at = NULL
    WHERE jobs.user_id = target_user_id
      AND jobs.scan_id = scan_id::TEXT;

    SET LOCAL ROLE service_role;
    SELECT public.recover_stranded_scan_ingestion_attempt(
        scan_id,
        target_user_id
    )
    INTO STRICT recovery_result;
    RESET ROLE;

    IF recovery_result ->> 'outcome'
            <> 'media_restage_required'
       OR recovery_result ->> 'authorized_source_user_id'
            <> source_user_id::TEXT THEN
        RAISE EXCEPTION
            'target recovery did not prove the exact merged source: %',
            recovery_result;
    END IF;

    SELECT *
    INTO STRICT retried_reservation
    FROM public.reserve_ai_quota(
        target_user_id,
        'scan_identification',
        scan_id,
        pg_catalog.REPEAT('f', 64)
    );

    IF retried_reservation.is_replay
       OR retried_reservation.reservation_id
            <> first_reservation.reservation_id
       OR retried_reservation.attempt_count <> 2
       OR retried_reservation.effective_plan <> 'pro_paid'
       OR retried_reservation.lease_token =
            first_reservation.lease_token THEN
        RAISE EXCEPTION
            'failed merged reservation did not produce a fenced metered retry';
    END IF;

    PERFORM public.finalize_ai_quota_reservation(
        retried_reservation.reservation_id,
        target_user_id,
        retried_reservation.lease_token,
        'refunded'
    );
END;
$test$;

SELECT extensions.ok(
    TRUE,
    'identity-merge scan recovery is fenced, charged, and owner-exact'
);
SELECT * FROM extensions.finish();
ROLLBACK;

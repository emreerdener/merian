\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $setup$
DECLARE
    exhausted_user_id UUID := '00000000-0000-4000-8000-00000000aa01';
    available_user_id UUID := '00000000-0000-4000-8000-00000000aa02';
    target_user_id UUID;
    scan_number INTEGER;
BEGIN
    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_my_scan_admission_preview(boolean)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_my_scan_admission_preview(boolean)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_my_scan_admission_preview(boolean)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'scan admission preview has an unsafe ACL';
    END IF;

    UPDATE internal.entitlement_rollout_config AS config
    SET entitlement_mode = 'complimentary',
        required_client_protocol = 3
    WHERE config.config_key = 'current';

    FOREACH target_user_id IN ARRAY ARRAY[
        exhausted_user_id,
        available_user_id
    ]
    LOOP
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
        VALUES (
            '00000000-0000-0000-0000-000000000000'::UUID,
            target_user_id,
            'authenticated',
            'authenticated',
            target_user_id::TEXT || '@scan-preview.invalid',
            pg_catalog.NOW(),
            pg_catalog.NOW(),
            '{"provider":"email","providers":["email"]}'::JSONB,
            '{}'::JSONB,
            pg_catalog.NOW() - INTERVAL '30 days',
            pg_catalog.NOW(),
            FALSE
        );

        UPDATE public.users AS users
        SET created_at = pg_catalog.NOW() - INTERVAL '30 days',
            subscription_tier = 'free',
            subscription_expires_at = NULL
        WHERE users.id = target_user_id;

        FOR scan_number IN 1..3
        LOOP
            INSERT INTO internal.complimentary_scan_usage (
                user_id,
                client_scan_id,
                state,
                held_at,
                settled_at,
                settlement_reason,
                created_at,
                updated_at
            )
            VALUES (
                target_user_id,
                (
                    pg_catalog.SUBSTR(target_user_id::TEXT, 1, 32)
                    || pg_catalog.LPAD(scan_number::TEXT, 4, '0')
                )::UUID,
                'consumed',
                pg_catalog.NOW(),
                pg_catalog.NOW(),
                'completed',
                pg_catalog.NOW(),
                pg_catalog.NOW()
            );
        END LOOP;
    END LOOP;

    INSERT INTO internal.ai_quota_counters (
        scope_type,
        scope_key,
        bucket,
        window_start,
        window_seconds,
        request_count
    )
    VALUES (
        'user_daily',
        exhausted_user_id::TEXT,
        'scan_inference:free',
        pg_catalog.DATE_TRUNC('day', pg_catalog.NOW(), 'UTC'),
        86400,
        1
    );
END;
$setup$;

SET LOCAL ROLE authenticated;

SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    pg_catalog.JSONB_BUILD_OBJECT(
        'sub', '00000000-0000-4000-8000-00000000aa01',
        'role', 'authenticated'
    )::TEXT,
    TRUE
);

DO $exhausted$
DECLARE
    preview_row RECORD;
BEGIN
    SELECT preview.*
    INTO STRICT preview_row
    FROM public.get_my_scan_admission_preview(TRUE) AS preview;

    IF preview_row.decision <> 'daily_quota_exhausted'
       OR preview_row.effective_plan <> 'free'
       OR preview_row.daily_limit <> 1
       OR preview_row.daily_remaining <> 0 THEN
        RAISE EXCEPTION 'exhausted caller received an invalid preview';
    END IF;

    SELECT preview.*
    INTO STRICT preview_row
    FROM public.get_my_scan_admission_preview(FALSE) AS preview;

    IF preview_row.decision <> 'pro_required' THEN
        RAISE EXCEPTION 'Pro-only preview admitted an exhausted free caller';
    END IF;
END;
$exhausted$;

SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    pg_catalog.JSONB_BUILD_OBJECT(
        'sub', '00000000-0000-4000-8000-00000000aa02',
        'role', 'authenticated'
    )::TEXT,
    TRUE
);

DO $available$
DECLARE
    preview_row RECORD;
BEGIN
    SELECT preview.*
    INTO STRICT preview_row
    FROM public.get_my_scan_admission_preview(TRUE) AS preview;

    IF preview_row.decision <> 'allowed'
       OR preview_row.effective_plan <> 'free'
       OR preview_row.daily_limit <> 1
       OR preview_row.daily_remaining <> 1 THEN
        RAISE EXCEPTION 'available caller inherited another account quota';
    END IF;
END;
$available$;

RESET ROLE;

SELECT extensions.pass(
    'scan admission preview is caller-bound, least-privilege, and quota-aware'
);
SELECT * FROM extensions.finish();
ROLLBACK;

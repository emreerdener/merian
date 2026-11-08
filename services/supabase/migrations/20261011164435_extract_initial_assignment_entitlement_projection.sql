-- First shared assignment prerequisite: select entitlement without holding credits.
-- The existing active-reservation replay and all outer admission guards stay in
-- the quota owner. This private helper supplies no execution/storage authority.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

CREATE FUNCTION internal.resolve_fresh_quota_entitlement(
    p_user_id UUID, p_operation TEXT, p_original_analysis_id UUID,
    p_flash_fallback_eligible BOOLEAN, p_quota_now TIMESTAMPTZ
) RETURNS TABLE (
    effective_plan TEXT, complimentary_client_scan_id UUID,
    flash_fallback_used BOOLEAN, acquire_complimentary_hold BOOLEAN
)
LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$
DECLARE
    app_user RECORD;
    rollout RECORD;
    usage_row internal.complimentary_scan_usage%ROWTYPE;
    entitlement_after RECORD;
    resolved_plan TEXT;
    resolved_link UUID;
    resolved_flash_fallback BOOLEAN := FALSE;
    main_scan_operation BOOLEAN;
    consumed_count INTEGER := 0;
    held_count INTEGER := 0;
    quota_now TIMESTAMPTZ := p_quota_now;
    acquire_hold BOOLEAN := FALSE;
BEGIN
    IF p_user_id IS NULL OR p_operation IS NULL
       OR p_operation !~ '^[a-z][a-z0-9_]{2,63}$'
       OR p_flash_fallback_eligible IS NULL OR p_quota_now IS NULL THEN
        RAISE EXCEPTION 'ai_quota_invalid_request' USING ERRCODE = '22023';
    END IF;
    -- Same authoritative rows and modes as the existing quota wrapper. Its
    -- caller already owns these locks; future preparation must own the same
    -- outer owner/namespace scope before using this projection.
    SELECT users.subscription_tier, users.created_at,
        users.subscription_expires_at, users.entitlement_version
    INTO app_user FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE = 'P0001';
    END IF;
    SELECT config.* INTO rollout FROM internal.entitlement_rollout_config AS config
    WHERE config.config_key = 'current' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE = 'P0001';
    END IF;
    main_scan_operation := p_operation IN ('scan_identification', 'scan_audio_identification');
        IF app_user.subscription_tier =
                'pro'::public.subscription_tier_enum
           AND (
                app_user.subscription_expires_at IS NULL
                OR app_user.subscription_expires_at > quota_now
           ) THEN
            -- Paid scans never create, consume, or erase a complimentary hold.
            resolved_plan := 'pro_paid';
        ELSIF rollout.entitlement_mode = 'legacy_trial' THEN
            resolved_plan := internal.effective_plan(
                app_user.subscription_tier,
                app_user.created_at,
                app_user.subscription_expires_at
            );
        ELSIF main_scan_operation THEN
            IF p_original_analysis_id IS NULL THEN
                RAISE EXCEPTION 'ai_quota_invalid_request'
                    USING ERRCODE = '22023';
            END IF;

            SELECT usage.*
            INTO usage_row
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_original_analysis_id
            FOR UPDATE;

            IF FOUND AND usage_row.state IN ('held', 'consumed') THEN
                resolved_plan := 'pro_complimentary';
                resolved_link := p_original_analysis_id;
            ELSE
                SELECT
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'consumed'
                    )::INTEGER,
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'held'
                    )::INTEGER
                INTO consumed_count, held_count
                FROM internal.complimentary_scan_usage AS usage
                WHERE usage.user_id = p_user_id;

                consumed_count := COALESCE(consumed_count, 0);
                held_count := COALESCE(held_count, 0);

                IF rollout.complimentary_scan_grant
                        - consumed_count - held_count > 0 THEN
                    acquire_hold := TRUE;
                    resolved_plan := 'pro_complimentary';
                    resolved_link := p_original_analysis_id;

                ELSIF p_flash_fallback_eligible THEN
                    resolved_plan := 'free';
                    resolved_flash_fallback := TRUE;
                ELSE
                    RAISE EXCEPTION 'ai_entitlement_required'
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;
        ELSE
            SELECT entitlement.*
            INTO entitlement_after
            FROM internal.resolve_effective_entitlement(
                p_user_id
            ) AS entitlement;

            resolved_plan := entitlement_after.current_plan;
            IF resolved_plan = 'free' THEN
                -- The policy matrix remains authoritative for whether this
                -- non-scan operation has a free implementation.
                resolved_plan := 'free';
            END IF;

            IF p_original_analysis_id IS NOT NULL
               AND EXISTS (
                    SELECT 1
                    FROM internal.complimentary_scan_usage AS usage
                    WHERE usage.user_id = p_user_id
                      AND usage.client_scan_id = p_original_analysis_id
                      AND usage.state IN ('held', 'consumed')
               ) THEN
                resolved_link := p_original_analysis_id;
            END IF;
        END IF;
    RETURN QUERY SELECT resolved_plan, resolved_link, resolved_flash_fallback, acquire_hold;
END;
$function$;
REVOKE ALL ON FUNCTION internal.resolve_fresh_quota_entitlement(UUID,TEXT,UUID,BOOLEAN,TIMESTAMPTZ)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.resolve_fresh_quota_entitlement(UUID,TEXT,UUID,BOOLEAN,TIMESTAMPTZ) IS
    'Private fresh entitlement projection under quota-owner locks; no funding mutation, no grant, no replay authority. Only the original quota owner can acquire the indicated hold.';

DO $migration$
DECLARE definition TEXT; old_fragment TEXT; new_fragment TEXT; fragment TEXT; replacement TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE)
    INTO STRICT definition;
    old_fragment := $old$        IF app_user.subscription_tier =
                'pro'::public.subscription_tier_enum
           AND (
                app_user.subscription_expires_at IS NULL
                OR app_user.subscription_expires_at > quota_now
           ) THEN
            -- Paid scans never create, consume, or erase a complimentary hold.
            resolved_plan := 'pro_paid';
        ELSIF rollout.entitlement_mode = 'legacy_trial' THEN
            resolved_plan := internal.effective_plan(
                app_user.subscription_tier,
                app_user.created_at,
                app_user.subscription_expires_at
            );
        ELSIF main_scan_operation THEN
            IF p_original_analysis_id IS NULL THEN
                RAISE EXCEPTION 'ai_quota_invalid_request'
                    USING ERRCODE = '22023';
            END IF;

            SELECT usage.*
            INTO usage_row
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_original_analysis_id
            FOR UPDATE;

            IF FOUND AND usage_row.state IN ('held', 'consumed') THEN
                resolved_plan := 'pro_complimentary';
                resolved_link := p_original_analysis_id;
            ELSE
                SELECT
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'consumed'
                    )::INTEGER,
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'held'
                    )::INTEGER
                INTO consumed_count, held_count
                FROM internal.complimentary_scan_usage AS usage
                WHERE usage.user_id = p_user_id;

                consumed_count := COALESCE(consumed_count, 0);
                held_count := COALESCE(held_count, 0);

                IF rollout.complimentary_scan_grant
                        - consumed_count - held_count > 0 THEN
                    IF usage_row.user_id IS NULL THEN
                        INSERT INTO internal.complimentary_scan_usage (
                            user_id,
                            client_scan_id,
                            state,
                            held_at,
                            created_at,
                            updated_at
                        )
                        VALUES (
                            p_user_id,
                            p_original_analysis_id,
                            'held',
                            quota_now,
                            quota_now,
                            quota_now
                        );
                    ELSE
                        UPDATE internal.complimentary_scan_usage AS usage
                        SET state = 'held',
                            held_at = quota_now,
                            settled_at = NULL,
                            settlement_reason = NULL,
                            reacquisition_count =
                                usage.reacquisition_count + 1,
                            updated_at = quota_now
                        WHERE usage.user_id = p_user_id
                          AND usage.client_scan_id =
                                p_original_analysis_id;
                    END IF;

                    resolved_plan := 'pro_complimentary';
                    resolved_link := p_original_analysis_id;
                    usage_changed := TRUE;
                ELSIF p_flash_fallback_eligible THEN
                    resolved_plan := 'free';
                    resolved_flash_fallback := TRUE;
                ELSE
                    RAISE EXCEPTION 'ai_entitlement_required'
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;
        ELSE
            SELECT entitlement.*
            INTO entitlement_after
            FROM internal.resolve_effective_entitlement(
                p_user_id
            ) AS entitlement;

            resolved_plan := entitlement_after.current_plan;
            IF resolved_plan = 'free' THEN
                -- The policy matrix remains authoritative for whether this
                -- non-scan operation has a free implementation.
                resolved_plan := 'free';
            END IF;

            IF p_original_analysis_id IS NOT NULL
               AND EXISTS (
                    SELECT 1
                    FROM internal.complimentary_scan_usage AS usage
                    WHERE usage.user_id = p_user_id
                      AND usage.client_scan_id = p_original_analysis_id
                      AND usage.state IN ('held', 'consumed')
               ) THEN
                resolved_link := p_original_analysis_id;
            END IF;
        END IF;$old$;
    new_fragment := $new$        SELECT projected.effective_plan, projected.complimentary_client_scan_id,
            projected.flash_fallback_used, projected.acquire_complimentary_hold
        INTO resolved_plan, resolved_link, resolved_flash_fallback, usage_changed
        FROM internal.resolve_fresh_quota_entitlement(
            p_user_id,p_operation,p_original_analysis_id,p_flash_fallback_eligible,quota_now
        ) AS projected;
        IF usage_changed THEN
            -- The projection has locked the original usage row if present.
            -- Retain the existing insertion/reacquisition timestamps and count.
            SELECT usage.* INTO usage_row FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id=p_user_id AND usage.client_scan_id=p_original_analysis_id
            FOR UPDATE;
                    IF usage_row.user_id IS NULL THEN
                        INSERT INTO internal.complimentary_scan_usage (
                            user_id,
                            client_scan_id,
                            state,
                            held_at,
                            created_at,
                            updated_at
                        )
                        VALUES (
                            p_user_id,
                            p_original_analysis_id,
                            'held',
                            quota_now,
                            quota_now,
                            quota_now
                        );
                    ELSE
                        UPDATE internal.complimentary_scan_usage AS usage
                        SET state = 'held',
                            held_at = quota_now,
                            settled_at = NULL,
                            settlement_reason = NULL,
                            reacquisition_count =
                                usage.reacquisition_count + 1,
                            updated_at = quota_now
                        WHERE usage.user_id = p_user_id
                          AND usage.client_scan_id =
                                p_original_analysis_id;
                    END IF;

        END IF;$new$;
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,old_fragment,'')))
        / pg_catalog.length(old_fragment) <> 1 THEN
        RAISE EXCEPTION 'initial entitlement projection source drift';
    END IF;
    definition := pg_catalog.replace(definition,old_fragment,new_fragment);
    -- Keep the same owner-row lock and FOUND behavior without retaining fields
    -- now read exclusively by the shared selector. Remove only its dead locals.
    FOR fragment, replacement IN SELECT * FROM (VALUES
        (E'    app_user RECORD;\n', ''),
        (E'    consumed_count INTEGER := 0;\n', ''),
        (E'    held_count INTEGER := 0;\n', ''),
        ($owner$    SELECT
        users.subscription_tier,
        users.created_at,
        users.subscription_expires_at,
        users.entitlement_version
    INTO app_user
$owner$, E'    PERFORM users.id\n')
    ) AS edits(source_text,replacement_text) LOOP
        IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,fragment,'')))
            / pg_catalog.length(fragment) <> 1 THEN
            RAISE EXCEPTION 'initial entitlement projection local source drift';
        END IF;
        definition := pg_catalog.replace(definition,fragment,replacement);
    END LOOP;
    EXECUTE definition;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;

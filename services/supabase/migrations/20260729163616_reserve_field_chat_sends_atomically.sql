-- Field Chat user-message admission was previously implemented as independent
-- count, capacity, and INSERT requests from Edge Functions. Two devices could
-- therefore both observe spare daily/conversation capacity and commit
-- contradictory sends. Move that boundary into one short database transaction.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.reserve_field_chat_send(
    p_user_id UUID,
    p_conversation_id UUID,
    p_subject_type TEXT,
    p_subject_id UUID,
    p_message_text TEXT,
    p_client_message_id UUID
)
RETURNS TABLE (
    message JSONB,
    is_replay BOOLEAN,
    sends_today INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    normalized_message_text TEXT;
    conversation_user_id UUID;
    conversation_subject_id UUID;
    existing_message JSONB;
    inserted_message JSONB;
    message_count INTEGER;
    daily_count INTEGER;
    daily_window_start TIMESTAMPTZ;
    reservation_now TIMESTAMPTZ;
    has_incomplete_request BOOLEAN;
    max_user_message_chars CONSTANT INTEGER := 600;
    max_messages_per_conversation CONSTANT INTEGER := 30;
    daily_send_limit CONSTANT INTEGER := 20;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_conversation_id IS NULL
       OR p_subject_id IS NULL
       OR p_client_message_id IS NULL
       OR p_subject_type NOT IN ('insight', 'explore')
       OR p_message_text IS NULL THEN
        RAISE EXCEPTION 'field_chat_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    normalized_message_text := pg_catalog.BTRIM(p_message_text);
    IF normalized_message_text = ''
       OR pg_catalog.CHAR_LENGTH(normalized_message_text)
            > max_user_message_chars THEN
        RAISE EXCEPTION 'field_chat_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    -- Every Field Chat admission takes the per-user lock before its
    -- conversation lock. This serializes the cross-table UTC-day counter while
    -- retaining concurrency between different users and prevents deadlocks
    -- between a user's Insight and Explore sends.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:user:' || p_user_id::TEXT,
            0::BIGINT
        )
    );
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:conversation:' || p_conversation_id::TEXT,
            0::BIGINT
        )
    );

    IF p_subject_type = 'insight' THEN
        SELECT
            conversation.user_id,
            conversation.scan_id
        INTO
            conversation_user_id,
            conversation_subject_id
        FROM public.insight_chat_conversations AS conversation
        WHERE conversation.id = p_conversation_id
        FOR UPDATE;

        SELECT pg_catalog.TO_JSONB(chat_message.*)
        INTO existing_message
        FROM public.insight_chat_messages AS chat_message
        WHERE chat_message.conversation_id = p_conversation_id
          AND chat_message.client_message_id = p_client_message_id
          AND chat_message.role = 'user';
    ELSE
        SELECT
            conversation.user_id,
            conversation.post_id
        INTO
            conversation_user_id,
            conversation_subject_id
        FROM public.explore_post_chat_conversations AS conversation
        WHERE conversation.id = p_conversation_id
        FOR UPDATE;

        SELECT pg_catalog.TO_JSONB(chat_message.*)
        INTO existing_message
        FROM public.explore_post_chat_messages AS chat_message
        WHERE chat_message.conversation_id = p_conversation_id
          AND chat_message.client_message_id = p_client_message_id
          AND chat_message.role = 'user';
    END IF;

    IF conversation_user_id IS NULL
       OR conversation_subject_id IS NULL THEN
        RAISE EXCEPTION 'field_chat_conversation_not_found'
            USING ERRCODE = 'P0002';
    END IF;
    IF conversation_user_id <> p_user_id
       OR conversation_subject_id <> p_subject_id THEN
        RAISE EXCEPTION 'field_chat_access_forbidden'
            USING ERRCODE = '42501';
    END IF;

    reservation_now := pg_catalog.CLOCK_TIMESTAMP();
    daily_window_start :=
        pg_catalog.DATE_TRUNC('day', reservation_now, 'UTC');

    SELECT
        (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM public.insight_chat_messages AS insight_message
            WHERE insight_message.user_id = p_user_id
              AND insight_message.role = 'user'
              AND insight_message.created_at >= daily_window_start
        )
        + (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM public.explore_post_chat_messages AS explore_message
            WHERE explore_message.user_id = p_user_id
              AND explore_message.role = 'user'
              AND explore_message.created_at >= daily_window_start
        )
    INTO daily_count;

    -- An exact replay remains available after the caller reaches either cap.
    -- It never consumes another daily send or another message slot.
    IF existing_message IS NOT NULL THEN
        IF existing_message ->> 'user_id' <> p_user_id::TEXT
           OR existing_message ->> 'conversation_id'
                <> p_conversation_id::TEXT
           OR existing_message ->> 'role' <> 'user'
           OR existing_message ->> 'message_text'
                <> normalized_message_text
           OR existing_message ->> 'client_message_id'
                <> p_client_message_id::TEXT THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY
        SELECT existing_message, TRUE, daily_count;
        RETURN;
    END IF;

    IF p_subject_type = 'insight' THEN
        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            pg_catalog.BOOL_OR(
                user_message.role = 'user'
                AND user_message.client_message_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.insight_chat_messages AS assistant_message
                    WHERE assistant_message.conversation_id =
                            user_message.conversation_id
                      AND assistant_message.role = 'assistant'
                      AND pg_catalog.LOWER(
                          assistant_message.safety_metadata ->> 'request_id'
                      ) = user_message.client_message_id::TEXT
                )
            )
        INTO message_count, has_incomplete_request
        FROM public.insight_chat_messages AS user_message
        WHERE user_message.conversation_id = p_conversation_id;
    ELSE
        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            pg_catalog.BOOL_OR(
                user_message.role = 'user'
                AND user_message.client_message_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.explore_post_chat_messages AS assistant_message
                    WHERE assistant_message.conversation_id =
                            user_message.conversation_id
                      AND assistant_message.role = 'assistant'
                      AND pg_catalog.LOWER(
                          assistant_message.safety_metadata ->> 'request_id'
                      ) = user_message.client_message_id::TEXT
                )
            )
        INTO message_count, has_incomplete_request
        FROM public.explore_post_chat_messages AS user_message
        WHERE user_message.conversation_id = p_conversation_id;
    END IF;

    IF COALESCE(has_incomplete_request, FALSE) THEN
        RAISE EXCEPTION 'field_chat_send_in_progress'
            USING ERRCODE = '55000';
    END IF;
    IF message_count + 2 > max_messages_per_conversation THEN
        RAISE EXCEPTION 'field_chat_conversation_limit_reached'
            USING ERRCODE = '54000';
    END IF;
    IF daily_count >= daily_send_limit THEN
        RAISE EXCEPTION 'field_chat_daily_limit_reached'
            USING ERRCODE = 'P0001';
    END IF;

    IF p_subject_type = 'insight' THEN
        INSERT INTO public.insight_chat_messages AS chat_message (
            conversation_id,
            scan_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            p_conversation_id,
            p_subject_id,
            p_user_id,
            'user',
            normalized_message_text,
            p_client_message_id
        )
        RETURNING pg_catalog.TO_JSONB(chat_message.*)
        INTO inserted_message;
    ELSE
        INSERT INTO public.explore_post_chat_messages AS chat_message (
            conversation_id,
            post_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            p_conversation_id,
            p_subject_id,
            p_user_id,
            'user',
            normalized_message_text,
            p_client_message_id
        )
        RETURNING pg_catalog.TO_JSONB(chat_message.*)
        INTO inserted_message;
    END IF;

    RETURN QUERY
    SELECT inserted_message, FALSE, daily_count + 1;
END;
$$;

COMMENT ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) IS
    'Service-only atomic Field Chat idempotency, in-flight, conversation-cap, UTC-day-cap, and user-message admission boundary.';

REVOKE ALL ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) TO service_role;

-- A process can terminate after charging its quota reservation but before
-- saving the assistant row. The generic quota ledger intentionally treats
-- committed operations as final. Permit a narrowly scoped Field Chat rescue
-- only when the exact bound user row exists, its assistant is absent, and the
-- committed provider claim has been stale for at least ten minutes.
CREATE OR REPLACE FUNCTION public.recover_stale_field_chat_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_conversation_id UUID,
    p_subject_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    recovery_now TIMESTAMPTZ;
    exact_user_message_exists BOOLEAN;
    exact_assistant_message_exists BOOLEAN;
    stale_after CONSTANT INTERVAL := INTERVAL '10 minutes';
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_request_id IS NULL
       OR p_conversation_id IS NULL
       OR p_subject_id IS NULL
       OR p_operation NOT IN (
           'insight_chat_reply',
           'explore_post_chat_reply'
       ) THEN
        RAISE EXCEPTION 'field_chat_invalid_recovery_request'
            USING ERRCODE = '22023';
    END IF;

    -- Match reserve_ai_quota's lock key so a recovery transition and a new
    -- reservation for this exact operation cannot pass one another.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            p_user_id::TEXT || ':' || p_operation || ':' || p_request_id::TEXT,
            0::BIGINT
        )
    );

    SELECT reservations.*
    INTO reservation_row
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.user_id = p_user_id
      AND reservations.operation = p_operation
      AND reservations.request_id = p_request_id
    FOR UPDATE;

    IF NOT FOUND OR reservation_row.state <> 'committed' THEN
        RETURN FALSE;
    END IF;

    recovery_now := pg_catalog.CLOCK_TIMESTAMP();
    IF reservation_row.committed_at IS NULL
       OR reservation_row.committed_at > recovery_now - stale_after THEN
        RETURN FALSE;
    END IF;

    IF p_operation = 'insight_chat_reply' THEN
        SELECT
            EXISTS (
                SELECT 1
                FROM public.insight_chat_conversations AS conversation
                JOIN public.insight_chat_messages AS user_message
                  ON user_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.scan_id = p_subject_id
                  AND user_message.user_id = p_user_id
                  AND user_message.scan_id = p_subject_id
                  AND user_message.role = 'user'
                  AND user_message.client_message_id = p_request_id
            ),
            EXISTS (
                SELECT 1
                FROM public.insight_chat_conversations AS conversation
                JOIN public.insight_chat_messages AS assistant_message
                  ON assistant_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.scan_id = p_subject_id
                  AND assistant_message.user_id = p_user_id
                  AND assistant_message.scan_id = p_subject_id
                  AND assistant_message.role = 'assistant'
                  AND pg_catalog.LOWER(
                      assistant_message.safety_metadata ->> 'request_id'
                  ) = p_request_id::TEXT
            )
        INTO
            exact_user_message_exists,
            exact_assistant_message_exists;
    ELSE
        SELECT
            EXISTS (
                SELECT 1
                FROM public.explore_post_chat_conversations AS conversation
                JOIN public.explore_post_chat_messages AS user_message
                  ON user_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.post_id = p_subject_id
                  AND user_message.user_id = p_user_id
                  AND user_message.post_id = p_subject_id
                  AND user_message.role = 'user'
                  AND user_message.client_message_id = p_request_id
            ),
            EXISTS (
                SELECT 1
                FROM public.explore_post_chat_conversations AS conversation
                JOIN public.explore_post_chat_messages AS assistant_message
                  ON assistant_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.post_id = p_subject_id
                  AND assistant_message.user_id = p_user_id
                  AND assistant_message.post_id = p_subject_id
                  AND assistant_message.role = 'assistant'
                  AND pg_catalog.LOWER(
                      assistant_message.safety_metadata ->> 'request_id'
                  ) = p_request_id::TEXT
            )
        INTO
            exact_user_message_exists,
            exact_assistant_message_exists;
    END IF;

    IF NOT exact_user_message_exists OR exact_assistant_message_exists THEN
        RETURN FALSE;
    END IF;

    UPDATE internal.ai_quota_reservations AS reservations
    SET
        state = 'failed',
        failed_at = recovery_now,
        updated_at = recovery_now
    WHERE reservations.id = reservation_row.id
      AND reservations.state = 'committed'
      AND reservations.committed_at <= recovery_now - stale_after;

    RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) IS
    'Service-only rescue for a ten-minute-stale committed Field Chat quota claim whose exact user row exists and assistant row is absent.';

REVOKE ALL ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) TO service_role;

-- Direct authenticated message insertion would bypass the atomic cap and
-- idempotency checks. Field Chat is an Edge-only API, matching the existing
-- Explore boundary; RLS remains enabled as defense in depth.
REVOKE ALL PRIVILEGES
    ON TABLE public.insight_chat_conversations,
             public.insight_chat_messages
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES
    ON TABLE public.explore_post_chat_conversations,
             public.explore_post_chat_messages
    FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.insight_chat_conversations,
             public.explore_post_chat_conversations
    TO service_role;
GRANT SELECT, INSERT
    ON TABLE public.insight_chat_messages,
             public.explore_post_chat_messages
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'Atomic Field Chat idempotency, capacity, daily-limit, and user-message admission.'
    ),
    (
        'service_role',
        'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)',
        'Narrow recovery for a stale charged Field Chat send missing its assistant row.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;

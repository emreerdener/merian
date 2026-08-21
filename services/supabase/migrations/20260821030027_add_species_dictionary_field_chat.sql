-- Private per-viewer Field Chat conversations grounded only in the latest
-- canonical public Species Dictionary text. This forward migration also
-- extends the shared admission, quota-recovery, and anonymous-account merge
-- boundaries to the third Field Chat family.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE public.species_dictionary_chat_conversations (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    species_dictionary_id UUID NOT NULL
        REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT species_dictionary_chat_conversations_subject_user_key
        UNIQUE (species_dictionary_id, user_id),
    CONSTRAINT species_dictionary_chat_conversations_bound_identity_key
        UNIQUE (id, species_dictionary_id, user_id)
);

CREATE TABLE public.species_dictionary_chat_messages (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    conversation_id UUID NOT NULL
        REFERENCES public.species_dictionary_chat_conversations(id)
        ON DELETE CASCADE,
    species_dictionary_id UUID NOT NULL
        REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    message_text TEXT NOT NULL
        CHECK (pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(message_text)) > 0),
    client_message_id UUID,
    model TEXT,
    llm_prompt_tokens INTEGER,
    llm_candidate_tokens INTEGER,
    llm_thinking_tokens INTEGER,
    llm_total_tokens INTEGER,
    llm_cached_tokens INTEGER,
    is_refusal BOOLEAN NOT NULL DEFAULT FALSE,
    refusal_reason TEXT,
    safety_metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT species_dictionary_chat_messages_bound_identity_key
        UNIQUE (id, conversation_id, species_dictionary_id, user_id),
    CONSTRAINT species_dictionary_chat_messages_bound_conversation_fk
        FOREIGN KEY (conversation_id, species_dictionary_id, user_id)
        REFERENCES public.species_dictionary_chat_conversations (
            id,
            species_dictionary_id,
            user_id
        )
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.species_dictionary_chat_message_feedback (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    message_id UUID NOT NULL
        REFERENCES public.species_dictionary_chat_messages(id)
        ON DELETE CASCADE,
    conversation_id UUID NOT NULL
        REFERENCES public.species_dictionary_chat_conversations(id)
        ON DELETE CASCADE,
    species_dictionary_id UUID NOT NULL
        REFERENCES public.species_dictionary(id) ON DELETE CASCADE,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    rating TEXT NOT NULL
        CHECK (rating IN ('helpful', 'not_helpful', 'wrong', 'unsafe', 'other')),
    note TEXT CHECK (note IS NULL OR pg_catalog.CHAR_LENGTH(note) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT species_dictionary_chat_feedback_message_user_key
        UNIQUE (message_id, user_id),
    CONSTRAINT species_dictionary_chat_feedback_bound_message_fk
        FOREIGN KEY (
            message_id,
            conversation_id,
            species_dictionary_id,
            user_id
        )
        REFERENCES public.species_dictionary_chat_messages (
            id,
            conversation_id,
            species_dictionary_id,
            user_id
        )
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX species_dictionary_chat_conversations_user_updated_idx
    ON public.species_dictionary_chat_conversations(user_id, updated_at DESC);

CREATE INDEX species_dictionary_chat_messages_conversation_created_idx
    ON public.species_dictionary_chat_messages(conversation_id, created_at, id);

CREATE INDEX species_dictionary_chat_messages_species_created_idx
    ON public.species_dictionary_chat_messages(
        species_dictionary_id,
        created_at,
        id
    );

CREATE INDEX species_dictionary_chat_messages_user_created_idx
    ON public.species_dictionary_chat_messages(user_id, created_at DESC);

CREATE UNIQUE INDEX species_dictionary_chat_messages_client_id_idx
    ON public.species_dictionary_chat_messages(
        conversation_id,
        client_message_id
    )
    WHERE client_message_id IS NOT NULL;

CREATE INDEX species_dictionary_chat_feedback_conversation_created_idx
    ON public.species_dictionary_chat_message_feedback(
        conversation_id,
        created_at,
        id
    );

CREATE INDEX species_dictionary_chat_feedback_species_created_idx
    ON public.species_dictionary_chat_message_feedback(
        species_dictionary_id,
        created_at,
        id
    );

CREATE INDEX species_dictionary_chat_feedback_user_created_idx
    ON public.species_dictionary_chat_message_feedback(user_id, created_at DESC);

ALTER TABLE public.species_dictionary_chat_conversations
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.species_dictionary_chat_messages
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.species_dictionary_chat_message_feedback
    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Viewers manage their Species Dictionary chat conversations"
    ON public.species_dictionary_chat_conversations
    FOR ALL
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Viewers manage exact Species Dictionary chat messages"
    ON public.species_dictionary_chat_messages
    FOR ALL
    TO authenticated
    USING (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary_chat_conversations AS conversation
            WHERE conversation.id =
                    species_dictionary_chat_messages.conversation_id
              AND conversation.species_dictionary_id =
                    species_dictionary_chat_messages.species_dictionary_id
              AND conversation.user_id = (SELECT auth.uid())
        )
    )
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary_chat_conversations AS conversation
            WHERE conversation.id =
                    species_dictionary_chat_messages.conversation_id
              AND conversation.species_dictionary_id =
                    species_dictionary_chat_messages.species_dictionary_id
              AND conversation.user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "Viewers manage exact Species Dictionary chat feedback"
    ON public.species_dictionary_chat_message_feedback
    FOR ALL
    TO authenticated
    USING (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary_chat_messages AS message
            WHERE message.id =
                    species_dictionary_chat_message_feedback.message_id
              AND message.conversation_id =
                    species_dictionary_chat_message_feedback.conversation_id
              AND message.species_dictionary_id =
                    species_dictionary_chat_message_feedback.species_dictionary_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    )
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.species_dictionary_chat_messages AS message
            WHERE message.id =
                    species_dictionary_chat_message_feedback.message_id
              AND message.conversation_id =
                    species_dictionary_chat_message_feedback.conversation_id
              AND message.species_dictionary_id =
                    species_dictionary_chat_message_feedback.species_dictionary_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    );

-- These tables are an authenticated Edge Function implementation detail.
-- RLS remains enabled as defense in depth if privileges change later.
REVOKE ALL PRIVILEGES
    ON TABLE public.species_dictionary_chat_conversations,
             public.species_dictionary_chat_messages,
             public.species_dictionary_chat_message_feedback
    FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.species_dictionary_chat_conversations
    TO service_role;
GRANT SELECT, INSERT
    ON TABLE public.species_dictionary_chat_messages
    TO service_role;
GRANT SELECT, INSERT, UPDATE
    ON TABLE public.species_dictionary_chat_message_feedback
    TO service_role;

CREATE OR REPLACE FUNCTION public.trg_species_dictionary_chat_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
    NEW.updated_at = pg_catalog.NOW();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_species_dictionary_chat_set_updated_at()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER species_dictionary_chat_conversations_set_updated_at
BEFORE UPDATE ON public.species_dictionary_chat_conversations
FOR EACH ROW
EXECUTE FUNCTION public.trg_species_dictionary_chat_set_updated_at();

CREATE TRIGGER species_dictionary_chat_feedback_set_updated_at
BEFORE UPDATE ON public.species_dictionary_chat_message_feedback
FOR EACH ROW
EXECUTE FUNCTION public.trg_species_dictionary_chat_set_updated_at();

COMMENT ON TABLE public.species_dictionary_chat_conversations IS
    'Private Pro Field Chat conversations grounded in canonical Species Dictionary text.';
COMMENT ON TABLE public.species_dictionary_chat_messages IS
    'Private per-viewer Species Dictionary Field Chat messages.';
COMMENT ON CONSTRAINT species_dictionary_chat_messages_bound_conversation_fk
    ON public.species_dictionary_chat_messages IS
    'Every private dictionary message is bound to its exact conversation, species, and viewer.';
COMMENT ON CONSTRAINT species_dictionary_chat_feedback_bound_message_fk
    ON public.species_dictionary_chat_message_feedback IS
    'Every private dictionary rating copies the exact rated message identity.';

-- Model replies use the same paid chat buckets and model as the existing
-- Insight and Explore families. Deterministic prompt suggestions do not invoke
-- the provider and therefore require no separate quota operation.
INSERT INTO internal.ai_quota_policies (
    operation,
    effective_plan,
    model,
    allowed,
    daily_bucket,
    daily_limit,
    user_rate_bucket,
    user_window_seconds,
    user_window_limit,
    ip_rate_bucket,
    ip_window_seconds,
    ip_window_limit
)
VALUES
    (
        'species_dictionary_chat_reply',
        'free',
        NULL,
        FALSE,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL
    ),
    (
        'species_dictionary_chat_reply',
        'pro_trial',
        'gemini-2.5-flash',
        TRUE,
        'ai_chat:pro_trial',
        60,
        'all_ai:pro_trial',
        60,
        10,
        'all_ai:pro_trial',
        60,
        60
    ),
    (
        'species_dictionary_chat_reply',
        'pro_complimentary',
        'gemini-2.5-flash',
        TRUE,
        'ai_chat:pro_complimentary',
        60,
        'all_ai:pro_complimentary',
        60,
        10,
        'all_ai:pro_complimentary',
        60,
        60
    ),
    (
        'species_dictionary_chat_reply',
        'pro_paid',
        'gemini-2.5-flash',
        TRUE,
        'ai_chat:pro_paid',
        120,
        'all_ai:pro_paid',
        60,
        20,
        'all_ai:pro_paid',
        60,
        120
    )
ON CONFLICT (operation, effective_plan) DO UPDATE
SET
    model = EXCLUDED.model,
    allowed = EXCLUDED.allowed,
    enabled = EXCLUDED.enabled,
    daily_bucket = EXCLUDED.daily_bucket,
    daily_limit = EXCLUDED.daily_limit,
    user_rate_bucket = EXCLUDED.user_rate_bucket,
    user_window_seconds = EXCLUDED.user_window_seconds,
    user_window_limit = EXCLUDED.user_window_limit,
    ip_rate_bucket = EXCLUDED.ip_rate_bucket,
    ip_window_seconds = EXCLUDED.ip_window_seconds,
    ip_window_limit = EXCLUDED.ip_window_limit,
    policy_version = internal.ai_quota_policies.policy_version + 1,
    updated_at = pg_catalog.NOW();

INSERT INTO internal.ghost_profile_merge_reference_policies (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column,
    strategy,
    execution_order,
    handler_key,
    purpose
)
VALUES
    (
        'public',
        'species_dictionary_chat_conversations',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Dictionary chat conversations follow the permanent profile after conversation conflicts are merged.'
    ),
    (
        'public',
        'species_dictionary_chat_message_feedback',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Dictionary chat feedback follows the permanent profile after duplicate resolution.'
    ),
    (
        'public',
        'species_dictionary_chat_messages',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Dictionary chat message ownership follows the permanent profile.'
    )
ON CONFLICT (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column
) DO UPDATE
SET
    strategy = EXCLUDED.strategy,
    execution_order = EXCLUDED.execution_order,
    handler_key = EXCLUDED.handler_key,
    purpose = EXCLUDED.purpose;

CREATE OR REPLACE FUNCTION internal.merge_ghost_chat_conversations(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    conversation_pair RECORD;
BEGIN
    FOR conversation_pair IN
        SELECT
            ghost_conversation.id AS ghost_id,
            target_conversation.id AS target_id
        FROM public.insight_chat_conversations AS ghost_conversation
        JOIN public.insight_chat_conversations AS target_conversation
          ON target_conversation.scan_id = ghost_conversation.scan_id
         AND target_conversation.user_id = p_target_user_id
        WHERE ghost_conversation.user_id = p_ghost_user_id
    LOOP
        DELETE FROM public.insight_chat_messages AS ghost_message
        USING public.insight_chat_messages AS target_message
        WHERE ghost_message.conversation_id = conversation_pair.ghost_id
          AND target_message.conversation_id = conversation_pair.target_id
          AND ghost_message.client_message_id IS NOT NULL
          AND target_message.client_message_id =
                ghost_message.client_message_id;

        UPDATE public.insight_chat_message_feedback AS feedback
        SET conversation_id = conversation_pair.target_id
        WHERE feedback.conversation_id = conversation_pair.ghost_id;

        UPDATE public.insight_chat_feature_feedback AS feedback
        SET conversation_id = conversation_pair.target_id
        WHERE feedback.conversation_id = conversation_pair.ghost_id;

        UPDATE public.insight_chat_messages AS message
        SET conversation_id = conversation_pair.target_id
        WHERE message.conversation_id = conversation_pair.ghost_id;

        DELETE FROM public.insight_chat_conversations
        WHERE id = conversation_pair.ghost_id;
    END LOOP;

    FOR conversation_pair IN
        SELECT
            ghost_conversation.id AS ghost_id,
            target_conversation.id AS target_id
        FROM public.explore_post_chat_conversations AS ghost_conversation
        JOIN public.explore_post_chat_conversations AS target_conversation
          ON target_conversation.post_id = ghost_conversation.post_id
         AND target_conversation.user_id = p_target_user_id
        WHERE ghost_conversation.user_id = p_ghost_user_id
    LOOP
        DELETE FROM public.explore_post_chat_messages AS ghost_message
        USING public.explore_post_chat_messages AS target_message
        WHERE ghost_message.conversation_id = conversation_pair.ghost_id
          AND target_message.conversation_id = conversation_pair.target_id
          AND ghost_message.client_message_id IS NOT NULL
          AND target_message.client_message_id =
                ghost_message.client_message_id;

        UPDATE public.explore_post_chat_message_feedback AS feedback
        SET conversation_id = conversation_pair.target_id
        WHERE feedback.conversation_id = conversation_pair.ghost_id;

        UPDATE public.explore_post_chat_messages AS message
        SET conversation_id = conversation_pair.target_id
        WHERE message.conversation_id = conversation_pair.ghost_id;

        DELETE FROM public.explore_post_chat_conversations
        WHERE id = conversation_pair.ghost_id;
    END LOOP;

    FOR conversation_pair IN
        SELECT
            ghost_conversation.id AS ghost_id,
            target_conversation.id AS target_id
        FROM public.species_dictionary_chat_conversations AS ghost_conversation
        JOIN public.species_dictionary_chat_conversations AS target_conversation
          ON target_conversation.species_dictionary_id =
                ghost_conversation.species_dictionary_id
         AND target_conversation.user_id = p_target_user_id
        WHERE ghost_conversation.user_id = p_ghost_user_id
    LOOP
        DELETE FROM public.species_dictionary_chat_messages AS ghost_message
        USING public.species_dictionary_chat_messages AS target_message
        WHERE ghost_message.conversation_id = conversation_pair.ghost_id
          AND target_message.conversation_id = conversation_pair.target_id
          AND ghost_message.client_message_id IS NOT NULL
          AND target_message.client_message_id =
                ghost_message.client_message_id;

        UPDATE public.species_dictionary_chat_message_feedback AS feedback
        SET conversation_id = conversation_pair.target_id
        WHERE feedback.conversation_id = conversation_pair.ghost_id;

        UPDATE public.species_dictionary_chat_messages AS message
        SET conversation_id = conversation_pair.target_id
        WHERE message.conversation_id = conversation_pair.ghost_id;

        DELETE FROM public.species_dictionary_chat_conversations
        WHERE id = conversation_pair.ghost_id;
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION internal.merge_ghost_chat_conversations(UUID, UUID) IS
    'Conflict-normalizes Insight, Explore, and Species Dictionary chat conversations before schema-aware account reparenting.';

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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
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
       OR p_subject_type NOT IN (
           'insight',
           'explore',
           'species_dictionary'
       )
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

    -- All chat families use the same user-first then conversation lock order.
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
    ELSIF p_subject_type = 'explore' THEN
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
    ELSE
        SELECT
            conversation.user_id,
            conversation.species_dictionary_id
        INTO
            conversation_user_id,
            conversation_subject_id
        FROM public.species_dictionary_chat_conversations AS conversation
        WHERE conversation.id = p_conversation_id
        FOR UPDATE;

        SELECT pg_catalog.TO_JSONB(chat_message.*)
        INTO existing_message
        FROM public.species_dictionary_chat_messages AS chat_message
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
        + (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM public.species_dictionary_chat_messages AS dictionary_message
            WHERE dictionary_message.user_id = p_user_id
              AND dictionary_message.role = 'user'
              AND dictionary_message.created_at >= daily_window_start
        )
    INTO daily_count;

    -- An exact replay remains available after either cap is reached.
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
    ELSIF p_subject_type = 'explore' THEN
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
    ELSE
        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            pg_catalog.BOOL_OR(
                user_message.role = 'user'
                AND user_message.client_message_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.species_dictionary_chat_messages
                        AS assistant_message
                    WHERE assistant_message.conversation_id =
                            user_message.conversation_id
                      AND assistant_message.role = 'assistant'
                      AND pg_catalog.LOWER(
                          assistant_message.safety_metadata ->> 'request_id'
                      ) = user_message.client_message_id::TEXT
                )
            )
        INTO message_count, has_incomplete_request
        FROM public.species_dictionary_chat_messages AS user_message
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
    ELSIF p_subject_type = 'explore' THEN
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
    ELSE
        INSERT INTO public.species_dictionary_chat_messages AS chat_message (
            conversation_id,
            species_dictionary_id,
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
$function$;

COMMENT ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) IS
    'Service-only atomic three-family Field Chat idempotency, in-flight, conversation-cap, UTC-day-cap, and user-message admission boundary.';

REVOKE ALL ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) TO service_role;

CREATE OR REPLACE FUNCTION public.recover_stale_field_chat_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_conversation_id UUID,
    p_subject_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
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
           'explore_post_chat_reply',
           'species_dictionary_chat_reply'
       ) THEN
        RAISE EXCEPTION 'field_chat_invalid_recovery_request'
            USING ERRCODE = '22023';
    END IF;

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
    ELSIF p_operation = 'explore_post_chat_reply' THEN
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
    ELSE
        SELECT
            EXISTS (
                SELECT 1
                FROM public.species_dictionary_chat_conversations
                    AS conversation
                JOIN public.species_dictionary_chat_messages AS user_message
                  ON user_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.species_dictionary_id = p_subject_id
                  AND user_message.user_id = p_user_id
                  AND user_message.species_dictionary_id = p_subject_id
                  AND user_message.role = 'user'
                  AND user_message.client_message_id = p_request_id
            ),
            EXISTS (
                SELECT 1
                FROM public.species_dictionary_chat_conversations
                    AS conversation
                JOIN public.species_dictionary_chat_messages
                    AS assistant_message
                  ON assistant_message.conversation_id = conversation.id
                WHERE conversation.id = p_conversation_id
                  AND conversation.user_id = p_user_id
                  AND conversation.species_dictionary_id = p_subject_id
                  AND assistant_message.user_id = p_user_id
                  AND assistant_message.species_dictionary_id = p_subject_id
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
$function$;

COMMENT ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) IS
    'Service-only rescue for a ten-minute-stale committed Insight, Explore, or Species Dictionary Field Chat quota claim whose exact user row exists and assistant row is absent.';

REVOKE ALL ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota(
    UUID, TEXT, UUID, UUID, UUID
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'Atomic three-family Field Chat idempotency, capacity, daily-limit, and user-message admission.'
    ),
    (
        'service_role',
        'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)',
        'Narrow recovery for a stale charged Field Chat send missing its assistant row.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

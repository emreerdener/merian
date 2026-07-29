\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(16);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'EXECUTE'
    ),
    'atomic Field Chat admission has an exact service-only API ACL'
);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)',
        'EXECUTE'
    ),
    'stale Field Chat quota rescue has an exact service-only API ACL'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.insight_chat_conversations',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.insight_chat_conversations',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.insight_chat_messages',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.insight_chat_messages',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.explore_post_chat_conversations',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.explore_post_chat_conversations',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.explore_post_chat_messages',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.explore_post_chat_messages',
        'INSERT'
    ),
    'unprivileged API roles cannot bypass either Edge-only Field Chat API'
);

SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_conversations',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_conversations',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_conversations',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_conversations',
        'DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_conversations',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_conversations',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_conversations',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_conversations',
        'DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_messages',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_messages',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_messages',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_messages',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_messages',
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_messages',
        'DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_messages',
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_messages',
        'DELETE'
    ),
    'service-role Field Chat table ACLs are explicit and least privilege'
);

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
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-4000-8000-00000000fc01',
    'authenticated',
    'authenticated',
    'field-chat-reservation@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}',
    '{}',
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
    created_at,
    subscription_tier,
    subscription_expires_at
)
VALUES (
    '00000000-0000-4000-8000-00000000fc01',
    'field-chat-reservation@naturebook.invalid',
    'field_chat_fc01',
    'Field Chat Test',
    'alias',
    pg_catalog.NOW() - INTERVAL '30 days',
    'pro',
    pg_catalog.NOW() + INTERVAL '30 days'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source,
    created_at = EXCLUDED.created_at,
    subscription_tier = EXCLUDED.subscription_tier,
    subscription_expires_at = EXCLUDED.subscription_expires_at;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES (
    '00000000-0000-4000-8000-00000000fc02',
    '00000000-0000-4000-8000-00000000fc01',
    0.95,
    pg_catalog.NOW(),
    TRUE
);

INSERT INTO public.insight_chat_conversations (
    id,
    scan_id,
    user_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fc03',
    '00000000-0000-4000-8000-00000000fc02',
    '00000000-0000-4000-8000-00000000fc01'
);

CREATE TEMPORARY TABLE first_admission ON COMMIT DROP AS
SELECT *
FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fc01',
    '00000000-0000-4000-8000-00000000fc03',
    'insight',
    '00000000-0000-4000-8000-00000000fc02',
    '  Which visible traits support this identification?  ',
    '00000000-0000-4000-8000-00000000fc04'
);

SELECT extensions.ok(
    NOT (SELECT is_replay FROM first_admission)
    AND (SELECT sends_today FROM first_admission) = 1
    AND (
        SELECT message ->> 'conversation_id'
        FROM first_admission
    ) = '00000000-0000-4000-8000-00000000fc03'
    AND (
        SELECT message ->> 'scan_id'
        FROM first_admission
    ) = '00000000-0000-4000-8000-00000000fc02'
    AND (
        SELECT message ->> 'user_id'
        FROM first_admission
    ) = '00000000-0000-4000-8000-00000000fc01'
    AND (
        SELECT message ->> 'message_text'
        FROM first_admission
    ) = 'Which visible traits support this identification?'
    AND (
        SELECT message ->> 'client_message_id'
        FROM first_admission
    ) = '00000000-0000-4000-8000-00000000fc04',
    'first atomic admission trims, binds, persists, and counts one user send'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.insight_chat_messages AS message
        WHERE message.conversation_id =
              '00000000-0000-4000-8000-00000000fc03'
          AND message.client_message_id =
              '00000000-0000-4000-8000-00000000fc04'
    ),
    1,
    'atomic admission persists exactly one bound user row'
);

CREATE TEMPORARY TABLE replayed_admission ON COMMIT DROP AS
SELECT *
FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fc01',
    '00000000-0000-4000-8000-00000000fc03',
    'insight',
    '00000000-0000-4000-8000-00000000fc02',
    'Which visible traits support this identification?',
    '00000000-0000-4000-8000-00000000fc04'
);

SELECT extensions.ok(
    (SELECT is_replay FROM replayed_admission)
    AND (SELECT sends_today FROM replayed_admission) = 1
    AND (
        SELECT message ->> 'id'
        FROM replayed_admission
    ) = (
        SELECT message ->> 'id'
        FROM first_admission
    ),
    'exact retry key replays the same user row without consuming capacity'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc03',
            'insight',
            '00000000-0000-4000-8000-00000000fc02',
            'A contradictory question',
            '00000000-0000-4000-8000-00000000fc04'
        )
    $statement$,
    '23505',
    'field_chat_idempotency_conflict',
    'retry key cannot be rebound to contradictory text'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc03',
            'insight',
            '00000000-0000-4000-8000-00000000fc02',
            'Can a second request pass the first one?',
            '00000000-0000-4000-8000-00000000fc06'
        )
    $statement$,
    '55000',
    'field_chat_send_in_progress',
    'a different request cannot pass an unanswered user row'
);

INSERT INTO public.insight_chat_messages (
    id,
    conversation_id,
    scan_id,
    user_id,
    role,
    message_text,
    safety_metadata
)
VALUES (
    '00000000-0000-4000-8000-00000000fc05',
    '00000000-0000-4000-8000-00000000fc03',
    '00000000-0000-4000-8000-00000000fc02',
    '00000000-0000-4000-8000-00000000fc01',
    'assistant',
    'The saved evidence supports that identification.',
    '{"request_id":"00000000-0000-4000-8000-00000000fc04"}'
);

CREATE TEMPORARY TABLE second_admission ON COMMIT DROP AS
SELECT *
FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fc01',
    '00000000-0000-4000-8000-00000000fc03',
    'insight',
    '00000000-0000-4000-8000-00000000fc02',
    'What habitat is typical?',
    '00000000-0000-4000-8000-00000000fc06'
);

SELECT extensions.ok(
    NOT (SELECT is_replay FROM second_admission)
    AND (SELECT sends_today FROM second_admission) = 2,
    'a completed request permits the next sequential admission'
);

INSERT INTO public.insight_chat_messages (
    id,
    conversation_id,
    scan_id,
    user_id,
    role,
    message_text,
    safety_metadata
)
VALUES (
    '00000000-0000-4000-8000-00000000fc07',
    '00000000-0000-4000-8000-00000000fc03',
    '00000000-0000-4000-8000-00000000fc02',
    '00000000-0000-4000-8000-00000000fc01',
    'assistant',
    'This habitat answer completes request two.',
    '{"request_id":"00000000-0000-4000-8000-00000000fc06"}'
);

DO $fixture$
DECLARE
    pair_number INTEGER;
    pair_request_id UUID;
BEGIN
    FOR pair_number IN 3..15
    LOOP
        pair_request_id := pg_catalog.GEN_RANDOM_UUID();
        INSERT INTO public.insight_chat_messages (
            id,
            conversation_id,
            scan_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            pg_catalog.GEN_RANDOM_UUID(),
            '00000000-0000-4000-8000-00000000fc03',
            '00000000-0000-4000-8000-00000000fc02',
            '00000000-0000-4000-8000-00000000fc01',
            'user',
            'Conversation-cap fixture question ' || pair_number::TEXT,
            pair_request_id
        );

        INSERT INTO public.insight_chat_messages (
            id,
            conversation_id,
            scan_id,
            user_id,
            role,
            message_text,
            safety_metadata
        )
        VALUES (
            pg_catalog.GEN_RANDOM_UUID(),
            '00000000-0000-4000-8000-00000000fc03',
            '00000000-0000-4000-8000-00000000fc02',
            '00000000-0000-4000-8000-00000000fc01',
            'assistant',
            'Conversation-cap fixture answer ' || pair_number::TEXT,
            pg_catalog.JSONB_BUILD_OBJECT(
                'request_id',
                pair_request_id::TEXT
            )
        );
    END LOOP;
END;
$fixture$;

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc03',
            'insight',
            '00000000-0000-4000-8000-00000000fc02',
            'This pair would exceed thirty rows.',
            '00000000-0000-4000-8000-00000000fc10'
        )
    $statement$,
    '54000',
    'field_chat_conversation_limit_reached',
    'atomic admission reserves both rows at the conversation cap'
);

CREATE TEMPORARY TABLE recovery_fixture (
    scan_id UUID NOT NULL,
    conversation_id UUID NOT NULL
) ON COMMIT DROP;

DO $fixture$
DECLARE
    fixture_number INTEGER;
    fixture_scan_id UUID;
    fixture_conversation_id UUID;
    fixture_request_id UUID;
BEGIN
    FOR fixture_number IN 1..5
    LOOP
        fixture_scan_id := pg_catalog.GEN_RANDOM_UUID();
        fixture_conversation_id := pg_catalog.GEN_RANDOM_UUID();
        fixture_request_id := CASE
            WHEN fixture_number = 1
                THEN '00000000-0000-4000-8000-00000000fc11'::UUID
            ELSE pg_catalog.GEN_RANDOM_UUID()
        END;

        INSERT INTO public.scans (
            id,
            user_id,
            ai_confidence_score,
            timestamp,
            is_biological_subject
        )
        VALUES (
            fixture_scan_id,
            '00000000-0000-4000-8000-00000000fc01',
            0.95,
            pg_catalog.NOW(),
            TRUE
        );

        INSERT INTO public.insight_chat_conversations (
            id,
            scan_id,
            user_id
        )
        VALUES (
            fixture_conversation_id,
            fixture_scan_id,
            '00000000-0000-4000-8000-00000000fc01'
        );

        INSERT INTO public.insight_chat_messages (
            id,
            conversation_id,
            scan_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            pg_catalog.GEN_RANDOM_UUID(),
            fixture_conversation_id,
            fixture_scan_id,
            '00000000-0000-4000-8000-00000000fc01',
            'user',
            'Daily-limit fixture question ' || fixture_number::TEXT,
            fixture_request_id
        );

        IF fixture_number = 1 THEN
            INSERT INTO recovery_fixture (scan_id, conversation_id)
            VALUES (fixture_scan_id, fixture_conversation_id);
        END IF;
    END LOOP;
END;
$fixture$;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES (
    '00000000-0000-4000-8000-00000000fc12',
    '00000000-0000-4000-8000-00000000fc01',
    0.95,
    pg_catalog.NOW(),
    TRUE
);

INSERT INTO public.insight_chat_conversations (
    id,
    scan_id,
    user_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fc13',
    '00000000-0000-4000-8000-00000000fc12',
    '00000000-0000-4000-8000-00000000fc01'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc13',
            'insight',
            '00000000-0000-4000-8000-00000000fc12',
            'This request would exceed twenty sends today.',
            '00000000-0000-4000-8000-00000000fc14'
        )
    $statement$,
    'P0001',
    'field_chat_daily_limit_reached',
    'cross-conversation daily admission stops at twenty user sends'
);

CREATE TEMPORARY TABLE recovery_quota ON COMMIT DROP AS
SELECT *
FROM public.reserve_ai_quota(
    '00000000-0000-4000-8000-00000000fc01',
    'insight_chat_reply',
    '00000000-0000-4000-8000-00000000fc11',
    pg_catalog.REPEAT('f', 64)
);

SELECT extensions.ok(
    NOT (SELECT is_replay FROM recovery_quota)
    AND (
        SELECT reservation_state
        FROM recovery_quota
    ) = 'reserved'
    AND public.finalize_ai_quota_reservation(
        (SELECT reservation_id FROM recovery_quota),
        '00000000-0000-4000-8000-00000000fc01',
        (SELECT lease_token FROM recovery_quota),
        'committed'
    ),
    'recovery fixture owns a committed quota reservation'
);

UPDATE internal.ai_quota_reservations AS reservation
SET
    committed_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '11 minutes',
    updated_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '11 minutes'
WHERE reservation.id = (
    SELECT reservation_id
    FROM recovery_quota
);

SELECT extensions.is(
    public.recover_stale_field_chat_quota(
        '00000000-0000-4000-8000-00000000fc01',
        'insight_chat_reply',
        '00000000-0000-4000-8000-00000000fc11',
        (SELECT conversation_id FROM recovery_fixture),
        (SELECT scan_id FROM recovery_fixture)
    ),
    TRUE,
    'ten-minute-stale committed quota with an exact missing assistant is recoverable'
);

SELECT extensions.is(
    (
        SELECT reservation.state
        FROM internal.ai_quota_reservations AS reservation
        WHERE reservation.id = (
            SELECT reservation_id
            FROM recovery_quota
        )
    ),
    'failed',
    'stale Field Chat recovery transitions the exact quota row to failed'
);

SELECT extensions.is(
    public.recover_stale_field_chat_quota(
        '00000000-0000-4000-8000-00000000fc01',
        'insight_chat_reply',
        '00000000-0000-4000-8000-00000000fc11',
        (SELECT conversation_id FROM recovery_fixture),
        (SELECT scan_id FROM recovery_fixture)
    ),
    FALSE,
    'the same stale quota recovery is idempotent'
);

SELECT * FROM extensions.finish();
ROLLBACK;

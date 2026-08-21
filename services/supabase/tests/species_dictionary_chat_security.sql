\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(12);

SELECT extensions.ok(
    (
        SELECT pg_catalog.COUNT(*) = 3
        FROM pg_catalog.pg_class AS relation_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = relation_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND relation_row.relname IN (
              'species_dictionary_chat_conversations',
              'species_dictionary_chat_messages',
              'species_dictionary_chat_message_feedback'
          )
          AND relation_row.relrowsecurity
    ),
    'all Species Dictionary chat tables have effective RLS enabled'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_dictionary_chat_conversations',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_dictionary_chat_conversations',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_dictionary_chat_messages',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_dictionary_chat_messages',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_dictionary_chat_message_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_dictionary_chat_message_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    ),
    'browser roles cannot bypass the dictionary Field Chat Edge boundary'
);

SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_conversations',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_messages',
        'SELECT, INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_messages',
        'UPDATE, DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_message_feedback',
        'SELECT, INSERT, UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_message_feedback',
        'DELETE'
    ),
    'dictionary chat service-role grants are explicit and least privilege'
);

SELECT extensions.ok(
    (
        SELECT pg_catalog.COUNT(*) = 2
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conname IN (
            'species_dictionary_chat_messages_bound_conversation_fk',
            'species_dictionary_chat_feedback_bound_message_fk'
        )
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND constraint_row.condeferrable
          AND constraint_row.condeferred
    ),
    'dictionary message and feedback identities have deferred composite bindings'
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
    '00000000-0000-4000-8000-00000000fd01',
    'authenticated',
    'authenticated',
    'dictionary-chat@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000fd01',
    'dictionary-chat@naturebook.invalid',
    'dictionary_chat_fd01',
    'Dictionary Chat Test',
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
    '00000000-0000-4000-8000-00000000fd09',
    'authenticated',
    'authenticated',
    'dictionary-chat-target@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000fd09',
    'dictionary-chat-target@naturebook.invalid',
    'dictionary_chat_fd09',
    'Dictionary Chat Target',
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

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus
)
VALUES
    (
        '00000000-0000-4000-8000-00000000fd02',
        'Ardea alba fixture',
        '{"en":"Great Egret Fixture"}',
        'Animalia',
        'Chordata',
        'Aves',
        'Pelecaniformes',
        'Ardeidae',
        'Ardea'
    ),
    (
        '00000000-0000-4000-8000-00000000fd03',
        'Ardea herodias fixture',
        '{"en":"Great Blue Heron Fixture"}',
        'Animalia',
        'Chordata',
        'Aves',
        'Pelecaniformes',
        'Ardeidae',
        'Ardea'
    );

INSERT INTO public.species_dictionary_chat_conversations (
    id,
    species_dictionary_id,
    user_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fd04',
    '00000000-0000-4000-8000-00000000fd02',
    '00000000-0000-4000-8000-00000000fd01'
);

CREATE TEMPORARY TABLE dictionary_admission ON COMMIT DROP AS
SELECT *
FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd04',
    'species_dictionary',
    '00000000-0000-4000-8000-00000000fd02',
    '  How can I distinguish this species?  ',
    '00000000-0000-4000-8000-00000000fd05'
);

SELECT extensions.ok(
    NOT (SELECT is_replay FROM dictionary_admission)
    AND (SELECT sends_today FROM dictionary_admission) = 1
    AND (
        SELECT message ->> 'species_dictionary_id'
        FROM dictionary_admission
    ) = '00000000-0000-4000-8000-00000000fd02'
    AND (
        SELECT message ->> 'message_text'
        FROM dictionary_admission
    ) = 'How can I distinguish this species?',
    'atomic dictionary admission trims and binds the exact species row'
);

SELECT extensions.ok(
    (
        SELECT is_replay
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fd01',
            '00000000-0000-4000-8000-00000000fd04',
            'species_dictionary',
            '00000000-0000-4000-8000-00000000fd02',
            'How can I distinguish this species?',
            '00000000-0000-4000-8000-00000000fd05'
        )
    ),
    'exact dictionary retry replays without another send'
);

SET CONSTRAINTS species_dictionary_chat_messages_bound_conversation_fk
    IMMEDIATE;

SELECT extensions.throws_ok(
    $statement$
        INSERT INTO public.species_dictionary_chat_messages (
            conversation_id,
            species_dictionary_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            '00000000-0000-4000-8000-00000000fd04',
            '00000000-0000-4000-8000-00000000fd03',
            '00000000-0000-4000-8000-00000000fd01',
            'user',
            'Cross-species message',
            '00000000-0000-4000-8000-00000000fd06'
        )
    $statement$,
    '23503',
    'insert or update on table "species_dictionary_chat_messages" violates foreign key constraint "species_dictionary_chat_messages_bound_conversation_fk"',
    'composite binding rejects a cross-species message'
);

SELECT extensions.throws_ok(
    $statement$
        INSERT INTO public.species_dictionary_chat_messages (
            conversation_id,
            species_dictionary_id,
            user_id,
            role,
            message_text,
            client_message_id
        )
        VALUES (
            '00000000-0000-4000-8000-00000000fd04',
            '00000000-0000-4000-8000-00000000fd02',
            '00000000-0000-4000-8000-00000000fd09',
            'user',
            'Cross-viewer message',
            '00000000-0000-4000-8000-00000000fd0a'
        )
    $statement$,
    '23503',
    'insert or update on table "species_dictionary_chat_messages" violates foreign key constraint "species_dictionary_chat_messages_bound_conversation_fk"',
    'composite binding rejects a cross-viewer message'
);

INSERT INTO public.species_dictionary_chat_messages (
    id,
    conversation_id,
    species_dictionary_id,
    user_id,
    role,
    message_text,
    safety_metadata
)
VALUES (
    '00000000-0000-4000-8000-00000000fd07',
    '00000000-0000-4000-8000-00000000fd04',
    '00000000-0000-4000-8000-00000000fd02',
    '00000000-0000-4000-8000-00000000fd01',
    'assistant',
    'The dictionary evidence distinguishes these species.',
    '{"request_id":"00000000-0000-4000-8000-00000000fd05"}'
);

INSERT INTO public.species_dictionary_chat_message_feedback (
    id,
    message_id,
    conversation_id,
    species_dictionary_id,
    user_id,
    rating
)
VALUES (
    '00000000-0000-4000-8000-00000000fd08',
    '00000000-0000-4000-8000-00000000fd07',
    '00000000-0000-4000-8000-00000000fd04',
    '00000000-0000-4000-8000-00000000fd02',
    '00000000-0000-4000-8000-00000000fd01',
    'helpful'
);

SELECT extensions.is(
    (
        SELECT rating
        FROM public.species_dictionary_chat_message_feedback
        WHERE id = '00000000-0000-4000-8000-00000000fd08'
    ),
    'helpful',
    'feedback is retained only for the exact owned assistant identity'
);

SET CONSTRAINTS species_dictionary_chat_messages_bound_conversation_fk
    DEFERRED;

INSERT INTO public.species_dictionary_chat_conversations (
    id,
    species_dictionary_id,
    user_id
)
VALUES
    (
        '00000000-0000-4000-8000-00000000fd10',
        '00000000-0000-4000-8000-00000000fd03',
        '00000000-0000-4000-8000-00000000fd01'
    ),
    (
        '00000000-0000-4000-8000-00000000fd11',
        '00000000-0000-4000-8000-00000000fd03',
        '00000000-0000-4000-8000-00000000fd09'
    );

INSERT INTO public.species_dictionary_chat_messages (
    id,
    conversation_id,
    species_dictionary_id,
    user_id,
    role,
    message_text,
    client_message_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fd12',
    '00000000-0000-4000-8000-00000000fd10',
    '00000000-0000-4000-8000-00000000fd03',
    '00000000-0000-4000-8000-00000000fd01',
    'user',
    'Move this private thread with the account.',
    '00000000-0000-4000-8000-00000000fd13'
);

SELECT internal.merge_ghost_chat_conversations(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd09'
);

UPDATE public.species_dictionary_chat_messages
SET user_id = '00000000-0000-4000-8000-00000000fd09'
WHERE conversation_id = '00000000-0000-4000-8000-00000000fd11';

SET CONSTRAINTS ALL IMMEDIATE;

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd10'
    )
    AND EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_messages
        WHERE id = '00000000-0000-4000-8000-00000000fd12'
          AND conversation_id =
              '00000000-0000-4000-8000-00000000fd11'
          AND user_id = '00000000-0000-4000-8000-00000000fd09'
    ),
    'account-merge helper preserves a private dictionary thread on the target viewer'
);

DELETE FROM public.species_dictionary
WHERE id = '00000000-0000-4000-8000-00000000fd02';

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_conversations
        WHERE species_dictionary_id =
              '00000000-0000-4000-8000-00000000fd02'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_messages
        WHERE species_dictionary_id =
              '00000000-0000-4000-8000-00000000fd02'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_message_feedback
        WHERE species_dictionary_id =
              '00000000-0000-4000-8000-00000000fd02'
    ),
    'species deletion cascades through the private dictionary thread'
);

SELECT extensions.ok(
    EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'public'
          AND policy.source_table =
              'species_dictionary_chat_conversations'
          AND policy.source_column = 'user_id'
          AND policy.strategy = 'reparent'
    )
    AND EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'public'
          AND policy.source_table = 'species_dictionary_chat_messages'
          AND policy.source_column = 'user_id'
          AND policy.strategy = 'reparent'
    )
    AND EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'public'
          AND policy.source_table =
              'species_dictionary_chat_message_feedback'
          AND policy.source_column = 'user_id'
          AND policy.strategy = 'reparent'
    ),
    'schema-aware account merge manifest covers every dictionary chat row'
);

SELECT * FROM extensions.finish();
ROLLBACK;

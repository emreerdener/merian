\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(37);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_field_chat_daily_usage(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_field_chat_daily_usage(uuid)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_field_chat_daily_usage(uuid)',
        'EXECUTE'
    ),
    'durable Field Chat usage has an exact service-only API ACL'
);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_field_chat_admission_cutover_status()',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_field_chat_admission_cutover_status()',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_field_chat_admission_cutover_status()',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.field_chat_admission_cutover',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.activate_field_chat_admission_cutover(text,text,text,text,text)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.activate_field_chat_admission_cutover(text,text,text,text,text)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.activate_field_chat_admission_cutover(text,text,text,text,text)',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.prune_empty_field_chat_conversations()',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.prune_empty_field_chat_conversations()',
        'EXECUTE'
    )
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.prune_empty_field_chat_conversations()',
        'EXECUTE'
    ),
    'cutover status and activation have bounded service-only APIs while cleanup remains owner-only'
);

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
        'internal.field_chat_daily_admissions',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.field_chat_daily_admissions',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.field_chat_daily_admissions',
        'SELECT, INSERT, UPDATE, DELETE'
    ),
    'daily Field Chat admission accounting is private behind service RPCs'
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
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_dictionary_chat_conversations',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_dictionary_chat_conversations',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.species_dictionary_chat_messages',
        'SELECT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.species_dictionary_chat_messages',
        'INSERT'
    ),
    'unprivileged API roles cannot bypass any Edge-only Field Chat API'
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
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_conversations',
        'INSERT'
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
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_conversations',
        'INSERT'
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
        'public.species_dictionary_chat_conversations',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_conversations',
        'SELECT, UPDATE, DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_messages',
        'SELECT, INSERT'
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
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary_chat_messages',
        'UPDATE, DELETE'
    ),
    'service-role Field Chat ACLs reserve conversation creation for the atomic RPC'
);

SELECT extensions.ok(
    (
        SELECT pg_catalog.COUNT(*) = 9
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conname IN (
            'insight_chat_conversations_bound_scan_owner_fk',
            'insight_chat_feature_feedback_bound_scan_owner_fk',
            'insight_chat_messages_bound_conversation_fk',
            'explore_post_chat_messages_bound_conversation_fk',
            'insight_chat_message_feedback_bound_message_fk',
            'explore_post_chat_message_feedback_bound_message_fk',
            'insight_chat_feature_feedback_bound_conversation_fk',
            'species_dictionary_chat_messages_bound_conversation_fk',
            'species_dictionary_chat_feedback_bound_message_fk'
        )
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND constraint_row.condeferrable
          AND constraint_row.condeferred
    ),
    'Field Chat parent ownership and child identities have validated deferred structural bindings'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.insight_chat_message_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.insight_chat_message_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.insight_chat_feature_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.insight_chat_feature_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.explore_post_chat_message_feedback',
        'SELECT, INSERT, UPDATE, DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.explore_post_chat_message_feedback',
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
    'unprivileged API roles cannot write or read private Field Chat feedback'
);

SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_message_feedback',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_message_feedback',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_message_feedback',
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_message_feedback',
        'DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_feature_feedback',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_feature_feedback',
        'INSERT'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.insight_chat_feature_feedback',
        'UPDATE, DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_message_feedback',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_message_feedback',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_message_feedback',
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_chat_message_feedback',
        'DELETE'
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
    'backend feedback privileges are explicit and least privilege'
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

INSERT INTO public.user_adult_eligibility_receipts (
    id,
    user_id,
    policy_version,
    confirmed_at,
    confirmation_method,
    confirmation_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000fcf0',
    '00000000-0000-4000-8000-00000000fc01',
    '2026-08-03',
    pg_catalog.NOW(),
    'self_attestation',
    'I confirm I am 18 or older',
    'ios',
    '1.0.3',
    '275'
);

INSERT INTO public.user_terms_acceptance_receipts (
    id,
    user_id,
    terms_version,
    accepted_at,
    acceptance_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000fcf1',
    '00000000-0000-4000-8000-00000000fc01',
    '2026-08-03',
    pg_catalog.NOW(),
    'I accept the terms and allow this data sharing',
    'ios',
    '1.0.3',
    '275'
);

INSERT INTO public.user_ai_consent_events (
    id,
    user_id,
    provider,
    disclosure_version,
    event_kind,
    occurred_at,
    disclosure_text,
    action_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000fcf2',
    '00000000-0000-4000-8000-00000000fc01',
    'google_gemini',
    '2026-08-03.1',
    'granted',
    pg_catalog.NOW(),
    'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
    'I accept the terms and allow this data sharing',
    'ios',
    '1.0.3',
    '275'
);

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

SELECT extensions.ok(
    (
        SELECT
            status_row.not_before_utc > status_row.seeded_at
            AND status_row.not_before_utc = pg_catalog.DATE_TRUNC(
                'day',
                status_row.not_before_utc,
                'UTC'
            )
            AND status_row.activated_at IS NULL
            AND status_row.activated_candidate_sha IS NULL
            AND status_row.activated_migration_sha256 IS NULL
            AND status_row.activated_explore_bundle_sha256 IS NULL
            AND status_row.activated_insight_bundle_sha256 IS NULL
            AND status_row.activated_species_dictionary_bundle_sha256 IS NULL
            AND status_row.status = CASE
                WHEN status_row.database_now >= status_row.not_before_utc
                    THEN 'ready'
                ELSE 'pending'
            END
        FROM public.get_field_chat_admission_cutover_status() AS status_row
    ),
    'fresh migration exposes a self-consistent PostgreSQL-clock UTC boundary'
);

-- Make the pending-state behavior deterministic even if this catalog happens
-- to execute across the migration's UTC boundary.
UPDATE internal.field_chat_admission_cutover
SET seeded_at = cutover.database_now,
    not_before_utc = pg_catalog.DATE_TRUNC(
        'day',
        cutover.database_now,
        'UTC'
    ) + INTERVAL '1 day'
FROM (
    SELECT pg_catalog.CLOCK_TIMESTAMP() AS database_now
) AS cutover
WHERE singleton;

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc03',
            'insight',
            '00000000-0000-4000-8000-00000000fc02',
            'This novel request must wait for UTC rollover.',
            '00000000-0000-4000-8000-00000000fc04'
        )
    $statement$,
    '55000',
    'field_chat_admission_cutover_pending',
    'pending cutover rejects a novel admission before conversation creation'
);

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.insight_chat_conversations AS conversation
        WHERE conversation.id =
              '00000000-0000-4000-8000-00000000fc03'
    )
    AND public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fc01'
    ) = 0,
    'pending cutover writes neither a conversation nor a daily admission'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT public.activate_field_chat_admission_cutover(
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
        )
    $statement$,
    '55000',
    'field_chat_admission_cutover_not_ready',
    'database activation rejects a candidate before the UTC boundary'
);

-- Enter the post-rollover eligible state explicitly inside this disposable
-- transaction. Time alone still cannot open novel admissions.
UPDATE internal.field_chat_admission_cutover
SET not_before_utc = seeded_at + INTERVAL '1 microsecond'
WHERE singleton;

SELECT extensions.is(
    (
        SELECT status_row.status
        FROM public.get_field_chat_admission_cutover_status() AS status_row
    ),
    'ready',
    'UTC eligibility remains closed until explicit bundle activation'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT public.activate_field_chat_admission_cutover(
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            '0000000000000000000000000000000000000000000000000000000000000000',
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
        )
    $statement$,
    '22023',
    'field_chat_admission_cutover_invalid_activation',
    'activation rejects a zero placeholder bundle digest'
);

SELECT public.activate_field_chat_admission_cutover(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
);

SELECT extensions.ok(
    (
        SELECT
            status_row.status = 'active'
            AND status_row.activated_candidate_sha =
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            AND status_row.activated_migration_sha256 =
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            AND status_row.activated_explore_bundle_sha256 =
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
            AND status_row.activated_insight_bundle_sha256 =
                'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
            AND status_row.activated_species_dictionary_bundle_sha256 =
                'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
            AND status_row.activated_at >= status_row.not_before_utc
        FROM public.get_field_chat_admission_cutover_status() AS status_row
    ),
    'explicit activation binds the open state to candidate, migration, and three live bundle digests'
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

UPDATE internal.field_chat_admission_cutover
SET not_before_utc = pg_catalog.CLOCK_TIMESTAMP() + INTERVAL '1 day',
    activated_at = NULL,
    activated_candidate_sha = NULL,
    activated_migration_sha256 = NULL,
    activated_explore_bundle_sha256 = NULL,
    activated_insight_bundle_sha256 = NULL,
    activated_species_dictionary_bundle_sha256 = NULL
WHERE singleton;

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

UPDATE internal.field_chat_admission_cutover
SET not_before_utc = seeded_at + INTERVAL '1 microsecond'
WHERE singleton;

SELECT public.activate_field_chat_admission_cutover(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
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

DELETE FROM public.insight_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fc03';

SELECT extensions.is(
    public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fc01'
    ),
    2,
    'conversation deletion does not restore either admitted send'
);

-- Exercise each production branch with real atomic admissions. Every family
-- must count first-send, survive a conversation cascade, create a fresh thread
-- only after the next slot is admitted, and advance the same shared ledger.
INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-4000-8000-00000000fd01',
    'authenticated',
    'authenticated',
    'field-chat-delete-paths@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source,
    subscription_tier
)
VALUES (
    '00000000-0000-4000-8000-00000000fd01',
    'field-chat-delete-paths@naturebook.invalid',
    'field_chat_fd01',
    'Field Chat Delete Paths',
    'alias',
    'pro'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source,
    subscription_tier = EXCLUDED.subscription_tier;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES (
    '00000000-0000-4000-8000-00000000fd02',
    '00000000-0000-4000-8000-00000000fd01',
    0.95,
    pg_catalog.NOW(),
    TRUE
);

CREATE TEMPORARY TABLE insight_delete_first ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd03',
    'insight',
    '00000000-0000-4000-8000-00000000fd02',
    'Insight first admission',
    '00000000-0000-4000-8000-00000000fd04'
);

DELETE FROM public.insight_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fd03';

CREATE TEMPORARY TABLE insight_delete_fresh ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd05',
    'insight',
    '00000000-0000-4000-8000-00000000fd02',
    'Insight fresh admission after delete',
    '00000000-0000-4000-8000-00000000fd06'
);

SELECT extensions.ok(
    (SELECT sends_today FROM insight_delete_first) = 1
    AND (SELECT sends_today FROM insight_delete_fresh) = 2
    AND (SELECT conversation_id FROM insight_delete_fresh) =
        '00000000-0000-4000-8000-00000000fd05'::UUID
    AND public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fd01'
    ) = 2,
    'Insight reserve-delete-fresh-reserve consumes two durable admissions'
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000fd10',
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd02',
    'obscured',
    pg_catalog.NOW()
);

CREATE TEMPORARY TABLE explore_delete_first ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd11',
    'explore',
    '00000000-0000-4000-8000-00000000fd10',
    'Explore first admission',
    '00000000-0000-4000-8000-00000000fd12'
);

DELETE FROM public.explore_post_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fd11';

CREATE TEMPORARY TABLE explore_delete_fresh ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd13',
    'explore',
    '00000000-0000-4000-8000-00000000fd10',
    'Explore fresh admission after delete',
    '00000000-0000-4000-8000-00000000fd14'
);

SELECT extensions.ok(
    (SELECT sends_today FROM explore_delete_first) = 3
    AND (SELECT sends_today FROM explore_delete_fresh) = 4
    AND (SELECT conversation_id FROM explore_delete_fresh) =
        '00000000-0000-4000-8000-00000000fd13'::UUID
    AND public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fd01'
    ) = 4,
    'Explore reserve-delete-fresh-reserve consumes two more durable admissions'
);

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
VALUES (
    '00000000-0000-4000-8000-00000000fd20',
    'Ardea alba durable delete path',
    '{"en":"Great Egret Durable Delete Path"}',
    'Animalia',
    'Chordata',
    'Aves',
    'Pelecaniformes',
    'Ardeidae',
    'Ardea'
);

CREATE TEMPORARY TABLE dictionary_delete_first ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd21',
    'species_dictionary',
    '00000000-0000-4000-8000-00000000fd20',
    'Dictionary first admission',
    '00000000-0000-4000-8000-00000000fd22'
);

DELETE FROM public.species_dictionary_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fd21';

CREATE TEMPORARY TABLE dictionary_delete_fresh ON COMMIT DROP AS
SELECT * FROM public.reserve_field_chat_send(
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd23',
    'species_dictionary',
    '00000000-0000-4000-8000-00000000fd20',
    'Dictionary fresh admission after delete',
    '00000000-0000-4000-8000-00000000fd24'
);

SELECT extensions.ok(
    (SELECT sends_today FROM dictionary_delete_first) = 5
    AND (SELECT sends_today FROM dictionary_delete_fresh) = 6
    AND (SELECT conversation_id FROM dictionary_delete_fresh) =
        '00000000-0000-4000-8000-00000000fd23'::UUID
    AND public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fd01'
    ) = 6,
    'Dictionary reserve-delete-fresh-reserve consumes two more durable admissions'
);

-- Execute the same owner-only cleanup used by the migration against one
-- historical message-less thread in every family. Nonempty admitted threads
-- must survive.
INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES (
    '00000000-0000-4000-8000-00000000fd30',
    '00000000-0000-4000-8000-00000000fd01',
    0.95,
    pg_catalog.NOW(),
    TRUE
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000fd31',
    '00000000-0000-4000-8000-00000000fd01',
    '00000000-0000-4000-8000-00000000fd30',
    'obscured',
    pg_catalog.NOW()
);

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
VALUES (
    '00000000-0000-4000-8000-00000000fd32',
    'Ardea alba historical empty thread fixture',
    '{"en":"Great Egret Historical Empty Thread Fixture"}',
    'Animalia',
    'Chordata',
    'Aves',
    'Pelecaniformes',
    'Ardeidae',
    'Ardea'
);

INSERT INTO public.insight_chat_conversations (id, scan_id, user_id)
VALUES (
    '00000000-0000-4000-8000-00000000fd33',
    '00000000-0000-4000-8000-00000000fd30',
    '00000000-0000-4000-8000-00000000fd01'
);

INSERT INTO public.explore_post_chat_conversations (id, post_id, user_id)
VALUES (
    '00000000-0000-4000-8000-00000000fd34',
    '00000000-0000-4000-8000-00000000fd31',
    '00000000-0000-4000-8000-00000000fd01'
);

INSERT INTO public.species_dictionary_chat_conversations (
    id,
    species_dictionary_id,
    user_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fd35',
    '00000000-0000-4000-8000-00000000fd32',
    '00000000-0000-4000-8000-00000000fd01'
);

CREATE TEMPORARY TABLE empty_thread_cleanup ON COMMIT DROP AS
SELECT * FROM internal.prune_empty_field_chat_conversations();

SELECT extensions.ok(
    (SELECT insight_removed FROM empty_thread_cleanup) = 1
    AND (SELECT explore_removed FROM empty_thread_cleanup) = 1
    AND (SELECT dictionary_removed FROM empty_thread_cleanup) = 1
    AND NOT EXISTS (
        SELECT 1 FROM public.insight_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd33'
    )
    AND NOT EXISTS (
        SELECT 1 FROM public.explore_post_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd34'
    )
    AND NOT EXISTS (
        SELECT 1 FROM public.species_dictionary_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd35'
    )
    AND EXISTS (
        SELECT 1 FROM public.insight_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd05'
    )
    AND EXISTS (
        SELECT 1 FROM public.explore_post_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd13'
    )
    AND EXISTS (
        SELECT 1 FROM public.species_dictionary_chat_conversations
        WHERE id = '00000000-0000-4000-8000-00000000fd23'
    ),
    'owner-only cutover cleanup removes all three message-less threads and preserves admitted threads'
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
    FOR fixture_number IN 1..3
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

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    location_sharing,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000fc20',
    '00000000-0000-4000-8000-00000000fc01',
    '00000000-0000-4000-8000-00000000fc02',
    'obscured',
    pg_catalog.NOW()
);

INSERT INTO public.explore_post_chat_conversations (
    id,
    post_id,
    user_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fc21',
    '00000000-0000-4000-8000-00000000fc20',
    '00000000-0000-4000-8000-00000000fc01'
);

INSERT INTO public.explore_post_chat_messages (
    id,
    conversation_id,
    post_id,
    user_id,
    role,
    message_text,
    client_message_id
)
VALUES (
    '00000000-0000-4000-8000-00000000fc22',
    '00000000-0000-4000-8000-00000000fc21',
    '00000000-0000-4000-8000-00000000fc20',
    '00000000-0000-4000-8000-00000000fc01',
    'user',
    'Explore daily-limit fixture question',
    '00000000-0000-4000-8000-00000000fc23'
);

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
VALUES (
    '00000000-0000-4000-8000-00000000fc24',
    'Ardea alba shared quota fixture',
    '{"en":"Great Egret Shared Quota Fixture"}',
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
    '00000000-0000-4000-8000-00000000fc25',
    '00000000-0000-4000-8000-00000000fc24',
    '00000000-0000-4000-8000-00000000fc01'
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
    '00000000-0000-4000-8000-00000000fc26',
    '00000000-0000-4000-8000-00000000fc25',
    '00000000-0000-4000-8000-00000000fc24',
    '00000000-0000-4000-8000-00000000fc01',
    'user',
    'Dictionary daily-limit fixture question',
    '00000000-0000-4000-8000-00000000fc27'
);

UPDATE internal.field_chat_daily_admissions AS admission
SET admitted_count = 20,
    last_admitted_at = GREATEST(
        admission.last_admitted_at,
        pg_catalog.CLOCK_TIMESTAMP()
    )
WHERE admission.user_id = '00000000-0000-4000-8000-00000000fc01'
  AND admission.admission_day =
        (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE;

DELETE FROM public.explore_post_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fc21';

SELECT extensions.is(
    public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fc01'
    ),
    20,
    'Explore conversation deletion does not restore daily admission capacity'
);

DELETE FROM public.species_dictionary_chat_conversations
WHERE id = '00000000-0000-4000-8000-00000000fc25';

SELECT extensions.is(
    public.get_field_chat_daily_usage(
        '00000000-0000-4000-8000-00000000fc01'
    ),
    20,
    'Dictionary conversation deletion does not restore daily admission capacity'
);

SELECT extensions.throws_ok(
    $statement$
        SELECT *
        FROM public.reserve_field_chat_send(
            '00000000-0000-4000-8000-00000000fc01',
            '00000000-0000-4000-8000-00000000fc13',
            'species_dictionary',
            '00000000-0000-4000-8000-00000000fc24',
            'This request would exceed twenty sends today.',
            '00000000-0000-4000-8000-00000000fc14'
        )
    $statement$,
    'P0001',
    'field_chat_daily_limit_reached',
    'three-family daily admission stops at twenty user sends'
);

SELECT extensions.ok(
    NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_conversations AS conversation
        WHERE conversation.id =
              '00000000-0000-4000-8000-00000000fc13'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_messages AS message
        WHERE message.client_message_id =
              '00000000-0000-4000-8000-00000000fc14'
    ),
    'Dictionary quota denial creates neither a hidden conversation nor a user message'
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

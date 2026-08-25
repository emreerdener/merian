-- Preserve the shared Field Chat UTC-day allowance independently of private
-- message retention. Conversation deletion may erase content, but it must not
-- restore a provider-backed send that was already admitted.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE internal.field_chat_daily_admissions (
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    admission_day DATE NOT NULL,
    admitted_count INTEGER NOT NULL,
    first_admitted_at TIMESTAMPTZ NOT NULL,
    last_admitted_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, admission_day),
    CONSTRAINT field_chat_daily_admissions_count_check
        CHECK (admitted_count >= 1),
    CONSTRAINT field_chat_daily_admissions_time_check
        CHECK (last_admitted_at >= first_admitted_at)
);

ALTER TABLE internal.field_chat_daily_admissions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.field_chat_daily_admissions
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.field_chat_daily_admissions IS
    'Private deletion-resistant aggregate of admitted Insight, Explore, and Species Dictionary Field Chat user sends by UTC day.';
COMMENT ON COLUMN internal.field_chat_daily_admissions.admitted_count IS
    'Conservative send count for the UTC day. Ghost-profile merges sum both principals and may leave a value above the ordinary daily limit.';

-- The retained-row seed below cannot reconstruct messages deleted earlier in
-- the current UTC day. Keep every novel Field Chat admission closed through the
-- next database-observed UTC boundary and until explicit post-bundle activation.
-- Exact idempotent replays remain available because they do not consume a new
-- daily admission.
CREATE TABLE internal.field_chat_admission_cutover (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE,
    migration_id TEXT NOT NULL,
    seeded_at TIMESTAMPTZ NOT NULL,
    not_before_utc TIMESTAMPTZ NOT NULL,
    activated_at TIMESTAMPTZ,
    activated_candidate_sha TEXT,
    activated_migration_sha256 TEXT,
    activated_explore_bundle_sha256 TEXT,
    activated_insight_bundle_sha256 TEXT,
    activated_species_dictionary_bundle_sha256 TEXT,
    CONSTRAINT field_chat_admission_cutover_singleton_check
        CHECK (singleton),
    CONSTRAINT field_chat_admission_cutover_migration_check
        CHECK (
            migration_id =
                '20260824210544_preserve_field_chat_daily_usage'
        ),
    CONSTRAINT field_chat_admission_cutover_boundary_check
        CHECK (not_before_utc > seeded_at),
    CONSTRAINT field_chat_admission_cutover_activation_check
        CHECK (
            (
                activated_at IS NULL
                AND activated_candidate_sha IS NULL
                AND activated_migration_sha256 IS NULL
                AND activated_explore_bundle_sha256 IS NULL
                AND activated_insight_bundle_sha256 IS NULL
                AND activated_species_dictionary_bundle_sha256 IS NULL
            )
            OR (
                activated_at IS NOT NULL
                AND activated_candidate_sha IS NOT NULL
                AND activated_migration_sha256 IS NOT NULL
                AND activated_explore_bundle_sha256 IS NOT NULL
                AND activated_insight_bundle_sha256 IS NOT NULL
                AND activated_species_dictionary_bundle_sha256 IS NOT NULL
                AND activated_at >= not_before_utc
                AND activated_candidate_sha
                    ~ '^[0-9a-f]{40}$'
                AND activated_candidate_sha
                    <> pg_catalog.REPEAT('0', 40)
                AND activated_migration_sha256
                    ~ '^[0-9a-f]{64}$'
                AND activated_migration_sha256
                    <> pg_catalog.REPEAT('0', 64)
                AND activated_explore_bundle_sha256
                    ~ '^[0-9a-f]{64}$'
                AND activated_explore_bundle_sha256
                    <> pg_catalog.REPEAT('0', 64)
                AND activated_insight_bundle_sha256
                    ~ '^[0-9a-f]{64}$'
                AND activated_insight_bundle_sha256
                    <> pg_catalog.REPEAT('0', 64)
                AND activated_species_dictionary_bundle_sha256
                    ~ '^[0-9a-f]{64}$'
                AND activated_species_dictionary_bundle_sha256
                    <> pg_catalog.REPEAT('0', 64)
            )
        )
);

ALTER TABLE internal.field_chat_admission_cutover ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.field_chat_admission_cutover
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.field_chat_admission_cutover (
    singleton,
    migration_id,
    seeded_at,
    not_before_utc
)
SELECT
    TRUE,
    '20260824210544_preserve_field_chat_daily_usage',
    cutover.database_now,
    pg_catalog.DATE_TRUNC('day', cutover.database_now, 'UTC')
        + INTERVAL '1 day'
FROM (
    SELECT pg_catalog.CLOCK_TIMESTAMP() AS database_now
) AS cutover;

COMMENT ON TABLE internal.field_chat_admission_cutover IS
    'One-row cutover guard. Database time establishes eligibility, but only an explicit post-bundle activation bound to the candidate, migration, and all three content-addressed Function bundles opens novel Field Chat admissions.';

CREATE OR REPLACE FUNCTION internal.assert_field_chat_admission_open()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '2s'
AS $function$
DECLARE
    cutover_not_before TIMESTAMPTZ;
    cutover_activated_at TIMESTAMPTZ;
BEGIN
    SELECT cutover.not_before_utc, cutover.activated_at
    INTO cutover_not_before, cutover_activated_at
    FROM internal.field_chat_admission_cutover AS cutover
    WHERE cutover.singleton;

    IF cutover_not_before IS NULL THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_unavailable'
            USING ERRCODE = '55000';
    END IF;
    IF cutover_activated_at IS NULL
       OR pg_catalog.CLOCK_TIMESTAMP() < cutover_not_before THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_pending'
            USING ERRCODE = '55000';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION internal.assert_field_chat_admission_open()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.guard_field_chat_conversation_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '2s'
AS $function$
BEGIN
    PERFORM internal.assert_field_chat_admission_open();
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION internal.guard_field_chat_conversation_insert()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER insight_chat_conversation_cutover_guard
BEFORE INSERT ON public.insight_chat_conversations
FOR EACH ROW
EXECUTE FUNCTION internal.guard_field_chat_conversation_insert();

CREATE TRIGGER explore_post_chat_conversation_cutover_guard
BEFORE INSERT ON public.explore_post_chat_conversations
FOR EACH ROW
EXECUTE FUNCTION internal.guard_field_chat_conversation_insert();

CREATE TRIGGER species_dictionary_chat_conversation_cutover_guard
BEFORE INSERT ON public.species_dictionary_chat_conversations
FOR EACH ROW
EXECUTE FUNCTION internal.guard_field_chat_conversation_insert();

-- Conversation creation is permanently owned by the SECURITY DEFINER
-- reservation routine. This prevents an old or in-flight create-before-reserve
-- bundle from regaining direct insertion after activation; current routes keep
-- SELECT/UPDATE/DELETE for load, touch, and user-requested deletion.
REVOKE INSERT
    ON TABLE public.insight_chat_conversations,
             public.explore_post_chat_conversations,
             public.species_dictionary_chat_conversations
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.prune_empty_field_chat_conversations()
RETURNS TABLE (
    insight_removed BIGINT,
    explore_removed BIGINT,
    dictionary_removed BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '10s'
SET statement_timeout = '30s'
AS $function$
BEGIN
    -- Prevent old create-before-reserve, admission, and deletion paths from
    -- racing cleanup. A busy writer makes the reviewed migration fail cleanly.
    LOCK TABLE
        public.insight_chat_conversations,
        public.insight_chat_messages,
        public.explore_post_chat_conversations,
        public.explore_post_chat_messages,
        public.species_dictionary_chat_conversations,
        public.species_dictionary_chat_messages
    IN SHARE ROW EXCLUSIVE MODE;

    -- Repair hidden empty threads left by historical create-before-reserve
    -- bundles, including a request that committed immediately before the locks.
    -- Insight feature feedback survives through its ON DELETE SET NULL link;
    -- message-bound feedback has no row to retain.
    DELETE FROM public.insight_chat_conversations AS conversation
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.insight_chat_messages AS message
        WHERE message.conversation_id = conversation.id
    );
    GET DIAGNOSTICS insight_removed = ROW_COUNT;

    DELETE FROM public.explore_post_chat_conversations AS conversation
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.explore_post_chat_messages AS message
        WHERE message.conversation_id = conversation.id
    );
    GET DIAGNOSTICS explore_removed = ROW_COUNT;

    DELETE FROM public.species_dictionary_chat_conversations AS conversation
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.species_dictionary_chat_messages AS message
        WHERE message.conversation_id = conversation.id
    );
    GET DIAGNOSTICS dictionary_removed = ROW_COUNT;

    RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION internal.prune_empty_field_chat_conversations() IS
    'Owner-only cutover maintenance that locks all Field Chat conversation/message tables and removes historical message-less threads without deleting messages.';

REVOKE ALL ON FUNCTION internal.prune_empty_field_chat_conversations()
    FROM PUBLIC, anon, authenticated, service_role;

SELECT * FROM internal.prune_empty_field_chat_conversations();

WITH utc_window AS (
    SELECT
        (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE
            AS admission_day,
        pg_catalog.DATE_TRUNC(
            'day',
            CURRENT_TIMESTAMP,
            'UTC'
        ) AS window_start
), retained_admissions AS (
    SELECT message.user_id, message.created_at
    FROM public.insight_chat_messages AS message
    CROSS JOIN utc_window
    WHERE message.role = 'user'
      AND message.created_at >= utc_window.window_start
    UNION ALL
    SELECT message.user_id, message.created_at
    FROM public.explore_post_chat_messages AS message
    CROSS JOIN utc_window
    WHERE message.role = 'user'
      AND message.created_at >= utc_window.window_start
    UNION ALL
    SELECT message.user_id, message.created_at
    FROM public.species_dictionary_chat_messages AS message
    CROSS JOIN utc_window
    WHERE message.role = 'user'
      AND message.created_at >= utc_window.window_start
), retained_totals AS (
    SELECT
        retained.user_id,
        utc_window.admission_day,
        pg_catalog.COUNT(*)::INTEGER AS admitted_count,
        pg_catalog.MIN(retained.created_at) AS first_admitted_at,
        pg_catalog.MAX(retained.created_at) AS last_admitted_at
    FROM retained_admissions AS retained
    CROSS JOIN utc_window
    GROUP BY retained.user_id, utc_window.admission_day
)
INSERT INTO internal.field_chat_daily_admissions AS admission (
    user_id,
    admission_day,
    admitted_count,
    first_admitted_at,
    last_admitted_at
)
SELECT
    retained.user_id,
    retained.admission_day,
    retained.admitted_count,
    retained.first_admitted_at,
    retained.last_admitted_at
FROM retained_totals AS retained
ON CONFLICT (user_id, admission_day) DO UPDATE
SET
    admitted_count = GREATEST(
        admission.admitted_count,
        EXCLUDED.admitted_count
    ),
    first_admitted_at = LEAST(
        admission.first_admitted_at,
        EXCLUDED.first_admitted_at
    ),
    last_admitted_at = GREATEST(
        admission.last_admitted_at,
        EXCLUDED.last_admitted_at
    );

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
VALUES (
    'internal',
    'field_chat_daily_admissions',
    'user_id',
    'public',
    'users',
    'id',
    'handler_then_reparent',
    200,
    'field_chat_daily_admissions',
    'Daily Field Chat admissions are conservatively summed before a Ghost profile is removed.'
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

-- Keep the schema-aware merge preflight fail closed while explicitly
-- registering this reviewed handler. Match the established source-rewrite
-- convention so upstream allowlist drift aborts the migration.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT :=
        '              ''complimentary_scan_usage'',';
    replacement_fragment TEXT :=
        '              ''complimentary_scan_usage'','
        || pg_catalog.CHR(10)
        || '              ''field_chat_daily_admissions'',';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'internal.assert_ghost_profile_merge_reference_policy_coverage()'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF pg_catalog.STRPOS(
        function_definition,
        '''field_chat_daily_admissions'''
    ) <> 0
       OR (
            pg_catalog.LENGTH(function_definition)
            - pg_catalog.LENGTH(
                pg_catalog.REPLACE(
                    function_definition,
                    guarded_fragment,
                    ''
                )
            )
          ) / pg_catalog.LENGTH(guarded_fragment) <> 1 THEN
        RAISE EXCEPTION 'ghost_merge_field_chat_allowlist_source_drift'
            USING ERRCODE = '55000';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF pg_catalog.STRPOS(
        rewritten_definition,
        '''field_chat_daily_admissions'''
    ) = 0 THEN
        RAISE EXCEPTION 'ghost_merge_field_chat_allowlist_rewrite_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

SELECT internal.assert_ghost_profile_merge_reference_policy_coverage();

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
    -- Serialize both identities with the same user lock namespace used by
    -- reserve_field_chat_send. UUID order makes overlapping merges deadlock
    -- safe while preventing an admission from landing after its source ledger
    -- has already been transferred.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:user:'
                || LEAST(p_ghost_user_id, p_target_user_id)::TEXT,
            0::BIGINT
        )
    );
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:user:'
                || GREATEST(p_ghost_user_id, p_target_user_id)::TEXT,
            0::BIGINT
        )
    );

    INSERT INTO internal.field_chat_daily_admissions AS target_admission (
        user_id,
        admission_day,
        admitted_count,
        first_admitted_at,
        last_admitted_at
    )
    SELECT
        p_target_user_id,
        ghost_admission.admission_day,
        ghost_admission.admitted_count,
        ghost_admission.first_admitted_at,
        ghost_admission.last_admitted_at
    FROM internal.field_chat_daily_admissions AS ghost_admission
    WHERE ghost_admission.user_id = p_ghost_user_id
    ON CONFLICT (user_id, admission_day) DO UPDATE
    SET
        admitted_count =
            target_admission.admitted_count + EXCLUDED.admitted_count,
        first_admitted_at = LEAST(
            target_admission.first_admitted_at,
            EXCLUDED.first_admitted_at
        ),
        last_admitted_at = GREATEST(
            target_admission.last_admitted_at,
            EXCLUDED.last_admitted_at
        );

    DELETE FROM internal.field_chat_daily_admissions AS ghost_admission
    WHERE ghost_admission.user_id = p_ghost_user_id;

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
        FROM public.species_dictionary_chat_conversations
            AS ghost_conversation
        JOIN public.species_dictionary_chat_conversations
            AS target_conversation
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
    'Conservatively merges durable daily admissions, then conflict-normalizes Insight, Explore, and Species Dictionary chat conversations before schema-aware account reparenting.';

CREATE OR REPLACE FUNCTION public.get_field_chat_daily_usage(
    p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    daily_count INTEGER;
    current_utc_day DATE :=
        (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'field_chat_invalid_usage_request'
            USING ERRCODE = '22023';
    END IF;

    SELECT admission.admitted_count
    INTO daily_count
    FROM internal.field_chat_daily_admissions AS admission
    WHERE admission.user_id = p_user_id
      AND admission.admission_day = current_utc_day;

    RETURN COALESCE(daily_count, 0);
END;
$function$;

COMMENT ON FUNCTION public.get_field_chat_daily_usage(UUID) IS
    'Service-only deletion-resistant aggregate of admitted Field Chat user sends for the current UTC day.';

REVOKE ALL ON FUNCTION public.get_field_chat_daily_usage(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_field_chat_daily_usage(UUID)
    TO service_role;

CREATE OR REPLACE FUNCTION public.get_field_chat_admission_cutover_status()
RETURNS TABLE (
    migration_id TEXT,
    database_now TIMESTAMPTZ,
    seeded_at TIMESTAMPTZ,
    not_before_utc TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    activated_candidate_sha TEXT,
    activated_migration_sha256 TEXT,
    activated_explore_bundle_sha256 TEXT,
    activated_insight_bundle_sha256 TEXT,
    activated_species_dictionary_bundle_sha256 TEXT,
    status TEXT
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    observed_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    SELECT
        cutover.migration_id,
        observed_now,
        cutover.seeded_at,
        cutover.not_before_utc,
        cutover.activated_at,
        cutover.activated_candidate_sha,
        cutover.activated_migration_sha256,
        cutover.activated_explore_bundle_sha256,
        cutover.activated_insight_bundle_sha256,
        cutover.activated_species_dictionary_bundle_sha256,
        CASE
            WHEN observed_now < cutover.not_before_utc THEN 'pending'
            WHEN cutover.activated_at IS NULL THEN 'ready'
            ELSE 'active'
        END
    FROM internal.field_chat_admission_cutover AS cutover
    WHERE cutover.singleton;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_unavailable'
            USING ERRCODE = '55000';
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.get_field_chat_admission_cutover_status() IS
    'Service-only bounded rollout evidence for pending, ready, and explicitly activated Field Chat admission states; returns no user or quota data.';

REVOKE ALL ON FUNCTION public.get_field_chat_admission_cutover_status()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_field_chat_admission_cutover_status()
    TO service_role;

CREATE OR REPLACE FUNCTION public.activate_field_chat_admission_cutover(
    p_candidate_sha TEXT,
    p_migration_sha256 TEXT,
    p_explore_bundle_sha256 TEXT,
    p_insight_bundle_sha256 TEXT,
    p_species_dictionary_bundle_sha256 TEXT
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    observed_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    cutover_not_before TIMESTAMPTZ;
    existing_candidate_sha TEXT;
    existing_migration_sha256 TEXT;
    existing_explore_bundle_sha256 TEXT;
    existing_insight_bundle_sha256 TEXT;
    existing_species_dictionary_bundle_sha256 TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_candidate_sha IS NULL
       OR p_candidate_sha !~ '^[0-9a-f]{40}$'
       OR p_candidate_sha = pg_catalog.REPEAT('0', 40)
       OR p_migration_sha256 IS NULL
       OR p_migration_sha256 !~ '^[0-9a-f]{64}$'
       OR p_migration_sha256 = pg_catalog.REPEAT('0', 64)
       OR p_explore_bundle_sha256 IS NULL
       OR p_explore_bundle_sha256 !~ '^[0-9a-f]{64}$'
       OR p_explore_bundle_sha256 = pg_catalog.REPEAT('0', 64)
       OR p_insight_bundle_sha256 IS NULL
       OR p_insight_bundle_sha256 !~ '^[0-9a-f]{64}$'
       OR p_insight_bundle_sha256 = pg_catalog.REPEAT('0', 64)
       OR p_species_dictionary_bundle_sha256 IS NULL
       OR p_species_dictionary_bundle_sha256 !~ '^[0-9a-f]{64}$'
       OR p_species_dictionary_bundle_sha256 = pg_catalog.REPEAT('0', 64) THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_invalid_activation'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        cutover.not_before_utc,
        cutover.activated_candidate_sha,
        cutover.activated_migration_sha256,
        cutover.activated_explore_bundle_sha256,
        cutover.activated_insight_bundle_sha256,
        cutover.activated_species_dictionary_bundle_sha256
    INTO
        cutover_not_before,
        existing_candidate_sha,
        existing_migration_sha256,
        existing_explore_bundle_sha256,
        existing_insight_bundle_sha256,
        existing_species_dictionary_bundle_sha256
    FROM internal.field_chat_admission_cutover AS cutover
    WHERE cutover.singleton
    FOR UPDATE;

    IF cutover_not_before IS NULL THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_unavailable'
            USING ERRCODE = '55000';
    END IF;
    IF observed_now < cutover_not_before THEN
        RAISE EXCEPTION 'field_chat_admission_cutover_not_ready'
            USING ERRCODE = '55000';
    END IF;
    IF existing_candidate_sha IS NOT NULL THEN
        IF existing_candidate_sha <> p_candidate_sha
           OR existing_migration_sha256 <> p_migration_sha256
           OR existing_explore_bundle_sha256 <> p_explore_bundle_sha256
           OR existing_insight_bundle_sha256 <> p_insight_bundle_sha256
           OR existing_species_dictionary_bundle_sha256
                <> p_species_dictionary_bundle_sha256 THEN
            RAISE EXCEPTION 'field_chat_admission_cutover_activation_conflict'
                USING ERRCODE = '23505';
        END IF;
        RETURN;
    END IF;

    UPDATE internal.field_chat_admission_cutover AS cutover
    SET
        activated_at = observed_now,
        activated_candidate_sha = p_candidate_sha,
        activated_migration_sha256 = p_migration_sha256,
        activated_explore_bundle_sha256 = p_explore_bundle_sha256,
        activated_insight_bundle_sha256 = p_insight_bundle_sha256,
        activated_species_dictionary_bundle_sha256 =
            p_species_dictionary_bundle_sha256
    WHERE cutover.singleton;
END;
$function$;

COMMENT ON FUNCTION public.activate_field_chat_admission_cutover(
    TEXT, TEXT, TEXT, TEXT, TEXT
) IS
    'Service-only one-way activation after the UTC boundary and successful live verification of the exact content digest for all three reviewed Field Chat bundles; binds the opening to immutable candidate, migration, and bundle evidence.';

REVOKE ALL ON FUNCTION public.activate_field_chat_admission_cutover(
    TEXT, TEXT, TEXT, TEXT, TEXT
)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_field_chat_admission_cutover(
    TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;

-- The return row now includes the authoritative conversation id. Dropping the
-- prior function is required because PostgreSQL cannot alter a table-return
-- shape with CREATE OR REPLACE. The argument signature remains compatible
-- with already-deployed Edge bundles.
DROP FUNCTION IF EXISTS public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
);

CREATE FUNCTION public.reserve_field_chat_send(
    p_user_id UUID,
    p_conversation_id UUID,
    p_subject_type TEXT,
    p_subject_id UUID,
    p_message_text TEXT,
    p_client_message_id UUID
)
RETURNS TABLE (
    conversation_id UUID,
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
    resolved_conversation_id UUID;
    replaced_conversation_id UUID;
    conversation_user_id UUID;
    conversation_subject_id UUID;
    conversation_species_dictionary_id UUID;
    explore_species_dictionary_id UUID;
    existing_message JSONB;
    inserted_message JSONB;
    message_count INTEGER;
    daily_count INTEGER;
    current_utc_day DATE;
    admission_now TIMESTAMPTZ;
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

    -- Match account merge's parent-row then Field-Chat-lock order. The parent
    -- key lock also makes the first daily-ledger insert safe against a
    -- concurrent identity reparent/delete without creating a lock cycle.
    PERFORM profile.id
    FROM public.users AS profile
    WHERE profile.id = p_user_id
    FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'field_chat_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    -- All chat families then use the same user-first, subject-second lock
    -- order. A subject lock makes first-conversation creation and admission a
    -- single convergence boundary; p_conversation_id is only the caller's UUID
    -- candidate when no conversation exists yet.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:user:' || p_user_id::TEXT,
            0::BIGINT
        )
    );
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:field-chat:subject:'
                || p_subject_type || ':' || p_subject_id::TEXT
                || ':user:' || p_user_id::TEXT,
            0::BIGINT
        )
    );

    IF p_subject_type = 'insight' THEN
        SELECT
            conversation.id,
            conversation.user_id,
            conversation.scan_id
        INTO
            resolved_conversation_id,
            conversation_user_id,
            conversation_subject_id
        FROM public.insight_chat_conversations AS conversation
        WHERE conversation.scan_id = p_subject_id
          AND conversation.user_id = p_user_id
        FOR UPDATE;

        SELECT pg_catalog.TO_JSONB(chat_message.*)
        INTO existing_message
        FROM public.insight_chat_messages AS chat_message
        WHERE chat_message.conversation_id = resolved_conversation_id
          AND chat_message.client_message_id = p_client_message_id
          AND chat_message.role = 'user';
    ELSIF p_subject_type = 'explore' THEN
        SELECT COALESCE(scan.confirmed_species_id, scan.species_id)
        INTO explore_species_dictionary_id
        FROM public.explore_posts AS post
        JOIN public.scans AS scan
          ON scan.id = post.scan_id
        WHERE post.id = p_subject_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'field_chat_subject_not_found'
                USING ERRCODE = 'P0002';
        END IF;

        SELECT
            conversation.id,
            conversation.user_id,
            conversation.post_id,
            conversation.species_dictionary_id
        INTO
            resolved_conversation_id,
            conversation_user_id,
            conversation_subject_id,
            conversation_species_dictionary_id
        FROM public.explore_post_chat_conversations AS conversation
        WHERE conversation.post_id = p_subject_id
          AND conversation.user_id = p_user_id
        FOR UPDATE;

        IF resolved_conversation_id IS NOT NULL
           AND conversation_species_dictionary_id IS DISTINCT FROM
                explore_species_dictionary_id THEN
            replaced_conversation_id := resolved_conversation_id;
            resolved_conversation_id := NULL;
            conversation_user_id := NULL;
            conversation_subject_id := NULL;
        ELSE
            SELECT pg_catalog.TO_JSONB(chat_message.*)
            INTO existing_message
            FROM public.explore_post_chat_messages AS chat_message
            WHERE chat_message.conversation_id = resolved_conversation_id
              AND chat_message.client_message_id = p_client_message_id
              AND chat_message.role = 'user';
        END IF;
    ELSE
        SELECT
            conversation.id,
            conversation.user_id,
            conversation.species_dictionary_id
        INTO
            resolved_conversation_id,
            conversation_user_id,
            conversation_subject_id
        FROM public.species_dictionary_chat_conversations AS conversation
        WHERE conversation.species_dictionary_id = p_subject_id
          AND conversation.user_id = p_user_id
        FOR UPDATE;

        SELECT pg_catalog.TO_JSONB(chat_message.*)
        INTO existing_message
        FROM public.species_dictionary_chat_messages AS chat_message
        WHERE chat_message.conversation_id = resolved_conversation_id
          AND chat_message.client_message_id = p_client_message_id
          AND chat_message.role = 'user';
    END IF;

    IF resolved_conversation_id IS NOT NULL
       AND (
            conversation_user_id <> p_user_id
            OR conversation_subject_id <> p_subject_id
       ) THEN
        RAISE EXCEPTION 'field_chat_access_forbidden'
            USING ERRCODE = '42501';
    END IF;

    admission_now := pg_catalog.CLOCK_TIMESTAMP();
    current_utc_day := (admission_now AT TIME ZONE 'UTC')::DATE;

    SELECT admission.admitted_count
    INTO daily_count
    FROM internal.field_chat_daily_admissions AS admission
    WHERE admission.user_id = p_user_id
      AND admission.admission_day = current_utc_day;
    daily_count := COALESCE(daily_count, 0);

    -- An exact replay remains available after either cap is reached and never
    -- increments durable admission accounting.
    IF existing_message IS NOT NULL THEN
        IF existing_message ->> 'user_id' <> p_user_id::TEXT
           OR existing_message ->> 'conversation_id'
                <> resolved_conversation_id::TEXT
           OR existing_message ->> 'role' <> 'user'
           OR existing_message ->> 'message_text'
                <> normalized_message_text
           OR existing_message ->> 'client_message_id'
                <> p_client_message_id::TEXT THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY
        SELECT
            resolved_conversation_id,
            existing_message,
            TRUE,
            daily_count;
        RETURN;
    END IF;

    -- The lower-bound seed cannot know about content deleted before this
    -- migration. Preserve exact replay above, but reject every novel request
    -- through PostgreSQL's next complete UTC day boundary and until the
    -- reviewed bundles are explicitly activated.
    PERFORM internal.assert_field_chat_admission_open();

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
        WHERE user_message.conversation_id = resolved_conversation_id;
    ELSIF p_subject_type = 'explore' THEN
        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            pg_catalog.BOOL_OR(
                user_message.role = 'user'
                AND user_message.client_message_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.explore_post_chat_messages
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
        FROM public.explore_post_chat_messages AS user_message
        WHERE user_message.conversation_id = resolved_conversation_id;
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
        WHERE user_message.conversation_id = resolved_conversation_id;
    END IF;

    IF COALESCE(has_incomplete_request, FALSE) THEN
        RAISE EXCEPTION 'field_chat_send_in_progress'
            USING ERRCODE = '55000';
    END IF;
    IF message_count + 2 > max_messages_per_conversation THEN
        RAISE EXCEPTION 'field_chat_conversation_limit_reached'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO internal.field_chat_daily_admissions AS admission (
        user_id,
        admission_day,
        admitted_count,
        first_admitted_at,
        last_admitted_at
    )
    VALUES (
        p_user_id,
        current_utc_day,
        1,
        admission_now,
        admission_now
    )
    ON CONFLICT (user_id, admission_day) DO UPDATE
    SET
        admitted_count = admission.admitted_count + 1,
        last_admitted_at = EXCLUDED.last_admitted_at
    WHERE admission.admitted_count < daily_send_limit
    RETURNING admission.admitted_count
    INTO daily_count;

    IF daily_count IS NULL THEN
        RAISE EXCEPTION 'field_chat_daily_limit_reached'
            USING ERRCODE = 'P0001';
    END IF;

    -- Conversation creation/replacement happens only after a daily slot has
    -- been admitted. Any later failure rolls the ledger and conversation back
    -- together, so a denied request cannot leave a hidden empty thread.
    IF resolved_conversation_id IS NULL THEN
        IF replaced_conversation_id IS NOT NULL THEN
            DELETE FROM public.explore_post_chat_conversations AS conversation
            WHERE conversation.id = replaced_conversation_id
              AND conversation.user_id = p_user_id
              AND conversation.post_id = p_subject_id;
        END IF;

        IF p_subject_type = 'insight' THEN
            INSERT INTO public.insight_chat_conversations AS conversation (
                id,
                scan_id,
                user_id
            )
            VALUES (p_conversation_id, p_subject_id, p_user_id)
            ON CONFLICT (scan_id, user_id) DO UPDATE
            SET updated_at = conversation.updated_at
            RETURNING conversation.id
            INTO resolved_conversation_id;
        ELSIF p_subject_type = 'explore' THEN
            INSERT INTO public.explore_post_chat_conversations AS conversation (
                id,
                post_id,
                user_id,
                species_dictionary_id
            )
            VALUES (
                p_conversation_id,
                p_subject_id,
                p_user_id,
                explore_species_dictionary_id
            )
            ON CONFLICT (post_id, user_id) DO UPDATE
            SET updated_at = conversation.updated_at
            RETURNING conversation.id
            INTO resolved_conversation_id;
        ELSE
            INSERT INTO public.species_dictionary_chat_conversations
                AS conversation (
                    id,
                    species_dictionary_id,
                    user_id
                )
            VALUES (p_conversation_id, p_subject_id, p_user_id)
            ON CONFLICT (species_dictionary_id, user_id) DO UPDATE
            SET updated_at = conversation.updated_at
            RETURNING conversation.id
            INTO resolved_conversation_id;
        END IF;
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
            resolved_conversation_id,
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
            resolved_conversation_id,
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
            resolved_conversation_id,
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
    SELECT
        resolved_conversation_id,
        inserted_message,
        FALSE,
        daily_count;
END;
$function$;

COMMENT ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) IS
    'Service-only atomic three-family Field Chat conversation convergence, idempotency, in-flight, conversation-cap, deletion-resistant UTC-day-cap, and user-message admission boundary.';

REVOKE ALL ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send(
    UUID, UUID, TEXT, UUID, TEXT, UUID
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_field_chat_daily_usage(uuid)',
        'Read the deletion-resistant current-UTC-day Field Chat admission aggregate.'
    ),
    (
        'service_role',
        'public.get_field_chat_admission_cutover_status()',
        'Read bounded PostgreSQL-clock Field Chat admission-cutover evidence without user data.'
    ),
    (
        'service_role',
        'public.activate_field_chat_admission_cutover(text,text,text,text,text)',
        'One-way post-boundary Field Chat activation bound to an exact candidate SHA, migration digest, and the content digest of all three live bundles.'
    ),
    (
        'service_role',
        'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)',
        'Atomic three-family Field Chat idempotency, capacity, deletion-resistant daily-limit, and user-message admission.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

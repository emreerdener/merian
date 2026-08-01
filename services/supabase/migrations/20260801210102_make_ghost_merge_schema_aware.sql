-- Replace the runtime "rewrite every user foreign key" assumption with a
-- reviewed ownership policy. Foreign keys express referential integrity, not
-- merge semantics: canonical rows can move directly, conflict-prone rows need
-- a handler first, derived rows must follow their source of truth, and audit
-- attribution must never be silently rewritten.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE internal.ghost_profile_merge_reference_policies (
    source_schema TEXT NOT NULL,
    source_table TEXT NOT NULL,
    source_column TEXT NOT NULL,
    referenced_schema TEXT NOT NULL,
    referenced_table TEXT NOT NULL,
    referenced_column TEXT NOT NULL,
    strategy TEXT NOT NULL,
    execution_order INTEGER NOT NULL,
    handler_key TEXT,
    purpose TEXT NOT NULL,
    PRIMARY KEY (
        source_schema,
        source_table,
        source_column,
        referenced_schema,
        referenced_table,
        referenced_column
    ),
    CONSTRAINT ghost_profile_merge_reference_identifier_check CHECK (
        pg_catalog.CHAR_LENGTH(source_schema) BETWEEN 1 AND 63
        AND pg_catalog.CHAR_LENGTH(source_table) BETWEEN 1 AND 63
        AND pg_catalog.CHAR_LENGTH(source_column) BETWEEN 1 AND 63
        AND pg_catalog.CHAR_LENGTH(referenced_schema) BETWEEN 1 AND 63
        AND pg_catalog.CHAR_LENGTH(referenced_table) BETWEEN 1 AND 63
        AND pg_catalog.CHAR_LENGTH(referenced_column) BETWEEN 1 AND 63
    ),
    CONSTRAINT ghost_profile_merge_reference_strategy_check CHECK (
        strategy IN (
            'reparent',
            'handler_then_reparent',
            'derived',
            'preserve',
            'delete_source',
            'blocked'
        )
    ),
    CONSTRAINT ghost_profile_merge_reference_order_check CHECK (
        execution_order BETWEEN 0 AND 1000000
    ),
    CONSTRAINT ghost_profile_merge_reference_handler_check CHECK (
        (
            strategy IN ('handler_then_reparent', 'derived')
            AND handler_key IS NOT NULL
            AND handler_key ~ '^[a-z][a-z0-9_]{2,79}$'
        )
        OR (
            strategy NOT IN ('handler_then_reparent', 'derived')
            AND handler_key IS NULL
        )
    ),
    CONSTRAINT ghost_profile_merge_reference_purpose_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(purpose)) BETWEEN 1 AND 500
    )
);

ALTER TABLE internal.ghost_profile_merge_reference_policies
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.ghost_profile_merge_reference_policies
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.ghost_profile_merge_reference_policies IS
    'Owner-only reviewed policy for every non-Auth-internal single-column FK to public.users or auth.users. Runtime catalog discovery verifies coverage but never chooses merge semantics.';
COMMENT ON COLUMN internal.ghost_profile_merge_reference_policies.strategy IS
    'reparent moves rows directly; handler_then_reparent normalizes conflicts first; derived must be exhausted by its source-of-truth handler; preserve rejects any source reference; delete_source is reserved for public.users.id; blocked disables merging until support is implemented.';
COMMENT ON COLUMN internal.ghost_profile_merge_reference_policies.execution_order IS
    'Deterministic order for direct ownership updates after all explicit conflict handlers run.';
COMMENT ON COLUMN internal.ghost_profile_merge_reference_policies.handler_key IS
    'Reviewed implementation key asserted by migration contracts; it is documentation, never dynamically executed SQL.';

-- This manifest is intentionally explicit. A migration that adds, drops, or
-- retargets an eligible user FK must update the policy in the same change.
-- Unknown topology fails before a merge mutates user data.
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
        'internal', 'admin_audit_log', 'actor_user_id',
        'auth', 'users', 'id', 'preserve', 900, NULL,
        'Immutable administrator attribution may never be rewritten; anonymous sources must have no rows.'
    ),
    (
        'internal', 'admin_memberships', 'created_by',
        'auth', 'users', 'id', 'preserve', 900, NULL,
        'Administrator attribution may never be rewritten; anonymous sources must have no rows.'
    ),
    (
        'internal', 'admin_memberships', 'user_id',
        'auth', 'users', 'id', 'preserve', 900, NULL,
        'Anonymous identities may never transfer administrator authority during an account merge.'
    ),
    (
        'internal', 'admin_sessions', 'user_id',
        'auth', 'users', 'id', 'preserve', 900, NULL,
        'Anonymous identities may never transfer administrator sessions during an account merge.'
    ),
    (
        'internal', 'ai_quota_reservations', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Canonical quota attribution follows the permanent profile after ingestion generations are fenced.'
    ),
    (
        'internal', 'community_identification_activity_actors', 'user_id',
        'public', 'users', 'id', 'handler_then_reparent', 200,
        'community_activity_actors',
        'Actor counts are coalesced by activity group before any remaining ownership update.'
    ),
    (
        'internal', 'revenuecat_customer_state', 'merian_user_id',
        'public', 'users', 'id', 'handler_then_reparent', 250,
        'revenuecat_state',
        'Provider ordering watermarks are conflict-normalized before any remaining ownership update.'
    ),
    (
        'internal', 'revenuecat_reconciliation_queue', 'merian_user_id',
        'public', 'users', 'id', 'handler_then_reparent', 250,
        'revenuecat_state',
        'Provider repair work is made immediately due and conflict-normalized before ownership moves.'
    ),
    (
        'internal', 'revenuecat_webhook_event_subjects', 'merian_user_id',
        'public', 'users', 'id', 'handler_then_reparent', 250,
        'revenuecat_state',
        'Provider event subjects are deduplicated per event before any remaining ownership update.'
    ),
    (
        'internal', 'review_case_sources', 'reporter_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Moderation source attribution follows the canonical permanent profile after duplicate reports are resolved.'
    ),
    (
        'internal', 'review_cases', 'subject_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'The reviewed subject follows the canonical permanent profile.'
    ),
    (
        'internal', 'user_species_scan_counts', 'user_id',
        'public', 'users', 'id', 'derived', 900,
        'scan_species_ledger',
        'Derived from public.scans owner/species transitions and never updated directly.'
    ),
    (
        'public', 'collections', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Collection ownership follows the permanent account.'
    ),
    (
        'public', 'community_feedback', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Feedback ownership follows the permanent profile.'
    ),
    (
        'public', 'explore_comment_mentions', 'mentioned_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Mentions resolve to the canonical permanent profile.'
    ),
    (
        'public', 'explore_comment_reactions', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Reactions follow the permanent profile after duplicate and self-reaction resolution.'
    ),
    (
        'public', 'explore_comment_reports', 'comment_author_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Report subject attribution follows the canonical permanent profile.'
    ),
    (
        'public', 'explore_comment_reports', 'reporter_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Reporter attribution follows the canonical permanent profile after duplicate resolution.'
    ),
    (
        'public', 'explore_community_requests', 'requested_by',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Community request ownership follows the permanent profile.'
    ),
    (
        'public', 'explore_identifications', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Community identifications follow the permanent profile after active-vote conflict resolution.'
    ),
    (
        'public', 'explore_post_chat_conversations', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Explore chat conversations follow the permanent profile after conversation conflicts are merged.'
    ),
    (
        'public', 'explore_post_chat_message_feedback', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Explore chat feedback follows the permanent profile after duplicate resolution.'
    ),
    (
        'public', 'explore_post_chat_messages', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Explore chat message ownership follows the permanent profile.'
    ),
    (
        'public', 'explore_post_comments', 'moderated_by_user_id',
        'public', 'users', 'id', 'preserve', 900, NULL,
        'Moderator attribution may never be rewritten; anonymous sources must have no rows.'
    ),
    (
        'public', 'explore_post_comments', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Comment ownership follows the permanent profile.'
    ),
    (
        'public', 'explore_post_likes', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Likes follow the permanent profile after duplicate and self-like resolution.'
    ),
    (
        'public', 'explore_post_notifications', 'triggering_user_id',
        'public', 'users', 'id', 'derived', 800,
        'social_conflicts',
        'Ephemeral notification state involving the source is deleted by the social conflict handler.'
    ),
    (
        'public', 'explore_post_notifications', 'user_id',
        'public', 'users', 'id', 'derived', 800,
        'social_conflicts',
        'Ephemeral notification state involving the source is deleted by the social conflict handler.'
    ),
    (
        'public', 'explore_post_reports', 'post_author_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Report subject attribution follows the canonical permanent profile.'
    ),
    (
        'public', 'explore_post_reports', 'reporter_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Reporter attribution follows the canonical permanent profile after duplicate resolution.'
    ),
    (
        'public', 'explore_posts', 'moderated_by_user_id',
        'auth', 'users', 'id', 'preserve', 900, NULL,
        'Moderator attribution may never be rewritten; anonymous sources must have no rows.'
    ),
    (
        'public', 'explore_posts', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Published observation ownership follows the permanent profile.'
    ),
    (
        'public', 'export_jobs', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Export ownership follows the permanent account after active-job conflict resolution.'
    ),
    (
        'public', 'failed_scan_ingestions', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Failed ingestion ownership follows the permanent account.'
    ),
    (
        'public', 'feedback_survey_responses', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Survey response ownership follows the permanent profile.'
    ),
    (
        'public', 'field_trip_activity_notifications', 'actor_user_id',
        'public', 'users', 'id', 'derived', 800,
        'social_conflicts',
        'Ephemeral notification state involving the source is deleted by the social conflict handler.'
    ),
    (
        'public', 'field_trip_activity_notifications', 'user_id',
        'public', 'users', 'id', 'derived', 800,
        'social_conflicts',
        'Ephemeral notification state involving the source is deleted by the social conflict handler.'
    ),
    (
        'public', 'field_trip_challenge_badges', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Challenge badge ownership follows the permanent profile after challenge-state conflicts are merged.'
    ),
    (
        'public', 'field_trip_challenge_entries', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Challenge entry ownership follows the permanent profile after challenge-state conflicts are merged.'
    ),
    (
        'public', 'field_trip_challenge_entry_comments', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Challenge comment ownership follows the permanent profile.'
    ),
    (
        'public', 'field_trip_challenge_entry_likes', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Challenge likes follow the permanent profile after duplicate and self-like resolution.'
    ),
    (
        'public', 'field_trip_challenge_participants', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Challenge participation follows the permanent profile after participant conflicts are merged.'
    ),
    (
        'public', 'field_trip_publication_comments', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Field trip comment ownership follows the permanent profile.'
    ),
    (
        'public', 'field_trip_publication_likes', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Field trip likes follow the permanent profile after duplicate and self-like resolution.'
    ),
    (
        'public', 'field_trip_publications', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Field trip publication ownership follows the permanent profile after pin conflicts are normalized.'
    ),
    (
        'public', 'field_trip_scan_goal_preferences', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Selected field trip goal ownership follows the permanent profile after preference conflicts are merged.'
    ),
    (
        'public', 'field_trip_scan_progress_receipts', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Field trip progress receipt ownership follows the permanent profile.'
    ),
    (
        'public', 'flagged_reviews', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Flagged review ownership follows the permanent profile after moderation conflicts are normalized.'
    ),
    (
        'public', 'insight_chat_conversations', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Insight chat conversations follow the permanent profile after conversation conflicts are merged.'
    ),
    (
        'public', 'insight_chat_feature_feedback', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Insight feature feedback follows the permanent profile.'
    ),
    (
        'public', 'insight_chat_message_feedback', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Insight chat feedback follows the permanent profile after duplicate resolution.'
    ),
    (
        'public', 'insight_chat_messages', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Insight chat message ownership follows the permanent profile.'
    ),
    (
        'public', 'scan_deferred_context_updates', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Deferred context ownership follows the permanent account after ingestion generations are fenced.'
    ),
    (
        'public', 'scan_ingestion_intents', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Ingestion intent ownership follows the permanent account after generations are fenced.'
    ),
    (
        'public', 'scan_ingestion_jobs', 'user_id',
        'auth', 'users', 'id', 'reparent', 500, NULL,
        'Ingestion job ownership follows the permanent account after generations are fenced.'
    ),
    (
        'public', 'scan_media_assets', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Scan media ownership follows the permanent profile.'
    ),
    (
        'public', 'scans', 'user_id',
        'public', 'users', 'id', 'reparent', 100, NULL,
        'Scans move first so their statement trigger owns every derived species-ledger transition.'
    ),
    (
        'public', 'species_reference_image_merian_sources', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Reference-image contribution ownership follows the permanent profile.'
    ),
    (
        'public', 'user_blocks', 'blocked_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Block endpoints follow the permanent profile after relationship conflicts are rebuilt.'
    ),
    (
        'public', 'user_blocks', 'blocker_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Block endpoints follow the permanent profile after relationship conflicts are rebuilt.'
    ),
    (
        'public', 'user_field_trips', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Field trip ownership follows the permanent profile after trip-state conflicts are merged.'
    ),
    (
        'public', 'user_follows', 'followee_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Follow endpoints follow the permanent profile after relationship conflicts are rebuilt.'
    ),
    (
        'public', 'user_follows', 'follower_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Follow endpoints follow the permanent profile after relationship conflicts are rebuilt.'
    ),
    (
        'public', 'user_push_devices', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Push-device ownership follows the permanent profile.'
    ),
    (
        'public', 'user_reports', 'reported_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Report subject attribution follows the canonical permanent profile after self-report resolution.'
    ),
    (
        'public', 'user_reports', 'reporter_user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Reporter attribution follows the canonical permanent profile after duplicate resolution.'
    ),
    (
        'public', 'user_species_preferences', 'user_id',
        'public', 'users', 'id', 'reparent', 500, NULL,
        'Species preferences follow the permanent profile, whose conflicting choice wins.'
    ),
    (
        'public', 'users', 'id',
        'auth', 'users', 'id', 'delete_source', 1000, NULL,
        'The source public profile is deleted after all dependent ownership moves; its Auth identity is cleaned externally.'
    );

CREATE OR REPLACE FUNCTION internal.assert_ghost_profile_merge_reference_policy_coverage()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    unsupported_composite_references TEXT;
    missing_references TEXT;
    stale_policies TEXT;
    blocked_references TEXT;
BEGIN
    SELECT pg_catalog.STRING_AGG(
        pg_catalog.FORMAT(
            '%I.%I:%I',
            source_namespace.nspname,
            source_table.relname,
            constraint_row.conname
        ),
        ', '
        ORDER BY
            source_namespace.nspname,
            source_table.relname,
            constraint_row.conname
    )
    INTO unsupported_composite_references
    FROM pg_catalog.pg_constraint AS constraint_row
    JOIN pg_catalog.pg_class AS source_table
      ON source_table.oid = constraint_row.conrelid
    JOIN pg_catalog.pg_namespace AS source_namespace
      ON source_namespace.oid = source_table.relnamespace
    WHERE constraint_row.contype = 'f'
      AND constraint_row.confrelid IN (
          'public.users'::REGCLASS,
          'auth.users'::REGCLASS
      )
      AND (
          pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) <> 1
          OR pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) <> 1
      )
      AND NOT (
          constraint_row.confrelid = 'auth.users'::REGCLASS
          AND source_namespace.nspname = 'auth'
      );

    IF unsupported_composite_references IS NOT NULL THEN
        RAISE EXCEPTION
            'ghost_merge_schema_requires_composite_fk_policy: %',
            unsupported_composite_references
            USING ERRCODE = '55000';
    END IF;

    WITH effective_foreign_keys AS (
        SELECT DISTINCT
            source_namespace.nspname AS source_schema,
            source_table.relname AS source_table,
            source_column.attname AS source_column,
            target_namespace.nspname AS referenced_schema,
            target_table.relname AS referenced_table,
            target_column.attname AS referenced_column
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_class AS target_table
          ON target_table.oid = constraint_row.confrelid
        JOIN pg_catalog.pg_namespace AS target_namespace
          ON target_namespace.oid = target_table.relnamespace
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
    )
    SELECT pg_catalog.STRING_AGG(
        pg_catalog.FORMAT(
            '%I.%I.%I -> %I.%I.%I',
            foreign_key.source_schema,
            foreign_key.source_table,
            foreign_key.source_column,
            foreign_key.referenced_schema,
            foreign_key.referenced_table,
            foreign_key.referenced_column
        ),
        ', '
        ORDER BY
            foreign_key.source_schema,
            foreign_key.source_table,
            foreign_key.source_column,
            foreign_key.referenced_schema
    )
    INTO missing_references
    FROM effective_foreign_keys AS foreign_key
    LEFT JOIN internal.ghost_profile_merge_reference_policies AS policy
      ON policy.source_schema = foreign_key.source_schema
     AND policy.source_table = foreign_key.source_table
     AND policy.source_column = foreign_key.source_column
     AND policy.referenced_schema = foreign_key.referenced_schema
     AND policy.referenced_table = foreign_key.referenced_table
     AND policy.referenced_column = foreign_key.referenced_column
    WHERE policy.source_schema IS NULL;

    IF missing_references IS NOT NULL THEN
        RAISE EXCEPTION
            'ghost_merge_unclassified_reference: %',
            missing_references
            USING ERRCODE = '55000';
    END IF;

    WITH effective_foreign_keys AS (
        SELECT DISTINCT
            source_namespace.nspname AS source_schema,
            source_table.relname AS source_table,
            source_column.attname AS source_column,
            target_namespace.nspname AS referenced_schema,
            target_table.relname AS referenced_table,
            target_column.attname AS referenced_column
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_class AS target_table
          ON target_table.oid = constraint_row.confrelid
        JOIN pg_catalog.pg_namespace AS target_namespace
          ON target_namespace.oid = target_table.relnamespace
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
    )
    SELECT pg_catalog.STRING_AGG(
        pg_catalog.FORMAT(
            '%I.%I.%I -> %I.%I.%I',
            policy.source_schema,
            policy.source_table,
            policy.source_column,
            policy.referenced_schema,
            policy.referenced_table,
            policy.referenced_column
        ),
        ', '
        ORDER BY
            policy.source_schema,
            policy.source_table,
            policy.source_column,
            policy.referenced_schema
    )
    INTO stale_policies
    FROM internal.ghost_profile_merge_reference_policies AS policy
    LEFT JOIN effective_foreign_keys AS foreign_key
      ON foreign_key.source_schema = policy.source_schema
     AND foreign_key.source_table = policy.source_table
     AND foreign_key.source_column = policy.source_column
     AND foreign_key.referenced_schema = policy.referenced_schema
     AND foreign_key.referenced_table = policy.referenced_table
     AND foreign_key.referenced_column = policy.referenced_column
    WHERE foreign_key.source_schema IS NULL;

    IF stale_policies IS NOT NULL THEN
        RAISE EXCEPTION
            'ghost_merge_stale_reference_policy: %',
            stale_policies
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.strategy = 'delete_source'
          AND NOT (
              policy.source_schema = 'public'
              AND policy.source_table = 'users'
              AND policy.source_column = 'id'
              AND policy.referenced_schema = 'auth'
              AND policy.referenced_table = 'users'
              AND policy.referenced_column = 'id'
          )
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'public'
          AND policy.source_table = 'users'
          AND policy.source_column = 'id'
          AND policy.referenced_schema = 'auth'
          AND policy.referenced_table = 'users'
          AND policy.referenced_column = 'id'
          AND policy.strategy = 'delete_source'
    ) THEN
        RAISE EXCEPTION 'ghost_merge_invalid_source_profile_policy'
            USING ERRCODE = '55000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'internal'
          AND policy.source_table = 'user_species_scan_counts'
          AND policy.source_column = 'user_id'
          AND policy.referenced_schema = 'public'
          AND policy.referenced_table = 'users'
          AND policy.referenced_column = 'id'
          AND policy.strategy = 'derived'
          AND policy.handler_key = 'scan_species_ledger'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.source_schema = 'public'
          AND policy.source_table = 'scans'
          AND policy.source_column = 'user_id'
          AND policy.referenced_schema = 'public'
          AND policy.referenced_table = 'users'
          AND policy.referenced_column = 'id'
          AND policy.strategy = 'reparent'
          AND policy.execution_order < 900
    ) THEN
        RAISE EXCEPTION 'ghost_merge_invalid_scan_species_policy'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE policy.handler_key IS NOT NULL
          AND policy.handler_key NOT IN (
              'community_activity_actors',
              'revenuecat_state',
              'scan_species_ledger',
              'social_conflicts'
          )
    ) THEN
        RAISE EXCEPTION 'ghost_merge_unknown_policy_handler'
            USING ERRCODE = '55000';
    END IF;

    SELECT pg_catalog.STRING_AGG(
        pg_catalog.FORMAT(
            '%I.%I.%I',
            policy.source_schema,
            policy.source_table,
            policy.source_column
        ),
        ', '
        ORDER BY
            policy.source_schema,
            policy.source_table,
            policy.source_column
    )
    INTO blocked_references
    FROM internal.ghost_profile_merge_reference_policies AS policy
    WHERE policy.strategy = 'blocked';

    IF blocked_references IS NOT NULL THEN
        RAISE EXCEPTION
            'ghost_merge_blocked_reference: %',
            blocked_references
            USING ERRCODE = '55000';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.assert_ghost_profile_merge_reference_preconditions(
    p_ghost_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    policy RECORD;
    has_preserved_reference BOOLEAN;
BEGIN
    IF p_ghost_user_id IS NULL THEN
        RAISE EXCEPTION 'ghost_merge_invalid_source_identity'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage();

    FOR policy IN
        SELECT
            reference_policy.source_schema,
            reference_policy.source_table,
            reference_policy.source_column
        FROM internal.ghost_profile_merge_reference_policies
            AS reference_policy
        WHERE reference_policy.strategy = 'preserve'
        ORDER BY
            reference_policy.source_schema,
            reference_policy.source_table,
            reference_policy.source_column
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I = $1)',
            policy.source_schema,
            policy.source_table,
            policy.source_column
        )
        INTO has_preserved_reference
        USING p_ghost_user_id;

        IF has_preserved_reference THEN
            RAISE EXCEPTION
                'ghost_merge_preserved_reference_present: %.%.%',
                policy.source_schema,
                policy.source_table,
                policy.source_column
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_community_activity_actors(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    -- New actor inserts take a key-share lock on public.users and therefore
    -- wait behind the pair lock held by the orchestrator. Lock existing rows in
    -- one order so a concurrent count update completes before the next
    -- statement snapshots and coalesces it.
    PERFORM actor.user_id
    FROM internal.community_identification_activity_actors AS actor
    WHERE actor.user_id IN (p_ghost_user_id, p_target_user_id)
    ORDER BY actor.activity_group_id, actor.user_id
    FOR UPDATE;

    INSERT INTO internal.community_identification_activity_actors
        AS target_actor (
            activity_group_id,
            user_id,
            suggestion_count,
            last_suggested_at
        )
    SELECT
        source_actor.activity_group_id,
        p_target_user_id,
        source_actor.suggestion_count,
        source_actor.last_suggested_at
    FROM internal.community_identification_activity_actors AS source_actor
    WHERE source_actor.user_id = p_ghost_user_id
    ORDER BY source_actor.activity_group_id
    ON CONFLICT (activity_group_id, user_id) DO UPDATE
    SET suggestion_count =
            target_actor.suggestion_count + EXCLUDED.suggestion_count,
        last_suggested_at = GREATEST(
            target_actor.last_suggested_at,
            EXCLUDED.last_suggested_at
        );

    DELETE FROM internal.community_identification_activity_actors
        AS source_actor
    WHERE source_actor.user_id = p_ghost_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_revenuecat_state(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    -- A transfer event can already contain both source and destination. Keep
    -- the destination subject so changing the source identity cannot violate
    -- the per-event primary key.
    DELETE FROM internal.revenuecat_webhook_event_subjects AS source_subject
    USING internal.revenuecat_webhook_event_subjects AS target_subject
    WHERE source_subject.merian_user_id = p_ghost_user_id
      AND target_subject.merian_user_id = p_target_user_id
      AND target_subject.event_id = source_subject.event_id;

    -- Preserve the newest authoritative ordering watermark when both users
    -- already have state. If the target has no row, the remaining source row
    -- is reparented by the reviewed policy pass.
    UPDATE internal.revenuecat_customer_state AS target_state
    SET last_event_id = source_state.last_event_id,
        last_event_timestamp_ms = source_state.last_event_timestamp_ms,
        last_authoritative_snapshot_at_ms =
            source_state.last_authoritative_snapshot_at_ms,
        updated_at = GREATEST(
            target_state.updated_at,
            source_state.updated_at
        )
    FROM internal.revenuecat_customer_state AS source_state
    WHERE target_state.merian_user_id = p_target_user_id
      AND source_state.merian_user_id = p_ghost_user_id
      AND (
          source_state.last_authoritative_snapshot_at_ms
              > target_state.last_authoritative_snapshot_at_ms
          OR (
              source_state.last_authoritative_snapshot_at_ms
                  = target_state.last_authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms
                  > target_state.last_event_timestamp_ms
          )
          OR (
              source_state.last_authoritative_snapshot_at_ms
                  = target_state.last_authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms
                  = target_state.last_event_timestamp_ms
              AND source_state.last_event_id COLLATE pg_catalog."C"
                  > target_state.last_event_id COLLATE pg_catalog."C"
          )
      );

    DELETE FROM internal.revenuecat_customer_state AS source_state
    USING internal.revenuecat_customer_state AS target_state
    WHERE source_state.merian_user_id = p_ghost_user_id
      AND target_state.merian_user_id = p_target_user_id;

    -- A reconciler must query the permanent RevenueCat app-user identity. Any
    -- surviving source queue row is rewritten before its PK is reparented.
    UPDATE internal.revenuecat_reconciliation_queue AS source_queue
    SET lookup_app_user_id = p_target_user_id::TEXT,
        next_reconcile_at = LEAST(
            source_queue.next_reconcile_at,
            pg_catalog.NOW()
        ),
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE source_queue.merian_user_id = p_ghost_user_id;

    UPDATE internal.revenuecat_reconciliation_queue AS target_queue
    SET lookup_app_user_id = p_target_user_id::TEXT,
        next_reconcile_at = LEAST(
            target_queue.next_reconcile_at,
            pg_catalog.NOW()
        ),
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    FROM internal.revenuecat_reconciliation_queue AS source_queue
    WHERE target_queue.merian_user_id = p_target_user_id
      AND source_queue.merian_user_id = p_ghost_user_id;

    DELETE FROM internal.revenuecat_reconciliation_queue AS source_queue
    USING internal.revenuecat_reconciliation_queue AS target_queue
    WHERE source_queue.merian_user_id = p_ghost_user_id
      AND target_queue.merian_user_id = p_target_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.assert_ghost_profile_merge_species_ledger(
    p_user_ids UUID[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
BEGIN
    IF p_user_ids IS NULL
       OR pg_catalog.CARDINALITY(p_user_ids) = 0
       OR EXISTS (
           SELECT 1
           FROM pg_catalog.UNNEST(p_user_ids) AS requested(user_id)
           WHERE requested.user_id IS NULL
       ) THEN
        RAISE EXCEPTION 'ghost_merge_invalid_species_ledger_users'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        WITH requested_users AS (
            SELECT DISTINCT requested.user_id
            FROM pg_catalog.UNNEST(p_user_ids) AS requested(user_id)
        ),
        source_counts AS (
            SELECT
                scans.user_id,
                scans.species_id,
                pg_catalog.COUNT(*)::BIGINT AS scan_count
            FROM public.scans AS scans
            JOIN requested_users AS requested
              ON requested.user_id = scans.user_id
            WHERE scans.species_id IS NOT NULL
            GROUP BY scans.user_id, scans.species_id
        ),
        ledger_counts AS (
            SELECT
                counts.user_id,
                counts.species_id,
                counts.scan_count
            FROM internal.user_species_scan_counts AS counts
            JOIN requested_users AS requested
              ON requested.user_id = counts.user_id
        )
        SELECT 1
        FROM source_counts AS source_count
        FULL JOIN ledger_counts AS ledger_count
          ON ledger_count.user_id = source_count.user_id
         AND ledger_count.species_id = source_count.species_id
        WHERE COALESCE(source_count.scan_count, 0)
            <> COALESCE(ledger_count.scan_count, 0)
    ) THEN
        RAISE EXCEPTION 'ghost_merge_species_ledger_mismatch'
            USING ERRCODE = '23514';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.reparent_ghost_user_foreign_keys(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '25s'
AS $function$
DECLARE
    foreign_key RECORD;
    has_remaining_rows BOOLEAN;
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.assert_ghost_profile_merge_reference_preconditions(
        p_ghost_user_id
    );

    FOR foreign_key IN
        SELECT DISTINCT
            policy.execution_order,
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_class AS target_table
          ON target_table.oid = constraint_row.confrelid
        JOIN pg_catalog.pg_namespace AS target_namespace
          ON target_namespace.oid = target_table.relnamespace
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        JOIN internal.ghost_profile_merge_reference_policies AS policy
          ON policy.source_schema = source_namespace.nspname
         AND policy.source_table = source_table.relname
         AND policy.source_column = source_column.attname
         AND policy.referenced_schema = target_namespace.nspname
         AND policy.referenced_table = target_table.relname
         AND policy.referenced_column = target_column.attname
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
          AND policy.strategy IN (
              'reparent',
              'handler_then_reparent'
          )
        ORDER BY
            policy.execution_order,
            source_namespace.nspname,
            source_table.relname,
            source_column.attname
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'UPDATE %I.%I SET %I = $1 WHERE %I = $2',
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name,
            foreign_key.column_name
        )
        USING p_target_user_id, p_ghost_user_id;
    END LOOP;

    -- Derived species state must be exact before the source profile can be
    -- removed. The later public total recount can repair harmless historical
    -- projection drift, but ledger/source disagreement remains a hard error.
    PERFORM internal.assert_ghost_profile_merge_species_ledger(
        ARRAY[p_ghost_user_id, p_target_user_id]
    );

    -- Every non-profile strategy must exhaust the source reference. This
    -- verifies direct updates and proves that each derived/explicit handler
    -- actually ran before ON DELETE behavior can hide a missed relation.
    FOR foreign_key IN
        SELECT DISTINCT
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_class AS target_table
          ON target_table.oid = constraint_row.confrelid
        JOIN pg_catalog.pg_namespace AS target_namespace
          ON target_namespace.oid = target_table.relnamespace
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        JOIN internal.ghost_profile_merge_reference_policies AS policy
          ON policy.source_schema = source_namespace.nspname
         AND policy.source_table = source_table.relname
         AND policy.source_column = source_column.attname
         AND policy.referenced_schema = target_namespace.nspname
         AND policy.referenced_table = target_table.relname
         AND policy.referenced_column = target_column.attname
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
          AND policy.strategy <> 'delete_source'
        ORDER BY
            source_namespace.nspname,
            source_table.relname,
            source_column.attname
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I = $1)',
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name
        )
        INTO has_remaining_rows
        USING p_ghost_user_id;

        IF has_remaining_rows THEN
            RAISE EXCEPTION
                'ghost_merge_unhandled_reference: %.%.%',
                foreign_key.schema_name,
                foreign_key.table_name,
                foreign_key.column_name
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
END;
$function$;

-- Install the fail-closed topology/precondition assertion and the two new
-- conflict handlers before the first mutating helper in the reviewed merge.
-- Reading the effective catalog body preserves later migrations that inserted
-- scan-ingestion fencing and rewired trusted author-identity refresh.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT :=
        '    PERFORM internal.merge_ghost_chat_conversations(';
    replacement_fragment TEXT :=
        '    PERFORM internal.assert_ghost_profile_merge_reference_preconditions('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || '    PERFORM internal.merge_ghost_community_activity_actors('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id,'
        || pg_catalog.CHR(10)
        || '        p_target_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || '    PERFORM internal.merge_ghost_revenuecat_state('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id,'
        || pg_catalog.CHR(10)
        || '        p_target_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || '    PERFORM internal.merge_ghost_chat_conversations(';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'internal.perform_ghost_profile_merge(uuid,uuid)'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF (
        pg_catalog.LENGTH(function_definition)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_definition, guarded_fragment, '')
        )
    ) / pg_catalog.LENGTH(guarded_fragment) <> 1
       OR pg_catalog.STRPOS(
           function_definition,
           'assert_ghost_profile_merge_reference_preconditions('
       ) <> 0 THEN
        RAISE EXCEPTION 'ghost_merge_orchestrator_source_drift'
            USING ERRCODE = '55000';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF pg_catalog.STRPOS(
        rewritten_definition,
        'PERFORM internal.assert_ghost_profile_merge_reference_preconditions('
    ) = 0
       OR pg_catalog.STRPOS(
           rewritten_definition,
           'PERFORM internal.merge_ghost_community_activity_actors('
       ) = 0
       OR pg_catalog.STRPOS(
           rewritten_definition,
           'PERFORM internal.merge_ghost_revenuecat_state('
       ) = 0 THEN
        RAISE EXCEPTION 'ghost_merge_orchestrator_rewrite_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

COMMENT ON FUNCTION internal.assert_ghost_profile_merge_reference_policy_coverage() IS
    'Fails closed when eligible user-FK topology and the reviewed Ghost-merge policy differ, when composite support is required, or when any relation remains blocked.';
COMMENT ON FUNCTION internal.assert_ghost_profile_merge_reference_preconditions(UUID) IS
    'Runs topology coverage and rejects source rows whose attribution or authority is policy-classified as preserve before the Ghost merge mutates data.';
COMMENT ON FUNCTION internal.merge_ghost_community_activity_actors(UUID, UUID) IS
    'Coalesces source and destination Community Identify activity actor counts without primary-key collisions.';
COMMENT ON FUNCTION internal.merge_ghost_revenuecat_state(UUID, UUID) IS
    'Normalizes RevenueCat event subjects, ordering watermarks, and reconciliation work before reviewed ownership reparenting.';
COMMENT ON FUNCTION internal.assert_ghost_profile_merge_species_ledger(UUID[]) IS
    'Checks exact public.scans-to-ledger counts for a bounded user set before an atomic Ghost merge deletes its source profile.';
COMMENT ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID, UUID) IS
    'Policy-driven Ghost ownership transfer. Catalog discovery verifies coverage and resolves reviewed objects but never chooses merge semantics.';

REVOKE ALL ON FUNCTION
    internal.assert_ghost_profile_merge_reference_policy_coverage()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.assert_ghost_profile_merge_reference_preconditions(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.merge_ghost_community_activity_actors(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.merge_ghost_revenuecat_state(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.assert_ghost_profile_merge_species_ledger(UUID[])
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.reparent_ghost_user_foreign_keys(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
    internal.perform_ghost_profile_merge(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- Validate the manifest against the complete migrated catalog during deploy,
-- not only when the next user attempts an account upgrade.
SELECT internal.assert_ghost_profile_merge_reference_policy_coverage();

RESET lock_timeout;
RESET statement_timeout;

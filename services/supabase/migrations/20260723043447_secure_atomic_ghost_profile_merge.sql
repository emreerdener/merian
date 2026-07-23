-- Secure anonymous-to-existing-account handoff.
--
-- Normal anonymous upgrades should continue to use Supabase Auth identity
-- linking, which preserves the Auth UUID and requires no data merge. This
-- protocol exists only for the conflict case where the OAuth identity already
-- belongs to a different permanent account.
--
-- Security properties:
--   * the ghost session itself issues the handoff;
--   * the handoff is bound to the exact OAuth provider subject selected by the
--     ghost session;
--   * only a SHA-256 hash of the bearer secret is stored;
--   * consumption is one transaction, serialized per ghost user;
--   * retries by the same destination are idempotent;
--   * public execution is explicitly revoked from every privileged function.

-- These operational ledgers were intentionally created before public.users can
-- exist for a first anonymous scan. auth.users does exist before any
-- authenticated Edge request, however, so NOT VALID Auth FKs enforce all new
-- writes without making rollout depend on cleaning up historical orphan rows.
-- They also make source-user row locks serialize ingestion writes with a merge.
ALTER TABLE public.scan_ingestion_jobs
    ADD CONSTRAINT scan_ingestion_jobs_auth_user_fk
    FOREIGN KEY (user_id) REFERENCES auth.users(id)
    ON DELETE CASCADE NOT VALID;

ALTER TABLE public.scan_ingestion_intents
    ADD CONSTRAINT scan_ingestion_intents_auth_user_fk
    FOREIGN KEY (user_id) REFERENCES auth.users(id)
    ON DELETE CASCADE NOT VALID;

ALTER TABLE public.scan_deferred_context_updates
    ADD CONSTRAINT scan_deferred_context_updates_auth_user_fk
    FOREIGN KEY (user_id) REFERENCES auth.users(id)
    ON DELETE CASCADE NOT VALID;

ALTER TABLE public.failed_scan_ingestions
    ADD CONSTRAINT failed_scan_ingestions_auth_user_fk
    FOREIGN KEY (user_id) REFERENCES auth.users(id)
    ON DELETE CASCADE NOT VALID;

-- AI usage is normally immutable. A Ghost merge is the one ownership rewrite
-- that must retain attribution rather than look like account deletion. Bind
-- the exception to transaction-local source/target IDs and reject any attempt
-- to change another ledger field. Do not add an auth.users FK here: normal Auth
-- deletion is intentionally anonymized by the public.users deletion trigger,
-- while an ON DELETE SET NULL FK would reach this append-only trigger without
-- that transaction-local authorization.
CREATE OR REPLACE FUNCTION internal.trg_protect_ai_usage_events()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND CURRENT_SETTING('internal.ai_usage_anonymizing', TRUE) = 'on'
       AND OLD.user_id IS NOT NULL
       AND NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND CURRENT_SETTING('internal.ai_usage_reparenting', TRUE) = 'on'
       AND OLD.user_id::TEXT =
           CURRENT_SETTING('internal.ai_usage_reparent_source', TRUE)
       AND NEW.user_id::TEXT =
           CURRENT_SETTING('internal.ai_usage_reparent_target', TRUE)
       AND TO_JSONB(NEW) - 'user_id' = TO_JSONB(OLD) - 'user_id' THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'AI usage events are append-only.'
        USING ERRCODE = '42501';
END;
$$;

REVOKE ALL ON FUNCTION internal.trg_protect_ai_usage_events() FROM PUBLIC;

-- A bulk owner rewrite must not rebuild every normalized media manifest or
-- recount the destination's full species set once per scan. The transaction
-- flag is local to the merge and both derived surfaces are reconciled once
-- after all scan rows have moved.
CREATE OR REPLACE FUNCTION public.sync_global_species_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_user_id UUID;
BEGIN
    IF CURRENT_SETTING(
        'app.ghost_profile_merge_skip_scan_derivations',
        TRUE
    ) = 'on' THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'DELETE' THEN
        target_user_id := OLD.user_id;
    ELSE
        target_user_id := NEW.user_id;
    END IF;

    IF target_user_id IS NOT NULL
       AND target_user_id <>
           '00000000-0000-0000-0000-000000000000'::UUID THEN
        UPDATE public.users AS profile
        SET total_species_discovered = (
            SELECT COUNT(DISTINCT scan.species_id)
            FROM public.scans AS scan
            WHERE scan.user_id = target_user_id
              AND scan.species_id IS NOT NULL
        )
        WHERE profile.id = target_user_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets_for_scan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF CURRENT_SETTING(
        'app.ghost_profile_merge_skip_scan_derivations',
        TRUE
    ) = 'on' THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        DELETE FROM public.scan_media_assets
        WHERE scan_id = OLD.id;
        RETURN OLD;
    END IF;

    PERFORM public.refresh_scan_media_assets(NEW.id);
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_global_species_count()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_scan_media_assets_for_scan()
    FROM PUBLIC, anon, authenticated;

CREATE TABLE internal.ghost_profile_merge_handoffs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ghost_user_id UUID NOT NULL,
    target_user_id UUID,
    expected_provider TEXT NOT NULL
        CHECK (expected_provider IN ('apple', 'google')),
    expected_provider_subject TEXT NOT NULL
        CHECK (
            CHAR_LENGTH(expected_provider_subject) BETWEEN 1 AND 255
            AND expected_provider_subject !~ '[[:cntrl:]]'
        ),
    secret_hash TEXT NOT NULL UNIQUE
        CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
    status TEXT NOT NULL DEFAULT 'prepared'
        CHECK (status IN ('prepared', 'merged', 'superseded', 'expired')),
    expires_at TIMESTAMPTZ NOT NULL,
    merged_at TIMESTAMPTZ,
    auth_deleted_at TIMESTAMPTZ,
    cleanup_attempt_count INTEGER NOT NULL DEFAULT 0
        CHECK (cleanup_attempt_count >= 0),
    last_cleanup_error_code TEXT,
    cleanup_claim_token UUID,
    cleanup_claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (expires_at > created_at),
    CHECK (
        (status = 'merged' AND target_user_id IS NOT NULL AND merged_at IS NOT NULL)
        OR status <> 'merged'
    )
);

CREATE UNIQUE INDEX ghost_profile_merge_one_prepared_per_ghost_idx
    ON internal.ghost_profile_merge_handoffs (ghost_user_id)
    WHERE status = 'prepared';

CREATE UNIQUE INDEX ghost_profile_merge_one_completed_per_ghost_idx
    ON internal.ghost_profile_merge_handoffs (ghost_user_id)
    WHERE status = 'merged';

CREATE INDEX ghost_profile_merge_cleanup_idx
    ON internal.ghost_profile_merge_handoffs (merged_at, id)
    WHERE status = 'merged' AND auth_deleted_at IS NULL;

CREATE INDEX ghost_profile_merge_expiry_idx
    ON internal.ghost_profile_merge_handoffs (expires_at, id)
    WHERE status = 'prepared';

ALTER TABLE internal.ghost_profile_merge_handoffs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.ghost_profile_merge_handoffs
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE internal.ghost_profile_merge_handoffs TO service_role;

COMMENT ON TABLE internal.ghost_profile_merge_handoffs IS
    'Private, hashed, provider-bound proofs for atomic anonymous-profile merges.';

CREATE TABLE internal.ghost_user_cleanup_reservations (
    ghost_user_id UUID PRIMARY KEY,
    reservation_token UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    last_error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (expires_at > created_at OR completed_at IS NOT NULL)
);

CREATE INDEX ghost_user_cleanup_reservation_expiry_idx
    ON internal.ghost_user_cleanup_reservations (expires_at)
    WHERE completed_at IS NULL;

ALTER TABLE internal.ghost_user_cleanup_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.ghost_user_cleanup_reservations
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE internal.ghost_user_cleanup_reservations TO service_role;

COMMENT ON TABLE internal.ghost_user_cleanup_reservations IS
    'Short service-only leases preventing bulk empty-ghost cleanup from racing an account-upgrade handoff.';

CREATE OR REPLACE FUNCTION internal.repoint_merge_review_source(
    p_source_type TEXT,
    p_old_source_id UUID,
    p_new_source_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM internal.review_case_sources AS source
        WHERE source.source_type = p_source_type
          AND source.source_id = p_new_source_id
    ) THEN
        DELETE FROM internal.review_case_sources AS source
        WHERE source.source_type = p_source_type
          AND source.source_id = p_old_source_id;
    ELSE
        UPDATE internal.review_case_sources AS source
        SET source_id = p_new_source_id
        WHERE source.source_type = p_source_type
          AND source.source_id = p_old_source_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_social_conflicts(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    duplicate_report RECORD;
BEGIN
    -- Rebuild two-sided relationships after replacing the ghost endpoint.
    INSERT INTO public.user_blocks (blocker_id, blocked_id, created_at)
    SELECT DISTINCT ON (mapped.blocker_id, mapped.blocked_id)
        mapped.blocker_id,
        mapped.blocked_id,
        mapped.created_at
    FROM (
        SELECT
            CASE
                WHEN block.blocker_id = p_ghost_user_id THEN p_target_user_id
                ELSE block.blocker_id
            END AS blocker_id,
            CASE
                WHEN block.blocked_id = p_ghost_user_id THEN p_target_user_id
                ELSE block.blocked_id
            END AS blocked_id,
            block.created_at
        FROM public.user_blocks AS block
        WHERE block.blocker_id = p_ghost_user_id
           OR block.blocked_id = p_ghost_user_id
    ) AS mapped
    WHERE mapped.blocker_id <> mapped.blocked_id
    ORDER BY mapped.blocker_id, mapped.blocked_id, mapped.created_at
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

    DELETE FROM public.user_blocks AS block
    WHERE block.blocker_id = p_ghost_user_id
       OR block.blocked_id = p_ghost_user_id;

    INSERT INTO public.user_follows (
        follower_user_id,
        followee_user_id,
        created_at
    )
    SELECT DISTINCT ON (mapped.follower_user_id, mapped.followee_user_id)
        mapped.follower_user_id,
        mapped.followee_user_id,
        mapped.created_at
    FROM (
        SELECT
            CASE
                WHEN follow.follower_user_id = p_ghost_user_id
                    THEN p_target_user_id
                ELSE follow.follower_user_id
            END AS follower_user_id,
            CASE
                WHEN follow.followee_user_id = p_ghost_user_id
                    THEN p_target_user_id
                ELSE follow.followee_user_id
            END AS followee_user_id,
            follow.created_at
        FROM public.user_follows AS follow
        WHERE follow.follower_user_id = p_ghost_user_id
           OR follow.followee_user_id = p_ghost_user_id
    ) AS mapped
    WHERE mapped.follower_user_id <> mapped.followee_user_id
    ORDER BY
        mapped.follower_user_id,
        mapped.followee_user_id,
        mapped.created_at
    ON CONFLICT (follower_user_id, followee_user_id) DO NOTHING;

    DELETE FROM public.user_follows AS follow
    WHERE follow.follower_user_id = p_ghost_user_id
       OR follow.followee_user_id = p_ghost_user_id;

    -- Target-account choices win when both identities selected a preference.
    DELETE FROM public.user_species_preferences AS ghost_preference
    USING public.user_species_preferences AS target_preference
    WHERE ghost_preference.user_id = p_ghost_user_id
      AND target_preference.user_id = p_target_user_id
      AND target_preference.scientific_name = ghost_preference.scientific_name;

    -- Collapse duplicate reactions and likes before the generic FK reparent.
    DELETE FROM public.explore_post_likes AS ghost_like
    USING public.explore_post_likes AS target_like
    WHERE ghost_like.user_id = p_ghost_user_id
      AND target_like.user_id = p_target_user_id
      AND target_like.post_id = ghost_like.post_id;

    -- Likes and reactions that would become self-interactions are derived
    -- social state, not user-authored content. Remove them instead of carrying
    -- impossible self-activity into the destination profile.
    DELETE FROM public.explore_post_likes AS source_like
    USING public.explore_posts AS post
    WHERE source_like.post_id = post.id
      AND (
          source_like.user_id = p_ghost_user_id
          OR post.user_id = p_ghost_user_id
      )
      AND CASE
            WHEN source_like.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE source_like.user_id
          END
          =
          CASE
            WHEN post.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE post.user_id
          END;

    DELETE FROM public.explore_comment_reactions AS ghost_reaction
    USING public.explore_comment_reactions AS target_reaction
    WHERE ghost_reaction.user_id = p_ghost_user_id
      AND target_reaction.user_id = p_target_user_id
      AND target_reaction.comment_id = ghost_reaction.comment_id
      AND target_reaction.emoji = ghost_reaction.emoji;

    DELETE FROM public.explore_comment_reactions AS source_reaction
    USING public.explore_post_comments AS comment
    WHERE source_reaction.comment_id = comment.id
      AND (
          source_reaction.user_id = p_ghost_user_id
          OR comment.user_id = p_ghost_user_id
      )
      AND CASE
            WHEN source_reaction.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE source_reaction.user_id
          END
          =
          CASE
            WHEN comment.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE comment.user_id
          END;

    DELETE FROM public.explore_comment_mentions AS ghost_mention
    USING public.explore_comment_mentions AS target_mention
    WHERE ghost_mention.mentioned_user_id = p_ghost_user_id
      AND target_mention.mentioned_user_id = p_target_user_id
      AND target_mention.comment_id = ghost_mention.comment_id;

    DELETE FROM public.explore_comment_mentions AS source_mention
    USING public.explore_post_comments AS comment
    WHERE source_mention.comment_id = comment.id
      AND (
          source_mention.mentioned_user_id = p_ghost_user_id
          OR comment.user_id = p_ghost_user_id
      )
      AND CASE
            WHEN source_mention.mentioned_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE source_mention.mentioned_user_id
          END
          =
          CASE
            WHEN comment.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE comment.user_id
          END;

    DELETE FROM public.field_trip_publication_likes AS ghost_like
    USING public.field_trip_publication_likes AS target_like
    WHERE ghost_like.user_id = p_ghost_user_id
      AND target_like.user_id = p_target_user_id
      AND target_like.publication_id = ghost_like.publication_id;

    DELETE FROM public.field_trip_publication_likes AS source_like
    USING public.field_trip_publications AS publication
    WHERE source_like.publication_id = publication.id
      AND (
          source_like.user_id = p_ghost_user_id
          OR publication.user_id = p_ghost_user_id
      )
      AND CASE
            WHEN source_like.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE source_like.user_id
          END
          =
          CASE
            WHEN publication.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE publication.user_id
          END;

    DELETE FROM public.field_trip_challenge_entry_likes AS ghost_like
    USING public.field_trip_challenge_entry_likes AS target_like
    WHERE ghost_like.user_id = p_ghost_user_id
      AND target_like.user_id = p_target_user_id
      AND target_like.entry_id = ghost_like.entry_id;

    DELETE FROM public.field_trip_challenge_entry_likes AS source_like
    USING public.field_trip_challenge_entries AS entry
    WHERE source_like.entry_id = entry.id
      AND (
          source_like.user_id = p_ghost_user_id
          OR entry.user_id = p_ghost_user_id
      )
      AND CASE
            WHEN source_like.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE source_like.user_id
          END
          =
          CASE
            WHEN entry.user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE entry.user_id
          END;

    DELETE FROM public.insight_chat_message_feedback AS ghost_feedback
    USING public.insight_chat_message_feedback AS target_feedback
    WHERE ghost_feedback.user_id = p_ghost_user_id
      AND target_feedback.user_id = p_target_user_id
      AND target_feedback.message_id = ghost_feedback.message_id;

    DELETE FROM public.explore_post_chat_message_feedback AS ghost_feedback
    USING public.explore_post_chat_message_feedback AS target_feedback
    WHERE ghost_feedback.user_id = p_ghost_user_id
      AND target_feedback.user_id = p_target_user_id
      AND target_feedback.message_id = ghost_feedback.message_id;

    -- A user can contribute only one active identification per request.
    UPDATE public.explore_identifications AS ghost_identification
    SET withdrawn_at = COALESCE(ghost_identification.withdrawn_at, NOW())
    WHERE ghost_identification.user_id = p_ghost_user_id
      AND ghost_identification.withdrawn_at IS NULL
      AND EXISTS (
          SELECT 1
          FROM public.explore_identifications AS target_identification
          WHERE target_identification.user_id = p_target_user_id
            AND target_identification.request_id =
                ghost_identification.request_id
            AND target_identification.withdrawn_at IS NULL
      );

    -- Notifications are derived, ephemeral state. Drop every row where the
    -- source is a recipient or actor. Rewriting actor arrays would leave stale
    -- action counts and can collide with follow/activity partial indexes; the
    -- source likes/comments/follows remain authoritative.
    DELETE FROM public.explore_post_notifications AS notification
    WHERE notification.user_id = p_ghost_user_id
       OR notification.triggering_user_id = p_ghost_user_id
       OR p_ghost_user_id = ANY(notification.recent_actor_ids);

    DELETE FROM public.field_trip_activity_notifications AS notification
    WHERE notification.user_id = p_ghost_user_id
       OR notification.actor_user_id = p_ghost_user_id;

    -- Preserve moderation source links while collapsing duplicate reports.
    FOR duplicate_report IN
        SELECT ghost_report.id AS ghost_id, target_report.id AS target_id
        FROM public.explore_post_reports AS ghost_report
        JOIN public.explore_post_reports AS target_report
          ON target_report.post_id = ghost_report.post_id
         AND target_report.reporter_user_id = p_target_user_id
        WHERE ghost_report.reporter_user_id = p_ghost_user_id
    LOOP
        PERFORM internal.repoint_merge_review_source(
            'explore_post_report',
            duplicate_report.ghost_id,
            duplicate_report.target_id
        );
        DELETE FROM public.explore_post_reports
        WHERE id = duplicate_report.ghost_id;
    END LOOP;

    FOR duplicate_report IN
        SELECT ghost_report.id AS ghost_id, target_report.id AS target_id
        FROM public.explore_comment_reports AS ghost_report
        JOIN public.explore_comment_reports AS target_report
          ON target_report.comment_id = ghost_report.comment_id
         AND target_report.reporter_user_id = p_target_user_id
        WHERE ghost_report.reporter_user_id = p_ghost_user_id
    LOOP
        PERFORM internal.repoint_merge_review_source(
            'explore_comment_report',
            duplicate_report.ghost_id,
            duplicate_report.target_id
        );
        DELETE FROM public.explore_comment_reports
        WHERE id = duplicate_report.ghost_id;
    END LOOP;

    -- Reports that would become self-reports after the ownership rewrite are
    -- no longer meaningful moderation evidence.
    DELETE FROM internal.review_case_sources AS source
    USING public.explore_post_reports AS report
    WHERE source.source_type = 'explore_post_report'
      AND source.source_id = report.id
      AND (
          report.reporter_user_id = p_ghost_user_id
          OR report.post_author_user_id = p_ghost_user_id
      )
      AND CASE
            WHEN report.reporter_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.reporter_user_id
          END
          =
          CASE
            WHEN report.post_author_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.post_author_user_id
          END;

    DELETE FROM public.explore_post_reports AS report
    WHERE (
          report.reporter_user_id = p_ghost_user_id
          OR report.post_author_user_id = p_ghost_user_id
      )
      AND CASE
            WHEN report.reporter_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.reporter_user_id
          END
          =
          CASE
            WHEN report.post_author_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.post_author_user_id
          END;

    DELETE FROM internal.review_case_sources AS source
    USING public.explore_comment_reports AS report
    WHERE source.source_type = 'explore_comment_report'
      AND source.source_id = report.id
      AND (
          report.reporter_user_id = p_ghost_user_id
          OR report.comment_author_user_id = p_ghost_user_id
      )
      AND CASE
            WHEN report.reporter_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.reporter_user_id
          END
          =
          CASE
            WHEN report.comment_author_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.comment_author_user_id
          END;

    DELETE FROM public.explore_comment_reports AS report
    WHERE (
          report.reporter_user_id = p_ghost_user_id
          OR report.comment_author_user_id = p_ghost_user_id
      )
      AND CASE
            WHEN report.reporter_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.reporter_user_id
          END
          =
          CASE
            WHEN report.comment_author_user_id = p_ghost_user_id
                THEN p_target_user_id
            ELSE report.comment_author_user_id
          END;

    FOR duplicate_report IN
        SELECT ghost_report.id AS ghost_id, target_report.id AS target_id
        FROM public.user_reports AS ghost_report
        JOIN public.user_reports AS target_report
          ON target_report.reporter_user_id = CASE
                WHEN ghost_report.reporter_user_id = p_ghost_user_id
                    THEN p_target_user_id
                ELSE ghost_report.reporter_user_id
             END
         AND target_report.reported_user_id = CASE
                WHEN ghost_report.reported_user_id = p_ghost_user_id
                    THEN p_target_user_id
                ELSE ghost_report.reported_user_id
             END
         AND target_report.reporter_user_id <> p_ghost_user_id
         AND target_report.reported_user_id <> p_ghost_user_id
        WHERE ghost_report.reporter_user_id = p_ghost_user_id
           OR ghost_report.reported_user_id = p_ghost_user_id
    LOOP
        PERFORM internal.repoint_merge_review_source(
            'user_report',
            duplicate_report.ghost_id,
            duplicate_report.target_id
        );
        DELETE FROM public.user_reports
        WHERE id = duplicate_report.ghost_id;
    END LOOP;

    -- Reports between the two identities become meaningless self-reports.
    DELETE FROM internal.review_case_sources AS source
    USING public.user_reports AS report
    WHERE source.source_type = 'user_report'
      AND source.source_id = report.id
      AND (
          (report.reporter_user_id = p_ghost_user_id
            AND report.reported_user_id = p_target_user_id)
          OR
          (report.reporter_user_id = p_target_user_id
            AND report.reported_user_id = p_ghost_user_id)
      );

    DELETE FROM public.user_reports AS report
    WHERE (report.reporter_user_id = p_ghost_user_id
            AND report.reported_user_id = p_target_user_id)
       OR (report.reporter_user_id = p_target_user_id
            AND report.reported_user_id = p_ghost_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_chat_conversations(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
END;
$$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_field_trip_state(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    trip_pair RECORD;
    participant_pair RECORD;
    ghost_publication_id UUID;
    target_publication_id UUID;
    ghost_entry_id UUID;
    target_entry_id UUID;
BEGIN
    -- Merge duplicate standard outings by template while retaining every
    -- non-conflicting scan credit and public comment.
    FOR trip_pair IN
        SELECT
            ghost_trip.id AS ghost_id,
            target_trip.id AS target_id
        FROM public.user_field_trips AS ghost_trip
        JOIN public.user_field_trips AS target_trip
          ON target_trip.template_id = ghost_trip.template_id
         AND target_trip.user_id = p_target_user_id
        WHERE ghost_trip.user_id = p_ghost_user_id
        ORDER BY ghost_trip.id
    LOOP
        UPDATE public.user_field_trip_active_periods AS period
        SET stopped_at = NOW()
        WHERE period.user_field_trip_id = trip_pair.ghost_id
          AND period.stopped_at IS NULL;

        UPDATE public.user_field_trip_active_periods AS period
        SET user_field_trip_id = trip_pair.target_id
        WHERE period.user_field_trip_id = trip_pair.ghost_id;

        DELETE FROM public.user_field_trip_item_completions AS ghost_completion
        USING public.user_field_trip_item_completions AS target_completion
        WHERE ghost_completion.user_field_trip_id = trip_pair.ghost_id
          AND target_completion.user_field_trip_id = trip_pair.target_id
          AND (
              target_completion.item_id = ghost_completion.item_id
              OR target_completion.scan_id = ghost_completion.scan_id
          );

        UPDATE public.user_field_trip_item_completions AS completion
        SET user_field_trip_id = trip_pair.target_id
        WHERE completion.user_field_trip_id = trip_pair.ghost_id;

        UPDATE public.field_trip_scan_goal_preferences AS preference
        SET user_field_trip_id = trip_pair.target_id
        WHERE preference.user_field_trip_id = trip_pair.ghost_id;

        UPDATE public.field_trip_scan_progress_receipts AS receipt
        SET preferred_user_field_trip_id = trip_pair.target_id
        WHERE receipt.preferred_user_field_trip_id = trip_pair.ghost_id;

        UPDATE public.field_trip_challenge_participants AS participant
        SET user_field_trip_id = trip_pair.target_id
        WHERE participant.user_field_trip_id = trip_pair.ghost_id;

        ghost_publication_id := NULL;
        target_publication_id := NULL;

        SELECT publication.id
        INTO ghost_publication_id
        FROM public.field_trip_publications AS publication
        WHERE publication.user_field_trip_id = trip_pair.ghost_id;

        SELECT publication.id
        INTO target_publication_id
        FROM public.field_trip_publications AS publication
        WHERE publication.user_field_trip_id = trip_pair.target_id;

        IF ghost_publication_id IS NOT NULL
           AND target_publication_id IS NOT NULL THEN
            DELETE FROM public.field_trip_publication_items AS ghost_item
            USING public.field_trip_publication_items AS target_item
            WHERE ghost_item.publication_id = ghost_publication_id
              AND target_item.publication_id = target_publication_id
              AND target_item.item_id = ghost_item.item_id;

            UPDATE public.field_trip_publication_items AS item
            SET publication_id = target_publication_id
            WHERE item.publication_id = ghost_publication_id;

            INSERT INTO public.field_trip_publication_likes (
                publication_id,
                user_id,
                created_at
            )
            SELECT
                target_publication_id,
                CASE
                    WHEN source_like.user_id = p_ghost_user_id
                        THEN p_target_user_id
                    ELSE source_like.user_id
                END,
                source_like.created_at
            FROM public.field_trip_publication_likes AS source_like
            WHERE source_like.publication_id = ghost_publication_id
              AND source_like.user_id NOT IN (
                  p_ghost_user_id,
                  p_target_user_id
              )
            ON CONFLICT (publication_id, user_id) DO NOTHING;

            DELETE FROM public.field_trip_publication_likes AS source_like
            WHERE source_like.publication_id = ghost_publication_id;

            UPDATE public.field_trip_publication_comments AS comment
            SET publication_id = target_publication_id
            WHERE comment.publication_id = ghost_publication_id;

            DELETE FROM public.field_trip_activity_notifications AS notification
            WHERE notification.publication_id = ghost_publication_id;

            DELETE FROM public.field_trip_publications
            WHERE id = ghost_publication_id;
        ELSIF ghost_publication_id IS NOT NULL THEN
            UPDATE public.field_trip_publications AS publication
            SET user_field_trip_id = trip_pair.target_id
            WHERE publication.id = ghost_publication_id;
        END IF;

        UPDATE public.user_field_trips AS target_trip
        SET started_at = LEAST(target_trip.started_at, ghost_trip.started_at),
            current_level_number = GREATEST(
                target_trip.current_level_number,
                ghost_trip.current_level_number
            ),
            completed_at = CASE
                WHEN target_trip.completed_at IS NULL THEN ghost_trip.completed_at
                WHEN ghost_trip.completed_at IS NULL THEN target_trip.completed_at
                ELSE LEAST(target_trip.completed_at, ghost_trip.completed_at)
            END,
            is_profile_visible =
                target_trip.is_profile_visible OR ghost_trip.is_profile_visible,
            hidden_at = CASE
                WHEN target_trip.is_profile_visible
                  OR ghost_trip.is_profile_visible THEN NULL
                ELSE COALESCE(target_trip.hidden_at, ghost_trip.hidden_at)
            END,
            updated_at = GREATEST(target_trip.updated_at, ghost_trip.updated_at)
        FROM public.user_field_trips AS ghost_trip
        WHERE target_trip.id = trip_pair.target_id
          AND ghost_trip.id = trip_pair.ghost_id;

        DELETE FROM public.user_field_trips
        WHERE id = trip_pair.ghost_id;
    END LOOP;

    -- Merge duplicate challenge participation after standard outings have been
    -- canonicalized.
    FOR participant_pair IN
        SELECT
            ghost_participant.id AS ghost_id,
            target_participant.id AS target_id
        FROM public.field_trip_challenge_participants AS ghost_participant
        JOIN public.field_trip_challenge_participants AS target_participant
          ON target_participant.challenge_id =
              ghost_participant.challenge_id
         AND target_participant.user_id = p_target_user_id
        WHERE ghost_participant.user_id = p_ghost_user_id
        ORDER BY ghost_participant.id
    LOOP
        DELETE FROM public.field_trip_challenge_item_completions
            AS ghost_completion
        USING public.field_trip_challenge_item_completions
            AS target_completion
        WHERE ghost_completion.participation_id = participant_pair.ghost_id
          AND target_completion.participation_id = participant_pair.target_id
          AND (
              target_completion.item_id = ghost_completion.item_id
              OR target_completion.scan_id = ghost_completion.scan_id
          );

        UPDATE public.field_trip_challenge_item_completions AS completion
        SET participation_id = participant_pair.target_id
        WHERE completion.participation_id = participant_pair.ghost_id;

        IF EXISTS (
            SELECT 1
            FROM public.field_trip_challenge_badges AS badge
            WHERE badge.participation_id = participant_pair.target_id
        ) THEN
            DELETE FROM public.field_trip_challenge_badges
            WHERE participation_id = participant_pair.ghost_id;
        ELSE
            UPDATE public.field_trip_challenge_badges AS badge
            SET participation_id = participant_pair.target_id,
                user_id = p_target_user_id
            WHERE badge.participation_id = participant_pair.ghost_id;
        END IF;

        ghost_entry_id := NULL;
        target_entry_id := NULL;

        SELECT entry.id
        INTO ghost_entry_id
        FROM public.field_trip_challenge_entries AS entry
        WHERE entry.participation_id = participant_pair.ghost_id;

        SELECT entry.id
        INTO target_entry_id
        FROM public.field_trip_challenge_entries AS entry
        WHERE entry.participation_id = participant_pair.target_id;

        IF ghost_entry_id IS NOT NULL AND target_entry_id IS NOT NULL THEN
            DELETE FROM public.field_trip_challenge_entry_items AS ghost_item
            USING public.field_trip_challenge_entry_items AS target_item
            WHERE ghost_item.entry_id = ghost_entry_id
              AND target_item.entry_id = target_entry_id
              AND target_item.item_id = ghost_item.item_id;

            UPDATE public.field_trip_challenge_entry_items AS item
            SET entry_id = target_entry_id
            WHERE item.entry_id = ghost_entry_id;

            INSERT INTO public.field_trip_challenge_entry_likes (
                entry_id,
                user_id,
                created_at
            )
            SELECT
                target_entry_id,
                CASE
                    WHEN source_like.user_id = p_ghost_user_id
                        THEN p_target_user_id
                    ELSE source_like.user_id
                END,
                source_like.created_at
            FROM public.field_trip_challenge_entry_likes AS source_like
            WHERE source_like.entry_id = ghost_entry_id
              AND source_like.user_id NOT IN (
                  p_ghost_user_id,
                  p_target_user_id
              )
            ON CONFLICT (entry_id, user_id) DO NOTHING;

            DELETE FROM public.field_trip_challenge_entry_likes AS source_like
            WHERE source_like.entry_id = ghost_entry_id;

            UPDATE public.field_trip_challenge_entry_comments AS comment
            SET entry_id = target_entry_id
            WHERE comment.entry_id = ghost_entry_id;

            DELETE FROM public.field_trip_challenge_entries
            WHERE id = ghost_entry_id;
        ELSIF ghost_entry_id IS NOT NULL THEN
            UPDATE public.field_trip_challenge_entries AS entry
            SET participation_id = participant_pair.target_id,
                user_id = p_target_user_id
            WHERE entry.id = ghost_entry_id;
        END IF;

        UPDATE public.field_trip_challenge_participants AS target_participant
        SET joined_at = LEAST(
                target_participant.joined_at,
                ghost_participant.joined_at
            ),
            current_level_number = GREATEST(
                target_participant.current_level_number,
                ghost_participant.current_level_number
            ),
            completed_at = CASE
                WHEN target_participant.completed_at IS NULL
                    THEN ghost_participant.completed_at
                WHEN ghost_participant.completed_at IS NULL
                    THEN target_participant.completed_at
                ELSE LEAST(
                    target_participant.completed_at,
                    ghost_participant.completed_at
                )
            END,
            badge_awarded_at = CASE
                WHEN target_participant.badge_awarded_at IS NULL
                    THEN ghost_participant.badge_awarded_at
                WHEN ghost_participant.badge_awarded_at IS NULL
                    THEN target_participant.badge_awarded_at
                ELSE LEAST(
                    target_participant.badge_awarded_at,
                    ghost_participant.badge_awarded_at
                )
            END,
            is_profile_visible =
                target_participant.is_profile_visible
                OR ghost_participant.is_profile_visible,
            hidden_at = CASE
                WHEN target_participant.is_profile_visible
                  OR ghost_participant.is_profile_visible THEN NULL
                ELSE COALESCE(
                    target_participant.hidden_at,
                    ghost_participant.hidden_at
                )
            END,
            updated_at = GREATEST(
                target_participant.updated_at,
                ghost_participant.updated_at
            )
        FROM public.field_trip_challenge_participants AS ghost_participant
        WHERE target_participant.id = participant_pair.target_id
          AND ghost_participant.id = participant_pair.ghost_id;

        DELETE FROM public.field_trip_challenge_participants
        WHERE id = participant_pair.ghost_id;
    END LOOP;

    -- Two different publications may use the same profile pin position.
    UPDATE public.field_trip_publications AS ghost_publication
    SET profile_pin_position = NULL
    WHERE ghost_publication.user_id = p_ghost_user_id
      AND ghost_publication.profile_pin_position IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM public.field_trip_publications AS target_publication
          WHERE target_publication.user_id = p_target_user_id
            AND target_publication.profile_pin_position =
                ghost_publication.profile_pin_position
            AND target_publication.deleted_at IS NULL
      );
END;
$$;

CREATE OR REPLACE FUNCTION internal.reparent_ghost_user_foreign_keys(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    foreign_key RECORD;
    has_remaining_rows BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint AS constraint_row
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND (
              ARRAY_LENGTH(constraint_row.conkey, 1) <> 1
              OR ARRAY_LENGTH(constraint_row.confkey, 1) <> 1
          )
          AND constraint_row.conrelid::REGCLASS::TEXT
              NOT LIKE 'auth.%'
    ) THEN
        RAISE EXCEPTION 'ghost_merge_schema_requires_explicit_composite_fk_support'
            USING ERRCODE = '55000';
    END IF;

    FOR foreign_key IN
        SELECT
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name,
            constraint_row.confrelid
        FROM pg_constraint AS constraint_row
        JOIN pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
        ORDER BY
            source_namespace.nspname,
            source_table.relname,
            source_column.attname
    LOOP
        EXECUTE FORMAT(
            'UPDATE %I.%I SET %I = $1 WHERE %I = $2',
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name,
            foreign_key.column_name
        )
        USING p_target_user_id, p_ghost_user_id;
    END LOOP;

    -- Refuse to delete the public profile if a future FK could not be
    -- reparented. This converts schema drift into a safe merge failure rather
    -- than an ON DELETE CASCADE data-loss event.
    FOR foreign_key IN
        SELECT
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name,
            constraint_row.confrelid
        FROM pg_constraint AS constraint_row
        JOIN pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
    LOOP
        EXECUTE FORMAT(
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
$$;

CREATE OR REPLACE FUNCTION internal.perform_ghost_profile_merge(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    ghost_profile public.users%ROWTYPE;
    default_ghost_username TEXT;
BEGIN
    PERFORM profile.id
    FROM public.users AS profile
    WHERE profile.id IN (p_ghost_user_id, p_target_user_id)
    ORDER BY profile.id
    FOR UPDATE;

    SELECT profile.*
    INTO STRICT ghost_profile
    FROM public.users AS profile
    WHERE profile.id = p_ghost_user_id;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id = p_target_user_id
    ) THEN
        RAISE EXCEPTION 'ghost_merge_target_profile_missing'
            USING ERRCODE = 'P0002';
    END IF;

    default_ghost_username :=
        public.build_default_public_username(p_ghost_user_id);

    PERFORM internal.merge_ghost_chat_conversations(
        p_ghost_user_id,
        p_target_user_id
    );
    PERFORM internal.merge_ghost_field_trip_state(
        p_ghost_user_id,
        p_target_user_id
    );
    PERFORM internal.merge_ghost_social_conflicts(
        p_ghost_user_id,
        p_target_user_id
    );

    -- Prevent uniqueness conflicts in operational ledgers before their new
    -- auth.users foreign keys are handled by the generic reparent pass.
    DELETE FROM public.scan_ingestion_jobs AS ghost_job
    USING public.scan_ingestion_jobs AS target_job
    WHERE ghost_job.user_id = p_ghost_user_id
      AND target_job.user_id = p_target_user_id
      AND target_job.scan_id = ghost_job.scan_id;

    DELETE FROM public.scan_ingestion_intents AS ghost_intent
    USING public.scan_ingestion_intents AS target_intent
    WHERE ghost_intent.user_id = p_ghost_user_id
      AND target_intent.user_id = p_target_user_id
      AND target_intent.scan_id = ghost_intent.scan_id;

    DELETE FROM public.scan_deferred_context_updates AS ghost_context
    USING public.scan_deferred_context_updates AS target_context
    WHERE ghost_context.user_id = p_ghost_user_id
      AND target_context.user_id = p_target_user_id
      AND target_context.scan_id = ghost_context.scan_id;

    -- At most one export can be non-terminal after the identities converge.
    UPDATE public.export_jobs AS ghost_job
    SET status = 'failed',
        error_message = 'Superseded during account merge'
    WHERE ghost_job.user_id = p_ghost_user_id
      AND ghost_job.status NOT IN ('completed', 'failed')
      AND EXISTS (
          SELECT 1
          FROM public.export_jobs AS target_job
          WHERE target_job.user_id = p_target_user_id
            AND target_job.status NOT IN ('completed', 'failed')
      );

    -- A deletion request for the source identity must never follow its data to
    -- the permanent account.
    DELETE FROM public.pending_storage_deletions
    WHERE target_user_id = p_ghost_user_id;

    PERFORM SET_CONFIG(
        'app.ghost_profile_merge_skip_scan_derivations',
        'on',
        TRUE
    );
    PERFORM SET_CONFIG(
        'internal.ai_usage_reparent_source',
        p_ghost_user_id::TEXT,
        TRUE
    );
    PERFORM SET_CONFIG(
        'internal.ai_usage_reparent_target',
        p_target_user_id::TEXT,
        TRUE
    );
    PERFORM SET_CONFIG(
        'internal.ai_usage_reparenting',
        'on',
        TRUE
    );

    -- ai_usage_events intentionally has no user FK because its account-delete
    -- anonymization is trigger-controlled. Reparent it explicitly before the
    -- catalog-driven FK pass.
    UPDATE public.ai_usage_events AS event
    SET user_id = p_target_user_id
    WHERE event.user_id = p_ghost_user_id;

    PERFORM internal.reparent_ghost_user_foreign_keys(
        p_ghost_user_id,
        p_target_user_id
    );

    PERFORM SET_CONFIG(
        'internal.ai_usage_reparenting',
        'off',
        TRUE
    );

    UPDATE public.users AS target_profile
    SET total_species_discovered = (
        SELECT COUNT(DISTINCT scan.species_id)
        FROM public.scans AS scan
        WHERE scan.user_id = p_target_user_id
          AND scan.species_id IS NOT NULL
    )
    WHERE target_profile.id = p_target_user_id;

    PERFORM SET_CONFIG(
        'app.ghost_profile_merge_skip_scan_derivations',
        'off',
        TRUE
    );

    DELETE FROM public.users
    WHERE id = p_ghost_user_id;

    PERFORM public.refresh_public_author_identity(p_target_user_id);

    UPDATE public.users AS target_profile
    SET public_author_name = CASE
            WHEN ghost_profile.public_identity_source = 'display_name'
             AND NULLIF(BTRIM(ghost_profile.public_author_name), '') IS NOT NULL
                THEN BTRIM(ghost_profile.public_author_name)
            ELSE target_profile.public_author_name
        END,
        public_identity_source = CASE
            WHEN ghost_profile.public_identity_source = 'display_name'
             AND NULLIF(BTRIM(ghost_profile.public_author_name), '') IS NOT NULL
                THEN 'display_name'
            ELSE target_profile.public_identity_source
        END,
        public_username = CASE
            WHEN ghost_profile.public_username <> default_ghost_username
                THEN ghost_profile.public_username
            ELSE target_profile.public_username
        END,
        custom_avatar_url = CASE
            WHEN NULLIF(BTRIM(ghost_profile.custom_avatar_url), '') IS NOT NULL
                THEN ghost_profile.custom_avatar_url
            ELSE target_profile.custom_avatar_url
        END,
        custom_avatar_updated_at = CASE
            WHEN NULLIF(BTRIM(ghost_profile.custom_avatar_url), '') IS NOT NULL
                THEN COALESCE(ghost_profile.custom_avatar_updated_at, NOW())
            ELSE target_profile.custom_avatar_updated_at
        END,
        public_avatar_url = CASE
            WHEN NULLIF(BTRIM(ghost_profile.custom_avatar_url), '') IS NOT NULL
                THEN ghost_profile.custom_avatar_url
            ELSE target_profile.public_avatar_url
        END
    WHERE target_profile.id = p_target_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_ghost_profile_merge_handoff(
    p_secret_hash TEXT,
    p_expected_provider TEXT,
    p_expected_provider_subject TEXT
)
RETURNS TABLE (
    handoff_id UUID,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    caller_id UUID := auth.uid();
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'ghost_merge_authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'ghost_merge_invalid_secret_hash'
            USING ERRCODE = '22023';
    END IF;

    IF p_expected_provider NOT IN ('apple', 'google') THEN
        RAISE EXCEPTION 'ghost_merge_invalid_provider'
            USING ERRCODE = '22023';
    END IF;

    IF p_expected_provider_subject IS NULL
       OR CHAR_LENGTH(p_expected_provider_subject) NOT BETWEEN 1 AND 255
       OR p_expected_provider_subject ~ '[[:cntrl:]]' THEN
        RAISE EXCEPTION 'ghost_merge_invalid_provider_subject'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('ghost-profile-merge:' || caller_id::TEXT, 0)
    );

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_user_cleanup_reservations AS reservation
        WHERE reservation.ghost_user_id = caller_id
          AND reservation.completed_at IS NULL
          AND reservation.expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_cleanup_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = caller_id
          AND auth_user.is_anonymous = TRUE
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_must_be_anonymous'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.ghost_user_id = caller_id
          AND handoff.status = 'merged'
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_already_merged'
            USING ERRCODE = '23505';
    END IF;

    UPDATE internal.ghost_profile_merge_handoffs AS handoff
    SET status = CASE
            WHEN handoff.expires_at <= NOW() THEN 'expired'
            ELSE 'superseded'
        END,
        updated_at = NOW()
    WHERE handoff.ghost_user_id = caller_id
      AND handoff.status = 'prepared';

    RETURN QUERY
    INSERT INTO internal.ghost_profile_merge_handoffs AS handoff (
        ghost_user_id,
        expected_provider,
        expected_provider_subject,
        secret_hash,
        expires_at
    )
    VALUES (
        caller_id,
        p_expected_provider,
        p_expected_provider_subject,
        p_secret_hash,
        NOW() + INTERVAL '30 days'
    )
    RETURNING handoff.id, handoff.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_ghost_profile_merge_handoff(
    p_handoff_id UUID,
    p_secret_hash TEXT
)
RETURNS TABLE (
    handoff_id UUID,
    ghost_user_id UUID,
    target_user_id UUID,
    already_merged BOOLEAN,
    merged_at TIMESTAMPTZ,
    auth_deleted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '30s'
AS $$
DECLARE
    caller_id UUID := auth.uid();
    source_user_id UUID;
    handoff_record internal.ghost_profile_merge_handoffs%ROWTYPE;
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'ghost_merge_authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_handoff_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'ghost_merge_handoff_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT handoff.ghost_user_id
    INTO source_user_id
    FROM internal.ghost_profile_merge_handoffs AS handoff
    WHERE handoff.id = p_handoff_id;

    IF source_user_id IS NULL THEN
        RAISE EXCEPTION 'ghost_merge_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('ghost-profile-merge:' || source_user_id::TEXT, 0)
    );

    SELECT handoff.*
    INTO STRICT handoff_record
    FROM internal.ghost_profile_merge_handoffs AS handoff
    WHERE handoff.id = p_handoff_id
    FOR UPDATE;

    IF handoff_record.secret_hash <> p_secret_hash THEN
        RAISE EXCEPTION 'ghost_merge_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF handoff_record.status = 'merged' THEN
        IF handoff_record.target_user_id <> caller_id THEN
            RAISE EXCEPTION 'ghost_merge_handoff_invalid'
                USING ERRCODE = 'P0002';
        END IF;

        RETURN QUERY SELECT
            handoff_record.id,
            handoff_record.ghost_user_id,
            handoff_record.target_user_id,
            TRUE,
            handoff_record.merged_at,
            handoff_record.auth_deleted_at;
        RETURN;
    END IF;

    IF handoff_record.status = 'expired'
       OR (
           handoff_record.status = 'prepared'
           AND handoff_record.expires_at <= NOW()
       ) THEN
        -- Raising is intentional so the caller receives a stable 410. Status
        -- maintenance is persisted by the cleanup worker; an update here would
        -- be rolled back with the exception.
        RAISE EXCEPTION 'ghost_merge_handoff_expired'
            USING ERRCODE = 'P0001';
    END IF;

    IF handoff_record.status <> 'prepared' THEN
        RAISE EXCEPTION 'ghost_merge_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF caller_id = handoff_record.ghost_user_id THEN
        RAISE EXCEPTION 'ghost_merge_destination_must_differ'
            USING ERRCODE = '42501';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id IN (handoff_record.ghost_user_id, caller_id)
    ORDER BY auth_user.id
    FOR UPDATE;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = handoff_record.ghost_user_id
          AND auth_user.is_anonymous = TRUE
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = caller_id
          AND auth_user.is_anonymous = FALSE
    ) THEN
        RAISE EXCEPTION 'ghost_merge_destination_must_be_permanent'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.identities AS identity
        WHERE identity.user_id = caller_id
          AND identity.provider = handoff_record.expected_provider
          AND (
              identity.provider_id =
                  handoff_record.expected_provider_subject
              OR identity.identity_data ->> 'sub' =
                  handoff_record.expected_provider_subject
          )
    ) THEN
        RAISE EXCEPTION 'ghost_merge_destination_identity_mismatch'
            USING ERRCODE = '42501';
    END IF;

    PERFORM internal.perform_ghost_profile_merge(
        handoff_record.ghost_user_id,
        caller_id
    );

    UPDATE internal.ghost_profile_merge_handoffs AS handoff
    SET target_user_id = caller_id,
        status = 'merged',
        merged_at = NOW(),
        updated_at = NOW()
    WHERE handoff.id = handoff_record.id
    RETURNING handoff.*
    INTO handoff_record;

    RETURN QUERY SELECT
        handoff_record.id,
        handoff_record.ghost_user_id,
        handoff_record.target_user_id,
        FALSE,
        handoff_record.merged_at,
        handoff_record.auth_deleted_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_ghost_profile_merge_auth_cleanup(
    p_handoff_id UUID,
    p_succeeded BOOLEAN,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE internal.ghost_profile_merge_handoffs AS handoff
    SET cleanup_attempt_count = handoff.cleanup_attempt_count + 1,
        auth_deleted_at = CASE
            WHEN p_succeeded THEN COALESCE(handoff.auth_deleted_at, NOW())
            ELSE handoff.auth_deleted_at
        END,
        last_cleanup_error_code = CASE
            WHEN p_succeeded THEN NULL
            ELSE LEFT(NULLIF(BTRIM(p_error_code), ''), 120)
        END,
        cleanup_claim_token = CASE
            WHEN p_succeeded THEN NULL
            ELSE handoff.cleanup_claim_token
        END,
        cleanup_claimed_at = CASE
            WHEN p_succeeded THEN NULL
            ELSE handoff.cleanup_claimed_at
        END,
        updated_at = NOW()
    WHERE handoff.id = p_handoff_id
      AND handoff.status = 'merged';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ghost_merge_receipt_not_found'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_ghost_profile_merge_auth_cleanups(
    p_limit INTEGER DEFAULT 25
)
RETURNS TABLE (
    handoff_id UUID,
    ghost_user_id UUID,
    target_user_id UUID,
    claim_token UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    -- Expiration is maintenance state, not part of the consumer's exception
    -- transaction, so this update is durable.
    UPDATE internal.ghost_profile_merge_handoffs AS handoff
    SET status = 'expired',
        updated_at = NOW()
    WHERE handoff.status = 'prepared'
      AND handoff.expires_at <= NOW();

    RETURN QUERY
    WITH candidates AS (
        SELECT handoff.id
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.status = 'merged'
          AND handoff.auth_deleted_at IS NULL
          AND (
              handoff.cleanup_claimed_at IS NULL
              OR handoff.cleanup_claimed_at <= NOW() - INTERVAL '10 minutes'
          )
          AND (
              handoff.cleanup_attempt_count = 0
              OR handoff.updated_at <= NOW() - CASE
                  WHEN handoff.cleanup_attempt_count = 1
                      THEN INTERVAL '1 minute'
                  WHEN handoff.cleanup_attempt_count = 2
                      THEN INTERVAL '2 minutes'
                  WHEN handoff.cleanup_attempt_count = 3
                      THEN INTERVAL '4 minutes'
                  ELSE INTERVAL '15 minutes'
              END
          )
        ORDER BY handoff.merged_at, handoff.id
        FOR UPDATE SKIP LOCKED
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
    ),
    claimed AS (
        UPDATE internal.ghost_profile_merge_handoffs AS handoff
        SET cleanup_claim_token = gen_random_uuid(),
            cleanup_claimed_at = NOW(),
            cleanup_attempt_count = handoff.cleanup_attempt_count + 1,
            updated_at = NOW()
        FROM candidates
        WHERE handoff.id = candidates.id
        RETURNING
            handoff.id,
            handoff.ghost_user_id,
            handoff.target_user_id,
            handoff.cleanup_claim_token
    )
    SELECT
        claimed.id,
        claimed.ghost_user_id,
        claimed.target_user_id,
        claimed.cleanup_claim_token
    FROM claimed;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_ghost_profile_merge_auth_cleanup(
    p_handoff_id UUID,
    p_claim_token UUID,
    p_succeeded BOOLEAN,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE internal.ghost_profile_merge_handoffs AS handoff
    SET auth_deleted_at = CASE
            WHEN p_succeeded THEN COALESCE(handoff.auth_deleted_at, NOW())
            ELSE handoff.auth_deleted_at
        END,
        last_cleanup_error_code = CASE
            WHEN p_succeeded THEN NULL
            ELSE LEFT(NULLIF(BTRIM(p_error_code), ''), 120)
        END,
        cleanup_claim_token = NULL,
        cleanup_claimed_at = NULL,
        updated_at = NOW()
    WHERE handoff.id = p_handoff_id
      AND handoff.status = 'merged'
      AND handoff.cleanup_claim_token = p_claim_token;

    IF NOT FOUND AND NOT (
        p_succeeded
        AND EXISTS (
            SELECT 1
            FROM internal.ghost_profile_merge_handoffs AS handoff
            WHERE handoff.id = p_handoff_id
              AND handoff.status = 'merged'
              AND handoff.auth_deleted_at IS NOT NULL
        )
    ) THEN
        RAISE EXCEPTION 'ghost_merge_cleanup_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_protected_ghost_profile_merge_sources()
RETURNS TABLE (ghost_user_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT DISTINCT handoff.ghost_user_id
    FROM internal.ghost_profile_merge_handoffs AS handoff
    WHERE handoff.status = 'prepared'
       OR (
           handoff.status = 'merged'
           AND handoff.auth_deleted_at IS NULL
       );
$$;

CREATE OR REPLACE FUNCTION public.reserve_ghost_user_bulk_cleanup(
    p_ghost_user_id UUID,
    p_lease_minutes INTEGER DEFAULT 15
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    reserved_token UUID;
    lease_minutes INTEGER :=
        LEAST(GREATEST(COALESCE(p_lease_minutes, 15), 5), 60);
BEGIN
    IF p_ghost_user_id IS NULL THEN
        RAISE EXCEPTION 'ghost_cleanup_invalid_source'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            'ghost-profile-merge:' || p_ghost_user_id::TEXT,
            0
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.ghost_user_id = p_ghost_user_id
          AND (
              handoff.status = 'prepared'
              OR (
                  handoff.status = 'merged'
                  AND handoff.auth_deleted_at IS NULL
              )
          )
    ) THEN
        RAISE EXCEPTION 'ghost_cleanup_source_protected_by_merge'
            USING ERRCODE = '55000';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = p_ghost_user_id
          AND auth_user.is_anonymous = TRUE
    ) THEN
        RAISE EXCEPTION 'ghost_cleanup_source_not_anonymous'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM internal.ghost_user_cleanup_reservations AS reservation
    WHERE reservation.ghost_user_id = p_ghost_user_id
      AND reservation.completed_at IS NULL
      AND reservation.expires_at <= NOW();

    INSERT INTO internal.ghost_user_cleanup_reservations AS reservation (
        ghost_user_id,
        expires_at
    )
    VALUES (
        p_ghost_user_id,
        NOW() + MAKE_INTERVAL(mins => lease_minutes)
    )
    RETURNING reservation.reservation_token
    INTO reserved_token;

    RETURN reserved_token;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'ghost_cleanup_source_already_reserved'
            USING ERRCODE = '55P03';
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_ghost_user_bulk_cleanup(
    p_ghost_user_id UUID,
    p_reservation_token UUID,
    p_succeeded BOOLEAN,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE internal.ghost_user_cleanup_reservations AS reservation
    SET completed_at = CASE
            WHEN p_succeeded THEN COALESCE(reservation.completed_at, NOW())
            ELSE reservation.completed_at
        END,
        expires_at = CASE
            WHEN p_succeeded THEN reservation.expires_at
            ELSE GREATEST(
                NOW(),
                reservation.created_at + INTERVAL '1 microsecond'
            )
        END,
        last_error_code = CASE
            WHEN p_succeeded THEN NULL
            ELSE LEFT(NULLIF(BTRIM(p_error_code), ''), 120)
        END,
        updated_at = NOW()
    WHERE reservation.ghost_user_id = p_ghost_user_id
      AND reservation.reservation_token = p_reservation_token
      AND reservation.completed_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ghost_cleanup_reservation_not_found'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION internal.repoint_merge_review_source(TEXT, UUID, UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.merge_ghost_social_conflicts(UUID, UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.merge_ghost_chat_conversations(UUID, UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.merge_ghost_field_trip_state(UUID, UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID, UUID)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.perform_ghost_profile_merge(UUID, UUID)
    FROM PUBLIC;

REVOKE ALL ON FUNCTION public.issue_ghost_profile_merge_handoff(
    TEXT,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_ghost_profile_merge_handoff(
    TEXT,
    TEXT,
    TEXT
) TO authenticated;

REVOKE ALL ON FUNCTION public.consume_ghost_profile_merge_handoff(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_ghost_profile_merge_handoff(UUID, TEXT)
    TO authenticated;

REVOKE ALL ON FUNCTION public.record_ghost_profile_merge_auth_cleanup(
    UUID,
    BOOLEAN,
    TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_ghost_profile_merge_auth_cleanup(
    UUID,
    BOOLEAN,
    TEXT
) TO service_role;

REVOKE ALL ON FUNCTION public.claim_ghost_profile_merge_auth_cleanups(INTEGER)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ghost_profile_merge_auth_cleanups(INTEGER)
    TO service_role;

REVOKE ALL ON FUNCTION public.finish_ghost_profile_merge_auth_cleanup(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_ghost_profile_merge_auth_cleanup(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) TO service_role;

REVOKE ALL ON FUNCTION public.list_protected_ghost_profile_merge_sources()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_protected_ghost_profile_merge_sources()
    TO service_role;

REVOKE ALL ON FUNCTION public.reserve_ghost_user_bulk_cleanup(UUID, INTEGER)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ghost_user_bulk_cleanup(UUID, INTEGER)
    TO service_role;

REVOKE ALL ON FUNCTION public.finish_ghost_user_bulk_cleanup(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_ghost_user_bulk_cleanup(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) TO service_role;

-- The old helper accepted arbitrary source and target UUIDs and was executable
-- by PUBLIC by default. It is retained only for deployment compatibility and
-- made unreachable; the atomic merge function now handles follows internally.
REVOKE ALL ON FUNCTION public.reparent_user_follows(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reparent_user_follows(UUID, UUID)
    TO service_role;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'reconcile_ghost_profile_merges_every_five_minutes'
    ) THEN
        PERFORM cron.unschedule(
            'reconcile_ghost_profile_merges_every_five_minutes'
        );
    END IF;
END;
$$;

SELECT cron.schedule(
    'reconcile_ghost_profile_merges_every_five_minutes',
    '*/5 * * * *',
    $schedule$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := CURRENT_SETTING(
                'app.settings.supabase_url',
                TRUE
            );
        END IF;

        IF service_role_key IS NULL THEN
            service_role_key := CURRENT_SETTING(
                'app.settings.service_role_key',
                TRUE
            );
        END IF;

        IF project_url IS NOT NULL AND service_role_key IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url ||
                    '/functions/v1/reconcile-ghost-profile-merges',
                headers := JSONB_BUILD_OBJECT(
                    'Content-Type',
                    'application/json',
                    'Authorization',
                    'Bearer ' || service_role_key
                ),
                body := JSONB_BUILD_OBJECT('limit', 25)
            );
        END IF;
    END;
    $job$;
    $schedule$
);

NOTIFY pgrst, 'reload schema';

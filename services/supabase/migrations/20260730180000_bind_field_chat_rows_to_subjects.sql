-- Field Chat Edge handlers validate subject identity before writing, but the
-- original tables kept conversation, subject, and user references as
-- independent foreign keys. A historical direct-client write or a future
-- service regression could therefore create a cross-bound private row that
-- makes the strict iOS thread decoder reject the entire conversation. Remove
-- only those untrusted mismatches, bind every retained row structurally, and
-- close the remaining direct feedback-write surfaces.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- A private Insight conversation is meaningful only for the owner of its
-- exact scan. These rows predate the Edge-only API boundary, so discard any
-- impossible cross-owner conversation before validating the new constraints.
DELETE FROM public.insight_chat_conversations AS conversation
WHERE NOT EXISTS (
    SELECT 1
    FROM public.scans AS scan
    WHERE scan.id = conversation.scan_id
      AND scan.user_id = conversation.user_id
);

-- Message text cannot be reassigned safely across subjects. Delete only rows
-- whose three identities disagree with their parent conversation. Existing
-- message-feedback rows follow their message through the original cascade.
DELETE FROM public.insight_chat_messages AS message
WHERE NOT EXISTS (
    SELECT 1
    FROM public.insight_chat_conversations AS conversation
    WHERE conversation.id = message.conversation_id
      AND conversation.scan_id = message.scan_id
      AND conversation.user_id = message.user_id
);

DELETE FROM public.explore_post_chat_messages AS message
WHERE NOT EXISTS (
    SELECT 1
    FROM public.explore_post_chat_conversations AS conversation
    WHERE conversation.id = message.conversation_id
      AND conversation.post_id = message.post_id
      AND conversation.user_id = message.user_id
);

-- Feedback is retained only when all of its copied identity columns match the
-- exact assistant/user message it rates. A mismatched rating has no trustworthy
-- target and must not be silently moved onto another private message.
DELETE FROM public.insight_chat_message_feedback AS feedback
WHERE NOT EXISTS (
    SELECT 1
    FROM public.insight_chat_messages AS message
    WHERE message.id = feedback.message_id
      AND message.conversation_id = feedback.conversation_id
      AND message.scan_id = feedback.scan_id
      AND message.user_id = feedback.user_id
      AND message.role = 'assistant'
);

DELETE FROM public.explore_post_chat_message_feedback AS feedback
WHERE NOT EXISTS (
    SELECT 1
    FROM public.explore_post_chat_messages AS message
    WHERE message.id = feedback.message_id
      AND message.conversation_id = feedback.conversation_id
      AND message.post_id = feedback.post_id
      AND message.user_id = feedback.user_id
      AND message.role = 'assistant'
);

-- Feature feedback remains useful without a conversation, but its scan target
-- must still belong to the copied owner. A cross-owner row has no trustworthy
-- private subject and cannot be repaired safely.
DELETE FROM public.insight_chat_feature_feedback AS feedback
WHERE NOT EXISTS (
    SELECT 1
    FROM public.scans AS scan
    WHERE scan.id = feedback.scan_id
      AND scan.user_id = feedback.user_id
);

-- Preserve valid scan feedback while clearing only an optional conversation
-- identity that cannot be proven exact.
UPDATE public.insight_chat_feature_feedback AS feedback
SET conversation_id = NULL
WHERE feedback.conversation_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM public.insight_chat_conversations AS conversation
      WHERE conversation.id = feedback.conversation_id
        AND conversation.scan_id = feedback.scan_id
        AND conversation.user_id = feedback.user_id
  );

-- PostgreSQL requires an explicit unique key covering every referenced column
-- of a composite foreign key. The leading UUID is already globally unique;
-- these keys add no new logical uniqueness rule.
ALTER TABLE public.scans
ADD CONSTRAINT scans_bound_owner_identity_key
UNIQUE (id, user_id);

ALTER TABLE public.insight_chat_conversations
ADD CONSTRAINT insight_chat_conversations_bound_identity_key
UNIQUE (id, scan_id, user_id);

ALTER TABLE public.explore_post_chat_conversations
ADD CONSTRAINT explore_post_chat_conversations_bound_identity_key
UNIQUE (id, post_id, user_id);

ALTER TABLE public.insight_chat_messages
ADD CONSTRAINT insight_chat_messages_bound_identity_key
UNIQUE (id, conversation_id, scan_id, user_id);

ALTER TABLE public.explore_post_chat_messages
ADD CONSTRAINT explore_post_chat_messages_bound_identity_key
UNIQUE (id, conversation_id, post_id, user_id);

-- Deferred binding preserves the existing all-in-one anonymous-account merge:
-- that transaction reparents conversations and children in deterministic
-- passes, and every row must agree again before it commits.
ALTER TABLE public.insight_chat_conversations
ADD CONSTRAINT insight_chat_conversations_bound_scan_owner_fk
FOREIGN KEY (scan_id, user_id)
REFERENCES public.scans (id, user_id)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.insight_chat_feature_feedback
ADD CONSTRAINT insight_chat_feature_feedback_bound_scan_owner_fk
FOREIGN KEY (scan_id, user_id)
REFERENCES public.scans (id, user_id)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.insight_chat_messages
ADD CONSTRAINT insight_chat_messages_bound_conversation_fk
FOREIGN KEY (conversation_id, scan_id, user_id)
REFERENCES public.insight_chat_conversations (id, scan_id, user_id)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.explore_post_chat_messages
ADD CONSTRAINT explore_post_chat_messages_bound_conversation_fk
FOREIGN KEY (conversation_id, post_id, user_id)
REFERENCES public.explore_post_chat_conversations (id, post_id, user_id)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.insight_chat_message_feedback
ADD CONSTRAINT insight_chat_message_feedback_bound_message_fk
FOREIGN KEY (message_id, conversation_id, scan_id, user_id)
REFERENCES public.insight_chat_messages (
    id,
    conversation_id,
    scan_id,
    user_id
)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.explore_post_chat_message_feedback
ADD CONSTRAINT explore_post_chat_message_feedback_bound_message_fk
FOREIGN KEY (message_id, conversation_id, post_id, user_id)
REFERENCES public.explore_post_chat_messages (
    id,
    conversation_id,
    post_id,
    user_id
)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.insight_chat_feature_feedback
ADD CONSTRAINT insight_chat_feature_feedback_bound_conversation_fk
FOREIGN KEY (conversation_id, scan_id, user_id)
REFERENCES public.insight_chat_conversations (id, scan_id, user_id)
DEFERRABLE INITIALLY DEFERRED;

-- Insight feedback tables were created before Field Chat became an Edge-only
-- API and retained authenticated Data API writes. Match the conversation and
-- message boundary: only the backend may mutate private feedback.
REVOKE ALL PRIVILEGES
    ON TABLE public.insight_chat_message_feedback,
             public.insight_chat_feature_feedback,
             public.explore_post_chat_message_feedback
    FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE
    ON TABLE public.insight_chat_message_feedback,
             public.explore_post_chat_message_feedback
    TO service_role;

GRANT SELECT, INSERT
    ON TABLE public.insight_chat_feature_feedback
    TO service_role;

-- Keep RLS exact as defense in depth if a future privilege migration exposes
-- these tables again.
DROP POLICY IF EXISTS "Users can insert their own insight chat conversations"
    ON public.insight_chat_conversations;
CREATE POLICY "Users can insert their own insight chat conversations"
    ON public.insight_chat_conversations
    FOR INSERT
    TO authenticated
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.scans AS scan
            WHERE scan.id = insight_chat_conversations.scan_id
              AND scan.user_id = (SELECT auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can insert their own insight chat messages"
    ON public.insight_chat_messages;
CREATE POLICY "Users can insert their own insight chat messages"
    ON public.insight_chat_messages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.insight_chat_conversations AS conversation
            WHERE conversation.id = insight_chat_messages.conversation_id
              AND conversation.scan_id = insight_chat_messages.scan_id
              AND conversation.user_id = (SELECT auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can read their own insight chat feedback"
    ON public.insight_chat_message_feedback;
DROP POLICY IF EXISTS "Users can insert their own insight chat feedback"
    ON public.insight_chat_message_feedback;
DROP POLICY IF EXISTS "Users can update their own insight chat feedback"
    ON public.insight_chat_message_feedback;
DROP POLICY IF EXISTS "Users can delete their own insight chat feedback"
    ON public.insight_chat_message_feedback;
CREATE POLICY "Users access exact insight chat feedback"
    ON public.insight_chat_message_feedback
    FOR ALL
    TO authenticated
    USING (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.insight_chat_messages AS message
            WHERE message.id = insight_chat_message_feedback.message_id
              AND message.conversation_id =
                    insight_chat_message_feedback.conversation_id
              AND message.scan_id = insight_chat_message_feedback.scan_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    )
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.insight_chat_messages AS message
            WHERE message.id = insight_chat_message_feedback.message_id
              AND message.conversation_id =
                    insight_chat_message_feedback.conversation_id
              AND message.scan_id = insight_chat_message_feedback.scan_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    );

DROP POLICY IF EXISTS "Users can read their own insight chat feature feedback"
    ON public.insight_chat_feature_feedback;
DROP POLICY IF EXISTS "Users can insert their own insight chat feature feedback"
    ON public.insight_chat_feature_feedback;
CREATE POLICY "Users access exact insight chat feature feedback"
    ON public.insight_chat_feature_feedback
    FOR ALL
    TO authenticated
    USING (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.scans AS scan
            WHERE scan.id = insight_chat_feature_feedback.scan_id
              AND scan.user_id = (SELECT auth.uid())
        )
        AND (
            conversation_id IS NULL
            OR EXISTS (
                SELECT 1
                FROM public.insight_chat_conversations AS conversation
                WHERE conversation.id =
                      insight_chat_feature_feedback.conversation_id
                  AND conversation.scan_id =
                      insight_chat_feature_feedback.scan_id
                  AND conversation.user_id = (SELECT auth.uid())
            )
        )
    )
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.scans AS scan
            WHERE scan.id = insight_chat_feature_feedback.scan_id
              AND scan.user_id = (SELECT auth.uid())
        )
        AND (
            conversation_id IS NULL
            OR EXISTS (
                SELECT 1
                FROM public.insight_chat_conversations AS conversation
                WHERE conversation.id =
                      insight_chat_feature_feedback.conversation_id
                  AND conversation.scan_id =
                      insight_chat_feature_feedback.scan_id
                  AND conversation.user_id = (SELECT auth.uid())
            )
        )
    );

DROP POLICY IF EXISTS "Viewers manage their Explore chat feedback"
    ON public.explore_post_chat_message_feedback;
CREATE POLICY "Viewers manage their Explore chat feedback"
    ON public.explore_post_chat_message_feedback
    FOR ALL
    TO authenticated
    USING (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.explore_post_chat_messages AS message
            WHERE message.id = explore_post_chat_message_feedback.message_id
              AND message.conversation_id =
                    explore_post_chat_message_feedback.conversation_id
              AND message.post_id =
                    explore_post_chat_message_feedback.post_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    )
    WITH CHECK (
        (SELECT auth.uid()) = user_id
        AND EXISTS (
            SELECT 1
            FROM public.explore_post_chat_messages AS message
            WHERE message.id = explore_post_chat_message_feedback.message_id
              AND message.conversation_id =
                    explore_post_chat_message_feedback.conversation_id
              AND message.post_id =
                    explore_post_chat_message_feedback.post_id
              AND message.user_id = (SELECT auth.uid())
              AND message.role = 'assistant'
        )
    );

COMMENT ON CONSTRAINT insight_chat_messages_bound_conversation_fk
    ON public.insight_chat_messages IS
    'Every private Insight message is bound to its exact conversation, scan, and user.';

COMMENT ON CONSTRAINT insight_chat_conversations_bound_scan_owner_fk
    ON public.insight_chat_conversations IS
    'Every private Insight conversation is bound to its exact scan owner.';

COMMENT ON CONSTRAINT explore_post_chat_messages_bound_conversation_fk
    ON public.explore_post_chat_messages IS
    'Every private Explore message is bound to its exact conversation, post, and viewer.';

COMMENT ON CONSTRAINT insight_chat_message_feedback_bound_message_fk
    ON public.insight_chat_message_feedback IS
    'Every private Insight rating copies the exact rated message identity.';

COMMENT ON CONSTRAINT explore_post_chat_message_feedback_bound_message_fk
    ON public.explore_post_chat_message_feedback IS
    'Every private Explore rating copies the exact rated message identity.';

COMMENT ON CONSTRAINT insight_chat_feature_feedback_bound_conversation_fk
    ON public.insight_chat_feature_feedback IS
    'Optional conversation identity must match the exact scan and owner.';

COMMENT ON CONSTRAINT insight_chat_feature_feedback_bound_scan_owner_fk
    ON public.insight_chat_feature_feedback IS
    'Every private Insight feature rating is bound to its exact scan owner.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

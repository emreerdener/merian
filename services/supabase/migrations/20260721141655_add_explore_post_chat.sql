-- Private per-viewer Field chat conversations grounded only in the public
-- projection of another user's active Explore post.

CREATE TABLE public.explore_post_chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  species_dictionary_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

CREATE TABLE public.explore_post_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.explore_post_chat_conversations(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  message_text TEXT NOT NULL CHECK (CHAR_LENGTH(BTRIM(message_text)) > 0),
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
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.explore_post_chat_message_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.explore_post_chat_messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES public.explore_post_chat_conversations(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating TEXT NOT NULL CHECK (rating IN ('helpful', 'not_helpful', 'wrong', 'unsafe', 'other')),
  note TEXT CHECK (note IS NULL OR CHAR_LENGTH(note) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (message_id, user_id)
);

CREATE INDEX explore_post_chat_conversations_user_updated_idx
  ON public.explore_post_chat_conversations(user_id, updated_at DESC);
CREATE INDEX explore_post_chat_messages_conversation_created_idx
  ON public.explore_post_chat_messages(conversation_id, created_at, id);
CREATE INDEX explore_post_chat_messages_user_created_idx
  ON public.explore_post_chat_messages(user_id, created_at DESC);
CREATE UNIQUE INDEX explore_post_chat_messages_client_id_idx
  ON public.explore_post_chat_messages(conversation_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

ALTER TABLE public.explore_post_chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_post_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_post_chat_message_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Viewers manage their Explore chat conversations"
  ON public.explore_post_chat_conversations
  FOR ALL TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Viewers manage their Explore chat messages"
  ON public.explore_post_chat_messages
  FOR ALL TO authenticated
  USING (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1 FROM public.explore_post_chat_conversations conversation
      WHERE conversation.id = explore_post_chat_messages.conversation_id
        AND conversation.post_id = explore_post_chat_messages.post_id
        AND conversation.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1 FROM public.explore_post_chat_conversations conversation
      WHERE conversation.id = explore_post_chat_messages.conversation_id
        AND conversation.post_id = explore_post_chat_messages.post_id
        AND conversation.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "Viewers manage their Explore chat feedback"
  ON public.explore_post_chat_message_feedback
  FOR ALL TO authenticated
  USING (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1 FROM public.explore_post_chat_messages message
      WHERE message.id = explore_post_chat_message_feedback.message_id
        AND message.conversation_id = explore_post_chat_message_feedback.conversation_id
        AND message.post_id = explore_post_chat_message_feedback.post_id
        AND message.user_id = (SELECT auth.uid())
    )
  )
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1 FROM public.explore_post_chat_messages message
      WHERE message.id = explore_post_chat_message_feedback.message_id
        AND message.conversation_id = explore_post_chat_message_feedback.conversation_id
        AND message.post_id = explore_post_chat_message_feedback.post_id
        AND message.user_id = (SELECT auth.uid())
    )
  );

-- These tables are an Edge Function implementation detail, not a client Data
-- API. RLS remains enabled as defense in depth if privileges change later.
REVOKE ALL ON public.explore_post_chat_conversations FROM anon, authenticated;
REVOKE ALL ON public.explore_post_chat_messages FROM anon, authenticated;
REVOKE ALL ON public.explore_post_chat_message_feedback FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_explore_post_chat_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER explore_post_chat_conversations_set_updated_at
BEFORE UPDATE ON public.explore_post_chat_conversations
FOR EACH ROW EXECUTE FUNCTION public.trg_explore_post_chat_set_updated_at();

CREATE TRIGGER explore_post_chat_feedback_set_updated_at
BEFORE UPDATE ON public.explore_post_chat_message_feedback
FOR EACH ROW EXECUTE FUNCTION public.trg_explore_post_chat_set_updated_at();

CREATE OR REPLACE FUNCTION public.trg_remove_unshared_explore_post_chats()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.unshared_at IS NULL AND NEW.unshared_at IS NOT NULL THEN
    DELETE FROM public.explore_post_chat_conversations WHERE post_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER remove_unshared_explore_post_chats
AFTER UPDATE OF unshared_at ON public.explore_posts
FOR EACH ROW EXECUTE FUNCTION public.trg_remove_unshared_explore_post_chats();

COMMENT ON TABLE public.explore_post_chat_conversations IS
  'Private Pro Field chat conversations grounded in active public Explore posts.';
COMMENT ON TABLE public.explore_post_chat_messages IS
  'Private per-viewer Explore Field chat messages; never public post comments.';

NOTIFY pgrst, 'reload schema';

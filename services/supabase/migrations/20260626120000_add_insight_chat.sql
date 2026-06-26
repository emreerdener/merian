-- Private Pro follow-up conversations attached to saved scans.
-- These rows are owner-only personal data and are intentionally not referenced
-- by Explore projections, species dictionary surfaces, or Darwin Core exports.

CREATE TABLE IF NOT EXISTS public.insight_chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (scan_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.insight_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.insight_chat_conversations(id) ON DELETE CASCADE,
  scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  message_text TEXT NOT NULL CHECK (char_length(message_text) BETWEEN 1 AND 4000),
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

CREATE INDEX IF NOT EXISTS idx_insight_chat_conversations_user_updated
  ON public.insight_chat_conversations(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_insight_chat_messages_conversation_created
  ON public.insight_chat_messages(conversation_id, created_at ASC, id ASC);

CREATE INDEX IF NOT EXISTS idx_insight_chat_messages_user_created
  ON public.insight_chat_messages(user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_insight_chat_messages_client_message
  ON public.insight_chat_messages(conversation_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.trg_insight_chat_conversations_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_insight_chat_conversations_set_updated_at
  ON public.insight_chat_conversations;

CREATE TRIGGER trg_insight_chat_conversations_set_updated_at
BEFORE UPDATE ON public.insight_chat_conversations
FOR EACH ROW
EXECUTE FUNCTION public.trg_insight_chat_conversations_set_updated_at();

ALTER TABLE public.insight_chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insight_chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own insight chat conversations"
  ON public.insight_chat_conversations;
CREATE POLICY "Users can read their own insight chat conversations"
  ON public.insight_chat_conversations
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own insight chat conversations"
  ON public.insight_chat_conversations;
CREATE POLICY "Users can insert their own insight chat conversations"
  ON public.insight_chat_conversations
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own insight chat conversations"
  ON public.insight_chat_conversations;
CREATE POLICY "Users can delete their own insight chat conversations"
  ON public.insight_chat_conversations
  FOR DELETE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read their own insight chat messages"
  ON public.insight_chat_messages;
CREATE POLICY "Users can read their own insight chat messages"
  ON public.insight_chat_messages
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own insight chat messages"
  ON public.insight_chat_messages;
CREATE POLICY "Users can insert their own insight chat messages"
  ON public.insight_chat_messages
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own insight chat messages"
  ON public.insight_chat_messages;
CREATE POLICY "Users can delete their own insight chat messages"
  ON public.insight_chat_messages
  FOR DELETE
  USING (auth.uid() = user_id);

COMMENT ON TABLE public.insight_chat_conversations IS
  'Private Pro AI follow-up chat conversations linked to owner scans.';

COMMENT ON TABLE public.insight_chat_messages IS
  'Private user and assistant messages for scan-linked Insight follow-up chat.';

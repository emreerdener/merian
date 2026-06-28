-- Owner-only feedback on private Insight chat assistant messages.
-- Feedback is private scan data and is not projected into Explore, species
-- dictionary contribution flows, or Darwin Core exports.

CREATE TABLE IF NOT EXISTS public.insight_chat_message_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.insight_chat_messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES public.insight_chat_conversations(id) ON DELETE CASCADE,
  scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating TEXT NOT NULL CHECK (rating IN ('helpful', 'not_helpful', 'wrong', 'unsafe', 'other')),
  note TEXT CHECK (note IS NULL OR char_length(note) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_insight_chat_feedback_user_created
  ON public.insight_chat_message_feedback(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_insight_chat_feedback_scan_created
  ON public.insight_chat_message_feedback(scan_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.trg_insight_chat_feedback_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_insight_chat_feedback_set_updated_at
  ON public.insight_chat_message_feedback;

CREATE TRIGGER trg_insight_chat_feedback_set_updated_at
BEFORE UPDATE ON public.insight_chat_message_feedback
FOR EACH ROW
EXECUTE FUNCTION public.trg_insight_chat_feedback_set_updated_at();

ALTER TABLE public.insight_chat_message_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own insight chat feedback"
  ON public.insight_chat_message_feedback;
CREATE POLICY "Users can read their own insight chat feedback"
  ON public.insight_chat_message_feedback
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own insight chat feedback"
  ON public.insight_chat_message_feedback;
CREATE POLICY "Users can insert their own insight chat feedback"
  ON public.insight_chat_message_feedback
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own insight chat feedback"
  ON public.insight_chat_message_feedback;
CREATE POLICY "Users can update their own insight chat feedback"
  ON public.insight_chat_message_feedback
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own insight chat feedback"
  ON public.insight_chat_message_feedback;
CREATE POLICY "Users can delete their own insight chat feedback"
  ON public.insight_chat_message_feedback
  FOR DELETE
  USING (auth.uid() = user_id);

COMMENT ON TABLE public.insight_chat_message_feedback IS
  'Private owner-only feedback on Insight chat assistant messages.';

-- Owner-only feedback on the Field chat feature itself.
-- This is private scan data and is not projected into Explore, species
-- dictionary contribution flows, or Darwin Core exports.

CREATE TABLE IF NOT EXISTS public.insight_chat_feature_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES public.insight_chat_conversations(id) ON DELETE SET NULL,
  scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sentiment TEXT CHECK (sentiment IS NULL OR sentiment IN ('positive', 'negative')),
  note TEXT CHECK (note IS NULL OR char_length(note) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT insight_chat_feature_feedback_has_content
    CHECK (sentiment IS NOT NULL OR note IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_insight_chat_feature_feedback_user_created
  ON public.insight_chat_feature_feedback(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_insight_chat_feature_feedback_scan_created
  ON public.insight_chat_feature_feedback(scan_id, created_at DESC);

ALTER TABLE public.insight_chat_feature_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own insight chat feature feedback"
  ON public.insight_chat_feature_feedback;
CREATE POLICY "Users can read their own insight chat feature feedback"
  ON public.insight_chat_feature_feedback
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own insight chat feature feedback"
  ON public.insight_chat_feature_feedback;
CREATE POLICY "Users can insert their own insight chat feature feedback"
  ON public.insight_chat_feature_feedback
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE public.insight_chat_feature_feedback IS
  'Private owner-only feedback on the Field chat feature experience.';

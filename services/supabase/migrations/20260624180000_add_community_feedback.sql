CREATE TABLE IF NOT EXISTS public.community_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  feedback TEXT NOT NULL,
  app_version TEXT,
  build_number TEXT,
  platform TEXT NOT NULL DEFAULT 'ios',
  os_version TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT community_feedback_length CHECK (char_length(feedback) <= 4000)
);

CREATE INDEX IF NOT EXISTS community_feedback_user_created_at_idx
  ON public.community_feedback (user_id, created_at DESC);

ALTER TABLE public.community_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own community feedback"
  ON public.community_feedback
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read their own community feedback"
  ON public.community_feedback
  FOR SELECT
  USING (auth.uid() = user_id);

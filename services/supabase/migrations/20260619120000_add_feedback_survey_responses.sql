CREATE TABLE IF NOT EXISTS public.feedback_survey_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_campaign_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  app_version TEXT,
  build_number TEXT,
  platform TEXT NOT NULL DEFAULT 'ios',
  device_model TEXT,
  os_version TEXT,
  locale TEXT,
  timezone TEXT,
  satisfaction_rating INTEGER NOT NULL CHECK (satisfaction_rating BETWEEN 1 AND 5),
  recommendation_rating INTEGER NOT NULL CHECK (recommendation_rating BETWEEN 0 AND 10),
  used_features TEXT[] NOT NULL DEFAULT '{}',
  most_useful_feature TEXT NOT NULL,
  bug_status TEXT NOT NULL CHECK (bug_status IN ('no', 'workaround', 'blocked')),
  confusing_or_disappointing TEXT NOT NULL DEFAULT '',
  wished_next TEXT NOT NULL DEFAULT '',
  bug_details TEXT NOT NULL DEFAULT '',
  may_follow_up BOOLEAN NOT NULL DEFAULT false,
  contact TEXT NOT NULL DEFAULT '',
  raw_response JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT feedback_survey_campaign_not_blank CHECK (char_length(btrim(survey_campaign_id)) > 0),
  CONSTRAINT feedback_survey_confusing_length CHECK (char_length(confusing_or_disappointing) <= 4000),
  CONSTRAINT feedback_survey_wished_next_length CHECK (char_length(wished_next) <= 4000),
  CONSTRAINT feedback_survey_bug_details_length CHECK (char_length(bug_details) <= 4000),
  CONSTRAINT feedback_survey_contact_length CHECK (char_length(contact) <= 320)
);

CREATE INDEX IF NOT EXISTS feedback_survey_responses_campaign_created_at_idx
  ON public.feedback_survey_responses (survey_campaign_id, created_at DESC);

CREATE INDEX IF NOT EXISTS feedback_survey_responses_user_created_at_idx
  ON public.feedback_survey_responses (user_id, created_at DESC);

ALTER TABLE public.feedback_survey_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own feedback survey responses"
  ON public.feedback_survey_responses
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read their own feedback survey responses"
  ON public.feedback_survey_responses
  FOR SELECT
  USING (auth.uid() = user_id);

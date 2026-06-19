ALTER TABLE public.feedback_survey_responses
  ADD COLUMN IF NOT EXISTS most_useful_features TEXT[] NOT NULL DEFAULT '{}';

UPDATE public.feedback_survey_responses
SET most_useful_features = ARRAY[most_useful_feature]
WHERE most_useful_feature IS NOT NULL
  AND most_useful_feature <> ''
  AND most_useful_features = '{}';

ALTER TABLE public.feedback_survey_responses
  DROP COLUMN IF EXISTS most_useful_feature;

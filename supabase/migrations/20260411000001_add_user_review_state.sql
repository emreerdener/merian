-- Create the user_review_state enum type
CREATE TYPE public.user_review_state AS ENUM ('unreviewed', 'ai_confirmed', 'user_overridden');

-- Add user_review_state to scans, defaulting to 'unreviewed'
ALTER TABLE public.scans
  ADD COLUMN user_review_state public.user_review_state NOT NULL DEFAULT 'unreviewed';

-- Index for the override query
CREATE INDEX idx_scans_user_review_state_overridden
  ON public.scans(user_id, confirmed_species_id)
  WHERE user_review_state = 'user_overridden';

-- Covering index for GROUP BY analytics
CREATE INDEX idx_scans_user_review_state
  ON public.scans(user_review_state);

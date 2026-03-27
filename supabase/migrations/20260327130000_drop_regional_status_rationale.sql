-- regional_status_rationale was per-scan output from the identify Edge Function.
-- Removed in favour of the existing is_invasive flag which carries the same signal
-- without the extra LLM tokens.
ALTER TABLE public.scans DROP COLUMN IF EXISTS regional_status_rationale;

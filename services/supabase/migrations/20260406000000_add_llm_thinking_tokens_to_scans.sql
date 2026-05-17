-- Adds llm_thinking_tokens to scans for thinking budget observability.
-- Allows querying actual thinking token usage per tier to verify that
-- thinkingBudget caps (1024 Flash, 5000 Pro) are not constraining the model.
-- NULL for all scans captured before this migration.
ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS llm_thinking_tokens INTEGER;

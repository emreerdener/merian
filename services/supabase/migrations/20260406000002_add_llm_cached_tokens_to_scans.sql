-- Adds llm_cached_tokens to scans for implicit context caching observability.
-- Records how many prompt tokens were served from Gemini's implicit cache per scan.
-- Non-zero only for gemini-2.5-flash requests after the system instruction expanded
-- past the 1,024-token caching threshold. NULL for pre-migration scans and for all
-- gemini-2.5-pro scans (below the 4,096-token Pro caching threshold).
-- Used in cost analytics: cached tokens are billed at 75% off the standard input rate.
ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS llm_cached_tokens INTEGER;

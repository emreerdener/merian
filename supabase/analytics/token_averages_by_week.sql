-- TOKEN AVERAGES BY WEEK AND TIER
-- Use this to validate the financial model's per-scan token assumptions
-- and to detect prompt/output token drift after system instruction changes.
-- The week a new instruction deploys will show a step-change in avg_prompt_tokens.

SELECT
  DATE_TRUNC('week', created_at)                      AS week_start,
  inference_tier,
  COUNT(*)                                            AS scans,
  ROUND(AVG(llm_prompt_tokens))                       AS avg_prompt_tokens,
  ROUND(AVG(llm_cached_tokens))                       AS avg_cached_tokens,
  ROUND(AVG(llm_candidate_tokens))                    AS avg_candidate_tokens,
  ROUND(AVG(llm_thinking_tokens))                     AS avg_thinking_tokens,
  ROUND(AVG(llm_total_tokens))                        AS avg_total_tokens,
  -- Cache hit rate for this week
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE llm_cached_tokens > 0)
    / NULLIF(COUNT(*) FILTER (WHERE llm_cached_tokens IS NOT NULL), 0),
    1
  )                                                   AS cache_hit_rate_pct,
  -- Thinking as % of total output (candidate + thinking)
  ROUND(
    100.0 * AVG(llm_thinking_tokens)
    / NULLIF(AVG(COALESCE(llm_candidate_tokens, 0) + COALESCE(llm_thinking_tokens, 0)), 0),
    1
  )                                                   AS thinking_pct_of_output
FROM public.scans
WHERE llm_prompt_tokens IS NOT NULL
  AND created_at >= NOW() - INTERVAL '90 days'
GROUP BY DATE_TRUNC('week', created_at), inference_tier
ORDER BY week_start DESC, inference_tier;

-- DAILY COST TREND (last 30 days)
-- Rolling per-day API spend estimate split by tier.
-- Use this to spot cost anomalies — a spike in a single day means either
-- a traffic surge, a runaway thinking budget, or a pricing change.

WITH pricing AS (
  SELECT
    0.075   / 1000000.0 AS flash_input,
    0.01875 / 1000000.0 AS flash_cached,
    0.300   / 1000000.0 AS flash_output,
    1.25    / 1000000.0 AS pro_input,
    10.00   / 1000000.0 AS pro_output
)
SELECT
  DATE_TRUNC('day', s.timestamp)                     AS day,
  s.inference_tier,
  COUNT(*)                                            AS scans,
  SUM(CASE
    WHEN s.inference_tier = 'flash' THEN
      COALESCE(s.llm_cached_tokens, 0) * p.flash_cached
      + (COALESCE(s.llm_prompt_tokens, 0) - COALESCE(s.llm_cached_tokens, 0)) * p.flash_input
      + (COALESCE(s.llm_candidate_tokens, 0) + COALESCE(s.llm_thinking_tokens, 0)) * p.flash_output
    WHEN s.inference_tier = 'pro' THEN
      COALESCE(s.llm_prompt_tokens, 0) * p.pro_input
      + (COALESCE(s.llm_candidate_tokens, 0) + COALESCE(s.llm_thinking_tokens, 0)) * p.pro_output
    ELSE 0
  END) * 100                                          AS cost_cents
FROM public.scans s
CROSS JOIN pricing p
WHERE s.timestamp >= NOW() - INTERVAL '30 days'
  AND s.llm_prompt_tokens IS NOT NULL
GROUP BY DATE_TRUNC('day', s.timestamp), s.inference_tier
ORDER BY day DESC, s.inference_tier;

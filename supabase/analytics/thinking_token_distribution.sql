-- THINKING TOKEN DISTRIBUTION BY TIER
-- Thinking tokens are the dominant output cost driver, especially for Pro.
-- Flash thinking budget: 2,048. Pro thinking budget: 5,000.
-- P90 approaching the budget ceiling is a signal to raise the cap.
-- P90 well below the cap means budget is not constraining the model.

SELECT
  inference_tier,
  COUNT(*)                                                        AS scans,
  ROUND(AVG(llm_thinking_tokens))                                 AS avg_thinking,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY llm_thinking_tokens)
                                                                  AS p50_thinking,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY llm_thinking_tokens)
                                                                  AS p90_thinking,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY llm_thinking_tokens)
                                                                  AS p95_thinking,
  MAX(llm_thinking_tokens)                                        AS max_thinking,
  -- What % of scans hit the thinking budget ceiling (within 50 tokens)
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE
      (inference_tier = 'flash' AND llm_thinking_tokens >= 1998) OR
      (inference_tier = 'pro'  AND llm_thinking_tokens >= 4950)
    ) / NULLIF(COUNT(*), 0),
    2
  )                                                               AS pct_at_budget_ceiling,
  -- Total thinking output cost (cents)
  ROUND(SUM(CASE
    WHEN inference_tier = 'flash' THEN llm_thinking_tokens * 0.300 / 1000000.0 * 100
    WHEN inference_tier = 'pro'  THEN llm_thinking_tokens * 10.00 / 1000000.0 * 100
    ELSE 0
  END), 4)                                                        AS thinking_cost_cents
FROM public.scans
WHERE llm_thinking_tokens IS NOT NULL
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY inference_tier
ORDER BY inference_tier;

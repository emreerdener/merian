-- TOKEN COST SUMMARY
-- Estimated API spend per tier using current Gemini 2.5 pricing.
-- Gemini 2.5 Flash: input $0.075/M, cached input $0.01875/M, output $0.30/M (incl. thinking)
-- Gemini 2.5 Pro:  input $1.25/M,  no caching,               output $10.00/M (incl. thinking)
-- Run this query to get a high-level cost picture for any date range.
-- Adjust the WHERE clause to scope by week, month, or all-time.

WITH pricing AS (
  SELECT
    -- Flash rates (per token)
    0.075   / 1000000.0 AS flash_input,
    0.01875 / 1000000.0 AS flash_cached,
    0.300   / 1000000.0 AS flash_output,
    -- Pro rates (per token)
    1.25    / 1000000.0 AS pro_input,
    10.00   / 1000000.0 AS pro_output
),
scan_costs AS (
  SELECT
    s.inference_tier,
    COUNT(*)                                        AS scan_count,
    -- Prompt cost: cached portion at discount, remainder at full rate
    SUM(CASE
      WHEN s.inference_tier = 'flash' THEN
        COALESCE(s.llm_cached_tokens, 0)                                       * p.flash_cached
        + (COALESCE(s.llm_prompt_tokens, 0) - COALESCE(s.llm_cached_tokens, 0)) * p.flash_input
      WHEN s.inference_tier = 'pro' THEN
        COALESCE(s.llm_prompt_tokens, 0)                                       * p.pro_input
      ELSE 0
    END)                                            AS prompt_cost_usd,
    -- Output cost: candidates + thinking at output rate
    SUM(CASE
      WHEN s.inference_tier = 'flash' THEN
        (COALESCE(s.llm_candidate_tokens, 0) + COALESCE(s.llm_thinking_tokens, 0)) * p.flash_output
      WHEN s.inference_tier = 'pro' THEN
        (COALESCE(s.llm_candidate_tokens, 0) + COALESCE(s.llm_thinking_tokens, 0)) * p.pro_output
      ELSE 0
    END)                                            AS output_cost_usd
  FROM public.scans s
  CROSS JOIN pricing p
  WHERE s.created_at >= NOW() - INTERVAL '30 days'   -- adjust window here
    AND s.llm_prompt_tokens IS NOT NULL
  GROUP BY s.inference_tier
)
SELECT
  inference_tier,
  scan_count,
  ROUND((prompt_cost_usd * 100)::numeric, 4)          AS prompt_cost_cents,
  ROUND((output_cost_usd * 100)::numeric, 4)          AS output_cost_cents,
  ROUND(((prompt_cost_usd + output_cost_usd) * 100)::numeric, 4) AS total_cost_cents,
  ROUND((((prompt_cost_usd + output_cost_usd) / NULLIF(scan_count, 0)) * 100)::numeric, 6)
                                                      AS cost_per_scan_cents
FROM scan_costs
ORDER BY inference_tier;

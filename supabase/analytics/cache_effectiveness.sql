-- CACHE EFFECTIVENESS
-- Measures implicit context caching hit rate and token savings for Flash scans.
-- A cache hit is any scan where llm_cached_tokens > 0.
-- Only meaningful for Flash scans after the system instruction expanded past 1,024 tokens.
-- NULL llm_cached_tokens = scan predates the column or caching was not triggered.

SELECT
  DATE_TRUNC('day', created_at)                       AS day,
  COUNT(*)                                            AS flash_scans,
  COUNT(*) FILTER (WHERE llm_cached_tokens > 0)       AS cache_hits,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE llm_cached_tokens > 0)
    / NULLIF(COUNT(*) FILTER (WHERE llm_cached_tokens IS NOT NULL), 0),
    1
  )                                                   AS hit_rate_pct,
  ROUND(AVG(llm_cached_tokens) FILTER (WHERE llm_cached_tokens > 0))
                                                      AS avg_cached_tokens_on_hit,
  -- Savings: difference between full input price and cached price per hit
  -- (cached_tokens * (flash_input_rate - flash_cached_rate))
  ROUND(
    SUM(llm_cached_tokens) FILTER (WHERE llm_cached_tokens > 0)
    * (0.075 - 0.01875) / 1000000.0 * 100,           -- result in cents
    4
  )                                                   AS cache_savings_cents
FROM public.scans
WHERE inference_tier = 'flash'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY day DESC;

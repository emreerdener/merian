-- INSIGHT CHAT COST SUMMARY
-- Estimates Gemini 2.5 Flash spend for Pro Insight chat assistant replies.
-- Token telemetry is stored on assistant rows in insight_chat_messages.

WITH pricing AS (
  SELECT
    0.300 / 1000000.0 AS flash_input,
    0.030 / 1000000.0 AS flash_cached,
    2.500 / 1000000.0 AS flash_output
),
message_costs AS (
  SELECT
    COUNT(*) AS assistant_messages,
    SUM(
      COALESCE(m.llm_cached_tokens, 0) * p.flash_cached
      + (COALESCE(m.llm_prompt_tokens, 0) - COALESCE(m.llm_cached_tokens, 0)) * p.flash_input
      + (COALESCE(m.llm_candidate_tokens, 0) + COALESCE(m.llm_thinking_tokens, 0)) * p.flash_output
    ) AS cost_usd,
    SUM(COALESCE(m.llm_prompt_tokens, 0)) AS prompt_tokens,
    SUM(COALESCE(m.llm_cached_tokens, 0)) AS cached_tokens,
    SUM(COALESCE(m.llm_candidate_tokens, 0) + COALESCE(m.llm_thinking_tokens, 0)) AS output_tokens
  FROM public.insight_chat_messages m
  CROSS JOIN pricing p
  WHERE m.role = 'assistant'
    AND m.created_at >= NOW() - INTERVAL '30 days'
)
SELECT
  assistant_messages,
  prompt_tokens,
  cached_tokens,
  output_tokens,
  ROUND((cost_usd * 100)::numeric, 4) AS total_cost_cents,
  ROUND(((cost_usd / NULLIF(assistant_messages, 0)) * 100)::numeric, 6) AS cost_per_reply_cents
FROM message_costs;

-- Forward-only attribution and cost coverage. Existing ledger rows, prices,
-- ownership, append-only/anonymization rules and provider assignments are unchanged.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION public.record_ai_usage_event(p_operation text, p_model text, p_effective_plan text DEFAULT 'unknown'::text, p_input_modality text DEFAULT 'unknown'::text, p_prompt_tokens bigint DEFAULT NULL::bigint, p_cached_tokens bigint DEFAULT NULL::bigint, p_candidate_tokens bigint DEFAULT NULL::bigint, p_thinking_tokens bigint DEFAULT NULL::bigint, p_tool_tokens bigint DEFAULT NULL::bigint, p_total_tokens bigint DEFAULT NULL::bigint, p_prompt_tokens_by_modality jsonb DEFAULT '{}'::jsonb, p_outcome text DEFAULT 'success'::text, p_user_id uuid DEFAULT NULL::uuid, p_scan_id uuid DEFAULT NULL::uuid, p_conversation_id uuid DEFAULT NULL::uuid, p_message_id uuid DEFAULT NULL::uuid, p_source_type text DEFAULT NULL::text, p_source_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb, p_occurred_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  event_id UUID;
  estimated_cost BIGINT;
  estimate_version TEXT;
  resolved_provider TEXT;
BEGIN
    PERFORM internal.require_service_role();

  -- Legacy RPC calls use the existing Gemini-shaped token contract. Explicit
  -- provider/usage metadata can only narrow pricing eligibility, never borrow
  -- a Gemini tariff for another provider with an identical model name.
  resolved_provider := CASE
    WHEN COALESCE(p_metadata, '{}'::JSONB) ? 'ai_provider' THEN
      CASE WHEN pg_catalog.JSONB_TYPEOF(p_metadata -> 'ai_provider') = 'string'
        THEN p_metadata ->> 'ai_provider' ELSE 'unknown' END
    WHEN p_model IN ('gemini-2.5-flash', 'gemini-2.5-pro') THEN 'gemini'
    ELSE 'unknown'
  END;
  IF resolved_provider = 'gemini'
     AND (NOT (COALESCE(p_metadata, '{}'::JSONB) ? 'ai_usage_contract')
          OR p_metadata ->> 'ai_usage_contract' = 'gemini_token_counts_v1')
     AND p_input_modality IN ('text', 'image', 'audio', 'video', 'mixed')
     AND p_prompt_tokens IS NOT NULL AND p_candidate_tokens IS NOT NULL
     AND (p_cached_tokens IS NULL OR p_cached_tokens <= p_prompt_tokens) THEN
    SELECT price.cost_microusd, price.pricing_version INTO estimated_cost, estimate_version
    FROM internal.estimate_ai_cost_microusd(
      p_model, p_input_modality, COALESCE(p_occurred_at, NOW()),
      p_prompt_tokens, p_cached_tokens, p_candidate_tokens,
      p_thinking_tokens, p_tool_tokens
    ) AS price;
  END IF;

  INSERT INTO public.ai_usage_events (
    occurred_at, user_id, operation, model, effective_plan, input_modality,
    prompt_tokens, cached_tokens, candidate_tokens, thinking_tokens, tool_tokens,
    total_tokens, prompt_tokens_by_modality, outcome, scan_id, conversation_id,
    message_id, source_type, source_id, estimated_cost_microusd, pricing_version,
    metadata
  ) VALUES (
    COALESCE(p_occurred_at, NOW()), p_user_id, btrim(p_operation), btrim(p_model),
    p_effective_plan, p_input_modality, p_prompt_tokens, p_cached_tokens,
    p_candidate_tokens, p_thinking_tokens, p_tool_tokens, p_total_tokens,
    COALESCE(p_prompt_tokens_by_modality, '{}'::JSONB), p_outcome, p_scan_id,
    p_conversation_id, p_message_id, p_source_type, p_source_id,
    estimated_cost, estimate_version,
    COALESCE(p_metadata, '{}'::JSONB)
  )
  ON CONFLICT (source_type, source_id, operation) DO NOTHING
  RETURNING id INTO event_id;

  IF event_id IS NULL AND p_source_type IS NOT NULL AND p_source_id IS NOT NULL THEN
    SELECT event.id INTO event_id
    FROM public.ai_usage_events event
    WHERE event.source_type = p_source_type
      AND event.source_id = p_source_id
      AND event.operation = btrim(p_operation);
  END IF;

  RETURN event_id;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.trg_record_scan_ai_usage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  resolved_plan TEXT := 'unknown';
  resolved_modality TEXT := 'image';
  resolved_model TEXT;
  execution_metadata JSONB;
BEGIN
  IF NEW.llm_total_tokens IS NULL THEN RETURN NEW; END IF;
  SELECT internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)
  INTO resolved_plan FROM public.users app_user WHERE app_user.id = NEW.user_id;
  resolved_modality := CASE
    WHEN COALESCE(array_length(NEW.video_storage_urls, 1), 0) > 0
      OR (
        COALESCE(array_length(NEW.audio_storage_urls, 1), 0) > 0
        AND COALESCE(array_length(NEW.image_storage_urls, 1), 0) > 0
      ) THEN 'mixed'
    WHEN COALESCE(array_length(NEW.audio_storage_urls, 1), 0) > 0 THEN 'audio'
    ELSE 'image'
  END;
  IF NEW.identification_provenance IS NULL THEN
    resolved_model := CASE WHEN NEW.inference_tier::TEXT = 'pro'
      THEN 'gemini-2.5-pro' ELSE 'gemini-2.5-flash' END;
    execution_metadata := pg_catalog.JSONB_BUILD_OBJECT(
      'writer', 'scan_trigger', 'ai_provider', 'gemini',
      'ai_attribution', 'legacy_tier', 'ai_usage_contract', 'gemini_token_counts_v1');
  ELSE
    resolved_model := NEW.identification_provenance ->> 'model';
    execution_metadata := pg_catalog.JSONB_BUILD_OBJECT(
      'writer', 'scan_trigger', 'ai_provider', NEW.identification_provenance ->> 'provider',
      'ai_binding', NEW.identification_provenance ->> 'binding',
      'ai_policy_version', NEW.identification_provenance -> 'policy_version',
      'ai_prompt', NEW.identification_provenance ->> 'prompt',
      'ai_schema', NEW.identification_provenance ->> 'schema',
      'ai_operation', NEW.identification_provenance ->> 'operation',
      'ai_attribution', 'recorded_provenance',
      'ai_usage_contract', CASE WHEN NEW.identification_provenance ->> 'provider' = 'gemini'
        THEN 'gemini_token_counts_v1' ELSE NULL END);
  END IF;
  PERFORM public.record_ai_usage_event(
    'scan_identification',
    resolved_model,
    COALESCE(resolved_plan, 'unknown'), resolved_modality,
    NEW.llm_prompt_tokens, NEW.llm_cached_tokens, NEW.llm_candidate_tokens,
    NEW.llm_thinking_tokens, NULL, NEW.llm_total_tokens, NEW.llm_usage_metadata,
    'success', NEW.user_id, NEW.id, NULL, NULL, 'scan', NEW.id,
    execution_metadata, NEW.timestamp
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_ai_usage_summary(p_days integer DEFAULT 30, p_operation text DEFAULT NULL::text, p_model text DEFAULT NULL::text, p_effective_plan text DEFAULT NULL::text, p_input_modality text DEFAULT NULL::text, p_scan_scope text DEFAULT 'primary'::text, p_refresh boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_role TEXT;
  bounded_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 0), 36500);
  start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN '1970-01-01T00:00:00Z'::TIMESTAMPTZ
    ELSE NOW() - make_interval(days => bounded_days) END;
  -- Structural encoding distinguishes delimiters and SQL NULL from literal '*'.
  cache_key_value TEXT := 'ai:provider-coverage-v1:' || pg_catalog.JSONB_BUILD_ARRAY(
    bounded_days, p_operation, p_model, p_effective_plan, p_input_modality,
    COALESCE(p_scan_scope, 'primary')
  )::TEXT;
  result JSONB;
BEGIN
  caller_role := internal.require_admin('analyst');
  IF COALESCE(p_scan_scope, 'primary') NOT IN ('primary', 'all_scan_related') THEN
    RAISE EXCEPTION 'Invalid scan usage scope.' USING ERRCODE = '22023';
  END IF;
  IF NOT COALESCE(p_refresh, FALSE) THEN
    SELECT cache.payload INTO result FROM internal.admin_aggregate_cache cache
    WHERE cache.cache_key = cache_key_value
      AND cache.created_at > NOW() - INTERVAL '5 minutes';
    IF FOUND THEN
      PERFORM internal.write_admin_audit(caller_role, 'ai_usage_viewed_cached', 'ai_usage', bounded_days::TEXT);
      RETURN result;
    END IF;
  END IF;
  WITH filtered AS MATERIALIZED (
    SELECT event.*,
      CASE
        WHEN event.metadata ? 'ai_provider' THEN CASE
          WHEN pg_catalog.JSONB_TYPEOF(event.metadata -> 'ai_provider') = 'string'
            AND event.metadata ->> 'ai_provider' ~ '^[a-z][a-z0-9_.-]{0,79}$'
          THEN event.metadata ->> 'ai_provider' ELSE 'unknown' END
        WHEN event.model IN ('gemini-2.5-flash','gemini-2.5-pro') THEN 'gemini'
        ELSE 'unknown'
      END AS provider_identity,
      CASE
        WHEN event.metadata ->> 'ai_attribution' = 'recorded_provenance' THEN 'saved_result'
        WHEN event.metadata ->> 'ai_attribution' = 'legacy_tier' THEN 'legacy_tier'
        WHEN event.metadata ? 'ai_provider' THEN 'execution_metadata'
        WHEN event.model IN ('gemini-2.5-flash','gemini-2.5-pro') THEN 'legacy_model'
        ELSE 'unknown'
      END AS attribution_source
    FROM public.ai_usage_events event
    WHERE event.occurred_at >= start_at
      AND (p_operation IS NULL OR event.operation = p_operation)
      AND (p_model IS NULL OR event.model = p_model)
      AND (p_effective_plan IS NULL OR event.effective_plan = p_effective_plan)
      AND (p_input_modality IS NULL OR event.input_modality = p_input_modality)
  ), scan_totals AS (
    SELECT event.scan_id, SUM(COALESCE(event.total_tokens, 0)) AS total_tokens
    FROM filtered event
    WHERE event.scan_id IS NOT NULL
      AND (
        COALESCE(p_scan_scope, 'primary') = 'all_scan_related'
        OR (event.operation = 'scan_identification' AND event.outcome = 'success')
      )
    GROUP BY event.scan_id
  )
  SELECT jsonb_build_object(
    'events', COUNT(*),
    'priced_events', COUNT(*) FILTER (WHERE estimated_cost_microusd IS NOT NULL),
    'unpriced_events', COUNT(*) FILTER (WHERE estimated_cost_microusd IS NULL),
    'prompt_tokens', COALESCE(SUM(prompt_tokens), 0),
    'cached_tokens', COALESCE(SUM(cached_tokens), 0),
    'candidate_tokens', COALESCE(SUM(candidate_tokens), 0),
    'thinking_tokens', COALESCE(SUM(thinking_tokens), 0),
    'tool_tokens', COALESCE(SUM(tool_tokens), 0),
    'total_tokens', COALESCE(SUM(total_tokens), 0),
    'estimated_cost_microusd', COALESCE(SUM(estimated_cost_microusd), 0),
    'cache_hit_rate', ROUND(100.0 * COUNT(*) FILTER (WHERE cached_tokens > 0) / NULLIF(COUNT(*) FILTER (WHERE cached_tokens IS NOT NULL), 0), 2),
    'scan_avg', (SELECT ROUND(AVG(scan.total_tokens)) FROM scan_totals scan),
    'scan_p50', (SELECT percentile_cont(0.50) WITHIN GROUP (ORDER BY scan.total_tokens) FROM scan_totals scan),
    'scan_p95', (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY scan.total_tokens) FROM scan_totals scan),
    'scan_scope', COALESCE(p_scan_scope, 'primary'),
    'modality_tokens', (
      SELECT COALESCE(jsonb_object_agg(modality_row.modality, modality_row.tokens), '{}'::JSONB)
      FROM (
        SELECT modality.key AS modality, SUM((modality.value #>> '{}')::BIGINT) AS tokens
        FROM filtered event
        CROSS JOIN LATERAL jsonb_each(COALESCE(event.prompt_tokens_by_modality, '{}'::JSONB)) category
        CROSS JOIN LATERAL jsonb_each(
          CASE WHEN jsonb_typeof(category.value) = 'object' THEN category.value ELSE '{}'::JSONB END
        ) modality
        WHERE jsonb_typeof(modality.value) = 'number'
        GROUP BY modality.key
      ) modality_row
    ),
    'provider_usage', (
      SELECT COALESCE(jsonb_agg(to_jsonb(provider_row) ORDER BY provider_row.events DESC,
        provider_row.provider, provider_row.model, provider_row.attribution), '[]'::JSONB)
      FROM (
        SELECT provider_identity AS provider, model, attribution_source AS attribution,
          COUNT(*) AS events, COALESCE(SUM(total_tokens), 0) AS total_tokens,
          COUNT(*) FILTER (WHERE estimated_cost_microusd IS NOT NULL) AS priced_events,
          COUNT(*) FILTER (WHERE estimated_cost_microusd IS NULL) AS unpriced_events,
          COALESCE(SUM(estimated_cost_microusd), 0) AS estimated_cost_microusd
        FROM filtered GROUP BY provider_identity, model, attribution_source
        ORDER BY events DESC, provider, model, attribution LIMIT 50
      ) provider_row
    ),
    'provider_groups_truncated', (
      SELECT COUNT(*) > 50 FROM (
        SELECT 1 FROM filtered GROUP BY provider_identity, model, attribution_source
        LIMIT 51
      ) provider_groups
    ),
    'complete_from', MIN(occurred_at) FILTER (WHERE is_backfilled = FALSE),
    'daily', (
      SELECT COALESCE(jsonb_agg(to_jsonb(day_row) ORDER BY day_row.day), '[]'::JSONB)
      FROM (
        SELECT date_trunc('day', occurred_at)::DATE AS day,
               COUNT(*) AS events,
               COUNT(*) FILTER (WHERE estimated_cost_microusd IS NOT NULL) AS priced_events,
               COUNT(*) FILTER (WHERE estimated_cost_microusd IS NULL) AS unpriced_events,
               COALESCE(SUM(total_tokens), 0) AS total_tokens,
               COALESCE(SUM(estimated_cost_microusd), 0) AS estimated_cost_microusd
        FROM filtered GROUP BY 1
      ) day_row
    )
  ) INTO result FROM filtered;

  INSERT INTO internal.admin_aggregate_cache (cache_key, payload, created_at)
  VALUES (cache_key_value, result, NOW())
  ON CONFLICT (cache_key) DO UPDATE SET payload = EXCLUDED.payload, created_at = EXCLUDED.created_at;

  PERFORM internal.write_admin_audit(caller_role, 'ai_usage_viewed', 'ai_usage', bounded_days::TEXT);
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_overview(p_days integer DEFAULT 30, p_timezone text DEFAULT 'UTC'::text, p_refresh boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_role TEXT;
  bounded_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 0), 36500);
  start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN '1970-01-01T00:00:00Z'::TIMESTAMPTZ
    ELSE NOW() - make_interval(days => bounded_days) END;
  previous_start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN start_at
    ELSE start_at - make_interval(days => bounded_days) END;
  cache_key_value TEXT := format('overview:provider-coverage-v1:%s:%s', bounded_days, COALESCE(p_timezone, 'UTC'));
  result JSONB;
BEGIN
  caller_role := internal.require_admin('analyst');
  IF NOT COALESCE(p_refresh, FALSE) THEN
    SELECT cache.payload INTO result
    FROM internal.admin_aggregate_cache cache
    WHERE cache.cache_key = cache_key_value
      AND cache.created_at > NOW() - INTERVAL '5 minutes';
    IF FOUND THEN
      PERFORM internal.write_admin_audit(caller_role, 'overview_viewed_cached', 'dashboard', bounded_days::TEXT);
      RETURN result;
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'range_start', start_at,
    'range_end', NOW(),
    'coverage_complete_from', (
      SELECT MIN(event.occurred_at) FROM public.ai_usage_events event WHERE event.is_backfilled = FALSE
    ),
    'accounts', (
      SELECT jsonb_build_object(
        'total', COUNT(*),
        'registered', COUNT(*) FILTER (WHERE auth_user.is_anonymous = FALSE),
        'ghost', COUNT(*) FILTER (WHERE auth_user.is_anonymous = TRUE),
        'new_in_range', COUNT(*) FILTER (WHERE auth_user.created_at >= start_at)
      ) FROM auth.users auth_user
    ),
    'plans', (
      SELECT jsonb_build_object(
        'pro_paid', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = 'pro_paid'),
        'pro_trial', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = 'pro_trial'),
        'pro_complimentary', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = 'pro_complimentary'),
        'free', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = 'free')
      ) FROM auth.users auth_user LEFT JOIN public.users app_user ON app_user.id = auth_user.id
    ),
    'open_reviews', (
      SELECT COUNT(*) FROM internal.review_cases review
      WHERE review.status IN ('open', 'in_review')
    ),
    'new_feedback', (
      SELECT
        (SELECT COUNT(*) FROM public.community_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'community' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.feedback_survey_responses survey
          LEFT JOIN internal.feedback_state state ON state.source_type = 'survey' AND state.source_id = survey.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.insight_chat_message_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'chat_message' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.insight_chat_feature_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'chat_feature' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
    ),
    'ai', (
      SELECT jsonb_build_object(
        'events', COUNT(*),
        'priced_events', COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NOT NULL),
        'unpriced_events', COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NULL),
        'total_tokens', COALESCE(SUM(event.total_tokens), 0),
        'estimated_cost_microusd', COALESCE(SUM(event.estimated_cost_microusd), 0),
        'avg_tokens_per_scan', ROUND(AVG(event.total_tokens) FILTER (
          WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
        ))
      ) FROM public.ai_usage_events event WHERE event.occurred_at >= start_at
    ),
    'previous_period', CASE WHEN bounded_days = 0 THEN NULL ELSE (
      SELECT jsonb_build_object(
        'events', COUNT(*),
        'priced_events', COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NOT NULL),
        'unpriced_events', COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NULL),
        'scans', COUNT(*) FILTER (
          WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
        ),
        'total_tokens', COALESCE(SUM(event.total_tokens), 0),
        'estimated_cost_microusd', COALESCE(SUM(event.estimated_cost_microusd), 0)
      )
      FROM public.ai_usage_events event
      WHERE event.occurred_at >= previous_start_at AND event.occurred_at < start_at
    ) END,
    'daily', (
      SELECT COALESCE(jsonb_agg(to_jsonb(day_row) ORDER BY day_row.day), '[]'::JSONB)
      FROM (
        SELECT
          date_trunc('day', event.occurred_at AT TIME ZONE p_timezone)::DATE AS day,
          COUNT(*) AS events,
          COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NOT NULL) AS priced_events,
          COUNT(*) FILTER (WHERE event.estimated_cost_microusd IS NULL) AS unpriced_events,
          COUNT(*) FILTER (
            WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
          ) AS scans,
          COALESCE(SUM(event.total_tokens), 0) AS total_tokens,
          COALESCE(SUM(event.estimated_cost_microusd), 0) AS estimated_cost_microusd
        FROM public.ai_usage_events event
        WHERE event.occurred_at >= start_at
        GROUP BY 1
      ) day_row
    )
  ) INTO result;

  INSERT INTO internal.admin_aggregate_cache (cache_key, payload, created_at)
  VALUES (cache_key_value, result, NOW())
  ON CONFLICT (cache_key) DO UPDATE SET payload = EXCLUDED.payload, created_at = EXCLUDED.created_at;

  PERFORM internal.write_admin_audit(caller_role, 'overview_viewed', 'dashboard', bounded_days::TEXT);
  RETURN result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;

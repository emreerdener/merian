-- Forward-only primary invocation accounting. Does not enable a provider.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

CREATE TABLE internal.ai_native_token_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    usage_contract TEXT NOT NULL,
    service_tier TEXT NOT NULL,
    endpoint_profile TEXT NOT NULL,
    input_modality TEXT NOT NULL,
    max_input_tokens BIGINT NOT NULL CHECK (max_input_tokens > 0),
    input_usd_per_million NUMERIC(12,6) NOT NULL CHECK (input_usd_per_million >= 0),
    cached_usd_per_million NUMERIC(12,6) NOT NULL CHECK (cached_usd_per_million >= 0),
    cache_write_usd_per_million NUMERIC(12,6) NOT NULL CHECK (cache_write_usd_per_million >= 0),
    output_usd_per_million NUMERIC(12,6) NOT NULL CHECK (output_usd_per_million >= 0),
    effective_from TIMESTAMPTZ NOT NULL,
    effective_to TIMESTAMPTZ,
    version TEXT NOT NULL UNIQUE,
    CHECK (effective_to IS NULL OR effective_to > effective_from),
    EXCLUDE USING gist (
        provider extensions.gist_text_ops WITH =,
        model extensions.gist_text_ops WITH =,
        service_tier extensions.gist_text_ops WITH =,
        endpoint_profile extensions.gist_text_ops WITH =,
        input_modality extensions.gist_text_ops WITH =,
        tstzrange(effective_from, effective_to, '[)') WITH &&
    )
);
ALTER TABLE internal.ai_native_token_prices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.ai_native_token_prices FROM PUBLIC, anon, authenticated, service_role;

-- Reviewed 2026-09-27: https://developers.openai.com/api/docs/models/gpt-6-sol
-- and https://developers.openai.com/api/docs/guides/prompt-caching.
-- Standard/global, short context only. Cache writes replace input pricing;
-- Responses output already includes reasoning. No historical event repricing.
INSERT INTO internal.ai_native_token_prices (
    provider, model, usage_contract, service_tier, endpoint_profile, input_modality,
    max_input_tokens, input_usd_per_million, cached_usd_per_million,
    cache_write_usd_per_million, output_usd_per_million, effective_from, version
) VALUES ('openai', 'gpt-6-sol', 'openai_responses_tokens_v1', 'default',
    'openai_responses_global_v1', 'image', 272000, 2, 0.2, 2.5, 10,
    '2026-09-27T23:08:01Z', 'openai-photo-standard-2026-09-27');

CREATE TABLE internal.identification_invocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id UUID,
    attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
    -- Hash only; the quota lease itself is never retained in accounting.
    lease_sha256 TEXT,
    user_id UUID,
    scan_id UUID,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    binding TEXT NOT NULL,
    input_profile TEXT NOT NULL,
    effective_plan TEXT NOT NULL,
    policy_version BIGINT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Freeze the reviewed tariff at dispatch. Never reinterpret after a change.
    native_price JSONB,
    provenance JSONB NOT NULL CHECK (internal.identification_provenance_is_valid(provenance)),
    event_id UUID,
    UNIQUE (reservation_id, attempt_count)
);
CREATE INDEX identification_invocations_pending ON internal.identification_invocations (occurred_at)
    WHERE event_id IS NULL;
CREATE INDEX identification_invocations_scan ON internal.identification_invocations (scan_id, user_id);
CREATE INDEX identification_invocations_user ON internal.identification_invocations (user_id);
ALTER TABLE internal.identification_invocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.identification_invocations FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.ai_usage_events DROP CONSTRAINT ai_usage_events_outcome_check;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_outcome_check
    CHECK (outcome IN ('success', 'refusal', 'error', 'unknown'));

CREATE FUNCTION public.commit_identification_invocation(
    p_reservation_id UUID, p_user_id UUID, p_lease_token UUID, p_attempt_count INTEGER, p_provenance JSONB
) RETURNS TABLE(invocation_id UUID, may_dispatch BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'
AS $function$
DECLARE
    reserved internal.ai_quota_reservations%ROWTYPE;
    assigned internal.identification_provider_attempts%ROWTYPE;
    invocation internal.identification_invocations%ROWTYPE;
    price JSONB;
    started TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();
    IF p_reservation_id IS NULL OR p_user_id IS NULL OR p_lease_token IS NULL
        OR p_attempt_count IS NULL OR p_attempt_count < 1 OR p_provenance IS NULL
        OR NOT internal.identification_provenance_is_valid(p_provenance) THEN
        RAISE EXCEPTION 'identification_invocation_invalid' USING ERRCODE = '22023';
    END IF;
    -- Same user -> reservation lock order as admission/identity transitions.
    PERFORM id FROM public.users WHERE id = p_user_id FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'identification_invocation_unavailable' USING ERRCODE = 'P0001'; END IF;
    SELECT * INTO reserved FROM internal.ai_quota_reservations
        WHERE id = p_reservation_id AND user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR reserved.lease_token <> p_lease_token OR reserved.attempt_count <> p_attempt_count
        OR reserved.operation <> 'scan_identification' OR reserved.original_analysis_id IS NULL THEN
        RAISE EXCEPTION 'identification_invocation_conflict' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO invocation FROM internal.identification_invocations
        WHERE reservation_id = p_reservation_id AND attempt_count = p_attempt_count;
    IF FOUND THEN
        RETURN QUERY SELECT invocation.id, FALSE;
        RETURN;
    END IF;
    IF reserved.state <> 'reserved' THEN
        RAISE EXCEPTION 'identification_invocation_conflict' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO assigned FROM internal.identification_provider_attempts
        WHERE reservation_id = p_reservation_id AND attempt_count = p_attempt_count;
    IF NOT FOUND OR assigned.input_profile NOT LIKE 'multimodal_%'
        OR assigned.operation <> reserved.operation THEN
        RAISE EXCEPTION 'identification_invocation_unqualified' USING ERRCODE = 'P0001';
    END IF;
    IF p_provenance ->> 'provider' IS DISTINCT FROM assigned.provider
        OR p_provenance ->> 'binding' IS DISTINCT FROM assigned.binding
        OR p_provenance ->> 'model' IS DISTINCT FROM COALESCE(assigned.provider_model, assigned.model)
        OR p_provenance ->> 'operation' IS DISTINCT FROM assigned.operation
        OR p_provenance ->> 'variant' IS DISTINCT FROM 'multimodal'
        OR p_provenance ->> 'policy_version' IS DISTINCT FROM assigned.policy_version::TEXT THEN
        RAISE EXCEPTION 'identification_invocation_provenance_conflict' USING ERRCODE = 'P0001';
    END IF;
    started := clock_timestamp();
    IF assigned.provider = 'openai' AND assigned.binding = 'openai_photo_v1' THEN
        SELECT to_jsonb(pricing) - 'id' INTO price FROM internal.ai_native_token_prices pricing
        WHERE pricing.provider = assigned.provider AND pricing.model = assigned.provider_model
          AND pricing.usage_contract = 'openai_responses_tokens_v1'
          AND pricing.service_tier = 'default' AND pricing.endpoint_profile = 'openai_responses_global_v1'
          AND pricing.input_modality = 'image'
          AND pricing.effective_from <= started AND (pricing.effective_to IS NULL OR pricing.effective_to > started);
        IF price IS NULL THEN RAISE EXCEPTION 'identification_pricing_unavailable' USING ERRCODE = 'P0001'; END IF;
    END IF;
    PERFORM public.finalize_ai_quota_reservation(p_reservation_id, p_user_id, p_lease_token, 'committed');
    INSERT INTO internal.identification_invocations (
        reservation_id, attempt_count, lease_sha256, user_id, scan_id,
        provider, model, binding, input_profile, effective_plan, policy_version, occurred_at, native_price, provenance
    ) VALUES (
        reserved.id, reserved.attempt_count, encode(extensions.digest(p_lease_token::TEXT, 'sha256'), 'hex'),
        p_user_id, reserved.original_analysis_id, assigned.provider, COALESCE(assigned.provider_model, assigned.model),
        assigned.binding, assigned.input_profile, assigned.effective_plan, assigned.policy_version, started, price, p_provenance
    ) RETURNING id INTO invocation_id;
    may_dispatch := TRUE;
    RETURN NEXT;
END;
$function$;

-- Native facts only; no response body, exception text, evidence or provider IDs.
CREATE FUNCTION internal.identification_usage_count(p_usage JSONB, p_key TEXT)
RETURNS BIGINT LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path = ''
AS $function$
    SELECT CASE WHEN jsonb_typeof(p_usage -> p_key) = 'number'
        AND p_usage ->> p_key ~ '^[0-9]{1,9}$'
        AND (p_usage ->> p_key)::NUMERIC <= 100000000
        THEN (p_usage ->> p_key)::BIGINT ELSE NULL END;
$function$;

CREATE FUNCTION internal.complete_identification_usage(p_invocation_id UUID, p_outcome TEXT, p_usage JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $function$
DECLARE
    invocation internal.identification_invocations%ROWTYPE;
    event_uuid UUID;
    input_count BIGINT; cached BIGINT; writes BIGINT; output_count BIGINT;
    candidates BIGINT; thinking BIGINT; tools BIGINT; total BIGINT;
    cost BIGINT; price_version TEXT; modality TEXT; metadata JSONB;
    breakdown JSONB := '{}'::JSONB; category TEXT; unit TEXT; units JSONB; value BIGINT;
BEGIN
    SELECT * INTO invocation FROM internal.identification_invocations WHERE id = p_invocation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'identification_invocation_not_found' USING ERRCODE = 'P0001'; END IF;
    IF invocation.event_id IS NOT NULL THEN RETURN invocation.event_id; END IF;
    IF p_outcome IS NULL OR p_outcome NOT IN ('draft', 'refusal', 'invalid_output', 'operational_failure', 'unknown_execution')
        OR jsonb_typeof(p_usage) IS DISTINCT FROM 'object' OR octet_length(p_usage::TEXT) > 2048
        OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_usage) k WHERE k NOT IN (
            'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens',
            'candidate_tokens', 'thinking_tokens', 'tool_tokens', 'total_tokens', 'service_tier', 'modality_breakdown')) THEN
        RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE = '22023';
    END IF;
    IF invocation.provider = 'gemini' THEN
        FOREACH category IN ARRAY ARRAY['prompt','cached','candidates','tool'] LOOP
            units := '{}'::JSONB;
            FOREACH unit IN ARRAY ARRAY['text','image','audio','video'] LOOP
                value := internal.identification_usage_count(p_usage -> 'modality_breakdown' -> category, unit);
                IF value IS NOT NULL THEN units := units || jsonb_build_object(unit, value); END IF;
            END LOOP;
            breakdown := breakdown || jsonb_build_object(category, units);
        END LOOP;
    END IF;
    input_count := internal.identification_usage_count(p_usage, 'input_tokens');
    cached := internal.identification_usage_count(p_usage, 'cached_tokens');
    writes := internal.identification_usage_count(p_usage, 'cache_write_tokens');
    output_count := internal.identification_usage_count(p_usage, 'output_tokens');
    candidates := internal.identification_usage_count(p_usage, 'candidate_tokens');
    thinking := internal.identification_usage_count(p_usage, 'thinking_tokens');
    tools := internal.identification_usage_count(p_usage, 'tool_tokens');
    total := internal.identification_usage_count(p_usage, 'total_tokens');
    modality := CASE invocation.input_profile
        WHEN 'multimodal_text_v1' THEN 'text'
        WHEN 'multimodal_photo_v1' THEN 'image'
        WHEN 'multimodal_audio_v1' THEN 'audio'
        WHEN 'multimodal_video_frames_v1' THEN 'video'
        ELSE 'mixed' END;
    metadata := jsonb_build_object('writer', 'identification_invocation', 'ai_provider', invocation.provider,
        'ai_binding', invocation.binding, 'ai_policy_version', invocation.policy_version,
        'ai_input_profile', invocation.input_profile, 'ai_attribution', 'attempt_snapshot', 'ai_outcome', p_outcome,
        'ai_prompt', invocation.provenance ->> 'prompt', 'ai_schema', invocation.provenance ->> 'schema',
        'ai_provenance', invocation.provenance,
        'ai_usage_contract', CASE invocation.provider WHEN 'openai' THEN 'openai_responses_tokens_v1'
            WHEN 'gemini' THEN 'gemini_token_counts_v1' END);
    IF invocation.provider = 'openai' THEN
        metadata := metadata || jsonb_build_object('ai_output_tokens', output_count, 'ai_cache_write_tokens', writes,
            'ai_service_tier', CASE WHEN p_usage ->> 'service_tier' = 'default' THEN 'default' ELSE NULL END);
        IF invocation.model = 'gpt-6-sol' AND invocation.binding = 'openai_photo_v1'
            AND modality = 'image' AND invocation.native_price IS NOT NULL
            AND p_usage ->> 'service_tier' = 'default'
            AND input_count IS NOT NULL AND cached IS NOT NULL AND writes IS NOT NULL AND output_count IS NOT NULL
            AND cached + writes <= input_count
            AND input_count <= (invocation.native_price ->> 'max_input_tokens')::BIGINT
            AND tools = 0 AND (thinking IS NULL OR thinking <= output_count)
            AND (total IS NULL OR total = input_count + output_count)
            AND (candidates IS NULL OR thinking IS NULL OR candidates + thinking = output_count) THEN
            cost := round((input_count - cached - writes) * (invocation.native_price ->> 'input_usd_per_million')::NUMERIC
                + cached * (invocation.native_price ->> 'cached_usd_per_million')::NUMERIC
                + writes * (invocation.native_price ->> 'cache_write_usd_per_million')::NUMERIC
                + output_count * (invocation.native_price ->> 'output_usd_per_million')::NUMERIC)::BIGINT;
            price_version := invocation.native_price ->> 'version';
        END IF;
    ELSIF invocation.provider = 'gemini' AND input_count IS NOT NULL AND candidates IS NOT NULL
        AND (cached IS NULL OR cached <= input_count) THEN
        SELECT pricing.cost_microusd, pricing.pricing_version INTO cost, price_version
        FROM internal.estimate_ai_cost_microusd(invocation.model, modality, invocation.occurred_at,
            input_count, cached, candidates, thinking, tools) pricing;
    END IF;
    INSERT INTO public.ai_usage_events (
        occurred_at, user_id, operation, model, effective_plan, input_modality,
        prompt_tokens, cached_tokens, candidate_tokens, thinking_tokens, tool_tokens, total_tokens, prompt_tokens_by_modality,
        outcome, scan_id, source_type, source_id, estimated_cost_microusd, pricing_version, metadata
    ) VALUES (invocation.occurred_at, invocation.user_id, 'scan_identification', invocation.model,
        invocation.effective_plan, modality, input_count, cached, candidates, thinking, tools, total, breakdown,
        CASE p_outcome WHEN 'draft' THEN 'success' WHEN 'refusal' THEN 'refusal'
            WHEN 'unknown_execution' THEN 'unknown' ELSE 'error' END,
        invocation.scan_id, 'identification_invocation', invocation.id, cost, price_version, metadata)
    ON CONFLICT (source_type, source_id, operation) DO NOTHING RETURNING id INTO event_uuid;
    IF event_uuid IS NULL THEN
        SELECT id INTO STRICT event_uuid FROM public.ai_usage_events
        WHERE source_type = 'identification_invocation' AND source_id = invocation.id AND operation = 'scan_identification';
    END IF;
    UPDATE internal.identification_invocations SET event_id = event_uuid WHERE id = invocation.id;
    RETURN event_uuid;
END;
$function$;

CREATE FUNCTION public.complete_identification_invocation(
    p_invocation_id UUID, p_user_id UUID, p_lease_token UUID, p_outcome TEXT, p_usage JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'
AS $function$
DECLARE invocation internal.identification_invocations%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_invocation_id IS NULL OR p_user_id IS NULL OR p_lease_token IS NULL THEN
        RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO invocation FROM internal.identification_invocations WHERE id = p_invocation_id FOR UPDATE;
    IF NOT FOUND OR invocation.user_id IS DISTINCT FROM p_user_id
        OR invocation.lease_sha256 IS DISTINCT FROM encode(extensions.digest(p_lease_token::TEXT, 'sha256'), 'hex') THEN
        RAISE EXCEPTION 'identification_invocation_conflict' USING ERRCODE = 'P0001';
    END IF;
    RETURN internal.complete_identification_usage(p_invocation_id, p_outcome, p_usage);
END;
$function$;

CREATE FUNCTION internal.reconcile_identification_usage(p_limit INTEGER DEFAULT 1000)
RETURNS INTEGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' SET statement_timeout = '15s'
AS $function$
DECLARE pending RECORD; reconciled INTEGER := 0;
BEGIN
    FOR pending IN SELECT id FROM internal.identification_invocations
        WHERE event_id IS NULL AND occurred_at < clock_timestamp() - INTERVAL '5 minutes'
        ORDER BY occurred_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 1000)
        FOR UPDATE SKIP LOCKED LOOP
        PERFORM internal.complete_identification_usage(pending.id, 'unknown_execution', '{}'::JSONB);
        reconciled := reconciled + 1;
    END LOOP;
    DELETE FROM internal.identification_invocations WHERE id IN (
        SELECT id FROM internal.identification_invocations
        WHERE event_id IS NOT NULL AND occurred_at < clock_timestamp() - INTERVAL '30 days'
        ORDER BY occurred_at LIMIT LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 1000)
        FOR UPDATE SKIP LOCKED
    );
    RETURN reconciled;
END;
$function$;

-- Serialize account deletion with completion BEFORE the existing event scrub.
CREATE FUNCTION internal.trg_anonymize_identification_invocations()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE invocation RECORD;
BEGIN
    FOR invocation IN SELECT id FROM internal.identification_invocations WHERE user_id = OLD.id ORDER BY id FOR UPDATE LOOP
        PERFORM internal.complete_identification_usage(invocation.id, 'unknown_execution', '{}'::JSONB);
    END LOOP;
    UPDATE internal.identification_invocations SET user_id = NULL, scan_id = NULL,
        reservation_id = NULL, lease_sha256 = NULL WHERE user_id = OLD.id;
    RETURN OLD;
END;
$function$;
CREATE TRIGGER trg_aa_anonymize_identification_invocations BEFORE DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION internal.trg_anonymize_identification_invocations();

-- Reparent the accounting witness at the same controlled identity transition.
DO $migration$
DECLARE definition TEXT; fragment TEXT;
BEGIN
    definition := pg_get_functiondef('internal.perform_ghost_profile_merge(uuid,uuid)'::regprocedure);
    fragment := 'UPDATE public.ai_usage_events AS event';
    IF strpos(definition, fragment) = 0 THEN RAISE EXCEPTION 'usage merge source drift'; END IF;
    definition := replace(definition, fragment,
        'UPDATE internal.identification_invocations SET user_id = p_target_user_id WHERE user_id = p_ghost_user_id;' || E'\n    ' || fragment);
    EXECUTE definition;
END;
$migration$;

-- An invocation has one writer even if completion is late or the scan is saved
-- more than once. Old bundles retain the scan-trigger fallback.
DO $migration$
DECLARE definition TEXT; fragment TEXT;
BEGIN
    definition := pg_get_functiondef('internal.trg_record_scan_ai_usage()'::regprocedure);
    fragment := 'BEGIN';
    definition := regexp_replace(definition, fragment,
        'BEGIN' || E'\n  IF NEW.llm_usage_metadata ->> ''accounting_contract'' = ''identification_invocation_v1'' THEN'
        || E'\n    IF NOT EXISTS (SELECT 1 FROM internal.identification_invocations WHERE scan_id = NEW.id AND user_id = NEW.user_id)'
        || E'\n      AND NOT EXISTS (SELECT 1 FROM public.ai_usage_events WHERE scan_id = NEW.id AND user_id = NEW.user_id AND source_type = ''identification_invocation'') THEN'
        || E'\n      RAISE EXCEPTION ''identification_usage_witness_missing'' USING ERRCODE = ''23514'';'
        || E'\n    END IF;'
        || E'\n    RETURN NEW;'
        || E'\n  END IF;');
    EXECUTE definition;
END;
$migration$;

REVOKE ALL ON FUNCTION public.commit_identification_invocation(UUID,UUID,UUID,INTEGER,JSONB),
    public.complete_identification_invocation(UUID,UUID,UUID,TEXT,JSONB),
    internal.identification_usage_count(JSONB,TEXT), internal.complete_identification_usage(UUID,TEXT,JSONB),
    internal.reconcile_identification_usage(INTEGER), internal.trg_anonymize_identification_invocations()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.commit_identification_invocation(UUID,UUID,UUID,INTEGER,JSONB),
    public.complete_identification_invocation(UUID,UUID,UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose) VALUES
    ('service_role','public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)','Atomic primary identification quota commit and unique invocation witness.'),
    ('service_role','public.complete_identification_invocation(uuid,uuid,uuid,text,jsonb)','Lease-bound append-only primary identification accounting completion.');

SELECT cron.schedule('reconcile_identification_usage', '* * * * *',
    $cron$SELECT internal.reconcile_identification_usage();$cron$);

COMMENT ON TABLE internal.identification_invocations IS
    'Primary multimodal may-have-dispatched witnesses. One append-only usage event per witness; absent reports become unknown after five minutes. No provider retry authority. Completed witnesses retained 30 days; append-only events retained under existing policy. Identifying linkage scrubbed on account deletion.';
NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;

-- Independent cutoff: replacement validation or client distribution cannot extend legacy dispatch.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

-- Google standard generateContent pricing, verified 2026-11-14:
-- https://aistudio.google.com/docs/pricing#gemini-3.8-flash
-- https://aistudio.google.com/docs/pricing#gemini-3.5-flash-lite
-- Cache storage/tools are not enabled by these stateless profiles.
INSERT INTO internal.ai_model_pricing(model,input_modality,prompt_usd_per_million,cached_usd_per_million,
    output_usd_per_million,effective_from,effective_to,version)
SELECT tariff.model,modality,tariff.input,tariff.cached,tariff.output,tariff.starts,tariff.ends,tariff.version
FROM (VALUES
  ('gemini-3.8-flash',0.75,0.075,3.75,TIMESTAMPTZ '2026-11-14 00:00:00+00',TIMESTAMPTZ '2027-01-01 00:00:00+00','google-standard-2026-11-14'),
  ('gemini-3.8-flash',1.50,0.15,7.50,TIMESTAMPTZ '2027-01-01 00:00:00+00',NULL::TIMESTAMPTZ,'google-standard-2027-01-01'),
  ('gemini-3.5-flash-lite',0.30,0.03,2.50,TIMESTAMPTZ '2026-11-14 00:00:00+00',NULL::TIMESTAMPTZ,'google-standard-2026-11-14')
) AS tariff(model,input,cached,output,starts,ends,version)
CROSS JOIN unnest(ARRAY['text','image','audio','video','mixed']) AS modality;

ALTER TABLE internal.gemini_invocation_receipts
    ADD COLUMN estimated_cost_microusd BIGINT CHECK (estimated_cost_microusd >= 0),
    ADD COLUMN pricing_version TEXT,
    ADD COLUMN settlement TEXT NOT NULL DEFAULT 'unresolved' CHECK (settlement IN ('settled','unresolved','not_invoked'));

CREATE FUNCTION internal.gemini_response_receipt_valid(p_value JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SET search_path = '' AS $$
DECLARE usage JSONB; category JSONB; item JSONB; key TEXT;
BEGIN
 IF pg_catalog.jsonb_typeof(p_value) IS DISTINCT FROM 'object' OR pg_catalog.octet_length(p_value::TEXT)>4096
  OR NOT p_value ?& ARRAY['returnedModel','usage','usageConsistent','finishReason','failure']
  OR p_value-ARRAY['returnedModel','usage','usageConsistent','finishReason','failure']<>'{}'::JSONB
  OR p_value->'usageConsistent' NOT IN ('true'::JSONB,'false'::JSONB)
  OR (p_value->'returnedModel'<>'null'::JSONB AND (pg_catalog.jsonb_typeof(p_value->'returnedModel')<>'string' OR p_value->>'returnedModel' !~ '^gemini-[a-zA-Z0-9.-]{1,100}$'))
  OR (p_value->'finishReason'<>'null'::JSONB AND (pg_catalog.jsonb_typeof(p_value->'finishReason')<>'string' OR p_value->>'finishReason' !~ '^[A-Z_]{1,80}$'))
  OR p_value->'failure' NOT IN ('null'::JSONB,'"envelope"'::JSONB,'"identity"'::JSONB,'"safety"'::JSONB,'"finish"'::JSONB,'"parts"'::JSONB) THEN RETURN FALSE; END IF;
 usage:=p_value->'usage';
 IF usage='null'::JSONB THEN RETURN p_value->'usageConsistent'='false'::JSONB; END IF;
 IF pg_catalog.jsonb_typeof(usage) IS DISTINCT FROM 'object'
  OR NOT usage ?& ARRAY['promptTokens','candidateTokens','thinkingTokens','cachedTokens','toolTokens','totalTokens','modalityBreakdown']
  OR usage-ARRAY['promptTokens','candidateTokens','thinkingTokens','cachedTokens','toolTokens','totalTokens','modalityBreakdown']<>'{}'::JSONB THEN RETURN FALSE; END IF;
 FOREACH key IN ARRAY ARRAY['promptTokens','candidateTokens','thinkingTokens','cachedTokens','toolTokens','totalTokens'] LOOP
  IF usage->key<>'null'::JSONB AND (pg_catalog.jsonb_typeof(usage->key)<>'number' OR usage->>key !~ '^[0-9]{1,9}$' OR (usage->>key)::NUMERIC>100000000) THEN RETURN FALSE; END IF;
 END LOOP;
 IF pg_catalog.jsonb_typeof(usage->'modalityBreakdown') IS DISTINCT FROM 'object'
  OR NOT (usage->'modalityBreakdown') ?& ARRAY['prompt','cached','candidates','tool']
  OR (usage->'modalityBreakdown')-ARRAY['prompt','cached','candidates','tool']<>'{}'::JSONB THEN RETURN FALSE; END IF;
 FOR category IN SELECT value FROM pg_catalog.jsonb_each(usage->'modalityBreakdown') LOOP
  IF pg_catalog.jsonb_typeof(category)<>'object' OR category-ARRAY['text','image','audio','video','document']<>'{}'::JSONB THEN RETURN FALSE; END IF;
  FOR item IN SELECT value FROM pg_catalog.jsonb_each(category) LOOP
   IF pg_catalog.jsonb_typeof(item)<>'number' OR item::TEXT !~ '^[0-9]{1,9}$' OR item::TEXT::NUMERIC>100000000 THEN RETURN FALSE; END IF;
  END LOOP;
 END LOOP;
 RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.gemini_response_receipt_valid(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.price_gemini_receipt(p_receipt JSONB,p_at TIMESTAMPTZ)
RETURNS TABLE(cost BIGINT,version TEXT) LANGUAGE PLPGSQL STABLE SET search_path = '' AS $$
BEGIN
 IF NOT COALESCE(internal.gemini_response_receipt_valid(p_receipt),FALSE) THEN RETURN; END IF;
 RETURN QUERY SELECT pg_catalog.round(
    ((p_receipt#>>'{usage,promptTokens}')::BIGINT-(p_receipt#>>'{usage,cachedTokens}')::BIGINT
      +(p_receipt#>>'{usage,toolTokens}')::BIGINT)*price.prompt_usd_per_million
    +(p_receipt#>>'{usage,cachedTokens}')::BIGINT*price.cached_usd_per_million
    +((p_receipt#>>'{usage,candidateTokens}')::BIGINT+(p_receipt#>>'{usage,thinkingTokens}')::BIGINT)*price.output_usd_per_million
 )::BIGINT,price.version
 FROM internal.ai_model_pricing AS price
 WHERE internal.gemini_response_receipt_valid(p_receipt)
   AND p_receipt->'usageConsistent'='true'::JSONB
   AND price.model=p_receipt->>'returnedModel'
   -- Generation 3 standard tariffs are modality-independent. Older models need
   -- modality evidence and remain unresolved here rather than assuming text.
   AND price.model IN ('gemini-3.8-flash','gemini-3.5-flash-lite') AND price.input_modality='text'
   AND price.effective_from<=p_at AND (price.effective_to IS NULL OR p_at<price.effective_to)
   AND (p_receipt#>>'{usage,cachedTokens}')::BIGINT <= (p_receipt#>>'{usage,promptTokens}')::BIGINT
   AND (p_receipt#>>'{usage,totalTokens}')::BIGINT = (p_receipt#>>'{usage,promptTokens}')::BIGINT
     +(p_receipt#>>'{usage,candidateTokens}')::BIGINT+(p_receipt#>>'{usage,thinkingTokens}')::BIGINT+(p_receipt#>>'{usage,toolTokens}')::BIGINT;
END;
$$;
REVOKE ALL ON FUNCTION internal.price_gemini_receipt(JSONB,TIMESTAMPTZ) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.require_fresh_gemini_assignment(p_model TEXT,p_operation TEXT,p_plan TEXT,p_policy BIGINT)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SET search_path = '' AS $$
DECLARE current_revision BIGINT; assigned BIGINT;
BEGIN
 IF p_model NOT IN ('gemini-2.5-flash','gemini-2.5-pro','gemini-3.8-flash','gemini-3.5-flash-lite') THEN RETURN; END IF;
 SELECT revision INTO current_revision FROM internal.gemini_routing_head WHERE singleton FOR SHARE;
 SELECT revision INTO assigned FROM internal.gemini_assignment_revisions
   WHERE operation=p_operation AND effective_plan=p_plan AND policy_version=p_policy AND requested_model=p_model;
 IF assigned IS NULL AND p_model IN ('gemini-2.5-flash','gemini-2.5-pro') THEN assigned:=0; END IF;
 IF assigned IS DISTINCT FROM current_revision OR NOT COALESCE(internal.gemini_dispatch_open(p_model,assigned),FALSE) THEN
   RAISE EXCEPTION 'ai_quota_unavailable' USING ERRCODE='P0001';
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_fresh_gemini_assignment(TEXT,TEXT,TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::regprocedure);
 anchor:='    IF reservation_found THEN' || E'\n        -- Explicitly refunded/failed attempts';
 IF pg_catalog.strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'Gemini quota source drift'; END IF;
 definition:=pg_catalog.replace(definition,anchor,
   -- A failed request is still admitted evidence. A new assignment requires a
   -- new user-created request identity, never rebinding this reservation.
   '    IF reservation_found AND reservation_row.model LIKE ''gemini-%'' AND (reservation_row.model IS DISTINCT FROM policy_row.model OR reservation_row.policy_version IS DISTINCT FROM policy_row.policy_version) THEN' || E'\n' ||
   '        RAISE EXCEPTION ''ai_quota_unavailable'' USING ERRCODE=''P0001'';' || E'\n    END IF;\n' ||
   '    PERFORM internal.require_fresh_gemini_assignment(policy_row.model,p_operation,resolved_plan,policy_row.policy_version);' || E'\n' ||
   '    IF reservation_found AND EXISTS(SELECT 1 FROM internal.gemini_invocation_receipts r WHERE r.reservation_id=reservation_row.id AND r.attempt_count=reservation_row.attempt_count AND r.state IN (''dispatch_intent'',''unknown'')) THEN' || E'\n' ||
   '        RAISE EXCEPTION ''ai_quota_unavailable'' USING ERRCODE=''P0001'';' || E'\n    END IF;\n' || anchor);
 EXECUTE definition;
 definition:=pg_catalog.pg_get_functiondef('public.record_gemini_invocation_receipt(uuid,uuid,jsonb)'::regprocedure);
 anchor:='    returned:=p_receipt->>''returnedModel'';';
 IF pg_catalog.strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'Gemini receipt source drift'; END IF;
 definition:=pg_catalog.replace(definition,anchor,
  '    IF NOT internal.gemini_response_receipt_valid(p_receipt) THEN RAISE EXCEPTION ''gemini_receipt_invalid'' USING ERRCODE=''22023''; END IF;' || E'\n' || anchor);
 anchor:='    RETURN TRUE;' || E'\nEND;';
 IF pg_catalog.strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'Gemini receipt settlement source drift'; END IF;
 definition:=pg_catalog.replace(definition,anchor,
  '    UPDATE internal.gemini_invocation_receipts AS receipt SET estimated_cost_microusd=price.cost,pricing_version=price.version,' || E'\n' ||
  '      settlement=CASE WHEN price.cost IS NULL THEN ''unresolved'' ELSE ''settled'' END' || E'\n' ||
  '      FROM internal.price_gemini_receipt(p_receipt,saved.dispatch_intent_at) AS price WHERE receipt.id=saved.id;' || E'\n' || anchor);
 EXECUTE definition;
END;
$migration$;

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;

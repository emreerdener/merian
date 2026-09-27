\set ON_ERROR_STOP on
BEGIN;
SELECT extensions.plan(8);

-- Service-only writes with real tariffs and deliberately incomplete/unknown units.
SET LOCAL ROLE service_role;
DO $$
DECLARE fixture RECORD;
BEGIN
  FOR fixture IN SELECT * FROM (VALUES
    ('legacy', 'gemini-2.5-flash', '{}'::JSONB, 100, 20, 30, 'text'),
    ('explicit', 'gemini-2.5-flash', '{"ai_provider":"gemini","ai_usage_contract":"gemini_token_counts_v1"}'::JSONB, 100, 20, 30, 'text'),
    ('collision', 'gemini-2.5-flash', '{"ai_provider":"future-provider"}'::JSONB, 100, 20, 30, 'text'),
    ('unknown_model', 'future-model', '{"ai_provider":"gemini"}'::JSONB, 100, 20, 30, 'text'),
    ('unknown_provider', 'gemini-2.5-flash', '{"ai_provider":null}'::JSONB, 100, 20, 30, 'text'),
    ('bad_contract', 'gemini-2.5-flash', '{"ai_usage_contract":"unreviewed_units"}'::JSONB, 100, 20, 30, 'text'),
    ('null_contract', 'gemini-2.5-flash', '{"ai_usage_contract":null}'::JSONB, 100, 20, 30, 'text'),
    ('missing_prompt', 'gemini-2.5-flash', '{}'::JSONB, NULL, 20, 30, 'text'),
    ('missing_output', 'gemini-2.5-flash', '{}'::JSONB, 100, 20, NULL, 'text'),
    ('invalid_cache', 'gemini-2.5-flash', '{}'::JSONB, 100, 101, 30, 'text'),
    ('unknown_modality', 'gemini-2.5-flash', '{}'::JSONB, 100, 20, 30, 'unknown')
  ) AS inputs(label, model, metadata, prompt, cached, candidate, modality) LOOP
    PERFORM public.record_ai_usage_event('provider_coverage_fixture', fixture.model,
      p_input_modality => fixture.modality, p_prompt_tokens => fixture.prompt,
      p_cached_tokens => fixture.cached, p_candidate_tokens => fixture.candidate, p_total_tokens => 130,
      p_source_type => fixture.label, p_source_id => gen_random_uuid(), p_metadata => fixture.metadata);
  END LOOP;
END;
$$;
SELECT public.record_ai_usage_event('coverage:a', 'b', p_total_tokens=>100);
SELECT public.record_ai_usage_event('coverage', 'a:b', p_total_tokens=>200);
RESET ROLE;
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM public.ai_usage_events WHERE operation='provider_coverage_fixture') <> 11
    OR EXISTS (SELECT 1 FROM public.ai_usage_events WHERE operation='provider_coverage_fixture'
      AND ((estimated_cost_microusd IS NOT NULL) IS DISTINCT FROM (source_type IN ('legacy','explicit'))
        OR (pricing_version IS NOT NULL) IS DISTINCT FROM (source_type IN ('legacy','explicit')))) THEN
    RAISE EXCEPTION 'unsupported or incomplete provider usage borrowed a tariff';
  END IF;
END;
$$;
SELECT extensions.pass('provider, usage contract, modality and required counts qualify pricing');

DO $$
DECLARE original public.ai_usage_events%ROWTYPE; replay UUID;
BEGIN
  SELECT * INTO STRICT original FROM public.ai_usage_events WHERE operation='provider_coverage_fixture' AND source_type='explicit';
  replay := public.record_ai_usage_event('provider_coverage_fixture','future-model',
    p_source_type=>original.source_type,p_source_id=>original.source_id,p_metadata=>'{"ai_provider":"future-provider"}');
  IF replay <> original.id OR (SELECT to_jsonb(event) FROM public.ai_usage_events event WHERE id=replay) <> to_jsonb(original) THEN
    RAISE EXCEPTION 'idempotent retry changed original accounting';
  END IF;
  BEGIN
    UPDATE public.ai_usage_events SET model='edited' WHERE id=original.id;
    RAISE EXCEPTION 'ledger permitted an arbitrary rewrite';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
SELECT extensions.pass('idempotent retries preserve append-only event identity, metadata and price');

INSERT INTO auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_anonymous)
VALUES ('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000761','authenticated','authenticated',
  'coverage-owner@naturebook.invalid',NOW(),'{"provider":"google","providers":["google"]}','{}',NOW(),NOW(),FALSE);
INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
VALUES ('00000000-0000-0000-0000-000000000761','00000000-0000-0000-0000-000000000761',
  '{"sub":"00000000-0000-0000-0000-000000000761","email":"coverage-owner@naturebook.invalid"}','google',NOW(),NOW());
INSERT INTO auth.sessions(id,user_id,created_at,updated_at,refreshed_at,aal,not_after)
VALUES ('00000000-0000-0000-0000-000000000762','00000000-0000-0000-0000-000000000761',NOW(),NOW(),NOW(),'aal2',NOW()+INTERVAL '1 day');
INSERT INTO internal.admin_memberships(user_id,role,is_active,created_by)
VALUES ('00000000-0000-0000-0000-000000000761','owner',TRUE,'00000000-0000-0000-0000-000000000761');
-- A prior backend payload must not be returned after the coverage contract changes.
INSERT INTO internal.admin_aggregate_cache(cache_key,payload,created_at) VALUES
  ('ai:30:provider_coverage_fixture:*:*:*:primary','{"legacy_cache":true}',NOW()),
  ('overview:30:UTC','{"legacy_cache":true}',NOW())
ON CONFLICT(cache_key) DO UPDATE SET payload=EXCLUDED.payload,created_at=EXCLUDED.created_at;
SELECT set_config('test.coverage_expected', (SELECT jsonb_build_object('events',COUNT(*),
  'priced_events',COUNT(*) FILTER (WHERE estimated_cost_microusd IS NOT NULL),
  'unpriced_events',COUNT(*) FILTER (WHERE estimated_cost_microusd IS NULL))::TEXT
  FROM public.ai_usage_events WHERE occurred_at>=NOW()-INTERVAL '30 days'), TRUE);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000761","role":"authenticated","aal":"aal2","session_id":"00000000-0000-0000-0000-000000000762"}',TRUE);
SELECT public.admin_begin_session();
DO $$
DECLARE result JSONB; groups JSONB;
BEGIN
  result := public.admin_ai_usage_summary(p_operation=>'provider_coverage_fixture');
  IF (result->>'events')::INT <> 11 OR (result->>'priced_events')::INT <> 2 OR (result->>'unpriced_events')::INT <> 9
     OR (result->>'estimated_cost_microusd')::BIGINT <= 0 OR result ? 'legacy_cache'
     OR result->>'provider_groups_truncated' <> 'false' THEN
    RAISE EXCEPTION 'summary omitted pricing coverage or served legacy cache';
  END IF;
  IF (SELECT SUM((day->>'priced_events')::INT) FROM jsonb_array_elements(result->'daily') day) <> 2
    OR (SELECT SUM((day->>'unpriced_events')::INT) FROM jsonb_array_elements(result->'daily') day) <> 9 THEN
    RAISE EXCEPTION 'daily coverage differs from total coverage';
  END IF;
  groups := result->'provider_usage';
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(groups) g WHERE g->>'provider'='future-provider'
    AND g->>'model'='gemini-2.5-flash' AND g->>'attribution'='execution_metadata'
    AND g->>'priced_events'='0' AND g->>'unpriced_events'='1')
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(groups) g WHERE g->>'provider'='gemini' AND g->>'attribution'='legacy_model')
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(groups) g WHERE g->>'provider'='unknown') THEN
    RAISE EXCEPTION 'provider grouping concealed a model collision or legacy attribution';
  END IF;
  IF public.admin_ai_usage_summary(p_operation=>'provider_coverage_fixture') <> result THEN
    RAISE EXCEPTION 'new aggregate cache lost coverage';
  END IF;
END;
$$;
SELECT extensions.pass('actual authorized summary returns total, daily and provider coverage through new cache');
DO $$
DECLARE result JSONB; expected JSONB:=current_setting('test.coverage_expected')::JSONB; field TEXT;
BEGIN
  result:=public.admin_get_overview();
  FOREACH field IN ARRAY ARRAY['events','priced_events','unpriced_events'] LOOP
    IF result#>>ARRAY['ai',field] IS DISTINCT FROM expected->>field THEN
      RAISE EXCEPTION 'overview coverage differs for %',field;
    END IF;
    IF (SELECT COALESCE(SUM((day->>field)::BIGINT),0) FROM jsonb_array_elements(result->'daily') day) <> (expected->>field)::BIGINT THEN
      RAISE EXCEPTION 'overview daily coverage differs for %',field;
    END IF;
    IF result#>>ARRAY['previous_period',field] IS NULL THEN RAISE EXCEPTION 'previous coverage missing'; END IF;
  END LOOP;
  IF result ? 'legacy_cache' THEN RAISE EXCEPTION 'old overview cache served'; END IF;
END;
$$;
SELECT extensions.pass('overview total, previous period and daily estimates expose pricing coverage');
DO $$
DECLARE first JSONB; second JSONB; all_events JSONB; literal_star JSONB;
BEGIN
  first:=public.admin_ai_usage_summary(p_operation=>'coverage:a',p_model=>'b');
  second:=public.admin_ai_usage_summary(p_operation=>'coverage',p_model=>'a:b');
  IF first->>'total_tokens'<>'100' OR second->>'total_tokens'<>'200' THEN
    RAISE EXCEPTION 'distinct filter tuples collided in cache';
  END IF;
  all_events:=public.admin_ai_usage_summary();
  literal_star:=public.admin_ai_usage_summary(p_operation=>'*');
  IF (all_events->>'events')::INT=0 OR literal_star->>'events'<>'0' THEN
    RAISE EXCEPTION 'SQL-null filter collided with literal star';
  END IF;
END;
$$;
SELECT extensions.pass('structured cache keys distinguish delimiters and literal stars from missing filters');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT public.record_ai_usage_event('provider_groups_fixture', 'synthetic-model-' || n::TEXT,
  p_metadata=>'{"ai_provider":"synthetic-provider"}') FROM generate_series(1,52) n;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
DECLARE result JSONB;
BEGIN
  result:=public.admin_ai_usage_summary(p_operation=>'provider_groups_fixture',p_refresh=>TRUE);
  IF jsonb_array_length(result->'provider_usage')<>50 OR result->>'provider_groups_truncated'<>'true'
    OR result->>'events'<>'52' OR result->>'priced_events'<>'0' OR result->>'unpriced_events'<>'52'
    OR result->>'estimated_cost_microusd'<>'0' THEN RAISE EXCEPTION 'provider aggregation is unbounded or totals lost omitted groups'; END IF;
END;
$$;
SELECT extensions.pass('provider groups are bounded while totals and unknown pricing include all groups');

DO $$
BEGIN
  BEGIN PERFORM 1 FROM public.ai_usage_events; RAISE EXCEPTION 'client read raw ledger'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.record_ai_usage_event('unauthorized','gemini-2.5-flash'); RAISE EXCEPTION 'client wrote ledger'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
SELECT extensions.pass('authenticated users cannot read or write the underlying ledger');
RESET ROLE;
UPDATE internal.admin_memberships SET is_active=FALSE WHERE user_id='00000000-0000-0000-0000-000000000761';
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN PERFORM public.admin_ai_usage_summary(p_operation=>'provider_coverage_fixture'); RAISE EXCEPTION 'revoked admin used cached summary'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.admin_get_overview(); RAISE EXCEPTION 'revoked admin used cached overview'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN PERFORM public.record_ai_usage_event('unauthorized','gemini-2.5-flash'); RAISE EXCEPTION 'anon wrote ledger'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.admin_ai_usage_summary(); RAISE EXCEPTION 'anon read summary'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;
SELECT extensions.pass('authorization still precedes cached aggregates and anonymous access is denied');
SELECT * FROM extensions.finish();
ROLLBACK;

\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(11);

-- BEGIN ACCOUNTING SYNTHETIC HELPERS
CREATE FUNCTION pg_temp.seed_invocation(p_openai BOOLEAN DEFAULT FALSE)
RETURNS TABLE(reservation UUID, owner_id UUID, token UUID, scan UUID)
LANGUAGE plpgsql AS $function$
BEGIN
    reservation := gen_random_uuid(); owner_id := gen_random_uuid(); token := gen_random_uuid(); scan := gen_random_uuid();
    INSERT INTO auth.users(id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
        VALUES (owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}');
    INSERT INTO public.users(id,email,public_username,public_author_name,public_identity_source)
        VALUES(owner_id,owner_id::TEXT || '@example.invalid','account_' || left(replace(owner_id::TEXT,'-',''),16),'Synthetic accounting','alias')
        ON CONFLICT(id) DO NOTHING;
    INSERT INTO internal.ai_quota_reservations (id,user_id,operation,request_id,lease_token,
        model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id)
        VALUES(reservation,owner_id,'scan_identification',scan,token,'gemini-2.5-flash','free','free','free',FALSE,1,1,scan);
    INSERT INTO internal.identification_provider_attempts (reservation_id,attempt_count,operation,effective_plan,model,policy_version,
        provider,binding,processor_permission,input_profile,provider_model,minimum_identification_protocol,accepted_identification_protocol)
        VALUES(reservation,1,'scan_identification','free','gemini-2.5-flash',1,
            CASE WHEN p_openai THEN 'openai' ELSE 'gemini' END,
            CASE WHEN p_openai THEN 'openai_photo_v1' ELSE 'gemini_baseline_v1' END,
            CASE WHEN p_openai THEN 'openai' ELSE 'google_gemini' END,'multimodal_photo_v1',
            CASE WHEN p_openai THEN 'gpt-6-sol' ELSE NULL END,CASE WHEN p_openai THEN 4 ELSE 0 END,4);
    RETURN NEXT;
END;
$function$;

CREATE FUNCTION pg_temp.commit_invocation(p_reservation UUID, p_owner UUID, p_token UUID, p_attempt INTEGER)
RETURNS TABLE(invocation_id UUID, may_dispatch BOOLEAN) LANGUAGE sql AS $function$
    SELECT result.* FROM internal.identification_provider_attempts, LATERAL public.commit_identification_invocation(p_reservation,p_owner,p_token,p_attempt,
        jsonb_build_object('version',CASE provider WHEN 'openai' THEN 2 ELSE 1 END,
        'provider',provider,'binding',binding,'model',coalesce(provider_model,model),'variant','multimodal',
        'operation',operation,'policy_version',policy_version,'prompt','identify_vision_v1',
        'schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,
        'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,'generation',
        CASE provider WHEN 'openai' THEN '{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}'::JSONB
          ELSE '{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB END))
    AS result WHERE reservation_id=p_reservation AND attempt_count=p_attempt;
$function$;

-- END ACCOUNTING SYNTHETIC HELPERS

DO $test$
DECLARE f RECORD; first RECORD; duplicate RECORD; event UUID; denied BOOLEAN := FALSE;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO first FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    SELECT * INTO duplicate FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    IF NOT first.may_dispatch OR duplicate.may_dispatch OR first.invocation_id <> duplicate.invocation_id
      OR (SELECT state FROM internal.ai_quota_reservations WHERE id=f.reservation) <> 'committed' THEN
        RAISE EXCEPTION 'duplicate invocation or non-atomic commit'; END IF;
    BEGIN
        PERFORM pg_temp.commit_invocation(f.reservation,gen_random_uuid(),f.token,1);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'foreign owner admitted'; END IF;
    event := public.complete_identification_invocation(first.invocation_id,f.owner_id,f.token,'refusal',
        '{"input_tokens":100,"cached_tokens":20,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}');
    IF public.complete_identification_invocation(first.invocation_id,f.owner_id,f.token,'draft','{}') <> event
      OR (SELECT outcome FROM public.ai_usage_events WHERE id=event) <> 'refusal'
      OR (SELECT COUNT(*) FROM public.ai_usage_events WHERE source_id=first.invocation_id) <> 1 THEN
        RAISE EXCEPTION 'completion is not immutable and idempotent'; END IF;
END;
$test$;
SELECT extensions.pass('atomic commit, duplicate fence, foreign owner rejection and immutable completion');

DO $test$
DECLARE f RECORD; started RECORD; event RECORD; late UUID;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    UPDATE internal.identification_invocations SET occurred_at=clock_timestamp()-INTERVAL '6 minutes' WHERE id=started.invocation_id;
    PERFORM internal.reconcile_identification_usage(1000);
    SELECT * INTO STRICT event FROM public.ai_usage_events WHERE source_id=started.invocation_id;
    late := public.complete_identification_invocation(started.invocation_id,f.owner_id,f.token,'draft','{"input_tokens":100,"candidate_tokens":40}');
    IF late <> event.id OR event.outcome <> 'unknown' OR event.estimated_cost_microusd IS NOT NULL
      OR event.prompt_tokens IS NOT NULL OR event.occurred_at > clock_timestamp()-INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'unknown reconciliation fabricated or revised usage'; END IF;
    DELETE FROM internal.ai_quota_reservations WHERE id=f.reservation;
    IF NOT EXISTS (SELECT 1 FROM internal.identification_invocations WHERE id=started.invocation_id)
        THEN RAISE EXCEPTION 'accounting cascaded with quota'; END IF;
END;
$test$;
SELECT extensions.pass('crash recovery appends unknown at original time, late reports do not reprice, quota pruning retains evidence');

DO $test$
DECLARE f RECORD; started RECORD; event UUID; version TEXT;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation(TRUE);
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    SELECT native_price->>'version' INTO version FROM internal.identification_invocations WHERE id=started.invocation_id;
    IF version IS NULL THEN RAISE EXCEPTION 'native price not snapshotted'; END IF;
    UPDATE internal.ai_native_token_prices SET input_usd_per_million=999;
    event := public.complete_identification_invocation(started.invocation_id,f.owner_id,f.token,'invalid_output',
        '{"input_tokens":100,"cached_tokens":20,"cache_write_tokens":5,"output_tokens":40,"candidate_tokens":30,"thinking_tokens":10,"tool_tokens":0,"total_tokens":140,"service_tier":"default"}');
    IF (SELECT estimated_cost_microusd FROM public.ai_usage_events WHERE id=event) <> 567
        OR (SELECT pricing_version FROM public.ai_usage_events WHERE id=event) <> version
        OR (SELECT outcome FROM public.ai_usage_events WHERE id=event) <> 'error' THEN
        RAISE EXCEPTION 'native usage double counted, repriced or omitted on failure'; END IF;
    UPDATE internal.ai_native_token_prices SET input_usd_per_million=2;
END;
$test$;
SELECT extensions.pass('native pricing uses frozen tariff, cache writes replace input and reasoning is not charged twice');

DO $test$
DECLARE f RECORD; started RECORD; event UUID; bad JSONB;
BEGIN
    FOREACH bad IN ARRAY ARRAY[
        '{}'::JSONB,
        '{"input_tokens":100,"cached_tokens":80,"cache_write_tokens":30,"output_tokens":40,"tool_tokens":0,"service_tier":"default"}'::JSONB,
        '{"input_tokens":272001,"cached_tokens":0,"cache_write_tokens":0,"output_tokens":40,"tool_tokens":0,"service_tier":"default"}'::JSONB,
        '{"input_tokens":100,"cached_tokens":0,"cache_write_tokens":0,"output_tokens":40,"tool_tokens":0,"service_tier":"flex"}'::JSONB,
        '{"input_tokens":100,"cached_tokens":0,"cache_write_tokens":0,"output_tokens":40,"tool_tokens":1,"service_tier":"default"}'::JSONB
    ] LOOP
        SELECT * INTO f FROM pg_temp.seed_invocation(TRUE);
        SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
        event := public.complete_identification_invocation(started.invocation_id,f.owner_id,f.token,'draft',bad);
        IF (SELECT estimated_cost_microusd FROM public.ai_usage_events WHERE id=event) IS NOT NULL
            THEN RAISE EXCEPTION 'unsupported or missing native units priced'; END IF;
    END LOOP;
END;
$test$;
SELECT extensions.pass('missing and inconsistent usage, unknown tier, long context and tools remain unpriced');

DO $test$
DECLARE f RECORD; started RECORD; denied BOOLEAN := FALSE; boundary TIMESTAMPTZ := clock_timestamp()+INTERVAL '1 hour';
BEGIN
    BEGIN
        INSERT INTO internal.ai_native_token_prices SELECT gen_random_uuid(), provider, model, usage_contract, service_tier,
            endpoint_profile,input_modality,max_input_tokens,input_usd_per_million,cached_usd_per_million,
            cache_write_usd_per_million,output_usd_per_million,effective_from,effective_to,'overlap-test'
            FROM internal.ai_native_token_prices;
    EXCEPTION WHEN exclusion_violation THEN denied:=TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'overlapping tariffs accepted'; END IF;
    UPDATE internal.ai_native_token_prices SET effective_to=boundary;
    INSERT INTO internal.ai_native_token_prices SELECT gen_random_uuid(),provider,model,usage_contract,service_tier,
        endpoint_profile,input_modality,max_input_tokens,input_usd_per_million,cached_usd_per_million,
        cache_write_usd_per_million,output_usd_per_million,boundary,NULL,'next-test'
        FROM internal.ai_native_token_prices;
    IF (SELECT count(*) FROM internal.ai_native_token_prices WHERE effective_from<=boundary AND (effective_to IS NULL OR effective_to>boundary)) <> 1
        THEN RAISE EXCEPTION 'tariff boundary not half open'; END IF;
END;
$test$;
SELECT extensions.pass('tariff ranges cannot overlap and effective boundary is half open');

DO $test$
DECLARE f RECORD; started RECORD; event UUID;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    event := public.complete_identification_invocation(started.invocation_id,f.owner_id,f.token,'draft',
        '{"input_tokens":100,"cached_tokens":20,"candidate_tokens":40,"total_tokens":140}');
    INSERT INTO public.scans(id,user_id,image_storage_urls,is_biological_subject,ai_confidence_score,llm_total_tokens,llm_usage_metadata)
        VALUES(f.scan,f.owner_id,'{}',FALSE,0,140,'{"accounting_contract":"identification_invocation_v1"}');
    UPDATE internal.identification_invocations SET occurred_at=clock_timestamp()-INTERVAL '31 days' WHERE id=started.invocation_id;
    PERFORM internal.reconcile_identification_usage();
    UPDATE public.scans SET llm_total_tokens=140 WHERE id=f.scan;
    IF (SELECT COUNT(*) FROM public.ai_usage_events WHERE scan_id=f.scan) <> 1
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE id=started.invocation_id) THEN
        RAISE EXCEPTION 'scan trigger double counted or completed witness not pruned'; END IF;
END;
$test$;
SELECT extensions.pass('saved scan and later updates never duplicate accounting, including after witness retention');

DO $test$
DECLARE f RECORD; started RECORD; event RECORD;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    DELETE FROM public.users WHERE id=f.owner_id;
    SELECT * INTO STRICT event FROM public.ai_usage_events WHERE id=(SELECT event_id FROM internal.identification_invocations WHERE id=started.invocation_id);
    IF event.user_id IS NOT NULL OR event.scan_id IS NOT NULL OR event.source_id IS NOT NULL OR event.outcome<>'unknown'
      OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE id=started.invocation_id
        AND (user_id IS NOT NULL OR scan_id IS NOT NULL OR reservation_id IS NOT NULL OR lease_sha256 IS NOT NULL)) THEN
        RAISE EXCEPTION 'deletion lost accounting or retained identifying linkage'; END IF;
END;
$test$;
SELECT extensions.pass('account deletion settles pending uncertainty then anonymizes every identifying link');

DO $test$
DECLARE role_name TEXT; signature TEXT;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        IF has_table_privilege(role_name,'internal.identification_invocations','SELECT,INSERT,UPDATE,DELETE')
            OR has_table_privilege(role_name,'internal.ai_native_token_prices','SELECT,INSERT,UPDATE,DELETE')
            THEN RAISE EXCEPTION 'private accounting table accessible'; END IF;
    END LOOP;
    FOREACH signature IN ARRAY ARRAY['public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)',
        'public.complete_identification_invocation(uuid,uuid,uuid,text,jsonb)'] LOOP
        IF has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE')
          OR NOT has_function_privilege('service_role',signature,'EXECUTE')
          OR NOT EXISTS (SELECT 1 FROM internal.privileged_routine_grants WHERE routine_signature=signature AND privileged_routine_grants.role_name='service_role')
          THEN RAISE EXCEPTION 'accounting RPC grants not exact'; END IF;
    END LOOP;
END;
$test$;
SELECT extensions.pass('private tables and exact service-only RPC grants match allowlist');
DO $test$
DECLARE f RECORD; denied BOOLEAN := FALSE;
BEGIN
    IF (SELECT extnamespace FROM pg_extension WHERE extname='btree_gist') <> 'extensions'::regnamespace THEN
        RAISE EXCEPTION 'btree_gist schema drift'; END IF;
    SELECT * INTO f FROM pg_temp.seed_invocation(TRUE);
    DELETE FROM internal.ai_native_token_prices;
    BEGIN
        PERFORM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied:=TRUE; END;
    IF NOT denied OR (SELECT state FROM internal.ai_quota_reservations WHERE id=f.reservation) <> 'reserved'
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE reservation_id=f.reservation) THEN
        RAISE EXCEPTION 'missing price allowed dispatch or charged quota'; END IF;
END;
$test$;
SELECT extensions.pass('missing effective OpenAI tariff fails before quota commitment');
DO $test$
DECLARE f RECORD; started RECORD; provenance JSONB; denied BOOLEAN;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    SELECT i.provenance INTO provenance FROM internal.identification_invocations i WHERE id=started.invocation_id;
    SELECT * INTO f FROM pg_temp.seed_invocation();
    denied := FALSE;
    BEGIN
        PERFORM public.commit_identification_invocation(f.reservation,f.owner_id,gen_random_uuid(),1,provenance);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'stale lease admitted'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.commit_identification_invocation(f.reservation,f.owner_id,f.token,2,provenance);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'stale attempt admitted'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.commit_identification_invocation(f.reservation,f.owner_id,f.token,1,provenance || '{"policy_version":999}'::JSONB);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE; END;
    IF NOT denied OR (SELECT state FROM internal.ai_quota_reservations WHERE id=f.reservation) <> 'reserved'
        THEN RAISE EXCEPTION 'mismatched provenance admitted or quota consumed'; END IF;
END;
$test$;
SELECT extensions.pass('stale leases, attempt numbers and mismatched execution provenance cannot dispatch');

DO $test$
DECLARE source RECORD; target RECORD; started RECORD; event UUID;
BEGIN
    SELECT * INTO source FROM pg_temp.seed_invocation();
    SELECT * INTO target FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(source.reservation,source.owner_id,source.token,1);
    PERFORM internal.perform_ghost_profile_merge(source.owner_id,target.owner_id);
    IF (SELECT user_id FROM internal.identification_invocations WHERE id=started.invocation_id) IS DISTINCT FROM target.owner_id
        THEN RAISE EXCEPTION 'ghost merge did not reparent witness'; END IF;
    event := public.complete_identification_invocation(started.invocation_id,target.owner_id,source.token,'draft','{}');
    IF (SELECT user_id FROM public.ai_usage_events WHERE id=event) IS DISTINCT FROM target.owner_id
        THEN RAISE EXCEPTION 'ghost merge lost usage ownership'; END IF;
END;
$test$;
SELECT extensions.pass('controlled ghost merge reparents pending accounting before old-profile deletion');

SELECT * FROM extensions.finish();
ROLLBACK;

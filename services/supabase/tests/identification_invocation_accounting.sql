\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

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

-- Replace only the estimator body in this rollback fixture, preserving its OID
-- so cached callers are observed too. The delegate is the exact original body.
CREATE TEMP TABLE accounting_estimator_original(definition TEXT);
INSERT INTO accounting_estimator_original SELECT pg_get_functiondef(
 'internal.estimate_ai_cost_microusd(text,text,timestamptz,bigint,bigint,bigint,bigint,bigint)'::regprocedure);
DO $instrument$
BEGIN
 EXECUTE replace((SELECT definition FROM accounting_estimator_original),
  'FUNCTION internal.estimate_ai_cost_microusd(', 'FUNCTION pg_temp.accounting_original_estimator(');
END;
$instrument$;
CREATE TEMP TABLE accounting_price_calls(cost BIGINT, version TEXT);
CREATE OR REPLACE FUNCTION internal.estimate_ai_cost_microusd(
 p_model TEXT,p_modality TEXT,p_occurred_at TIMESTAMPTZ,p_prompt BIGINT,p_cached BIGINT,
 p_candidate BIGINT,p_thinking BIGINT,p_tool BIGINT)
RETURNS TABLE(cost_microusd BIGINT,pricing_version TEXT)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $instrument$
DECLARE result RECORD;
BEGIN
 SELECT * INTO result FROM pg_temp.accounting_original_estimator(
  p_model,p_modality,p_occurred_at,p_prompt,p_cached,p_candidate,p_thinking,p_tool);
 INSERT INTO pg_temp.accounting_price_calls VALUES(result.cost_microusd,result.pricing_version);
 RETURN QUERY SELECT result.cost_microusd,result.pricing_version;
END;
$instrument$;

-- Transaction-local observation only: full synthetic images never leave this
-- rollback fixture. Observe both attempted and effective rows for ON CONFLICT.
CREATE TEMP TABLE accounting_observations(relation_name TEXT, timing TEXT, old_image JSONB, new_image JSONB);
CREATE FUNCTION pg_temp.observe_accounting_write() RETURNS TRIGGER LANGUAGE plpgsql AS $function$
BEGIN
    INSERT INTO accounting_observations VALUES(TG_TABLE_NAME,TG_WHEN,
        CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) END,to_jsonb(NEW));
    RETURN NEW;
END;
$function$;
CREATE TRIGGER accounting_test_before BEFORE INSERT ON public.ai_usage_events
 FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_accounting_write();
CREATE TRIGGER accounting_test_after AFTER INSERT ON public.ai_usage_events
 FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_accounting_write();
CREATE TRIGGER accounting_test_link AFTER UPDATE ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION pg_temp.observe_accounting_write();

DO $test$
DECLARE f RECORD; started RECORD; event UUID; row_image public.ai_usage_events; invocation_image JSONB;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    SELECT to_jsonb(i) INTO invocation_image FROM internal.identification_invocations i WHERE id=started.invocation_id;
    DELETE FROM accounting_observations;
    DELETE FROM accounting_price_calls;
    event:=public.complete_identification_invocation(started.invocation_id,f.owner_id,f.token,'refusal',
        '{"input_tokens":100,"cached_tokens":20,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}');
    SELECT * INTO STRICT row_image FROM public.ai_usage_events WHERE id=event;
    IF (SELECT count(*) FROM accounting_price_calls)<>1
        OR row_image.estimated_cost_microusd IS DISTINCT FROM (SELECT cost FROM accounting_price_calls)
        OR row_image.pricing_version IS DISTINCT FROM (SELECT version FROM accounting_price_calls)
        OR row_image.id IS NULL OR row_image.created_at IS DISTINCT FROM now()
        OR row_image.occurred_at IS DISTINCT FROM (invocation_image->>'occurred_at')::TIMESTAMPTZ
        OR row_image.conversation_id IS NOT NULL OR row_image.message_id IS NOT NULL
        OR row_image.is_backfilled IS DISTINCT FROM FALSE OR row_image.coverage_scope IS DISTINCT FROM 'complete'
        OR row_image.user_id IS DISTINCT FROM f.owner_id OR row_image.scan_id IS DISTINCT FROM f.scan
        OR row_image.source_id IS DISTINCT FROM started.invocation_id OR row_image.outcome IS DISTINCT FROM 'refusal'
        OR row_image.prompt_tokens IS DISTINCT FROM 100 OR row_image.cached_tokens IS DISTINCT FROM 20
        OR row_image.candidate_tokens IS DISTINCT FROM 30 OR row_image.thinking_tokens IS DISTINCT FROM 10
        OR row_image.total_tokens IS DISTINCT FROM 140
        OR (SELECT count(*) FROM accounting_observations WHERE relation_name='ai_usage_events'
            AND new_image=to_jsonb(row_image) AND timing IN ('BEFORE','AFTER'))<>2
        OR (SELECT count(*) FROM accounting_observations WHERE relation_name='identification_invocations'
            AND old_image=invocation_image AND new_image=invocation_image||jsonb_build_object('event_id',event))<>1
        OR (SELECT count(*) FROM accounting_observations)<>3 THEN
        RAISE EXCEPTION 'candidate defaults, full insert image or invocation-only linkage drifted';
    END IF;
    DELETE FROM accounting_observations;
    DELETE FROM accounting_price_calls;
    -- Invalid input must not even reach derivation on an accounted replay.
    IF internal.complete_identification_usage(started.invocation_id,NULL,'null') IS DISTINCT FROM event
        OR EXISTS(SELECT 1 FROM accounting_observations)
        OR EXISTS(SELECT 1 FROM accounting_price_calls)
        OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=event) IS DISTINCT FROM to_jsonb(row_image) THEN
        RAISE EXCEPTION 'accounted replay validated input or wrote accounting rows';
    END IF;
END;
$test$;
SELECT extensions.pass('full candidate image and six defaults persist once; invalid accounted replay performs zero writes');

DO $test$
DECLARE f RECORD; started RECORD; invocation internal.identification_invocations;
 winner public.ai_usage_events; event UUID; attempt JSONB;
BEGIN
    SELECT * INTO f FROM pg_temp.seed_invocation();
    SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
    SELECT * INTO STRICT invocation FROM internal.identification_invocations WHERE id=started.invocation_id;
    -- Model an already-inserted winner without its link; a conflicting report
    -- must link that actual winner, not overwrite it with the new candidate.
    winner:=internal.prepare_identification_usage_event(invocation,'unknown_execution','{}');
    INSERT INTO public.ai_usage_events SELECT (winner).*;
    DELETE FROM accounting_observations;
    DELETE FROM accounting_price_calls;
    event:=internal.complete_identification_usage(invocation.id,'draft','{"input_tokens":101,"candidate_tokens":37}');
    SELECT new_image INTO STRICT attempt FROM accounting_observations WHERE relation_name='ai_usage_events' AND timing='BEFORE';
    IF (SELECT count(*) FROM accounting_price_calls)<>1
        OR event IS DISTINCT FROM winner.id
        OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=event) IS DISTINCT FROM to_jsonb(winner)
        OR (SELECT event_id FROM internal.identification_invocations WHERE id=invocation.id) IS DISTINCT FROM winner.id
        OR (attempt->>'id')::UUID=winner.id OR attempt->>'outcome' IS DISTINCT FROM 'success'
        OR (attempt->>'prompt_tokens')::BIGINT IS DISTINCT FROM 101
        OR (attempt->>'candidate_tokens')::BIGINT IS DISTINCT FROM 37
        OR EXISTS(SELECT 1 FROM accounting_observations WHERE relation_name='ai_usage_events' AND timing='AFTER')
        OR (SELECT count(*) FROM accounting_observations WHERE relation_name='identification_invocations'
            AND old_image=to_jsonb(invocation) AND new_image=to_jsonb(invocation)||jsonb_build_object('event_id',winner.id))<>1
        OR (SELECT count(*) FROM accounting_observations)<>2 THEN
        RAISE EXCEPTION 'conflict lost attempted image, changed winner or linked candidate';
    END IF;
END;
$test$;
SELECT extensions.pass('conflict observes attempted BEFORE without AFTER insert and preserves the actual winner and linkage');
-- Report mechanics integrate the actual accounting writer, but classification
-- is injected and no original admission authority is claimed. All trigger
-- installation and synthetic rows roll back; report observers are installed; public report admission stays closed.
CREATE FUNCTION pg_temp.report_suppress() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION pg_temp.report_mutate() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.metadata:=NEW.metadata||'{"changed":true}'::JSONB; RETURN NEW; END $$;
CREATE FUNCTION pg_temp.report_case(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $case$
DECLARE f RECORD; started RECORD; original internal.identification_invocations;
 candidate public.ai_usage_events; stage internal.initial_consuming_staging; event UUID;
 receipt UUID:=gen_random_uuid();
BEGIN
 BEGIN
  SELECT * INTO f FROM pg_temp.seed_invocation();
  SELECT * INTO started FROM pg_temp.commit_invocation(f.reservation,f.owner_id,f.token,1);
  ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
  UPDATE internal.identification_invocations SET is_initial_analysis=TRUE,initial_admission_receipt_id=receipt WHERE id=started.invocation_id;
  ALTER TABLE internal.identification_invocations ENABLE TRIGGER a00_initial_invocation_authority;
  SELECT * INTO STRICT original FROM internal.identification_invocations WHERE id=started.invocation_id FOR UPDATE;
  IF mode IN ('winner','suppressed_winner','mutated_winner') THEN
   candidate:=internal.prepare_identification_usage_event(original,'unknown_execution','{}');
   INSERT INTO public.ai_usage_events SELECT (candidate).*;
  END IF;
  IF mode='immediate' THEN SET CONSTRAINTS ALL IMMEDIATE; END IF;
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
   admission_receipt_digest,reservation_id,invocation_id,expected_writes,report_invocation)
   VALUES(pg_current_xact_id(),original.scan_id,original.user_id,'report',receipt,repeat('a',64),original.reservation_id,
    original.id,'[]',to_jsonb(original));
  IF mode='suppressed' OR mode='suppressed_winner' THEN
   CREATE TRIGGER zzzz_report_suppress BEFORE INSERT ON public.ai_usage_events FOR EACH ROW EXECUTE FUNCTION pg_temp.report_suppress();
  ELSIF mode='mutated' THEN
   CREATE TRIGGER zzzz_report_mutate BEFORE INSERT ON public.ai_usage_events FOR EACH ROW EXECUTE FUNCTION pg_temp.report_mutate();
  ELSIF mode='link_suppressed' THEN
   CREATE TRIGGER zzzz_report_suppress BEFORE UPDATE ON internal.identification_invocations FOR EACH ROW EXECUTE FUNCTION pg_temp.report_suppress();
  ELSIF mode='missing_before' THEN ALTER TABLE public.ai_usage_events DISABLE TRIGGER s0_report_row_before;
  ELSIF mode='missing_after' THEN ALTER TABLE public.ai_usage_events DISABLE TRIGGER s0_report_row_after;
  ELSIF mode='direct_winner' THEN UPDATE internal.initial_consuming_staging SET report_winner='{}';
  ELSIF mode='original_changed' THEN UPDATE internal.initial_consuming_staging SET report_invocation=report_invocation||'{"model":"changed"}';
  END IF;
  DELETE FROM accounting_price_calls;
  event:=internal.complete_identification_usage(original.id,'draft','{"input_tokens":101,"candidate_tokens":37}');
  SELECT * INTO STRICT stage FROM internal.initial_consuming_staging;
  IF NOT stage.sealed OR stage.report_winner IS DISTINCT FROM (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE id=event)
   OR stage.report_invocation IS DISTINCT FROM to_jsonb(original)
   OR (stage.expected_writes#>>'{0,0,new,prompt_tokens}')::BIGINT IS DISTINCT FROM 101
   OR (SELECT count(*) FROM accounting_price_calls)<>1
   OR stage.report_inserted IS DISTINCT FROM (mode NOT IN ('winner','suppressed_winner','mutated_winner')) THEN
   RAISE EXCEPTION 'report candidate, winner, pricing count or terminal mismatch'; END IF;
  IF mode='extra_statement' THEN UPDATE internal.identification_invocations SET event_id=event WHERE id=original.id; END IF;
  IF mode='protected_winner' THEN UPDATE public.ai_usage_events SET metadata=metadata||'{"changed":true}' WHERE id=event; END IF;
  -- Deliberate fault injection bypasses only append-only protection; this
  -- separate case reaches the report terminal validator. DDL rolls back.
  IF mode IN ('mutated_winner','mutated_after_delete') THEN
   ALTER TABLE public.ai_usage_events DISABLE TRIGGER trg_protect_ai_usage_events;
  END IF;
  IF mode='mutated_winner' THEN UPDATE public.ai_usage_events SET metadata=metadata||'{"changed":true}' WHERE id=event; END IF;
  DELETE FROM internal.initial_consuming_staging;
  IF mode='mutated_after_delete' THEN UPDATE public.ai_usage_events SET metadata=metadata||'{"changed":true}' WHERE id=event; END IF;
  IF mode='link_after_delete' THEN
   ALTER TABLE internal.identification_invocations DISABLE TRIGGER a00_initial_invocation_authority;
   UPDATE internal.identification_invocations SET event_id=NULL WHERE id=original.id;
  END IF;
  IF mode='reuse' THEN
   INSERT INTO internal.initial_consuming_staging SELECT (stage).*;
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'success rollback' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN 'ok';
 END;
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END;
$case$;
SELECT extensions.is(pg_temp.report_case(mode),expected,mode) FROM (VALUES
 ('inserted','ok'),('winner','ok'),('suppressed_winner','ok'),
 ('suppressed','55000:initial_analysis_report_winner_missing'),
 ('mutated','55000:initial_analysis_consuming_row_invalid'),
 ('link_suppressed','55000:initial_analysis_consuming_stage_incomplete'),
 ('missing_before','55000:initial_analysis_consuming_row_invalid'),
 ('missing_after','55000:initial_analysis_report_resolution_invalid'),
 ('direct_winner','55000:initial_analysis_report_attachment_invalid'),
 ('original_changed','55000:initial_analysis_report_attachment_invalid'),
 ('extra_statement','55000:initial_analysis_consuming_statement_invalid'),
 ('protected_winner','42501:AI usage events are append-only.'),
 ('mutated_winner','55000:initial_analysis_report_incomplete'),
 ('mutated_after_delete','55000:initial_analysis_report_incomplete'),
 ('link_after_delete','55000:initial_analysis_report_incomplete'),
 ('immediate','55000:initial_analysis_consuming_stage_incomplete'),
 ('reuse','55000:initial_analysis_consuming_stage_invalid')
) cases(mode,expected);
DROP TRIGGER accounting_test_before ON public.ai_usage_events;
DROP TRIGGER accounting_test_after ON public.ai_usage_events;
DROP TRIGGER accounting_test_link ON internal.identification_invocations;
DO $instrument$
BEGIN EXECUTE (SELECT definition FROM accounting_estimator_original); END;
$instrument$;


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
        IF has_function_privilege(role_name,'internal.prepare_identification_usage_event(internal.identification_invocations,text,jsonb)','EXECUTE')
            OR has_table_privilege(role_name,'internal.identification_invocations','SELECT,INSERT,UPDATE,DELETE')
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

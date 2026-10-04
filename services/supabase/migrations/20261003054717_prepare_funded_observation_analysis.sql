SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN admission_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- One settlement implementation for existing scans and new child analyses.
-- This private helper is never an admission/completion proof by itself.
CREATE FUNCTION internal.settle_complimentary_analysis(p_owner UUID,p_analysis UUID,p_failure TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE app_user public.users; usage_row internal.complimentary_scan_usage;
    consumed BOOLEAN:=FALSE; released BOOLEAN:=FALSE; changed BOOLEAN:=FALSE; settled TIMESTAMPTZ;
BEGIN
    IF p_owner IS NULL OR p_analysis IS NULL OR (p_failure IS NOT NULL AND p_failure !~ '^[a-z][a-z0-9_]{1,63}$') THEN
        RAISE EXCEPTION 'invalid_scan_terminal_failure' USING ERRCODE='22023';
    END IF;
    SELECT * INTO app_user FROM public.users WHERE id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
    SELECT * INTO usage_row FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis FOR UPDATE;
    settled:=clock_timestamp();
    IF FOUND AND usage_row.state='held' THEN
        IF p_failure IS NOT NULL OR (app_user.subscription_tier='pro' AND (app_user.subscription_expires_at IS NULL OR app_user.subscription_expires_at>settled)) THEN
            UPDATE internal.complimentary_scan_usage SET state='released',settled_at=settled,
                settlement_reason=COALESCE(p_failure,'paid_before_completion'),updated_at=settled
            WHERE user_id=p_owner AND client_scan_id=p_analysis;
            released:=TRUE;
        ELSE
            UPDATE internal.complimentary_scan_usage SET state='consumed',settled_at=settled,
                settlement_reason='durable_result_complete',updated_at=settled WHERE user_id=p_owner AND client_scan_id=p_analysis;
            consumed:=TRUE;
        END IF;
        changed:=TRUE;
    ELSIF FOUND AND usage_row.state='consumed' AND p_failure IS NULL THEN consumed:=TRUE;
    END IF;
    IF changed THEN UPDATE public.users SET complimentary_entitlement_epoch=complimentary_entitlement_epoch+1 WHERE id=p_owner; END IF;
    RETURN jsonb_build_object('credit_consumed',consumed,'credit_released',released);
END;
$$;
REVOKE ALL ON FUNCTION internal.settle_complimentary_analysis(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.observation_analysis_intents (
    analysis_id UUID PRIMARY KEY,
    observation_id UUID NOT NULL REFERENCES internal.observation_histories(observation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    input_snapshot JSONB NOT NULL CHECK(octet_length(input_snapshot::TEXT)<=1048576),
    state TEXT NOT NULL DEFAULT 'admitted' CHECK(state IN ('admitted','dispatched','draft','complete','failed_terminal')),
    quota JSONB,
    invocation_id UUID,
    draft JSONB CHECK(octet_length(draft::TEXT)<=1048576),
    receipt JSONB CHECK(octet_length(receipt::TEXT)<=2097152),
    terminal_reason TEXT,
    provider_usage JSONB CHECK(jsonb_typeof(provider_usage)='object' AND octet_length(provider_usage::TEXT)<=2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK(analysis_id<>observation_id)
);
CREATE INDEX observation_analysis_intents_parent ON internal.observation_analysis_intents(observation_id);
CREATE INDEX observation_analysis_intents_owner ON internal.observation_analysis_intents(owner_id);
ALTER TABLE internal.observation_analysis_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_analysis_intents FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.finalize_observation_provider_reservation(p_owner UUID,p_analysis UUID,p_reservation UUID,p_token UUID,p_state TEXT)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE old_fence TEXT;
BEGIN
    old_fence:=current_setting('merian.observation_analysis_provider',TRUE);
    PERFORM set_config('merian.observation_analysis_provider',p_owner::TEXT || ':' || p_analysis::TEXT,TRUE);
    PERFORM public.finalize_ai_quota_reservation(p_reservation,p_owner,p_token,p_state);
    PERFORM set_config('merian.observation_analysis_provider',COALESCE(old_fence,''),TRUE);
END;
$$;
REVOKE ALL ON FUNCTION internal.finalize_observation_provider_reservation(UUID,UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.admit_observation_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; analysis UUID; source UUID; saved internal.observation_analysis_intents;
    admitted RECORD; item JSONB; field TEXT; previous_fence TEXT;
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object'
        OR NOT (p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' IS DISTINCT FROM '1'::JSONB OR octet_length(p_input::TEXT)>1048576
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR p_input->'history_protocol' IS DISTINCT FROM '7'::JSONB
        OR p_input->>'expected_processor_permission' IS NULL OR p_input->>'expected_processor_permission' NOT IN ('google_gemini','openai')
        OR jsonb_typeof(p_input->'request_digest') IS DISTINCT FROM 'string' OR p_input->>'request_digest' IS NULL OR p_input->>'request_digest' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','analysis_id'] LOOP
        IF jsonb_typeof(p_input->field) IS DISTINCT FROM 'string' OR p_input->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF p_input->'source_analysis_id'<>'null'::JSONB AND (jsonb_typeof(p_input->'source_analysis_id') IS DISTINCT FROM 'string'
        OR p_input->>'source_analysis_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation:=(p_input->>'observation_id')::UUID; analysis:=(p_input->>'analysis_id')::UUID; source:=(p_input->>'source_analysis_id')::UUID;
    IF analysis=observation OR source IN (analysis,observation) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_input->'evidence_manifest') IS DISTINCT FROM 'object'
        OR (p_input->'evidence_manifest') - ARRAY['schema_version','captured_media']<>'{}'
        OR p_input#>'{evidence_manifest,schema_version}' IS DISTINCT FROM '1'::JSONB
        OR jsonb_typeof(p_input#>'{evidence_manifest,captured_media}') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF jsonb_array_length(p_input#>'{evidence_manifest,captured_media}') NOT BETWEEN 1 AND 64 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(p_input#>'{evidence_manifest,captured_media}') LOOP
        IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR item-'description'<>'{}'
            OR jsonb_typeof(item->'description') IS DISTINCT FROM 'object' OR (item->'description')-'_0'<>'{}'
            OR jsonb_typeof(item#>'{description,_0}') IS DISTINCT FROM 'object' OR (item#>'{description,_0}')-'freeText'<>'{}'
            OR jsonb_typeof(item#>'{description,_0,freeText}') IS DISTINCT FROM 'string'
            OR char_length(item#>>'{description,_0,freeText}') NOT BETWEEN 1 AND 8192 OR btrim(item#>>'{description,_0,freeText}')='' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF EXISTS(SELECT 1 FROM public.scans WHERE id=analysis) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || analysis::TEXT,0::BIGINT));
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || analysis::TEXT,0::BIGINT));
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=analysis FOR UPDATE;
    IF FOUND THEN
        IF saved.owner_id<>p_owner OR saved.observation_id<>observation OR saved.input_snapshot<>p_input THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- Dispatched/ambiguous work is recovery-only, never another provider call.
        IF saved.state<>'admitted' THEN RETURN to_jsonb(saved)-'draft'; END IF;
    ELSE
        IF (SELECT admission_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=analysis)
            OR EXISTS(SELECT 1 FROM public.scans WHERE id=analysis)
            OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=analysis::TEXT)
            OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
            OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=analysis)
            OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=analysis)
            OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=analysis)
            OR (source IS NOT NULL AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=source AND observation_id=observation)) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) VALUES(analysis,observation,p_owner,p_input);
    END IF;
    IF (SELECT admission_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    previous_fence:=current_setting('merian.observation_analysis_admission',TRUE);
    PERFORM set_config('merian.observation_analysis_admission',p_owner::TEXT || ':' || analysis::TEXT,TRUE);
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(p_owner,'scan_identification',analysis,p_ip_hash,analysis,FALSE,
        (p_input->>'entitlement_protocol')::INTEGER,FALSE,'multimodal_text_v1',p_input->>'expected_processor_permission',(p_input->>'identification_protocol')::INTEGER);
    PERFORM set_config('merian.observation_analysis_admission',COALESCE(previous_fence,''),TRUE);
    IF admitted.original_analysis_id IS DISTINCT FROM analysis OR admitted.reservation_state<>'reserved' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.observation_analysis_intents SET quota=to_jsonb(admitted) WHERE analysis_id=analysis RETURNING * INTO saved;
    RETURN to_jsonb(saved)-'draft';
END;
$$;

CREATE FUNCTION internal.dispatch_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_token UUID,p_provenance JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; dispatched RECORD; old_fence TEXT;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner FOR UPDATE;
    IF NOT FOUND OR p_token IS NULL OR saved.quota->>'lease_token' IS DISTINCT FROM p_token::TEXT THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF saved.state IN ('dispatched','draft','complete') THEN
        IF NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE id=saved.invocation_id AND provenance=p_provenance) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        RETURN jsonb_build_object('invocation_id',saved.invocation_id,'may_dispatch',FALSE);
    END IF;
    IF saved.state<>'admitted' OR (SELECT dispatch_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.require_identification_processor_consent(p_owner,saved.quota->>'processor_permission');
    old_fence:=current_setting('merian.observation_analysis_provider',TRUE);
    PERFORM set_config('merian.observation_analysis_provider',p_owner::TEXT || ':' || p_analysis::TEXT,TRUE);
    SELECT * INTO STRICT dispatched FROM public.commit_identification_invocation((saved.quota->>'reservation_id')::UUID,p_owner,p_token,(saved.quota->>'attempt_count')::INTEGER,p_provenance);
    PERFORM set_config('merian.observation_analysis_provider',COALESCE(old_fence,''),TRUE);
    IF NOT dispatched.may_dispatch THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    UPDATE internal.observation_analysis_intents SET state='dispatched',invocation_id=dispatched.invocation_id WHERE analysis_id=p_analysis;
    RETURN to_jsonb(dispatched);
END;
$$;

CREATE FUNCTION internal.record_observation_analysis_draft(p_owner UUID,p_observation UUID,p_analysis UUID,p_token UUID,p_draft JSONB,p_usage JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; expected_identity JSONB;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner FOR UPDATE;
    IF NOT FOUND OR p_token IS NULL OR saved.quota->>'lease_token' IS DISTINCT FROM p_token::TEXT THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_usage) IS DISTINCT FROM 'object' OR octet_length(p_usage::TEXT)>2048 OR p_usage-ARRAY['input_tokens','cached_tokens','cache_write_tokens','output_tokens','candidate_tokens','thinking_tokens','tool_tokens','total_tokens','service_tier','modality_breakdown']<>'{}' THEN RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
    expected_identity:=saved.input_snapshot-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'];
    IF jsonb_typeof(p_draft) IS DISTINCT FROM 'object' OR octet_length(p_draft::TEXT)>1048576
        OR p_draft-'result_snapshot' IS DISTINCT FROM expected_identity
        OR jsonb_typeof(p_draft->'result_snapshot') IS DISTINCT FROM 'object'
        OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE id=saved.invocation_id
            AND provenance=p_draft#>'{result_snapshot,identification_provenance}') THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF saved.state IN ('draft','complete') THEN
        IF saved.draft IS DISTINCT FROM p_draft OR saved.provider_usage IS DISTINCT FROM p_usage THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        RETURN;
    END IF;
    IF saved.state<>'dispatched' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.complete_identification_usage(saved.invocation_id,'draft',p_usage);
    UPDATE internal.observation_analysis_intents SET state='draft',draft=p_draft,provider_usage=p_usage WHERE analysis_id=p_analysis;
END;
$$;

CREATE FUNCTION internal.complete_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; snapshot TEXT; settlement JSONB; completion_receipt JSONB; entitlement RECORD; old_fence TEXT;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF saved.state='complete' THEN RETURN saved.receipt; END IF;
    IF saved.state<>'draft' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF saved.quota->>'complimentary_client_scan_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis AND state='held') THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    old_fence:=current_setting('merian.observation_analysis_completion',TRUE);
    PERFORM set_config('merian.observation_analysis_completion',p_owner::TEXT || ':' || p_analysis::TEXT,TRUE);
    snapshot:=internal.append_observation_analysis(p_owner,saved.draft);
    PERFORM set_config('merian.observation_analysis_completion',COALESCE(old_fence,''),TRUE);
    settlement:=internal.settle_complimentary_analysis(p_owner,p_analysis);
    SELECT * INTO STRICT entitlement FROM internal.resolve_effective_entitlement(p_owner);
    completion_receipt:=jsonb_build_object('snapshot',snapshot,'plan_used',saved.quota->>'effective_plan','credit_consumed',settlement->'credit_consumed','entitlement_after',to_jsonb(entitlement));
    UPDATE internal.observation_analysis_intents SET state='complete',receipt=completion_receipt WHERE analysis_id=p_analysis;
    RETURN completion_receipt;
END;
$$;

CREATE FUNCTION internal.fail_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_token UUID,p_reason TEXT,p_usage JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis AND observation_id=p_observation AND owner_id=p_owner FOR UPDATE;
    IF NOT FOUND OR p_token IS NULL OR saved.quota->>'lease_token' IS DISTINCT FROM p_token::TEXT THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_usage) IS DISTINCT FROM 'object' OR octet_length(p_usage::TEXT)>2048 OR p_usage-ARRAY['input_tokens','cached_tokens','cache_write_tokens','output_tokens','candidate_tokens','thinking_tokens','tool_tokens','total_tokens','service_tier','modality_breakdown']<>'{}' THEN RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
    IF saved.state='failed_terminal' AND saved.terminal_reason=p_reason AND saved.provider_usage=p_usage THEN RETURN; END IF;
    IF p_reason IS NULL OR NOT ((saved.state='admitted' AND p_reason IN ('cancelled_before_dispatch','admission_expired'))
        OR (saved.state='dispatched' AND p_reason IN ('provider_refusal','invalid_result','proven_provider_failure'))) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF saved.state='admitted' THEN
        PERFORM internal.finalize_observation_provider_reservation(p_owner,p_analysis,(saved.quota->>'reservation_id')::UUID,p_token,'refunded');
    END IF;
    IF saved.state='dispatched' THEN PERFORM internal.complete_identification_usage(saved.invocation_id,CASE p_reason WHEN 'provider_refusal' THEN 'refusal' WHEN 'invalid_result' THEN 'invalid_output' ELSE 'operational_failure' END,p_usage); END IF;
    PERFORM internal.settle_complimentary_analysis(p_owner,p_analysis,p_reason);
    UPDATE internal.observation_analysis_intents SET state='failed_terminal',terminal_reason=p_reason,provider_usage=p_usage WHERE analysis_id=p_analysis;
END;
$$;

-- Child cancellation is owned by observation erasure, never the legacy scan job.
CREATE FUNCTION internal.erase_observation_analysis_intent()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM id FROM public.users WHERE id=OLD.owner_id FOR UPDATE;
    IF FOUND THEN
        IF OLD.state='admitted' AND EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(OLD.quota->>'reservation_id')::UUID AND state='reserved') THEN
            PERFORM internal.finalize_observation_provider_reservation(OLD.owner_id,OLD.analysis_id,(OLD.quota->>'reservation_id')::UUID,(OLD.quota->>'lease_token')::UUID,'refunded');
        END IF;
        PERFORM internal.settle_complimentary_analysis(OLD.owner_id,OLD.analysis_id,'observation_deleted');
    END IF;
    -- Reuse the existing permanent deleted-generation namespace without retaining
    -- any owner, observation link, private input or cleanup work for a child.
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || OLD.analysis_id::TEXT,0::BIGINT));
    INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
    VALUES(OLD.analysis_id,NULL,now()) ON CONFLICT(scan_id) DO NOTHING;
    RETURN OLD;
END;
$$;
CREATE TRIGGER erase_observation_analysis_intent BEFORE DELETE ON internal.observation_analysis_intents FOR EACH ROW EXECUTE FUNCTION internal.erase_observation_analysis_intent();
CREATE FUNCTION internal.fence_observation_analysis_intents()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_analysis_intents WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER fence_observation_analysis_intents AFTER INSERT ON internal.scan_deletion_tombstones FOR EACH ROW EXECUTE FUNCTION internal.fence_observation_analysis_intents();

CREATE FUNCTION internal.guard_funded_observation_result()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE owned_by UUID;
BEGIN
    SELECT owner_id INTO owned_by FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id;
    IF FOUND AND current_setting('merian.observation_analysis_completion',TRUE) IS DISTINCT FROM owned_by::TEXT || ':' || NEW.analysis_id::TEXT THEN
        RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_observation_zfunded_result BEFORE INSERT ON internal.observation_analysis_results FOR EACH ROW EXECUTE FUNCTION internal.guard_funded_observation_result();

-- Serialize legacy INSERT with child admission and permanent deletion fences.
CREATE FUNCTION internal.guard_history_child_scan_identity()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM id FROM public.users WHERE id=NEW.user_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || NEW.id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=NEW.id) THEN
        RAISE EXCEPTION 'scan_generation_deleted' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER a_guard_history_child_scan_identity BEFORE INSERT ON public.scans FOR EACH ROW EXECUTE FUNCTION internal.guard_history_child_scan_identity();
REVOKE ALL ON FUNCTION internal.guard_history_child_scan_identity() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_funded_observation_evidence()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER guard_funded_observation_evidence BEFORE INSERT ON internal.observation_evidence_objects FOR EACH ROW EXECUTE FUNCTION internal.guard_funded_observation_evidence();
REVOKE ALL ON FUNCTION internal.guard_funded_observation_evidence() FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION internal.admit_observation_analysis(UUID,JSONB,TEXT),internal.dispatch_observation_analysis(UUID,UUID,UUID,UUID,JSONB),
    internal.record_observation_analysis_draft(UUID,UUID,UUID,UUID,JSONB,JSONB),internal.complete_observation_analysis(UUID,UUID,UUID),
    internal.fail_observation_analysis(UUID,UUID,UUID,UUID,TEXT,JSONB),internal.erase_observation_analysis_intent(),
    internal.fence_observation_analysis_intents(),internal.guard_funded_observation_result() FROM PUBLIC,anon,authenticated,service_role;

-- Keep the existing public ABIs, admission rules and completion fences. Extract
-- only the ledger transition, guarded against source drift in applied history.
DO $patch$
DECLARE definition TEXT; fragment TEXT; replacement TEXT; signature TEXT;
BEGIN
    signature := 'public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)';
    definition:=pg_get_functiondef(to_regprocedure(signature));
    fragment:=$old$    UPDATE internal.complimentary_scan_usage AS usage
    SET state = 'released',
        settled_at = settlement_now,
        settlement_reason = p_terminal_reason_code,
        updated_at = settlement_now
    WHERE usage.user_id = p_user_id
      AND usage.client_scan_id = p_scan_id
      AND usage.state = 'held';
    usage_released := FOUND;

    IF usage_released THEN
        UPDATE public.users AS users
        SET complimentary_entitlement_epoch =
                users.complimentary_entitlement_epoch + 1
        WHERE users.id = p_user_id;
    END IF;

$old$;
    replacement:=$new$    usage_released := (internal.settle_complimentary_analysis(p_user_id,p_scan_id,p_terminal_reason_code)->>'credit_released')::BOOLEAN;

$new$;
    IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_settlement_source_drift'; END IF;
    definition:=replace(definition,fragment,replacement);
    definition:=replace(definition,'    PERFORM internal.require_service_role();',
        '    PERFORM internal.require_service_role();' || E'
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended(''merian-scan-ingestion:'' || p_scan_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan_id) THEN RAISE EXCEPTION ''analysis_history_completion_required'' USING ERRCODE=''55000''; END IF;');
    EXECUTE definition;
    signature := 'public.complete_scan_ingestion_with_entitlement(uuid,uuid,jsonb,jsonb,text[])';
    definition:=pg_get_functiondef(to_regprocedure(signature));
    fragment:=$old$    IF FOUND AND usage_row.state = 'held' THEN
        IF app_user.subscription_tier =
                'pro'::public.subscription_tier_enum
           AND (
                app_user.subscription_expires_at IS NULL
                OR app_user.subscription_expires_at > settlement_now
           ) THEN
            UPDATE internal.complimentary_scan_usage AS usage
            SET state = 'released',
                settled_at = settlement_now,
                settlement_reason = 'paid_before_completion',
                updated_at = settlement_now
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_scan_id;
        ELSE
            UPDATE internal.complimentary_scan_usage AS usage
            SET state = 'consumed',
                settled_at = settlement_now,
                settlement_reason = 'durable_result_complete',
                updated_at = settlement_now
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_scan_id;
            credit_consumed := TRUE;
        END IF;
        usage_changed := TRUE;
    ELSIF FOUND AND usage_row.state = 'consumed' THEN
        -- A replay reports how the stored result was funded, not whether this
        -- invocation performed the already-durable transition.
        credit_consumed := TRUE;
    END IF;

    IF usage_changed THEN
        UPDATE public.users AS users
        SET complimentary_entitlement_epoch =
                users.complimentary_entitlement_epoch + 1
        WHERE users.id = p_user_id;
    END IF;

$old$;
    replacement:=$new$    credit_consumed := (internal.settle_complimentary_analysis(p_user_id,p_scan_id)->>'credit_consumed')::BOOLEAN;

$new$;
    IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_settlement_source_drift'; END IF;
    definition:=replace(definition,fragment,replacement);
    definition:=replace(definition,'    usage_changed BOOLEAN := FALSE;' || chr(10),'');
    definition:=replace(definition,'    PERFORM internal.require_service_role();',
        '    PERFORM internal.require_service_role();' || E'
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended(''merian-scan-ingestion:'' || p_scan_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan_id) THEN RAISE EXCEPTION ''analysis_history_completion_required'' USING ERRCODE=''55000''; END IF;');
    EXECUTE definition;
    signature:='public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)';
    definition:=pg_get_functiondef(to_regprocedure(signature));
    fragment:='    scan_id_uuid := p_scan_id::UUID;';
    IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_ingestion_source_drift'; END IF;
    replacement:=fragment || $guard$
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || scan_id_uuid::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=scan_id_uuid) THEN
        RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
    END IF;
$guard$;
    EXECUTE replace(definition,fragment,replacement);
    signature:='internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)';
    definition:=pg_get_functiondef(to_regprocedure(signature));
    fragment:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
    IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_quota_source_drift'; END IF;
    replacement:=$guard$
    IF p_original_analysis_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || p_original_analysis_id::TEXT,0::BIGINT));
        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_original_analysis_id) THEN RAISE EXCEPTION 'scan_generation_deleted' USING ERRCODE='55000'; END IF;
        IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_original_analysis_id)
            AND current_setting('merian.observation_analysis_admission',TRUE) IS DISTINCT FROM p_user_id::TEXT || ':' || p_original_analysis_id::TEXT THEN
            RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
        END IF;
    END IF;
$guard$ || fragment;
    EXECUTE replace(definition,fragment,replacement);
    signature:='public.complete_identification_invocation(uuid,uuid,uuid,text,jsonb)';
    definition:=pg_get_functiondef(to_regprocedure(signature));
    fragment:='    PERFORM internal.require_service_role();';
    IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_usage_source_drift'; END IF;
    replacement:=fragment || $guard$
    IF EXISTS(SELECT 1 FROM internal.identification_invocations v JOIN internal.observation_analysis_intents i ON i.analysis_id=v.scan_id
        WHERE v.id=p_invocation_id) THEN RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000'; END IF;
$guard$;
    EXECUTE replace(definition,fragment,replacement);
    FOREACH signature IN ARRAY ARRAY['public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)','public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)'] LOOP
        definition:=pg_get_functiondef(to_regprocedure(signature));
        fragment:='    PERFORM internal.require_service_role();';
        IF definition IS NULL OR (length(definition)-length(replace(definition,fragment,'')))/length(fragment)<>1 THEN RAISE EXCEPTION 'history_dispatch_source_drift'; END IF;
        replacement:=fragment || $guard$
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations r JOIN internal.observation_analysis_intents i ON i.analysis_id=r.original_analysis_id
        WHERE r.id=p_reservation_id AND current_setting('merian.observation_analysis_provider',TRUE) IS DISTINCT FROM i.owner_id::TEXT || ':' || i.analysis_id::TEXT) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
$guard$;
        EXECUTE replace(definition,fragment,replacement);
    END LOOP;
END;
$patch$;

RESET lock_timeout;
RESET statement_timeout;

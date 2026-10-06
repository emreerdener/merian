SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Provider diagnostics and arbitrary JSON are not a completion payload.
CREATE FUNCTION internal.validate_protected_insight_chat_reply(p_reply JSONB)
RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE usage JSONB; item RECORD; category RECORD; detail RECORD;
BEGIN
    IF pg_catalog.jsonb_typeof(p_reply) IS DISTINCT FROM 'object'
        OR pg_catalog.octet_length(p_reply::TEXT)>32768
        OR NOT p_reply ?& ARRAY['answer','model','is_refusal','refusal_reason','usage']
        OR p_reply-ARRAY['answer','model','is_refusal','refusal_reason','usage']<>'{}'::JSONB
        OR pg_catalog.jsonb_typeof(p_reply->'answer') IS DISTINCT FROM 'string'
        OR pg_catalog.char_length(p_reply->>'answer') NOT BETWEEN 1 AND 4000
        OR pg_catalog.btrim(p_reply->>'answer',E' \t\n\r')=''
        OR pg_catalog.btrim(p_reply->>'answer') IS DISTINCT FROM p_reply->>'answer'
        OR p_reply->>'model' IS DISTINCT FROM 'gemini-2.5-flash'
        OR pg_catalog.jsonb_typeof(p_reply->'is_refusal') IS DISTINCT FROM 'boolean'
        OR (p_reply->'refusal_reason'<>'null'::JSONB AND (
            pg_catalog.jsonb_typeof(p_reply->'refusal_reason') IS DISTINCT FROM 'string'
            OR pg_catalog.char_length(p_reply->>'refusal_reason') NOT BETWEEN 1 AND 100
            OR pg_catalog.btrim(p_reply->>'refusal_reason',E' \t\n\r')=''
            OR pg_catalog.btrim(p_reply->>'refusal_reason') IS DISTINCT FROM p_reply->>'refusal_reason'))
        OR (p_reply->'is_refusal'='false'::JSONB AND p_reply->'refusal_reason'<>'null'::JSONB) THEN
        RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023';
    END IF;
    usage:=p_reply->'usage';
    IF usage='null'::JSONB THEN RETURN; END IF;
    IF pg_catalog.jsonb_typeof(usage) IS DISTINCT FROM 'object'
        OR NOT usage ?& ARRAY['prompt_tokens','candidate_tokens','thinking_tokens','total_tokens','cached_tokens','modality_breakdown']
        OR usage-ARRAY['prompt_tokens','candidate_tokens','thinking_tokens','total_tokens','cached_tokens','modality_breakdown']<>'{}'::JSONB
        OR pg_catalog.jsonb_typeof(usage->'modality_breakdown') IS DISTINCT FROM 'object'
        OR NOT (usage->'modality_breakdown') ?& ARRAY['prompt','cached','candidates','tool']
        OR (usage->'modality_breakdown')-ARRAY['prompt','cached','candidates','tool']<>'{}'::JSONB THEN
        RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT key,value FROM pg_catalog.jsonb_each(usage-'modality_breakdown') LOOP
        IF item.value='null'::JSONB THEN CONTINUE; END IF;
        IF pg_catalog.jsonb_typeof(item.value) IS DISTINCT FROM 'number' OR item.value::TEXT!~'^[0-9]{1,10}$' THEN
            RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023';
        END IF;
        IF (item.value::TEXT)::BIGINT>2147483647 THEN RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023'; END IF;
    END LOOP;
    FOR category IN SELECT key,value FROM pg_catalog.jsonb_each(usage->'modality_breakdown') LOOP
        IF pg_catalog.jsonb_typeof(category.value) IS DISTINCT FROM 'object'
            OR category.value-ARRAY['text','image','audio','video','document','unspecified']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023';
        END IF;
        FOR detail IN SELECT key,value FROM pg_catalog.jsonb_each(category.value) LOOP
            IF pg_catalog.jsonb_typeof(detail.value) IS DISTINCT FROM 'number' OR detail.value::TEXT!~'^[0-9]{1,10}$' THEN
                RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023';
            END IF;
            IF (detail.value::TEXT)::BIGINT>2147483647 THEN RAISE EXCEPTION 'field_chat_invalid_reply' USING ERRCODE='22023'; END IF;
        END LOOP;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION internal.validate_protected_insight_chat_reply(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.protected_insight_chat_reply_receipt(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,p_displayed_ticket JSONB,
    p_context_version INTEGER,p_message_id UUID,p_conversation_id UUID,p_reservation_id UUID,p_lease_token UUID,p_reply JSONB
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE fence internal.insight_chat_execution_fences; receipt JSONB;
    saved public.insight_chat_messages; usage JSONB; metadata JSONB; fingerprint TEXT;
BEGIN
    IF p_message_id IS NULL OR p_conversation_id IS NULL OR p_reservation_id IS NULL OR p_lease_token IS NULL THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    fingerprint:=internal.insight_chat_execution_fingerprint(p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    SELECT * INTO fence FROM internal.insight_chat_execution_fences
        WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id FOR UPDATE;
    IF NOT FOUND OR fence.reservation_id IS DISTINCT FROM p_reservation_id OR fence.lease_token IS DISTINCT FROM p_lease_token
        OR fence.request_sha256 IS DISTINCT FROM fingerprint OR NOT fence.message_bound
        OR fence.message_id IS DISTINCT FROM p_message_id OR fence.dispatch_grant_id IS NULL OR fence.dispatch_granted_at IS NULL THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    receipt:=public.get_insight_chat_turn_completion(p_user_id,p_scan_id,p_client_message_id,p_message_text,
        p_displayed_ticket,p_context_version,p_message_id,p_conversation_id);
    usage:=p_reply->'usage';
    metadata:=pg_catalog.jsonb_build_object('request_id',p_client_message_id)
        || CASE WHEN (p_reply->>'is_refusal')::BOOLEAN THEN pg_catalog.jsonb_build_object('refusal_reason',p_reply->'refusal_reason') ELSE '{}'::JSONB END;
    IF (receipt->>'completed')::BOOLEAN THEN
        SELECT * INTO STRICT saved FROM public.insight_chat_messages WHERE id=(receipt#>>'{message,id}')::UUID FOR SHARE;
        IF ROW(saved.message_text,saved.model,saved.is_refusal,saved.refusal_reason,saved.llm_prompt_tokens,saved.llm_candidate_tokens,
            saved.llm_thinking_tokens,saved.llm_total_tokens,saved.llm_cached_tokens,saved.llm_usage_metadata,saved.safety_metadata)
            IS DISTINCT FROM ROW(p_reply->>'answer',p_reply->>'model',(p_reply->>'is_refusal')::BOOLEAN,p_reply->>'refusal_reason',
                (usage->>'prompt_tokens')::INTEGER,(usage->>'candidate_tokens')::INTEGER,(usage->>'thinking_tokens')::INTEGER,
                (usage->>'total_tokens')::INTEGER,(usage->>'cached_tokens')::INTEGER,COALESCE(usage->'modality_breakdown','{}'::JSONB),metadata) THEN
            RAISE EXCEPTION 'field_chat_reply_conflict' USING ERRCODE='23505';
        END IF;
        RETURN receipt;
    END IF;
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION internal.protected_insight_chat_reply_receipt(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID,UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.get_protected_insight_chat_reply(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,p_displayed_ticket JSONB,
    p_context_version INTEGER,p_message_id UUID,p_conversation_id UUID,p_reservation_id UUID,p_lease_token UUID,p_reply JSONB
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    PERFORM internal.validate_protected_insight_chat_reply(p_reply);
    RETURN internal.protected_insight_chat_reply_receipt(p_user_id,p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version,p_message_id,p_conversation_id,p_reservation_id,p_lease_token,p_reply);
END;
$$;
REVOKE ALL ON FUNCTION public.get_protected_insight_chat_reply(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID,UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_protected_insight_chat_reply(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID,UUID,UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.get_protected_insight_chat_reply(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid,uuid,uuid,jsonb)',
 'Read an exact original-grant reply with private payload equality; never admit or write.');

CREATE FUNCTION public.complete_protected_insight_chat_reply(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,p_displayed_ticket JSONB,
    p_context_version INTEGER,p_message_id UUID,p_conversation_id UUID,p_reservation_id UUID,p_lease_token UUID,p_reply JSONB
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE quota internal.ai_quota_reservations; receipt JSONB; usage JSONB; metadata JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    PERFORM internal.validate_protected_insight_chat_reply(p_reply);
    -- Same subject -> quota -> fence -> message order as dispatch admission.
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=p_reservation_id FOR UPDATE;
    receipt:=internal.protected_insight_chat_reply_receipt(p_user_id,p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version,p_message_id,p_conversation_id,p_reservation_id,p_lease_token,p_reply);
    IF (receipt->>'completed')::BOOLEAN THEN RETURN receipt; END IF;
    usage:=p_reply->'usage';
    metadata:=pg_catalog.jsonb_build_object('request_id',p_client_message_id)
        || CASE WHEN (p_reply->>'is_refusal')::BOOLEAN THEN pg_catalog.jsonb_build_object('refusal_reason',p_reply->'refusal_reason') ELSE '{}'::JSONB END;
    -- A late original reply may finish after lease/gate/consent changes. It is
    -- not fresh inference. Pruned or retired quota cannot authorize a NEW write.
    IF quota.id IS NULL OR quota.user_id IS DISTINCT FROM p_user_id OR quota.request_id IS DISTINCT FROM p_client_message_id
        OR quota.original_analysis_id IS DISTINCT FROM p_scan_id OR quota.operation IS DISTINCT FROM 'insight_chat_reply'
        OR quota.lease_token IS DISTINCT FROM p_lease_token OR quota.attempt_count<>1 OR quota.state<>'committed'
        OR quota.model IS DISTINCT FROM p_reply->>'model' THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    INSERT INTO public.insight_chat_messages(id,conversation_id,user_id,scan_id,role,message_text,model,is_refusal,refusal_reason,
        llm_prompt_tokens,llm_candidate_tokens,llm_thinking_tokens,llm_total_tokens,llm_cached_tokens,llm_usage_metadata,safety_metadata)
    VALUES(internal.insight_chat_assistant_id(p_conversation_id,p_client_message_id),p_conversation_id,p_user_id,p_scan_id,'assistant',
        p_reply->>'answer',p_reply->>'model',(p_reply->>'is_refusal')::BOOLEAN,p_reply->>'refusal_reason',
        (usage->>'prompt_tokens')::INTEGER,(usage->>'candidate_tokens')::INTEGER,(usage->>'thinking_tokens')::INTEGER,
        (usage->>'total_tokens')::INTEGER,(usage->>'cached_tokens')::INTEGER,COALESCE(usage->'modality_breakdown','{}'::JSONB),metadata);
    UPDATE public.insight_chat_conversations SET updated_at=pg_catalog.clock_timestamp()
        WHERE id=p_conversation_id AND user_id=p_user_id AND scan_id=p_scan_id;
    RETURN public.get_insight_chat_turn_completion(p_user_id,p_scan_id,p_client_message_id,p_message_text,
        p_displayed_ticket,p_context_version,p_message_id,p_conversation_id);
END;
$$;
REVOKE ALL ON FUNCTION public.complete_protected_insight_chat_reply(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID,UUID,UUID,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_protected_insight_chat_reply(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID,UUID,UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.complete_protected_insight_chat_reply(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid,uuid,uuid,jsonb)',
 'Persist the exact original dispatched Insight reply once; no quota admission, redispatch or refund.');
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

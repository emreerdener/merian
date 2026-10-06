SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- The caller already holds the exact original user/context and subject locks.
-- Return only the existing public message projection, never its private metadata.
CREATE FUNCTION internal.insight_chat_completion_receipt(
    p_user_id UUID,p_scan_id UUID,p_request_id UUID,p_message_id UUID,p_conversation_id UUID,p_context JSONB
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE answer public.insight_chat_messages; snapshot JSONB; response JSONB;
BEGIN
    IF p_message_id IS NULL OR p_conversation_id IS NULL
        OR p_context->>'found' IS DISTINCT FROM 'true'
        OR p_context#>>'{message,id}' IS DISTINCT FROM p_message_id::TEXT
        OR p_context#>>'{message,conversation_id}' IS DISTINCT FROM p_conversation_id::TEXT THEN
        RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000';
    END IF;
    snapshot:=p_context->'context_snapshot';
    IF pg_catalog.jsonb_typeof(snapshot) IS DISTINCT FROM 'object'
        OR NOT snapshot ?& ARRAY['context_version','source_kind','displayed_ticket','scan_context','conversation_prefix']
        OR snapshot-ARRAY['context_version','source_kind','displayed_ticket','scan_context','conversation_prefix']<>'{}'::JSONB
        OR snapshot->'context_version' IS DISTINCT FROM '1'::JSONB
        OR snapshot->>'source_kind' IS DISTINCT FROM (CASE WHEN snapshot->'displayed_ticket'='null'::JSONB THEN 'legacy_scan_v1' ELSE 'analysis_history_v1' END)
        OR pg_catalog.jsonb_typeof(snapshot->'scan_context') IS DISTINCT FROM 'object'
        OR pg_catalog.jsonb_typeof(snapshot->'conversation_prefix') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000';
    END IF;
    IF pg_catalog.jsonb_array_length(snapshot->'conversation_prefix')>12 OR EXISTS(
        SELECT 1 FROM pg_catalog.jsonb_array_elements(snapshot->'conversation_prefix') item
        WHERE pg_catalog.jsonb_typeof(item) IS DISTINCT FROM 'object'
            OR NOT item ?& ARRAY['role','text'] OR item-ARRAY['role','text']<>'{}'::JSONB
            OR pg_catalog.jsonb_typeof(item->'role') IS DISTINCT FROM 'string'
            OR item->>'role' NOT IN('user','assistant')
            OR pg_catalog.jsonb_typeof(item->'text') IS DISTINCT FROM 'string'
            OR pg_catalog.char_length(item->>'text')>900
    ) THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
    SELECT * INTO answer FROM public.insight_chat_messages
        WHERE id=internal.insight_chat_assistant_id(p_conversation_id,p_request_id) FOR SHARE;
    IF NOT FOUND THEN
        -- A reparented or damaged completion is not a new empty turn.
        IF EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE conversation_id=p_conversation_id
            AND role='assistant' AND safety_metadata->>'request_id'=p_request_id::TEXT) THEN
            RAISE EXCEPTION 'field_chat_completion_held' USING ERRCODE='55000';
        END IF;
        RETURN pg_catalog.jsonb_build_object('context_version',1,'completed',FALSE);
    END IF;
    IF answer.conversation_id<>p_conversation_id OR answer.scan_id<>p_scan_id OR answer.user_id<>p_user_id
        OR answer.role<>'assistant' OR answer.client_message_id IS NOT NULL
        OR answer.safety_metadata->>'request_id' IS DISTINCT FROM p_request_id::TEXT
        OR pg_catalog.btrim(answer.message_text)='' OR pg_catalog.char_length(answer.message_text)>4000
        OR (answer.model IS NOT NULL AND (pg_catalog.btrim(answer.model)='' OR pg_catalog.char_length(answer.model)>200))
        OR (answer.refusal_reason IS NOT NULL AND (pg_catalog.btrim(answer.refusal_reason)='' OR pg_catalog.char_length(answer.refusal_reason)>100))
        OR NOT pg_catalog.isfinite(answer.created_at) THEN
        RAISE EXCEPTION 'field_chat_completion_held' USING ERRCODE='55000';
    END IF;
    response:=pg_catalog.jsonb_build_object('context_version',1,'completed',TRUE,'message',pg_catalog.jsonb_build_object(
        'id',answer.id,'conversation_id',answer.conversation_id,'scan_id',answer.scan_id,'role','assistant',
        'text',answer.message_text,'client_message_id',p_request_id,'model',answer.model,
        'is_refusal',answer.is_refusal,'refusal_reason',answer.refusal_reason,'created_at',answer.created_at));
    IF pg_catalog.octet_length(response::TEXT)>32768 THEN
        RAISE EXCEPTION 'field_chat_completion_held' USING ERRCODE='55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_completion_receipt(UUID,UUID,UUID,UUID,UUID,JSONB)
    FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.get_insight_chat_turn_completion(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,p_displayed_ticket JSONB,
    p_context_version INTEGER,p_message_id UUID,p_conversation_id UUID
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE context JSONB;
BEGIN
    PERFORM internal.require_service_role();
    context:=public.get_insight_chat_turn_context(p_user_id,p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    IF context#>'{context_snapshot,displayed_ticket}' IS DISTINCT FROM COALESCE(p_displayed_ticket,'null'::JSONB) THEN
        RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000';
    END IF;
    RETURN internal.insight_chat_completion_receipt(p_user_id,p_scan_id,p_client_message_id,p_message_id,p_conversation_id,context);
END;
$$;
REVOKE ALL ON FUNCTION public.get_insight_chat_turn_completion(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_insight_chat_turn_completion(UUID,UUID,UUID,TEXT,JSONB,INTEGER,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.get_insight_chat_turn_completion(uuid,uuid,uuid,text,jsonb,integer,uuid,uuid)',
 'Read exact immutable user turn and deterministic owned assistant receipt without admission or execution.');


-- Closed local safety answers are persisted atomically, never provider work.
CREATE FUNCTION internal.insight_chat_refusal_text(p_reason TEXT)
RETURNS TEXT LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    CASE p_reason
    WHEN 'foraging_or_ingestion' THEN RETURN 'I cannot tell you that this organism is safe to eat, brew, cook, or feed to people or animals. Treat field identifications as educational only, and consult a qualified local expert before any ingestion-related decision. I can still help compare visible traits, habitat, seasonality, or lookalikes from the saved scan evidence.';
    WHEN 'medical_or_veterinary' THEN RETURN 'I cannot provide medical, veterinary, poison-control, dosage, or treatment advice. If there is possible exposure, bite, sting, ingestion, or a concerning reaction, contact local emergency services, poison control, or a qualified clinician. I can help explain the stored hazard classification and identification evidence in non-treatment terms.';
    WHEN 'dangerous_handling' THEN RETURN 'I cannot give instructions for dangerous handling, capture, killing, poisoning, or removal. Observe from a safe distance and follow local guidance. I can help describe safer field-observation cues from the saved scan context.';
    WHEN 'legal_or_collection' THEN RETURN 'I cannot determine whether collection, harvest, or removal is legal from this scan. Rules vary by location, land manager, and species status. Check local regulations or a qualified authority before acting. I can help summarize the conservation and identification context Naturebook has saved.';
    ELSE RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END CASE;
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_refusal_text(TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.admit_insight_chat_local_refusal(
    p_user_id UUID,p_conversation_id UUID,p_scan_id UUID,p_message_text TEXT,p_client_message_id UUID,
    p_displayed_ticket JSONB,p_context_version INTEGER,p_refusal_reason TEXT
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE context JSONB; receipt JSONB; answer TEXT; admitted RECORD; original_id UUID; conversation UUID;
BEGIN
    PERFORM internal.require_service_role();
    answer:=internal.insight_chat_refusal_text(p_refusal_reason);
    IF p_conversation_id IS NULL THEN RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023'; END IF;
    -- Exclusive subject locks precede read recovery, so later admission needs no
    -- owner/scan lock upgrade. Account merge and deletion use the same order.
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    context:=public.get_insight_chat_turn_context(p_user_id,p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    IF (context->>'found')::BOOLEAN THEN
        original_id:=(context#>>'{message,id}')::UUID;
        conversation:=(context#>>'{message,conversation_id}')::UUID;
        receipt:=public.get_insight_chat_turn_completion(p_user_id,p_scan_id,p_client_message_id,p_message_text,
            p_displayed_ticket,p_context_version,original_id,conversation);
        IF receipt->>'completed' IS DISTINCT FROM 'true'
            OR receipt#>'{message,is_refusal}' IS DISTINCT FROM 'true'::JSONB
            OR receipt#>>'{message,refusal_reason}' IS DISTINCT FROM p_refusal_reason
            OR receipt#>>'{message,text}' IS DISTINCT FROM answer
            OR receipt#>'{message,model}' IS DISTINCT FROM 'null'::JSONB
            OR NOT EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE id=(receipt#>>'{message,id}')::UUID
                AND llm_prompt_tokens IS NULL AND llm_candidate_tokens IS NULL AND llm_thinking_tokens IS NULL
                AND llm_total_tokens IS NULL AND llm_cached_tokens IS NULL
                AND safety_metadata=pg_catalog.jsonb_build_object('request_id',p_client_message_id,'refusal_reason',p_refusal_reason)) THEN
            RAISE EXCEPTION 'field_chat_completion_held' USING ERRCODE='55000';
        END IF;
        RETURN receipt;
    END IF;
    -- A different observation or prior provider attempt cannot be converted
    -- into a fresh no-quota refusal, even after its operational quota expires.
    IF EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE user_id=p_user_id AND role='user' AND client_message_id=p_client_message_id)
        OR EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences f JOIN public.scans s ON s.id=f.scan_id
            WHERE s.user_id=p_user_id AND f.client_message_id=p_client_message_id)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=p_user_id
            AND operation='insight_chat_reply' AND request_id=p_client_message_id) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    IF NOT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'field_chat_execution_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO admitted FROM public.reserve_insight_chat_send_with_context(
        p_user_id,p_conversation_id,p_scan_id,p_message_text,p_client_message_id,p_displayed_ticket,p_context_version);
    IF admitted.is_replay THEN RAISE EXCEPTION 'field_chat_completion_held' USING ERRCODE='55000'; END IF;
    INSERT INTO public.insight_chat_messages(id,conversation_id,user_id,scan_id,role,message_text,model,is_refusal,refusal_reason,safety_metadata)
        VALUES(internal.insight_chat_assistant_id(admitted.conversation_id,p_client_message_id),admitted.conversation_id,
            p_user_id,p_scan_id,'assistant',answer,NULL,TRUE,p_refusal_reason,
            pg_catalog.jsonb_build_object('request_id',p_client_message_id,'refusal_reason',p_refusal_reason));
    UPDATE public.insight_chat_conversations SET updated_at=pg_catalog.clock_timestamp()
        WHERE id=admitted.conversation_id AND user_id=p_user_id AND scan_id=p_scan_id;
    -- Return through the exact same read owner; any failure rolls back the
    -- daily slot, question, context, answer and conversation update together.
    RETURN public.get_insight_chat_turn_completion(p_user_id,p_scan_id,p_client_message_id,p_message_text,
        p_displayed_ticket,p_context_version,(admitted.message->>'id')::UUID,admitted.conversation_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admit_insight_chat_local_refusal(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_insight_chat_local_refusal(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.admit_insight_chat_local_refusal(uuid,uuid,uuid,text,uuid,jsonb,integer,text)',
 'Default-off atomic immutable question and closed local safety refusal without provider quota.');
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

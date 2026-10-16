SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Read-only recovery uses the same canonical subject/request locks as writers.
-- A fresh candidate permits only subsequent preflight, never provider dispatch.
CREATE FUNCTION public.get_insight_chat_no_admission(
    p_user_id UUID,p_scan_id UUID,p_conversation_id UUID,p_client_message_id UUID,
    p_message_text TEXT,p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE fingerprint TEXT; fence internal.insight_chat_execution_fences;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    fingerprint:=internal.insight_chat_execution_fingerprint(
        p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    IF p_conversation_id IS NULL THEN RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        p_user_id::TEXT||':insight_chat_reply:'||p_client_message_id::TEXT,0::BIGINT));
    BEGIN
        SELECT f.* INTO STRICT fence FROM internal.insight_chat_execution_fences f
            JOIN public.scans s ON s.id=f.scan_id
            WHERE s.user_id=p_user_id AND f.client_message_id=p_client_message_id FOR UPDATE OF f;
    EXCEPTION WHEN no_data_found THEN fence:=NULL;
        WHEN too_many_rows THEN RETURN pg_catalog.jsonb_build_object('status','held');
    END;
    IF fence.scan_id IS NOT NULL THEN
        IF fence.scan_id<>p_scan_id OR fence.request_sha256<>fingerprint
            OR (fence.no_admission_reason IS NOT NULL AND fence.no_admission_conversation_id<>p_conversation_id) THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        IF fence.no_admission_reason IS NULL THEN RETURN pg_catalog.jsonb_build_object('status','held'); END IF;
        RETURN pg_catalog.jsonb_build_object('status','not_admitted','context_version',1,
            'scan_id',p_scan_id,'conversation_id',p_conversation_id,'client_message_id',p_client_message_id,
            'reason',fence.no_admission_reason);
    END IF;
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=p_user_id
            AND operation='insight_chat_reply' AND request_id=p_client_message_id)
        OR EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE user_id=p_user_id
            AND (client_message_id=p_client_message_id OR safety_metadata->>'request_id'=p_client_message_id::TEXT)) THEN
        RETURN pg_catalog.jsonb_build_object('status','held');
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','fresh_candidate');
END;
$$;
REVOKE ALL ON FUNCTION public.get_insight_chat_no_admission(UUID,UUID,UUID,UUID,TEXT,JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_insight_chat_no_admission(UUID,UUID,UUID,UUID,TEXT,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.get_insight_chat_no_admission(uuid,uuid,uuid,uuid,text,jsonb,integer)',
 'Read exact permanent no-admission proof before fresh gates; a fresh candidate is not admission or dispatch authority.');
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

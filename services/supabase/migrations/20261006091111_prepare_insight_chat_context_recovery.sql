SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Read-only recovery is deliberately separate from admission. A missing turn
-- grants no quota, eligibility, new-message or provider-execution authority.
CREATE FUNCTION public.get_insight_chat_turn_context(
    p_user_id UUID, p_scan_id UUID, p_client_message_id UUID,
    p_message_text TEXT, p_displayed_ticket JSONB, p_context_version INTEGER
)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    original public.insight_chat_messages;
    saved internal.insight_chat_turn_contexts;
    normalized_text TEXT; response JSONB;
BEGIN
    PERFORM internal.require_service_role();
    -- PostgREST maps an explicit JSON null RPC argument to SQL NULL. Both
    -- representations mean the closed legacy (no displayed history) ticket.
    p_displayed_ticket:=COALESCE(p_displayed_ticket,'null'::JSONB);
    normalized_text:=pg_catalog.btrim(p_message_text);
    IF p_user_id IS NULL OR p_scan_id IS NULL OR p_client_message_id IS NULL
        OR normalized_text IS NULL OR normalized_text='' OR pg_catalog.char_length(normalized_text)>600
        OR p_context_version IS DISTINCT FROM 1 OR p_displayed_ticket IS NULL
        OR pg_catalog.octet_length(p_displayed_ticket::TEXT)>1024
        OR (p_displayed_ticket<>'null'::JSONB AND (
            pg_catalog.jsonb_typeof(p_displayed_ticket) IS DISTINCT FROM 'object'
            OR NOT p_displayed_ticket ?& ARRAY['analysis_id','state_revision','review_revision']
            OR p_displayed_ticket-ARRAY['analysis_id','state_revision','review_revision']<>'{}'::JSONB
            OR pg_catalog.jsonb_typeof(p_displayed_ticket->'analysis_id') IS DISTINCT FROM 'string'
            OR COALESCE(p_displayed_ticket->>'analysis_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            OR pg_catalog.jsonb_typeof(p_displayed_ticket->'state_revision') IS DISTINCT FROM 'number'
            OR pg_catalog.jsonb_typeof(p_displayed_ticket->'review_revision') IS DISTINCT FROM 'number'
            OR COALESCE(p_displayed_ticket->>'state_revision','')!~'^[0-9]{1,10}$'
            OR COALESCE(p_displayed_ticket->>'review_revision','')!~'^[0-9]{1,10}$')) THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    IF p_displayed_ticket<>'null'::JSONB AND (
        (p_displayed_ticket->>'analysis_id')::UUID=p_scan_id
        OR (p_displayed_ticket->>'state_revision')::BIGINT NOT BETWEEN 1 AND 2147483646
        OR (p_displayed_ticket->>'review_revision')::BIGINT NOT BETWEEN 0 AND 2147483646) THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    -- No lock upgrades: admission/merge/deletion all begin with this owner.
    PERFORM id FROM public.users WHERE id=p_user_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:subject:insight:'||p_scan_id::TEXT||':user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_scan_id AND user_id=p_user_id AND NOT is_tombstoned FOR SHARE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT m.* INTO original FROM public.insight_chat_messages m
        JOIN public.insight_chat_conversations c ON c.id=m.conversation_id AND c.scan_id=m.scan_id AND c.user_id=m.user_id
        WHERE m.scan_id=p_scan_id AND m.user_id=p_user_id AND m.client_message_id=p_client_message_id AND m.role='user'
        FOR SHARE OF c,m;
    IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('context_version',1,'found',FALSE); END IF;
    IF original.message_text IS DISTINCT FROM normalized_text THEN
        RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
    END IF;
    SELECT * INTO saved FROM internal.insight_chat_turn_contexts WHERE message_id=original.id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
    IF saved.context_version IS DISTINCT FROM p_context_version OR saved.displayed_ticket IS DISTINCT FROM p_displayed_ticket THEN
        RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
    END IF;
    -- No current history, rollout or dictionary reads on recovery. Scope comes
    -- from the joined current owner; the frozen snapshot contains no old owner.
    response:=pg_catalog.jsonb_build_object('context_version',1,'found',TRUE,
        'message',pg_catalog.jsonb_build_object('id',original.id,'conversation_id',original.conversation_id,
            'scan_id',original.scan_id,'user_id',original.user_id,'role','user',
            'client_message_id',original.client_message_id,'message_text',original.message_text),
        'context_snapshot',saved.context_snapshot);
    IF pg_catalog.octet_length(response::TEXT)>139264 THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.get_insight_chat_turn_context(UUID,UUID,UUID,TEXT,JSONB,INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_insight_chat_turn_context(UUID,UUID,UUID,TEXT,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.get_insight_chat_turn_context(uuid,uuid,uuid,text,jsonb,integer)',
     'Exact immutable Insight turn recovery without admission, quota, current authority or provider work.');

RESET statement_timeout;
RESET lock_timeout;

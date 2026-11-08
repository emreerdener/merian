SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Shared fresh-context derivation. No message, conversation, prefix, quota or
-- admission side effects belong in this helper. Its locks end with the RPC.
CREATE FUNCTION internal.prepare_current_insight_chat_context(
    p_user_id UUID,p_scan_id UUID,p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
DECLARE
    scan public.scans; history internal.observation_histories;
    evidence internal.observation_analysis_results; authority internal.observation_analysis_authorities;
    source JSONB; effective JSONB; expected_ticket JSONB; selected_species UUID; prepared JSONB;
BEGIN
    p_displayed_ticket:=COALESCE(p_displayed_ticket,'null'::JSONB);
    IF p_user_id IS NULL OR p_scan_id IS NULL
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
    -- Owner first matches history mutation/account deletion and avoids a lock
    -- upgrade after generic admission has obtained a weaker parent key lock.
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:subject:insight:'||p_scan_id::TEXT||':user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    SELECT * INTO scan FROM public.scans WHERE id=p_scan_id AND user_id=p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002';
    END IF;
    IF NOT COALESCE((SELECT chat_context_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_scan_id FOR UPDATE;
    IF FOUND THEN
        IF NOT history.selection_initialized OR history.selected_analysis_id IS NULL OR history.state_revision<1 THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO evidence FROM internal.observation_analysis_results WHERE observation_id=p_scan_id AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND OR evidence.result_snapshot->>'scan_id' IS DISTINCT FROM p_scan_id::TEXT THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        SELECT * INTO authority FROM internal.observation_analysis_authorities WHERE observation_id=p_scan_id AND analysis_id=history.selected_analysis_id;
        IF NOT FOUND OR NOT authority.review_snapshot ?& ARRAY['ai_identification_review','confirmed_species_identity',
            'confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']
            OR authority.review_snapshot-ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision',
                'confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        effective:=internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
        IF effective IS DISTINCT FROM history.active_projection THEN
            RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
        END IF;
        expected_ticket:=pg_catalog.jsonb_build_object('analysis_id',history.selected_analysis_id,
            'state_revision',history.state_revision,'review_revision',authority.review_revision);
        source:=evidence.result_snapshot||authority.review_snapshot;
    ELSE
        expected_ticket:='null'::JSONB;
        effective:=internal.scan_effective_identification(scan);
        source:=pg_catalog.to_jsonb(scan);
    END IF;
    IF p_displayed_ticket IS DISTINCT FROM expected_ticket THEN
        RAISE EXCEPTION 'field_chat_context_conflict' USING ERRCODE='40001';
    END IF;
    IF effective->>'source'='invalid' THEN RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000'; END IF;
    selected_species:=NULLIF(effective->>'species_id','')::UUID;
    source:=internal.insight_chat_context_projection(source)
        ||pg_catalog.jsonb_build_object('species_dictionary',internal.insight_chat_dictionary_context(selected_species),
            'confirmed_species',internal.insight_chat_dictionary_context(NULLIF(source->>'confirmed_species_id','')::UUID));
    prepared:=pg_catalog.jsonb_build_object('context_version',1,
        'source_kind',CASE WHEN expected_ticket='null'::JSONB THEN 'legacy_scan_v1' ELSE 'analysis_history_v1' END,
        'displayed_ticket',expected_ticket,'scan_context',source);
    IF pg_catalog.octet_length(prepared::TEXT)>131072 THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN prepared;
END;
$$;
REVOKE ALL ON FUNCTION internal.prepare_current_insight_chat_context(UUID,UUID,JSONB,INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.prepare_insight_chat_send_context(
    p_user_id UUID,p_scan_id UUID,p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN internal.prepare_current_insight_chat_context(p_user_id,p_scan_id,p_displayed_ticket,p_context_version);
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_insight_chat_send_context(UUID,UUID,JSONB,INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prepare_insight_chat_send_context(UUID,UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.prepare_insight_chat_send_context(uuid,uuid,jsonb,integer)',
     'Default-off fresh immutable Insight context preflight without message or quota admission.');

-- Exact existing-message replay remains before fresh derivation. The helper
-- runs again in this transaction: preflight never grants later admission.
CREATE OR REPLACE FUNCTION public.reserve_insight_chat_send_with_context(
    p_user_id UUID, p_conversation_id UUID, p_scan_id UUID, p_message_text TEXT,
    p_client_message_id UUID, p_displayed_ticket JSONB, p_context_version INTEGER
)
RETURNS TABLE(conversation_id UUID,message JSONB,is_replay BOOLEAN,sends_today INTEGER,context_snapshot JSONB)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s' AS $$
DECLARE
    saved internal.insight_chat_turn_contexts; admitted RECORD;
    existing_id UUID; snapshot JSONB; prefix JSONB; prepared JSONB;
    expected_ticket JSONB;
BEGIN
    PERFORM internal.require_service_role();
    p_displayed_ticket:=COALESCE(p_displayed_ticket,'null'::JSONB);
    IF p_user_id IS NULL OR p_scan_id IS NULL OR p_conversation_id IS NULL OR p_client_message_id IS NULL
        OR p_context_version IS DISTINCT FROM 1 OR p_displayed_ticket IS NULL
        OR pg_catalog.octet_length(p_displayed_ticket::TEXT)>1024 THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    -- Owner first matches history mutation/account deletion and avoids a lock
    -- upgrade after generic admission has obtained a weaker parent key lock.
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:subject:insight:'||p_scan_id::TEXT||':user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_scan_id AND user_id=p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT m.id INTO existing_id FROM public.insight_chat_messages m
        JOIN public.insight_chat_conversations c ON c.id=m.conversation_id AND c.scan_id=m.scan_id AND c.user_id=m.user_id
        WHERE m.scan_id=p_scan_id AND m.user_id=p_user_id AND m.client_message_id=p_client_message_id AND m.role='user';
    IF existing_id IS NOT NULL THEN
        SELECT * INTO saved FROM internal.insight_chat_turn_contexts WHERE message_id=existing_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
        IF saved.displayed_ticket IS DISTINCT FROM p_displayed_ticket THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        SELECT * INTO admitted FROM public.reserve_field_chat_send(p_user_id,p_conversation_id,'insight',p_scan_id,p_message_text,p_client_message_id);
        RETURN QUERY SELECT admitted.conversation_id,admitted.message,admitted.is_replay,admitted.sends_today,saved.context_snapshot;
        RETURN;
    END IF;
    prepared:=internal.prepare_current_insight_chat_context(p_user_id,p_scan_id,p_displayed_ticket,p_context_version);
    expected_ticket:=prepared->'displayed_ticket';
    -- Existing admission owns exact text, caps, cutover and conversation UUID.
    SELECT * INTO admitted FROM public.reserve_field_chat_send(p_user_id,p_conversation_id,'insight',p_scan_id,p_message_text,p_client_message_id);
    IF admitted.is_replay THEN RAISE EXCEPTION 'field_chat_context_missing' USING ERRCODE='55000'; END IF;
    SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',m.role,'text',pg_catalog.left(pg_catalog.btrim(m.message_text),900))
        ORDER BY m.created_at,m.id),'[]'::JSONB) INTO prefix
        FROM (SELECT prior.id,prior.role,prior.message_text,prior.created_at FROM public.insight_chat_messages prior
            WHERE prior.conversation_id=admitted.conversation_id AND prior.id<>(admitted.message->>'id')::UUID
            ORDER BY prior.created_at DESC,prior.id DESC LIMIT 12) m;
    snapshot:=prepared||pg_catalog.jsonb_build_object('conversation_prefix',prefix);
    IF pg_catalog.octet_length(snapshot::TEXT)>131072 THEN
        RAISE EXCEPTION 'field_chat_context_unavailable' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.insight_chat_turn_contexts(message_id,context_version,displayed_ticket,context_snapshot)
        VALUES((admitted.message->>'id')::UUID,1,expected_ticket,snapshot);
    RETURN QUERY SELECT admitted.conversation_id,admitted.message,FALSE,admitted.sends_today,snapshot;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER) TO service_role;

RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- A retained immutable turn remains protected even if fresh rollout is closed.
CREATE FUNCTION internal.insight_chat_requires_context(p_scan_id UUID)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE)
        OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan_id)
        OR EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences WHERE scan_id=p_scan_id)
        OR EXISTS(SELECT 1 FROM public.insight_chat_messages m
            JOIN internal.insight_chat_turn_contexts c ON c.message_id=m.id WHERE m.scan_id=p_scan_id);
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_requires_context(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the existing admission implementation and public signature. Only
-- trusted SQL snapshot owners may bypass the legacy wrapper, never a caller flag.
ALTER FUNCTION public.reserve_field_chat_send(UUID,UUID,TEXT,UUID,TEXT,UUID) SET SCHEMA internal;
ALTER FUNCTION internal.reserve_field_chat_send(UUID,UUID,TEXT,UUID,TEXT,UUID) RENAME TO reserve_field_chat_send_core;
REVOKE ALL ON FUNCTION internal.reserve_field_chat_send_core(UUID,UUID,TEXT,UUID,TEXT,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.reserve_field_chat_send(
    p_user_id UUID,p_conversation_id UUID,p_subject_type TEXT,p_subject_id UUID,p_message_text TEXT,p_client_message_id UUID
) RETURNS TABLE(conversation_id UUID,message JSONB,is_replay BOOLEAN,sends_today INTEGER)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_subject_type='insight' THEN
        PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_subject_id);
        IF internal.insight_chat_requires_context(p_subject_id) THEN
            RAISE EXCEPTION 'field_chat_context_required' USING ERRCODE='55000';
        END IF;
    END IF;
    RETURN QUERY SELECT * FROM internal.reserve_field_chat_send_core(
        p_user_id,p_conversation_id,p_subject_type,p_subject_id,p_message_text,p_client_message_id);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_field_chat_send(UUID,UUID,TEXT,UUID,TEXT,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send(UUID,UUID,TEXT,UUID,TEXT,UUID) TO service_role;

-- The two snapshot-owned calls (fresh and replay) already hold the same subject
-- locks and validate immutable context. Fail migration on unexpected source drift.
DO $migration$
DECLARE definition TEXT; marker CONSTANT TEXT:='public.reserve_field_chat_send(';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,marker,'')))/pg_catalog.length(marker)<>2 THEN
        RAISE EXCEPTION 'protected_chat_admission_source_drift' USING ERRCODE='55000';
    END IF;
    EXECUTE pg_catalog.replace(definition,marker,'internal.reserve_field_chat_send_core(');
END;
$migration$;

CREATE FUNCTION public.get_insight_chat_send_route(p_user_id UUID,p_scan_id UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    RETURN pg_catalog.jsonb_build_object('requires_context',internal.insight_chat_requires_context(p_scan_id));
END;
$$;
REVOKE ALL ON FUNCTION public.get_insight_chat_send_route(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_insight_chat_send_route(UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.get_insight_chat_send_route(uuid,uuid)',
 'Owner/deletion-fenced server routing for immutable Insight sends; never admission or dispatch permission.');

-- Serialize commit with enrollment BEFORE taking the quota row lock. Do not
-- acquire subject locks inside quota triggers (their row lock is already held).
ALTER FUNCTION public.finalize_ai_quota_reservation(UUID,UUID,UUID,TEXT) SET SCHEMA internal;
ALTER FUNCTION internal.finalize_ai_quota_reservation(UUID,UUID,UUID,TEXT) RENAME TO finalize_ai_quota_reservation_core;
REVOKE ALL ON FUNCTION internal.finalize_ai_quota_reservation_core(UUID,UUID,UUID,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.finalize_ai_quota_reservation(
    p_reservation_id UUID,p_user_id UUID,p_lease_token UUID,p_final_state TEXT
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE quota internal.ai_quota_reservations; observation UUID;
BEGIN
    PERFORM internal.require_service_role();
    IF p_final_state='committed' THEN
        -- Discovery only. The unchanged core reloads and validates under lock.
        SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=p_reservation_id AND user_id=p_user_id;
        IF FOUND AND quota.operation='insight_chat_reply' THEN
            observation:=quota.original_analysis_id;
            IF observation IS NULL THEN
                BEGIN
                    SELECT m.scan_id INTO STRICT observation FROM public.insight_chat_messages m
                        WHERE m.user_id=p_user_id AND m.client_message_id=quota.request_id AND m.role='user';
                EXCEPTION WHEN no_data_found THEN observation:=NULL;
                    WHEN too_many_rows THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
                END;
            END IF;
            IF observation IS NOT NULL THEN
                PERFORM internal.lock_insight_chat_execution_subject(p_user_id,observation);
                IF internal.insight_chat_requires_context(observation) AND NOT EXISTS(
                    SELECT 1 FROM internal.insight_chat_execution_fences f
                    JOIN internal.insight_chat_turn_contexts c ON c.message_id=f.message_id
                    WHERE f.scan_id=observation AND f.client_message_id=quota.request_id
                        AND f.reservation_id=p_reservation_id AND f.lease_token=p_lease_token
                        AND f.message_bound AND f.dispatch_grant_id IS NOT NULL) THEN
                    IF EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences WHERE reservation_id=p_reservation_id) THEN
                        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
                    END IF;
                    RAISE EXCEPTION 'field_chat_context_required' USING ERRCODE='55000';
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN internal.finalize_ai_quota_reservation_core(p_reservation_id,p_user_id,p_lease_token,p_final_state);
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_ai_quota_reservation(UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_ai_quota_reservation(UUID,UUID,UUID,TEXT) TO service_role;

ALTER FUNCTION public.recover_stale_field_chat_quota(UUID,TEXT,UUID,UUID,UUID) SET SCHEMA internal;
ALTER FUNCTION internal.recover_stale_field_chat_quota(UUID,TEXT,UUID,UUID,UUID) RENAME TO recover_stale_field_chat_quota_core;
REVOKE ALL ON FUNCTION internal.recover_stale_field_chat_quota_core(UUID,TEXT,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.recover_stale_field_chat_quota(
    p_user_id UUID,p_operation TEXT,p_request_id UUID,p_conversation_id UUID,p_subject_id UUID
) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF p_operation='insight_chat_reply' THEN
        PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_subject_id);
        IF internal.insight_chat_requires_context(p_subject_id) THEN RETURN FALSE; END IF;
    END IF;
    RETURN internal.recover_stale_field_chat_quota_core(p_user_id,p_operation,p_request_id,p_conversation_id,p_subject_id);
END;
$$;
REVOKE ALL ON FUNCTION public.recover_stale_field_chat_quota(UUID,TEXT,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota(UUID,TEXT,UUID,UUID,UUID) TO service_role;

-- Exact counterpart of deriveFieldChatAssistantMessageId: first 16 SHA256
-- bytes with UUIDv8/version and RFC variant bits; no mutable timestamps/order.
CREATE FUNCTION internal.insight_chat_assistant_id(p_conversation UUID,p_request UUID)
RETURNS UUID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE bytes BYTEA;
BEGIN
    bytes:=pg_catalog.substring(extensions.digest(pg_catalog.convert_to(
        'merian-field-chat-assistant-v1:'||p_conversation::TEXT||':'||p_request::TEXT,'UTF8'),'sha256'),1,16);
    bytes:=pg_catalog.set_byte(bytes,6,(pg_catalog.get_byte(bytes,6) & 15) | 128);
    bytes:=pg_catalog.set_byte(bytes,8,(pg_catalog.get_byte(bytes,8) & 63) | 128);
    RETURN pg_catalog.encode(bytes,'hex')::UUID;
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_assistant_id(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.require_settled_legacy_insight_chat(p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    -- Caller owns subject/profile locks shared with first commit and stale
    -- recovery. Unknown already-dispatched legacy work cannot coexist with a
    -- newly enrolled history; it needs its exact assistant receipt first.
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations q
        WHERE q.user_id=p_owner AND q.operation='insight_chat_reply' AND q.state='committed'
            AND (q.original_analysis_id=p_scan OR (q.original_analysis_id IS NULL AND EXISTS(
                SELECT 1 FROM public.insight_chat_messages m WHERE m.scan_id=p_scan AND m.user_id=p_owner
                    AND m.role='user' AND m.client_message_id=q.request_id)))
            AND NOT EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences f WHERE f.reservation_id=q.id)
            AND NOT EXISTS(SELECT 1 FROM public.insight_chat_messages m
                JOIN public.insight_chat_messages a ON a.id=internal.insight_chat_assistant_id(m.conversation_id,q.request_id)
                WHERE m.user_id=p_owner AND m.scan_id=p_scan AND m.role='user' AND m.client_message_id=q.request_id
                    AND a.conversation_id=m.conversation_id AND a.user_id=p_owner AND a.scan_id=p_scan
                    AND a.role='assistant' AND a.safety_metadata->>'request_id'=q.request_id::TEXT)) THEN
        RAISE EXCEPTION 'analysis_history_chat_in_progress' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_settled_legacy_insight_chat(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $migration$
DECLARE definition TEXT;
    lock_marker CONSTANT TEXT:='    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian-scan-ingestion:''||p_observation::TEXT,0::BIGINT));';
    fresh_marker CONSTANT TEXT:='    IF (SELECT enrollment_enabled AND saved_import_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('public.enroll_owned_observation_history(uuid,integer)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,lock_marker,'')))/pg_catalog.length(lock_marker)<>1
        OR (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,fresh_marker,'')))/pg_catalog.length(fresh_marker)<>1 THEN
        RAISE EXCEPTION 'protected_chat_enrollment_source_drift' USING ERRCODE='55000';
    END IF;
    -- Keep existing ownership/not-found errors; user-first locking already
    -- prevents any new chat commit while these advisories are acquired.
    definition:=pg_catalog.replace(definition,lock_marker,
        '    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian:field-chat:user:''||caller::TEXT,0::BIGINT));'
        ||pg_catalog.chr(10)||'    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''merian:field-chat:subject:insight:''||p_observation::TEXT||'':user:''||caller::TEXT,0::BIGINT));'
        ||pg_catalog.chr(10)||lock_marker);
    definition:=pg_catalog.replace(definition,fresh_marker,
        '    PERFORM internal.require_settled_legacy_insight_chat(caller,p_observation);'||pg_catalog.chr(10)||fresh_marker);
    EXECUTE definition;
END;
$migration$;

NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

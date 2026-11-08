SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- A terminal pre-admission seal is a different kind of permanent fence. It
-- cannot be upgraded into quota, message or dispatch authority, even internally.
ALTER TABLE internal.insight_chat_execution_fences
    ADD COLUMN no_admission_reason TEXT,
    ADD COLUMN no_admission_conversation_id UUID,
    ADD CONSTRAINT insight_chat_no_admission_shape CHECK (
        (no_admission_reason IS NULL AND no_admission_conversation_id IS NULL)
        OR (no_admission_reason IS NOT NULL
            AND no_admission_reason='displayed_identification_changed'
            AND no_admission_conversation_id IS NOT NULL
            AND reservation_id IS NULL AND lease_token IS NULL
            AND message_id IS NULL AND NOT message_bound
            AND dispatch_grant_id IS NULL AND dispatch_granted_at IS NULL));

CREATE OR REPLACE FUNCTION internal.guard_insight_chat_execution_fence_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF ROW(NEW.no_admission_reason,NEW.no_admission_conversation_id)
        IS DISTINCT FROM ROW(OLD.no_admission_reason,OLD.no_admission_conversation_id)
        OR ROW(NEW.scan_id,NEW.client_message_id,NEW.request_sha256,NEW.created_at)
        IS DISTINCT FROM ROW(OLD.scan_id,OLD.client_message_id,OLD.request_sha256,OLD.created_at)
        OR (OLD.reservation_id IS NOT NULL AND ROW(NEW.reservation_id,NEW.lease_token)
            IS DISTINCT FROM ROW(OLD.reservation_id,OLD.lease_token))
        OR (OLD.message_bound AND (NOT NEW.message_bound OR (NEW.message_id IS DISTINCT FROM OLD.message_id AND NEW.message_id IS NOT NULL)))
        OR (OLD.dispatch_grant_id IS NOT NULL AND ROW(NEW.dispatch_grant_id,NEW.dispatch_granted_at)
            IS DISTINCT FROM ROW(OLD.dispatch_grant_id,OLD.dispatch_granted_at))
        OR (NOT OLD.message_bound AND NEW.message_bound AND NEW.message_id IS NULL) THEN
        RAISE EXCEPTION 'field_chat_execution_immutable' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.guard_insight_chat_execution_quota()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE fence internal.insight_chat_execution_fences;
BEGIN
    IF TG_OP='UPDATE' AND OLD.operation='insight_chat_reply' AND
        EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences WHERE reservation_id=OLD.id)
        AND ROW(NEW.operation,NEW.request_id) IS DISTINCT FROM ROW(OLD.operation,OLD.request_id) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    IF NEW.operation<>'insight_chat_reply' THEN RETURN NEW; END IF;
    BEGIN
    SELECT f.* INTO STRICT fence FROM internal.insight_chat_execution_fences f
        WHERE f.reservation_id=NEW.id OR (f.client_message_id=NEW.request_id
            AND EXISTS(SELECT 1 FROM public.scans s WHERE s.id=f.scan_id AND s.user_id=NEW.user_id))
        FOR UPDATE;
    EXCEPTION WHEN no_data_found THEN RETURN NEW;
        WHEN too_many_rows THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END;
    IF fence.no_admission_reason IS NOT NULL THEN
        RAISE EXCEPTION 'field_chat_not_admitted' USING ERRCODE='55000';
    END IF;
    IF TG_OP='INSERT' AND fence.reservation_id IS NULL THEN
        IF NEW.state<>'reserved' OR NEW.attempt_count<>1 OR NOT EXISTS(
            SELECT 1 FROM public.scans WHERE id=fence.scan_id AND user_id=NEW.user_id AND NOT is_tombstoned) THEN
            RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
        END IF;
        UPDATE internal.insight_chat_execution_fences SET reservation_id=NEW.id,lease_token=NEW.lease_token
            WHERE scan_id=fence.scan_id AND client_message_id=NEW.request_id;
    ELSIF TG_OP='INSERT' OR NEW.id IS DISTINCT FROM fence.reservation_id
        OR NEW.lease_token IS DISTINCT FROM fence.lease_token OR NEW.attempt_count<>1
        OR (NEW.state='reserved' AND OLD.state<>'reserved') THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    IF NEW.state='committed' AND (TG_OP='INSERT' OR OLD.state<>'committed')
        AND (fence.dispatch_grant_id IS NULL OR fence.dispatch_granted_at IS NULL OR NOT fence.message_bound OR fence.message_id IS NULL OR NOT EXISTS(
            SELECT 1 FROM public.scans WHERE id=fence.scan_id AND user_id=NEW.user_id AND NOT is_tombstoned)
            OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=fence.scan_id)) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;

-- Called after canonical owner/scan locks, before either replay or fresh
-- context admission. Never let the unfunded snapshot core bypass a terminal seal.
CREATE FUNCTION internal.require_unsealed_insight_chat_request(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,
    p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE fence internal.insight_chat_execution_fences;
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        p_user_id::TEXT||':insight_chat_reply:'||p_client_message_id::TEXT,0::BIGINT));
    BEGIN
        SELECT f.* INTO STRICT fence FROM internal.insight_chat_execution_fences f
            JOIN public.scans s ON s.id=f.scan_id
            WHERE s.user_id=p_user_id AND f.client_message_id=p_client_message_id FOR UPDATE OF f;
    EXCEPTION WHEN no_data_found THEN RETURN;
        WHEN too_many_rows THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END;
    IF fence.scan_id IS DISTINCT FROM p_scan_id THEN
        RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
    END IF;
    IF fence.no_admission_reason IS NOT NULL THEN
        IF fence.request_sha256 IS DISTINCT FROM internal.insight_chat_execution_fingerprint(
            p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version) THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        RAISE EXCEPTION 'field_chat_not_admitted' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_unsealed_insight_chat_request(UUID,UUID,UUID,TEXT,JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE definition TEXT;
    marker CONSTANT TEXT:='    SELECT m.id INTO existing_id FROM public.insight_chat_messages m';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('public.reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,marker,'')))/pg_catalog.length(marker)<>1 THEN
        RAISE EXCEPTION 'protected_chat_seal_source_drift' USING ERRCODE='55000';
    END IF;
    EXECUTE pg_catalog.replace(definition,marker,
        '    PERFORM internal.require_unsealed_insight_chat_request(p_user_id,p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);'
        ||pg_catalog.chr(10)||marker);
END;
$migration$;

-- No client reason is accepted. Only the shared fresh-context derivation's
-- exact stale-ticket denial is sealable, after proving no admitted/attempted
-- evidence under the same locks as all writers. Everything else stays held.
CREATE FUNCTION public.seal_unadmitted_insight_chat_request(
    p_user_id UUID,p_scan_id UUID,p_conversation_id UUID,p_client_message_id UUID,
    p_message_text TEXT,p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE fingerprint TEXT; fence internal.insight_chat_execution_fences;
    denial TEXT; error_message TEXT;
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
        WHEN too_many_rows THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END;
    IF fence.scan_id IS NOT NULL THEN
        IF fence.scan_id<>p_scan_id OR fence.request_sha256<>fingerprint
            OR (fence.no_admission_reason IS NOT NULL AND fence.no_admission_conversation_id<>p_conversation_id) THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        IF fence.no_admission_reason IS NULL THEN
            RETURN pg_catalog.jsonb_build_object('status','held');
        END IF;
        denial:=fence.no_admission_reason;
    ELSE
        IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=p_user_id
                AND operation='insight_chat_reply' AND request_id=p_client_message_id)
            OR EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE user_id=p_user_id
                AND (client_message_id=p_client_message_id OR safety_metadata->>'request_id'=p_client_message_id::TEXT)) THEN
            RETURN pg_catalog.jsonb_build_object('status','held');
        END IF;
        IF NOT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
            RAISE EXCEPTION 'field_chat_execution_unavailable' USING ERRCODE='55000';
        END IF;
        BEGIN
            PERFORM internal.prepare_current_insight_chat_context(p_user_id,p_scan_id,p_displayed_ticket,p_context_version);
        EXCEPTION WHEN SQLSTATE '40001' THEN
            GET STACKED DIAGNOSTICS error_message=MESSAGE_TEXT;
            IF error_message IS DISTINCT FROM 'field_chat_context_conflict' THEN RAISE; END IF;
            denial:='displayed_identification_changed';
        END;
        IF denial IS NULL THEN RETURN pg_catalog.jsonb_build_object('status','held'); END IF;
        INSERT INTO internal.insight_chat_execution_fences(
            scan_id,client_message_id,request_sha256,no_admission_reason,no_admission_conversation_id)
            VALUES(p_scan_id,p_client_message_id,fingerprint,denial,p_conversation_id);
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','not_admitted','context_version',1,
        'scan_id',p_scan_id,'conversation_id',p_conversation_id,'client_message_id',p_client_message_id,
        'reason',denial);
END;
$$;
REVOKE ALL ON FUNCTION public.seal_unadmitted_insight_chat_request(UUID,UUID,UUID,UUID,TEXT,JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.seal_unadmitted_insight_chat_request(UUID,UUID,UUID,UUID,TEXT,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.seal_unadmitted_insight_chat_request(uuid,uuid,uuid,uuid,text,jsonb,integer)',
 'Exact request retirement after independently proven stale displayed ticket and locked absence of admission or execution; no refund or replacement authority.');
-- Account merge already owns both canonical profile locks. A retained seal
-- must not acquire another account's attempted identity as its new owner.
-- Even two seals conflict: no merged owner may choose between their identities.
CREATE FUNCTION internal.require_no_sealed_chat_merge_collision(p_source UUID,p_target UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences f
        JOIN public.scans s ON s.id=f.scan_id
        WHERE f.no_admission_reason IS NOT NULL AND s.user_id IN(p_source,p_target)
            AND (EXISTS(SELECT 1 FROM internal.ai_quota_reservations q
                WHERE q.operation='insight_chat_reply' AND q.request_id=f.client_message_id
                    AND q.user_id=CASE WHEN s.user_id=p_source THEN p_target ELSE p_source END)
                OR EXISTS(SELECT 1 FROM public.insight_chat_messages m
                    WHERE m.user_id=CASE WHEN s.user_id=p_source THEN p_target ELSE p_source END
                        AND (m.client_message_id=f.client_message_id OR m.safety_metadata->>'request_id'=f.client_message_id::TEXT))
                OR EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences other
                    JOIN public.scans other_scan ON other_scan.id=other.scan_id
                    WHERE other.client_message_id=f.client_message_id
                        AND other_scan.user_id=CASE WHEN s.user_id=p_source THEN p_target ELSE p_source END))) THEN
        RAISE EXCEPTION 'field_chat_execution_merge_conflict' USING ERRCODE='55000';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.require_no_sealed_chat_merge_collision(UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
DO $migration$
DECLARE definition TEXT;
    marker CONSTANT TEXT:='    PERFORM internal.retire_colliding_protected_chat_quotas(p_ghost_user_id,p_target_user_id);';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.perform_ghost_profile_merge(uuid,uuid)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,marker,'')))/pg_catalog.length(marker)<>1 THEN
        RAISE EXCEPTION 'protected_chat_seal_merge_source_drift' USING ERRCODE='55000';
    END IF;
    EXECUTE pg_catalog.replace(definition,marker,
        '    PERFORM internal.require_no_sealed_chat_merge_collision(p_ghost_user_id,p_target_user_id);'
        ||pg_catalog.chr(10)||marker);
END;
$migration$;

COMMENT ON COLUMN internal.insight_chat_execution_fences.no_admission_reason IS
 'Insert-only permanent pre-admission denial; no message, quota or dispatch can ever bind this request.';
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

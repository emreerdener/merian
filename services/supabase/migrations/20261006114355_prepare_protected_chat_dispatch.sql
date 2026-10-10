SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Permanent permission consumption is independent of quota/message retention.
ALTER TABLE internal.insight_chat_execution_fences
    ADD COLUMN dispatch_grant_id UUID,
    ADD COLUMN dispatch_granted_at TIMESTAMPTZ,
    ADD CONSTRAINT insight_chat_dispatch_pair CHECK (
        (dispatch_grant_id IS NULL) = (dispatch_granted_at IS NULL)),
    ADD CONSTRAINT insight_chat_dispatch_bound CHECK (
        dispatch_grant_id IS NULL OR (message_bound AND reservation_id IS NOT NULL));

CREATE OR REPLACE FUNCTION internal.guard_insight_chat_execution_fence_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF ROW(NEW.scan_id,NEW.client_message_id,NEW.request_sha256,NEW.created_at)
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
        WHERE f.reservation_id=NEW.id OR (TG_OP='INSERT' AND f.client_message_id=NEW.request_id
            AND EXISTS(SELECT 1 FROM public.scans s WHERE s.id=f.scan_id AND s.user_id=NEW.user_id))
        FOR UPDATE;
    EXCEPTION WHEN no_data_found THEN RETURN NEW;
        WHEN too_many_rows THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END;
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

CREATE OR REPLACE FUNCTION public.reserve_protected_insight_chat_quota(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,
    p_displayed_ticket JSONB,p_context_version INTEGER,p_ip_hash TEXT
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE fingerprint TEXT; fence internal.insight_chat_execution_fences; admitted RECORD;
BEGIN
    PERFORM internal.require_service_role();
    fingerprint:=internal.insight_chat_execution_fingerprint(p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    IF p_ip_hash IS NULL OR p_ip_hash!~'^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        p_user_id::TEXT||':insight_chat_reply:'||p_client_message_id::TEXT,0::BIGINT));
    SELECT * INTO fence FROM internal.insight_chat_execution_fences WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id FOR UPDATE;
    IF FOUND THEN
        IF fence.scan_id<>p_scan_id OR fence.request_sha256<>fingerprint THEN
            RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
        END IF;
        -- Exact recovery is historical, not a new lease/dispatch grant.
        RETURN pg_catalog.jsonb_build_object('status','held');
    END IF;
    IF EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences f JOIN public.scans s ON s.id=f.scan_id
        WHERE f.client_message_id=p_client_message_id AND s.user_id=p_user_id AND f.scan_id<>p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_idempotency_conflict' USING ERRCODE='23505';
    END IF;
    IF NOT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'field_chat_execution_unavailable' USING ERRCODE='55000';
    END IF;
    -- A previous unprotected message/reservation never becomes a fresh protected
    -- attempt. The generic core's own lock is acquired before this absence test.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        p_user_id::TEXT||':insight_chat_reply:'||p_client_message_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=p_user_id
        AND operation='insight_chat_reply' AND request_id=p_client_message_id)
        OR EXISTS(SELECT 1 FROM public.insight_chat_messages WHERE user_id=p_user_id AND client_message_id=p_client_message_id) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    PERFORM internal.prepare_current_insight_chat_context(p_user_id,p_scan_id,p_displayed_ticket,p_context_version);
    PERFORM internal.require_current_ai_consent(p_user_id);
    INSERT INTO internal.insight_chat_execution_fences(client_message_id,scan_id,request_sha256)
        VALUES(p_client_message_id,p_scan_id,fingerprint);
    SELECT * INTO STRICT admitted FROM internal.reserve_ai_quota_core(
        p_user_id,'insight_chat_reply',p_client_message_id,p_ip_hash,p_scan_id,FALSE,NULL,FALSE);
    IF admitted.is_replay OR admitted.attempt_count<>1 OR admitted.reservation_state<>'reserved' THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','reserved',
        'reservation_id',admitted.reservation_id,'lease_token',admitted.lease_token,
        'lease_expires_at',admitted.lease_expires_at,'model',admitted.model);
END;
$$;

-- Only the fresh return of this transaction authorizes one immediate provider
-- execution. A lost reply cannot be recovered as a reusable permission.
CREATE FUNCTION public.grant_protected_insight_chat_dispatch(
    p_user_id UUID,p_scan_id UUID,p_client_message_id UUID,p_reservation_id UUID,p_lease_token UUID
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE fence internal.insight_chat_execution_fences; quota internal.ai_quota_reservations;
    message_row public.insight_chat_messages; context_row internal.insight_chat_turn_contexts;
BEGIN
    PERFORM internal.require_service_role();
    IF p_client_message_id IS NULL OR p_reservation_id IS NULL OR p_lease_token IS NULL THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    -- Match finalization/reaping: quota precedes fence, then immutable message.
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=p_reservation_id FOR UPDATE;
    SELECT * INTO fence FROM internal.insight_chat_execution_fences
        WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id FOR UPDATE;
    IF NOT FOUND OR fence.reservation_id IS DISTINCT FROM p_reservation_id
        OR fence.lease_token IS DISTINCT FROM p_lease_token THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    IF fence.dispatch_grant_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object('status','held');
    END IF;
    IF NOT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'field_chat_execution_unavailable' USING ERRCODE='55000';
    END IF;
    IF NOT fence.message_bound OR fence.message_id IS NULL
        OR quota.id IS NULL OR quota.user_id IS DISTINCT FROM p_user_id
        OR quota.operation IS DISTINCT FROM 'insight_chat_reply' OR quota.request_id IS DISTINCT FROM p_client_message_id
        OR quota.original_analysis_id IS DISTINCT FROM p_scan_id
        OR quota.lease_token IS DISTINCT FROM p_lease_token OR quota.attempt_count<>1
        OR quota.state<>'reserved' OR quota.lease_expires_at<=pg_catalog.clock_timestamp() THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    SELECT * INTO message_row FROM public.insight_chat_messages WHERE id=fence.message_id FOR UPDATE;
    IF NOT FOUND OR message_row.user_id IS DISTINCT FROM p_user_id OR message_row.scan_id IS DISTINCT FROM p_scan_id
        OR message_row.client_message_id IS DISTINCT FROM p_client_message_id OR message_row.role IS DISTINCT FROM 'user' THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    SELECT * INTO context_row FROM internal.insight_chat_turn_contexts WHERE message_id=message_row.id FOR UPDATE;
    IF NOT FOUND OR context_row.context_snapshot->'displayed_ticket' IS DISTINCT FROM context_row.displayed_ticket
        OR context_row.context_snapshot->'context_version' IS DISTINCT FROM pg_catalog.to_jsonb(context_row.context_version)
        OR fence.request_sha256 IS DISTINCT FROM internal.insight_chat_execution_fingerprint(
            p_scan_id,p_client_message_id,message_row.message_text,context_row.displayed_ticket,context_row.context_version) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    -- Current consent is required; current selection must NOT rebase the saved context.
    PERFORM internal.require_current_ai_consent(p_user_id);
    UPDATE internal.insight_chat_execution_fences
        SET dispatch_grant_id=extensions.gen_random_uuid(),dispatch_granted_at=pg_catalog.clock_timestamp()
        WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id;
    IF public.finalize_ai_quota_reservation(p_reservation_id,p_user_id,p_lease_token,'committed') IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    RETURN pg_catalog.jsonb_build_object('status','dispatch_granted','model',quota.model);
END;
$$;
REVOKE ALL ON FUNCTION public.grant_protected_insight_chat_dispatch(UUID,UUID,UUID,UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.grant_protected_insight_chat_dispatch(UUID,UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.grant_protected_insight_chat_dispatch(uuid,uuid,uuid,uuid,uuid)',
 'One-time protected chat dispatch permission and atomic provider quota commit; replay returns no capability.');
COMMENT ON COLUMN internal.insight_chat_execution_fences.dispatch_grant_id IS
 'Permanent first-dispatch marker; unknown grant replies never authorize provider execution or retry.';
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN chat_execution_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Ownership follows the scan through merge. No duplicated user foreign key and
-- no FK to the independently pruned quota row. Message erasure retires binding,
-- not the one-attempt fence; only observation erasure removes the fence.
CREATE TABLE internal.insight_chat_execution_fences (
    client_message_id UUID NOT NULL,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    request_sha256 TEXT NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
    reservation_id UUID UNIQUE,
    lease_token UUID,
    message_id UUID UNIQUE REFERENCES public.insight_chat_messages(id) ON DELETE SET NULL,
    message_bound BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    PRIMARY KEY (scan_id,client_message_id),
    CHECK ((reservation_id IS NULL) = (lease_token IS NULL)),
    CHECK (message_id IS NULL OR (message_bound AND reservation_id IS NOT NULL))
);
CREATE INDEX insight_chat_execution_fences_request_idx ON internal.insight_chat_execution_fences(client_message_id);
ALTER TABLE internal.insight_chat_execution_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.insight_chat_execution_fences FROM PUBLIC, anon, authenticated, service_role;

-- Allow only first quota binding, first message binding, or FK-driven message
-- retirement. Neither merge nor retries rewrite immutable request evidence.
CREATE FUNCTION internal.guard_insight_chat_execution_fence_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF ROW(NEW.scan_id,NEW.client_message_id,NEW.request_sha256,NEW.created_at)
        IS DISTINCT FROM ROW(OLD.scan_id,OLD.client_message_id,OLD.request_sha256,OLD.created_at)
        OR (OLD.reservation_id IS NOT NULL AND ROW(NEW.reservation_id,NEW.lease_token)
            IS DISTINCT FROM ROW(OLD.reservation_id,OLD.lease_token))
        OR (OLD.message_bound AND (NOT NEW.message_bound OR (NEW.message_id IS DISTINCT FROM OLD.message_id AND NEW.message_id IS NOT NULL)))
        OR (NOT OLD.message_bound AND NEW.message_bound AND NEW.message_id IS NULL) THEN
        RAISE EXCEPTION 'field_chat_execution_immutable' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_insight_chat_execution_fence_update() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_insight_chat_execution_fence_update BEFORE UPDATE ON internal.insight_chat_execution_fences
FOR EACH ROW EXECUTE FUNCTION internal.guard_insight_chat_execution_fence_update();

CREATE FUNCTION internal.insight_chat_execution_fingerprint(
    p_scan_id UUID,p_client_message_id UUID,p_message_text TEXT,p_displayed_ticket JSONB,p_context_version INTEGER
) RETURNS TEXT LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
    p_displayed_ticket:=COALESCE(p_displayed_ticket,'null'::JSONB);
    IF p_scan_id IS NULL OR p_client_message_id IS NULL OR p_context_version IS DISTINCT FROM 1
        OR p_message_text IS NULL OR pg_catalog.btrim(p_message_text) IS DISTINCT FROM p_message_text
        OR pg_catalog.char_length(p_message_text) NOT BETWEEN 1 AND 600
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
    RETURN pg_catalog.encode(extensions.digest(pg_catalog.convert_to(pg_catalog.jsonb_build_object(
        'scan_id',p_scan_id,'client_message_id',p_client_message_id,'message_text',p_message_text,
        'displayed_ticket',p_displayed_ticket,'context_version',1)::TEXT,'UTF8'),'sha256'),'hex');
END;
$$;
REVOKE ALL ON FUNCTION internal.insight_chat_execution_fingerprint(UUID,UUID,TEXT,JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;

-- All protected mutation owners acquire the same owner/subject/deletion locks.
CREATE FUNCTION internal.lock_insight_chat_execution_subject(p_user_id UUID,p_scan_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF p_user_id IS NULL OR p_scan_id IS NULL THEN
        RAISE EXCEPTION 'field_chat_invalid_request' USING ERRCODE='22023';
    END IF;
    PERFORM id FROM public.users WHERE id=p_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian:field-chat:subject:insight:'||p_scan_id::TEXT||':user:'||p_user_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan_id::TEXT,0::BIGINT));
    PERFORM id FROM public.scans WHERE id=p_scan_id AND user_id=p_user_id AND NOT is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan_id) THEN
        RAISE EXCEPTION 'field_chat_subject_not_found' USING ERRCODE='P0002';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_insight_chat_execution_subject(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Generic quota callers must not bypass this fence by reopening a failed,
-- refunded, expired or already-pruned protected request. No higher-order locks
-- are taken in this trigger: quota callers already own user/reservation locks.
CREATE FUNCTION internal.guard_insight_chat_execution_quota()
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
        AND (NOT fence.message_bound OR fence.message_id IS NULL OR NOT EXISTS(
            SELECT 1 FROM public.scans WHERE id=fence.scan_id AND user_id=NEW.user_id AND NOT is_tombstoned)
            OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=fence.scan_id)) THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_insight_chat_execution_quota() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_insight_chat_execution_quota BEFORE INSERT OR UPDATE ON internal.ai_quota_reservations
FOR EACH ROW EXECUTE FUNCTION internal.guard_insight_chat_execution_quota();

CREATE FUNCTION internal.erase_detached_insight_chat_execution()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF NEW.user_id IS NULL OR NEW.is_tombstoned THEN
        DELETE FROM internal.insight_chat_execution_fences WHERE scan_id=NEW.id;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.erase_detached_insight_chat_execution() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER erase_detached_insight_chat_execution AFTER UPDATE OF user_id,is_tombstoned ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.erase_detached_insight_chat_execution();

CREATE FUNCTION public.reserve_protected_insight_chat_quota(
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
    RETURN pg_catalog.jsonb_build_object('status','reserved','quota',pg_catalog.to_jsonb(admitted));
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_protected_insight_chat_quota(UUID,UUID,UUID,TEXT,JSONB,INTEGER,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_protected_insight_chat_quota(UUID,UUID,UUID,TEXT,JSONB,INTEGER,TEXT) TO service_role;

CREATE FUNCTION public.reserve_protected_insight_chat_send_with_context(
    p_user_id UUID,p_conversation_id UUID,p_scan_id UUID,p_message_text TEXT,p_client_message_id UUID,
    p_displayed_ticket JSONB,p_context_version INTEGER,p_reservation_id UUID,p_lease_token UUID
) RETURNS TABLE(conversation_id UUID,message JSONB,is_replay BOOLEAN,sends_today INTEGER,context_snapshot JSONB)
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE fingerprint TEXT; fence internal.insight_chat_execution_fences; quota internal.ai_quota_reservations; admitted RECORD;
BEGIN
    PERFORM internal.require_service_role();
    fingerprint:=internal.insight_chat_execution_fingerprint(p_scan_id,p_client_message_id,p_message_text,p_displayed_ticket,p_context_version);
    PERFORM internal.lock_insight_chat_execution_subject(p_user_id,p_scan_id);
    -- Quota-before-fence matches the finalizer/reaper trigger and avoids
    -- inversion with their quota row locks. Owner lock serializes admission.
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=p_reservation_id FOR UPDATE;
    SELECT * INTO fence FROM internal.insight_chat_execution_fences WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id FOR UPDATE;
    IF NOT FOUND OR fence.scan_id<>p_scan_id OR fence.request_sha256<>fingerprint
        OR p_reservation_id IS NULL OR p_lease_token IS NULL
        OR fence.reservation_id IS DISTINCT FROM p_reservation_id OR fence.lease_token IS DISTINCT FROM p_lease_token THEN
        RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
    END IF;
    IF fence.message_bound THEN
        IF fence.message_id IS NULL THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000'; END IF;
        SELECT * INTO admitted FROM public.reserve_insight_chat_send_with_context(
            p_user_id,p_conversation_id,p_scan_id,p_message_text,p_client_message_id,p_displayed_ticket,p_context_version);
        IF NOT admitted.is_replay OR (admitted.message->>'id')::UUID IS DISTINCT FROM fence.message_id THEN
            RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
        END IF;
    ELSE
        IF NOT COALESCE((SELECT chat_execution_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
            RAISE EXCEPTION 'field_chat_execution_unavailable' USING ERRCODE='55000';
        END IF;
        IF quota.id IS NULL OR quota.user_id<>p_user_id OR quota.request_id<>p_client_message_id
            OR quota.operation<>'insight_chat_reply' OR quota.lease_token<>p_lease_token OR quota.attempt_count<>1
            OR quota.state<>'reserved' OR quota.lease_expires_at<=pg_catalog.clock_timestamp() THEN
            RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000';
        END IF;
        SELECT * INTO admitted FROM public.reserve_insight_chat_send_with_context(
            p_user_id,p_conversation_id,p_scan_id,p_message_text,p_client_message_id,p_displayed_ticket,p_context_version);
        IF admitted.is_replay THEN RAISE EXCEPTION 'field_chat_execution_held' USING ERRCODE='55000'; END IF;
        UPDATE internal.insight_chat_execution_fences SET message_id=(admitted.message->>'id')::UUID,message_bound=TRUE
            WHERE scan_id=p_scan_id AND client_message_id=p_client_message_id;
    END IF;
    RETURN QUERY SELECT admitted.conversation_id,admitted.message,admitted.is_replay,admitted.sends_today,admitted.context_snapshot;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_protected_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER,UUID,UUID)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_protected_insight_chat_send_with_context(UUID,UUID,UUID,TEXT,UUID,JSONB,INTEGER,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.reserve_protected_insight_chat_quota(uuid,uuid,uuid,text,jsonb,integer,text)',
 'Default-off one-attempt Insight quota admission; exact replay never grants another execution.'),
('service_role','public.reserve_protected_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer,uuid,uuid)',
 'Atomically bind immutable chat context to the original protected quota fence.');

-- Merging two accounts can collide with an already existing legacy quota
-- UUID. Retire BOTH operational rows if either is protected, retaining charged
-- committed/failed counters and every scan-owned fence. No winner gains a lease.
CREATE FUNCTION internal.retire_colliding_protected_chat_quotas(p_source UUID,p_target UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE item RECORD;
BEGIN
    FOR item IN
        SELECT q.id,q.state FROM internal.ai_quota_reservations q
        WHERE q.operation='insight_chat_reply' AND q.user_id IN(p_source,p_target)
          AND EXISTS(SELECT 1 FROM internal.ai_quota_reservations other
              WHERE other.operation=q.operation AND other.request_id=q.request_id
                AND other.user_id=CASE WHEN q.user_id=p_source THEN p_target ELSE p_source END)
          AND EXISTS(SELECT 1 FROM internal.insight_chat_execution_fences f
              JOIN internal.ai_quota_reservations protected ON protected.id=f.reservation_id
              WHERE protected.operation=q.operation AND protected.request_id=q.request_id
                AND protected.user_id IN(p_source,p_target))
        ORDER BY q.id FOR UPDATE OF q
    LOOP
        IF item.state='reserved' THEN PERFORM internal.release_ai_quota_reservation_counters(item.id); END IF;
        DELETE FROM internal.ai_quota_reservations WHERE id=item.id;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION internal.retire_colliding_protected_chat_quotas(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $migration$
DECLARE definition TEXT; marker CONSTANT TEXT:='    PERFORM internal.merge_ghost_chat_conversations(';
BEGIN
    definition:=pg_catalog.pg_get_functiondef('internal.perform_ghost_profile_merge(uuid,uuid)'::REGPROCEDURE);
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,marker,'')))/pg_catalog.length(marker)<>1 THEN
        RAISE EXCEPTION 'protected_chat_merge_source_drift' USING ERRCODE='55000';
    END IF;
    EXECUTE pg_catalog.replace(definition,marker,
        '    PERFORM internal.retire_colliding_protected_chat_quotas(p_ghost_user_id,p_target_user_id);'
        ||pg_catalog.chr(10)||marker);
END;
$migration$;

COMMENT ON TABLE internal.insight_chat_execution_fences IS
 'Private scan-owned one-attempt authority retained across quota pruning and message erasure; no question text or provider response. HTTP dispatch remains unconnected.';
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

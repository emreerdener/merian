SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private lifecycle only. No provider adapter or public-copy permission is exposed.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_moderation_enabled BOOLEAN NOT NULL DEFAULT FALSE;
INSERT INTO internal.ai_quota_policies(operation,effective_plan,model,allowed,enabled,policy_version,daily_bucket,daily_limit,user_rate_bucket,user_window_seconds,user_window_limit,ip_rate_bucket,ip_window_seconds,ip_window_limit)
SELECT 'observation_photo_publication_moderation',effective_plan,'gemini-2.5-flash',allowed,FALSE,1,
    'observation_photo_publication_moderation:'||effective_plan,daily_limit,user_rate_bucket,user_window_seconds,user_window_limit,ip_rate_bucket,ip_window_seconds,ip_window_limit
FROM internal.ai_quota_policies WHERE operation='explore_audio_moderation';

CREATE TABLE internal.observation_photo_moderations (
    operation_id UUID NOT NULL REFERENCES internal.observation_publication_intents(operation_id) ON DELETE CASCADE,
    media_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    analysis_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    quota_request_id UUID NOT NULL UNIQUE DEFAULT extensions.gen_random_uuid(),
    source JSONB NOT NULL CHECK(pg_catalog.octet_length(source::TEXT)<=1024),
    policy_version TEXT NOT NULL DEFAULT 'photo_publication_v1' CHECK(policy_version='photo_publication_v1'),
    provider TEXT NOT NULL DEFAULT 'gemini' CHECK(provider='gemini'),
    model TEXT NOT NULL DEFAULT 'gemini-2.5-flash' CHECK(model='gemini-2.5-flash'),
    processor_permission TEXT NOT NULL DEFAULT 'google_gemini' CHECK(processor_permission='google_gemini'),
    PRIMARY KEY(operation_id,media_id)
);
CREATE INDEX observation_photo_moderations_observation_idx ON internal.observation_photo_moderations(observation_id);
CREATE TABLE internal.observation_photo_moderation_attempts (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    operation_id UUID NOT NULL,
    media_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    predecessor_id UUID,
    attempt_count INTEGER NOT NULL CHECK(attempt_count>0),
    quota JSONB NOT NULL CHECK(pg_catalog.octet_length(quota::TEXT)<=4096 AND NOT quota?'lease_token'),
    lease_token UUID,
    lease_hash TEXT NOT NULL CHECK(lease_hash ~ '^[0-9a-f]{64}$'),
    state TEXT NOT NULL CHECK(state IN ('reserved','dispatched','approved','rejected','unknown_execution','cancelled')),
    dispatch_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.now(),
    FOREIGN KEY(operation_id,media_id) REFERENCES internal.observation_photo_moderations(operation_id,media_id) ON DELETE CASCADE,
    UNIQUE NULLS NOT DISTINCT(operation_id,media_id,predecessor_id),
    CHECK((state IN ('reserved','dispatched'))=(lease_token IS NOT NULL)),
    CHECK(state NOT IN ('dispatched','approved','rejected','unknown_execution') OR dispatch_expires_at IS NOT NULL)
);
CREATE UNIQUE INDEX observation_photo_moderation_quota_attempt_idx ON internal.observation_photo_moderation_attempts((quota->>'reservation_id'),attempt_count);
ALTER TABLE internal.observation_photo_moderations ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_photo_moderation_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_photo_moderations,internal.observation_photo_moderation_attempts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_photo_moderation BEFORE INSERT OR UPDATE ON internal.observation_photo_moderations FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_photo_moderation_update BEFORE UPDATE ON internal.observation_photo_moderations FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();
CREATE TRIGGER guard_observation_photo_moderation_attempt BEFORE INSERT OR UPDATE ON internal.observation_photo_moderation_attempts FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE FUNCTION internal.guard_publication_moderation_attempt_update() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF (to_jsonb(NEW)-ARRAY['state','lease_token','dispatch_expires_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['state','lease_token','dispatch_expires_at'])
        OR OLD.state NOT IN ('reserved','dispatched')
        OR (OLD.state='reserved' AND NEW.state NOT IN ('dispatched','cancelled'))
        OR (OLD.state='dispatched' AND NEW.state NOT IN ('approved','rejected','unknown_execution'))
        OR (OLD.state='dispatched' AND NEW.dispatch_expires_at IS DISTINCT FROM OLD.dispatch_expires_at)
        OR (NEW.state='dispatched' AND NEW.lease_token IS DISTINCT FROM OLD.lease_token) THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_publication_moderation_attempt_update() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_moderation_attempt_update BEFORE UPDATE ON internal.observation_photo_moderation_attempts FOR EACH ROW EXECUTE FUNCTION internal.guard_publication_moderation_attempt_update();

CREATE FUNCTION internal.publication_moderation_receipt(p_attempt UUID) RETURNS JSONB LANGUAGE SQL SECURITY DEFINER SET search_path='' AS $$
    SELECT jsonb_build_object('schema_version',1,'attempt_id',a.id,'operation_id',a.operation_id,'media_id',a.media_id,
        'state',a.state,'quota',a.quota,'lease_token',a.lease_token,'dispatch_expires_at',a.dispatch_expires_at,
        'source',m.source,'policy_version',m.policy_version,'provider',m.provider,'model',m.model,'processor_permission',m.processor_permission)
    FROM internal.observation_photo_moderation_attempts a JOIN internal.observation_photo_moderations m USING(operation_id,media_id) WHERE a.id=p_attempt;
$$;
REVOKE ALL ON FUNCTION internal.publication_moderation_receipt(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.admit_publication_photo_moderation(p_owner UUID,p_observation UUID,p_operation UUID,p_media UUID,p_predecessor UUID,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE prepared JSONB; source JSONB; job internal.observation_photo_moderations; prior internal.observation_photo_moderation_attempts;
    admitted RECORD; new_attempt UUID;
BEGIN
    PERFORM internal.require_service_role();
    prepared:=internal.revalidate_observation_publication_intent(p_owner,p_observation,p_operation);
    IF (SELECT publication_moderation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT value INTO source FROM jsonb_array_elements(prepared->'sources') WHERE value->>'media_id'=p_media::TEXT;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO job FROM internal.observation_photo_moderations WHERE operation_id=p_operation AND media_id=p_media;
    IF NOT FOUND THEN
        IF p_predecessor IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        INSERT INTO internal.observation_photo_moderations(operation_id,media_id,observation_id,analysis_id,owner_id,source)
        VALUES(p_operation,p_media,p_observation,(prepared#>>'{request,analysis_id}')::UUID,p_owner,source) RETURNING * INTO job;
    END IF;
    IF job.owner_id IS DISTINCT FROM p_owner OR job.observation_id IS DISTINCT FROM p_observation OR job.source IS DISTINCT FROM source THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- Replay a particular admitted attempt, never silently launch a successor.
    SELECT * INTO prior FROM internal.observation_photo_moderation_attempts
    WHERE operation_id=p_operation AND media_id=p_media AND predecessor_id IS NOT DISTINCT FROM p_predecessor;
    IF FOUND THEN RETURN internal.publication_moderation_receipt(prior.id); END IF;
    IF p_predecessor IS NOT NULL THEN
        SELECT * INTO prior FROM internal.observation_photo_moderation_attempts WHERE id=p_predecessor AND operation_id=p_operation AND media_id=p_media;
        IF NOT FOUND OR prior.state NOT IN ('cancelled','unknown_execution') THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    END IF;
    PERFORM internal.require_current_ai_consent(p_owner,job.processor_permission);
    -- Correlation lives in this private job. Original analysis quota identities
    -- are fenced for identification only; do not borrow their bypass settings.
    SELECT * INTO STRICT admitted FROM internal.reserve_ai_quota_core(p_owner,'observation_photo_publication_moderation',job.quota_request_id,p_ip_hash,NULL,FALSE,3,FALSE);
    IF admitted.reservation_state<>'reserved' OR admitted.model IS DISTINCT FROM job.model
        OR admitted.complimentary_client_scan_id IS NOT NULL OR admitted.original_analysis_id IS NOT NULL THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.observation_photo_moderation_attempts(operation_id,media_id,observation_id,predecessor_id,attempt_count,quota,lease_token,lease_hash,state)
    VALUES(p_operation,p_media,p_observation,p_predecessor,admitted.attempt_count,to_jsonb(admitted)-'lease_token',admitted.lease_token,
        encode(extensions.digest(admitted.lease_token::TEXT,'sha256'),'hex'),'reserved') RETURNING id INTO new_attempt;
    RETURN internal.publication_moderation_receipt(new_attempt);
END;
$$;
REVOKE ALL ON FUNCTION internal.admit_publication_photo_moderation(UUID,UUID,UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.dispatch_publication_photo_moderation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; job internal.observation_photo_moderations;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF attempt.state<>'reserved' THEN RETURN jsonb_build_object('dispatch_allowed',FALSE,'receipt',internal.publication_moderation_receipt(p_attempt)); END IF;
    PERFORM internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    IF (SELECT publication_moderation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT job FROM internal.observation_photo_moderations WHERE operation_id=attempt.operation_id AND media_id=attempt.media_id;
    PERFORM internal.require_current_ai_consent(p_owner,job.processor_permission);
    PERFORM public.finalize_ai_quota_reservation((attempt.quota->>'reservation_id')::UUID,p_owner,p_token,'committed');
    UPDATE internal.observation_photo_moderation_attempts SET state='dispatched',dispatch_expires_at=clock_timestamp()+INTERVAL '2 minutes' WHERE id=p_attempt;
    RETURN jsonb_build_object('dispatch_allowed',TRUE,'receipt',internal.publication_moderation_receipt(p_attempt));
END;
$$;
REVOKE ALL ON FUNCTION internal.dispatch_publication_photo_moderation(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.complete_publication_photo_moderation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID,p_decision TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; reservation internal.ai_quota_reservations;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF attempt.state=p_decision THEN RETURN internal.publication_moderation_receipt(p_attempt); END IF;
    IF attempt.state<>'dispatched' OR attempt.dispatch_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    SELECT * INTO reservation FROM internal.ai_quota_reservations WHERE id=(attempt.quota->>'reservation_id')::UUID FOR UPDATE;
    IF NOT FOUND OR reservation.state<>'committed' OR reservation.user_id IS DISTINCT FROM p_owner
        OR reservation.lease_token IS DISTINCT FROM p_token OR reservation.attempt_count<>attempt.attempt_count THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.observation_photo_moderation_attempts SET state=p_decision,lease_token=NULL WHERE id=p_attempt;
    RETURN internal.publication_moderation_receipt(p_attempt);
END;
$$;
REVOKE ALL ON FUNCTION internal.complete_publication_photo_moderation(UUID,UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Before dispatch, cancellation is provably unexecuted. After dispatch, only
-- expiry can resolve uncertainty; no speculative refund or approval is allowed.
CREATE FUNCTION internal.retire_publication_photo_moderation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF attempt.state NOT IN ('reserved','dispatched') THEN RETURN internal.publication_moderation_receipt(p_attempt); END IF;
    IF attempt.state='dispatched' AND attempt.dispatch_expires_at>clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    -- Generic quota retention is shorter than observation history. Once an old
    -- reservation has been pruned, private state still proves whether dispatch
    -- occurred; there is nothing left to refund or mutate in the quota ledger.
    PERFORM id FROM internal.ai_quota_reservations WHERE id=(attempt.quota->>'reservation_id')::UUID FOR UPDATE;
    IF FOUND THEN
        PERFORM public.finalize_ai_quota_reservation((attempt.quota->>'reservation_id')::UUID,p_owner,p_token,CASE WHEN attempt.state='reserved' THEN 'refunded' ELSE 'failed' END);
    END IF;
    UPDATE internal.observation_photo_moderation_attempts SET state=CASE WHEN state='reserved' THEN 'cancelled' ELSE 'unknown_execution' END,lease_token=NULL WHERE id=p_attempt;
    RETURN internal.publication_moderation_receipt(p_attempt);
END;
$$;
REVOKE ALL ON FUNCTION internal.retire_publication_photo_moderation(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.erase_publication_photo_moderation() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE owner UUID;
BEGIN
    -- Parent may already be invisible during cascades; the reservation still
    -- supplies its owner. There is no complimentary credit link to settle.
    SELECT user_id INTO owner FROM internal.ai_quota_reservations WHERE id=(OLD.quota->>'reservation_id')::UUID;
    PERFORM id FROM public.users WHERE id=owner FOR UPDATE;
    IF FOUND AND OLD.state='reserved' AND EXISTS(SELECT 1 FROM internal.ai_quota_reservations
        WHERE id=(OLD.quota->>'reservation_id')::UUID AND state='reserved' AND lease_token=OLD.lease_token) THEN
        PERFORM public.finalize_ai_quota_reservation((OLD.quota->>'reservation_id')::UUID,owner,OLD.lease_token,'refunded');
    END IF;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION internal.erase_publication_photo_moderation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER erase_publication_photo_moderation BEFORE DELETE ON internal.observation_photo_moderation_attempts FOR EACH ROW EXECUTE FUNCTION internal.erase_publication_photo_moderation();
CREATE FUNCTION internal.fence_publication_photo_moderation() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_photo_moderations WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_publication_photo_moderation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fence_publication_photo_moderation AFTER INSERT ON internal.scan_deletion_tombstones FOR EACH ROW EXECUTE FUNCTION internal.fence_publication_photo_moderation();

RESET statement_timeout;
RESET lock_timeout;

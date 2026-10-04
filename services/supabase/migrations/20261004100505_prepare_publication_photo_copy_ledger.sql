SET lock_timeout='5s';
SET statement_timeout='2min';

-- Staging only: no publication binding, API grant or scheduler. Every object is
-- permanently registered before I/O and eligible for erasure after ten minutes.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_copy_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.publication_photo_objects (
    object_id UUID PRIMARY KEY,
    available_at TIMESTAMPTZ NOT NULL,
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    erased_at TIMESTAMPTZ,
    CHECK((claim_token IS NULL)=(claim_expires_at IS NULL))
);
CREATE INDEX publication_photo_objects_pending ON internal.publication_photo_objects(available_at) WHERE erased_at IS NULL;
CREATE TABLE internal.observation_photo_copies (
    attempt_id UUID PRIMARY KEY REFERENCES internal.observation_photo_moderation_attempts(id) ON DELETE CASCADE,
    object_id UUID NOT NULL UNIQUE REFERENCES internal.publication_photo_objects(object_id),
    observation_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    source JSONB NOT NULL CHECK(pg_catalog.octet_length(source::TEXT)<=1024),
    lease_token UUID NOT NULL DEFAULT extensions.gen_random_uuid(),
    expires_at TIMESTAMPTZ NOT NULL,
    ready_at TIMESTAMPTZ
);
CREATE INDEX observation_photo_copies_observation_idx ON internal.observation_photo_copies(observation_id);
ALTER TABLE internal.publication_photo_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_photo_copies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.publication_photo_objects,internal.observation_photo_copies FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_photo_copy BEFORE INSERT OR UPDATE ON internal.observation_photo_copies FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();

CREATE FUNCTION internal.guard_publication_photo_object() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF TG_OP='DELETE' OR NEW.object_id IS DISTINCT FROM OLD.object_id
        OR NEW.available_at>OLD.available_at OR OLD.erased_at IS NOT NULL THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_publication_photo_object() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_photo_object BEFORE UPDATE OR DELETE ON internal.publication_photo_objects FOR EACH ROW EXECUTE FUNCTION internal.guard_publication_photo_object();
CREATE FUNCTION internal.guard_publication_photo_copy() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
    IF (to_jsonb(NEW)-'ready_at') IS DISTINCT FROM (to_jsonb(OLD)-'ready_at') OR OLD.ready_at IS NOT NULL OR NEW.ready_at IS NULL THEN
        RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_publication_photo_copy() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_photo_copy BEFORE UPDATE ON internal.observation_photo_copies FOR EACH ROW EXECUTE FUNCTION internal.guard_publication_photo_copy();
CREATE FUNCTION internal.enqueue_publication_photo_erasure() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()) WHERE object_id=OLD.object_id AND erased_at IS NULL;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION internal.enqueue_publication_photo_erasure() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER enqueue_publication_photo_erasure BEFORE DELETE ON internal.observation_photo_copies FOR EACH ROW EXECUTE FUNCTION internal.enqueue_publication_photo_erasure();

CREATE FUNCTION internal.authorize_publication_photo_copy(p_owner UUID,p_observation UUID,p_attempt UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; job internal.observation_photo_moderations; proof JSONB; result JSONB; prepared JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    prepared:=internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    IF (SELECT publication_copy_enabled AND publication_moderation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT job FROM internal.observation_photo_moderations WHERE operation_id=attempt.operation_id AND media_id=attempt.media_id;
    SELECT p.proof,r.result INTO proof,result FROM internal.observation_photo_execution_proofs p JOIN internal.observation_photo_execution_results r USING(attempt_id) WHERE p.attempt_id=p_attempt;
    IF NOT FOUND OR attempt.state<>'approved' OR job.owner_id IS DISTINCT FROM p_owner
        OR job.observation_id IS DISTINCT FROM p_observation OR internal.valid_publication_photo_result(result) IS NOT TRUE
        OR result->>'decision' IS DISTINCT FROM 'approved' OR proof->'source' IS DISTINCT FROM job.source
        OR proof->>'policy_version' IS DISTINCT FROM job.policy_version
        OR proof->>'policy_sha256' IS DISTINCT FROM 'b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9'
        OR job.source->>'content_type' NOT IN ('image/jpeg','image/png')
        OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(prepared->'sources') s WHERE s.value=job.source) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN job.source;
END;
$$;
REVOKE ALL ON FUNCTION internal.authorize_publication_photo_copy(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.reserve_publication_photo_copy(p_owner UUID,p_observation UUID,p_attempt UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE source JSONB; saved internal.observation_photo_copies; registry internal.publication_photo_objects; candidate UUID; deadline TIMESTAMPTZ;
BEGIN
    source:=internal.authorize_publication_photo_copy(p_owner,p_observation,p_attempt);
    SELECT * INTO saved FROM internal.observation_photo_copies WHERE attempt_id=p_attempt FOR UPDATE;
    IF FOUND THEN
        SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=saved.object_id FOR UPDATE;
        IF saved.source IS DISTINCT FROM source OR saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
            OR saved.expires_at<=clock_timestamp() OR registry.available_at<=clock_timestamp() OR registry.claim_token IS NOT NULL OR registry.erased_at IS NOT NULL THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN to_jsonb(saved);
    END IF;
    deadline:=clock_timestamp()+INTERVAL '10 minutes';
    LOOP
        candidate:=extensions.gen_random_uuid();
        IF candidate IN (p_owner,p_observation,p_attempt,(source->>'media_id')::UUID,(source->>'object_id')::UUID) THEN CONTINUE; END IF;
        INSERT INTO internal.publication_photo_objects(object_id,available_at) VALUES(candidate,deadline) ON CONFLICT DO NOTHING;
        EXIT WHEN FOUND;
    END LOOP;
    INSERT INTO internal.observation_photo_copies(attempt_id,object_id,observation_id,owner_id,source,expires_at)
    VALUES(p_attempt,candidate,p_observation,p_owner,source,deadline) RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;
REVOKE ALL ON FUNCTION internal.reserve_publication_photo_copy(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.complete_publication_photo_copy(p_owner UUID,p_observation UUID,p_attempt UUID,p_object UUID,p_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE source JSONB; saved internal.observation_photo_copies; registry internal.publication_photo_objects;
BEGIN
    source:=internal.authorize_publication_photo_copy(p_owner,p_observation,p_attempt);
    SELECT * INTO saved FROM internal.observation_photo_copies WHERE attempt_id=p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF ROW(saved.object_id,saved.lease_token,saved.owner_id,saved.observation_id,saved.source) IS DISTINCT FROM ROW(p_object,p_token,p_owner,p_observation,source) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=p_object FOR UPDATE;
    IF saved.expires_at<=clock_timestamp() OR registry.available_at<=clock_timestamp() OR registry.claim_token IS NOT NULL OR registry.erased_at IS NOT NULL THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF saved.ready_at IS NULL THEN UPDATE internal.observation_photo_copies SET ready_at=clock_timestamp() WHERE attempt_id=p_attempt RETURNING * INTO saved; END IF;
    RETURN to_jsonb(saved);
END;
$$;
REVOKE ALL ON FUNCTION internal.complete_publication_photo_copy(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Cleanup ignores current publication gates/review authority. Keep the receipt
-- as a no-reallocation fence until its parent is erased. No bound copies exist.
CREATE FUNCTION internal.abandon_publication_photo_copy(p_owner UUID,p_observation UUID,p_attempt UUID,p_object UUID,p_token UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_photo_copies;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO saved FROM internal.observation_photo_copies WHERE attempt_id=p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF ROW(saved.object_id,saved.lease_token,saved.owner_id,saved.observation_id) IS DISTINCT FROM ROW(p_object,p_token,p_owner,p_observation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()) WHERE object_id=p_object AND erased_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.abandon_publication_photo_copy(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.claim_publication_photo_erasure() RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.publication_photo_objects WHERE erased_at IS NULL AND available_at<=clock_timestamp()
        AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp()) ORDER BY available_at,object_id LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE internal.publication_photo_objects SET claim_token=extensions.gen_random_uuid(),claim_expires_at=clock_timestamp()+INTERVAL '2 minutes'
        WHERE object_id=saved.object_id RETURNING * INTO saved;
    RETURN to_jsonb(saved);
END;
$$;
REVOKE ALL ON FUNCTION internal.claim_publication_photo_erasure() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.finish_publication_photo_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.publication_photo_objects WHERE object_id=p_object FOR UPDATE;
    IF NOT FOUND OR saved.erased_at IS NOT NULL OR p_claim IS NULL OR saved.claim_token IS DISTINCT FROM p_claim OR saved.claim_expires_at<=clock_timestamp() OR p_success IS NULL THEN RETURN FALSE; END IF;
    UPDATE internal.publication_photo_objects SET claim_token=NULL,claim_expires_at=NULL,erased_at=CASE WHEN p_success THEN clock_timestamp() ELSE NULL END WHERE object_id=p_object;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.finish_publication_photo_erasure(UUID,UUID,BOOLEAN) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;

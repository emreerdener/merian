SET lock_timeout='5s';
SET statement_timeout='2min';

-- Historical provider decisions only, not container, note, copy or publication
-- permission. Future copy execution must verify the exact bytes again.
CREATE TABLE internal.observation_publication_moderation_outcomes (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_operations(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('photos_approved','needs_action')),
    reason TEXT,
    attempt_ids UUID[] NOT NULL CHECK(cardinality(attempt_ids) BETWEEN 1 AND 6),
    finalized_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK((state='photos_approved' AND reason IS NULL AND array_position(attempt_ids,NULL) IS NULL)
        OR (state='needs_action' AND reason IS NOT NULL AND reason IN ('photo_rejected','unknown_execution','cancelled')))
);
ALTER TABLE internal.observation_publication_moderation_outcomes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_moderation_outcomes FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_moderation_outcome BEFORE INSERT OR UPDATE ON internal.observation_publication_moderation_outcomes
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_publication_moderation_outcome_update BEFORE UPDATE ON internal.observation_publication_moderation_outcomes
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

-- Even a future private successor caller cannot reopen a settled operation.
-- Use the same parent lock as admission, completion, finalization and deletion.
CREATE FUNCTION internal.guard_settled_publication_attempt() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE owner UUID;
BEGIN
    SELECT owner_id INTO STRICT owner FROM internal.observation_photo_moderations
        WHERE operation_id=NEW.operation_id AND media_id=NEW.media_id;
    PERFORM internal.lock_owned_observation_evidence(owner,NEW.observation_id);
    IF EXISTS(SELECT 1 FROM internal.observation_publication_moderation_outcomes WHERE operation_id=NEW.operation_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_settled_publication_attempt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_settled_publication_attempt BEFORE INSERT ON internal.observation_photo_moderation_attempts
FOR EACH ROW EXECUTE FUNCTION internal.guard_settled_publication_attempt();

-- Quota attempt_count restarts when a reservation is pruned. Causal links,
-- not billing counters or timestamps, identify the current attempt.
CREATE FUNCTION internal.latest_publication_photo_attempt(p_operation UUID,p_media UUID) RETURNS UUID
LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE leaves UUID[];
BEGIN
    SELECT pg_catalog.array_agg(a.id) INTO leaves FROM internal.observation_photo_moderation_attempts a
        WHERE a.operation_id=p_operation AND a.media_id=p_media
        AND NOT EXISTS(SELECT 1 FROM internal.observation_photo_moderation_attempts child
            WHERE child.operation_id=p_operation AND child.media_id=p_media AND child.predecessor_id=a.id);
    IF pg_catalog.cardinality(leaves)>1 OR (leaves IS NULL AND EXISTS(
        SELECT 1 FROM internal.observation_photo_moderation_attempts WHERE operation_id=p_operation AND media_id=p_media)) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN leaves[1];
END;
$$;
REVOKE ALL ON FUNCTION internal.latest_publication_photo_attempt(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.finalize_publication_photo_moderation(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE outcome internal.observation_publication_moderation_outcomes;
    intent internal.observation_publication_intents; source JSONB;
    attempt internal.observation_photo_moderation_attempts;
    job internal.observation_photo_moderations; proof JSONB; result JSONB;
    ids UUID[]:='{}'::UUID[]; states TEXT[]:='{}'::TEXT[]; reason TEXT; state TEXT;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_publication_operations
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO outcome FROM internal.observation_publication_moderation_outcomes WHERE operation_id=p_operation;
    IF FOUND THEN
        RETURN pg_catalog.jsonb_build_object('finalized',TRUE,'status',outcome.state,'reason',outcome.reason);
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    SELECT * INTO STRICT intent FROM internal.observation_publication_intents WHERE operation_id=p_operation;
    -- No implicit cancellation/refund or loss of late completion ownership.
    -- Include predecessors, not just the newest member of each media chain.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_moderation_attempts a
        WHERE a.operation_id=p_operation AND a.state IN ('reserved','dispatched')) THEN
        RETURN '{"finalized":false}'::JSONB;
    END IF;
    FOR source IN SELECT value FROM pg_catalog.jsonb_array_elements(intent.sources) LOOP
        SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts
            WHERE id=internal.latest_publication_photo_attempt(p_operation,(source->>'media_id')::UUID) FOR UPDATE;
        ids:=pg_catalog.array_append(ids,attempt.id);
        states:=pg_catalog.array_append(states,attempt.state);
        IF attempt.id IS NULL THEN CONTINUE; END IF;
        SELECT * INTO STRICT job FROM internal.observation_photo_moderations
            WHERE operation_id=p_operation AND media_id=attempt.media_id;
        IF job.owner_id IS DISTINCT FROM p_owner OR job.observation_id IS DISTINCT FROM p_observation
            OR job.analysis_id IS DISTINCT FROM intent.analysis_id OR job.source IS DISTINCT FROM source THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        IF attempt.state IN ('approved','rejected') THEN
            SELECT p.proof,r.result INTO proof,result FROM internal.observation_photo_execution_proofs p
                JOIN internal.observation_photo_execution_results r USING(attempt_id)
                WHERE p.attempt_id=attempt.id AND p.observation_id=p_observation AND r.observation_id=p_observation;
            IF NOT FOUND OR internal.valid_publication_photo_result(result) IS NOT TRUE
                OR result->>'decision' IS DISTINCT FROM attempt.state
                OR proof IS DISTINCT FROM pg_catalog.jsonb_build_object('schema_version',1,'policy_version',job.policy_version,
                    'policy_sha256','b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9',
                    'request_sha256',proof->'request_sha256','provider',job.provider,'model',job.model,
                    'processor_permission',job.processor_permission,'source',source)
                OR pg_catalog.jsonb_typeof(proof->'request_sha256') IS DISTINCT FROM 'string'
                OR (proof->>'request_sha256') !~ '^[0-9a-f]{64}$'
                OR proof->'source' IS DISTINCT FROM source
                OR proof->>'policy_version' IS DISTINCT FROM job.policy_version
                OR proof->>'policy_sha256' IS DISTINCT FROM 'b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9'
                OR proof->>'provider' IS DISTINCT FROM job.provider OR proof->>'model' IS DISTINCT FROM job.model
                OR proof->>'processor_permission' IS DISTINCT FROM job.processor_permission THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
            END IF;
        END IF;
    END LOOP;
    -- Failures dominate unattempted photos: do not spend on the remaining cohort
    -- after a durable refusal. Old terminal predecessors do not poison a newer
    -- explicitly admitted result. No successor can be created after settlement.
    reason:=CASE WHEN 'rejected'=ANY(states) THEN 'photo_rejected'
        WHEN 'unknown_execution'=ANY(states) THEN 'unknown_execution'
        WHEN 'cancelled'=ANY(states) THEN 'cancelled' ELSE NULL END;
    IF reason IS NULL AND (pg_catalog.array_position(states,NULL) IS NOT NULL OR NOT 'approved'=ALL(states)) THEN
        RETURN '{"finalized":false}'::JSONB;
    END IF;
    state:=CASE WHEN reason IS NULL THEN 'photos_approved' ELSE 'needs_action' END;
    INSERT INTO internal.observation_publication_moderation_outcomes(operation_id,owner_id,observation_id,state,reason,attempt_ids)
        VALUES(p_operation,p_owner,p_observation,state,reason,ids);
    DELETE FROM internal.observation_publication_work WHERE operation_id=p_operation;
    RETURN pg_catalog.jsonb_build_object('finalized',TRUE,'status',state,'reason',reason);
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_publication_photo_moderation(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_publication_photo_moderation(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.finalize_publication_photo_moderation(uuid,uuid,uuid,uuid)','Settle historical photo decisions from durable evidence and retire only the exact accepted moderation work.');

CREATE OR REPLACE FUNCTION public.read_owned_observation_publication_status(p_owner UUID,p_observation UUID,p_operation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE accepted internal.observation_publication_operations; state TEXT;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO accepted FROM internal.observation_publication_operations
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT o.state INTO state FROM internal.observation_publication_moderation_outcomes o WHERE operation_id=p_operation;
    -- Both approval and admission are historical; neither asserts current
    -- visibility. Provider approval says nothing about public notes or containers.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN state:='admitted';
    ELSIF state IS NOT NULL THEN NULL;
    ELSIF EXISTS(SELECT 1 FROM internal.observation_publication_work WHERE operation_id=p_operation AND work_expires_at>clock_timestamp()) THEN state:='processing';
    ELSE state:='accepted'; END IF;
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'operation_id',p_operation,
        'observation_id',p_observation,'analysis_id',accepted.receipt->'analysis_id','status',state);
END;
$$;
REVOKE ALL ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) TO service_role;
CREATE OR REPLACE FUNCTION public.read_publication_moderation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE sources JSONB; source JSONB; attempt UUID; result JSONB:='[]'::JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    SELECT i.sources INTO STRICT sources FROM internal.observation_publication_intents i
        JOIN internal.observation_publication_operations o USING(operation_id)
        WHERE i.operation_id=p_operation AND o.owner_id=p_owner AND o.observation_id=p_observation;
    FOR source IN SELECT value FROM pg_catalog.jsonb_array_elements(sources) LOOP
        attempt:=internal.latest_publication_photo_attempt(p_operation,(source->>'media_id')::UUID);
        result:=result||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('media_id',source->'media_id',
            'attempt',CASE WHEN attempt IS NULL THEN NULL ELSE internal.publication_moderation_receipt(attempt) END));
    END LOOP;
    -- Original provider tokens are private recovery capabilities, never a client
    -- response or a new dispatch permit. Sources remain in exact consent order.
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admit_publication_moderation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID,p_media UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE ip TEXT; attempt UUID;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    SELECT o.ip_hash INTO ip FROM internal.observation_publication_operations o
        JOIN internal.observation_publication_intents i USING(operation_id)
        WHERE o.operation_id=p_operation AND o.owner_id=p_owner AND o.observation_id=p_observation
            AND EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(i.sources) s WHERE s->>'media_id'=p_media::TEXT);
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    attempt:=internal.latest_publication_photo_attempt(p_operation,p_media);
    -- Any existing attempt is recovery, including cancelled/unknown. This API
    -- cannot request a successor, even after retirement or generic quota pruning.
    IF attempt IS NOT NULL THEN RETURN internal.publication_moderation_receipt(attempt); END IF;
    IF (SELECT publication_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- The trusted execution owner must verify the entire immutable source cohort
    -- and reject unsupported/metadata-bearing containers BEFORE this quota call.
    RETURN internal.admit_publication_photo_moderation(p_owner,p_observation,p_operation,p_media,NULL,ip);
END;
$$;

REVOKE ALL ON FUNCTION public.read_publication_moderation_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.admit_publication_moderation_work(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_publication_moderation_work(UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.admit_publication_moderation_work(UUID,UUID,UUID,UUID,UUID) TO service_role;
RESET statement_timeout;
RESET lock_timeout;

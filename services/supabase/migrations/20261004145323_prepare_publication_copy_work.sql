SET lock_timeout='5s';
SET statement_timeout='2min';

-- Moderation settlement retires moderation work. Copy recovery has its own
-- lease; neither lease is a provider permit or permission to publish a note.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_copy_execution_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_copy_work (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_moderation_outcomes(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    work_token UUID,
    work_expires_at TIMESTAMPTZ,
    recover_after TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT publication_copy_work_lease_pair CHECK((work_token IS NULL)=(work_expires_at IS NULL))
);
CREATE INDEX observation_publication_copy_work_due ON internal.observation_publication_copy_work(recover_after,operation_id);
ALTER TABLE internal.observation_publication_copy_work ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_copy_work FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_copy_work BEFORE INSERT OR UPDATE ON internal.observation_publication_copy_work
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();

CREATE FUNCTION internal.seed_publication_copy_work() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF NEW.state='photos_approved' AND NOT EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=NEW.operation_id) THEN
        INSERT INTO internal.observation_publication_copy_work(operation_id,owner_id,observation_id)
        VALUES(NEW.operation_id,NEW.owner_id,NEW.observation_id);
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.seed_publication_copy_work() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER seed_publication_copy_work AFTER INSERT ON internal.observation_publication_moderation_outcomes
FOR EACH ROW EXECUTE FUNCTION internal.seed_publication_copy_work();
INSERT INTO internal.observation_publication_copy_work(operation_id,owner_id,observation_id)
SELECT operation_id,owner_id,observation_id FROM internal.observation_publication_moderation_outcomes o
WHERE state='photos_approved' AND NOT EXISTS(SELECT 1 FROM internal.observation_photo_publications p WHERE p.operation_id=o.operation_id);

CREATE FUNCTION internal.finish_publication_copy_work() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_publication_copy_work WHERE operation_id=NEW.operation_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.finish_publication_copy_work() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER finish_publication_copy_work AFTER INSERT ON internal.observation_photo_publications
FOR EACH ROW EXECUTE FUNCTION internal.finish_publication_copy_work();

-- Immutable recovery facts only. Do not require current publication authority
-- here: a future executor must recover/clean up a denied operation as well.
CREATE FUNCTION internal.publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE outcome internal.observation_publication_moderation_outcomes;
    intent internal.observation_publication_intents; source JSONB; ordinal BIGINT;
    attempt internal.observation_photo_moderation_attempts; job internal.observation_photo_moderations;
    cohort JSONB:='[]'::JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT o.* INTO outcome FROM internal.observation_publication_moderation_outcomes o
        JOIN internal.observation_publication_operations accepted USING(operation_id)
        WHERE o.operation_id=p_operation AND o.owner_id=p_owner AND o.observation_id=p_observation
            AND accepted.owner_id=p_owner AND accepted.observation_id=p_observation;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO STRICT intent FROM internal.observation_publication_intents WHERE operation_id=p_operation;
    IF outcome.state<>'photos_approved' OR intent.owner_id IS DISTINCT FROM p_owner OR intent.observation_id IS DISTINCT FROM p_observation
        OR pg_catalog.cardinality(outcome.attempt_ids)<>pg_catalog.jsonb_array_length(intent.sources) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    FOR source,ordinal IN SELECT value,ordinality FROM pg_catalog.jsonb_array_elements(intent.sources) WITH ORDINALITY LOOP
        SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=outcome.attempt_ids[ordinal];
        IF NOT FOUND OR attempt.operation_id IS DISTINCT FROM p_operation OR attempt.observation_id IS DISTINCT FROM p_observation
            OR attempt.media_id IS DISTINCT FROM (source->>'media_id')::UUID OR attempt.state<>'approved'
            OR attempt.id IS DISTINCT FROM internal.latest_publication_photo_attempt(p_operation,(source->>'media_id')::UUID) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        SELECT * INTO job FROM internal.observation_photo_moderations WHERE operation_id=p_operation AND media_id=attempt.media_id;
        IF NOT FOUND OR job.owner_id IS DISTINCT FROM p_owner OR job.observation_id IS DISTINCT FROM p_observation
            OR job.analysis_id IS DISTINCT FROM intent.analysis_id OR job.source IS DISTINCT FROM source THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        cohort:=cohort||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('attempt_id',attempt.id,'source',source));
    END LOOP;
    -- No notes, provider leases, quota receipts, address hash or public URLs.
    RETURN cohort;
END;
$$;
REVOKE ALL ON FUNCTION internal.publication_copy_cohort(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_publication_copy_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE work internal.observation_publication_copy_work;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO work FROM internal.observation_publication_copy_work
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_work IS NULL OR work.work_token IS DISTINCT FROM p_work OR work.work_expires_at<=clock_timestamp() THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_publication_copy_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.list_publication_copy_work() RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT publication_copy_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(candidate)) FROM (
        SELECT owner_id,observation_id,operation_id FROM internal.observation_publication_copy_work
        WHERE recover_after<=clock_timestamp() AND (work_expires_at IS NULL OR work_expires_at<=clock_timestamp())
        ORDER BY recover_after,operation_id LIMIT 10
    ) candidate),'[]'::JSONB);
END;
$$;
CREATE FUNCTION public.claim_publication_copy_work(p_owner UUID,p_observation UUID,p_operation UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE work internal.observation_publication_copy_work; cohort JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT publication_copy_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    cohort:=internal.publication_copy_cohort(p_owner,p_observation,p_operation);
    SELECT * INTO work FROM internal.observation_publication_copy_work
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND OR work.recover_after>clock_timestamp() OR work.work_expires_at>clock_timestamp() THEN
        RETURN '{"claimed":false}'::JSONB;
    END IF;
    UPDATE internal.observation_publication_copy_work SET work_token=gen_random_uuid(),work_expires_at=clock_timestamp()+INTERVAL '120 seconds'
        WHERE operation_id=p_operation RETURNING * INTO work;
    RETURN pg_catalog.jsonb_build_object('claimed',TRUE,'owner_id',p_owner,'observation_id',p_observation,
        'operation_id',p_operation,'work_token',work.work_token,'work_expires_at',work.work_expires_at,'cohort',cohort);
END;
$$;
CREATE FUNCTION public.read_publication_copy_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_copy_work(p_owner,p_observation,p_operation,p_work);
    RETURN internal.publication_copy_cohort(p_owner,p_observation,p_operation);
END;
$$;
CREATE FUNCTION public.release_publication_copy_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_copy_work(p_owner,p_observation,p_operation,p_work);
    UPDATE internal.observation_publication_copy_work SET work_token=NULL,work_expires_at=NULL,
        recover_after=clock_timestamp()+INTERVAL '60 seconds' WHERE operation_id=p_operation;
END;
$$;

REVOKE ALL ON FUNCTION public.list_publication_copy_work() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.claim_publication_copy_work(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_publication_copy_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.release_publication_copy_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_publication_copy_work() TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_publication_copy_work(UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_publication_copy_work(UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_publication_copy_work(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.list_publication_copy_work()','Bounded hints for independently gated copy recovery after settled photo approval.'),
('service_role','public.claim_publication_copy_work(uuid,uuid,uuid)','Claim separate recovery work for the exact ordered settled photo cohort; no copy or provider authority.'),
('service_role','public.read_publication_copy_work(uuid,uuid,uuid,uuid)','Recover only the accepted ordered causal-leaf cohort under a live copy work token.'),
('service_role','public.release_publication_copy_work(uuid,uuid,uuid,uuid)','Release the exact live copy work token without changing immutable staging deadlines or funding.');
RESET statement_timeout;
RESET lock_timeout;

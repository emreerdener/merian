SET lock_timeout='5s';
SET statement_timeout='2min';

-- Orchestration leases are separate from immutable intake and provider attempts.
-- No scheduler, provider dispatch, quota, public copy or binding is enabled here.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_execution_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_work (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_operations(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    work_token UUID,
    work_expires_at TIMESTAMPTZ,
    recover_after TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT publication_work_lease_pair CHECK((work_token IS NULL)=(work_expires_at IS NULL))
);
CREATE INDEX observation_publication_work_due ON internal.observation_publication_work(recover_after,operation_id);
ALTER TABLE internal.observation_publication_work ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_work FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_publication_work BEFORE INSERT OR UPDATE ON internal.observation_publication_work
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();

CREATE FUNCTION internal.seed_publication_operation_work() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    INSERT INTO internal.observation_publication_work(operation_id,owner_id,observation_id)
    VALUES(NEW.operation_id,NEW.owner_id,NEW.observation_id);
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.seed_publication_operation_work() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER seed_publication_operation_work AFTER INSERT ON internal.observation_publication_operations
FOR EACH ROW EXECUTE FUNCTION internal.seed_publication_operation_work();
INSERT INTO internal.observation_publication_work(operation_id,owner_id,observation_id)
SELECT operation_id,owner_id,observation_id FROM internal.observation_publication_operations o
WHERE NOT EXISTS(SELECT 1 FROM internal.observation_photo_publications p WHERE p.operation_id=o.operation_id);

-- The authoritative binding transaction removes discovery eligibility. Its
-- immutable receipt remains the sole evidence of historical public admission.
CREATE FUNCTION internal.finish_publication_operation_work() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_publication_work WHERE operation_id=NEW.operation_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.finish_publication_operation_work() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER finish_publication_operation_work AFTER INSERT ON internal.observation_photo_publications
FOR EACH ROW EXECUTE FUNCTION internal.finish_publication_operation_work();

CREATE FUNCTION public.list_observation_publication_work() RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT publication_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Hints only: never take a child lock before locking the owner/observation.
    RETURN COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(candidate)) FROM (
        SELECT owner_id,observation_id,operation_id FROM internal.observation_publication_work
        WHERE recover_after<=clock_timestamp() AND (work_expires_at IS NULL OR work_expires_at<=clock_timestamp())
        ORDER BY recover_after,operation_id LIMIT 10
    ) candidate),'[]'::JSONB);
END;
$$;

CREATE FUNCTION public.claim_observation_publication_work(p_owner UUID,p_observation UUID,p_operation UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE work internal.observation_publication_work; accepted internal.observation_publication_operations;
    intent internal.observation_publication_intents;
BEGIN
    PERFORM internal.require_service_role();
    IF (SELECT publication_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO accepted FROM internal.observation_publication_operations
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO work FROM internal.observation_publication_work
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND OR work.recover_after>clock_timestamp() OR work.work_expires_at>clock_timestamp() THEN
        RETURN pg_catalog.jsonb_build_object('claimed',FALSE);
    END IF;
    SELECT * INTO STRICT intent FROM internal.observation_publication_intents WHERE operation_id=p_operation;
    UPDATE internal.observation_publication_work SET work_token=gen_random_uuid(),
        work_expires_at=clock_timestamp()+INTERVAL '120 seconds'
        WHERE operation_id=p_operation RETURNING * INTO work;
    -- Edge-private recovery context, not permission to execute an external step.
    -- Fresh execution must revalidate source/review/consent and separate provider
    -- attempts. In particular this claim cannot renew an uncertain dispatch.
    RETURN pg_catalog.jsonb_build_object('claimed',TRUE,'owner_id',p_owner,
        'observation_id',p_observation,'operation_id',p_operation,'work_token',work.work_token,
        'work_expires_at',work.work_expires_at,'request',intent.request,
        'sources',intent.sources,'ip_hash',accepted.ip_hash);
END;
$$;

CREATE FUNCTION internal.assert_publication_operation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE work internal.observation_publication_work;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO work FROM internal.observation_publication_work
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_work IS NULL OR work.work_token IS DISTINCT FROM p_work OR work.work_expires_at<=clock_timestamp() THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_publication_operation_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.release_observation_publication_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
    PERFORM internal.require_service_role();
    -- Releasing existing orchestration work remains possible after gates close;
    -- it never changes an attempt, grants authority or settles provider funding.
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    UPDATE internal.observation_publication_work SET work_token=NULL,work_expires_at=NULL,
        recover_after=clock_timestamp()+INTERVAL '60 seconds' WHERE operation_id=p_operation;
END;
$$;

CREATE FUNCTION public.read_owned_observation_publication_status(p_owner UUID,p_observation UUID,p_operation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE accepted internal.observation_publication_operations; state TEXT;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO accepted FROM internal.observation_publication_operations
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    -- Admission is historical. It does NOT assert that a post is still visible,
    -- confirmed, eligible, or unrevoked; those read projections remain separate.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN state:='admitted';
    ELSIF EXISTS(SELECT 1 FROM internal.observation_publication_work WHERE operation_id=p_operation AND work_expires_at>clock_timestamp()) THEN state:='processing';
    ELSE state:='accepted'; END IF;
    -- Safe for a future authenticated owner endpoint. Never expose worker data.
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'operation_id',p_operation,
        'observation_id',p_observation,'analysis_id',accepted.receipt->'analysis_id','status',state);
END;
$$;

REVOKE ALL ON FUNCTION public.list_observation_publication_work() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.claim_observation_publication_work(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.release_observation_publication_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.list_observation_publication_work() TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_observation_publication_work(UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_observation_publication_work(UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.list_observation_publication_work()','Bounded publication work discovery hints, never provider or public-copy authority.'),
('service_role','public.claim_observation_publication_work(uuid,uuid,uuid)','Acquire an exact accepted-operation orchestration lease and immutable private recovery context.'),
('service_role','public.release_observation_publication_work(uuid,uuid,uuid,uuid)','Release only the current live orchestration token without changing provider attempts or billing.'),
('service_role','public.read_owned_observation_publication_status(uuid,uuid,uuid)','Read sanitized owner-scoped historical admission or current orchestration status.');
RESET statement_timeout;
RESET lock_timeout;

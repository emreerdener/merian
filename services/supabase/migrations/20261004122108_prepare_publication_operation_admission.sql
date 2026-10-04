SET lock_timeout='5s';
SET statement_timeout='2min';

-- Durable intake only. No provider, storage, binding or worker dispatch here.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_operation_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_operations (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_intents(operation_id) ON DELETE CASCADE,
    observation_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    ip_hash TEXT NOT NULL CHECK(ip_hash ~ '^[0-9a-f]{64}$'),
    admitted_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    receipt JSONB NOT NULL CHECK(pg_catalog.octet_length(receipt::TEXT)<=1024)
);
CREATE INDEX observation_publication_operations_owner_idx ON internal.observation_publication_operations(owner_id,admitted_at);
CREATE INDEX observation_publication_operations_observation_idx ON internal.observation_publication_operations(observation_id);
ALTER TABLE internal.observation_publication_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_operations FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_publication_operation BEFORE INSERT OR UPDATE ON internal.observation_publication_operations
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_publication_operation_update BEFORE UPDATE ON internal.observation_publication_operations
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

CREATE FUNCTION public.admit_owned_observation_publication(p_owner UUID,p_request JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; operation UUID; prepared JSONB;
    saved internal.observation_publication_operations; admitted TIMESTAMPTZ; receipt JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR pg_catalog.jsonb_typeof(p_request) IS DISTINCT FROM 'object'
        OR pg_catalog.octet_length(p_request::TEXT)>4096
        OR pg_catalog.jsonb_typeof(p_request->'observation_id') IS DISTINCT FROM 'string'
        OR p_request->>'observation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.jsonb_typeof(p_request->'operation_id') IS DISTINCT FROM 'string'
        OR p_request->>'operation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR p_ip_hash IS NULL OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation:=(p_request->>'observation_id')::UUID; operation:=(p_request->>'operation_id')::UUID;
    -- Owner lock also serializes the bounded intake across different observations.
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    SELECT * INTO saved FROM internal.observation_publication_operations WHERE operation_id=operation;
    IF FOUND THEN
        -- Reuse the exact immutable request validator; it enforces owner and full
        -- request equality before returning historical evidence. No fresh I/O.
        prepared:=internal.prepare_observation_publication_intent(p_owner,p_request);
        IF saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM observation THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN saved.receipt;
    END IF;
    IF (SELECT publication_operation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Bounded rolling intake, not provider quota or a scan-credit reservation.
    -- Exact replay remains available even when the limit or rollout gate closes.
    IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_publication_operations
        WHERE owner_id=p_owner AND admitted_at>clock_timestamp()-INTERVAL '24 hours' LIMIT 8) recent)>=8 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    prepared:=internal.prepare_observation_publication_intent(p_owner,p_request);
    -- A private historical intent can predate this intake. It is not fresh
    -- authorization to enqueue after authority, source, taxonomy or gates changed.
    PERFORM internal.revalidate_observation_publication_intent(p_owner,observation,operation);
    admitted:=clock_timestamp();
    receipt:=pg_catalog.jsonb_build_object('schema_version',1,'operation_id',operation,
        'observation_id',observation,'analysis_id',prepared#>'{request,analysis_id}',
        'status','accepted','admitted_at',admitted);
    INSERT INTO internal.observation_publication_operations(operation_id,observation_id,owner_id,ip_hash,admitted_at,receipt)
    VALUES(operation,observation,p_owner,p_ip_hash,admitted,receipt);
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.admit_owned_observation_publication(UUID,JSONB,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_owned_observation_publication(UUID,JSONB,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.admit_owned_observation_publication(uuid,jsonb,text)','Persist exact owner-approved publication intent and immutable intake receipt before external I/O; no moderation or publication permission.');

CREATE FUNCTION internal.fence_publication_operation() RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    DELETE FROM internal.observation_publication_operations WHERE observation_id=NEW.scan_id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.fence_publication_operation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fence_publication_operation AFTER INSERT ON internal.scan_deletion_tombstones
FOR EACH ROW EXECUTE FUNCTION internal.fence_publication_operation();

RESET statement_timeout;
RESET lock_timeout;

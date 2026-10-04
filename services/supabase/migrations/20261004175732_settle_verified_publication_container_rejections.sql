SET lock_timeout='5s';
SET statement_timeout='2min';
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_container_settlement_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_publication_container_attestations (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_operations(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    attestation JSONB NOT NULL,
    attested_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK(jsonb_typeof(attestation)='object' AND octet_length(attestation::TEXT)<=2048)
);
ALTER TABLE internal.observation_publication_container_attestations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_container_attestations FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_container_attestation BEFORE INSERT OR UPDATE ON internal.observation_publication_container_attestations
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_publication_container_attestation_update BEFORE UPDATE ON internal.observation_publication_container_attestations
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

ALTER TABLE internal.observation_publication_moderation_outcomes DROP CONSTRAINT publication_moderation_outcome_evidence,
ADD CONSTRAINT publication_moderation_outcome_evidence CHECK (
    (state='photos_approved' AND reason IS NULL AND cardinality(attempt_ids) BETWEEN 1 AND 6 AND array_position(attempt_ids,NULL) IS NULL)
    OR (state='needs_action' AND reason IS NOT NULL AND reason IN ('photo_rejected','unknown_execution','cancelled') AND cardinality(attempt_ids) BETWEEN 1 AND 6)
    OR (state='needs_action' AND reason IS NOT NULL AND reason IN ('unsupported_source_type','public_container_rejected') AND cardinality(attempt_ids)=0)
);

-- SQL cannot inspect bytes. Only the verified-byte service execution owner may
-- attest this fixed policy decision; clients have no call or table privilege.
CREATE FUNCTION public.finalize_publication_container_rejection(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID,p_attestation JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE intent internal.observation_publication_intents;
    saved internal.observation_publication_container_attestations;
    outcome internal.observation_publication_moderation_outcomes;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_publication_operations WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO STRICT intent FROM internal.observation_publication_intents WHERE operation_id=p_operation;
    IF p_attestation IS NULL OR pg_catalog.octet_length(p_attestation::TEXT)>2048
        OR p_attestation IS DISTINCT FROM pg_catalog.jsonb_build_object('schema_version',1,'policy_version','public_photo_container_v1','source',p_attestation->'source')
        OR (p_attestation#>>'{source,content_type}') NOT IN ('image/jpeg','image/png')
        OR (SELECT count(*) FROM pg_catalog.jsonb_array_elements(intent.sources) s WHERE s=p_attestation->'source')<>1 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN
        PERFORM internal.bind_approved_publication_photo_cohort(p_owner,p_observation,p_operation);
        RETURN '{"finalized":true,"status":"admitted","reason":null}'::JSONB;
    END IF;
    SELECT * INTO outcome FROM internal.observation_publication_moderation_outcomes WHERE operation_id=p_operation;
    IF FOUND THEN
        SELECT * INTO saved FROM internal.observation_publication_container_attestations WHERE operation_id=p_operation;
        IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
            OR saved.attestation IS DISTINCT FROM p_attestation OR outcome.reason IS DISTINCT FROM 'public_container_rejected'
            OR outcome.state IS DISTINCT FROM 'needs_action' OR outcome.attempt_ids IS DISTINCT FROM '{}'::UUID[] THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN '{"finalized":true,"status":"needs_action","reason":"public_container_rejected"}'::JSONB;
    END IF;
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    IF (SELECT publication_container_settlement_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Any original provider attempt retains its completion/retirement ownership.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_moderation_attempts WHERE operation_id=p_operation)
        OR EXISTS(SELECT 1 FROM internal.observation_publication_copy_cohorts WHERE operation_id=p_operation)
        OR EXISTS(SELECT 1 FROM internal.observation_photo_copies c JOIN internal.observation_photo_moderation_attempts a ON a.id=c.attempt_id WHERE a.operation_id=p_operation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    INSERT INTO internal.observation_publication_container_attestations(operation_id,owner_id,observation_id,attestation)
        VALUES(p_operation,p_owner,p_observation,p_attestation);
    INSERT INTO internal.observation_publication_moderation_outcomes(operation_id,owner_id,observation_id,state,reason,attempt_ids)
        VALUES(p_operation,p_owner,p_observation,'needs_action','public_container_rejected','{}'::UUID[]);
    DELETE FROM internal.observation_publication_work WHERE operation_id=p_operation;
    RETURN '{"finalized":true,"status":"needs_action","reason":"public_container_rejected"}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_publication_container_rejection(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_publication_container_rejection(UUID,UUID,UUID,UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.finalize_publication_container_rejection(uuid,uuid,uuid,uuid,jsonb)','Store a verified-byte fixed-policy container rejection for an exact original source before any provider attempt, without quota or copy authority.');
RESET statement_timeout;
RESET lock_timeout;

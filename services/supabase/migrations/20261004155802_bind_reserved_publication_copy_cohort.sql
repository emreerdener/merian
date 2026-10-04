SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_copy_binding_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Exact reservation facade around the existing atomic publication writer. No
-- client supplies media URLs, alternate attempts, public notes or object IDs.
CREATE FUNCTION public.bind_publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE reservation JSONB; expected UUID[]; published internal.observation_photo_publications; receipt JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    -- A committed writer retires work and advances authority. Lost responses
    -- recover the original receipt even when gates close or authority changes.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN
        receipt:=internal.bind_approved_publication_photo_cohort(p_owner,p_observation,p_operation);
    ELSE
    IF (SELECT publication_copy_binding_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.authorize_publication_copy_cohort(p_owner,p_observation,p_operation,p_work);
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    IF reservation IS NULL OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(reservation->'copies') c WHERE c.value->>'ready_at' IS NULL) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_publication_copy_registry(reservation);
    receipt:=internal.bind_approved_publication_photo_cohort(p_owner,p_observation,p_operation);
    END IF;
    -- Replay must also belong to the immutable reservation, without imposing
    -- current work, authority, readiness or expiry requirements on history.
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    SELECT pg_catalog.array_agg((value->>'object_id')::UUID ORDER BY ordinality) INTO expected
        FROM pg_catalog.jsonb_array_elements(reservation->'copies') WITH ORDINALITY;
    IF expected IS NULL OR pg_catalog.cardinality(expected) NOT BETWEEN 1 AND 6
        OR (SELECT count(DISTINCT value) FROM unnest(expected) value)<>pg_catalog.cardinality(expected) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO published FROM internal.observation_photo_publications WHERE operation_id=p_operation;
    -- The older writer can discover approved attempts. Its entire transaction
    -- must roll back unless it bound exactly the settled reserved ordered cohort.
    IF NOT FOUND OR published.object_ids IS DISTINCT FROM expected OR published.receipt IS DISTINCT FROM receipt
        OR (SELECT a.receipt FROM internal.observation_community_admissions a WHERE operation_id=p_operation) IS DISTINCT FROM receipt
        OR (SELECT pg_catalog.array_agg(object_id ORDER BY order_index) FROM internal.publication_photo_bindings
            WHERE post_id=(receipt->>'post_id')::UUID) IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.bind_publication_copy_cohort(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bind_publication_copy_cohort(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.bind_publication_copy_cohort(uuid,uuid,uuid,uuid)','Bind only the settled no-note ordered reservation under live copy work, or recover its committed historical receipt.');

RESET statement_timeout;
RESET lock_timeout;

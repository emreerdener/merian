SET lock_timeout='5s';
SET statement_timeout='2min';

-- Copy eligibility is separate from immutable historical provider approval.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_copy_settlement_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_copy_outcomes (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_moderation_outcomes(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    reason TEXT NOT NULL CHECK(reason IN ('note_requires_text_moderation','staging_expired')),
    object_ids UUID[] NOT NULL CHECK(cardinality(object_ids) BETWEEN 0 AND 6 AND array_position(object_ids,NULL) IS NULL),
    finalized_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CHECK((reason='note_requires_text_moderation' AND cardinality(object_ids)=0)
        OR (reason='staging_expired' AND cardinality(object_ids) BETWEEN 1 AND 6))
);
ALTER TABLE internal.observation_publication_copy_outcomes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_copy_outcomes FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_copy_outcome BEFORE INSERT OR UPDATE ON internal.observation_publication_copy_outcomes
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_publication_copy_outcome_update BEFORE UPDATE ON internal.observation_publication_copy_outcomes
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

CREATE FUNCTION public.finalize_publication_copy_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_publication_copy_outcomes; reservation JSONB; intent internal.observation_publication_intents;
    reason TEXT; objects UUID[]:='{}'::UUID[]; object UUID; registry internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    -- Scope and deletion precede every historical replay; work/gates follow it.
    IF NOT EXISTS(SELECT 1 FROM internal.observation_publication_operations
        WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN
        -- Validate legacy and current historical bindings without granting fresh
        -- reserved-cohort authority or returning any cleanup targets.
        PERFORM internal.bind_approved_publication_photo_cohort(p_owner,p_observation,p_operation);
        RETURN '{"finalized":true,"status":"admitted","reason":null,"object_ids":[]}'::JSONB;
    END IF;
    SELECT * INTO saved FROM internal.observation_publication_copy_outcomes WHERE operation_id=p_operation;
    IF FOUND THEN
        IF saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN pg_catalog.jsonb_build_object('finalized',TRUE,'status','needs_action','reason',saved.reason,'object_ids',saved.object_ids);
    END IF;
    PERFORM internal.assert_publication_copy_work(p_owner,p_observation,p_operation,p_work);
    IF (SELECT publication_copy_settlement_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- Recover immutable facts without interpreting a live gate/review/consent
    -- denial, expired worker token or transport failure as a terminal outcome.
    PERFORM internal.publication_copy_cohort(p_owner,p_observation,p_operation);
    SELECT * INTO STRICT intent FROM internal.observation_publication_intents WHERE operation_id=p_operation;
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    IF intent.request->>'note' IS NOT NULL AND reservation IS NULL
        AND NOT EXISTS(SELECT 1 FROM internal.observation_photo_copies c JOIN internal.observation_photo_moderation_attempts a ON a.id=c.attempt_id WHERE a.operation_id=p_operation) THEN
        reason:='note_requires_text_moderation';
    ELSIF reservation IS NOT NULL AND (reservation->>'expires_at')::TIMESTAMPTZ<=clock_timestamp() THEN
        reason:='staging_expired';
        SELECT pg_catalog.array_agg((value->>'object_id')::UUID ORDER BY ordinality) INTO objects
            FROM pg_catalog.jsonb_array_elements(reservation->'copies') WITH ORDINALITY;
        -- Preserve source order in the receipt; lock registry in UUID order.
        FOR object IN SELECT unnest(objects) ORDER BY 1 LOOP
            SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=object FOR UPDATE;
            IF registry.bound_at IS NOT NULL THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
            END IF;
            IF registry.erased_at IS NULL THEN
                UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()),
                    revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE object_id=object;
            END IF;
        END LOOP;
    ELSE
        RETURN '{"finalized":false}'::JSONB;
    END IF;
    INSERT INTO internal.observation_publication_copy_outcomes(operation_id,owner_id,observation_id,reason,object_ids)
        VALUES(p_operation,p_owner,p_observation,reason,objects);
    DELETE FROM internal.observation_publication_copy_work WHERE operation_id=p_operation;
    -- These IDs are private cleanup hints; each still needs a registry claim.
    RETURN pg_catalog.jsonb_build_object('finalized',TRUE,'status','needs_action','reason',reason,'object_ids',objects);
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_publication_copy_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_publication_copy_work(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.finalize_publication_copy_work(uuid,uuid,uuid,uuid)','Derive immutable note or expired-staging needs-action facts and retire exact copy work without modifying provider approval or quota.');

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
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN state:='admitted';
    ELSIF EXISTS(SELECT 1 FROM internal.observation_publication_copy_outcomes WHERE operation_id=p_operation) THEN state:='needs_action';
    ELSIF state IS NOT NULL THEN NULL;
    ELSIF EXISTS(SELECT 1 FROM internal.observation_publication_work WHERE operation_id=p_operation AND work_expires_at>clock_timestamp()) THEN state:='processing';
    ELSE state:='accepted'; END IF;
    -- Keep the existing owner wire shape: no source keys, reasons or work tokens.
    RETURN pg_catalog.jsonb_build_object('schema_version',1,'operation_id',p_operation,
        'observation_id',p_observation,'analysis_id',accepted.receipt->'analysis_id','status',state);
END;
$$;
REVOKE ALL ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_owned_observation_publication_status(UUID,UUID,UUID) TO service_role;
RESET statement_timeout;
RESET lock_timeout;

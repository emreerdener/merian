SET lock_timeout='5s';
SET statement_timeout='2min';

-- One immutable reservation for the entire settled cohort. Every object and its
-- erasure obligation commit together, before any external read or write.
ALTER TABLE internal.observation_history_rollout ADD COLUMN publication_copy_reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE internal.observation_publication_copy_cohorts (
    operation_id UUID PRIMARY KEY REFERENCES internal.observation_publication_moderation_outcomes(operation_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    copies JSONB NOT NULL CHECK(pg_catalog.jsonb_typeof(copies)='array' AND pg_catalog.jsonb_array_length(copies) BETWEEN 1 AND 6 AND pg_catalog.octet_length(copies::TEXT)<=16384)
);
ALTER TABLE internal.observation_publication_copy_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_publication_copy_cohorts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_publication_copy_cohort BEFORE INSERT OR UPDATE ON internal.observation_publication_copy_cohorts
FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_publication_copy_cohort_update BEFORE UPDATE ON internal.observation_publication_copy_cohorts
FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

CREATE FUNCTION internal.authorize_publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE cohort JSONB; item JSONB; source JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_copy_work(p_owner,p_observation,p_operation,p_work);
    IF (SELECT publication_copy_execution_enabled AND publication_copy_reservation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    cohort:=internal.publication_copy_cohort(p_owner,p_observation,p_operation);
    -- Explicit no-note subset. Photo approval never approves arbitrary text.
    IF EXISTS(SELECT 1 FROM internal.observation_publication_intents WHERE operation_id=p_operation AND request->>'note' IS NOT NULL)
        OR EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(cohort) LOOP
        source:=internal.authorize_publication_photo_copy(p_owner,p_observation,(item->>'attempt_id')::UUID);
        IF source IS DISTINCT FROM item->'source' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    END LOOP;
    RETURN cohort;
END;
$$;
REVOKE ALL ON FUNCTION internal.authorize_publication_copy_cohort(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Recovery is allowed after expiry or authority loss, but it supplies no I/O
-- permission. Original object/lease/source tuples can never be substituted.
CREATE FUNCTION internal.publication_copy_reservation(p_owner UUID,p_observation UUID,p_operation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_publication_copy_cohorts; member JSONB; item JSONB; ordinal BIGINT;
    copy internal.observation_photo_copies; cohort JSONB; copies JSONB:='[]'::JSONB;
BEGIN
    PERFORM internal.require_service_role();
    cohort:=internal.publication_copy_cohort(p_owner,p_observation,p_operation);
    SELECT * INTO saved FROM internal.observation_publication_copy_cohorts WHERE operation_id=p_operation;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
        OR pg_catalog.jsonb_array_length(saved.copies)<>pg_catalog.jsonb_array_length(cohort) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    FOR member,ordinal IN SELECT value,ordinality FROM pg_catalog.jsonb_array_elements(saved.copies) WITH ORDINALITY LOOP
        item:=cohort->(ordinal::INT-1);
        SELECT * INTO copy FROM internal.observation_photo_copies WHERE attempt_id=(item->>'attempt_id')::UUID;
        IF NOT FOUND OR (pg_catalog.to_jsonb(copy)-'ready_at') IS DISTINCT FROM (member-'ready_at')
            OR copy.source IS DISTINCT FROM item->'source' OR copy.expires_at IS DISTINCT FROM saved.expires_at
            OR copy.owner_id IS DISTINCT FROM p_owner OR copy.observation_id IS DISTINCT FROM p_observation THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        copies:=copies||pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(copy));
    END LOOP;
    RETURN pg_catalog.jsonb_build_object('expires_at',saved.expires_at,'copies',copies);
END;
$$;
REVOKE ALL ON FUNCTION internal.publication_copy_reservation(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_publication_copy_registry(p_reservation JSONB) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE object UUID; registry internal.publication_photo_objects;
BEGIN
    PERFORM internal.require_service_role();
    IF p_reservation IS NULL OR (p_reservation->>'expires_at')::TIMESTAMPTZ<=clock_timestamp() THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- Match erasure/binding lock order. Never extend or clear registry state.
    FOR object IN SELECT (value->>'object_id')::UUID FROM pg_catalog.jsonb_array_elements(p_reservation->'copies') ORDER BY 1 LOOP
        SELECT * INTO registry FROM internal.publication_photo_objects WHERE object_id=object FOR UPDATE;
        IF NOT FOUND OR registry.available_at IS DISTINCT FROM (p_reservation->>'expires_at')::TIMESTAMPTZ
            OR registry.bound_at IS NOT NULL OR registry.revoked_at IS NOT NULL OR registry.claim_token IS NOT NULL OR registry.erased_at IS NOT NULL
            OR registry.available_at<=clock_timestamp() THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_publication_copy_registry(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.reserve_publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE cohort JSONB; reservation JSONB; item JSONB; candidate UUID; deadline TIMESTAMPTZ;
    copy internal.observation_photo_copies; copies JSONB:='[]'::JSONB;
BEGIN
    PERFORM internal.require_service_role();
    cohort:=internal.authorize_publication_copy_cohort(p_owner,p_observation,p_operation,p_work);
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    IF reservation IS NOT NULL THEN
        PERFORM internal.assert_publication_copy_registry(reservation);
        RETURN reservation;
    END IF;
    -- Do not adopt a legacy partial reservation or alter its original TTL.
    IF EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(cohort) c JOIN internal.observation_photo_copies p ON p.attempt_id=(c.value->>'attempt_id')::UUID) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    deadline:=clock_timestamp()+INTERVAL '10 minutes';
    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(cohort) LOOP
        LOOP
            candidate:=extensions.gen_random_uuid();
            IF candidate IN (p_owner,p_observation,p_operation,(item->>'attempt_id')::UUID,(item#>>'{source,media_id}')::UUID,(item#>>'{source,object_id}')::UUID) THEN CONTINUE; END IF;
            INSERT INTO internal.publication_photo_objects(object_id,available_at) VALUES(candidate,deadline) ON CONFLICT DO NOTHING;
            EXIT WHEN FOUND;
        END LOOP;
        INSERT INTO internal.observation_photo_copies(attempt_id,object_id,observation_id,owner_id,source,expires_at)
        VALUES((item->>'attempt_id')::UUID,candidate,p_observation,p_owner,item->'source',deadline) RETURNING * INTO copy;
        copies:=copies||pg_catalog.jsonb_build_array(pg_catalog.to_jsonb(copy));
    END LOOP;
    INSERT INTO internal.observation_publication_copy_cohorts(operation_id,owner_id,observation_id,expires_at,copies)
        VALUES(p_operation,p_owner,p_observation,deadline,copies);
    RETURN pg_catalog.jsonb_build_object('expires_at',deadline,'copies',copies);
END;
$$;
CREATE FUNCTION public.read_publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE reservation JSONB; publication JSONB;
BEGIN
    PERFORM internal.require_service_role();
    -- A binding retires work. Historical read must not require its old token or
    -- current authority, otherwise a lost binding response could trigger erasure.
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    SELECT receipt INTO publication FROM internal.observation_photo_publications WHERE operation_id=p_operation;
    RETURN pg_catalog.jsonb_build_object('reservation',reservation,'publication',publication);
END;
$$;
CREATE FUNCTION public.complete_publication_copy_cohort_photo(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID,p_attempt UUID,p_object UUID,p_lease UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE reservation JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.authorize_publication_copy_cohort(p_owner,p_observation,p_operation,p_work);
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    IF NOT EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(reservation->'copies') c
        WHERE c.value->>'attempt_id'=p_attempt::TEXT AND c.value->>'object_id'=p_object::TEXT AND c.value->>'lease_token'=p_lease::TEXT) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.assert_publication_copy_registry(reservation);
    RETURN internal.complete_publication_photo_copy(p_owner,p_observation,p_attempt,p_object,p_lease);
END;
$$;
CREATE FUNCTION public.abandon_publication_copy_cohort(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE reservation JSONB; object UUID; registry internal.publication_photo_objects; objects UUID[]:='{}'::UUID[];
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    -- A committed publication wins over late cleanup, even after work retired.
    IF EXISTS(SELECT 1 FROM internal.observation_photo_publications WHERE operation_id=p_operation)
        AND EXISTS(SELECT 1 FROM internal.observation_publication_operations WHERE operation_id=p_operation AND owner_id=p_owner AND observation_id=p_observation) THEN
        RETURN '{"abandoned":false}'::JSONB;
    END IF;
    PERFORM internal.assert_publication_copy_work(p_owner,p_observation,p_operation,p_work);
    reservation:=internal.publication_copy_reservation(p_owner,p_observation,p_operation);
    IF reservation IS NULL THEN RETURN '{"abandoned":false}'::JSONB; END IF;
    FOR object IN SELECT (value->>'object_id')::UUID FROM pg_catalog.jsonb_array_elements(reservation->'copies') ORDER BY 1 LOOP
        SELECT * INTO STRICT registry FROM internal.publication_photo_objects WHERE object_id=object FOR UPDATE;
        IF registry.bound_at IS NOT NULL THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        IF registry.erased_at IS NULL THEN
            UPDATE internal.publication_photo_objects SET available_at=LEAST(available_at,clock_timestamp()),
                revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE object_id=object;
        END IF;
        objects:=pg_catalog.array_append(objects,object);
    END LOOP;
    -- Registry eligibility only. External erasure still requires targeted claims.
    RETURN pg_catalog.jsonb_build_object('abandoned',TRUE,'object_ids',objects);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_publication_copy_cohort(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_publication_copy_cohort(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.complete_publication_copy_cohort_photo(UUID,UUID,UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.abandon_publication_copy_cohort(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_publication_copy_cohort(UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_publication_copy_cohort(UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_publication_copy_cohort_photo(UUID,UUID,UUID,UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.abandon_publication_copy_cohort(UUID,UUID,UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.reserve_publication_copy_cohort(uuid,uuid,uuid,uuid)','Reserve the exact settled no-note photo cohort atomically with one immutable expiry and current authority.'),
('service_role','public.read_publication_copy_cohort(uuid,uuid,uuid)','Recover original private cohort and historical publication before any cleanup decision.'),
('service_role','public.complete_publication_copy_cohort_photo(uuid,uuid,uuid,uuid,uuid,uuid,uuid)','Complete one exact cohort member under live copy work, current authority and the original shared expiry.'),
('service_role','public.abandon_publication_copy_cohort(uuid,uuid,uuid,uuid)','Queue all exact unbound cohort objects for targeted erasure without overriding a committed publication.');
RESET statement_timeout;
RESET lock_timeout;

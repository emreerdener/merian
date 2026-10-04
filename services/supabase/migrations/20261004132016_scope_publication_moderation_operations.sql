SET lock_timeout='5s';
SET statement_timeout='2min';

-- Service-only repository boundary. No endpoint, scheduler or gate is enabled.
-- Recover from the accepted operation, never infer a retry from missing replies.
CREATE FUNCTION public.read_publication_moderation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE sources JSONB; source JSONB; attempt UUID; result JSONB:='[]'::JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    SELECT i.sources INTO STRICT sources FROM internal.observation_publication_intents i
        JOIN internal.observation_publication_operations o USING(operation_id)
        WHERE i.operation_id=p_operation AND o.owner_id=p_owner AND o.observation_id=p_observation;
    FOR source IN SELECT value FROM pg_catalog.jsonb_array_elements(sources) LOOP
        SELECT a.id INTO attempt FROM internal.observation_photo_moderation_attempts a
            WHERE a.operation_id=p_operation AND a.media_id=(source->>'media_id')::UUID
            ORDER BY a.attempt_count DESC LIMIT 1;
        result:=result||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('media_id',source->'media_id',
            'attempt',CASE WHEN attempt IS NULL THEN NULL ELSE internal.publication_moderation_receipt(attempt) END));
    END LOOP;
    -- Original provider tokens are private recovery capabilities, never a client
    -- response or a new dispatch permit. Sources remain in exact consent order.
    RETURN result;
END;
$$;

CREATE FUNCTION public.admit_publication_moderation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID,p_media UUID)
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
    SELECT id INTO attempt FROM internal.observation_photo_moderation_attempts
        WHERE operation_id=p_operation AND media_id=p_media ORDER BY attempt_count DESC LIMIT 1;
    -- Any existing attempt is recovery, including cancelled/unknown. This API
    -- cannot request a successor, even after retirement or generic quota pruning.
    IF FOUND THEN RETURN internal.publication_moderation_receipt(attempt); END IF;
    IF (SELECT publication_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    -- The trusted execution owner must verify the entire immutable source cohort
    -- and reject unsupported/metadata-bearing containers BEFORE this quota call.
    RETURN internal.admit_publication_photo_moderation(p_owner,p_observation,p_operation,p_media,NULL,ip);
END;
$$;

CREATE FUNCTION public.advance_publication_moderation_work(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID,
    p_attempt UUID,p_token UUID,p_action TEXT,p_payload JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts;
BEGIN
    PERFORM internal.require_service_role();
    IF p_action IS NULL OR p_action NOT IN ('prepare','dispatch','complete','retire')
        OR pg_catalog.jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR pg_catalog.octet_length(p_payload::TEXT)>8192 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF NOT EXISTS(SELECT 1 FROM internal.observation_publication_operations WHERE operation_id=p_operation
        AND owner_id=p_owner AND observation_id=p_observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    -- Scope membership is checked even for late completions; a token from a
    -- different accepted operation can never be laundered through this facade.
    SELECT a.* INTO attempt FROM internal.observation_photo_moderation_attempts a
        JOIN internal.observation_photo_moderations m USING(operation_id,media_id)
        WHERE a.id=p_attempt AND a.operation_id=p_operation AND a.observation_id=p_observation
            AND m.owner_id=p_owner AND m.observation_id=p_observation FOR UPDATE OF a;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_action IN ('prepare','dispatch') OR (p_action='retire' AND attempt.state='reserved') THEN
        PERFORM internal.assert_publication_operation_work(p_owner,p_observation,p_operation,p_work);
    END IF;
    IF p_action IN ('prepare','dispatch') AND
        (SELECT publication_execution_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    IF p_action='prepare' THEN
        IF NOT p_payload?'proof' OR p_payload-'proof'<>'{}'::JSONB THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        PERFORM internal.prepare_publication_photo_execution(p_owner,p_observation,p_attempt,p_token,p_payload->'proof');
        RETURN '{}'::JSONB;
    ELSIF p_action='dispatch' THEN
        IF p_payload<>'{}'::JSONB THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        RETURN internal.dispatch_publication_photo_moderation(p_owner,p_observation,p_attempt,p_token);
    ELSIF p_action='complete' THEN
        IF NOT p_payload ?& ARRAY['proof','result'] OR p_payload-ARRAY['proof','result']<>'{}'::JSONB THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        -- Existing provider lease/proof/deadline, not a possibly expired work
        -- token, authorizes receipt of an already dispatched result. Deletion,
        -- review/source revalidation and identical replay remain authoritative.
        RETURN internal.complete_publication_photo_execution(p_owner,p_observation,p_attempt,p_token,p_payload->'proof',p_payload->'result');
    ELSE
        IF p_payload<>'{}'::JSONB THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        -- Dispatched retirement never refunds and requires provider expiry.
        -- An old orchestrator cannot cancel a still-reserved successor's work.
        RETURN internal.retire_publication_photo_moderation(p_owner,p_observation,p_attempt,p_token);
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.read_publication_moderation_work(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.admit_publication_moderation_work(UUID,UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.advance_publication_moderation_work(UUID,UUID,UUID,UUID,UUID,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_publication_moderation_work(UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.admit_publication_moderation_work(UUID,UUID,UUID,UUID,UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.advance_publication_moderation_work(UUID,UUID,UUID,UUID,UUID,UUID,TEXT,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.read_publication_moderation_work(uuid,uuid,uuid,uuid)','Recover exact ordered accepted-operation moderation attempts and original provider leases under a current work claim.'),
('service_role','public.admit_publication_moderation_work(uuid,uuid,uuid,uuid,uuid)','Admit one initial cohort attempt using saved intake IP; recover existing attempts without automatic successors.'),
('service_role','public.advance_publication_moderation_work(uuid,uuid,uuid,uuid,uuid,uuid,text,jsonb)','Scope proof, dispatch, exact completion and retirement to accepted operation and original provider identity.');
RESET statement_timeout;
RESET lock_timeout;

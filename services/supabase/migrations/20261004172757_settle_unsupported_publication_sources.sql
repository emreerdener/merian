SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN publication_source_settlement_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Keep provider failure rows with unattempted (NULL) siblings valid. Only the
-- metadata-derived source outcome may have no provider attempt slots at all.
ALTER TABLE internal.observation_publication_moderation_outcomes
    DROP CONSTRAINT observation_publication_moderation_outcomes_attempt_ids_check,
    DROP CONSTRAINT observation_publication_moderation_outcomes_check,
    ADD CONSTRAINT publication_moderation_outcome_evidence CHECK (
        (state='photos_approved' AND reason IS NULL AND cardinality(attempt_ids) BETWEEN 1 AND 6
            AND array_position(attempt_ids,NULL) IS NULL)
        OR (state='needs_action' AND reason IS NOT NULL AND reason IN ('photo_rejected','unknown_execution','cancelled')
            AND cardinality(attempt_ids) BETWEEN 1 AND 6)
        OR (state='needs_action' AND reason IS NOT NULL AND reason='unsupported_source_type'
            AND cardinality(attempt_ids)=0)
    );

CREATE OR REPLACE FUNCTION public.finalize_publication_photo_moderation(p_owner UUID,p_observation UUID,p_operation UUID,p_work UUID)
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
    -- Metadata-only remediation. Never replace any existing provider attempt,
    -- including a terminal predecessor, with a zero-attempt source decision.
    IF (SELECT publication_source_settlement_enabled FROM internal.observation_history_rollout WHERE singleton) IS TRUE
        AND NOT EXISTS(SELECT 1 FROM internal.observation_photo_moderation_attempts WHERE operation_id=p_operation)
        AND EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(intent.sources) s
            WHERE s->>'content_type' NOT IN ('image/jpeg','image/png')) THEN
        INSERT INTO internal.observation_publication_moderation_outcomes(operation_id,owner_id,observation_id,state,reason,attempt_ids)
            VALUES(p_operation,p_owner,p_observation,'needs_action','unsupported_source_type','{}'::UUID[]);
        DELETE FROM internal.observation_publication_work WHERE operation_id=p_operation;
        RETURN '{"finalized":true,"status":"needs_action","reason":"unsupported_source_type"}'::JSONB;
    END IF;
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
RESET statement_timeout;
RESET lock_timeout;

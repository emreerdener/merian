SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN execution_status_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Status is not a claim, dispatch grant, no-admission proof or retirement receipt.
-- Preserve the original request identity even when selection/review has changed.
CREATE FUNCTION public.get_owned_observation_analysis_execution(p_request JSONB, p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '5s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; analysis UUID; source UUID;
    saved internal.observation_analysis_intents; execution_state TEXT;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9
        OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR pg_catalog.OCTET_LENGTH(p_request::TEXT) > 2048
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest'])
        OR p_request - ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest'] <> '{}'::JSONB
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'observation_id') IS DISTINCT FROM 'string'
        OR (p_request ->> 'observation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'analysis_id') IS DISTINCT FROM 'string'
        OR (p_request ->> 'analysis_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (p_request -> 'source_analysis_id' <> 'null'::JSONB AND (
            pg_catalog.JSONB_TYPEOF(p_request -> 'source_analysis_id') IS DISTINCT FROM 'string'
            OR (p_request ->> 'source_analysis_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'request_digest') IS DISTINCT FROM 'string'
        OR (p_request ->> 'request_digest') !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    analysis := (p_request ->> 'analysis_id')::UUID;
    source := (p_request ->> 'source_analysis_id')::UUID;
    IF analysis = observation OR source IN (observation, analysis) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF NOT COALESCE((SELECT reader_enabled AND execution_status_api_enabled
        FROM internal.observation_history_rollout WHERE singleton), FALSE) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(caller, observation);
    -- Query the globally unique child, then reject scope conflicts. Never disguise
    -- a conflicting operation as absence, or return its private authority.
    SELECT * INTO saved FROM internal.observation_analysis_intents
        WHERE analysis_id=analysis;
    IF FOUND THEN
        IF saved.owner_id IS DISTINCT FROM caller OR saved.observation_id IS DISTINCT FROM observation
            OR saved.input_snapshot->>'observation_id' IS DISTINCT FROM observation::TEXT
            OR saved.input_snapshot->>'analysis_id' IS DISTINCT FROM analysis::TEXT
            OR saved.input_snapshot->>'source_analysis_id' IS DISTINCT FROM source::TEXT
            OR saved.input_snapshot->>'request_digest' IS DISTINCT FROM p_request->>'request_digest' THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        -- The caller's owner/parent locks already serialize matching writers.
        -- Do not lock a foreign-owner row before rejecting its scope.
        PERFORM analysis_id FROM internal.observation_analysis_intents
            WHERE analysis_id=analysis AND owner_id=caller FOR SHARE;
        execution_state := saved.state;
    ELSE
        execution_state := 'absent';
    END IF;
    RETURN pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'owner_id',caller,
        'observation_id',observation,'analysis_id',analysis,'source_analysis_id',source,
        'request_digest',p_request->>'request_digest','state',execution_state);
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_analysis_execution(JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_analysis_execution(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_analysis_execution(jsonb,integer)',
     'Default-off exact owner execution status only; absence never authorizes dispatch or retirement.');
COMMENT ON FUNCTION public.get_owned_observation_analysis_execution(JSONB,INTEGER) IS
    'Reader 9, bounded immutable operation reference. No consent, claim, quota, provider, selection or retirement mutation. Existing outcome recovery is separate.';

RESET statement_timeout;
RESET lock_timeout;

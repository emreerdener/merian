SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN selection_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Only the owner-bound public wrapper may enter with an authenticated caller.
-- The private implementation keeps all grants revoked and the service fallback.
DO $patch$
DECLARE definition TEXT; old TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.select_observation_analysis(uuid,jsonb)'::regprocedure);
    old := '    PERFORM internal.require_service_role();';
    IF (length(definition)-length(replace(definition,old,'')))/length(old) <> 1 THEN
        RAISE EXCEPTION 'history_selection_source_drift';
    END IF;
    EXECUTE replace(definition,old,$new$    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
        PERFORM internal.require_service_role();
    END IF;$new$);
END;
$patch$;

CREATE FUNCTION public.select_owned_observation_analysis(p_request JSONB, p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; target UUID; operation UUID;
    expected_revision INTEGER; expected_review INTEGER; response JSONB;
    saved internal.observation_selection_receipts;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9 OR pg_catalog.octet_length(p_request::TEXT) > 2048 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.JSONB_OBJECT_KEYS(p_request)) <> 6
        OR NOT p_request ?& ARRAY['schema_version','observation_id','analysis_id','operation_id','expected_observation_revision','expected_review_revision']
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR COALESCE(p_request ->> 'observation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'analysis_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR COALESCE(p_request ->> 'operation_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_observation_revision') IS DISTINCT FROM 'number'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'expected_review_revision') IS DISTINCT FROM 'number'
        OR COALESCE(p_request ->> 'expected_observation_revision','') !~ '^[0-9]{1,10}$'
        OR COALESCE(p_request ->> 'expected_review_revision','') !~ '^[0-9]{1,10}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    IF (p_request ->> 'expected_observation_revision')::BIGINT > 2147483646
        OR (p_request ->> 'expected_review_revision')::BIGINT > 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    operation := (p_request ->> 'operation_id')::UUID;
    expected_revision := (p_request ->> 'expected_observation_revision')::INTEGER;
    expected_review := (p_request ->> 'expected_review_revision')::INTEGER;


    -- These outer locks survive the exception subtransaction below. A rejected
    -- operation must be durable before its response can release a native intent.
    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||observation::TEXT,0::BIGINT));
    PERFORM scans.id FROM public.scans AS scans WHERE scans.id=observation AND scans.user_id=caller AND NOT scans.is_tombstoned FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO saved FROM internal.observation_selection_receipts
        WHERE observation_id=observation AND operation_id=operation;
    IF FOUND THEN
        IF saved.request_identity IS DISTINCT FROM p_request THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN saved.receipt;
    END IF;
    IF (SELECT selection_api_enabled AND reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    BEGIN
        response := internal.select_observation_analysis(caller,p_request);
    EXCEPTION WHEN serialization_failure THEN
        IF SQLERRM IS DISTINCT FROM 'analysis_history_revision_conflict' THEN RAISE; END IF;
        response := pg_catalog.jsonb_build_object('schema_version',1,'operation_id',operation,
            'observation_id',observation,'analysis_id',target,
            'expected_observation_revision',expected_revision,'expected_review_revision',expected_review,
            'outcome','revision_conflict');
        INSERT INTO internal.observation_selection_receipts(observation_id,operation_id,request_identity,receipt)
            VALUES(observation,operation,p_request,response);
    END;
    -- Both accepted and rejected exact retries use the immutable receipt table.
    -- A rejection never advances selection/revision or adds reconciliation work.
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.select_owned_observation_analysis(JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.select_owned_observation_analysis(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.select_owned_observation_analysis(jsonb,integer)',
     'Default-off protocol 9 owner selection with durable exact-operation success or revision-conflict receipts.');
COMMENT ON FUNCTION public.select_owned_observation_analysis(JSONB,INTEGER) IS
    'Prepared owner selection API. Current-state read remains required after a receipt. Definitive revision-conflict receipts prevent later retry application; other errors remain unresolved. No rollout activation or credit reconciliation worker.';

RESET statement_timeout;
RESET lock_timeout;

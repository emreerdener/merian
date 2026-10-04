SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Independent read hold. This migration grants no enrollment, result insertion
-- or selection capability and changes neither existing rollout switch.
ALTER TABLE internal.observation_history_rollout
    ADD COLUMN reader_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- The aggregate envelope is the native durable value. Independent legacy column
-- caps are insufficient: completion must never commit an unreadable history row.
CREATE FUNCTION internal.observation_analysis_snapshot(
    observation UUID, analysis UUID, source_analysis UUID, digest TEXT, ordinal INTEGER,
    completed TIMESTAMPTZ, result JSONB, evidence JSONB
) RETURNS TEXT LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT pg_catalog.JSONB_BUILD_OBJECT(
        'schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'ordinal',ordinal,'source_analysis_id',source_analysis,'request_digest',digest,
        'completed_at_ms',pg_catalog.FLOOR(EXTRACT(EPOCH FROM completed) * 1000),
        'result',result,'evidence_manifest',evidence)::TEXT;
$$;
REVOKE ALL ON FUNCTION internal.observation_analysis_snapshot(UUID, UUID, UUID, TEXT, INTEGER, TIMESTAMPTZ, JSONB, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_readable_snapshot CHECK (
    pg_catalog.ISFINITE(completed_at)
    AND EXTRACT(EPOCH FROM completed_at) * 1000 BETWEEN 0 AND 8640000000000000
    AND pg_catalog.OCTET_LENGTH(internal.observation_analysis_snapshot(
        observation_id,analysis_id,source_analysis_id,request_digest,ordinal,completed_at,result_snapshot,evidence_manifest)) <= 1048576
);

CREATE FUNCTION public.get_owned_observation_analysis_page(p_request JSONB, p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; before_ordinal INTEGER; page_limit INTEGER;
    history internal.observation_histories; result_row internal.observation_analysis_results;
    items JSONB := '[]'::JSONB; snapshot TEXT; item JSONB; response JSONB;
    last_ordinal INTEGER; has_more BOOLEAN := FALSE;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 7
        OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','before_ordinal','limit'])
        OR p_request - ARRAY['schema_version','observation_id','before_ordinal','limit'] <> '{}'::JSONB
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'observation_id') IS DISTINCT FROM 'string'
        OR (p_request ->> 'observation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'limit') IS DISTINCT FROM 'number'
        OR (p_request ->> 'limit') !~ '^[0-9]{1,2}$'
        OR (p_request -> 'before_ordinal' <> 'null'::JSONB AND (
            pg_catalog.JSONB_TYPEOF(p_request -> 'before_ordinal') IS DISTINCT FROM 'number'
            OR (p_request ->> 'before_ordinal') !~ '^[0-9]{1,10}$')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    page_limit := (p_request ->> 'limit')::INTEGER;
    IF page_limit NOT BETWEEN 1 AND 20 OR (p_request ->> 'before_ordinal')::BIGINT NOT BETWEEN 1 AND 2147483646 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE = '22023';
    END IF;
    before_ordinal := (p_request ->> 'before_ordinal')::INTEGER;
    IF (SELECT reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
    END IF;
    -- Same owner -> generation -> scan -> history ordering as completion/deletion.
    PERFORM users.id FROM public.users AS users WHERE users.id = caller FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE = 'P0002';
    END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || observation::TEXT, 0::BIGINT));
    PERFORM scan.id FROM public.scans AS scan
        WHERE scan.id = observation AND scan.user_id = caller AND NOT scan.is_tombstoned FOR SHARE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id = observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id = observation FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE = 'P0002';
    END IF;
    FOR result_row IN SELECT * FROM internal.observation_analysis_results
        WHERE observation_id = observation AND (before_ordinal IS NULL OR ordinal < before_ordinal)
        ORDER BY ordinal DESC LIMIT page_limit + 1
    LOOP
        IF pg_catalog.JSONB_ARRAY_LENGTH(items) = page_limit THEN has_more := TRUE; EXIT; END IF;
        IF result_row.result_snapshot ->> 'scan_id' IS DISTINCT FROM result_row.observation_id::TEXT
            OR result_row.evidence_manifest -> 'schema_version' IS DISTINCT FROM '1'::JSONB
            OR pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'captured_media') IS DISTINCT FROM 'array'
            OR NOT pg_catalog.ISFINITE(result_row.completed_at) THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
        END IF;
        snapshot := internal.observation_analysis_snapshot(result_row.observation_id,result_row.analysis_id,
            result_row.source_analysis_id,result_row.request_digest,result_row.ordinal,result_row.completed_at,
            result_row.result_snapshot,result_row.evidence_manifest);
        IF pg_catalog.OCTET_LENGTH(snapshot) > 1048576 THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
        END IF;
        item := pg_catalog.JSONB_BUILD_OBJECT('ordinal',result_row.ordinal,'snapshot',snapshot);
        -- Leave room for the envelope and escaped JSON string. Page truncation
        -- always returns a prefix and resumes before its last accepted ordinal.
        IF pg_catalog.OCTET_LENGTH((items || pg_catalog.JSONB_BUILD_ARRAY(item))::TEXT) > 4190208 THEN
            IF last_ordinal IS NULL THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000'; END IF;
            has_more := TRUE; EXIT;
        END IF;
        items := items || pg_catalog.JSONB_BUILD_ARRAY(item);
        last_ordinal := result_row.ordinal;
    END LOOP;
    response := pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'owner_id',caller,
        'observation_id',observation,'state_revision',history.state_revision,'items',items,
        'next_before_ordinal',CASE WHEN has_more THEN last_ordinal ELSE NULL END);
    IF pg_catalog.OCTET_LENGTH(response::TEXT) > 4194304 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE = '55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_analysis_page(JSONB, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_analysis_page(JSONB, INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_analysis_page(jsonb,integer)',
     'Default-off bounded private analysis evidence read; authenticated owner only.');
COMMENT ON FUNCTION public.get_owned_observation_analysis_page(JSONB, INTEGER) IS
    'Read preparation only. Requires explicit protocol 7 and reader_enabled. Never enrolls, writes results, selects or settles funding. Strict semantic decoding is required before native admission.';

RESET statement_timeout;
RESET lock_timeout;

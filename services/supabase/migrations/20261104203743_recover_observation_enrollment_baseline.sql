SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Recovery only: read the existing immutable imported baseline, never create
-- history, reinstate selection, or call the creation-capable enrollment RPC.
CREATE FUNCTION public.get_owned_observation_enrollment_baseline(p_request JSONB, p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID;
    history internal.observation_histories;
    baseline internal.observation_analysis_results;
    snapshot TEXT; response JSONB;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9
        OR pg_catalog.jsonb_typeof(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id'])
        OR p_request - ARRAY['schema_version','observation_id'] <> '{}'::JSONB
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.jsonb_typeof(p_request->'observation_id') IS DISTINCT FROM 'string'
        OR (p_request->>'observation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request->>'observation_id')::UUID;
    IF NOT COALESCE((SELECT reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('merian-scan-ingestion:' || observation::TEXT,0::BIGINT));
    PERFORM scan.id FROM public.scans AS scan
        WHERE scan.id=observation AND scan.user_id=caller AND NOT scan.is_tombstoned FOR SHARE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=observation) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT * INTO history FROM internal.observation_histories WHERE observation_id=observation FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF NOT history.selection_initialized OR history.selected_analysis_id IS NULL OR history.state_revision < 1 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO baseline FROM internal.observation_analysis_results
        WHERE observation_id=observation AND ordinal=1 AND evidence_manifest->'schema_version'='3'::JSONB;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF baseline.analysis_id IN (caller,observation)
        OR baseline.result_snapshot->>'scan_id' IS DISTINCT FROM observation::TEXT THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    snapshot := internal.observation_analysis_snapshot(observation,baseline.analysis_id,baseline.source_analysis_id,
        baseline.request_digest,baseline.ordinal,baseline.completed_at,baseline.result_snapshot,baseline.evidence_manifest);
    IF snapshot IS NULL OR pg_catalog.octet_length(snapshot)>1048576 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    response := pg_catalog.jsonb_build_object('schema_version',1,'owner_id',caller,
        'observation_id',observation,'baseline_analysis_id',baseline.analysis_id,'snapshot',snapshot,
        'snapshot_sha256',pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
            E'merian.observation-history.enrollment-baseline.v1\n' || snapshot,'UTF8'),'sha256'),'hex'));
    IF pg_catalog.octet_length(response::TEXT)>4194304 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_enrollment_baseline(JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_enrollment_baseline(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_enrollment_baseline(jsonb,integer)',
     'Default-off owner-only recovery of an existing immutable saved baseline; no enrollment, selection, or funding mutation.');
COMMENT ON FUNCTION public.get_owned_observation_enrollment_baseline(JSONB,INTEGER) IS
    'Prepared reader9 association recovery. Exact ordinal1 V3 snapshot and domain-separated digest; no original local intent identity is claimed. Both reader holds remain required.';

RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- One authoritative pair for first-import reconciliation. Nested readers retain
-- the existing owner SHARE -> observation advisory -> scan/history SHARE locks
-- until this transaction ends; there is no lock upgrade or selection write.
CREATE FUNCTION public.get_owned_observation_enrollment_selection(p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    caller UUID := auth.uid();
    association JSONB; baseline JSONB; selected JSONB; response JSONB;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 11 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    association := public.get_owned_observation_enrollment_baseline(p_request,9);
    baseline := public.get_owned_observation_analysis_state(
        p_request || pg_catalog.jsonb_build_object('analysis_id',association->'baseline_analysis_id'),p_reader);
    selected := public.get_owned_observation_analysis_state(
        p_request || pg_catalog.jsonb_build_object('analysis_id',NULL),p_reader);
    IF baseline->>'owner_id' IS DISTINCT FROM association->>'owner_id'
        OR baseline->>'observation_id' IS DISTINCT FROM association->>'observation_id'
        OR baseline#>>'{analysis,snapshot}' IS DISTINCT FROM association->>'snapshot'
        OR baseline->'owner_id' IS DISTINCT FROM selected->'owner_id'
        OR baseline->'observation_id' IS DISTINCT FROM selected->'observation_id'
        OR baseline->'state_revision' IS DISTINCT FROM selected->'state_revision'
        OR baseline->'selected_analysis_id' IS DISTINCT FROM selected->'selected_analysis_id' THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    response := pg_catalog.jsonb_build_object('schema_version',1,
        'baseline_sha256',association->'snapshot_sha256',
        'baseline_state',baseline,'selected_state',selected);
    IF pg_catalog.octet_length(response::TEXT)>4194304 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_enrollment_selection(JSONB,INTEGER)
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_enrollment_selection(JSONB,INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_enrollment_selection(jsonb,integer)',
     'Default-off first-import reconciliation of original baseline and current selection under one observation lock; read only.');
COMMENT ON FUNCTION public.get_owned_observation_enrollment_selection(JSONB,INTEGER) IS
    'Prepared reader11 bounded baseline/current pair. Existing reader holds, owner/deletion fences and serializers apply; never enrolls, selects or executes.';

RESET statement_timeout;
RESET lock_timeout;

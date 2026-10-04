SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN state_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- One bounded result and its mutable authority under the same observation fence.
-- Null analysis selects the current result; an explicit analysis is preview-only.
-- This endpoint never enrolls, selects, repairs authority or awards credit.
CREATE FUNCTION public.get_owned_observation_analysis_state(p_request JSONB, p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '10s' AS $$
DECLARE
    caller UUID := auth.uid(); observation UUID; target UUID;
    history internal.observation_histories;
    evidence internal.observation_analysis_results;
    authority internal.observation_analysis_authorities;
    snapshot TEXT; response JSONB;
BEGIN
    IF caller IS NULL OR p_reader IS DISTINCT FROM 9
        OR pg_catalog.JSONB_TYPEOF(p_request) IS DISTINCT FROM 'object'
        OR NOT (p_request ?& ARRAY['schema_version','observation_id','analysis_id'])
        OR p_request - ARRAY['schema_version','observation_id','analysis_id'] <> '{}'::JSONB
        OR p_request -> 'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.JSONB_TYPEOF(p_request -> 'observation_id') IS DISTINCT FROM 'string'
        OR (p_request ->> 'observation_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR (p_request -> 'analysis_id' <> 'null'::JSONB AND (
            pg_catalog.JSONB_TYPEOF(p_request -> 'analysis_id') IS DISTINCT FROM 'string'
            OR (p_request ->> 'analysis_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation := (p_request ->> 'observation_id')::UUID;
    target := (p_request ->> 'analysis_id')::UUID;
    IF target = observation THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF NOT COALESCE((SELECT reader_enabled AND state_reader_enabled
        FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM users.id FROM public.users AS users WHERE users.id=caller FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED('merian-scan-ingestion:' || observation::TEXT,0::BIGINT));
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
    target := COALESCE(target,history.selected_analysis_id);
    SELECT * INTO evidence FROM internal.observation_analysis_results
        WHERE observation_id=observation AND analysis_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO authority FROM internal.observation_analysis_authorities
        WHERE observation_id=observation AND analysis_id=target;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    -- Defense against malformed internal preparation rows; private fields can
    -- never hitchhike in authority or become an alternate public projection.
    IF NOT authority.review_snapshot ?& ARRAY['ai_identification_review','confirmed_species_identity',
        'confirmed_species_identity_revision','confirmed_species_id','user_identification_override',
        'user_confirmed_identification','user_review_state']
        OR authority.review_snapshot - ARRAY['ai_identification_review','confirmed_species_identity',
        'confirmed_species_identity_revision','confirmed_species_id','user_identification_override',
        'user_confirmed_identification','user_review_state'] <> '{}'::JSONB
        OR evidence.result_snapshot ->> 'scan_id' IS DISTINCT FROM observation::TEXT THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.observation_analysis_projection(evidence.result_snapshot,authority.review_snapshot);
    snapshot := internal.observation_analysis_snapshot(observation,target,evidence.source_analysis_id,
        evidence.request_digest,evidence.ordinal,evidence.completed_at,evidence.result_snapshot,evidence.evidence_manifest);
    IF pg_catalog.OCTET_LENGTH(snapshot) > 1048576 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    response := pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'owner_id',caller,
        'observation_id',observation,'state_revision',history.state_revision,
        'selection_initialized',TRUE,'selected_analysis_id',history.selected_analysis_id,
        'analysis',pg_catalog.JSONB_BUILD_OBJECT('snapshot',snapshot,
            'review_revision',authority.review_revision,'review_snapshot',authority.review_snapshot));
    IF pg_catalog.OCTET_LENGTH(response::TEXT) > 4194304 THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN response;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_analysis_state(JSONB, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_analysis_state(JSONB, INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('authenticated','public.get_owned_observation_analysis_state(jsonb,integer)',
     'Default-off owner-only atomic result and review read; no selection or credit mutation.');
COMMENT ON FUNCTION public.get_owned_observation_analysis_state(JSONB, INTEGER) IS
    'Prepared reader 9 boundary. Null target reads current selection; explicit target previews one child without selecting. Requires both read holds. Native must validate result and authority independently and reject stale revisions.';

RESET statement_timeout;
RESET lock_timeout;

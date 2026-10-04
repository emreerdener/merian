SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Keep the V1 envelope and serializer bytes. Only protocol 8 can read V2
-- snapshots; protocol 7 rejects the entire mixed history after ownership checks.
DO $patch$
DECLARE definition TEXT; old TEXT; replacement TEXT;
BEGIN
    definition:=pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    old:='p_reader IS DISTINCT FROM 7';
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    definition:=replace(definition,old,'(p_reader IS NULL OR p_reader NOT IN (7,8))');
    old:='IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''2''::JSONB) THEN';
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    definition:=replace(definition,old,'IF p_reader=7 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->''schema_version''=''2''::JSONB) THEN');
    old:=$old$OR result_row.evidence_manifest -> 'schema_version' IS DISTINCT FROM '1'::JSONB
            OR pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'captured_media') IS DISTINCT FROM 'array'$old$;
    replacement:=$new$OR NOT (
                (result_row.evidence_manifest -> 'schema_version' = '1'::JSONB
                 AND pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'captured_media') = 'array')
                OR (p_reader=8 AND result_row.evidence_manifest -> 'schema_version' = '2'::JSONB
                 AND pg_catalog.JSONB_TYPEOF(result_row.evidence_manifest -> 'items') = 'array'))$new$;
    IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'history_reader_source_drift'; END IF;
    EXECUTE replace(definition,old,replacement);
END;
$patch$;
COMMENT ON FUNCTION public.get_owned_observation_analysis_page(JSONB,INTEGER) IS
    'Default-off owner read. Protocol 7 reads V1-only histories; protocol 8 reads mixed immutable V1/V2 snapshots with unchanged page envelope and exact bytes.';

-- Trusted Edge adapter only: caller owner comes from verified auth. Never send
-- this internal receipt/object identity to clients. Only completed V2 references
-- can be resolved, even if some other ready upload exists for the observation.
CREATE FUNCTION public.resolve_owned_observation_photo(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE manifest JSONB; receipt JSONB; item JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_reader IS DISTINCT FROM 8 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT reader_enabled AND media_reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT evidence_manifest INTO manifest FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND analysis_id=p_analysis;
    IF NOT FOUND OR manifest->'schema_version' IS DISTINCT FROM '2'::JSONB THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    SELECT value INTO item FROM pg_catalog.jsonb_array_elements(manifest->'items')
        WHERE value->>'kind'='image' AND value->>'media_id'=p_media::TEXT;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    receipt:=internal.read_owned_observation_evidence(p_owner,p_observation,p_analysis,p_media);
    IF receipt->'content_type' IS DISTINCT FROM item->'content_type'
        OR receipt->'byte_count' IS DISTINCT FROM item->'byte_count'
        OR receipt->'sha256' IS DISTINCT FROM item->'sha256' THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_owned_observation_photo(UUID,UUID,UUID,UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_owned_observation_photo(UUID,UUID,UUID,UUID,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.resolve_owned_observation_photo(uuid,uuid,uuid,uuid,integer)',
     'Default-off completed private photo resolution; verified Edge owner and deletion fence before temporary signing.');

RESET statement_timeout;
RESET lock_timeout;

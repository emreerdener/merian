SET lock_timeout='5s';
SET statement_timeout='2min';

-- Internal Capture preparation only. A completed immutable manifest must name
-- the exact artifact. This does not resolve mutable/legacy scan media or grant
-- reanalysis admission. Existing photo protocol 8 remains unchanged.
CREATE FUNCTION public.resolve_owned_observation_media(p_owner UUID,p_observation UUID,p_analysis UUID,p_media UUID,p_protocol INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE manifest JSONB; item JSONB; receipt JSONB; matches INTEGER;
BEGIN
    PERFORM internal.require_service_role();
    IF p_protocol IS DISTINCT FROM 1 OR p_analysis IS NULL OR p_media IS NULL THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF (SELECT reader_enabled AND media_reader_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT evidence_manifest INTO manifest FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND analysis_id=p_analysis AND completed_at IS NOT NULL;
    IF NOT FOUND OR manifest->'schema_version' NOT IN ('2'::JSONB,'3'::JSONB,'4'::JSONB,'5'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    IF manifest->'schema_version' IN ('2'::JSONB,'3'::JSONB) THEN
        SELECT count(*),jsonb_agg(value)->0 INTO matches,item
            FROM pg_catalog.jsonb_array_elements(manifest->'items')
            WHERE value->>'media_id'=p_media::TEXT
              AND ((manifest->'schema_version'='2'::JSONB AND value->>'kind'='image')
                OR (manifest->'schema_version'='3'::JSONB AND value->>'kind'='audio'));
    ELSIF manifest->'schema_version'='5'::JSONB THEN
        SELECT count(*),jsonb_agg(artifact)->0 INTO matches,item FROM (
            SELECT value->'artifact' AS artifact FROM pg_catalog.jsonb_array_elements(manifest->'items')
                WHERE value->>'kind' IN ('image','audio')
            UNION ALL SELECT value#>'{provenance,source}' FROM pg_catalog.jsonb_array_elements(manifest->'items')
                WHERE value->>'kind'='video'
            UNION ALL SELECT frame.value->'artifact' FROM pg_catalog.jsonb_array_elements(manifest->'items') node
                CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(node.value#>'{provenance,frames}') frame
                WHERE node.value->>'kind'='video'
            UNION ALL SELECT value#>'{provenance,audio,artifact}' FROM pg_catalog.jsonb_array_elements(manifest->'items')
                WHERE value->>'kind'='video'
        ) AS members WHERE artifact->>'media_id'=p_media::TEXT;
    ELSE
        SELECT count(*),jsonb_agg(artifact)->0 INTO matches,item FROM (
            SELECT manifest#>'{provenance,source}' AS artifact
            UNION ALL SELECT value->'artifact' FROM pg_catalog.jsonb_array_elements(manifest#>'{provenance,frames}')
            UNION ALL SELECT manifest#>'{provenance,audio,artifact}'
        ) AS members WHERE artifact->>'media_id'=p_media::TEXT;
    END IF;
    IF matches IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002';
    END IF;
    receipt:=internal.read_owned_observation_evidence(p_owner,p_observation,p_analysis,p_media);
    IF receipt->'content_type' IS DISTINCT FROM item->'content_type'
        OR receipt->'byte_count' IS DISTINCT FROM item->'byte_count'
        OR receipt->'sha256' IS DISTINCT FROM item->'sha256' THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_owned_observation_media(UUID,UUID,UUID,UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_owned_observation_media(UUID,UUID,UUID,UUID,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)',
     'Private Capture preparation from completed immutable photo/audio/video manifests; verified owner and deletion fence before temporary signing.');

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

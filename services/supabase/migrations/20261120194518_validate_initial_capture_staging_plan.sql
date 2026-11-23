SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Descriptive staging contract only. This helper cannot allocate an object,
-- authorize a client PUT, admit inference, retain evidence or claim funding.
CREATE FUNCTION internal.initial_capture_plan_contract(p_owner UUID, p_plan JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE node JSONB; pair JSONB; prepared JSONB; items JSONB := '[]';
    contract JSONB; artifact JSONB; uploads JSONB := '[]'; audio JSONB := '[]';
    source JSONB; scan TEXT; generation TEXT;
BEGIN
    IF p_owner IS NULL OR jsonb_typeof(p_plan) IS DISTINCT FROM 'object'
        OR NOT(p_plan ?& ARRAY['schema_version','scan_id','generation','items'])
        OR p_plan-ARRAY['schema_version','scan_id','generation','items']<>'{}'
        OR p_plan->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR jsonb_typeof(p_plan->'scan_id') IS DISTINCT FROM 'string'
        OR jsonb_typeof(p_plan->'generation') IS DISTINCT FROM 'string'
        OR jsonb_typeof(p_plan->'items') IS DISTINCT FROM 'array'
        OR octet_length(p_plan::TEXT)>1044480 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    scan := p_plan->>'scan_id'; generation := p_plan->>'generation';
    IF jsonb_array_length(p_plan->'items') NOT BETWEEN 1 AND 64
        OR p_owner::TEXT IN (scan,generation) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOR node IN SELECT value FROM jsonb_array_elements(p_plan->'items') LOOP
        pair := NULL;
        IF node->>'kind'='audio' THEN
            IF jsonb_typeof(node) IS DISTINCT FROM 'object'
                OR NOT(node ?& ARRAY['kind','source','prepared_media_id'])
                OR node-ARRAY['kind','source','prepared_media_id']<>'{}' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            pair := node-'kind';
        ELSIF node->>'kind'='video' THEN
            IF jsonb_typeof(node) IS DISTINCT FROM 'object'
                OR NOT(node ?& ARRAY['kind','source','playback','frames','audio'])
                OR node-ARRAY['kind','source','playback','frames','audio']<>'{}' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            IF node->'audio'<>'null'::JSONB THEN pair := node->'audio'; END IF;
        END IF;
        IF pair IS NOT NULL THEN
            IF jsonb_typeof(pair) IS DISTINCT FROM 'object'
                OR NOT(pair ?& ARRAY['source','prepared_media_id'])
                OR pair-ARRAY['source','prepared_media_id']<>'{}'
                OR pair#>'{source,content_type}' IS DISTINCT FROM '"audio/wav"'::JSONB
                OR jsonb_typeof(pair->'prepared_media_id') IS DISTINCT FROM 'string' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            -- Minimum-sized placeholders reuse V9 shape/ID/budget validation.
            -- They never leave this function and no placeholder digest is
            -- returned or admitted. Actual DSP output must pass V9 separately.
            prepared := jsonb_build_object('media_id',pair->'prepared_media_id',
                'content_type','audio/wav','byte_count',46,'sha256',repeat('0',64));
            pair := jsonb_build_object('source',pair->'source','prepared',prepared);
            IF node->>'kind'='audio' THEN node := jsonb_build_object('kind','audio')||pair;
            ELSE node := jsonb_set(node,'{audio}',pair); END IF;
        END IF;
        items := items||jsonb_build_array(node);
    END LOOP;
    contract := internal.initial_evidence_contract(jsonb_build_object('schema_version',9,'items',items),scan,generation);
    FOR artifact IN SELECT value FROM jsonb_array_elements(contract->'items') LOOP
        IF artifact->>'media_id'=p_owner::TEXT THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF artifact->>'role' IN ('prepared_audio','prepared_companion_audio') THEN
            SELECT value INTO source FROM jsonb_array_elements(contract->'items')
                WHERE value->'item_index'=artifact->'item_index'
                AND value->>'role'=CASE artifact->>'role' WHEN 'prepared_audio' THEN 'source_audio' ELSE 'source_companion_audio' END;
            IF source IS NULL THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            audio := audio||jsonb_build_array(jsonb_build_object('source',source,
                'prepared_media_id',artifact->'media_id','companion',artifact->>'role'='prepared_companion_audio'));
        ELSE uploads := uploads||jsonb_build_array(artifact); END IF;
    END LOOP;
    RETURN jsonb_build_object('scan_id',scan,'generation',generation,'uploads',uploads,'audio',audio);
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_capture_plan_contract(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;

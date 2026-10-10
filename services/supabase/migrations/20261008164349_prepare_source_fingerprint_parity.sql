SET lock_timeout='5s';
SET statement_timeout='2min';

-- Pure, ungranted metadata encoders. No source claim or admission is installed.
CREATE FUNCTION internal.observation_source_fingerprint_bytes(p_input JSONB)
RETURNS BYTEA LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE
    schema_version INTEGER; observation TEXT; analysis TEXT; source TEXT; field TEXT;
    manifest JSONB; item JSONB; media TEXT; byte_count BIGINT; total_bytes BIGINT:=0;
    media_count INTEGER:=0; text_units INTEGER:=0; units INTEGER; text_value TEXT;
    seen TEXT[]:=ARRAY[]::TEXT[]; fields TEXT[]; framed BYTEA:=''::BYTEA; bytes BYTEA;
    -- ECMAScript TrimString whitespace/line terminators, not locale-dependent SQL trim.
    whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object'
        OR NOT(p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input-ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' NOT IN ('2'::JSONB,'3'::JSONB)
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR jsonb_typeof(p_input->'request_digest') IS DISTINCT FROM 'string'
        OR p_input->>'request_digest' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    schema_version:=(p_input->>'schema_version')::NUMERIC::INTEGER;
    IF NOT COALESCE((schema_version=2 AND p_input->'history_protocol'='8'::JSONB
            AND p_input->>'expected_processor_permission' IN ('google_gemini','openai'))
        OR (schema_version=3 AND p_input->'history_protocol'='9'::JSONB
            AND p_input->>'expected_processor_permission'='google_gemini'),FALSE) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','analysis_id','source_analysis_id'] LOOP
        IF jsonb_typeof(p_input->field) IS DISTINCT FROM 'string'
            OR p_input->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    observation:=p_input->>'observation_id'; analysis:=p_input->>'analysis_id'; source:=p_input->>'source_analysis_id';
    IF observation=analysis OR source IN (observation,analysis) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    manifest:=p_input->'evidence_manifest';
    IF jsonb_typeof(manifest) IS DISTINCT FROM 'object' OR NOT(manifest ?& ARRAY['schema_version','items'])
        OR manifest-ARRAY['schema_version','items']<>'{}' OR manifest->'schema_version' IS DISTINCT FROM p_input->'schema_version'
        OR jsonb_typeof(manifest->'items') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(manifest->'items') NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    fields:=ARRAY['merian.analysis-source-reservation','1',schema_version::TEXT,observation,analysis,source,
        p_input->>'request_digest','3','6',CASE WHEN schema_version=2 THEN '8' ELSE '9' END,
        p_input->>'expected_processor_permission',CASE WHEN schema_version=2 THEN 'multimodal_photo_v1' ELSE 'multimodal_audio_v1' END,
        schema_version::TEXT,jsonb_array_length(manifest->'items')::TEXT];
    FOR item IN SELECT value FROM jsonb_array_elements(manifest->'items') LOOP
        IF jsonb_typeof(item) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF item->>'kind'='description' THEN
            IF NOT(item ?& ARRAY['kind','text']) OR item-ARRAY['kind','text']<>'{}'
                OR jsonb_typeof(item->'text') IS DISTINCT FROM 'string' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            text_value:=item->>'text';
            IF char_length(text_value)>8192 OR btrim(text_value,whitespace)='' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units
                FROM regexp_split_to_table(text_value,'') c;
            text_units:=text_units+units;
            IF units>16384 OR text_units>32000 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            fields:=fields || ARRAY['description',text_value];
        ELSE
            IF NOT(item ?& ARRAY['kind','media_id','content_type','byte_count','sha256'])
                OR item-ARRAY['kind','media_id','content_type','byte_count','sha256']<>'{}'
                OR jsonb_typeof(item->'media_id') IS DISTINCT FROM 'string'
                OR item->>'media_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                OR jsonb_typeof(item->'sha256') IS DISTINCT FROM 'string' OR item->>'sha256' !~ '^[0-9a-f]{64}$'
                OR jsonb_typeof(item->'byte_count') IS DISTINCT FROM 'number'
                OR NOT COALESCE((schema_version=2 AND item->>'kind'='image' AND item->>'content_type' IN ('image/jpeg','image/png'))
                    OR (schema_version=3 AND item->>'kind'='audio' AND item->>'content_type'='audio/wav'),FALSE) THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            IF (item->>'byte_count')::NUMERIC<>trunc((item->>'byte_count')::NUMERIC)
                OR (item->>'byte_count')::NUMERIC NOT BETWEEN (CASE WHEN schema_version=2 THEN 1 ELSE 46 END)
                    AND (CASE WHEN schema_version=2 THEN 5242880 ELSE 2700000 END) THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            byte_count:=(item->>'byte_count')::NUMERIC::BIGINT; media:=item->>'media_id';
            IF media IN (observation,analysis,source) OR media=ANY(seen) THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            seen:=array_append(seen,media); media_count:=media_count+1; total_bytes:=total_bytes+byte_count;
            IF media_count>(CASE WHEN schema_version=2 THEN 5 ELSE 1 END)
                OR total_bytes>(CASE WHEN schema_version=2 THEN 5242880 ELSE 2700000 END) THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            fields:=fields || ARRAY[item->>'kind',media,item->>'content_type',byte_count::TEXT,item->>'sha256'];
        END IF;
    END LOOP;
    IF media_count=0 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    FOREACH field IN ARRAY fields LOOP
        bytes:=convert_to(field,'UTF8');
        framed:=framed || convert_to(octet_length(bytes)::TEXT || ':','UTF8') || bytes || convert_to(',','UTF8');
        IF octet_length(framed)>262144 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END LOOP;
    RETURN framed;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_source_fingerprint_bytes(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_source_fingerprint(p_input JSONB)
RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT pg_catalog.encode(extensions.digest(internal.observation_source_fingerprint_bytes(p_input),'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION internal.observation_source_fingerprint(JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.observation_source_fingerprint_bytes(JSONB) IS
    'Pure source fingerprint v1 UTF8 netstrings; no authorization, storage or execution. Original request digest remains a replay identifier.';
RESET statement_timeout;
RESET lock_timeout;

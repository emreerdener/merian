SET lock_timeout='5s';
SET statement_timeout='2min';

-- Held metadata codec only. These helpers have no installed consumer or API grant.
CREATE FUNCTION internal.observation_video_fingerprint_integer(p_value JSONB, p_min BIGINT, p_max BIGINT)
RETURNS BIGINT LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE value NUMERIC;
BEGIN
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    value:=(p_value #>> '{}')::NUMERIC;
    IF value<>trunc(value) OR value NOT BETWEEN p_min AND p_max THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    RETURN value::BIGINT;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_fingerprint_integer(JSONB,BIGINT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_video_fingerprint_artifact(p_value JSONB, p_types TEXT[], p_min BIGINT, p_max BIGINT)
RETURNS TEXT[] LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE count_bytes BIGINT;
BEGIN
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'object'
        OR NOT(p_value ?& ARRAY['media_id','content_type','byte_count','sha256'])
        OR p_value-ARRAY['media_id','content_type','byte_count','sha256']<>'{}'
        OR jsonb_typeof(p_value->'media_id') IS DISTINCT FROM 'string'
        OR p_value->>'media_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR jsonb_typeof(p_value->'content_type') IS DISTINCT FROM 'string'
        OR NOT COALESCE(p_value->>'content_type'=ANY(p_types),FALSE)
        OR jsonb_typeof(p_value->'sha256') IS DISTINCT FROM 'string'
        OR p_value->>'sha256' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    count_bytes:=internal.observation_video_fingerprint_integer(p_value->'byte_count',p_min,p_max);
    RETURN ARRAY[p_value->>'media_id',p_value->>'content_type',count_bytes::TEXT,p_value->>'sha256'];
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_fingerprint_artifact(JSONB,TEXT[],BIGINT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_video_source_fingerprint_bytes(p_input JSONB)
RETURNS BYTEA LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE
    observation TEXT; analysis TEXT; historical_source TEXT; source_id TEXT; field TEXT;
    manifest JSONB; graph JSONB; parameters JSONB; frame JSONB; audio JSONB; description JSONB;
    fields TEXT[]; artifact TEXT[]; seen TEXT[];
    duration BIGINT; crop BIGINT; edge BIGINT; frame_index INTEGER:=0;
    requested BIGINT; actual BIGINT; previous_time BIGINT:=-1; frame_bytes BIGINT:=0;
    start_ticks BIGINT; end_ticks BIGINT; samples BIGINT;
    text_value TEXT; units INTEGER; text_units INTEGER:=0;
    framed BYTEA:=''::BYTEA; bytes BYTEA;
    whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::TEXT)>1044480
        OR NOT(p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input-ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' IS DISTINCT FROM '4'::JSONB
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB
        OR p_input->'history_protocol' IS DISTINCT FROM '9'::JSONB
        OR p_input->'expected_processor_permission' IS DISTINCT FROM '"google_gemini"'::JSONB
        OR jsonb_typeof(p_input->'request_digest') IS DISTINCT FROM 'string'
        OR p_input->>'request_digest' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['observation_id','analysis_id','source_analysis_id'] LOOP
        IF jsonb_typeof(p_input->field) IS DISTINCT FROM 'string'
            OR p_input->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    observation:=p_input->>'observation_id'; analysis:=p_input->>'analysis_id'; historical_source:=p_input->>'source_analysis_id';
    IF observation=analysis OR historical_source IN (observation,analysis) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    seen:=ARRAY[observation,analysis,historical_source];
    manifest:=p_input->'evidence_manifest';
    IF jsonb_typeof(manifest) IS DISTINCT FROM 'object'
        OR NOT(manifest ?& ARRAY['schema_version','provenance','descriptions'])
        OR manifest-ARRAY['schema_version','provenance','descriptions']<>'{}'
        OR manifest->'schema_version' IS DISTINCT FROM '4'::JSONB
        OR jsonb_typeof(manifest->'descriptions') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(manifest->'descriptions')>64 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    graph:=manifest->'provenance';
    IF jsonb_typeof(graph) IS DISTINCT FROM 'object'
        OR NOT(graph ?& ARRAY['schema_version','preprocessing_version','source','parameters','frames','audio'])
        OR graph-ARRAY['schema_version','preprocessing_version','source','parameters','frames','audio']<>'{}'
        OR graph->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR graph->'preprocessing_version' IS DISTINCT FROM '"retained_clip_v1"'::JSONB
        OR jsonb_typeof(graph->'frames') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(graph->'frames')<>5 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    audio:=graph->'audio';
    fields:=ARRAY['merian.analysis-video-source-binding','1','4',observation,analysis,historical_source,
        p_input->>'request_digest','3','6','9','google_gemini',
        CASE WHEN audio='null'::JSONB THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END,
        '4','1','retained_clip_v1'];
    artifact:=internal.observation_video_fingerprint_artifact(graph->'source',ARRAY['video/mp4'],1,12582912);
    source_id:=artifact[1];
    IF source_id=ANY(seen) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    seen:=array_append(seen,source_id); fields:=fields || artifact;
    parameters:=graph->'parameters';
    IF jsonb_typeof(parameters) IS DISTINCT FROM 'object'
        OR NOT(parameters ?& ARRAY['timescale','frame_pipeline','decode_long_edge','duration_ticks','sampling','preferred_track_transform','crop','crop_center_basis_points','inference_long_edge','encoding_quality_percent'])
        OR parameters-ARRAY['timescale','frame_pipeline','decode_long_edge','duration_ticks','sampling','preferred_track_transform','crop','crop_center_basis_points','inference_long_edge','encoding_quality_percent']<>'{}'
        OR parameters->'timescale' IS DISTINCT FROM '600'::JSONB
        OR parameters->'frame_pipeline' IS DISTINCT FROM '"direct_inference_v1"'::JSONB
        OR parameters->'decode_long_edge' IS DISTINCT FROM '2048'::JSONB
        OR parameters->'sampling' IS DISTINCT FROM '"five_interior_v1"'::JSONB
        OR parameters->'preferred_track_transform' IS DISTINCT FROM 'true'::JSONB
        OR parameters->'crop' IS DISTINCT FROM '"square_v1"'::JSONB
        OR parameters->'encoding_quality_percent' IS DISTINCT FROM '85'::JSONB THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    duration:=internal.observation_video_fingerprint_integer(parameters->'duration_ticks',60,3000);
    crop:=internal.observation_video_fingerprint_integer(parameters->'crop_center_basis_points',0,10000);
    edge:=internal.observation_video_fingerprint_integer(parameters->'inference_long_edge',768,1024);
    IF edge NOT IN (768,1024) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    fields:=fields || ARRAY['600','direct_inference_v1','2048',duration::TEXT,'five_interior_v1','1','square_v1',crop::TEXT,edge::TEXT,'85','5'];
    FOR frame IN SELECT value FROM jsonb_array_elements(graph->'frames') LOOP
        requested:=least(greatest((duration*(1+2*frame_index)+5)/10,30),duration-30);
        IF jsonb_typeof(frame) IS DISTINCT FROM 'object'
            OR NOT(frame ?& ARRAY['index','source_media_id','requested_time_ticks','actual_time_ticks','artifact'])
            OR frame-ARRAY['index','source_media_id','requested_time_ticks','actual_time_ticks','artifact']<>'{}'
            OR frame->'source_media_id' IS DISTINCT FROM to_jsonb(source_id) THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        PERFORM internal.observation_video_fingerprint_integer(frame->'index',frame_index,frame_index);
        PERFORM internal.observation_video_fingerprint_integer(frame->'requested_time_ticks',requested,requested);
        actual:=internal.observation_video_fingerprint_integer(frame->'actual_time_ticks',greatest(previous_time,0),duration-1);
        previous_time:=actual;
        artifact:=internal.observation_video_fingerprint_artifact(frame->'artifact',ARRAY['image/webp','image/jpeg'],1,5242880);
        frame_bytes:=frame_bytes+artifact[3]::BIGINT;
        IF frame_bytes>5242880 OR artifact[1]=ANY(seen) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        seen:=array_append(seen,artifact[1]);
        fields:=fields || ARRAY[frame_index::TEXT,source_id,requested::TEXT,actual::TEXT] || artifact;
        frame_index:=frame_index+1;
    END LOOP;
    fields:=array_append(fields,CASE WHEN audio='null'::JSONB THEN '0' ELSE '1' END);
    IF audio<>'null'::JSONB THEN
        IF jsonb_typeof(audio) IS DISTINCT FROM 'object'
            OR NOT(audio ?& ARRAY['source_media_id','track','start_ticks','end_ticks','sample_rate','sample_count','channels','bits_per_sample','encoding','artifact'])
            OR audio-ARRAY['source_media_id','track','start_ticks','end_ticks','sample_rate','sample_count','channels','bits_per_sample','encoding','artifact']<>'{}'
            OR audio->'source_media_id' IS DISTINCT FROM to_jsonb(source_id)
            OR audio->'track' IS DISTINCT FROM '"first_audio_track"'::JSONB
            OR audio->'sample_rate' IS DISTINCT FROM '44100'::JSONB
            OR audio->'channels' IS DISTINCT FROM '1'::JSONB
            OR audio->'bits_per_sample' IS DISTINCT FROM '16'::JSONB
            OR audio->'encoding' IS DISTINCT FROM '"pcm_s16le"'::JSONB THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        start_ticks:=internal.observation_video_fingerprint_integer(audio->'start_ticks',0,duration-1);
        end_ticks:=internal.observation_video_fingerprint_integer(audio->'end_ticks',start_ticks+1,duration);
        samples:=internal.observation_video_fingerprint_integer(audio->'sample_count',1,220500);
        IF abs(samples*600-(end_ticks-start_ticks)*44100)>44100 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        artifact:=internal.observation_video_fingerprint_artifact(audio->'artifact',ARRAY['audio/wav'],44+samples*2,2700000);
        IF artifact[1]=ANY(seen) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        fields:=fields || ARRAY[source_id,'first_audio_track',start_ticks::TEXT,end_ticks::TEXT,'44100',samples::TEXT,'1','16','pcm_s16le'] || artifact;
    END IF;
    fields:=array_append(fields,jsonb_array_length(manifest->'descriptions')::TEXT);
    FOR description IN SELECT value FROM jsonb_array_elements(manifest->'descriptions') LOOP
        IF jsonb_typeof(description) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        text_value:=description #>> '{}';
        IF char_length(text_value)>8192 OR btrim(text_value,whitespace)='' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units FROM regexp_split_to_table(text_value,'') c;
        text_units:=text_units+units;
        IF units>16384 OR text_units>32000 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        fields:=array_append(fields,text_value);
    END LOOP;
    FOREACH field IN ARRAY fields LOOP
        bytes:=convert_to(field,'UTF8');
        framed:=framed || convert_to(octet_length(bytes)::TEXT || ':','UTF8') || bytes || convert_to(',','UTF8');
        IF octet_length(framed)>262144 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END LOOP;
    RETURN framed;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_fingerprint_bytes(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_video_source_fingerprint(p_input JSONB)
RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
    SELECT pg_catalog.encode(extensions.digest(internal.observation_video_source_fingerprint_bytes(p_input),'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_fingerprint(JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.observation_video_source_fingerprint_bytes(JSONB) IS
    'Held video metadata fingerprint v1 UTF8 netstrings. Semantic integer spelling; no authorization, byte proof, reservation or execution. Separate from live photo/audio codecs.';
RESET statement_timeout;
RESET lock_timeout;

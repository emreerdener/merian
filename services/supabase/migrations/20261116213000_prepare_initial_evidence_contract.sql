SET lock_timeout='5s';
SET statement_timeout='2min';

-- Ordinary ingestion evidence is a truthful record of retained source and
-- provider artifacts. It is NOT a retained_clip_v1 reanalysis recipe. No API
-- grants, enrollment, execution or rollout activation are installed here.
CREATE FUNCTION internal.initial_evidence_artifact_fields(p_value JSONB,p_kind TEXT)
RETURNS TEXT[] LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE size NUMERIC; allowed TEXT[]; maximum INTEGER;
BEGIN
    IF p_kind='source_image' THEN allowed:=ARRAY['image/jpeg','image/png','image/webp','image/heic','image/heif']; maximum:=5242880;
    ELSIF p_kind='source_audio' THEN allowed:=ARRAY['audio/wav','audio/mp4']; maximum:=2700000;
    ELSIF p_kind='image' THEN allowed:=ARRAY['image/jpeg','image/png']; maximum:=5242880;
    ELSIF p_kind='audio' THEN allowed:=ARRAY['audio/wav']; maximum:=2700000;
    ELSIF p_kind='video' THEN allowed:=ARRAY['video/mp4']; maximum:=12582912;
    ELSE RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'object'
        OR NOT(p_value ?& ARRAY['media_id','content_type','byte_count','sha256'])
        OR p_value-ARRAY['media_id','content_type','byte_count','sha256']<>'{}'
        OR jsonb_typeof(p_value->'media_id') IS DISTINCT FROM 'string'
        OR p_value->>'media_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR jsonb_typeof(p_value->'content_type') IS DISTINCT FROM 'string'
        OR NOT(p_value->>'content_type'=ANY(allowed))
        OR jsonb_typeof(p_value->'byte_count') IS DISTINCT FROM 'number'
        OR jsonb_typeof(p_value->'sha256') IS DISTINCT FROM 'string'
        OR p_value->>'sha256' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    size:=(p_value->>'byte_count')::NUMERIC;
    IF size<>trunc(size) OR size<(CASE WHEN p_kind IN ('audio','source_audio') AND p_value->>'content_type'='audio/wav' THEN 46 ELSE 1 END) OR size>maximum THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    RETURN ARRAY[p_value->>'media_id',p_value->>'content_type',size::INTEGER::TEXT,p_value->>'sha256'];
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_evidence_artifact_fields(JSONB,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_evidence_contract(p_manifest JSONB,p_scan TEXT,p_generation TEXT)
RETURNS JSONB LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE
    fields TEXT[]; artifact TEXT[]; seen TEXT[]; field TEXT; bytes BYTEA; framed BYTEA:=''::BYTEA;
    node JSONB; entry JSONB; node_items JSONB; inventory JSONB:='[]'::JSONB; text_value TEXT;
    node_index INTEGER:=0; frame_index INTEGER; physical INTEGER:=0; photos INTEGER:=0; videos INTEGER:=0; audios INTEGER:=0;
    units INTEGER; text_units INTEGER:=0; total_bytes BIGINT:=0; image_bytes BIGINT:=0;
    whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF p_scan IS NULL OR p_generation IS NULL OR p_scan=p_generation
        OR p_scan !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR p_generation !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR jsonb_typeof(p_manifest) IS DISTINCT FROM 'object'
        OR NOT(p_manifest ?& ARRAY['schema_version','items']) OR p_manifest-ARRAY['schema_version','items']<>'{}'
        OR p_manifest->'schema_version' IS DISTINCT FROM '7'::JSONB
        OR jsonb_typeof(p_manifest->'items') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(p_manifest->'items') NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    fields:=ARRAY['merian.initial-evidence','1',p_scan,p_generation,'7',jsonb_array_length(p_manifest->'items')::TEXT];
    seen:=ARRAY[p_scan,p_generation];
    FOR node IN SELECT value FROM jsonb_array_elements(p_manifest->'items') LOOP
        IF jsonb_typeof(node) IS DISTINCT FROM 'object' OR jsonb_typeof(node->'kind') IS DISTINCT FROM 'string'
            OR node->>'kind' NOT IN ('description','image','audio','video') THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        fields:=array_append(fields,node->>'kind'); node_items:='[]'::JSONB;
        IF node->>'kind'='description' THEN
            IF NOT(node ?& ARRAY['kind','text']) OR node-ARRAY['kind','text']<>'{}'
                OR jsonb_typeof(node->'text') IS DISTINCT FROM 'string' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            text_value:=node->>'text';
            SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units FROM regexp_split_to_table(text_value,'') c;
            text_units:=text_units+units;
            IF char_length(text_value)>8192 OR btrim(text_value,whitespace)='' OR units>16384 OR text_units>32000 THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            fields:=array_append(fields,text_value);
        ELSIF node->>'kind' IN ('image','audio') THEN
            physical:=physical+1;
            IF node->>'kind'='image' THEN
                photos:=photos+1;
                IF NOT(node ?& ARRAY['kind','source','prepared','coordinate_basis','focus_region'])
                    OR node-ARRAY['kind','source','prepared','coordinate_basis','focus_region']<>'{}'
                    OR node->'coordinate_basis' IS DISTINCT FROM '"prepared_image_top_left_v1"'::JSONB THEN
                    RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
                END IF;
            ELSE
                audios:=audios+1;
                IF NOT(node ?& ARRAY['kind','source','prepared']) OR node-ARRAY['kind','source','prepared']<>'{}' THEN
                    RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
                END IF;
            END IF;
            FOREACH field IN ARRAY ARRAY['source','prepared'] LOOP
                artifact:=internal.initial_evidence_artifact_fields(node->field,(CASE WHEN field='source' THEN 'source_' ELSE '' END)||(node->>'kind')); fields:=fields||artifact;
                node_items:=node_items||jsonb_build_array((node->field)||jsonb_build_object('item_index',node_index,'role',field||'_'||(node->>'kind'),'role_index',0));
            END LOOP;
            IF node->>'kind'='image' THEN
                fields:=array_append(fields,'prepared_image_top_left_v1');
                IF node->'focus_region'='null'::JSONB THEN fields:=array_append(fields,'0');
                ELSE fields:=fields||ARRAY['1']||internal.observation_focus_fingerprint_fields(node->'focus_region'); END IF;
            END IF;
        ELSE
            physical:=physical+1; videos:=videos+1;
            IF NOT(node ?& ARRAY['kind','source','playback','frames','audio']) OR node-ARRAY['kind','source','playback','frames','audio']<>'{}'
                OR jsonb_typeof(node->'frames') IS DISTINCT FROM 'array' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            IF jsonb_array_length(node->'frames') NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            artifact:=internal.initial_evidence_artifact_fields(node->'source','video'); fields:=fields||artifact;
            node_items:=jsonb_build_array((node->'source')||jsonb_build_object('item_index',node_index,'role','source_video','role_index',0));
            artifact:=internal.initial_evidence_artifact_fields(node->'playback','video'); fields:=fields||artifact;
            node_items:=node_items||jsonb_build_array((node->'playback')||jsonb_build_object('item_index',node_index,'role','playback_video','role_index',0));
            fields:=array_append(fields,jsonb_array_length(node->'frames')::TEXT); frame_index:=0;
            FOR entry IN SELECT value FROM jsonb_array_elements(node->'frames') LOOP
                artifact:=internal.initial_evidence_artifact_fields(entry,'image'); fields:=fields||artifact;
                node_items:=node_items||jsonb_build_array(entry||jsonb_build_object('item_index',node_index,'role','inference_frame','role_index',frame_index));
                frame_index:=frame_index+1;
            END LOOP;
            IF node->'audio'='null'::JSONB THEN fields:=array_append(fields,'0');
            ELSE
                audios:=audios+1;
                IF jsonb_typeof(node->'audio') IS DISTINCT FROM 'object' OR NOT((node->'audio') ?& ARRAY['source','prepared'])
                    OR (node->'audio')-ARRAY['source','prepared']<>'{}' THEN
                    RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
                END IF;
                fields:=array_append(fields,'1');
                FOREACH field IN ARRAY ARRAY['source','prepared'] LOOP
                    entry:=node->'audio'->field;
                    artifact:=internal.initial_evidence_artifact_fields(entry,CASE WHEN field='source' THEN 'source_audio' ELSE 'audio' END); fields:=fields||artifact;
                    node_items:=node_items||jsonb_build_array(entry||jsonb_build_object('item_index',node_index,'role',field||'_companion_audio','role_index',0));
                END LOOP;
            END IF;
        END IF;
        FOR entry IN SELECT value FROM jsonb_array_elements(node_items) LOOP
            IF entry->>'media_id'=ANY(seen) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            seen:=array_append(seen,entry->>'media_id');
            total_bytes:=total_bytes+(entry->>'byte_count')::BIGINT;
            IF entry->>'role' IN ('prepared_image','inference_frame') THEN image_bytes:=image_bytes+(entry->>'byte_count')::BIGINT; END IF;
        END LOOP;
        inventory:=inventory||node_items; node_index:=node_index+1;
    END LOOP;
    IF physical<1 OR physical>(CASE WHEN physical=photos THEN 5 ELSE 2 END) OR videos>1 OR audios>2
        OR total_bytes>33554432 OR image_bytes>5242880 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY fields LOOP
        bytes:=convert_to(field,'UTF8'); framed:=framed||convert_to(octet_length(bytes)::TEXT||':','UTF8')||bytes||convert_to(',','UTF8');
    END LOOP;
    RETURN jsonb_build_object('evidence_digest',encode(extensions.digest(framed,'sha256'),'hex'),'items',inventory);
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_evidence_contract(JSONB,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

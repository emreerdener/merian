SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private metadata codecs only. No caller grant, rollout activation, funded
-- admission, execution or source reuse is installed by this migration.
CREATE FUNCTION internal.observation_focus_fingerprint_fields(p_focus JSONB)
RETURNS TEXT[] LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE
    fields TEXT[]:=ARRAY[]::TEXT[]; key TEXT; coordinates DOUBLE PRECISION[]:=ARRAY[]::DOUBLE PRECISION[];
    coordinate DOUBLE PRECISION;
BEGIN
    IF jsonb_typeof(p_focus) IS DISTINCT FROM 'object'
        OR NOT(p_focus ?& ARRAY['x','y','width','height','source'])
        OR p_focus-ARRAY['x','y','width','height','source']<>'{}'
        OR jsonb_typeof(p_focus->'source') IS DISTINCT FROM 'string'
        OR p_focus->>'source' NOT IN ('vision_objectness','user_selection') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH key IN ARRAY ARRAY['x','y','width','height'] LOOP
        IF jsonb_typeof(p_focus->key) IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        BEGIN
            coordinate:=(p_focus->>key)::DOUBLE PRECISION;
        EXCEPTION WHEN numeric_value_out_of_range THEN
            -- PostgreSQL reports rounded-to-zero underflow; binary64 JSON
            -- decoding in Swift/JS yields zero. Preserve representable
            -- subnormals, and never convert an overflow to zero.
            IF abs((p_focus->>key)::NUMERIC)<5e-324::NUMERIC THEN
                coordinate:=0;
            ELSE RAISE;
            END IF;
        END;
        IF coordinate='NaN'::DOUBLE PRECISION OR coordinate IN ('Infinity'::DOUBLE PRECISION,'-Infinity'::DOUBLE PRECISION) THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        IF coordinate=0 THEN coordinate:=0; END IF;
        coordinates:=array_append(coordinates,coordinate);
        fields:=array_append(fields,encode(pg_catalog.float8send(coordinate),'hex'));
    END LOOP;
    -- Bounds use binary64 arithmetic, like Swift/JS, not JSONB decimal sums.
    IF coordinates[1]<0 OR coordinates[2]<0 OR coordinates[3]<=0 OR coordinates[4]<=0
        OR coordinates[1]+coordinates[3]>1 OR coordinates[2]+coordinates[4]>1 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    RETURN array_append(fields,p_focus->>'source');
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_focus_fingerprint_fields(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_focused_composition_contract(p_input JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE
    manifest JSONB; node JSONB; graph JSONB; parameters JSONB; frame JSONB; sound JSONB;
    item JSONB; video_input JSONB; inventory JSONB:='[]'::JSONB; node_items JSONB;
    fields TEXT[]; artifact TEXT[]; seen TEXT[]; field TEXT; text_value TEXT;
    node_index INTEGER:=0; physical INTEGER:=0; photos INTEGER:=0; videos INTEGER:=0; audios INTEGER:=0;
    units INTEGER; text_units INTEGER:=0; total_bytes BIGINT:=0; image_bytes BIGINT:=0;
    framed BYTEA:=''::BYTEA; unsigned_framed BYTEA:=''::BYTEA; bytes BYTEA; unsigned_fields TEXT[];
    whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::TEXT)>1044480
        OR NOT(p_input ?& ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission'])
        OR p_input-ARRAY['schema_version','observation_id','analysis_id','source_analysis_id','request_digest','evidence_manifest','entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']<>'{}'
        OR p_input->'schema_version' IS DISTINCT FROM '6'::JSONB
        OR p_input->'entitlement_protocol' IS DISTINCT FROM '3'::JSONB
        OR p_input->'identification_protocol' IS DISTINCT FROM '7'::JSONB
        OR p_input->'history_protocol' IS DISTINCT FROM '10'::JSONB
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
    seen:=ARRAY[p_input->>'observation_id',p_input->>'analysis_id',p_input->>'source_analysis_id'];
    IF seen[1]=seen[2] OR seen[3]=ANY(seen[1:2]) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    manifest:=p_input->'evidence_manifest';
    IF jsonb_typeof(manifest) IS DISTINCT FROM 'object'
        OR NOT(manifest ?& ARRAY['schema_version','items']) OR manifest-ARRAY['schema_version','items']<>'{}'
        OR manifest->'schema_version' IS DISTINCT FROM '6'::JSONB
        OR jsonb_typeof(manifest->'items') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(manifest->'items') NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    fields:=ARRAY['merian.analysis-composition-source-binding','2','6',seen[1],seen[2],seen[3],
        p_input->>'request_digest','3','7','10','google_gemini','6',jsonb_array_length(manifest->'items')::TEXT];
    FOR node IN SELECT value FROM jsonb_array_elements(manifest->'items') LOOP
        IF jsonb_typeof(node) IS DISTINCT FROM 'object' OR jsonb_typeof(node->'kind') IS DISTINCT FROM 'string'
            OR node->>'kind' NOT IN ('description','image','audio','video') THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
        fields:=array_append(fields,node->>'kind');
        node_items:='[]'::JSONB;
        IF node->>'kind'='description' THEN
            IF NOT(node ?& ARRAY['kind','text']) OR node-ARRAY['kind','text']<>'{}'
                OR jsonb_typeof(node->'text') IS DISTINCT FROM 'string' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            text_value:=node->>'text';
            IF char_length(text_value)>8192 OR btrim(text_value,whitespace)='' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            SELECT COALESCE(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0) INTO units FROM regexp_split_to_table(text_value,'') c;
            text_units:=text_units+units;
            IF units>16384 OR text_units>32000 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            fields:=array_append(fields,text_value);
        ELSIF node->>'kind' IN ('image','audio') THEN
            physical:=physical+1;
            IF NOT(node ?& ARRAY['kind','artifact'])
                OR node-(CASE WHEN node->>'kind'='image' THEN ARRAY['kind','artifact','focus_region'] ELSE ARRAY['kind','artifact'] END)<>'{}' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            IF node->>'kind'='image' THEN
                photos:=photos+1;
                artifact:=internal.observation_video_fingerprint_artifact(node->'artifact',ARRAY['image/jpeg','image/png'],1,5242880);
            ELSE
                artifact:=internal.observation_video_fingerprint_artifact(node->'artifact',ARRAY['audio/wav'],46,2700000);
            END IF;
            fields:=fields||artifact;
            IF node->>'kind'='image' THEN
                fields:=array_append(fields,CASE WHEN node ? 'focus_region' THEN '1' ELSE '0' END);
                IF node ? 'focus_region' THEN
                    fields:=fields||internal.observation_focus_fingerprint_fields(node->'focus_region');
                END IF;
            END IF;
            node_items:=jsonb_build_array((node->'artifact')||jsonb_build_object('node_index',node_index,'role',node->>'kind','frame_index',NULL));
        ELSE
            physical:=physical+1; videos:=videos+1;
            IF videos>1 OR NOT(node ?& ARRAY['kind','provenance']) OR node-ARRAY['kind','provenance']<>'{}' THEN
                RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
            END IF;
            graph:=node->'provenance';
            -- Reuse only the closed retained_clip_v1 *metadata* validator. This
            -- synthetic value is never saved, reserved or sent to an old lane.
            video_input:=p_input||jsonb_build_object('schema_version',4,'identification_protocol',6,'history_protocol',9,
                'evidence_manifest',jsonb_build_object('schema_version',4,'provenance',graph,'descriptions','[]'::JSONB));
            PERFORM internal.observation_video_source_fingerprint_bytes(video_input);
            fields:=fields||ARRAY['1','retained_clip_v1']||internal.observation_video_fingerprint_artifact(graph->'source',ARRAY['video/mp4'],1,12582912);
            parameters:=graph->'parameters';
            fields:=fields||ARRAY['600','direct_inference_v1','2048',((parameters->>'duration_ticks')::NUMERIC)::BIGINT::TEXT,
                'five_interior_v1','1','square_v1',((parameters->>'crop_center_basis_points')::NUMERIC)::BIGINT::TEXT,
                ((parameters->>'inference_long_edge')::NUMERIC)::BIGINT::TEXT,'85','5'];
            node_items:=jsonb_build_array((graph->'source')||jsonb_build_object('node_index',node_index,'role','video_source','frame_index',NULL));
            FOR frame IN SELECT value FROM jsonb_array_elements(graph->'frames') LOOP
                fields:=fields||ARRAY[((frame->>'index')::NUMERIC)::BIGINT::TEXT,frame->>'source_media_id',
                    ((frame->>'requested_time_ticks')::NUMERIC)::BIGINT::TEXT,((frame->>'actual_time_ticks')::NUMERIC)::BIGINT::TEXT]
                    ||internal.observation_video_fingerprint_artifact(frame->'artifact',ARRAY['image/webp','image/jpeg'],1,5242880);
                node_items:=node_items||jsonb_build_array((frame->'artifact')||jsonb_build_object('node_index',node_index,'role','video_frame','frame_index',frame->'index'));
            END LOOP;
            sound:=graph->'audio';
            fields:=array_append(fields,CASE WHEN sound='null'::JSONB THEN '0' ELSE '1' END);
            IF sound<>'null'::JSONB THEN
                fields:=fields||ARRAY[sound->>'source_media_id','first_audio_track',((sound->>'start_ticks')::NUMERIC)::BIGINT::TEXT,
                    ((sound->>'end_ticks')::NUMERIC)::BIGINT::TEXT,'44100',((sound->>'sample_count')::NUMERIC)::BIGINT::TEXT,'1','16','pcm_s16le']
                    ||internal.observation_video_fingerprint_artifact(sound->'artifact',ARRAY['audio/wav'],46,2700000);
                node_items:=node_items||jsonb_build_array((sound->'artifact')||jsonb_build_object('node_index',node_index,'role','video_audio','frame_index',NULL));
            END IF;
        END IF;
        FOR item IN SELECT value FROM jsonb_array_elements(node_items) LOOP
            IF item->>'media_id'=ANY(seen) THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
            seen:=array_append(seen,item->>'media_id');
            total_bytes:=total_bytes+((item->>'byte_count')::NUMERIC)::BIGINT;
            IF item->>'content_type' LIKE 'image/%' THEN image_bytes:=image_bytes+((item->>'byte_count')::NUMERIC)::BIGINT; END IF;
            IF item->>'content_type'='audio/wav' THEN audios:=audios+1; END IF;
            IF total_bytes>33554432 OR image_bytes>5242880 OR audios>2 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        END LOOP;
        inventory:=inventory||node_items;
        node_index:=node_index+1;
    END LOOP;
    IF physical<1 OR physical>(CASE WHEN physical=photos THEN 5 ELSE 2 END) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY fields LOOP
        bytes:=convert_to(field,'UTF8');
        framed:=framed||convert_to(octet_length(bytes)::TEXT||':','UTF8')||bytes||convert_to(',','UTF8');
        IF octet_length(framed)>262144 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END LOOP;
    -- The unsigned request uses the same typed fields, excluding the supplied
    -- request digest (field7) and using a separate domain. V5 is untouched.
    unsigned_fields:=ARRAY['merian.analysis-composition-request']||fields[2:6]||fields[8:array_length(fields,1)];
    FOREACH field IN ARRAY unsigned_fields LOOP
        bytes:=convert_to(field,'UTF8');
        unsigned_framed:=unsigned_framed||convert_to(octet_length(bytes)::TEXT||':','UTF8')||bytes||convert_to(',','UTF8');
    END LOOP;
    IF encode(extensions.digest(unsigned_framed,'sha256'),'hex')<>p_input->>'request_digest' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('fingerprint',encode(extensions.digest(framed,'sha256'),'hex'),
        'request_digest',encode(extensions.digest(unsigned_framed,'sha256'),'hex'),'items',inventory);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_focused_composition_contract(JSONB) FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION internal.observation_focused_composition_contract(JSONB) IS
    'Private schema6 typed request digest and FV2 ordered source fingerprint; no live admission or execution authority.';
RESET statement_timeout;
RESET lock_timeout;

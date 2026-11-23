SET lock_timeout='5s';
SET statement_timeout='2min';

-- V9 adds geometry; neither historical bytes nor an execution gate changes.
CREATE OR REPLACE FUNCTION internal.initial_photo_preparation_fields(p_value JSONB)
RETURNS TEXT[] LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE keys TEXT[]:=ARRAY['schema_version','coordinate_basis','format','crop_display_size','quarter_turns','scale','offset_x','offset_y','camera_vertical_center','source_selection'];
    name TEXT; number DOUBLE PRECISION; fields TEXT[]; selection TEXT[];
BEGIN
    IF jsonb_typeof(p_value) IS DISTINCT FROM 'object' OR NOT(p_value ?& keys) OR p_value-keys<>'{}'
        OR p_value->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR p_value->'coordinate_basis' IS DISTINCT FROM '"upright_source_top_left_v1"'::JSONB
        OR jsonb_typeof(p_value->'format') IS DISTINCT FROM 'string'
        OR p_value->>'format' NOT IN ('nativeStillImageV1','nativeCameraStillV1','nativeSelectedStillImageV2') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    FOREACH name IN ARRAY ARRAY['crop_display_size','quarter_turns','scale','offset_x','offset_y','camera_vertical_center'] LOOP
        IF name IN ('crop_display_size','camera_vertical_center') AND p_value->name='null'::JSONB THEN CONTINUE; END IF;
        IF jsonb_typeof(p_value->name) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
        number:=(p_value->>name)::DOUBLE PRECISION;
        IF number IN ('Infinity'::DOUBLE PRECISION,'-Infinity'::DOUBLE PRECISION,'NaN'::DOUBLE PRECISION)
            OR (name='crop_display_size' AND number<=0) OR (name='quarter_turns' AND (number<>trunc(number) OR number<0 OR number>3))
            OR (name='scale' AND number<1) OR (name='camera_vertical_center' AND (number<0 OR number>1)) THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END LOOP;
    IF p_value->'source_selection'<>'null'::JSONB THEN
        selection:=internal.observation_focus_fingerprint_fields(p_value->'source_selection');
        IF p_value->'source_selection'->'source' IS DISTINCT FROM '"user_selection"'::JSONB THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    END IF;
    IF p_value->'crop_display_size'='null'::JSONB AND (p_value->'quarter_turns'<>'0'::JSONB OR p_value->'scale'<>'1'::JSONB OR p_value->'offset_x'<>'0'::JSONB OR p_value->'offset_y'<>'0'::JSONB) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    IF (p_value->>'format'='nativeCameraStillV1' AND (p_value->'camera_vertical_center'='null'::JSONB OR p_value->'crop_display_size'<>'null'::JSONB OR selection IS NOT NULL))
        OR (p_value->>'format'='nativeStillImageV1' AND (p_value->'camera_vertical_center'<>'null'::JSONB OR selection IS NOT NULL))
        OR (p_value->>'format'='nativeSelectedStillImageV2' AND (p_value->'camera_vertical_center'<>'null'::JSONB OR p_value->'crop_display_size'='null'::JSONB OR selection IS NULL)) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    fields:=ARRAY['1','upright_source_top_left_v1',p_value->>'format'];
    FOREACH name IN ARRAY ARRAY['crop_display_size','quarter_turns','scale','offset_x','offset_y','camera_vertical_center'] LOOP
        IF name IN ('crop_display_size','camera_vertical_center') THEN
            fields:=array_append(fields,CASE WHEN p_value->name='null'::JSONB THEN '0' ELSE '1' END);
            IF p_value->name='null'::JSONB THEN CONTINUE; END IF;
        END IF;
        number:=(p_value->>name)::DOUBLE PRECISION;
        IF name='quarter_turns' THEN fields:=array_append(fields,number::INTEGER::TEXT);
        ELSE fields:=array_append(fields,encode(pg_catalog.float8send(CASE WHEN number=0 THEN 0::DOUBLE PRECISION ELSE number END),'hex')); END IF;
    END LOOP;
    fields:=array_append(fields,CASE WHEN selection IS NULL THEN '0' ELSE '1' END);
    IF selection IS NOT NULL THEN fields:=fields||selection; END IF;
    RETURN fields;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_photo_preparation_fields(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.initial_evidence_contract(p_manifest jsonb, p_scan text, p_generation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    fields TEXT[]; artifact TEXT[]; seen TEXT[]; field TEXT; bytes BYTEA; framed BYTEA:=''::BYTEA;
    node JSONB; entry JSONB; node_items JSONB; inventory JSONB:='[]'::JSONB; text_value TEXT;
    node_index INTEGER:=0; frame_index INTEGER; physical INTEGER:=0; photos INTEGER:=0; videos INTEGER:=0; audios INTEGER:=0;
    units INTEGER; text_units INTEGER:=0; total_bytes BIGINT:=0; image_bytes BIGINT:=0; original_bytes BIGINT:=0; version INTEGER;
    whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF p_scan IS NULL OR p_generation IS NULL OR p_scan=p_generation
        OR p_scan !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR p_generation !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR jsonb_typeof(p_manifest) IS DISTINCT FROM 'object'
        OR NOT(p_manifest ?& ARRAY['schema_version','items']) OR p_manifest-ARRAY['schema_version','items']<>'{}'
        OR (p_manifest->'schema_version' IS NULL OR p_manifest->'schema_version' NOT IN ('7'::JSONB,'8'::JSONB,'9'::JSONB))
        OR jsonb_typeof(p_manifest->'items') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    IF jsonb_array_length(p_manifest->'items') NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    version:=CASE WHEN p_manifest->'schema_version'='9'::JSONB THEN 9 WHEN p_manifest->'schema_version'='8'::JSONB THEN 8 ELSE 7 END;
    fields:=ARRAY['merian.initial-evidence','1',p_scan,p_generation,version::TEXT,jsonb_array_length(p_manifest->'items')::TEXT];
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
                IF NOT(node ?& (ARRAY['kind','source','prepared','coordinate_basis','focus_region']||CASE WHEN version=9 THEN ARRAY['preparation'] ELSE ARRAY[]::TEXT[] END))
                    OR node-(ARRAY['kind','source','prepared','coordinate_basis','focus_region']||CASE WHEN version=9 THEN ARRAY['preparation'] ELSE ARRAY[]::TEXT[] END)<>'{}'
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
                artifact:=internal.initial_evidence_artifact_fields(node->field,CASE WHEN version>=8 AND field='source' AND node->>'kind'='image' THEN 'source_image_v8' ELSE (CASE WHEN field='source' THEN 'source_' ELSE '' END)||(node->>'kind') END); fields:=fields||artifact;
                node_items:=node_items||jsonb_build_array((node->field)||jsonb_build_object('item_index',node_index,'role',field||'_'||(node->>'kind'),'role_index',0));
            END LOOP;
            IF node->>'kind'='image' THEN
                fields:=array_append(fields,'prepared_image_top_left_v1');
                IF node->'focus_region'='null'::JSONB THEN fields:=array_append(fields,'0');
                ELSE fields:=fields||ARRAY['1']||internal.observation_focus_fingerprint_fields(node->'focus_region'); END IF;
                IF version=9 THEN fields:=fields||internal.initial_photo_preparation_fields(node->'preparation'); END IF;
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
            IF entry->>'role'='source_image' THEN original_bytes:=original_bytes+(entry->>'byte_count')::BIGINT; END IF;
            IF entry->>'role' IN ('prepared_image','inference_frame') THEN image_bytes:=image_bytes+(entry->>'byte_count')::BIGINT; END IF;
        END LOOP;
        inventory:=inventory||node_items; node_index:=node_index+1;
    END LOOP;
    IF physical<1 OR physical>(CASE WHEN physical=photos THEN 5 ELSE 2 END) OR videos>1 OR audios>2
        OR total_bytes>(CASE WHEN version>=8 THEN 72351744 ELSE 33554432 END)
        OR (version>=8 AND original_bytes>67108864) OR image_bytes>5242880 THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY fields LOOP
        bytes:=convert_to(field,'UTF8'); framed:=framed||convert_to(octet_length(bytes)::TEXT||':','UTF8')||bytes||convert_to(',','UTF8');
    END LOOP;
    RETURN jsonb_build_object('evidence_digest',encode(extensions.digest(framed,'sha256'),'hex'),'items',inventory);
END;
$function$
;
REVOKE ALL ON FUNCTION internal.initial_evidence_contract(JSONB,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Exact predicates only; fail if an ownership implementation has drifted.
DO $patch$
DECLARE change RECORD; definition TEXT;
BEGIN
    FOR change IN SELECT * FROM (VALUES
        ('internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1),
        ('internal.fence_imported_observation_result()', $old$('3'::JSONB,'7'::JSONB,'8'::JSONB)$old$, $new$('3'::JSONB,'7'::JSONB,'8'::JSONB,'9'::JSONB)$new$, 1),
        ('internal.guard_initial_history_baseline()', $old$('7'::JSONB,'8'::JSONB)$old$, $new$('7'::JSONB,'8'::JSONB,'9'::JSONB)$new$, 1),
        ('internal.observation_result_snapshot(internal.observation_analysis_results)', $old$('7'::JSONB,'8'::JSONB)$old$, $new$('7'::JSONB,'8'::JSONB,'9'::JSONB)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader IN (11,14,15,16,17)$old$, $new$p_reader IN (11,14,15,16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader NOT IN (11,14,15,16,17)$old$, $new$p_reader NOT IN (11,14,15,16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader NOT IN (14,15,16,17)$old$, $new$p_reader NOT IN (14,15,16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader NOT IN (15,16,17)$old$, $new$p_reader NOT IN (15,16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader NOT IN (16,17)$old$, $new$p_reader NOT IN (16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1),
        ('internal.require_observation_action_reader(uuid,integer,uuid)', $old$    IF p_reader<>17 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$old$, $new$    IF p_reader<>18 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='9'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (17,18) AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$new$, 1),
        ('internal.resolve_initial_history_media(uuid,uuid,uuid,uuid)', $old$saved.evidence_manifest->'schema_version'='8'::JSONB$old$, $new$saved.evidence_manifest->'schema_version' IN ('8'::JSONB,'9'::JSONB)$new$, 2),
        ('public.enroll_owned_observation_history(uuid,integer)', $old$p_reader IN (16,17)$old$, $new$p_reader IN (16,17,18)$new$, 1),
        ('public.enroll_owned_observation_history(uuid,integer)', $old$IF p_reader=16 AND EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_observation AND owner_id=caller AND evidence_manifest->'schema_version'='8'::JSONB) THEN$old$, $new$IF p_reader=17 AND EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_observation AND owner_id=caller AND evidence_manifest->'schema_version'='9'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader=16 AND EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_observation AND owner_id=caller AND evidence_manifest->'schema_version' IN ('8'::JSONB,'9'::JSONB)) THEN$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader IN (11,13,14,15,16,17)$old$, $new$p_reader IN (11,13,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader IN (14,15,16,17)$old$, $new$p_reader IN (14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader IN (15,16,17)$old$, $new$p_reader IN (15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader IN (16,17)$old$, $new$p_reader IN (16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader NOT IN (13,14,15,16,17)$old$, $new$p_reader NOT IN (13,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader NOT IN (14,15,16,17)$old$, $new$p_reader NOT IN (14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader NOT IN (15,16,17)$old$, $new$p_reader NOT IN (15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader NOT IN (16,17)$old$, $new$p_reader NOT IN (16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$p_reader NOT IN (7,8,9,10,11,13,14,15,16,17)$old$, $new$p_reader NOT IN (7,8,9,10,11,13,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$    IF p_reader<>17 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$old$, $new$    IF p_reader<>18 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='9'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (17,18) AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$new$, 1),
        ('public.get_owned_observation_analysis_page(jsonb,integer)', $old$(p_reader=17 AND result_row.evidence_manifest->'schema_version'='8'::JSONB)$old$, $new$(p_reader IN (17,18) AND result_row.evidence_manifest->'schema_version'='8'::JSONB) OR (p_reader=18 AND result_row.evidence_manifest->'schema_version'='9'::JSONB)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$p_reader NOT IN (13,14,15,16,17)$old$, $new$p_reader NOT IN (13,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$p_reader NOT IN (14,15,16,17)$old$, $new$p_reader NOT IN (14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$p_reader NOT IN (15,16,17)$old$, $new$p_reader NOT IN (15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$p_reader NOT IN (16,17)$old$, $new$p_reader NOT IN (16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$p_reader NOT IN (9,10,11,13,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,13,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_analysis_state(jsonb,integer)', $old$    IF p_reader<>17 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$old$, $new$    IF p_reader<>18 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='9'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (17,18) AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='8'::JSONB) THEN$new$, 1),
        ('public.get_owned_observation_confirmation_undo(jsonb,integer)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_enrollment_baseline(jsonb,integer)', $old$p_reader IN (16,17)$old$, $new$p_reader IN (16,17,18)$new$, 2),
        ('public.get_owned_observation_enrollment_baseline(jsonb,integer)', $old$p_reader NOT IN (9,16,17)$old$, $new$p_reader NOT IN (9,16,17,18)$new$, 1),
        ('public.get_owned_observation_enrollment_baseline(jsonb,integer)', $old$(p_reader=17 AND evidence_manifest->'schema_version'='8'::JSONB)$old$, $new$(p_reader IN (17,18) AND evidence_manifest->'schema_version'='8'::JSONB) OR (p_reader=18 AND evidence_manifest->'schema_version'='9'::JSONB)$new$, 1),
        ('public.get_owned_observation_enrollment_selection(jsonb,integer)', $old$p_reader IN (16,17)$old$, $new$p_reader IN (16,17,18)$new$, 1),
        ('public.get_owned_observation_enrollment_selection(jsonb,integer)', $old$p_reader NOT IN (11,14,15,16,17)$old$, $new$p_reader NOT IN (11,14,15,16,17,18)$new$, 1),
        ('public.get_owned_observation_rejection_undo(jsonb,integer)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1),
        ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)', $old$'5'::JSONB,'6'::JSONB,'7'::JSONB,'8'::JSONB)$old$, $new$'5'::JSONB,'6'::JSONB,'7'::JSONB,'8'::JSONB,'9'::JSONB)$new$, 2),
        ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)', $old$manifest->'schema_version'='8'::JSONB$old$, $new$manifest->'schema_version' IN ('8'::JSONB,'9'::JSONB)$new$, 1),
        ('public.review_owned_observation_analysis(jsonb,integer)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1),
        ('public.select_owned_observation_analysis(jsonb,integer)', $old$p_reader NOT IN (9,10,11,14,15,16,17)$old$, $new$p_reader NOT IN (9,10,11,14,15,16,17,18)$new$, 1)
    ) AS changes(signature,anchor,replacement,expected) LOOP
        definition:=pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(change.signature));
        IF definition IS NULL OR (length(definition)-length(replace(definition,change.anchor,'')))/length(change.anchor)<>change.expected THEN
            RAISE EXCEPTION 'ordinary_geometry_v9_source_drift: %',change.signature; END IF;
        EXECUTE replace(definition,change.anchor,change.replacement);
    END LOOP;
END;
$patch$;

DO $constraints$
DECLARE name TEXT; definition TEXT; anchor TEXT:=$old$ARRAY['7'::jsonb, '8'::jsonb]$old$;
BEGIN
    FOREACH name IN ARRAY ARRAY['observation_analysis_origin','observation_initial_proof'] LOOP
        SELECT pg_catalog.pg_get_constraintdef(oid) INTO definition FROM pg_catalog.pg_constraint
            WHERE conrelid='internal.observation_analysis_results'::regclass AND conname=name;
        IF definition IS NULL OR (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
            RAISE EXCEPTION 'ordinary_geometry_v9_constraint_drift: %',name; END IF;
        EXECUTE pg_catalog.format('ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT %I',name);
        EXECUTE pg_catalog.format('ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT %I %s',name,
            replace(definition,anchor,$new$ARRAY['7'::jsonb, '8'::jsonb, '9'::jsonb]$new$));
    END LOOP;
END;
$constraints$;
RESET lock_timeout;
RESET statement_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- Selection-only V9 photos retain full aspect with identity geometry.
-- Existing fields, fingerprint framing, privileges and rollout gates are unchanged.
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
        OR (p_value->>'format'='nativeSelectedStillImageV2' AND (p_value->'camera_vertical_center'<>'null'::JSONB OR selection IS NULL)) THEN
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

RESET statement_timeout;
RESET lock_timeout;

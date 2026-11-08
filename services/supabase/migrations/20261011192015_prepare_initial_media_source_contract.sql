-- Source declarations only; no registry, intent, grant or public RPC is added.
SET lock_timeout='5s';
SET statement_timeout='2min';

CREATE FUNCTION internal.initial_media_source_candidate_schema_v2() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$
 SELECT '{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"variant":{"type":"string","enum":["media_sources"],"max_bytes":128},"source_plan":{"type":"object","properties":{"schema_version":{"type":"integer","minimum":1,"maximum":1},"route":{"type":"string","enum":["identify","identify-multimodal"],"max_bytes":128},"ordered_descriptions":{"type":"array","items":{"type":"string","max_bytes":65530},"max_items":64},"owner_timeline":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["description","media"],"max_bytes":128},"index":{"type":"integer","minimum":0,"maximum":63}}},"max_items":128},"capture":{"type":"object","properties":{"has_video":{"type":"boolean"},"video_clip_count":{"type":"integer","minimum":0,"maximum":64},"declared_video_frame_count":{"type":"integer","minimum":0,"maximum":150},"video_inference_frame_count":{"type":"integer","minimum":0,"maximum":150}}},"context":{"type":"object","properties":{"depth_scale_text":{"type":"string","max_bytes":8192,"nullable":true},"semantic_location":{"type":"string","max_bytes":8192,"nullable":true},"weather_condition":{"type":"string","max_bytes":8192,"nullable":true},"device_locale":{"type":"string","max_bytes":8192,"nullable":true},"device_time_zone":{"type":"string","max_bytes":8192,"nullable":true},"device_region":{"type":"string","max_bytes":8192,"nullable":true},"time_of_day":{"type":"string","max_bytes":8192,"nullable":true},"gps_latitude":{"type":"decimal","minimum":"-90","maximum":"90","max_bytes":326,"nullable":true},"gps_longitude":{"type":"decimal","minimum":"-180","maximum":"180","max_bytes":326,"nullable":true},"gps_elevation":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"zoom_factor":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"estimated_size_cm":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"weather_temperature_f":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"current_month":{"type":"integer","minimum":1,"maximum":12,"nullable":true}}},"options":{"type":"object","properties":{"timestamp":{"type":"string","max_bytes":128,"nullable":true},"geoprivacy":{"type":"string","enum":["open","obscured","private"],"max_bytes":128,"nullable":true},"public_location_label":{"type":"string","max_bytes":512,"nullable":true},"preferred_goal":{"type":"object","properties":{"user_field_trip_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"item_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"}},"nullable":true},"observation_context":{"type":"object","nullable":true,"properties":{"free_text":{"type":"string","max_bytes":65530}}}}},"admission":{"type":"object","properties":{"client_protocol":{"type":"integer","minimum":3,"maximum":3},"identification_protocol":{"type":"integer","minimum":6,"maximum":6},"expected_processor_permission":{"type":"string","enum":["google_gemini","openai"],"max_bytes":32}}},"experiment":{"type":"string","nullable":true,"enum":[],"max_bytes":0},"sources":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["image","audio","video"],"max_bytes":128},"source_byte_count":{"type":"integer","minimum":1,"maximum":12582912},"source_sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"input_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"source_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"clip_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"frame_index":{"type":"integer","minimum":0,"maximum":149,"nullable":true},"focus_region":{"type":"object","properties":{"x":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"y":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"width":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"height":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"source":{"type":"string","enum":["vision_objectness"],"max_bytes":128}},"nullable":true},"transform":{"type":"string","enum":["identity_v1","initial_audio_v1","video_frame_v1"],"max_bytes":128},"source_content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"transform_parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}},"prepared_output":{"type":"object","properties":{"state":{"type":"string","enum":["unresolved"],"max_bytes":128}}}}},"max_items":8}}}}}'::JSONB;
$schema$;
CREATE FUNCTION internal.initial_media_source_semantics(value JSONB) RETURNS VOID LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
DECLARE item JSONB; focus JSONB; text_value TEXT; route TEXT:=value->>'route'; descriptions JSONB:=value->'ordered_descriptions';
 media JSONB:=value->'sources'; capture JSONB:=value->'capture'; images INTEGER:=0; audios INTEGER:=0; videos INTEGER:=0;
 frames INTEGER:=0; photos INTEGER:=0; recordings INTEGER:=0; position INTEGER:=0; source_image_bytes BIGINT:=0;
 owners INTEGER[]:=ARRAY[]::INTEGER[]; seen INTEGER[]:=ARRAY[]::INTEGER[]; frame_indexes INTEGER[]:=ARRAY[]::INTEGER[]; video_audio INTEGER[]:=ARRAY[]::INTEGER[]; description_index INTEGER:=0;
 clip INTEGER; source_index INTEGER; frame INTEGER; index_value INTEGER;
 whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
 IF jsonb_array_length(media)=0 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT * FROM jsonb_array_elements(descriptions) LOOP
  text_value:=item#>>'{}';
  IF btrim(text_value,whitespace)='' OR octet_length(item::TEXT)>65536 OR text_value<>btrim(text_value,whitespace) THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOR item IN SELECT * FROM jsonb_array_elements(media) LOOP
  clip:=(item->>'clip_index')::INTEGER; source_index:=(item->>'source_index')::INTEGER; frame:=(item->>'frame_index')::INTEGER;
  IF item->>'kind'='video' OR clip IS NULL THEN owners:=array_append(owners,position); END IF;
  IF item->>'kind'<>'image' AND item->'focus_region'<>'null'::JSONB THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  focus:=item->'focus_region';
  IF focus<>'null'::JSONB AND ((focus->>'width')::NUMERIC<=0 OR (focus->>'height')::NUMERIC<=0
   OR (focus->>'x')::NUMERIC+(focus->>'width')::NUMERIC>1 OR (focus->>'y')::NUMERIC+(focus->>'height')::NUMERIC>1) THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  CASE item->>'kind'
  WHEN 'image' THEN
   IF item->>'source_content_type' NOT IN ('image/jpeg','image/png','image/webp','image/heic','image/heif')
    OR (item->>'input_index')::INTEGER IS DISTINCT FROM images THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   images:=images+1; source_image_bytes:=source_image_bytes+(item->>'source_byte_count')::BIGINT;
   IF clip IS NOT NULL THEN
    IF clip<>0 OR source_index IS NOT NULL OR frame IS NULL OR frame=ANY(frame_indexes) OR item->>'transform'<>'video_frame_v1' THEN
     RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    frame_indexes:=array_append(frame_indexes,frame); frames:=frames+1;
   ELSE
    IF frame IS NOT NULL OR source_index IS DISTINCT FROM photos OR item->>'transform'<>'identity_v1' THEN
     RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    photos:=photos+1;
   END IF;
   IF item->'transform_parameters'<>'null'::JSONB THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  WHEN 'audio' THEN
   IF item->>'source_content_type'<>'audio/wav' OR (item->>'input_index')::INTEGER IS DISTINCT FROM audios
    OR frame IS NOT NULL OR item->>'transform'<>'initial_audio_v1' OR (item->>'source_byte_count')::BIGINT>2700000
    OR item->'transform_parameters'='null'::JSONB OR (item#>>'{transform_parameters,preserve_short_video_context}')::BOOLEAN IS DISTINCT FROM (clip IS NOT NULL) THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   audios:=audios+1;
   IF clip IS NOT NULL THEN
    IF clip<>0 OR source_index IS NOT NULL OR clip=ANY(video_audio) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    video_audio:=array_append(video_audio,clip);
   ELSE
    IF source_index IS DISTINCT FROM recordings THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    recordings:=recordings+1;
   END IF;
  WHEN 'video' THEN
   IF item->>'source_content_type'<>'video/mp4' OR clip IS DISTINCT FROM videos
    OR item->'input_index'<>'null'::JSONB OR source_index IS NOT NULL OR frame IS NOT NULL OR item->>'transform'<>'identity_v1'
    OR item->'transform_parameters'<>'null'::JSONB THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   videos:=videos+1;
  END CASE;
  position:=position+1;
 END LOOP;
 IF images>5 OR audios>2 OR videos>1 OR source_image_bytes>5242880 OR ((frames>0 OR cardinality(video_audio)>0) AND videos<>1)
  OR (capture->>'has_video')::BOOLEAN IS DISTINCT FROM (videos>0) OR (capture->>'video_clip_count')::INTEGER<>videos
  OR (capture->>'video_inference_frame_count')::INTEGER<>frames OR (capture->>'declared_video_frame_count')::INTEGER<frames
  OR (videos=0 AND (capture->>'declared_video_frame_count')::INTEGER<>0) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF (route='identify' AND (images=0 OR photos<>images OR audios<>0 OR videos<>0 OR jsonb_array_length(descriptions)>1))
  OR (route='identify-multimodal' AND images=0 AND audios=0 AND jsonb_array_length(descriptions)=0) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(value->'owner_timeline')<>cardinality(owners)+jsonb_array_length(descriptions) OR jsonb_array_length(value->'owner_timeline')>64 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT * FROM jsonb_array_elements(value->'owner_timeline') LOOP
  index_value:=(item->>'index')::INTEGER;
  IF item->>'kind'='description' THEN
   IF index_value<>description_index THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   description_index:=description_index+1;
  ELSE
   IF NOT index_value=ANY(owners) OR index_value=ANY(seen) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   seen:=array_append(seen,index_value);
  END IF;
 END LOOP;
 IF description_index<>jsonb_array_length(descriptions) OR cardinality(seen)<>cardinality(owners) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_media_source_semantics(JSONB) FROM PUBLIC,anon,authenticated,service_role;


CREATE FUNCTION internal.parse_initial_media_source_candidate(p_text TEXT) RETURNS JSONB
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text
  OR NOT internal.initial_schema_matches(value,internal.initial_media_source_candidate_schema_v2()) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.initial_media_source_semantics(value->'source_plan');
 RETURN value;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_media_source_candidate_schema_v2(),internal.parse_initial_media_source_candidate(TEXT)
 FROM PUBLIC,anon,authenticated,service_role;
RESET statement_timeout;
RESET lock_timeout;

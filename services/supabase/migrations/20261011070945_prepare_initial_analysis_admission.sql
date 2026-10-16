SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private IC-1 codec. JSON is accepted only in one exact UTF-8 spelling.
CREATE FUNCTION internal.initial_canonical_parts(value JSONB, depth INTEGER)
RETURNS TABLE(encoded TEXT,nodes INTEGER) LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE kind TEXT:=jsonb_typeof(value); item RECORD; child RECORD; parts TEXT[]:=ARRAY[]::TEXT[]; n NUMERIC;
BEGIN
 IF depth>12 OR value IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 nodes:=1;
 CASE kind
 WHEN 'null','boolean','string' THEN encoded:=value::TEXT;
 WHEN 'number' THEN
  n:=(value::TEXT)::NUMERIC;
  IF n<>trunc(n) OR abs(n)>9007199254740991 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  encoded:=n::BIGINT::TEXT;
 WHEN 'array' THEN
  IF jsonb_array_length(value)>512 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT v FROM jsonb_array_elements(value) AS x(v) LOOP
   SELECT * INTO child FROM internal.initial_canonical_parts(item.v,depth+1);
   nodes:=nodes+child.nodes; parts:=array_append(parts,child.encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='['||array_to_string(parts,',')||']';
 WHEN 'object' THEN
  IF (SELECT count(*) FROM jsonb_object_keys(value))>128 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOR item IN SELECT key,v FROM jsonb_each(value) AS x(key,v) ORDER BY key COLLATE "C" LOOP
   IF item.key !~ '^[a-z][a-z0-9_]*$' OR length(item.key)>64 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   SELECT * INTO child FROM internal.initial_canonical_parts(item.v,depth+1);
   nodes:=nodes+child.nodes; parts:=array_append(parts,to_jsonb(item.key)::TEXT||':'||child.encoded);
   IF nodes>4096 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  encoded:='{'||array_to_string(parts,',')||'}';
 ELSE RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END CASE;
 IF octet_length(encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN NEXT;
END;
$$;
CREATE FUNCTION internal.initial_canonical(value JSONB) RETURNS TEXT LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT encoded FROM internal.initial_canonical_parts(value,0);
$$;
CREATE FUNCTION internal.initial_digest(domain TEXT,encoded TEXT) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF domain IS NULL OR domain NOT IN ('input','configuration','funding','descriptions','assets') OR encoded IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.'||domain||E'.v1\n'||encoded,'UTF8'),'sha256'),'hex');
END;
$$;
CREATE FUNCTION internal.initial_schema_matches(value JSONB, rule JSONB, depth INTEGER DEFAULT 0)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE field RECORD; item JSONB; scalar TEXT; number_value NUMERIC;
BEGIN
 IF depth>12 OR value IS NULL THEN RETURN FALSE; END IF;
 IF value='null'::JSONB THEN RETURN COALESCE((rule->>'nullable')::BOOLEAN,FALSE); END IF;
 CASE rule->>'type'
 WHEN 'object' THEN
  IF jsonb_typeof(value)<>'object' THEN RETURN FALSE; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(value))<>(SELECT count(*) FROM jsonb_object_keys(rule->'properties')) THEN RETURN FALSE; END IF;
  FOR field IN SELECT * FROM jsonb_each(rule->'properties') LOOP
   IF NOT internal.initial_schema_matches(value->field.key,field.value,depth+1) THEN RETURN FALSE; END IF;
  END LOOP; RETURN TRUE;
 WHEN 'array' THEN
  IF jsonb_typeof(value)<>'array' OR jsonb_array_length(value)>(rule->>'max_items')::INTEGER THEN RETURN FALSE; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(value) LOOP
   IF NOT internal.initial_schema_matches(item,rule->'items',depth+1) THEN RETURN FALSE; END IF;
  END LOOP; RETURN TRUE;
 WHEN 'boolean' THEN RETURN jsonb_typeof(value)='boolean';
 WHEN 'integer' THEN
  IF jsonb_typeof(value)<>'number' THEN RETURN FALSE; END IF;
  number_value:=(value::TEXT)::NUMERIC;
  RETURN number_value=trunc(number_value) AND number_value BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
 WHEN 'string','decimal' THEN
  IF jsonb_typeof(value)<>'string' THEN RETURN FALSE; END IF;
  scalar:=value#>>'{}';
  IF octet_length(scalar)>(rule->>'max_bytes')::INTEGER THEN RETURN FALSE; END IF;
  IF rule->>'type'='decimal' THEN
   IF scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$' OR scalar='-0' THEN RETURN FALSE; END IF;
   RETURN scalar::NUMERIC BETWEEN (rule->>'minimum')::NUMERIC AND (rule->>'maximum')::NUMERIC;
  END IF;
  RETURN (NOT rule ? 'enum' OR rule->'enum' @> jsonb_build_array(scalar)) AND (NOT rule ? 'pattern' OR scalar ~ (rule->>'pattern'));
 ELSE RETURN FALSE;
 END CASE;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_canonical_parts(JSONB,INTEGER),internal.initial_canonical(JSONB),internal.initial_digest(TEXT,TEXT),internal.initial_schema_matches(JSONB,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;

-- This content-free namespace fence survives owner/private-record erasure and
-- quota pruning. It is not a dispatch witness and contains no text-derived hash.
CREATE TABLE internal.initial_analysis_operation_fences(scan_id UUID PRIMARY KEY);
CREATE TABLE internal.initial_analysis_configuration_assets(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 manifest JSONB NOT NULL CHECK(jsonb_typeof(manifest)='object' AND octet_length(manifest::TEXT)<=65536),
 CHECK(digest=internal.initial_digest('assets',internal.initial_canonical(manifest)))
);
ALTER TABLE internal.initial_analysis_rollout ADD COLUMN configuration_assets_digest TEXT
 REFERENCES internal.initial_analysis_configuration_assets(digest);
CREATE TABLE internal.initial_analysis_admissions(
 scan_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 canonical_input TEXT NOT NULL CHECK(octet_length(canonical_input)<=1048576),
 submission_digest TEXT NOT NULL CHECK(submission_digest ~ '^[0-9a-f]{64}$'),
 configuration_digest TEXT NOT NULL CHECK(configuration_digest ~ '^[0-9a-f]{64}$'),
 funding_digest TEXT NOT NULL CHECK(funding_digest ~ '^[0-9a-f]{64}$'),
 descriptions_digest TEXT NOT NULL CHECK(descriptions_digest ~ '^[0-9a-f]{64}$'),
 funding_binding_id UUID NOT NULL,
 assets_digest TEXT NOT NULL REFERENCES internal.initial_analysis_configuration_assets(digest),
 FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE,
 FOREIGN KEY(scan_id) REFERENCES internal.initial_analysis_operation_fences(scan_id),
 CHECK(submission_digest=internal.initial_digest('input',canonical_input))
);
CREATE INDEX initial_analysis_admissions_owner ON internal.initial_analysis_admissions(owner_id,scan_id);
ALTER TABLE internal.initial_analysis_operation_fences ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_configuration_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_operation_fences,internal.initial_analysis_configuration_assets,internal.initial_analysis_admissions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.reject_initial_permanent_mutation() RETURNS TRIGGER LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END;
$$;
REVOKE ALL ON FUNCTION internal.reject_initial_permanent_mutation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_initial_operation_fence BEFORE UPDATE OR DELETE ON internal.initial_analysis_operation_fences
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE TRIGGER immutable_initial_configuration_assets BEFORE UPDATE OR DELETE ON internal.initial_analysis_configuration_assets
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE TRIGGER guard_initial_analysis_admission BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_analysis_admissions
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_analysis_storage();

CREATE FUNCTION internal.initial_input_semantics(value JSONB) RETURNS TEXT LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
DECLARE item JSONB; focus JSONB; text_value TEXT; route TEXT:=value->>'route'; descriptions JSONB:=value->'ordered_descriptions';
 media JSONB:=value->'media'; capture JSONB:=value->'capture'; images INTEGER:=0; audios INTEGER:=0; videos INTEGER:=0;
 frames INTEGER:=0; photos INTEGER:=0; recordings INTEGER:=0; position INTEGER:=0; image_bytes BIGINT:=0; source_image_bytes BIGINT:=0;
 owners INTEGER[]:=ARRAY[]::INTEGER[]; seen INTEGER[]:=ARRAY[]::INTEGER[]; frame_indexes INTEGER[]:=ARRAY[]::INTEGER[]; video_audio INTEGER[]:=ARRAY[]::INTEGER[]; description_index INTEGER:=0;
 clip INTEGER; source_index INTEGER; frame INTEGER; index_value INTEGER;
 whitespace TEXT:=U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
 FOR item IN SELECT * FROM jsonb_array_elements(descriptions) LOOP
  text_value:=item#>>'{}';
  IF btrim(text_value,whitespace)='' OR octet_length(item::TEXT)>65536 OR (route<>'identify-describe' AND text_value<>btrim(text_value,whitespace)) THEN
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
   IF item->>'content_type' NOT IN ('image/jpeg','image/png','image/webp','image/heic','image/heif')
    OR item->>'source_content_type' IS DISTINCT FROM item->>'content_type' OR (item->>'input_index')::INTEGER IS DISTINCT FROM images THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   images:=images+1; image_bytes:=image_bytes+(item->>'byte_count')::BIGINT; source_image_bytes:=source_image_bytes+(item->>'source_byte_count')::BIGINT;
   IF clip IS NOT NULL THEN
    IF clip<>0 OR source_index IS NOT NULL OR frame IS NULL OR frame=ANY(frame_indexes) OR item->>'transform'<>'video_frame_v1' THEN
     RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    frame_indexes:=array_append(frame_indexes,frame); frames:=frames+1;
   ELSE
    IF frame IS NOT NULL OR source_index IS DISTINCT FROM photos OR item->>'transform'<>'identity_v1' THEN
     RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
    photos:=photos+1;
   END IF;
   IF item->'byte_count'<>item->'source_byte_count' OR item->'sha256'<>item->'source_sha256' OR item->'transform_parameters'<>'null'::JSONB THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  WHEN 'audio' THEN
   IF item->>'content_type'<>'audio/wav' OR item->>'source_content_type'<>'audio/wav' OR (item->>'input_index')::INTEGER IS DISTINCT FROM audios
    OR frame IS NOT NULL OR item->>'transform'<>'initial_audio_v1' OR (item->>'byte_count')::BIGINT>2700000 OR (item->>'source_byte_count')::BIGINT>2700000
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
   IF item->>'content_type'<>'video/mp4' OR item->>'source_content_type'<>'video/mp4' OR clip IS DISTINCT FROM videos
    OR item->'input_index'<>'null'::JSONB OR source_index IS NOT NULL OR frame IS NOT NULL OR item->>'transform'<>'identity_v1'
    OR item->'transform_parameters'<>'null'::JSONB OR item->'byte_count'<>item->'source_byte_count' OR item->'sha256'<>item->'source_sha256' THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   videos:=videos+1;
  END CASE;
  position:=position+1;
 END LOOP;
 IF images>5 OR audios>2 OR videos>1 OR image_bytes>5242880 OR source_image_bytes>5242880 OR ((frames>0 OR cardinality(video_audio)>0) AND videos<>1)
  OR (capture->>'has_video')::BOOLEAN IS DISTINCT FROM (videos>0) OR (capture->>'video_clip_count')::INTEGER<>videos
  OR (capture->>'video_inference_frame_count')::INTEGER<>frames OR (capture->>'declared_video_frame_count')::INTEGER<frames
  OR (videos=0 AND (capture->>'declared_video_frame_count')::INTEGER<>0) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF (route='identify-describe' AND (jsonb_array_length(media)<>0 OR jsonb_array_length(descriptions)<>1))
  OR (route='identify' AND (images=0 OR photos<>images OR audios<>0 OR videos<>0 OR jsonb_array_length(descriptions)>1))
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
 RETURN CASE WHEN route='identify' THEN 'vision_compat_v1' WHEN route='identify-describe' THEN 'description_compat_v1'
 WHEN videos>0 THEN CASE WHEN audios>0 THEN 'multimodal_video_audio_v1' ELSE 'multimodal_video_frames_v1' END
 WHEN images>0 THEN CASE WHEN audios>0 THEN 'multimodal_photo_audio_v1' ELSE 'multimodal_photo_v1' END
 WHEN audios>0 THEN 'multimodal_audio_v1' ELSE 'multimodal_text_v1' END;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_input_semantics(JSONB) FROM PUBLIC,anon,authenticated,service_role;

-- Generated literals from the adjacent private codec schema and immutable asset catalog.
CREATE FUNCTION internal.initial_input_schema() RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$
 SELECT '{"type":"object","properties":{"schema_version":{"type":"integer","minimum":1,"maximum":1},"route":{"type":"string","enum":["identify","identify-describe","identify-multimodal"],"max_bytes":128},"ordered_descriptions":{"type":"array","items":{"type":"string","max_bytes":65530},"max_items":64},"media":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["image","audio","video"],"max_bytes":128},"content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"source_byte_count":{"type":"integer","minimum":1,"maximum":12582912},"source_sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"input_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"source_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"clip_index":{"type":"integer","minimum":0,"maximum":63,"nullable":true},"frame_index":{"type":"integer","minimum":0,"maximum":149,"nullable":true},"focus_region":{"type":"object","properties":{"x":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"y":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"width":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"height":{"type":"decimal","minimum":"0","maximum":"1","max_bytes":326},"source":{"type":"string","enum":["vision_objectness"],"max_bytes":128}},"nullable":true},"transform":{"type":"string","enum":["identity_v1","initial_audio_v1","video_frame_v1"],"max_bytes":128},"source_content_type":{"type":"string","enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"],"max_bytes":128},"transform_parameters":{"type":"object","nullable":true,"properties":{"target_sample_rate":{"type":"integer","minimum":16000,"maximum":16000},"preserve_short_video_context":{"type":"boolean"}}}}},"max_items":8},"owner_timeline":{"type":"array","items":{"type":"object","properties":{"kind":{"type":"string","enum":["description","media"],"max_bytes":128},"index":{"type":"integer","minimum":0,"maximum":63}}},"max_items":128},"capture":{"type":"object","properties":{"has_video":{"type":"boolean"},"video_clip_count":{"type":"integer","minimum":0,"maximum":64},"declared_video_frame_count":{"type":"integer","minimum":0,"maximum":150},"video_inference_frame_count":{"type":"integer","minimum":0,"maximum":150}}},"context":{"type":"object","properties":{"depth_scale_text":{"type":"string","max_bytes":8192,"nullable":true},"semantic_location":{"type":"string","max_bytes":8192,"nullable":true},"weather_condition":{"type":"string","max_bytes":8192,"nullable":true},"device_locale":{"type":"string","max_bytes":8192,"nullable":true},"device_time_zone":{"type":"string","max_bytes":8192,"nullable":true},"device_region":{"type":"string","max_bytes":8192,"nullable":true},"time_of_day":{"type":"string","max_bytes":8192,"nullable":true},"gps_latitude":{"type":"decimal","minimum":"-90","maximum":"90","max_bytes":326,"nullable":true},"gps_longitude":{"type":"decimal","minimum":"-180","maximum":"180","max_bytes":326,"nullable":true},"gps_elevation":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"zoom_factor":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"estimated_size_cm":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"weather_temperature_f":{"type":"decimal","minimum":"-1.7976931348623157e308","maximum":"1.7976931348623157e308","max_bytes":326,"nullable":true},"current_month":{"type":"integer","minimum":1,"maximum":12,"nullable":true}}},"options":{"type":"object","properties":{"timestamp":{"type":"string","max_bytes":128,"nullable":true},"geoprivacy":{"type":"string","enum":["open","obscured","private"],"max_bytes":128,"nullable":true},"public_location_label":{"type":"string","max_bytes":512,"nullable":true},"preferred_goal":{"type":"object","properties":{"user_field_trip_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"item_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"}},"nullable":true},"observation_context":{"type":"object","nullable":true,"properties":{"free_text":{"type":"string","max_bytes":65530}}}}},"admission":{"type":"object","properties":{"client_protocol":{"type":"integer","minimum":3,"maximum":3},"identification_protocol":{"type":"integer","minimum":6,"maximum":6},"expected_processor_permission":{"type":"string","enum":["google_gemini","openai"],"max_bytes":32}}},"experiment":{"type":"object","nullable":true,"properties":{"kind":{"type":"string","enum":["audio_comparison","audio_prompt_comparison"],"max_bytes":64},"plan_sha256":{"type":"string","pattern":"^[0-9a-f]{64}$","max_bytes":64},"slot":{"type":"integer","minimum":0,"maximum":1000000}}}}}'::JSONB;
$schema$;
REVOKE ALL ON FUNCTION internal.initial_input_schema() FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO internal.initial_analysis_configuration_assets(digest,manifest) VALUES('a2e87aae39606224487f74c7f9e286d0653ade4cbee87ab3d158d0973ad0f6c0','{"schema_version":1,"roots":["_shared/ai/production.ts","_shared/identify/media.ts","identify-describe/provider.ts","identify-multimodal/audio.ts","identify-multimodal/provider.ts","identify/provider.ts"],"files":[{"path":"services/supabase/functions/_shared/ai/admission.ts","sha256":"518db95eee5d7db36551900782a92e342d7b6fa3da67abef79f578bab1b176eb"},{"path":"services/supabase/functions/_shared/ai/contentRegistry.ts","sha256":"d120f445ba0f0035ccc477ab0c6ebedb60fd3ad6f032de577d716125e686bd60"},{"path":"services/supabase/functions/_shared/ai/execution.ts","sha256":"e53c7f34db6b9afa9340948f4f05bbfa280ceb7812cc5a06db077e6129f491d5"},{"path":"services/supabase/functions/_shared/ai/gemini.ts","sha256":"6bc849a1add789d4e10e6df6422649d23da2aeaeff12559547f6e513c023424f"},{"path":"services/supabase/functions/_shared/ai/geminiContent.ts","sha256":"2a0aeda771e36631618281091f5e5015307117bebd4021807475db0d4fd93246"},{"path":"services/supabase/functions/_shared/ai/geminiRequest.ts","sha256":"57d2475cc1844885161e9e9311a38ad302407a8ee2801d4b59b76fc137da4d0e"},{"path":"services/supabase/functions/_shared/ai/identificationInput.ts","sha256":"3cc1aaeecd17d1da1a913244bae9e8008f17bfcce7b7b9c155632d1338319c97"},{"path":"services/supabase/functions/_shared/ai/openai.ts","sha256":"b12b1e4000ee440f2ecc4a25e5983cc26283dcb69d0b9759a1af479f7565bd8e"},{"path":"services/supabase/functions/_shared/ai/openaiConfidenceRules.ts","sha256":"99967c62c406fd9abf6d7a838655fa51695166dfe1b0e5f8ed8fca2b16bb8749"},{"path":"services/supabase/functions/_shared/ai/openaiLunaEvidenceLimits.ts","sha256":"0034c16dca03915cb066d4ef7ccbd7ac1b1933717d33c1d26250f49681a7eba9"},{"path":"services/supabase/functions/_shared/ai/openaiNullFields.ts","sha256":"62e31d330cee7231feca7288cd82966556d646d4d5787dd5f2f51f90edbc7018"},{"path":"services/supabase/functions/_shared/ai/openaiPhoto.ts","sha256":"50b932bcb7602dbe96ec259aafb731e9f2b16c718aa4fc71116a7c7e762bf12a"},{"path":"services/supabase/functions/_shared/ai/openaiPhotoConfidence.ts","sha256":"23a85c54fdd8685cff739ff14eb2fa4fbc5d546cc4dc8e564bc88471ea1f5590"},{"path":"services/supabase/functions/_shared/ai/openaiPhotoEvidence.ts","sha256":"fcc5a14bf7003269c7b71fcf5e05dcc00d30d44cf9f4937e50dd066680d7bfa4"},{"path":"services/supabase/functions/_shared/ai/openaiPhotoModels.ts","sha256":"1b2361664050e025c5f443e7c64761356b7d0cb2ccf26905a32dbedacbfaa7d5"},{"path":"services/supabase/functions/_shared/ai/openaiPhotoPrimary.ts","sha256":"c5867e3bcd1f14b94849abe58fb070e16e24c9f9d07c445b0a6a4d1df4f8df3f"},{"path":"services/supabase/functions/_shared/ai/openaiPhotoReasoning.ts","sha256":"3924c3f5e74b700323b6a91ef8f9bde62ec37f7527b3f78cc77746f794a01a36"},{"path":"services/supabase/functions/_shared/ai/openaiRequest.ts","sha256":"890ef2d4a382959a991977d6ce7e8953db3853bcf74a8600e29508f930dfa8e8"},{"path":"services/supabase/functions/_shared/ai/openaiSolPrimary.ts","sha256":"656c270707b76ae4fb848ee2cf70a877f20c8ca7ffa477573f70f99d2e7b2764"},{"path":"services/supabase/functions/_shared/ai/openaiSolPrimaryContract.ts","sha256":"8b2113595eff5f86f400d32c2abf1eaa234b04e98b0771fe5c021d6a66f74792"},{"path":"services/supabase/functions/_shared/ai/openaiSolPrimaryInstructions.ts","sha256":"7f36739402fc5d44af0d9f0163b2ffb490c4f68713204e01a636518528b1c9d2"},{"path":"services/supabase/functions/_shared/ai/openaiSolRank.ts","sha256":"fa679c3fb2a4ae9bd9db1200567b3999706b6ef176f23cde72d00cd9dbeb2e0a"},{"path":"services/supabase/functions/_shared/ai/production.ts","sha256":"d22e59d929736bd75cbec218809618ce3f912ee6e65ace439523e69fb4489cda"},{"path":"services/supabase/functions/_shared/ai/registry.ts","sha256":"2739b45335c491d88b8fd5d08ba16c81eb16511b49a220e8e4db58d8c451456e"},{"path":"services/supabase/functions/_shared/aiUsage.ts","sha256":"f76d2ee7b79277102d1d9e6730826bd6b8a7f00368f478508990c70eb3767d4d"},{"path":"services/supabase/functions/_shared/audioProcessing.ts","sha256":"69601412422152a62095358838a1b7be4a6ab4cca2a27bb601f0287266b6d5b6"},{"path":"services/supabase/functions/_shared/auth.ts","sha256":"3ca912abd3a5b1a152e0e0fb1fae0553815cfb38faea948075638b25ebf56524"},{"path":"services/supabase/functions/_shared/aws.ts","sha256":"8cc0c72a593afc15bcd29873a909ed38cc4ed412bb8e95800858b95062098c63"},{"path":"services/supabase/functions/_shared/capturedMediaContract.ts","sha256":"e6167ca10093479a39cd80c9c7096e4ebb2dbc9019b72078c6672a1c910cb712"},{"path":"services/supabase/functions/_shared/concurrency.ts","sha256":"e65371063f2efa150032db1b9afc3ce21a9d2ead0e1da82d6283fde659384493"},{"path":"services/supabase/functions/_shared/edgeHandler.ts","sha256":"6d3bb449a2d0f7aa77734488b9c71fc35379f721130412cde076906570105a39"},{"path":"services/supabase/functions/_shared/encoding.ts","sha256":"8921b3b7bf3466426524fbc6e135b5789d950e6d491305bf7123875924f1827e"},{"path":"services/supabase/functions/_shared/gemini.ts","sha256":"3ad152eac0ee77758555fbead6b18cc97ac895ae00cfd0a8e3025d26bdc65dbd"},{"path":"services/supabase/functions/_shared/http.ts","sha256":"539a9ff6906d1b0322ca203d681b891b4f480c33e1095d10b36c2670f6788596"},{"path":"services/supabase/functions/_shared/identify/audioSubjectPolicy.ts","sha256":"5ce04dde2e970f266894cbb35e18441793b7787d0d93a28b93b2391226b6c601"},{"path":"services/supabase/functions/_shared/identify/context.ts","sha256":"eba9982710d145cf0ae97bfd8bc17e76db874a43b6241a513ead3a98a21112c3"},{"path":"services/supabase/functions/_shared/identify/contract.ts","sha256":"6a765e0286101721d9b0f995cf471320a299ac91342af68e1d2d7261a938a4c2"},{"path":"services/supabase/functions/_shared/identify/googleSchema.ts","sha256":"0c3ccb02172cd8a224387fc1eaa1e8386019cb9fdea950a122bf887b4928450b"},{"path":"services/supabase/functions/_shared/identify/media.ts","sha256":"e845f3e5132e7c5422ba42b2724bfce43f9d6bbe4202f64c8a09ed760763136b"},{"path":"services/supabase/functions/_shared/identify/schema.ts","sha256":"9a0f05df0590fa29b78eb099644b732ac8f5bb06863016b2c628d0509d7c237d"},{"path":"services/supabase/functions/_shared/identify/thresholds.ts","sha256":"658cb9b056e3ad3f3cf618ac18ee6e792d8a2267d35bea7f59167bcc87ad443b"},{"path":"services/supabase/functions/_shared/mediaBudgets.ts","sha256":"88f7fded8dcc01ea0cefd95840ccbc5cb725e4a2297831dbdaee9f2b3be06f81"},{"path":"services/supabase/functions/_shared/outbound.ts","sha256":"1b42cd13285279e09f0e982253a78c730c14325df6b1cb5f0cf811a7f7b6d587"},{"path":"services/supabase/functions/_shared/publishableKey.ts","sha256":"0bb662ee653aa246dd673a688417668fb2d58009383ee6130e29a2bf7db8bcc4"},{"path":"services/supabase/functions/_shared/serviceRoleAuth.ts","sha256":"18d3443ec5e09470be7a16c9dd0f761c894be3c548f116acda44cb930eda3dcb"},{"path":"services/supabase/functions/_shared/serviceRoleClient.ts","sha256":"7c902ab75359ddd04e634c23f88ea8817678a65b4e8417062d5182e636deb5b0"},{"path":"services/supabase/functions/_shared/taxonomy.ts","sha256":"7306f67cee982fb007a417ddc2c6ef38c30f9d2d3fd288d3ff39ada9423b59f6"},{"path":"services/supabase/functions/audio-spec/instructions.ts","sha256":"ac7de56e2a08f6b9f126c42a03764af609162fdf2c86c05650b69b55408d8c17"},{"path":"services/supabase/functions/audio-spec/resample.ts","sha256":"697a29cd6e937d08d7bbf6a5d9df7d32589227a21034db119feb43a723d45de1"},{"path":"services/supabase/functions/audio-spec/wav.ts","sha256":"b8f3fbf2aed80b4873a82f32d1271476426f2411d4ab17138a810b2041a5dfdc"},{"path":"services/supabase/functions/deno.json","sha256":"5f9b19300d164f5c406e5aca9a7f6965fa630da7bfabe01d0b01afb52a8c5b6b"},{"path":"services/supabase/functions/dependencies.lock","sha256":"c1cd6d302423798701d58af8b4ccbd7fed45aed9ad23082e431ed72bc9454d72"},{"path":"services/supabase/functions/identify-describe/provider.ts","sha256":"7c514fd897e4442f52705249ce4056a41fab3984535cbc5a1a0497341543fb36"},{"path":"services/supabase/functions/identify-describe/schema.ts","sha256":"5bcc551eda43586a49654d03fd210a0aeba4ccd6afcc4d452f06054f543017bb"},{"path":"services/supabase/functions/identify-multimodal/audio.ts","sha256":"ff70036c97f6110b20824d7cfbc4f38b5cc92367d9d8acec95f9f5ce3f852706"},{"path":"services/supabase/functions/identify-multimodal/capturedMedia.ts","sha256":"3a28246917f962b251144ddd43ed3d97d105113c39dcc0711a9eb157e341a253"},{"path":"services/supabase/functions/identify-multimodal/comparison/promptInstruction.ts","sha256":"39824ffe181bd457508e622d6fe4d0c233e55314144fbe8ea9e46a9754318ef7"},{"path":"services/supabase/functions/identify-multimodal/instructions.ts","sha256":"da038dc3292068b3da132dbbce3908a14926798ded597a3cb6de13078b35e783"},{"path":"services/supabase/functions/identify-multimodal/provider.ts","sha256":"0f88e88c80aef67888d2ff5356974f6f5ccb9cabe9400e76b05bb531eedca49f"},{"path":"services/supabase/functions/identify/provider.ts","sha256":"c63b919d2fceb53a51833abbfdb7a40133038415dbf946c0bd476f4b18124f6f"}],"external_specifiers":["@google/genai","@supabase/supabase-js","aws4fetch"],"repository_revision":"86e007a5f1b2ae3064bbe21f9fd140a4b3dead4b","retention_owner":"initial_engine_release_archive","resolver_id":"git_blob_sha256_v1"}'::JSONB);
UPDATE internal.initial_analysis_rollout SET configuration_assets_digest='a2e87aae39606224487f74c7f9e286d0653ade4cbee87ab3d158d0973ad0f6c0' WHERE singleton;

CREATE FUNCTION internal.parse_initial_input(encoded TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 IF encoded IS NULL OR octet_length(encoded)>1048576 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=encoded::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM encoded OR NOT internal.initial_schema_matches(value,internal.initial_input_schema()) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.initial_input_semantics(value);
 RETURN value;
END;
$$;
REVOKE ALL ON FUNCTION internal.parse_initial_input(TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Neither this envelope nor its exact replay contains a lease or dispatch grant.
CREATE FUNCTION internal.initial_admission_response(saved internal.initial_analysis_admissions, route TEXT, outcome TEXT)
RETURNS JSONB LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT jsonb_build_object('outcome',outcome,'binding',jsonb_build_object('version',1,'owner_id',saved.owner_id,'scan_id',saved.scan_id,
 'route',route,'submission_digest',saved.submission_digest,'configuration_digest',saved.configuration_digest,'funding_digest',saved.funding_digest,
 'descriptions_digest',saved.descriptions_digest,'funding_binding_id',saved.funding_binding_id,'assets_digest',saved.assets_digest));
$$;
REVOKE ALL ON FUNCTION internal.initial_admission_response(internal.initial_analysis_admissions,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.admit_initial_analysis(p_owner UUID,p_scan UUID,p_canonical_input TEXT,p_submission_digest TEXT,p_assets_digest TEXT,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE input JSONB; profile TEXT; saved internal.initial_analysis_admissions; submission internal.initial_analysis_submissions;
 scan_owner UUID; scan_retired BOOLEAN; scan_exists BOOLEAN; enabled BOOLEAN; assets TEXT; quota RECORD; attempt internal.identification_provider_attempts;
 funding JSONB; configuration JSONB; previous_context TEXT; images INTEGER; audios INTEGER; videos INTEGER; fallback BOOLEAN;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR p_submission_digest IS NULL OR p_submission_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 input:=internal.parse_initial_input(p_canonical_input);
 IF internal.initial_digest('input',p_canonical_input)<>p_submission_digest THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id,is_tombstoned INTO scan_owner,scan_retired FROM public.scans WHERE id=p_scan FOR UPDATE;
 scan_exists:=FOUND;
 IF scan_exists AND (scan_owner IS DISTINCT FROM p_owner OR scan_retired) THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan;
 IF FOUND THEN
  IF submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
  SELECT * INTO saved FROM internal.initial_analysis_admissions WHERE scan_id=p_scan;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  IF saved.canonical_input IS DISTINCT FROM p_canonical_input OR saved.submission_digest IS DISTINCT FROM p_submission_digest THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF submission.input_snapshot IS DISTINCT FROM input OR submission.route IS DISTINCT FROM input->>'route'
   OR submission.ordered_descriptions IS DISTINCT FROM input->'ordered_descriptions'
   OR saved.configuration_digest IS DISTINCT FROM internal.initial_digest('configuration',internal.initial_canonical(submission.configuration_snapshot))
   OR saved.funding_digest IS DISTINCT FROM internal.initial_digest('funding',internal.initial_canonical(submission.funding_snapshot))
   OR saved.descriptions_digest IS DISTINCT FROM internal.initial_digest('descriptions',internal.initial_canonical(submission.ordered_descriptions))
   OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations q WHERE q.id=saved.funding_binding_id AND q.user_id=p_owner
     AND q.request_id=p_scan AND q.original_analysis_id=p_scan AND q.operation='scan_identification' AND q.attempt_count=1)
   OR (scan_exists AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan AND owner_id=p_owner)) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  -- Do not consult current defaults, consent, gates, quota expiry or caller's
  -- current asset bundle. Future dispatch resolves this saved configuration only.
  RETURN internal.initial_admission_response(saved,submission.route,'replay');
 END IF;
 IF scan_exists OR EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=p_scan::TEXT)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=p_scan::TEXT)
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_scan OR request_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT initial_analysis_lifecycle_enabled,configuration_assets_digest INTO enabled,assets FROM internal.initial_analysis_rollout WHERE singleton FOR SHARE;
 IF enabled IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 IF assets IS NULL OR p_assets_digest IS DISTINCT FROM assets THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF input->'experiment'<>'null'::JSONB OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN RAISE EXCEPTION 'initial_analysis_experiment_unavailable' USING ERRCODE='55000'; END IF;
 profile:=internal.initial_input_semantics(input);
 SELECT count(*) FILTER(WHERE v->>'kind'='image'),count(*) FILTER(WHERE v->>'kind'='audio'),count(*) FILTER(WHERE v->>'kind'='video')
 INTO images,audios,videos FROM jsonb_array_elements(input->'media') AS m(v);
 fallback:=videos=0 AND ((images+audios=1 AND jsonb_array_length(input->'ordered_descriptions')<=1)
   OR (images+audios=0 AND jsonb_array_length(input->'ordered_descriptions')=1));
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 previous_context:=current_setting('merian.initial_analysis_admission',TRUE);
 PERFORM set_config('merian.initial_analysis_admission',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 SELECT * INTO STRICT quota FROM public.reserve_identification_quota(p_owner,'scan_identification',p_scan,p_ip_hash,p_scan,fallback,
  (input#>>'{admission,client_protocol}')::INTEGER,FALSE,profile,input#>>'{admission,expected_processor_permission}',(input#>>'{admission,identification_protocol}')::INTEGER);
 PERFORM set_config('merian.initial_analysis_admission',COALESCE(previous_context,''),TRUE);
 IF quota.request_id IS DISTINCT FROM p_scan OR quota.original_analysis_id IS DISTINCT FROM p_scan OR quota.is_replay
  OR quota.attempt_count<>1 OR quota.reservation_state<>'reserved' OR quota.input_profile IS DISTINCT FROM profile THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT attempt FROM internal.identification_provider_attempts WHERE reservation_id=quota.reservation_id AND attempt_count=1;
 funding:=jsonb_build_object('version',1,'original',jsonb_build_object(
  'reservation_id',quota.reservation_id,'request_id',quota.request_id,'original_analysis_id',quota.original_analysis_id,
  'operation','scan_identification','attempt_count',quota.attempt_count,'effective_plan',quota.effective_plan,
  'effective_tier',quota.effective_tier,'entitlement_version',quota.entitlement_version,'policy_version',quota.policy_version,
  'model',quota.model,'complimentary_client_scan_id',quota.complimentary_client_scan_id,'flash_fallback_used',quota.flash_fallback_used));
 configuration:=jsonb_build_object('version',1,'asset_manifest_digest',assets,'retention_owner','initial_engine_release_archive',
  'resolver_id','git_blob_sha256_v1','assignment',jsonb_build_object('operation',attempt.operation,'effective_plan',attempt.effective_plan,
  'model',attempt.model,'policy_version',attempt.policy_version,'provider',attempt.provider,'binding',attempt.binding,
  'processor_permission',attempt.processor_permission,'input_profile',attempt.input_profile,'provider_model',attempt.provider_model,
  'minimum_client_protocol',attempt.minimum_client_protocol,'accepted_client_protocol',attempt.accepted_client_protocol,
  'minimum_identification_protocol',attempt.minimum_identification_protocol,'accepted_identification_protocol',attempt.accepted_identification_protocol),
  'model',quota.model,'effective_tier',quota.effective_tier,'experiment',NULL);
 INSERT INTO internal.initial_analysis_submissions(scan_id,owner_id,route,input_schema_version,input_snapshot,ordered_descriptions,configuration_snapshot,funding_snapshot)
 VALUES(p_scan,p_owner,input->>'route',1,input,input->'ordered_descriptions',configuration,funding);
 INSERT INTO internal.initial_analysis_admissions(scan_id,owner_id,canonical_input,submission_digest,configuration_digest,funding_digest,descriptions_digest,funding_binding_id,assets_digest)
 VALUES(p_scan,p_owner,p_canonical_input,p_submission_digest,internal.initial_digest('configuration',internal.initial_canonical(configuration)),
  internal.initial_digest('funding',internal.initial_canonical(funding)),internal.initial_digest('descriptions',internal.initial_canonical(input->'ordered_descriptions')),quota.reservation_id,assets)
 RETURNING * INTO saved;
 RETURN internal.initial_admission_response(saved,input->>'route','admitted');
 -- No catch-and-return around reservation: any later validation/storage error
 -- rolls back the quota, complimentary hold, fence, input and binding together.
END;
$$;
REVOKE ALL ON FUNCTION public.admit_initial_analysis(UUID,UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_initial_analysis(UUID,UUID,TEXT,TEXT,TEXT,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.admit_initial_analysis(uuid,uuid,text,text,text,text)','Inactive IC-1 atomic original admission and exact replay without dispatch authority');

-- Hold generic execution/settlement/cleanup for this namespace. Exact initial
-- dispatch and original-attempt settlement will receive separate proof-bearing
-- owners; neither a reservation replay nor this admission context is that proof.
DO $patch$
DECLARE definition TEXT; anchor TEXT; signature TEXT; denial TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::regprocedure) INTO STRICT definition;
 anchor:='    quota_now := pg_catalog.CLOCK_TIMESTAMP();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed reservation identity scope changed'; END IF;
 definition:=replace(definition,anchor,$body$
    -- Preserve the existing blocking original scope above. A legacy alias or
    -- omitted original also occupies the request namespace. This added secondary
    -- scope never waits: crossed aliases cannot create a new advisory wait cycle.
    IF p_request_id IS DISTINCT FROM p_original_analysis_id THEN
        IF NOT pg_try_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || p_request_id::TEXT,0::BIGINT)) THEN
            RAISE EXCEPTION 'initial_analysis_scope_busy' USING ERRCODE='55000'; END IF;
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_request_id) THEN
            RAISE EXCEPTION 'initial_analysis_admission_required' USING ERRCODE='55000'; END IF;
    END IF;
$body$||anchor);
 anchor:=$anchor$        PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || p_original_analysis_id::TEXT,0::BIGINT));$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed reservation scope changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
        IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id IN (p_original_analysis_id,p_request_id)) THEN
            IF current_setting('merian.initial_analysis_admission',TRUE) IS DISTINCT FROM p_user_id::TEXT||':'||p_original_analysis_id::TEXT
                OR p_request_id IS DISTINCT FROM p_original_analysis_id OR p_operation IS DISTINCT FROM 'scan_identification'
                OR p_client_protocol IS DISTINCT FROM 3 OR p_internal_replay IS DISTINCT FROM FALSE
                OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=p_original_analysis_id)
                OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations bound WHERE bound.original_analysis_id=p_original_analysis_id OR bound.request_id=p_original_analysis_id) THEN
                RAISE EXCEPTION 'initial_analysis_admission_required' USING ERRCODE='55000';
            END IF;
        END IF;
$body$);
 -- Old ABI cannot be an alternate entry to this lifecycle. The second check
 -- also covers a concurrent initial admission that committed during reserve.
 denial:=$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id IN (p_original_analysis_id,p_request_id)) THEN
        RAISE EXCEPTION 'initial_analysis_admission_required' USING ERRCODE='55000';
    END IF;
$body$;
 FOREACH signature IN ARRAY ARRAY[
 'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)',
 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)'] LOOP
  SELECT pg_get_functiondef(signature::regprocedure) INTO STRICT definition;
  FOREACH anchor IN ARRAY ARRAY['PERFORM internal.require_service_role();','AS quota;'] LOOP
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed legacy quota entry changed: %',signature; END IF;
   definition:=replace(definition,anchor,anchor||denial);
  END LOOP;
  EXECUTE definition;
 END LOOP;
 -- Latest ABI must also reject a bound request with a deliberately omitted
 -- original ID before its validation or core work; fresh IC-1 always has both.
 SELECT pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::regprocedure) INTO STRICT definition;
 anchor:='    PERFORM internal.require_service_role();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed current quota entry changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
    IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_request_id)
      AND p_original_analysis_id IS DISTINCT FROM p_request_id THEN RAISE EXCEPTION 'initial_analysis_admission_required' USING ERRCODE='55000'; END IF;
$body$);
 FOREACH signature IN ARRAY ARRAY['public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)',
 'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)'] LOOP
  SELECT pg_get_functiondef(signature::regprocedure) INTO STRICT definition;
  anchor:='    PERFORM internal.require_service_role();';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial execution fence changed'; END IF;
  EXECUTE replace(definition,anchor,anchor||$body$
    IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations q JOIN internal.initial_analysis_operation_fences f ON f.scan_id IN (q.original_analysis_id,q.request_id) WHERE q.id=p_reservation_id) THEN
      RAISE EXCEPTION 'initial_analysis_execution_required' USING ERRCODE='55000'; END IF;
$body$);
 END LOOP;
 SELECT pg_get_functiondef('public.complete_identification_invocation(uuid,uuid,uuid,text,jsonb)'::regprocedure) INTO STRICT definition;
 anchor:='    PERFORM internal.require_service_role();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial outcome fence changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
    IF EXISTS(SELECT 1 FROM internal.identification_invocations v JOIN internal.initial_analysis_operation_fences f ON f.scan_id=v.scan_id WHERE v.id=p_invocation_id) THEN
      RAISE EXCEPTION 'initial_analysis_execution_required' USING ERRCODE='55000'; END IF;
$body$);
 SELECT pg_get_functiondef('internal.refund_expired_ai_quota_reservations(integer)'::regprocedure) INTO STRICT definition;
 anchor:='          AND reservations.lease_expires_at <= quota_now';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial expiry fence changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
          AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id IN (reservations.original_analysis_id,reservations.request_id))
$body$);
 SELECT pg_get_functiondef('internal.prune_ai_quota_state()'::regprocedure) INTO STRICT definition;
 anchor:='        WHERE candidates.state IN (''committed'', ''failed'', ''refunded'')';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed initial prune fence changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
          AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id IN (candidates.original_analysis_id,candidates.request_id))
$body$);
END;
$patch$;
COMMENT ON TABLE internal.initial_analysis_admissions IS 'Inactive IC-1 exact input/configuration/funding binding. Private canonical text and hashes erase with submission. Admission/replay never grants dispatch. Fresh-only cohort and all-route/worker cutover remain prerequisites.';
COMMENT ON TABLE internal.initial_analysis_operation_fences IS 'Permanent content-free logical scan namespace fence, retained after account/scan erasure. No owner, text hash, funding or dispatch authority.';
COMMENT ON FUNCTION public.admit_initial_analysis(UUID,UUID,TEXT,TEXT,TEXT,TEXT) IS 'Default-off IC-1 atomic original admission and exact replay. Existing funding owner only; rejects prior operations, never re-reserves an admitted ID. Not installed by current routes. All remaining S0 execution/media/settlement and old-writer quiescence gates remain required.';
RESET statement_timeout;
RESET lock_timeout;

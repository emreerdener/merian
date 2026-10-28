-- Inactive CPM photo allocation/recovery increment (under construction).
-- Closed content/candidate codecs below supply no runtime, storage or funding authority.
-- Preserve historical encoding and source-preparation branches.
SET lock_timeout = '5s';
SET statement_timeout = '60s';

CREATE FUNCTION internal.initial_cpm_photo_content_schema_v1() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path = '' AS $body$
SELECT $schema${"type":"object","properties":{"contract":{"type":"string","max_bytes":24,"enum":["client_prepared_media_v1"]},"version":{"type":"integer","minimum":1,"maximum":1},"kind":{"type":"string","max_bytes":13,"enum":["initial_photo"]},"resource_profile":{"type":"string","max_bytes":5,"enum":["P1-L1"]},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"package_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"photos":{"type":"array","max_items":2,"items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":0,"maximum":1},"source":{"type":"object","properties":{"reference_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":33554432},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"declared_content_type":{"type":"string","max_bytes":128,"pattern":"^[\\s\\S]+$"}}},"ai":{"type":"object","properties":{"reference_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":5242880},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"declared_content_type":{"type":"string","max_bytes":128,"pattern":"^[\\s\\S]+$"}}},"display":{"type":"object","properties":{"reference_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":4194304},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"declared_content_type":{"type":"string","max_bytes":128,"pattern":"^[\\s\\S]+$"}}},"recipe":{"type":"object","properties":{"format":{"type":"string","max_bytes":32,"enum":["nativeStillImageV1","nativeCameraStillV1"]},"is_pro":{"type":"boolean"},"crop_display_size_bits":{"type":"string","max_bytes":16,"pattern":"^[0-9a-f]{16}$","nullable":true},"quarter_turns":{"type":"integer","minimum":0,"maximum":3},"scale_bits":{"type":"string","max_bytes":16,"pattern":"^[0-9a-f]{16}$"},"offset_x_bits":{"type":"string","max_bytes":16,"pattern":"^[0-9a-f]{16}$"},"offset_y_bits":{"type":"string","max_bytes":16,"pattern":"^[0-9a-f]{16}$"},"camera_vertical_center_bits":{"type":"string","max_bytes":16,"pattern":"^[0-9a-f]{16}$","nullable":true}}}}}},"contexts":{"type":"array","max_items":64,"items":{"type":"object","properties":{"text_utf8_base64":{"type":"string","max_bytes":43692}}}}}}$schema$::JSONB;
$body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_content_schema_v1() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.initial_cpm_photo_candidate_schema_v1() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path = '' AS $body$
SELECT $schema${"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"content_canonical":{"type":"string","max_bytes":1048576},"admission":{"type":"object","properties":{"client_protocol":{"type":"integer","minimum":3,"maximum":3},"identification_protocol":{"type":"integer","minimum":6,"maximum":6},"expected_processor_permission":{"type":"string","max_bytes":32,"enum":["google_gemini","openai"]}}}}}$schema$::JSONB;
$body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_candidate_schema_v1() FROM PUBLIC, anon, authenticated, service_role;

-- Validate strict UTF-8 without decoding NUL into PostgreSQL TEXT. Count exactly
-- the native Unicode-scalar and UTF-16 units, including NUL and a leading BOM.
CREATE FUNCTION internal.initial_cpm_photo_text_units(p_encoded TEXT) RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE bytes BYTEA; size INTEGER; pos INTEGER:=0; first INTEGER; second INTEGER;
 width INTEGER; i INTEGER; scalars INTEGER:=0; units INTEGER:=0;
BEGIN
 IF p_encoded IS NULL OR octet_length(p_encoded)>43692 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN bytes:=decode(p_encoded,'base64');
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF replace(encode(bytes,'base64'),E'\n','')<>p_encoded THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 size:=octet_length(bytes);
 WHILE pos<size LOOP
  first:=get_byte(bytes,pos);
  IF first<128 THEN width:=1;
  ELSIF first BETWEEN 194 AND 223 THEN width:=2;
  ELSIF first BETWEEN 224 AND 239 THEN width:=3;
  ELSIF first BETWEEN 240 AND 244 THEN width:=4;
  ELSE RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF pos+width>size THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF width>1 THEN
   FOR i IN 1..width-1 LOOP
    IF get_byte(bytes,pos+i) NOT BETWEEN 128 AND 191 THEN
     RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   END LOOP;
   second:=get_byte(bytes,pos+1);
   IF (first=224 AND second<160) OR (first=237 AND second>159)
    OR (first=240 AND second<144) OR (first=244 AND second>143) THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END IF;
  scalars:=scalars+1; units:=units+CASE WHEN width=4 THEN 2 ELSE 1 END;
  IF scalars>8192 OR units>16384 THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  pos:=pos+width;
 END LOOP;
 RETURN units;
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_text_units(TEXT) FROM PUBLIC, anon, authenticated, service_role;

-- Only called after the closed recipe schema has checked types and hex spelling.
-- Positive finite binary64 bit strings sort numerically under C collation.
CREATE FUNCTION internal.assert_initial_cpm_photo_recipe(p_recipe JSONB) RETURNS VOID
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE field TEXT; bits TEXT; size TEXT:=p_recipe->>'crop_display_size_bits';
 center TEXT:=p_recipe->>'camera_vertical_center_bits'; scale TEXT:=p_recipe->>'scale_bits';
BEGIN
 IF NOT internal.initial_schema_matches(p_recipe,
  internal.initial_cpm_photo_content_schema_v1()#>'{properties,photos,items,properties,recipe}') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOREACH field IN ARRAY ARRAY['crop_display_size_bits','scale_bits','offset_x_bits','offset_y_bits','camera_vertical_center_bits'] LOOP
  bits:=p_recipe->>field;
  IF bits IS NOT NULL AND left(bits,3) IN ('7ff','fff') THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF scale COLLATE "C" < '3ff0000000000000' OR scale COLLATE "C" > '7fefffffffffffff'
  OR (size IS NOT NULL AND (size='0000000000000000' OR size COLLATE "C">'7fefffffffffffff')) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF size IS NULL AND ((p_recipe->>'quarter_turns')::INTEGER<>0 OR scale<>'3ff0000000000000'
  OR p_recipe->>'offset_x_bits' NOT IN ('0000000000000000','8000000000000000')
  OR p_recipe->>'offset_y_bits' NOT IN ('0000000000000000','8000000000000000')) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_recipe->>'format'='nativeCameraStillV1' THEN
  IF center IS NULL OR size IS NOT NULL OR (center<>'8000000000000000' AND center COLLATE "C">'3ff0000000000000') THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 ELSIF center IS NOT NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $body$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_photo_recipe(JSONB) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.parse_initial_cpm_photo_content(p_text TEXT) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE value JSONB; photo JSONB; role JSONB; context JSONB; position INTEGER:=0;
 refs TEXT[]:=ARRAY[]::TEXT[]; originals BIGINT:=0; ai BIGINT:=0; display BIGINT:=0; units INTEGER:=0;
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>1048576 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF NOT internal.initial_schema_matches(value,internal.initial_cpm_photo_content_schema_v1())
  OR internal.initial_canonical(value)<>p_text OR jsonb_array_length(value->'photos')<1 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR photo IN SELECT item FROM jsonb_array_elements(value->'photos') item LOOP
  IF (photo->>'ordinal')::INTEGER<>position THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  position:=position+1;
  FOR role IN SELECT item FROM jsonb_array_elements(jsonb_build_array(photo->'source',photo->'ai',photo->'display')) item LOOP
   IF role->>'reference_id'=ANY(refs) THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   refs:=array_append(refs,role->>'reference_id');
  END LOOP;
  originals:=originals+(photo#>>'{source,byte_count}')::BIGINT;
  ai:=ai+(photo#>>'{ai,byte_count}')::BIGINT;
  display:=display+(photo#>>'{display,byte_count}')::BIGINT;
  PERFORM internal.assert_initial_cpm_photo_recipe(photo->'recipe');
 END LOOP;
 IF originals>67108864 OR ai>5242880 OR display>8388608
  OR originals+ai+display+octet_length(p_text)>100663296 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR context IN SELECT item FROM jsonb_array_elements(value->'contexts') item LOOP
  units:=units+internal.initial_cpm_photo_text_units(context->>'text_utf8_base64');
  IF units>32000 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 RETURN value;
END; $body$;
REVOKE ALL ON FUNCTION internal.parse_initial_cpm_photo_content(TEXT) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.parse_initial_cpm_photo_candidate(p_text TEXT) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE value JSONB;
BEGIN
 IF p_text IS NULL OR octet_length(p_text)>1048576 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF NOT internal.initial_schema_matches(value,internal.initial_cpm_photo_candidate_schema_v1())
  OR internal.initial_canonical(value)<>p_text THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.parse_initial_cpm_photo_content(value->>'content_canonical');
 RETURN value;
END; $body$;
REVOKE ALL ON FUNCTION internal.parse_initial_cpm_photo_candidate(TEXT) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.initial_cpm_photo_digest(p_kind TEXT,p_text TEXT) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('content','candidate','assignment') OR p_text IS NULL OR octet_length(p_text)>1048576 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-'||p_kind||E'.v1\n'||p_text,'UTF8'),'sha256'),'hex');
END; $body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_digest(TEXT,TEXT) FROM PUBLIC, anon, authenticated, service_role;


CREATE FUNCTION internal.initial_cpm_photo_assignment_schema_v1() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path = '' AS $body$
SELECT $schema${"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"package_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"created_at_ms":{"type":"integer","minimum":1,"maximum":8639999998200000},"expires_at_ms":{"type":"integer","minimum":1800001,"maximum":8640000000000000},"configuration":{"type":"object","properties":{"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"effective_tier":{"type":"string","max_bytes":128,"enum":["free","pro"]},"flash_fallback_used":{"type":"boolean"},"quota_model":{"type":"string","max_bytes":128},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"provider":{"type":"string","max_bytes":128,"enum":["gemini","openai"]},"binding":{"type":"string","max_bytes":128},"processor_permission":{"type":"string","max_bytes":128,"enum":["google_gemini","openai"]},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1"]},"provider_model":{"type":"string","max_bytes":128,"nullable":true},"effective_model":{"type":"string","max_bytes":128},"minimum_client_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_client_protocol":{"type":"integer","minimum":3,"maximum":3},"minimum_identification_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6},"asset_manifest_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"retention_owner":{"type":"string","max_bytes":128,"enum":["initial_engine_release_archive"]},"resolver_id":{"type":"string","max_bytes":128,"enum":["git_blob_sha256_v1"]},"output_language":{"type":"string","max_bytes":64,"pattern":"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$"}}},"preparation":{"type":"object","properties":{"resource_profile":{"type":"string","max_bytes":5,"enum":["P1-L1"]},"composition_policy":{"type":"string","max_bytes":32,"enum":["cpm_photo_contexts_v1"]},"profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"selector_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verifier_build_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"role_mapping":{"type":"array","max_items":6,"items":{"type":"object","properties":{"photo_ordinal":{"type":"integer","minimum":0,"maximum":1},"role":{"type":"string","max_bytes":7,"enum":["source","ai","display"]},"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"declaration":{"type":"object","properties":{"reference_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":33554432},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"declared_content_type":{"type":"string","max_bytes":128,"pattern":"^[\\s\\S]+$"}}}}}}}}}}$schema$::JSONB;
$body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_assignment_schema_v1() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.initial_cpm_photo_recovery_schema_v1() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path = '' AS $body$
SELECT $schema${"allocated":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"outcome":{"type":"string","max_bytes":24,"enum":["allocated"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"assignment_canonical":{"type":"string","max_bytes":65536},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"terminal_held":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"outcome":{"type":"string","max_bytes":24,"enum":["terminal_held"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"reason":{"type":"string","max_bytes":16,"enum":["not_found","expired","cancelled"]}}}}$schema$::JSONB;
$body$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_recovery_schema_v1() FROM PUBLIC, anon, authenticated, service_role;

-- Strict saved binding only; the allocator separately proves current server
-- selection, consent, ownership, installation eligibility and object rows.
CREATE FUNCTION internal.parse_initial_cpm_photo_assignment(p_candidate TEXT,p_assignment TEXT) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE candidate JSONB; content JSONB; value JSONB; config JSONB; mapping JSONB;
 member JSONB; expected JSONB; object_ids TEXT[]:=ARRAY[]::TEXT[];
 position INTEGER:=0; ordinal INTEGER; role TEXT; roles TEXT[]:=ARRAY['source','ai','display'];
BEGIN
 candidate:=internal.parse_initial_cpm_photo_candidate(p_candidate);
 content:=internal.parse_initial_cpm_photo_content(candidate->>'content_canonical');
 IF p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_assignment::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF NOT internal.initial_schema_matches(value,internal.initial_cpm_photo_assignment_schema_v1()) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF internal.initial_canonical(value)<>p_assignment THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 config:=value->'configuration'; mapping:=value#>'{preparation,role_mapping}';
 IF value->>'scan_id'<>content->>'scan_id' OR value->>'package_id'<>content->>'package_id'
  OR (value->>'expires_at_ms')::BIGINT-(value->>'created_at_ms')::BIGINT<>1800000
  OR value->>'candidate_digest'<>internal.initial_cpm_photo_digest('candidate',p_candidate)
  OR value->>'content_digest'<>internal.initial_cpm_photo_digest('content',candidate->>'content_canonical')
  OR config->>'processor_permission'<>candidate#>>'{admission,expected_processor_permission}'
  OR config->'accepted_client_protocol'<>candidate#>'{admission,client_protocol}'
  OR config->'accepted_identification_protocol'<>candidate#>'{admission,identification_protocol}'
  OR (config->>'minimum_client_protocol')::INTEGER>(config->>'accepted_client_protocol')::INTEGER
  OR (config->>'minimum_identification_protocol')::INTEGER>(config->>'accepted_identification_protocol')::INTEGER
  OR config->>'effective_tier'<>(CASE WHEN config->>'effective_plan'='free' THEN 'free' ELSE 'pro' END)
  OR config->>'effective_model'<>COALESCE(config->>'provider_model',config->>'quota_model')
  OR (config->>'provider'='gemini')<>(config->>'processor_permission'='google_gemini')
  OR (config->>'route'='identify')<>(config->>'input_profile'='vision_compat_v1')
  OR jsonb_array_length(mapping)<>jsonb_array_length(content->'photos')*3 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR member IN SELECT item FROM jsonb_array_elements(mapping) item LOOP
  ordinal:=position/3; role:=roles[(position%3)+1];
  expected:=content->'photos'->ordinal->role;
  IF (member->>'photo_ordinal')::INTEGER<>ordinal OR member->>'role'<>role
   OR member->'declaration'<>expected OR member->>'object_id'=ANY(object_ids) THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  object_ids:=array_append(object_ids,member->>'object_id'); position:=position+1;
 END LOOP;
 RETURN value;
END; $body$;
REVOKE ALL ON FUNCTION internal.parse_initial_cpm_photo_assignment(TEXT,TEXT) FROM PUBLIC, anon, authenticated, service_role;

-- Explicit NULL means the first allocation acknowledgement was lost. A saved
-- assignment can never be replaced with a different otherwise-valid binding.
CREATE FUNCTION internal.parse_initial_cpm_photo_recovery(p_candidate TEXT,p_response TEXT,p_saved_assignment TEXT) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE candidate JSONB; content JSONB; value JSONB; assignment JSONB;
BEGIN
 candidate:=internal.parse_initial_cpm_photo_candidate(p_candidate);
 content:=internal.parse_initial_cpm_photo_content(candidate->>'content_canonical');
 IF p_response IS NULL OR octet_length(p_response)>1048576 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_response::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF jsonb_typeof(value) IS DISTINCT FROM 'object' OR internal.initial_canonical(value)<>p_response THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_saved_assignment IS NOT NULL THEN
  PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,p_saved_assignment);
 END IF;
 IF value->>'outcome'='terminal_held' THEN
  IF NOT internal.initial_schema_matches(value,internal.initial_cpm_photo_recovery_schema_v1()->'terminal_held')
   OR value->>'scan_id'<>content->>'scan_id' THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  RETURN value;
 END IF;
 IF NOT internal.initial_schema_matches(value,internal.initial_cpm_photo_recovery_schema_v1()->'allocated') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 assignment:=internal.parse_initial_cpm_photo_assignment(p_candidate,value->>'assignment_canonical');
 IF value->>'assignment_digest'<>internal.initial_cpm_photo_digest('assignment',value->>'assignment_canonical')
  OR (p_saved_assignment IS NOT NULL AND value->>'assignment_canonical'<>p_saved_assignment) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN value;
END; $body$;
REVOKE ALL ON FUNCTION internal.parse_initial_cpm_photo_recovery(TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated, service_role;

RESET statement_timeout;
RESET lock_timeout;

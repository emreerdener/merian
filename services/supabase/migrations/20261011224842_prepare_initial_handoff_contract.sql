SET lock_timeout='5s';
SET statement_timeout='2min';

-- Pure private codec/arithmetic. No catalogs, installation, locks or authority.
CREATE FUNCTION internal.initial_handoff_schema() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$
 SELECT $json${"protocol_artifact":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"input_projection":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":1,"maximum":1}}},"m1_mapping":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":2,"maximum":2}}},"m2_codec":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":2,"maximum":2}}},"transfer_validator":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":1,"maximum":1}}},"deadline_protocol":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":1,"maximum":1}}},"response_codec":{"type":"object","properties":{"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"schema_version":{"type":"integer","minimum":2,"maximum":2}}}}},"profile":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"source_backend_config_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"destination_backend_config_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"copy_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"cohort_limits":{"type":"object","properties":{"max_ordinals":{"type":"integer","minimum":1,"maximum":8},"max_unique_objects":{"type":"integer","minimum":1,"maximum":10},"max_unique_bytes":{"type":"integer","minimum":1,"maximum":28625792},"content_type_pairs":{"type":"array","max_items":7,"items":{"type":"object","properties":{"kind":{"type":"string","max_bytes":128,"enum":["image","audio","video"]},"source_content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]},"prepared_content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav"],"nullable":true}}}},"alias_policy":{"type":"string","max_bytes":128,"enum":["same_ordinal_exact_bytes_only"]},"video_policy":{"type":"string","max_bytes":128,"enum":["source_only"]}}},"phase_ms":{"type":"object","properties":{"admission":{"type":"integer","minimum":1,"maximum":299999},"copy":{"type":"integer","minimum":1,"maximum":299999},"verification_claim":{"type":"integer","minimum":1,"maximum":299999},"verification":{"type":"integer","minimum":1,"maximum":299999},"verification_settlement":{"type":"integer","minimum":1,"maximum":299999},"transfer":{"type":"integer","minimum":1,"maximum":299999},"reconciliation":{"type":"integer","minimum":1,"maximum":299999},"protocol_margin":{"type":"integer","minimum":1,"maximum":299999}}},"total_ms":{"type":"integer","minimum":8,"maximum":299999},"execution_model":{"type":"string","max_bytes":128,"enum":["sequential_whole_cohort"]}}}}$json$::JSONB;
$schema$;

CREATE FUNCTION internal.initial_handoff_digest(p_domain TEXT,p_text TEXT) RETURNS TEXT
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 IF p_domain IS NULL OR p_domain NOT IN ('profile','protocol_artifact') OR p_text IS NULL OR octet_length(p_text)>1048576 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.handoff.'||p_domain||E'.v1\n'||p_text,'UTF8'),'sha256'),'hex');
END; $$;

CREATE FUNCTION internal.parse_initial_handoff_shape(p_kind TEXT,p_text TEXT) RETURNS JSONB
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; shape JSONB;
BEGIN
 shape:=internal.initial_handoff_schema()->p_kind;
 IF shape IS NULL OR p_text IS NULL OR octet_length(p_text)>16384 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(value) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(value,shape) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 RETURN value;
END; $$;

CREATE FUNCTION internal.parse_initial_handoff_profile(p_text TEXT,p_protocol TEXT) RETURNS JSONB
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; pairs JSONB; pair JSONB; valid BOOLEAN; total BIGINT;
BEGIN
 PERFORM internal.parse_initial_handoff_shape('protocol_artifact',p_protocol);
 value:=internal.parse_initial_handoff_shape('profile',p_text);
 pairs:=value#>'{cohort_limits,content_type_pairs}';
 SELECT sum(v::BIGINT) INTO total FROM jsonb_each_text(value->'phase_ms') AS x(k,v);
 IF value->>'protocol_artifact_digest' IS DISTINCT FROM internal.initial_handoff_digest('protocol_artifact',p_protocol)
  OR total<>(value->>'total_ms')::BIGINT OR jsonb_array_length(pairs)=0
  OR (value#>>'{cohort_limits,max_unique_objects}')::INTEGER<(value#>>'{cohort_limits,max_ordinals}')::INTEGER
  OR (SELECT count(DISTINCT v) FROM jsonb_array_elements(pairs) AS x(v))<>jsonb_array_length(pairs) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 FOR pair IN SELECT * FROM jsonb_array_elements(pairs) LOOP
  valid:=CASE pair->>'kind'
   WHEN 'video' THEN pair->>'source_content_type'='video/mp4' AND pair->'prepared_content_type'='null'::JSONB
   WHEN 'audio' THEN pair->>'source_content_type'='audio/wav' AND pair->>'prepared_content_type'='audio/wav'
   ELSE pair->>'source_content_type' IN ('image/jpeg','image/png','image/webp','image/heic','image/heif') AND pair->>'prepared_content_type'=pair->>'source_content_type'
  END;
  IF valid IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 RETURN value;
END; $$;

CREATE FUNCTION internal.assert_initial_handoff_window(p_now NUMERIC,p_expires NUMERIC) RETURNS VOID
LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
BEGIN
 IF p_now IS NULL OR p_expires IS NULL
  OR p_now NOT BETWEEN 0 AND 9007199254740991 OR p_expires NOT BETWEEN 0 AND 9007199254740991
  OR p_now<>trunc(p_now) OR p_expires<>trunc(p_expires)
  OR p_expires<=p_now OR p_expires-p_now>300000 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
END; $$;

CREATE FUNCTION internal.assert_initial_handoff_issue_budget(p_profile TEXT,p_protocol TEXT,p_now NUMERIC,p_expires NUMERIC,p_wall NUMERIC) RETURNS VOID
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB;
BEGIN
 value:=internal.parse_initial_handoff_profile(p_profile,p_protocol);
 PERFORM internal.assert_initial_handoff_window(p_now,p_expires);
 IF p_wall IS NULL OR p_wall NOT BETWEEN 1 AND 300000 OR p_wall<>trunc(p_wall) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 IF 45000+p_wall+(value->>'total_ms')::NUMERIC>=p_expires-p_now THEN
  RAISE EXCEPTION 'initial_analysis_handoff_budget_unavailable' USING ERRCODE='55000';
 END IF;
END; $$;

CREATE FUNCTION internal.initial_handoff_phase_cutoffs(p_profile TEXT,p_protocol TEXT,p_anchor NUMERIC,p_expires NUMERIC) RETURNS JSONB
LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE value JSONB; phase TEXT; cutoff NUMERIC:=p_anchor; result JSONB:='{}'::JSONB;
BEGIN
 value:=internal.parse_initial_handoff_profile(p_profile,p_protocol);
 PERFORM internal.assert_initial_handoff_window(p_anchor,p_expires);
 IF (value->>'total_ms')::NUMERIC>=p_expires-p_anchor THEN
  RAISE EXCEPTION 'initial_analysis_handoff_budget_unavailable' USING ERRCODE='55000';
 END IF;
 FOREACH phase IN ARRAY ARRAY['admission','copy','verification_claim','verification','verification_settlement','transfer','reconciliation','protocol_margin'] LOOP
  cutoff:=cutoff+(value#>>ARRAY['phase_ms',phase])::NUMERIC;
  result:=result||jsonb_build_object(phase,cutoff::BIGINT);
 END LOOP;
 RETURN result;
END; $$;

REVOKE ALL ON FUNCTION internal.initial_handoff_schema(),internal.initial_handoff_digest(TEXT,TEXT),internal.parse_initial_handoff_shape(TEXT,TEXT),internal.parse_initial_handoff_profile(TEXT,TEXT),internal.assert_initial_handoff_window(NUMERIC,NUMERIC),internal.assert_initial_handoff_issue_budget(TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC),internal.initial_handoff_phase_cutoffs(TEXT,TEXT,NUMERIC,NUMERIC) FROM PUBLIC,anon,authenticated,service_role;
RESET lock_timeout;
RESET statement_timeout;

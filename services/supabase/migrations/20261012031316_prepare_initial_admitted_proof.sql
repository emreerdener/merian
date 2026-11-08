-- Inactive complete proof parity. No receipt issuance, storage, funding or dispatch authority.
SET lock_timeout='5s';
SET statement_timeout='2min';
CREATE FUNCTION internal.initial_admitted_proof_schema() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $f$
SELECT $json${"funding":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"original":{"type":"object","properties":{"reservation_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"request_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"original_analysis_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"attempt_count":{"type":"integer","minimum":1,"maximum":1},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"effective_tier":{"type":"string","max_bytes":128,"enum":["free","pro"]},"entitlement_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"model":{"type":"string","max_bytes":128,"enum":["gemini-2.5-flash","gemini-2.5-pro","gpt-6-sol"]},"complimentary_client_scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true},"flash_fallback_used":{"type":"boolean"}}}}},"accounting":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"reservation":{"type":"object","properties":{"reservation_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"attempt_count":{"type":"integer","minimum":1,"maximum":1},"lease_token":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"lease_expires_at":{"type":"string","max_bytes":27,"pattern":"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$"}}},"attempt":{"type":"object","properties":{"reservation_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"attempt_count":{"type":"integer","minimum":1,"maximum":1},"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"model":{"type":"string","max_bytes":128,"enum":["gemini-2.5-flash","gemini-2.5-pro"]},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991},"provider":{"type":"string","max_bytes":128,"enum":["gemini","openai"]},"binding":{"type":"string","max_bytes":128},"processor_permission":{"type":"string","max_bytes":128,"enum":["google_gemini","openai"]},"input_profile":{"type":"string","max_bytes":128,"enum":["vision_compat_v1","multimodal_photo_v1","multimodal_audio_v1","multimodal_photo_audio_v1","multimodal_video_frames_v1","multimodal_video_audio_v1"]},"provider_model":{"type":"string","max_bytes":128,"nullable":true},"minimum_client_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_client_protocol":{"type":"integer","minimum":3,"maximum":3},"minimum_identification_protocol":{"type":"integer","minimum":0,"maximum":1000},"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}}},"charges":{"type":"object","properties":{"policy":{"type":"object","properties":{"operation":{"type":"string","max_bytes":128,"enum":["scan_identification"]},"effective_plan":{"type":"string","max_bytes":128,"enum":["free","pro_trial","pro_paid","pro_complimentary"]},"policy_version":{"type":"integer","minimum":1,"maximum":9007199254740991}}},"links":{"type":"array","max_items":3,"items":{"type":"object","properties":{"reservation_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scope_type":{"type":"string","max_bytes":128,"enum":["user_daily","user_rate","ip_rate"]},"scope_key":{"type":"string","max_bytes":64},"bucket":{"type":"string","max_bytes":1024},"window_start":{"type":"string","max_bytes":27,"pattern":"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$"},"window_seconds":{"type":"integer","minimum":1,"maximum":86400},"delta":{"type":"integer","minimum":1,"maximum":1}}}}}},"complimentary":{"type":"object","properties":{"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"client_scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"classification":{"type":"string","max_bytes":128,"enum":["pro_complimentary"]},"state_at_admission":{"type":"string","max_bytes":128,"enum":["held"]}},"nullable":true}}},"manifest":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"route":{"type":"string","max_bytes":128,"enum":["identify","identify-multimodal"]},"input_schema_version":{"type":"integer","minimum":1,"maximum":1},"binding_version":{"type":"integer","minimum":3,"maximum":3},"funding_binding_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"authorized_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"metadata":{"type":"object","properties":{"mapping":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":65536}}},"media_binding":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":16384}}}}},"proof":{"type":"object","properties":{"candidate":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":1048576}}},"input":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":1048576}}},"configuration":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":65563}}},"funding":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":4096}}},"outcome":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":131072}}},"installation":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":16384}}},"protocol":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":16384}}},"destination":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":16384}}},"accounting":{"type":"object","properties":{"digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"byte_count":{"type":"integer","minimum":1,"maximum":32768}}}}},"metadata_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"proof_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"descriptions_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assets_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}}}$json$::JSONB;
$f$;

-- Validate each original canonical TEXT before any JSON parsing or composition.
CREATE FUNCTION internal.parse_initial_admitted_component(p_kind TEXT,p_text TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE v JSONB; cap INTEGER; shape JSONB;
BEGIN
 cap:=CASE p_kind
  WHEN 'candidate' THEN 1048576 WHEN 'input' THEN 1048576
  WHEN 'configuration' THEN 65563 WHEN 'funding' THEN 4096
  WHEN 'outcome' THEN 131072 WHEN 'installation' THEN 16384
  WHEN 'protocol' THEN 16384 WHEN 'destination' THEN 16384
  WHEN 'mapping' THEN 65536 WHEN 'media_binding' THEN 16384
  WHEN 'accounting' THEN 32768 WHEN 'manifest' THEN 8192 END;
 IF cap IS NULL OR p_text IS NULL OR octet_length(p_text)>cap THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 BEGIN v:=p_text::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF internal.initial_canonical(v) IS DISTINCT FROM p_text THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 shape:=internal.initial_admitted_proof_schema()->p_kind;
 IF shape IS NOT NULL AND NOT internal.initial_schema_matches(v,shape) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 RETURN v;
END; $$;

-- Gregorian calendar arithmetic: no timezone, epoch, DateStyle or precision coercion.
CREATE FUNCTION internal.valid_initial_admitted_timestamp(p_text TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SET search_path='' AS $$
DECLARE y INTEGER; m INTEGER; d INTEGER; days INTEGER[];
BEGIN
 IF p_text IS NULL OR length(p_text)<>27 OR p_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$' THEN RETURN FALSE; END IF;
 y:=substring(p_text,1,4)::INTEGER; m:=substring(p_text,6,2)::INTEGER; d:=substring(p_text,9,2)::INTEGER;
 IF y<1 OR m<1 OR m>12 OR substring(p_text,12,2)::INTEGER>23
  OR substring(p_text,15,2)::INTEGER>59 OR substring(p_text,18,2)::INTEGER>59 THEN RETURN FALSE; END IF;
 days:=ARRAY[31,CASE WHEN y%4=0 AND (y%100<>0 OR y%400=0) THEN 29 ELSE 28 END,31,30,31,30,31,31,30,31,30,31];
 RETURN d>=1 AND d<=days[m];
END; $$;

-- Fixed independent TEXT arguments, never an aggregate JSON receipt payload.
-- Successful validation proves internal historical consistency only. Future owners
-- must compare locked authority, exact accounting rows and erasure/terminal fences.
CREATE FUNCTION internal.validate_initial_admitted_proof(
 p_candidate TEXT,p_input TEXT,p_configuration TEXT,p_funding TEXT,p_outcome TEXT,
 p_installation TEXT,p_protocol TEXT,p_destination TEXT,p_mapping TEXT,
 p_media_binding TEXT,p_accounting TEXT,p_manifest TEXT
) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE
 kinds TEXT[]:=ARRAY['candidate','input','configuration','funding','outcome','installation','protocol','destination','mapping','media_binding','accounting','manifest'];
 texts TEXT[]:=ARRAY[p_candidate,p_input,p_configuration,p_funding,p_outcome,p_installation,p_protocol,p_destination,p_mapping,p_media_binding,p_accounting,p_manifest];
 docs JSONB[]:=ARRAY[]::JSONB[]; total BIGINT:=0; charge_index INTEGER; k TEXT; domain_name TEXT; ref JSONB;
 candidate JSONB; input_value JSONB; configuration JSONB; funding JSONB; outcome JSONB;
 binding JSONB; accounting JSONB; manifest JSONB; a JSONB; metadata JSONB; original JSONB;
 reservation JSONB; attempt JSONB; policy JSONB; links JSONB; link JSONB; scopes TEXT[]; complimentary JSONB;
BEGIN
 FOR n IN 1..12 LOOP
  docs:=array_append(docs,internal.parse_initial_admitted_component(kinds[n],texts[n]));
  total:=total+octet_length(texts[n]);
 END LOOP;
 IF total>2469915 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 candidate:=docs[1]; input_value:=docs[2]; configuration:=docs[3]; funding:=docs[4]; outcome:=docs[5];
 binding:=internal.parse_initial_admission_metadata('media_binding',p_media_binding); accounting:=docs[11]; manifest:=docs[12];
 IF jsonb_typeof(configuration) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF configuration->'version' IS DISTINCT FROM '2'::JSONB OR NOT configuration ? 'assignment'
  OR configuration-ARRAY['assignment','version'] IS DISTINCT FROM '{}'::JSONB THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 a:=configuration->'assignment';
 metadata:=internal.validate_initial_admission_metadata(
  p_candidate,internal.initial_canonical(a),internal.initial_canonical(outcome->'profile'),
  p_installation,p_protocol,p_destination,(binding#>>'{phase_window,original_expires_at_ms}')::NUMERIC,
  p_outcome,internal.initial_canonical(jsonb_build_object('owner_id',manifest->'owner_id','scan_id',manifest->'scan_id','admission_receipt_id',manifest->'admission_receipt_id')),
  internal.initial_canonical(binding->'phase_window'),p_mapping,p_media_binding);
 IF metadata->>'canonical_input' IS DISTINCT FROM p_input
  OR manifest->'route' IS DISTINCT FROM input_value->'route' OR manifest->'route' IS DISTINCT FROM a->'route'
  OR manifest->'input_schema_version' IS DISTINCT FROM input_value->'schema_version'
  OR manifest->'input_schema_version' IS DISTINCT FROM candidate#>'{source_plan,schema_version}'
  OR manifest->'descriptions_digest' IS DISTINCT FROM metadata->'descriptions_digest'
  OR manifest->'phase_window_digest' IS DISTINCT FROM metadata->'phase_window_digest'
  OR manifest->'assets_digest' IS DISTINCT FROM a->'asset_manifest_digest'
  OR (manifest->>'authorized_at_ms')::NUMERIC<(binding#>>'{phase_window,anchor_ms}')::NUMERIC
  OR (manifest->>'authorized_at_ms')::NUMERIC>=(binding#>>'{phase_window,cutoffs,admission}')::NUMERIC THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 FOR n IN 1..11 LOOP
  k:=kinds[n]; ref:=CASE WHEN k IN ('mapping','media_binding') THEN manifest#>ARRAY['metadata',k] ELSE manifest#>ARRAY['proof',k] END;
  domain_name:=CASE k
   WHEN 'candidate' THEN 'preparation-candidate.v2' WHEN 'input' THEN 'input.v1'
   WHEN 'configuration' THEN 'configuration.v1' WHEN 'funding' THEN 'funding.v1'
   WHEN 'outcome' THEN 'preparation-execution.outcome.v2' WHEN 'installation' THEN 'handoff.installation.v1'
   WHEN 'protocol' THEN 'handoff.protocol_artifact.v1' WHEN 'destination' THEN 'handoff.destination_backend.v1'
   WHEN 'mapping' THEN 'handoff.mapping.v2' WHEN 'media_binding' THEN 'handoff.media_binding.v2'
   WHEN 'accounting' THEN 'handoff.accounting.v1' END;
  IF (ref->>'byte_count')::INTEGER IS DISTINCT FROM octet_length(texts[n])
   OR ref->>'digest' IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.'||domain_name||chr(10)||texts[n],'UTF8'),'sha256'),'hex') THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
  END IF;
 END LOOP;
 IF manifest->>'metadata_digest' IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-metadata.v1'||chr(10)||internal.initial_canonical(manifest->'metadata'),'UTF8'),'sha256'),'hex')
  OR manifest->>'proof_digest' IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-proof.v1'||chr(10)||internal.initial_canonical(manifest->'proof'),'UTF8'),'sha256'),'hex')
  OR manifest->>'assignment_digest' IS DISTINCT FROM internal.initial_preparation_digest('assignment',internal.initial_canonical(a))
  OR manifest->'assignment_digest' IS DISTINCT FROM binding->'assignment_digest'
  OR manifest#>'{proof,candidate,digest}' IS DISTINCT FROM a->'candidate_digest'
  OR manifest#>'{proof,input,digest}' IS DISTINCT FROM binding->'submission_digest'
  OR manifest#>'{proof,outcome,digest}' IS DISTINCT FROM binding->'outcome_digest'
  OR manifest#>'{metadata,mapping,digest}' IS DISTINCT FROM binding->'mapping_digest'
  OR manifest#>'{proof,installation,digest}' IS DISTINCT FROM a#>'{handoff,installation_digest}'
  OR manifest#>'{proof,protocol,digest}' IS DISTINCT FROM a#>'{handoff,profile,protocol_artifact_digest}'
  OR manifest#>'{proof,destination,digest}' IS DISTINCT FROM a#>'{handoff,profile,destination_backend_config_digest}' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 original:=funding->'original'; reservation:=accounting->'reservation'; attempt:=accounting->'attempt';
 IF manifest->'funding_binding_id' IS DISTINCT FROM original->'reservation_id'
  OR reservation->'reservation_id' IS DISTINCT FROM original->'reservation_id'
  OR attempt->'reservation_id' IS DISTINCT FROM original->'reservation_id'
  OR reservation->'owner_id' IS DISTINCT FROM manifest->'owner_id' OR reservation->'scan_id' IS DISTINCT FROM manifest->'scan_id'
  OR original->'request_id' IS DISTINCT FROM manifest->'scan_id' OR original->'original_analysis_id' IS DISTINCT FROM manifest->'scan_id'
  OR NOT internal.valid_initial_admitted_timestamp(reservation->>'lease_expires_at') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 FOREACH k IN ARRAY ARRAY['operation','effective_plan','policy_version','effective_tier','flash_fallback_used'] LOOP
  IF original->k IS DISTINCT FROM a->k THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['operation','effective_plan','policy_version','provider','binding','processor_permission','input_profile','provider_model','minimum_client_protocol','accepted_client_protocol','minimum_identification_protocol','accepted_identification_protocol'] LOOP
  IF attempt->k IS DISTINCT FROM a->k THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF attempt->'model' IS DISTINCT FROM a->'quota_model' OR original->'model' IS DISTINCT FROM a->'effective_model'
  OR a->'effective_model' IS DISTINCT FROM (CASE WHEN a->'provider_model'='null'::JSONB THEN a->'quota_model' ELSE a->'provider_model' END)
  OR a->>'effective_tier' IS DISTINCT FROM (CASE WHEN a->>'effective_plan'='free' THEN 'free' ELSE 'pro' END)
  OR ((a->>'flash_fallback_used')::BOOLEAN AND a->>'effective_plan'<>'free')
  OR (a->>'minimum_client_protocol')::INTEGER>(a->>'accepted_client_protocol')::INTEGER
  OR input_value#>'{admission,client_protocol}' IS DISTINCT FROM a->'accepted_client_protocol'
  OR input_value#>'{admission,identification_protocol}' IS DISTINCT FROM a->'accepted_identification_protocol'
  OR input_value#>'{admission,expected_processor_permission}' IS DISTINCT FROM a->'processor_permission' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 IF a->>'provider'='gemini' THEN
  IF a->>'binding'<>'gemini_baseline_v1' OR a->>'processor_permission'<>'google_gemini'
   OR a->'provider_model'<>'null'::JSONB OR a->'minimum_identification_protocol'<>'0'::JSONB THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 ELSIF a->>'provider'='openai' THEN
  IF a->>'binding'<>'openai_photo_v1' OR a->>'processor_permission'<>'openai'
   OR a->>'provider_model' IS DISTINCT FROM 'gpt-6-sol' OR a->>'input_profile'<>'multimodal_photo_v1'
   OR a->'minimum_identification_protocol'<>'4'::JSONB THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 ELSE RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 policy:=accounting#>'{charges,policy}'; links:=accounting#>'{charges,links}';
 FOREACH k IN ARRAY ARRAY['operation','effective_plan','policy_version'] LOOP
  IF policy->k IS DISTINCT FROM original->k THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF jsonb_array_length(links) NOT IN (2,3) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 scopes:=CASE WHEN jsonb_array_length(links)=3 THEN ARRAY['user_daily','user_rate','ip_rate'] ELSE ARRAY['user_rate','ip_rate'] END;
 FOR link,charge_index IN SELECT v,i::INTEGER FROM jsonb_array_elements(links) WITH ORDINALITY z(v,i) LOOP
  IF link->>'scope_type' IS DISTINCT FROM scopes[charge_index] OR link->'reservation_id' IS DISTINCT FROM original->'reservation_id'
   OR (CASE WHEN link->>'scope_type'='ip_rate' THEN link->>'scope_key' !~ '^[0-9a-f]{64}$' ELSE link->'scope_key' IS DISTINCT FROM manifest->'owner_id' END)
   OR btrim(link->>'bucket')='' OR NOT internal.valid_initial_admitted_timestamp(link->>'window_start')
   OR (CASE WHEN link->>'scope_type'='user_daily' THEN (link->>'window_seconds')::INTEGER<>86400 ELSE (link->>'window_seconds')::INTEGER>3600 END) THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
  END IF;
 END LOOP;
 complimentary:=accounting->'complimentary';
 IF (original->'complimentary_client_scan_id'='null'::JSONB) IS DISTINCT FROM (complimentary='null'::JSONB)
  OR (a->>'effective_plan'='pro_complimentary') IS DISTINCT FROM (complimentary<>'null'::JSONB) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 IF complimentary<>'null'::JSONB AND (complimentary->'owner_id' IS DISTINCT FROM manifest->'owner_id'
  OR complimentary->'client_scan_id' IS DISTINCT FROM manifest->'scan_id'
  OR original->'complimentary_client_scan_id' IS DISTINCT FROM manifest->'scan_id') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-receipt.v1'||chr(10)||p_manifest,'UTF8'),'sha256'),'hex');
END; $$;

REVOKE ALL ON FUNCTION internal.initial_admitted_proof_schema(),
 internal.parse_initial_admitted_component(TEXT,TEXT),internal.valid_initial_admitted_timestamp(TEXT),
 internal.validate_initial_admitted_proof(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;
RESET lock_timeout;
RESET statement_timeout;

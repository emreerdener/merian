-- Reuse only values validated from the same immutable TEXT in this invocation.
-- These private declaration helpers confer no authority and read no live rows.
-- Direct entry points still parse fully; callbacks, locks and deadlines remain.
SET lock_timeout='5s';
SET statement_timeout='2min';

CREATE FUNCTION internal.initial_media_assignment_pair_values(p_candidate TEXT,p_assignment TEXT,p_candidate_value JSONB) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE c JSONB; a JSONB; mapping JSONB; ordinal INTEGER:=0;
BEGIN
 c:=p_candidate_value;
 IF p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN RETURN FALSE; END IF;
 BEGIN a:=p_assignment::JSONB; EXCEPTION WHEN OTHERS THEN RETURN FALSE; END;
 IF internal.initial_canonical(a) IS DISTINCT FROM p_assignment OR NOT internal.initial_schema_matches(a,internal.initial_media_assignment_schema()) THEN RETURN FALSE; END IF;
 IF a->>'candidate_digest' IS DISTINCT FROM internal.initial_preparation_digest('preparation-candidate',p_candidate)
 OR a->>'source_plan_digest' IS DISTINCT FROM internal.initial_media_contract_digest('source_plan',internal.initial_canonical(c->'source_plan'))
 OR a->>'route' IS DISTINCT FROM c#>>'{source_plan,route}' OR a->>'input_profile' IS DISTINCT FROM internal.initial_source_input_profile(c->'source_plan')
 OR jsonb_array_length(a#>'{preparation,source_mapping}')<>jsonb_array_length(c#>'{source_plan,sources}')
 OR (SELECT count(DISTINCT m->>'object_id') FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m)<>jsonb_array_length(c#>'{source_plan,sources}') THEN RETURN FALSE; END IF;
 FOR mapping IN SELECT m FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m LOOP
  IF (mapping->>'ordinal')::INTEGER<>ordinal OR mapping->'source' IS DISTINCT FROM c#>ARRAY['source_plan','sources',ordinal::TEXT]
   OR mapping->>'role' IS DISTINCT FROM internal.initial_source_role(c#>ARRAY['source_plan','sources',ordinal::TEXT]) THEN RETURN FALSE; END IF;
  ordinal:=ordinal+1;
 END LOOP;
 RETURN TRUE;
END; $$;

CREATE FUNCTION internal.assert_initial_media_profile_values(p_candidate_value JSONB,p_profile_value JSONB) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE plan JSONB; spec JSONB; source JSONB; rule JSONB; role TEXT; counts JSONB:='{}'::JSONB; n INTEGER; source_total BIGINT:=0; output_total BIGINT:=0; cpu_total BIGINT:=0; heap_total BIGINT:=0; wall_total BIGINT:=0;
BEGIN
 plan:=p_candidate_value->'source_plan'; spec:=p_profile_value->'spec';
 IF plan->>'route' IS DISTINCT FROM spec->>'route' OR internal.initial_source_input_profile(plan) IS DISTINCT FROM spec->>'input_profile' OR jsonb_array_length(plan->'sources')>(spec->>'max_sources')::INTEGER THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 FOR source IN SELECT s FROM jsonb_array_elements(plan->'sources') s LOOP
  role:=internal.initial_source_role(source);
  SELECT r INTO rule FROM jsonb_array_elements(spec->'rules') r WHERE r->>'role'=role;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  n:=COALESCE((counts->>role)::INTEGER,0)+1; counts:=jsonb_set(counts,ARRAY[role],to_jsonb(n));
  IF n>(rule->>'max_count')::INTEGER OR NOT (rule->'source_types' ? (source->>'source_content_type')) OR source->>'transform' IS DISTINCT FROM rule->>'transform'
   OR COALESCE(source#>'{transform_parameters,target_sample_rate}','null'::JSONB) IS DISTINCT FROM rule->'target_sample_rate'
   OR COALESCE(source#>'{transform_parameters,preserve_short_video_context}','null'::JSONB) IS DISTINCT FROM rule->'preserve_short_video_context'
   OR (source->>'source_byte_count')::BIGINT>(rule#>>'{limits,source_bytes}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  source_total:=source_total+(source->>'source_byte_count')::BIGINT; output_total:=output_total+(rule#>>'{limits,output_bytes}')::BIGINT;
  cpu_total:=cpu_total+(rule#>>'{limits,cpu_ms}')::BIGINT; heap_total:=heap_total+(rule#>>'{limits,heap_bytes}')::BIGINT; wall_total:=wall_total+(rule#>>'{limits,wall_ms}')::BIGINT;
 END LOOP;
 IF source_total>(spec#>>'{limits,source_bytes}')::BIGINT OR output_total>(spec#>>'{limits,output_bytes}')::BIGINT OR cpu_total>(spec#>>'{limits,cpu_ms}')::BIGINT OR heap_total>(spec#>>'{limits,heap_bytes}')::BIGINT OR wall_total>(spec#>>'{limits,wall_ms}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
END; $$;

REVOKE ALL ON FUNCTION internal.initial_media_assignment_pair_values(TEXT,TEXT,JSONB),internal.assert_initial_media_profile_values(JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.valid_initial_media_assignment_pair(p_candidate TEXT,p_assignment TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE candidate_value JSONB;
BEGIN
 candidate_value:=internal.parse_initial_media_source_candidate(p_candidate);
 RETURN internal.initial_media_assignment_pair_values(p_candidate,p_assignment,candidate_value);
END; $$;

CREATE OR REPLACE FUNCTION internal.assert_initial_media_profile_matches(p_candidate TEXT,p_profile TEXT) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE candidate_value JSONB; profile_value JSONB;
BEGIN
 candidate_value:=internal.parse_initial_media_source_candidate(p_candidate);
 profile_value:=internal.parse_initial_media_profile(p_profile);
 PERFORM internal.assert_initial_media_profile_values(candidate_value,profile_value);
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_qualified_context(p_candidate TEXT,p_assignment TEXT,p_preparation TEXT,p_installation TEXT,p_protocol TEXT,p_destination TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE pair_text TEXT; candidate_value JSONB; a JSONB:=internal.parse_initial_qualified_codec('assignment',p_assignment); profile JSONB:=internal.parse_initial_media_profile(p_preparation); i JSONB:=internal.parse_initial_handoff_catalog('installation',p_installation); d JSONB:=internal.parse_initial_handoff_catalog('destination_backend',p_destination); h JSONB:=internal.parse_initial_handoff_profile(internal.initial_canonical(a#>'{handoff,profile}'),p_protocol);
BEGIN
 pair_text:=internal.initial_canonical(jsonb_set(a-'handoff','{version}','2'));
 candidate_value:=internal.parse_initial_media_source_candidate(p_candidate);
 IF NOT internal.initial_media_assignment_pair_values(p_candidate,pair_text,candidate_value) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_media_profile_values(candidate_value,profile);
 PERFORM internal.assert_initial_handoff_catalog_envelope(p_preparation,internal.initial_canonical(h),p_protocol);
 IF a#>>'{handoff,profile_digest}' IS DISTINCT FROM internal.initial_handoff_digest('profile',internal.initial_canonical(h))
 OR a#>>'{handoff,installation_digest}' IS DISTINCT FROM internal.initial_handoff_catalog_digest('installation',p_installation)
 OR i->>'profile_digest' IS DISTINCT FROM a#>>'{handoff,profile_digest}' OR i->>'profile_generation' IS DISTINCT FROM h->>'generation'
 OR i->>'protocol_artifact_digest' IS DISTINCT FROM h->>'protocol_artifact_digest' OR i->>'copy_adapter_digest' IS DISTINCT FROM h->>'copy_adapter_digest' OR i->>'verification_adapter_digest' IS DISTINCT FROM h->>'verification_adapter_digest'
 OR i->>'preparation_profile_digest' IS DISTINCT FROM internal.initial_media_contract_digest('profile',p_preparation) OR a#>>'{preparation,profile_digest}' IS DISTINCT FROM i->>'preparation_profile_digest'
 OR i->>'source_backend_generation' IS DISTINCT FROM h->>'source_backend_generation' OR a#>>'{preparation,backend_generation}' IS DISTINCT FROM h->>'source_backend_generation'
 OR i->>'destination_backend_generation' IS DISTINCT FROM h->>'destination_backend_generation' OR d->>'generation' IS DISTINCT FROM h->>'destination_backend_generation'
 OR h->>'destination_backend_config_digest' IS DISTINCT FROM internal.initial_handoff_catalog_digest('destination_backend',p_destination) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('assignment',a,'profile',profile,'assignment_digest',internal.initial_preparation_digest('assignment',p_assignment));
END; $$;

RESET statement_timeout;
RESET lock_timeout;

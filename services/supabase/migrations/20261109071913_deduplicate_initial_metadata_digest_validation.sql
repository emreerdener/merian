-- Reuse only original immutable TEXT already parsed in this pure invocation.
-- Keep semantic outcome checks, all public digest parsers and every live
-- receipt/authority/transaction boundary unchanged. No cache or trusted input.
SET lock_timeout='5s';
SET statement_timeout='2min';

CREATE OR REPLACE FUNCTION internal.validate_initial_admission_metadata(p_candidate TEXT,p_assignment TEXT,p_preparation TEXT,p_installation TEXT,p_protocol TEXT,p_destination TEXT,p_expiry NUMERIC,p_outcome TEXT,p_scope TEXT,p_window TEXT,p_mapping TEXT,p_binding TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE scope JSONB:=internal.parse_initial_admission_metadata('scope',p_scope);
 ctx JSONB:=internal.initial_qualified_context(p_candidate,p_assignment,p_preparation,p_installation,p_protocol,p_destination);
 candidate JSONB:=p_candidate::JSONB; a JSONB:=ctx->'assignment'; h JSONB:=a#>'{handoff,profile}';
 outcome JSONB:=internal.parse_initial_qualified_codec('outcome',p_outcome);
 w JSONB:=internal.parse_initial_admission_metadata('phase_window',p_window); m JSONB:=internal.parse_initial_admission_metadata('mapping',p_mapping); b JSONB:=internal.parse_initial_admission_metadata('media_binding',p_binding);
 x JSONB; source JSONB; prepared JSONB; resolved JSONB; item JSONB; role_value JSONB; previous JSONB; objects JSONB; original_ids JSONB; destinations JSONB:='{}'::JSONB; media JSONB:='[]'::JSONB; input_value JSONB;
 n INTEGER; destination_id TEXT; total NUMERIC; ci TEXT; sd TEXT; dd TEXT; od TEXT; wd TEXT; md TEXT;
BEGIN
 PERFORM internal.assert_initial_qualified_outcome((scope->>'scan_id')::UUID,ctx,p_expiry,p_outcome);
 od:=encode(extensions.digest(convert_to('merian.initial-analysis.preparation-execution.outcome.v2'||chr(10)||p_outcome,'UTF8'),'sha256'),'hex');
 FOREACH x IN ARRAY ARRAY[w,m,b] LOOP
  IF x->'owner_id' IS DISTINCT FROM scope->'owner_id' OR x->'scan_id' IS DISTINCT FROM scope->'scan_id' OR x->'admission_receipt_id' IS DISTINCT FROM scope->'admission_receipt_id' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF w->'handoff_profile_digest' IS DISTINCT FROM a#>'{handoff,profile_digest}' OR w->'handoff_installation_digest' IS DISTINCT FROM a#>'{handoff,installation_digest}' OR w->'protocol_artifact_digest' IS DISTINCT FROM h->'protocol_artifact_digest'
 OR (w->>'original_expires_at_ms')::NUMERIC IS DISTINCT FROM p_expiry OR (w->>'anchor_ms')::NUMERIC<(outcome#>>'{grant,issued_at_ms}')::NUMERIC
 OR w->'cutoffs' IS DISTINCT FROM internal.initial_handoff_phase_cutoffs(internal.initial_canonical(h),p_protocol,(w->>'anchor_ms')::NUMERIC,p_expiry) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR source,n IN SELECT v,(i-1)::INTEGER FROM jsonb_array_elements(candidate#>'{source_plan,sources}') WITH ORDINALITY z(v,i) LOOP
  prepared:=outcome#>ARRAY['output_manifest','entries',n::TEXT,'prepared'];
  x:=CASE WHEN prepared='null'::JSONB THEN outcome#>ARRAY['source_verification','entries',n::TEXT,'bytes'] ELSE prepared->'bytes' END;
  media:=media||jsonb_build_array((source-'prepared_output')||jsonb_build_object('content_type',x->'content_type','byte_count',x->'byte_count','sha256',x->'sha256'));
 END LOOP;
 input_value:=internal.parse_initial_input(internal.initial_canonical(((candidate->'source_plan')-'sources')||jsonb_build_object('media',media)));
 ci:=internal.initial_canonical(input_value); sd:=internal.initial_digest('input',ci); dd:=internal.initial_digest('descriptions',internal.initial_canonical(input_value->'ordered_descriptions'));
 IF m->>'assignment_digest' IS DISTINCT FROM ctx->>'assignment_digest' OR m->>'outcome_digest' IS DISTINCT FROM od OR m->'source_backend_generation' IS DISTINCT FROM h->'source_backend_generation' OR m->'destination_backend_generation' IS DISTINCT FROM h->'destination_backend_generation'
 OR jsonb_array_length(m->'items')<>jsonb_array_length(media) OR jsonb_array_length(m->'items')=0 OR jsonb_array_length(m->'items')>(h#>>'{cohort_limits,max_ordinals}')::INTEGER THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT COALESCE(jsonb_agg(v->'object_id'),'[]') INTO original_ids FROM jsonb_array_elements((outcome#>'{source_verification,entries}')||(outcome#>'{resolved_manifest,entries}')||(outcome->'retained')) z(v) WHERE v->'object_id'<>'null'::JSONB;
 FOR item,n IN SELECT v,(i-1)::INTEGER FROM jsonb_array_elements(m->'items') WITH ORDINALITY z(v,i) LOOP
  source:=outcome#>ARRAY['source_verification','entries',n::TEXT]; prepared:=outcome#>ARRAY['output_manifest','entries',n::TEXT,'prepared']; resolved:=outcome#>ARRAY['resolved_manifest','entries',n::TEXT,'object_id'];
  IF (item->>'index')::INTEGER<>n OR item#>'{source,original_object_id}' IS DISTINCT FROM source->'object_id' OR item#>'{source,bytes}' IS DISTINCT FROM source->'bytes' OR (item->'prepared'='null'::JSONB) IS DISTINCT FROM (prepared='null'::JSONB) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF item->'prepared'<>'null'::JSONB AND (item#>'{prepared,original_object_id}' IS DISTINCT FROM resolved OR item#>'{prepared,bytes}' IS DISTINCT FROM prepared->'bytes'
   OR (item#>'{source,destination_object_id}'=item#>'{prepared,destination_object_id}') IS DISTINCT FROM (item#>'{source,bytes}'=item#>'{prepared,bytes}')) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(h#>'{cohort_limits,content_type_pairs}') z(v) WHERE v->'kind'=media#>ARRAY[n::TEXT,'kind'] AND v->'source_content_type'=item#>'{source,bytes,content_type}' AND v->'prepared_content_type'=COALESCE(item#>'{prepared,bytes,content_type}','null'::JSONB)) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  FOREACH role_value IN ARRAY ARRAY[item->'source',item->'prepared'] LOOP
   IF role_value='null'::JSONB THEN CONTINUE; END IF;
   destination_id:=role_value->>'destination_object_id'; previous:=destinations->destination_id;
   IF original_ids ? destination_id OR (previous IS NOT NULL AND ((previous->>'index')::INTEGER<>n OR previous->'bytes' IS DISTINCT FROM role_value->'bytes')) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
   destinations:=destinations||jsonb_build_object(destination_id,jsonb_build_object('index',n,'bytes',role_value->'bytes'));
  END LOOP;
 END LOOP;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('object_id',k,'bytes',v->'bytes') ORDER BY k COLLATE "C"),'[]'),sum((v#>>'{bytes,byte_count}')::NUMERIC) INTO objects,total FROM jsonb_each(destinations) z(k,v);
 IF m->'objects' IS DISTINCT FROM objects OR jsonb_array_length(objects)>10 OR jsonb_array_length(objects)>(h#>>'{cohort_limits,max_unique_objects}')::INTEGER OR total>28625792 OR total>(h#>>'{cohort_limits,max_unique_bytes}')::NUMERIC THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 wd:=encode(extensions.digest(convert_to('merian.initial-analysis.handoff.phase_window.v1'||chr(10)||p_window,'UTF8'),'sha256'),'hex'); md:=encode(extensions.digest(convert_to('merian.initial-analysis.handoff.mapping.v2'||chr(10)||p_mapping,'UTF8'),'sha256'),'hex');
 IF b->>'submission_digest' IS DISTINCT FROM sd OR b->>'assignment_digest' IS DISTINCT FROM ctx->>'assignment_digest' OR b->>'outcome_digest' IS DISTINCT FROM od OR b->>'mapping_digest' IS DISTINCT FROM md OR b->'destination_backend_generation' IS DISTINCT FROM m->'destination_backend_generation' OR b->'phase_window' IS DISTINCT FROM w OR b->>'phase_window_digest' IS DISTINCT FROM wd THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('canonical_input',ci,'submission_digest',sd,'descriptions_digest',dd,'canonical_phase_window',p_window,'phase_window_digest',wd,'canonical_mapping',p_mapping,'mapping_digest',md,'canonical_media_binding',p_binding,'media_binding_digest',encode(extensions.digest(convert_to('merian.initial-analysis.handoff.media_binding.v2'||chr(10)||p_binding,'UTF8'),'sha256'),'hex'));
END; $$;

RESET statement_timeout;
RESET lock_timeout;

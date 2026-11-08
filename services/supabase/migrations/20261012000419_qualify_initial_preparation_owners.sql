SET lock_timeout='5s'; SET statement_timeout='2min';

-- Bound immutable original declarations; eligibility is checked separately under locks.
CREATE FUNCTION internal.initial_saved_qualified_context(p_candidate TEXT,p_assignment TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE a JSONB:=internal.parse_initial_qualified_codec('assignment',p_assignment); i internal.initial_preparation_handoff_installations; h internal.initial_preparation_handoff_profiles; profile TEXT; artifact TEXT; destination JSONB; selection internal.initial_preparation_selections; ctx JSONB;
BEGIN
 SELECT * INTO STRICT selection FROM internal.initial_preparation_selections WHERE generation=(a#>>'{preparation,selector_generation}')::UUID;
 SELECT * INTO STRICT i FROM internal.initial_preparation_handoff_installations WHERE digest=a#>>'{handoff,installation_digest}';
 SELECT * INTO STRICT h FROM internal.initial_preparation_handoff_profiles WHERE digest=i.profile_digest AND generation=i.profile_generation;
 SELECT canonical_profile INTO STRICT profile FROM internal.initial_preparation_profiles WHERE digest=a#>>'{preparation,profile_digest}';
 SELECT canonical_artifact INTO STRICT artifact FROM internal.initial_preparation_handoff_protocol_artifacts WHERE digest=h.protocol_artifact_digest;
 SELECT jsonb_build_object('generation',b.generation,'provider',b.provider,'direct_endpoint',b.direct_endpoint,'private_bucket',b.private_bucket,'namespace',b.namespace,'credential_profile',b.credential_profile) INTO STRICT destination FROM internal.initial_analysis_media_backends b WHERE generation=h.destination_backend_generation;
 IF selection.handoff_installation_digest IS DISTINCT FROM i.digest OR selection.profile_digest IS DISTINCT FROM i.preparation_profile_digest OR selection.backend_generation IS DISTINCT FROM i.source_backend_generation
 OR h.canonical_profile IS DISTINCT FROM internal.initial_canonical(a#>'{handoff,profile}')
 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_backends WHERE generation=i.source_backend_generation AND configuration_digest=h.source_backend_config_digest)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_installations WHERE digest=a#>>'{preparation,installation_digest}' AND target_kind='profile' AND target_digest=i.preparation_profile_digest AND evidence_digest=profile::JSONB#>>'{qualification,evidence_digest}' AND reviewed_revision=profile::JSONB#>>'{qualification,source_revision}')
 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_installations WHERE digest=a#>>'{preparation,backend_installation_digest}' AND target_kind='backend' AND target_digest=h.source_backend_config_digest) THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 ctx:=internal.initial_qualified_context(p_candidate,p_assignment,profile,i.canonical_installation,artifact,internal.initial_canonical(destination));
 PERFORM internal.assert_initial_qualified_cohort(ctx);
 RETURN ctx;
END; $$;

-- Checked actual ordinal multiplicity, with conservative separate audio output.
CREATE FUNCTION internal.assert_initial_qualified_cohort(p_context JSONB) RETURNS VOID LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE a JSONB:=p_context->'assignment'; h JSONB:=a#>'{handoff,profile}'; profile JSONB:=p_context->'profile'; m JSONB; r JSONB; s JSONB; prepared_type TEXT; objects BIGINT:=0; bytes BIGINT:=0; n INTEGER:=0; source_bytes BIGINT; output_bytes BIGINT;
BEGIN
 IF jsonb_array_length(a#>'{preparation,source_mapping}')>(h#>>'{cohort_limits,max_ordinals}')::INTEGER THEN RAISE EXCEPTION 'initial_analysis_handoff_cohort_unsupported' USING ERRCODE='55000'; END IF;
 FOR m IN SELECT * FROM jsonb_array_elements(a#>'{preparation,source_mapping}') LOOP
  s:=m->'source'; SELECT rule INTO STRICT r FROM jsonb_array_elements(profile#>'{spec,rules}') rule WHERE rule->>'role'=m->>'role';
  source_bytes:=(s->>'source_byte_count')::BIGINT;
  output_bytes:=CASE WHEN s->>'kind'='video' THEN 0 WHEN s->>'kind'='image' THEN source_bytes ELSE (r#>>'{limits,output_bytes}')::BIGINT END;
  prepared_type:=CASE WHEN s->>'kind'='video' THEN NULL WHEN s->>'kind'='audio' THEN 'audio/wav' ELSE s->>'source_content_type' END;
  IF (m->>'ordinal')::INTEGER<>n OR output_bytes>(r#>>'{limits,output_bytes}')::BIGINT OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(h#>'{cohort_limits,content_type_pairs}') pair WHERE pair->>'kind'=s->>'kind' AND pair->>'source_content_type'=s->>'source_content_type' AND pair->>'prepared_content_type' IS NOT DISTINCT FROM prepared_type) THEN RAISE EXCEPTION 'initial_analysis_handoff_cohort_unsupported' USING ERRCODE='55000'; END IF;
  objects:=objects+CASE WHEN s->>'kind'='audio' THEN 2 ELSE 1 END;
  bytes:=bytes+source_bytes+CASE WHEN s->>'kind'='audio' THEN output_bytes ELSE 0 END;
  n:=n+1;
 END LOOP;
 IF objects>(h#>>'{cohort_limits,max_unique_objects}')::BIGINT OR bytes>(h#>>'{cohort_limits,max_unique_bytes}')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_handoff_cohort_unsupported' USING ERRCODE='55000'; END IF;
END; $$;

CREATE FUNCTION internal.valid_initial_saved_media_assignment_pair(p_candidate TEXT,p_assignment TEXT) RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF p_assignment::JSONB->>'version'='3' THEN PERFORM internal.initial_saved_qualified_context(p_candidate,p_assignment); RETURN TRUE; END IF;
 RETURN internal.valid_initial_media_assignment_pair(p_candidate,p_assignment);
EXCEPTION WHEN invalid_parameter_value OR invalid_text_representation OR no_data_found OR too_many_rows OR object_not_in_prerequisite_state THEN RETURN FALSE;
END; $$;

CREATE OR REPLACE FUNCTION internal.valid_initial_preparation_pair(p_candidate text, p_assignment text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE c JSONB; a JSONB;
BEGIN
 IF p_candidate IS NULL OR octet_length(p_candidate)>1048576 OR p_assignment IS NULL OR octet_length(p_assignment)>65536 THEN RETURN FALSE; END IF;
 BEGIN c:=p_candidate::JSONB; a:=p_assignment::JSONB; EXCEPTION WHEN OTHERS THEN RETURN FALSE; END;
 IF c->>'variant'='media_sources' THEN RETURN internal.valid_initial_saved_media_assignment_pair(p_candidate,p_assignment); END IF;
 PERFORM internal.parse_initial_preparation_candidate(p_candidate);
 RETURN internal.initial_canonical(a)=p_assignment AND internal.initial_schema_matches(a,internal.initial_assignment_schema_v2()) AND a->>'candidate_digest'=internal.initial_preparation_digest('preparation-candidate',p_candidate);
END; $function$;

CREATE OR REPLACE FUNCTION internal.initial_preparation_sources_complete(p_scan uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; item JSONB; count_sources INTEGER;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'media_sources' THEN RETURN FALSE; END IF;
 IF NOT internal.valid_initial_saved_media_assignment_pair(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB; count_sources:=jsonb_array_length(a#>'{preparation,source_mapping}');
 IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan AND state='allocated' AND execution_state='unissued')
  OR (SELECT count(*) FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)<>count_sources
  OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan)<>count_sources THEN RETURN FALSE; END IF;
 FOR item IN SELECT m FROM jsonb_array_elements(a#>'{preparation,source_mapping}') m LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping m JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
   WHERE m.scan_id=p_scan AND m.ordinal=(item->>'ordinal')::INTEGER AND m.object_id=(item->>'object_id')::UUID
    AND r.backend_generation=(a#>>'{preparation,backend_generation}')::UUID AND NOT r.retired AND NOT r.marker_confirmed AND r.claim_token IS NULL) THEN RETURN FALSE; END IF;
 END LOOP;
 RETURN TRUE;
END; $function$;

CREATE OR REPLACE FUNCTION internal.initial_preparation_execution_coherent(p_scan uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; fence internal.initial_preparation_source_fences; a JSONB; source_proof TEXT; grant_value TEXT; output internal.initial_preparation_output_manifests; outcome TEXT; item JSONB; n INTEGER; ids UUID[];
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 SELECT * INTO fence FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan;
 IF saved.scan_id IS NULL OR fence.scan_id IS NULL OR fence.state<>'allocated' OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'media_sources' OR NOT internal.valid_initial_saved_media_assignment_pair(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB;
 SELECT canonical_receipt INTO source_proof FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT canonical_grant INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT * INTO output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_outcome INTO outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
 IF (fence.execution_state='issued') IS DISTINCT FROM (grant_value IS NOT NULL) OR (source_proof IS NULL AND grant_value IS NOT NULL) OR (grant_value IS NULL AND output.scan_id IS NOT NULL) OR (output.scan_id IS NULL AND outcome IS NOT NULL)
  OR (fence.provider_barrier IS NULL AND (source_proof IS NOT NULL OR grant_value IS NOT NULL OR output.scan_id IS NOT NULL OR outcome IS NOT NULL)) THEN RETURN FALSE; END IF;
 IF source_proof IS NOT NULL THEN PERFORM internal.validate_initial_execution_source(p_scan,source_proof); END IF;
 IF grant_value IS NOT NULL THEN PERFORM internal.validate_initial_execution_grant(p_scan,grant_value); END IF;
 IF output.scan_id IS NOT NULL THEN
  PERFORM internal.validate_initial_execution_output(p_scan,output.canonical_request);
  PERFORM internal.validate_initial_execution_resolved(p_scan,output.canonical_resolved);
 END IF;
 IF outcome IS NOT NULL THEN PERFORM internal.validate_initial_execution_outcome(p_scan,outcome); END IF;
 IF (SELECT count(*) FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)<>jsonb_array_length(a#>'{preparation,source_mapping}') THEN RETURN FALSE; END IF;
 FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(a#>'{preparation,source_mapping}') WITH ORDINALITY v(e,i) LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n AND object_id=(item->>'object_id')::UUID) THEN RETURN FALSE; END IF;
 END LOOP;
 IF (SELECT count(*) FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan)<>(SELECT count(*) FROM jsonb_array_elements(COALESCE(output.canonical_resolved::JSONB->'entries','[]'::JSONB)) e WHERE e->'object_id'<>'null'::JSONB) THEN RETURN FALSE; END IF;
 FOR item IN SELECT e FROM jsonb_array_elements(COALESCE(output.canonical_resolved::JSONB->'entries','[]'::JSONB)) e WHERE e->'object_id'<>'null'::JSONB LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan AND ordinal=(item->>'ordinal')::INTEGER AND object_id=(item->>'object_id')::UUID) THEN RETURN FALSE; END IF;
 END LOOP;
 SELECT array_agg(object_id ORDER BY object_id) INTO ids FROM (SELECT object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan UNION SELECT object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan) v;
 IF (SELECT array_agg(object_id ORDER BY object_id) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan) IS DISTINCT FROM ids
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan AND (backend_generation<>(a#>>'{preparation,backend_generation}')::UUID OR retired OR marker_confirmed OR claim_token IS NOT NULL)) THEN RETURN FALSE; END IF;
 RETURN TRUE;
EXCEPTION WHEN check_violation OR invalid_parameter_value OR no_data_found OR too_many_rows THEN RETURN FALSE;
END; $function$;

CREATE OR REPLACE FUNCTION internal.lock_initial_preparation_eligibility(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE a JSONB; pe internal.initial_preparation_profile_eligibility; be internal.initial_preparation_backend_eligibility;
BEGIN
 SELECT canonical_assignment::JSONB INTO STRICT a FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 PERFORM singleton FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO pe FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=a#>>'{preparation,profile_digest}' FOR SHARE NOWAIT;
 SELECT * INTO be FROM internal.initial_preparation_backend_eligibility WHERE generation=(a#>>'{preparation,backend_generation}')::UUID FOR SHARE NOWAIT;
 IF pe.state IS DISTINCT FROM 'eligible' OR be.state IS DISTINCT FROM 'eligible' OR pe.installation_digest IS DISTINCT FROM a#>>'{preparation,installation_digest}' OR be.installation_digest IS DISTINCT FROM a#>>'{preparation,backend_installation_digest}' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF a->>'version'='3' THEN
  PERFORM installation_digest FROM internal.initial_preparation_handoff_eligibility WHERE installation_digest=a#>>'{handoff,installation_digest}' AND state='eligible' FOR SHARE NOWAIT;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_qualification_unavailable' USING ERRCODE='55000'; END IF;
 END IF;
END; $function$;

CREATE OR REPLACE FUNCTION internal.resolve_initial_media_preparation_assignment(p_owner uuid, p_scan uuid, p_candidate text, p_plan text, p_fallback boolean, p_objects jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE input JSONB; profile TEXT; policy internal.ai_quota_policies;
 binding internal.identification_provider_bindings; rollout internal.initial_analysis_rollout;
 accepted_protocol INTEGER; accepted_capability INTEGER; assignment JSONB; manifest JSONB; selection internal.initial_preparation_selections; profile_row internal.initial_preparation_profiles; profile_eligible internal.initial_preparation_profile_eligibility; backend_eligible internal.initial_preparation_backend_eligibility; installed internal.initial_preparation_installations; selected_generation UUID; mapping JSONB; handoff internal.initial_preparation_handoff_profiles;
BEGIN
 input:=internal.parse_initial_media_source_candidate(p_candidate)->'source_plan';
 profile:=internal.initial_source_input_profile(input);
 SELECT * INTO rollout FROM internal.initial_analysis_rollout WHERE singleton FOR SHARE NOWAIT;
 IF rollout.initial_analysis_lifecycle_enabled IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 SELECT a.manifest INTO manifest FROM internal.initial_analysis_configuration_assets a WHERE a.digest=rollout.configuration_assets_digest;
 IF manifest IS NULL OR manifest->>'retention_owner' IS DISTINCT FROM 'initial_engine_release_archive'
  OR manifest->>'resolver_id' IS DISTINCT FROM 'git_blob_sha256_v1'
  OR manifest->'schema_version' IS DISTINCT FROM '1'::JSONB
  OR COALESCE(manifest->>'repository_revision','') !~ '^[0-9a-f]{40}$'
  OR jsonb_typeof(manifest->'roots') IS DISTINCT FROM 'array'
  OR jsonb_typeof(manifest->'files') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 IF jsonb_array_length(manifest->'roots')=0 OR jsonb_array_length(manifest->'files')=0
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'roots') root
   WHERE jsonb_typeof(root)<>'string' OR length(root#>>'{}')=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(manifest->'files') file
   WHERE jsonb_typeof(file)<>'object' OR COALESCE(file->>'path','')=''
    OR COALESCE(file->>'sha256','') !~ '^[0-9a-f]{64}$') THEN
  RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM operation FROM internal.ai_quota_policies WHERE operation='scan_identification' AND effective_plan=p_plan FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_quota_policy_missing' USING ERRCODE='P0001'; END IF;
 SELECT * INTO policy FROM internal.resolve_quota_policy('scan_identification',p_plan);
 PERFORM operation FROM internal.identification_provider_bindings WHERE operation='scan_identification' AND effective_plan=p_plan
  AND model=policy.model AND policy_version=policy.policy_version AND input_profile=profile FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE='P0001'; END IF;
 SELECT * INTO binding FROM internal.resolve_identification_provider_binding('scan_identification',p_plan,policy.model,policy.policy_version,profile);
 accepted_protocol:=internal.require_identification_client_protocol(p_owner,'scan_identification',p_scan,profile,
  (input#>>'{admission,client_protocol}')::INTEGER,FALSE,binding.minimum_client_protocol);
 accepted_capability:=internal.require_identification_capability(p_owner,'scan_identification',p_scan,profile,
  (input#>>'{admission,identification_protocol}')::INTEGER,FALSE,binding.minimum_identification_protocol);
 IF input#>>'{admission,expected_processor_permission}' IS DISTINCT FROM binding.processor_permission THEN
  RAISE EXCEPTION 'ai_identification_preflight_changed' USING ERRCODE='P0001'; END IF;
 PERFORM config_key FROM internal.ai_consent_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_configuration_unavailable' USING ERRCODE='55000'; END IF;
 -- Existing rows protect UPDATE/DELETE; immediate owner FKs serialize new rows
 -- and owner reassignment against the outer users UPDATE lock.
 PERFORM id FROM public.user_adult_eligibility_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_terms_acceptance_receipts WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM id FROM public.user_ai_consent_events WHERE user_id=p_owner ORDER BY id FOR SHARE NOWAIT;
 PERFORM internal.require_identification_processor_consent(p_owner,binding.processor_permission);
 PERFORM input_profile FROM internal.initial_preparation_current_selection WHERE input_profile=profile FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT generation INTO selected_generation FROM internal.initial_preparation_current_selection WHERE input_profile=profile;
 SELECT * INTO selection FROM internal.initial_preparation_selections WHERE generation=selected_generation;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO profile_eligible FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=selection.profile_digest FOR SHARE NOWAIT;
 IF NOT FOUND OR profile_eligible.state<>'eligible' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO backend_eligible FROM internal.initial_preparation_backend_eligibility WHERE generation=selection.backend_generation FOR SHARE NOWAIT;
 IF NOT FOUND OR backend_eligible.state<>'eligible' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO profile_row FROM internal.initial_preparation_profiles WHERE digest=selection.profile_digest;
 SELECT * INTO installed FROM internal.initial_preparation_installations WHERE digest=profile_eligible.installation_digest;
 IF installed.evidence_digest IS DISTINCT FROM profile_row.canonical_profile::JSONB#>>'{qualification,evidence_digest}'
  OR installed.reviewed_revision IS DISTINCT FROM profile_row.canonical_profile::JSONB#>>'{qualification,source_revision}' THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF selection.handoff_installation_digest IS NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_qualification_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM installation_digest FROM internal.initial_preparation_handoff_eligibility WHERE installation_digest=selection.handoff_installation_digest AND state='eligible' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_handoff_qualification_unavailable' USING ERRCODE='55000'; END IF;
 SELECT h.* INTO STRICT handoff FROM internal.initial_preparation_handoff_profiles h JOIN internal.initial_preparation_handoff_installations i ON i.profile_digest=h.digest AND i.profile_generation=h.generation WHERE i.digest=selection.handoff_installation_digest;
 PERFORM internal.assert_initial_media_profile_matches(p_candidate,profile_row.canonical_profile);
 IF jsonb_typeof(p_objects) IS DISTINCT FROM 'array' OR jsonb_array_length(p_objects)<>jsonb_array_length(input->'sources') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_object('ordinal',n-1,'source',source,'role',internal.initial_source_role(source),'object_id',p_objects->(n::INTEGER-1),'prepared_destination',NULL) ORDER BY n) INTO mapping FROM jsonb_array_elements(input->'sources') WITH ORDINALITY s(source,n);
 assignment:=jsonb_build_object('version',3,'handoff',jsonb_build_object('profile',handoff.canonical_profile::JSONB,'profile_digest',handoff.digest,'installation_digest',selection.handoff_installation_digest),'candidate_digest',internal.initial_preparation_digest('preparation-candidate',p_candidate),
  'route',input->>'route','operation','scan_identification','effective_plan',p_plan,
  'effective_tier',CASE WHEN p_plan='free' THEN 'free' ELSE 'pro' END,'flash_fallback_used',p_fallback,
  'quota_model',policy.model,'policy_version',policy.policy_version,'provider',binding.provider,'binding',binding.binding,
  'processor_permission',binding.processor_permission,'input_profile',profile,'provider_model',binding.provider_model,
  'effective_model',COALESCE(binding.provider_model,policy.model),'minimum_client_protocol',binding.minimum_client_protocol,
  'accepted_client_protocol',accepted_protocol,'minimum_identification_protocol',binding.minimum_identification_protocol,
  'accepted_identification_protocol',accepted_capability,'asset_manifest_digest',rollout.configuration_assets_digest,
  'retention_owner','initial_engine_release_archive','resolver_id','git_blob_sha256_v1',
  'variant','media_sources','source_plan_digest',internal.initial_media_contract_digest('source_plan',internal.initial_canonical(input)),
  'preparation',jsonb_build_object('kind','media_sources','profile_digest',selection.profile_digest,'installation_digest',profile_eligible.installation_digest,'selector_generation',selection.generation,'backend_generation',selection.backend_generation,'backend_installation_digest',backend_eligible.installation_digest,'source_mapping',mapping),'experiment',NULL);
 PERFORM internal.initial_saved_qualified_context(p_candidate,internal.initial_canonical(assignment));
 RETURN internal.initial_canonical(assignment);
END;
$function$;

-- Allocation responses have a separate version namespace from execution replies.
CREATE FUNCTION internal.checked_initial_media_preparation_response(p_value JSONB)
 RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE kind TEXT:=CASE WHEN p_value->>'outcome' IN ('allocated','blocked') THEN 'allocated' ELSE p_value->>'outcome' END; shape JSONB;
BEGIN
 IF kind NOT IN ('allocated','expired') OR kind IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_value->>'version'='3' THEN RETURN internal.parse_initial_qualified_codec(kind,internal.initial_canonical(p_value)); END IF;
 shape:=internal.initial_media_response_schema()->kind;
 IF octet_length(internal.initial_canonical(p_value))>524288 OR NOT internal.initial_schema_matches(p_value,shape) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN p_value;
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_media_preparation_response(p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; available BOOLEAN;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR NOT internal.initial_preparation_execution_coherent(p_scan) THEN RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 a:=saved.canonical_assignment::JSONB;
 available:=EXISTS(SELECT 1 FROM internal.initial_preparation_profile_eligibility WHERE profile_digest=a#>>'{preparation,profile_digest}' AND installation_digest=a#>>'{preparation,installation_digest}' AND state='eligible')
 AND EXISTS(SELECT 1 FROM internal.initial_preparation_backend_eligibility WHERE generation=(a#>>'{preparation,backend_generation}')::UUID AND installation_digest=a#>>'{preparation,backend_installation_digest}' AND state='eligible');
 IF a->>'version'='3' THEN available:=available AND EXISTS(SELECT 1 FROM internal.initial_preparation_handoff_eligibility WHERE installation_digest=a#>>'{handoff,installation_digest}' AND state='eligible'); END IF;
 RETURN internal.checked_initial_media_preparation_response(jsonb_build_object('version',(a->>'version')::INTEGER,'variant','media_sources','outcome',CASE WHEN available THEN 'allocated' ELSE 'blocked' END,'authority','none','candidate_digest',saved.candidate_digest,'assignment_digest',saved.assignment_digest,'assignment',a,'expires_at',saved.expires_at));
END; $function$;

CREATE OR REPLACE FUNCTION internal.create_initial_media_preparation(p_owner uuid, p_scan uuid, p_candidate text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE candidate JSONB; saved internal.initial_analysis_preparation_intents; origin TIMESTAMPTZ; projected RECORD; objects JSONB; assignment TEXT; item JSONB;
BEGIN
 candidate:=internal.parse_initial_media_source_candidate(p_candidate);
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_candidate IS DISTINCT FROM p_candidate THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  IF clock_timestamp()>=saved.expires_at THEN PERFORM internal.cancel_initial_analysis(p_owner,p_scan); RETURN internal.checked_initial_media_preparation_response(jsonb_build_object('version',(saved.canonical_assignment::JSONB->>'version')::INTEGER,'variant','media_sources','outcome','expired','authority','none')); END IF;
  RETURN internal.initial_media_preparation_response(p_scan);
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan) OR p_scan::TEXT ~ '^ac0[ab]0001-[0-9a-f]{4}-8' THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 PERFORM config_key FROM internal.entitlement_rollout_config WHERE config_key='current' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE='P0001'; END IF;
 origin:=clock_timestamp();
 SELECT * INTO projected FROM internal.resolve_fresh_quota_entitlement(p_owner,'scan_identification',p_scan,FALSE,origin);
 SELECT jsonb_agg(gen_random_uuid() ORDER BY n) INTO objects FROM generate_series(1,jsonb_array_length(candidate#>'{source_plan,sources}')) n;
 assignment:=internal.resolve_initial_media_preparation_assignment(p_owner,p_scan,p_candidate,projected.effective_plan,projected.flash_fallback_used,objects);
 IF clock_timestamp()>=origin+INTERVAL '300 seconds' THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.initial_preparation_source_fences(scan_id,state,provider_barrier) VALUES(p_scan,'allocated','blocked_pre_admission');
 INSERT INTO internal.initial_analysis_operation_fences(scan_id) VALUES(p_scan);
 INSERT INTO internal.initial_analysis_preparation_intents(scan_id,owner_id,canonical_candidate,candidate_digest,canonical_assignment,assignment_digest,created_at,expires_at)
 VALUES(p_scan,p_owner,p_candidate,internal.initial_preparation_digest('preparation-candidate',p_candidate),assignment,internal.initial_preparation_digest('assignment',assignment),origin,origin+INTERVAL '300 seconds');

 -- The deterministic object order is shared with all retirement paths.
 FOR item IN SELECT m FROM jsonb_array_elements(assignment::JSONB#>'{preparation,source_mapping}') m ORDER BY (m->>'object_id')::UUID LOOP
  INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) VALUES((item->>'object_id')::UUID,p_scan,(assignment::JSONB#>>'{preparation,backend_generation}')::UUID);
  INSERT INTO internal.initial_preparation_source_mapping(scan_id,ordinal,object_id) VALUES(p_scan,(item->>'ordinal')::INTEGER,(item->>'object_id')::UUID);
 END LOOP;
 RETURN internal.initial_media_preparation_response(p_scan);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_initial_preparation_status(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; recovered JSONB;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 recovered:=internal.recover_initial_preparation_admission(p_owner,p_scan);
 IF recovered IS NOT NULL THEN RETURN recovered; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF clock_timestamp()>=saved.expires_at THEN
  PERFORM internal.cancel_initial_analysis(p_owner,p_scan);

  IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.checked_initial_media_preparation_response(jsonb_build_object('version',(saved.canonical_assignment::JSONB->>'version')::INTEGER,'variant','media_sources','outcome','expired','authority','none')); END IF;
  RETURN jsonb_build_object('version',2,'outcome','expired');
 END IF;

 IF saved.canonical_candidate::JSONB->>'variant'='media_sources' THEN RETURN internal.initial_media_preparation_response(p_scan); END IF;
 RETURN jsonb_build_object('version',2,'outcome','prepared','candidate_digest',saved.candidate_digest,
  'assignment_digest',saved.assignment_digest,'expires_at',saved.expires_at);
END;
$function$;

CREATE OR REPLACE FUNCTION internal.validate_initial_execution_grant(p_scan uuid, p_text text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; profile JSONB; source_digest TEXT; wall BIGINT; issue BIGINT;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF saved.canonical_assignment::JSONB->>'version'='3' THEN
  SELECT digest INTO STRICT source_digest FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
  PERFORM internal.assert_initial_qualified_grant(p_scan,internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment),source_digest,floor(extract(epoch FROM saved.expires_at)*1000),p_text);
  RETURN;
 END IF;
 value:=internal.parse_initial_preparation_execution('grant',p_text);
 PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
 SELECT digest INTO STRICT source_digest FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 wall:=internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile); issue:=(value->>'issued_at_ms')::BIGINT;
 IF value->>'source_digest' IS DISTINCT FROM source_digest OR value->>'profile_digest' IS DISTINCT FROM saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}' OR value->>'artifact_digest' IS DISTINCT FROM profile#>>'{spec,artifact,sha256}'
  OR (value->>'execution_deadline_ms')::BIGINT<>issue+5000+wall OR (value->>'registration_deadline_ms')::BIGINT<>issue+10000+wall OR (value->>'outcome_deadline_ms')::BIGINT<>issue+45000+wall
  OR issue<floor(extract(epoch FROM saved.created_at)*1000)::BIGINT OR issue+80000+wall>floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $function$;

CREATE OR REPLACE FUNCTION internal.validate_initial_execution_outcome(p_scan uuid, p_text text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; value JSONB; grant_value JSONB; source_value JSONB; output internal.initial_preparation_output_manifests; profile JSONB; retained JSONB;
BEGIN
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF saved.canonical_assignment::JSONB->>'version'='3' THEN
  PERFORM internal.assert_initial_qualified_outcome(p_scan,internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment),floor(extract(epoch FROM saved.expires_at)*1000),p_text);
  value:=p_text::JSONB;
 ELSE
  value:=internal.parse_initial_preparation_execution('outcome',p_text);
  PERFORM internal.assert_initial_execution_identity(p_scan,saved.assignment_digest,value);
 END IF;
 SELECT canonical_grant::JSONB INTO STRICT grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT canonical_receipt::JSONB INTO STRICT source_value FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT * INTO STRICT output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
 SELECT COALESCE(jsonb_agg(jsonb_build_object('ordinal',e->'ordinal','object_id',output.canonical_resolved::JSONB#>ARRAY['entries',(i-1)::TEXT,'object_id'],'bytes',e#>'{prepared,bytes}') ORDER BY i),'[]'::JSONB) INTO retained FROM jsonb_array_elements(output.canonical_request::JSONB->'entries') WITH ORDINALITY v(e,i) WHERE e->'prepared'<>'null'::JSONB;
 IF value->'grant' IS DISTINCT FROM grant_value OR value->'source_verification' IS DISTINCT FROM source_value OR value->'output_manifest' IS DISTINCT FROM output.canonical_request::JSONB OR value->'resolved_manifest' IS DISTINCT FROM output.canonical_resolved::JSONB OR value->'profile' IS DISTINCT FROM profile OR value->'retained' IS DISTINCT FROM retained THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
END; $function$;

CREATE FUNCTION internal.initial_saved_execution_outcome_digest(p_scan UUID,p_text TEXT) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE version TEXT;
BEGIN
 SELECT canonical_assignment::JSONB->>'version' INTO STRICT version FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF version='3' THEN RETURN internal.initial_qualified_outcome_digest(p_text); END IF;
 PERFORM internal.parse_initial_preparation_execution('outcome',p_text);
 RETURN internal.initial_preparation_execution_digest('outcome',p_text);
END; $$;

CREATE OR REPLACE FUNCTION internal.guard_initial_preparation_execution_private()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; grant_value JSONB; now_ms BIGINT; issue_ms BIGINT; ctx JSONB;
BEGIN
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id AND state='retired') THEN RETURN OLD; END IF;
 ELSIF TG_OP='INSERT' THEN
  SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
  PERFORM internal.lock_initial_preparation_scope(saved.owner_id,NEW.scan_id);
  PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND state='allocated' AND provider_barrier='blocked_pre_admission') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
  now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
  SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=NEW.scan_id;
  IF TG_TABLE_NAME IN ('initial_preparation_source_verifications','initial_preparation_execution_grants') THEN
   PERFORM internal.lock_initial_preparation_eligibility(NEW.scan_id);
   IF saved.canonical_assignment::JSONB->>'version'='3' THEN ctx:=internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment); END IF;
   now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
   IF now_ms>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
   IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='unissued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME='initial_preparation_source_verifications' THEN PERFORM internal.validate_initial_execution_source(NEW.scan_id,NEW.canonical_receipt);
   ELSE
    IF ctx IS NULL THEN RAISE EXCEPTION 'initial_analysis_handoff_qualification_unavailable' USING ERRCODE='55000'; END IF;
    IF now_ms+45000+internal.initial_preparation_cohort_wall(ctx->'assignment',ctx->'profile')+(ctx#>>'{assignment,handoff,profile,total_ms}')::BIGINT>=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    PERFORM internal.validate_initial_execution_grant(NEW.scan_id,NEW.canonical_grant);
    issue_ms:=(NEW.canonical_grant::JSONB->>'issued_at_ms')::BIGINT;
    IF issue_ms>now_ms OR issue_ms<now_ms-5000 THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
   END IF;
  ELSE
   IF grant_value IS NULL OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=NEW.scan_id AND execution_state='issued') THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
   IF TG_TABLE_NAME IN ('initial_preparation_output_manifests','initial_preparation_output_mapping') THEN
    IF now_ms>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    IF TG_TABLE_NAME='initial_preparation_output_manifests' THEN PERFORM internal.validate_initial_execution_output(NEW.scan_id,NEW.canonical_request); END IF;
   ELSE
    IF now_ms>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
    PERFORM internal.validate_initial_execution_outcome(NEW.scan_id,NEW.canonical_outcome);
   END IF;
  END IF;
  RETURN NEW;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $function$;

CREATE FUNCTION internal.parse_initial_saved_execution_record(p_kind TEXT,p_text TEXT) RETURNS JSONB LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('grant','outcome') THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_text::JSONB->>'version'='2' THEN RETURN internal.parse_initial_qualified_codec(p_kind,p_text); END IF;
 RETURN internal.parse_initial_preparation_execution(p_kind,p_text);
END; $$;

DO $checks$ DECLARE r RECORD; found_count INTEGER:=0;
BEGIN
 FOR r IN SELECT c.conname,c.conrelid::REGCLASS tbl FROM pg_constraint c WHERE c.contype='c' AND c.conrelid IN ('internal.initial_preparation_execution_grants'::REGCLASS,'internal.initial_preparation_outcomes'::REGCLASS) AND (pg_get_constraintdef(c.oid) LIKE '%parse_initial_preparation_execution%' OR pg_get_constraintdef(c.oid) LIKE '%initial_preparation_execution_digest%') LOOP
  EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',r.tbl,r.conname); found_count:=found_count+1;
 END LOOP;
 IF found_count<>3 THEN RAISE EXCEPTION 'qualified_execution_constraint_catalog_changed'; END IF;
END; $checks$;

ALTER TABLE internal.initial_preparation_execution_grants ADD CONSTRAINT initial_execution_grant_closed_version CHECK(internal.parse_initial_saved_execution_record('grant',canonical_grant) IS NOT NULL);

ALTER TABLE internal.initial_preparation_outcomes ADD CONSTRAINT initial_execution_outcome_closed_version CHECK(internal.parse_initial_saved_execution_record('outcome',canonical_outcome) IS NOT NULL), ADD CONSTRAINT initial_execution_outcome_version_digest CHECK(digest=CASE WHEN canonical_outcome::JSONB->>'version'='2' THEN internal.initial_qualified_outcome_digest(canonical_outcome) ELSE internal.initial_preparation_execution_digest('outcome',canonical_outcome) END);

CREATE FUNCTION internal.initial_preparation_held_reply(p_version INTEGER,p_reason TEXT) RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $$ SELECT jsonb_build_object('version',p_version,'outcome','held','reason',p_reason)||CASE WHEN p_version=2 THEN jsonb_build_object('authority','none') ELSE '{}'::JSONB END $$;

CREATE OR REPLACE FUNCTION internal.initial_preparation_execution_action(p_action text, p_owner uuid, p_scan uuid, p_assignment_digest text, p_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
DECLARE saved internal.initial_analysis_preparation_intents; fence internal.initial_preparation_source_fences; source_proof internal.initial_preparation_source_verifications; grant_value JSONB; output internal.initial_preparation_output_manifests; outcome TEXT; value JSONB; digest TEXT; now_ms BIGINT; expiry_ms BIGINT; wall BIGINT; profile JSONB; resolved JSONB; entries JSONB:='[]'::JSONB; item JSONB; prepared JSONB; object UUID; identity UUID; backend UUID; n INTEGER; reply_version INTEGER; ctx JSONB; handoff JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_action IS NULL OR p_action NOT IN ('sources','issue','output','outcome','status') OR p_owner IS NULL OR p_scan IS NULL OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN RETURN internal.initial_preparation_held_reply(1,'missing'); END IF;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 reply_version:=CASE WHEN saved.canonical_assignment::JSONB->>'version'='3' THEN 2 ELSE 1 END;
 now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT; expiry_ms:=floor(extract(epoch FROM saved.expires_at)*1000)::BIGINT;
 IF now_ms>=expiry_ms THEN PERFORM internal.cancel_initial_analysis(p_owner,p_scan); RETURN internal.initial_preparation_held_reply(reply_version,'expired'); END IF;
 SELECT * INTO fence FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan;
 IF NOT internal.initial_preparation_execution_coherent(p_scan) THEN RETURN internal.initial_preparation_held_reply(reply_version,'incoherent'); END IF;
 SELECT * INTO source_proof FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan;
 SELECT canonical_grant::JSONB INTO grant_value FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan;
 SELECT * INTO output FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan;
 SELECT canonical_outcome INTO outcome FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan;
 IF p_action='status' THEN
  RETURN jsonb_build_object('version',reply_version,'outcome','status','phase',CASE WHEN outcome IS NOT NULL THEN 'outcome_ready' WHEN output.scan_id IS NOT NULL THEN 'output_registered' WHEN grant_value IS NOT NULL THEN 'issued' WHEN source_proof.scan_id IS NOT NULL THEN 'verified' ELSE 'allocated' END,
   'source',source_proof.canonical_receipt::JSONB,'execution_reference',CASE WHEN grant_value IS NOT NULL THEN jsonb_build_object('grant_id',grant_value->'grant_id','source_digest',grant_value->'source_digest') END,'output',CASE WHEN output.scan_id IS NOT NULL THEN jsonb_build_object('request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB) END,'result',outcome::JSONB,'server_now_ms',now_ms,'expires_at_ms',expiry_ms);
 END IF;
 IF fence.provider_barrier IS DISTINCT FROM 'blocked_pre_admission' OR NOT internal.can_cancel_initial_preparation(p_owner,p_scan) THEN RETURN internal.initial_preparation_held_reply(reply_version,'incoherent'); END IF;
 IF p_action='sources' THEN
  PERFORM internal.validate_initial_execution_source(p_scan,p_text);
  IF source_proof.scan_id IS NOT NULL THEN
   IF source_proof.canonical_receipt IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   PERFORM internal.lock_initial_preparation_eligibility(p_scan);
   IF fence.execution_state<>'unissued' THEN RETURN internal.initial_preparation_held_reply(reply_version,'preparation_issued'); END IF;
   INSERT INTO internal.initial_preparation_source_verifications(scan_id,canonical_receipt,digest) VALUES(p_scan,p_text,internal.initial_preparation_execution_digest('source_verification',p_text));
  END IF;
  RETURN jsonb_build_object('version',reply_version,'outcome','verified','receipt',p_text::JSONB,'digest',internal.initial_preparation_execution_digest('source_verification',p_text));
 ELSIF p_action='issue' THEN
  IF fence.execution_state='issued' THEN RETURN internal.initial_preparation_held_reply(reply_version,'preparation_issued'); END IF;
  IF source_proof.scan_id IS NULL OR source_proof.digest IS DISTINCT FROM p_text THEN RETURN internal.initial_preparation_held_reply(reply_version,'missing'); END IF;
  IF reply_version=1 THEN RETURN internal.initial_preparation_held_reply(2,'handoff_qualification_unavailable'); END IF;
  PERFORM internal.lock_initial_preparation_eligibility(p_scan);
  ctx:=internal.initial_saved_qualified_context(saved.canonical_candidate,saved.canonical_assignment); handoff:=ctx#>'{assignment,handoff,profile}';
  SELECT canonical_profile::JSONB INTO STRICT profile FROM internal.initial_preparation_profiles profile_row WHERE profile_row.digest=saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}';
  wall:=internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile); now_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  IF now_ms+45000+wall+(handoff->>'total_ms')::BIGINT>=expiry_ms THEN RETURN internal.initial_preparation_held_reply(reply_version,'budget'); END IF;
  grant_value:=jsonb_build_object('version',2,'handoff_profile_digest',saved.canonical_assignment::JSONB#>>'{handoff,profile_digest}','handoff_installation_digest',saved.canonical_assignment::JSONB#>>'{handoff,installation_digest}','protocol_artifact_digest',handoff->>'protocol_artifact_digest','handoff_total_ms',handoff->'total_ms','preparation_wall_ms',wall,'preparation_expires_at_ms',expiry_ms,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',gen_random_uuid(),'source_digest',source_proof.digest,'profile_digest',saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}','artifact_digest',profile#>>'{spec,artifact,sha256}',
   'issued_at_ms',now_ms,'execution_deadline_ms',now_ms+5000+wall,'registration_deadline_ms',now_ms+10000+wall,'outcome_deadline_ms',now_ms+45000+wall);
  INSERT INTO internal.initial_preparation_execution_grants(scan_id,canonical_grant) VALUES(p_scan,internal.initial_canonical(grant_value));
  UPDATE internal.initial_preparation_source_fences SET execution_state='issued' WHERE scan_id=p_scan;
  RETURN jsonb_build_object('version',reply_version,'outcome','granted','grant',grant_value,'server_now_ms',floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT,'expires_at_ms',expiry_ms);
 ELSIF p_action='output' THEN
  PERFORM internal.validate_initial_execution_output(p_scan,p_text);
  IF output.scan_id IS NOT NULL THEN
   IF output.canonical_request IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('version',reply_version,'outcome','registered','request',output.canonical_request::JSONB,'resolved',output.canonical_resolved::JSONB);
  END IF;
  IF grant_value IS NULL OR floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'registration_deadline_ms')::BIGINT THEN RETURN internal.initial_preparation_held_reply(reply_version,'phase_expired'); END IF;
  value:=p_text::JSONB; digest:=internal.initial_preparation_execution_digest('output_manifest',p_text);
  FOR item,n IN SELECT e,i::INTEGER-1 FROM jsonb_array_elements(value->'entries') WITH ORDINALITY v(e,i) LOOP
   prepared:=item->'prepared'; object:=NULL;
   IF prepared<>'null'::JSONB THEN
    IF (prepared->>'source_identity')::BOOLEAN THEN SELECT object_id INTO STRICT object FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan AND ordinal=n; ELSE object:=gen_random_uuid(); END IF;
   END IF;
   entries:=entries||jsonb_build_array(jsonb_build_object('ordinal',n,'object_id',object));
  END LOOP;
  resolved:=jsonb_build_object('version',1,'scan_id',p_scan,'assignment_digest',p_assignment_digest,'grant_id',grant_value->'grant_id','request_digest',digest,'entries',entries);
  INSERT INTO internal.initial_preparation_output_manifests(scan_id,canonical_request,request_digest,canonical_resolved) VALUES(p_scan,p_text,digest,internal.initial_canonical(resolved));
  backend:=(saved.canonical_assignment::JSONB#>>'{preparation,backend_generation}')::UUID;
  FOR identity IN SELECT id FROM (SELECT object_id id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan UNION SELECT (e->>'object_id')::UUID FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL) v ORDER BY id LOOP
   PERFORM object_id FROM internal.initial_preparation_source_registry WHERE object_id=identity FOR UPDATE;
   IF NOT FOUND THEN INSERT INTO internal.initial_preparation_source_registry(object_id,scan_id,backend_generation) VALUES(identity,p_scan,backend);
   ELSIF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE object_id=identity AND scan_id=p_scan AND backend_generation=backend AND NOT retired) THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  END LOOP;
  FOR item IN SELECT e FROM jsonb_array_elements(entries) e WHERE e->>'object_id' IS NOT NULL ORDER BY (e->>'object_id')::UUID LOOP
   INSERT INTO internal.initial_preparation_output_mapping(scan_id,ordinal,object_id) VALUES(p_scan,(item->>'ordinal')::INTEGER,(item->>'object_id')::UUID);
  END LOOP;
  RETURN jsonb_build_object('version',reply_version,'outcome','registered','request',value,'resolved',resolved);
 ELSE
  PERFORM internal.validate_initial_execution_outcome(p_scan,p_text);
  IF outcome IS NOT NULL THEN
   IF outcome IS DISTINCT FROM p_text THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  ELSE
   IF floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT>=(grant_value->>'outcome_deadline_ms')::BIGINT THEN RETURN internal.initial_preparation_held_reply(reply_version,'phase_expired'); END IF;
   INSERT INTO internal.initial_preparation_outcomes(scan_id,canonical_outcome,digest) VALUES(p_scan,p_text,internal.initial_saved_execution_outcome_digest(p_scan,p_text));
  END IF;
  RETURN jsonb_build_object('version',reply_version,'outcome','outcome_ready','result',p_text::JSONB,'digest',internal.initial_saved_execution_outcome_digest(p_scan,p_text));
 END IF;
END; $function$;

CREATE OR REPLACE FUNCTION internal.checked_initial_preparation_reply(p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE shape JSONB; phase INTEGER;
BEGIN
 IF p_value->>'version'='2' THEN RETURN internal.parse_initial_qualified_codec('reply_'||(p_value->>'outcome'),internal.initial_canonical(p_value)); END IF;
 shape:=internal.initial_preparation_execution_schema()->('reply_'||(p_value->>'outcome'));
 IF shape IS NULL OR octet_length(internal.initial_canonical(p_value))>524288 OR NOT internal.initial_schema_matches(p_value,shape) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF p_value->>'outcome'='status' THEN
  phase:=array_position(ARRAY['allocated','verified','issued','output_registered','outcome_ready'],p_value->>'phase');
  IF (p_value->'source'<>'null'::JSONB)<>(phase>=2) OR (p_value->'execution_reference'<>'null'::JSONB)<>(phase>=3) OR (p_value->'output'<>'null'::JSONB)<>(phase>=4) OR (p_value->'result'<>'null'::JSONB)<>(phase>=5) THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 RETURN p_value;
END; $function$;

REVOKE ALL ON FUNCTION internal.checked_initial_media_preparation_response(JSONB),internal.initial_saved_qualified_context(TEXT,TEXT),internal.assert_initial_qualified_cohort(JSONB),internal.valid_initial_saved_media_assignment_pair(TEXT,TEXT),internal.initial_saved_execution_outcome_digest(UUID,TEXT),internal.parse_initial_saved_execution_record(TEXT,TEXT),internal.initial_preparation_held_reply(INTEGER,TEXT) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout; RESET statement_timeout;

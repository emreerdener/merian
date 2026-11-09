-- Repair the exact routine warnings found by candidate validation run 509.
-- No grants, interfaces, validation calls, or lifecycle operations are widened.
-- JSON construction/coercion dependencies require STABLE; cancellation capture
-- that obtains current transaction/lifecycle state requires VOLATILE.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION internal.validate_initial_admitted_proof(
 p_candidate TEXT,p_input TEXT,p_configuration TEXT,p_funding TEXT,p_outcome TEXT,
 p_installation TEXT,p_protocol TEXT,p_destination TEXT,p_mapping TEXT,
 p_media_binding TEXT,p_accounting TEXT,p_manifest TEXT
) RETURNS TEXT LANGUAGE PLPGSQL STABLE SET search_path='' AS $$
DECLARE
 kinds TEXT[]:=ARRAY['candidate','input','configuration','funding','outcome','installation','protocol','destination','mapping','media_binding','accounting','manifest'];
 texts TEXT[]:=ARRAY[p_candidate,p_input,p_configuration,p_funding,p_outcome,p_installation,p_protocol,p_destination,p_mapping,p_media_binding,p_accounting,p_manifest];
 docs JSONB[]:=ARRAY[]::JSONB[]; total BIGINT:=0; k TEXT; domain_name TEXT; ref JSONB;
 candidate JSONB; input_value JSONB; configuration JSONB; funding JSONB; outcome JSONB;
 binding JSONB; accounting JSONB; manifest JSONB; a JSONB; metadata JSONB;
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
 PERFORM internal.assert_initial_admitted_accounting(a,input_value->'admission',funding,accounting,manifest);
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-receipt.v1'||chr(10)||p_manifest,'UTF8'),'sha256'),'hex');
END; $$;

ALTER FUNCTION internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,jsonb) VOLATILE;

CREATE OR REPLACE FUNCTION internal.capture_initial_cancellation_private_images(p_scan UUID)
RETURNS JSONB LANGUAGE plpgsql SET search_path='' AS $$
DECLARE member RECORD; estimated BIGINT:=2; members INTEGER:=0; images JSONB; result JSONB:='{}'::JSONB;
BEGIN
 FOR member IN SELECT * FROM internal.measure_initial_cancellation_private_images(p_scan) LOOP
  estimated:=estimated+octet_length(to_jsonb(member.relation_name)::TEXT)+2+member.array_bytes
   +CASE WHEN members>0 THEN 2 ELSE 0 END;
  members:=members+1;
  IF estimated>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
 FOR member IN SELECT * FROM internal.initial_cancellation_private_catalog() LOOP
  EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY (to_jsonb(t)->>''ordinal'')::INTEGER, (to_jsonb(t)->>''photo_ordinal'')::INTEGER, (to_jsonb(t)->>''role'') COLLATE "C"),''[]''::JSONB) FROM %s t WHERE scan_id=$1',member.relation_name)
   INTO images USING p_scan;
  result:=result||jsonb_build_object(member.relation_name,images);
 END LOOP;
 IF octet_length(result::TEXT) IS DISTINCT FROM estimated THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_cpm_photo_text_units(p_encoded TEXT) RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $body$
DECLARE bytes BYTEA; size INTEGER; pos INTEGER:=0; first INTEGER; second INTEGER;
 width INTEGER; scalars INTEGER:=0; units INTEGER:=0;
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

ALTER FUNCTION internal.assert_initial_cpm_photo_recipe(JSONB) STABLE;

ALTER FUNCTION internal.parse_initial_cpm_photo_content(TEXT) STABLE;

ALTER FUNCTION internal.parse_initial_cpm_photo_candidate(TEXT) STABLE;

ALTER FUNCTION internal.initial_cpm_photo_digest(TEXT,TEXT) STABLE;

ALTER FUNCTION internal.parse_initial_cpm_photo_assignment(TEXT,TEXT) STABLE;

CREATE OR REPLACE FUNCTION internal.parse_initial_cpm_photo_recovery(p_candidate TEXT,p_response TEXT,p_saved_assignment TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SET search_path = '' AS $body$
DECLARE candidate JSONB; content JSONB; value JSONB;
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
 PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,value->>'assignment_canonical');
 IF value->>'assignment_digest'<>internal.initial_cpm_photo_digest('assignment',value->>'assignment_canonical')
  OR (p_saved_assignment IS NOT NULL AND value->>'assignment_canonical'<>p_saved_assignment) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN value;
END; $body$;

CREATE OR REPLACE FUNCTION internal.assert_initial_cpm_verification_start(
 p_old internal.initial_analysis_preparation_intents,p_new internal.initial_analysis_preparation_intents
) RETURNS VOID LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE snapshot TEXT; a JSONB:=p_old.canonical_assignment::JSONB; now_at TIMESTAMPTZ:=clock_timestamp();
BEGIN
 PERFORM internal.require_service_role();
 -- Consume the protected exact context before any nested work. A forged GUC,
 -- copied attempt or matching digest cannot substitute for this private row.
 DELETE FROM internal.initial_cpm_verification_start_context
 WHERE transaction_id=pg_catalog.pg_current_xact_id() AND owner_id=p_old.owner_id
  AND scan_id=p_old.scan_id AND attempt_id=p_new.cpm_verification_attempt_id
  AND old_digest=internal.initial_cpm_verification_intent_digest(p_old)
  AND new_digest=internal.initial_cpm_verification_intent_digest(p_new)
;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 IF num_nonnulls(p_old.cpm_verification_attempt_id,p_old.cpm_verification_started_at,p_old.cpm_verification_snapshot_digest)<>0
  OR num_nonnulls(p_new.cpm_verification_attempt_id,p_new.cpm_verification_started_at,p_new.cpm_verification_snapshot_digest)<>3
  OR to_jsonb(p_new)-ARRAY['cpm_verification_attempt_id','cpm_verification_started_at','cpm_verification_snapshot_digest']
   IS DISTINCT FROM to_jsonb(p_old)-ARRAY['cpm_verification_attempt_id','cpm_verification_started_at','cpm_verification_snapshot_digest']
  OR p_new.cpm_verification_started_at>now_at OR p_new.cpm_verification_started_at<now_at-INTERVAL '5 seconds'
  OR now_at>=p_old.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
 snapshot:=internal.initial_cpm_verification_start_snapshot(p_old.owner_id,p_old.scan_id);
 PERFORM internal.assert_initial_preparation_unfunded(p_old.owner_id,p_old.scan_id);
 PERFORM singleton FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM profile_digest FROM internal.initial_cpm_photo_profile_eligibility
  WHERE profile_digest=a#>>'{preparation,profile_digest}' AND state='eligible'
   AND installation_digest=a#>>'{preparation,installation_digest}' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM generation FROM internal.initial_preparation_backend_eligibility
  WHERE generation=(a#>>'{preparation,backend_generation}')::UUID AND state='eligible'
   AND installation_digest=a#>>'{preparation,backend_installation_digest}' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM p.digest FROM internal.initial_cpm_photo_write_policies p
  JOIN internal.initial_cpm_photo_write_attempts w ON w.write_policy_digest=p.digest
  WHERE w.scan_id=p_old.scan_id ORDER BY p.digest FOR SHARE OF p NOWAIT;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts w
  JOIN internal.initial_cpm_photo_write_policies p ON p.digest=w.write_policy_digest
  WHERE w.scan_id=p_old.scan_id AND p.state<>'eligible') THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF p_new.cpm_verification_snapshot_digest IS DISTINCT FROM encode(extensions.digest(convert_to(
  'merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
END; $$;

ALTER FUNCTION internal.initial_cpm_admission_submission(TEXT,TEXT) STABLE;

ALTER FUNCTION internal.parse_initial_cpm_admitted_document(TEXT,TEXT) STABLE;

CREATE OR REPLACE FUNCTION internal.build_initial_cpm_admitted_manifest(
 p_receipt internal.initial_preparation_admission_receipts,p_authorized_at_ms BIGINT
) RETURNS TEXT LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts:=p_receipt;
 candidate JSONB; configuration JSONB; a JSONB; projection JSONB; funding JSONB; accounting JSONB;
 snapshot JSONB; verification JSONB; m JSONB; role JSONB; w JSONB; c JSONB; expected JSONB;
 objects JSONB:='[]'::JSONB; attempt_ids TEXT[]:=ARRAY[]::TEXT[]; attempt_id TEXT; k TEXT;
 created TIMESTAMPTZ; issued TIMESTAMPTZ; closed TIMESTAMPTZ; capability TIMESTAMPTZ;
 assignment_digest TEXT; snapshot_digest TEXT; capacity_text TEXT; manifest TEXT;
 retained BIGINT:=0; member_index INTEGER; proof JSONB:='{}'::JSONB; metadata JSONB:='{}'::JSONB;
 kinds TEXT[]:=ARRAY['candidate','input','configuration','funding','accounting','verification','retained_roles','capacity_predecessor'];
 texts TEXT[]; domains TEXT[]:=ARRAY['cpm-photo-candidate.v1','cpm-photo-content.v1','configuration.v1','funding.v1',
  'handoff.accounting.v1','cpm-photo-verification.v1','cpm-verification-start.v1','cpm-photo-capacity.v1'];
 reference JSONB; total BIGINT:=0;
BEGIN
 IF r.scan_id IS NULL OR r.owner_id IS NULL OR r.admission_receipt_id IS NULL
  OR r.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
  OR NOT internal.initial_admission_variant_fields_valid(r.admission_variant,
   ARRAY[r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding],
   r.cpm_verification,r.cpm_verification_digest,r.cpm_retained_roles,r.cpm_capacity_predecessor,r.original_admission_expires_at) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 candidate:=internal.parse_initial_cpm_photo_candidate(r.candidate);
 configuration:=internal.parse_initial_admitted_component('configuration',r.configuration);
 IF configuration IS DISTINCT FROM jsonb_build_object('version',3,'assignment',configuration->'assignment') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 a:=internal.parse_initial_cpm_photo_assignment(r.candidate,internal.initial_canonical(configuration->'assignment'));
 projection:=internal.initial_cpm_admission_submission(r.candidate,internal.initial_canonical(a));
 assignment_digest:=internal.initial_cpm_photo_digest('assignment',internal.initial_canonical(a));
 IF a->>'scan_id' IS DISTINCT FROM r.scan_id::TEXT OR r.input IS DISTINCT FROM projection->>'submission_canonical'
  OR p_authorized_at_ms IS NULL OR p_authorized_at_ms<(a->>'created_at_ms')::BIGINT
  OR p_authorized_at_ms>=(a->>'expires_at_ms')::BIGINT
  OR extract(epoch FROM r.original_admission_expires_at)*1000 IS DISTINCT FROM (a->>'expires_at_ms')::NUMERIC THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 funding:=internal.parse_initial_admitted_component('funding',r.funding);
 accounting:=internal.parse_initial_admitted_component('accounting',r.accounting);
 snapshot:=internal.parse_initial_cpm_admitted_document('snapshot',r.cpm_retained_roles);
 verification:=internal.parse_initial_cpm_admitted_document('verification',r.cpm_verification);
 IF jsonb_typeof(snapshot->'members') IS DISTINCT FROM 'array'
  OR jsonb_array_length(snapshot->'members') IS DISTINCT FROM jsonb_array_length(a#>'{preparation,role_mapping}')
  OR jsonb_typeof(snapshot->'backend_configuration_digest') IS DISTINCT FROM 'string'
  OR (snapshot->>'backend_configuration_digest' ~ '^[0-9a-f]{64}$') IS NOT TRUE
  OR jsonb_typeof(verification->'attempt_id') IS DISTINCT FROM 'string'
  OR (verification->>'attempt_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') IS NOT TRUE THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 FOR m,member_index IN SELECT value,(ordinal-1)::INTEGER FROM jsonb_array_elements(snapshot->'members') WITH ORDINALITY t(value,ordinal) LOOP
  role:=a#>ARRAY['preparation','role_mapping',member_index::TEXT]; w:=m->'attempt'; c:=m->'closure';
  attempt_id:=w->>'attempt_id';
  IF jsonb_typeof(w->'attempt_id') IS DISTINCT FROM 'string'
   OR (attempt_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') IS NOT TRUE
   OR attempt_id=ANY(attempt_ids) OR jsonb_typeof(w->'write_policy_digest') IS DISTINCT FROM 'string'
   OR (w->>'write_policy_digest' ~ '^[0-9a-f]{64}$') IS NOT TRUE THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  attempt_ids:=array_append(attempt_ids,attempt_id);
  FOREACH k IN ARRAY ARRAY['created_at','admission_expires_at','capability_expires_at','issued_at'] LOOP
   IF internal.valid_initial_admitted_timestamp(w->>k) IS NOT TRUE OR jsonb_typeof(w->k) IS DISTINCT FROM 'string' THEN
    RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF internal.valid_initial_admitted_timestamp(c->>'observed_at') IS NOT TRUE OR jsonb_typeof(c->'observed_at') IS DISTINCT FROM 'string' THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  created:=(w->>'created_at')::TIMESTAMPTZ; issued:=(w->>'issued_at')::TIMESTAMPTZ;
  closed:=(c->>'observed_at')::TIMESTAMPTZ; capability:=(w->>'capability_expires_at')::TIMESTAMPTZ;
  IF extract(epoch FROM created)*1000<(a->>'created_at_ms')::NUMERIC
   OR mod(extract(epoch FROM created)*1000,1)<>0
   OR (w->>'admission_expires_at')::TIMESTAMPTZ IS DISTINCT FROM r.original_admission_expires_at
   OR capability IS DISTINCT FROM LEAST(created+INTERVAL '10 minutes',r.original_admission_expires_at)
   OR issued<created OR issued>=capability OR closed<issued
   OR floor(extract(epoch FROM closed)*1000)>p_authorized_at_ms THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  expected:=jsonb_build_object('attempt_id',attempt_id,'scan_id',r.scan_id,'object_id',role->'object_id',
   'assignment_digest',assignment_digest,'backend_generation',a#>'{preparation,backend_generation}',
   'backend_configuration_digest',snapshot->'backend_configuration_digest',
   'created_at',w->'created_at','admission_expires_at',w->'admission_expires_at',
   'capability_expires_at',w->'capability_expires_at','state','may_have_issued','issued_at',w->'issued_at',
   'retired',FALSE,'write_policy_digest',w->'write_policy_digest','write_closed',TRUE);
  IF w IS DISTINCT FROM expected OR c IS DISTINCT FROM jsonb_build_object('attempt_id',attempt_id,
   'outcome','live_object','policy_digest',w->'write_policy_digest','observed_at',c->'observed_at','claim_digest',NULL)
   OR m IS DISTINCT FROM jsonb_build_object('role',role,'attempt',w,'closure',c) THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  retained:=retained+(role#>>'{declaration,byte_count}')::BIGINT;
  objects:=objects||jsonb_build_array(jsonb_build_object('object_id',role->'object_id','photo_ordinal',role->'photo_ordinal',
   'role',role->'role','byte_count',role#>'{declaration,byte_count}','sha256',role#>'{declaration,sha256}',
   'content_type',role#>'{declaration,declared_content_type}','structural_acceptance',TRUE));
 END LOOP;
 expected:=jsonb_build_object('version',1,'owner_id',r.owner_id,'scan_id',r.scan_id,
  'candidate_digest',a->'candidate_digest','content_digest',a->'content_digest','assignment_digest',assignment_digest,
  'profile_digest',a#>'{preparation,profile_digest}','verifier_build_digest',a#>'{preparation,verifier_build_digest}',
  'backend_generation',a#>'{preparation,backend_generation}','backend_configuration_digest',snapshot->'backend_configuration_digest',
  'original_expires_at_ms',a->'expires_at_ms','members',snapshot->'members');
 IF snapshot IS DISTINCT FROM expected OR r.cpm_capacity_predecessor IS DISTINCT FROM jsonb_build_object(
  'scan_id',r.scan_id,'owner_id',r.owner_id,'declared_retained_bytes',retained,'state','pending','write_capability_state','may_have_issued') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 snapshot_digest:=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||E'\n'||r.cpm_retained_roles,'UTF8'),'sha256'),'hex');
 expected:=jsonb_build_object('version',1,'protocol','cpm_photo_full_bytes_v1','attempt_id',verification->'attempt_id',
  'snapshot_digest',snapshot_digest,'profile_digest',a#>'{preparation,profile_digest}',
  'verifier_build_digest',a#>'{preparation,verifier_build_digest}','objects',objects);
 IF verification IS DISTINCT FROM expected OR r.cpm_verification_digest IS DISTINCT FROM encode(extensions.digest(convert_to(
  'merian.initial-analysis.cpm-photo-verification.v1'||E'\n'||r.cpm_verification,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 capacity_text:=internal.initial_canonical(r.cpm_capacity_predecessor);
 texts:=ARRAY[r.candidate,r.input,r.configuration,r.funding,r.accounting,r.cpm_verification,r.cpm_retained_roles,capacity_text];
 FOR n IN 1..8 LOOP
  total:=total+octet_length(texts[n]);
  reference:=jsonb_build_object('byte_count',octet_length(texts[n]),'digest',encode(extensions.digest(convert_to(
   'merian.initial-analysis.'||domains[n]||E'\n'||texts[n],'UTF8'),'sha256'),'hex'));
  IF n>6 THEN metadata:=metadata||jsonb_build_object(kinds[n],reference);
  ELSE proof:=proof||jsonb_build_object(kinds[n],reference); END IF;
 END LOOP;
 expected:=jsonb_build_object('version',2,'owner_id',r.owner_id,'scan_id',r.scan_id,'admission_receipt_id',r.admission_receipt_id,
  'route',a#>'{configuration,route}','input_schema_version',2,'binding_version',4,
  'funding_binding_id',funding#>'{original,reservation_id}','authorized_at_ms',p_authorized_at_ms,
  'original_expires_at_ms',a->'expires_at_ms','metadata',metadata,'proof',proof,
  'metadata_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-admitted-metadata.v1'||E'\n'||internal.initial_canonical(metadata),'UTF8'),'sha256'),'hex'),
  'proof_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-admitted-proof.v1'||E'\n'||internal.initial_canonical(proof),'UTF8'),'sha256'),'hex'),
  'assignment_digest',assignment_digest,'descriptions_digest',projection->'descriptions_digest','assets_digest',a#>'{configuration,asset_manifest_digest}');
 PERFORM internal.assert_initial_admitted_accounting(a->'configuration',candidate->'admission',funding,accounting,expected);
 manifest:=internal.initial_canonical(expected);
 IF octet_length(manifest)>8192 OR total+octet_length(manifest)>2469915 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN manifest;
END; $$;

ALTER FUNCTION internal.initial_cpm_admission_bridge_response(internal.initial_analysis_preparation_intents,internal.initial_preparation_admission_receipts) STABLE;

ALTER FUNCTION internal.initial_cpm_cancellation_retained_row(TEXT,JSONB,BOOLEAN) STABLE;

ALTER FUNCTION internal.initial_result_node_matches_v1(JSONB,JSONB,INTEGER) STABLE;

ALTER FUNCTION internal.initial_result_primary_matches_v1(JSONB) STABLE;

ALTER FUNCTION internal.initial_consuming_row_image(TEXT,JSONB) STABLE;

ALTER FUNCTION internal.initial_report_expected_writes(JSONB,JSONB) STABLE;

CREATE OR REPLACE FUNCTION internal.assert_initial_consuming_expectations(p_operation TEXT,p_writes JSONB)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE catalog JSONB:=internal.initial_consuming_statement_catalog(p_operation); group_value JSONB;
 entry JSONB; image JSONB; projected JSONB; spec JSONB; side TEXT; row_count INTEGER;
BEGIN
 IF p_writes IS NULL OR jsonb_typeof(p_writes)<>'array' OR octet_length(p_writes::TEXT)>8388608
   OR jsonb_array_length(p_writes)<>jsonb_array_length(catalog) THEN
  RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
 FOR idx IN 0..jsonb_array_length(catalog)-1 LOOP
  spec:=catalog->idx; group_value:=p_writes->idx;
  IF jsonb_typeof(group_value)<>'array' THEN
   RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
  row_count:=jsonb_array_length(group_value);
  IF row_count>256 OR (p_operation='report' AND row_count<>1) OR (spec->>'rows'='one' AND row_count<>1)
    OR (spec->>'rows'='zero_or_one' AND row_count>1)
    OR (SELECT count(DISTINCT v) FROM jsonb_array_elements(group_value) v)<>row_count THEN
   RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
  FOR entry IN SELECT * FROM jsonb_array_elements(group_value) LOOP
   IF jsonb_typeof(entry)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(entry) k)
      IS DISTINCT FROM ARRAY['new','old']::TEXT[] THEN
    RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
   IF (spec->>'action'='INSERT' AND (entry->'old'<>'null'::JSONB OR jsonb_typeof(entry->'new')<>'object'))
     OR (spec->>'action'='DELETE' AND (entry->'new'<>'null'::JSONB OR jsonb_typeof(entry->'old')<>'object'))
     OR (spec->>'action'='UPDATE' AND (jsonb_typeof(entry->'old')<>'object' OR jsonb_typeof(entry->'new')<>'object')) THEN
    RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
   FOREACH side IN ARRAY ARRAY['old','new'] LOOP
    image:=entry->side;
    IF image='null'::JSONB THEN CONTINUE; END IF;
    IF spec->>'relation'='internal.ai_quota_reservations' THEN
     IF image ? 'lease_token' OR NOT image ? 'lease_sha256'
       OR (image->'lease_sha256'<>'null'::JSONB AND (jsonb_typeof(image->'lease_sha256')<>'string'
           OR image->>'lease_sha256' !~ '^[0-9a-f]{64}$')) THEN
      RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
     projected:=internal.initial_consuming_row_image(spec->>'relation',(image-'lease_sha256')||'{"lease_token":null}'::JSONB);
     IF projected-'lease_sha256' IS DISTINCT FROM image-'lease_sha256' THEN
      RAISE EXCEPTION 'initial_analysis_consuming_expectations_invalid' USING ERRCODE='22023'; END IF;
    ELSE
     PERFORM internal.initial_consuming_row_image(spec->>'relation',image);
    END IF;
   END LOOP;
  END LOOP;
 END LOOP;
END;
$body$;

CREATE OR REPLACE FUNCTION internal.capture_initial_accounted_cancellation_prestate(p_owner uuid, p_scan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE admitted internal.initial_analysis_admissions;
    receipt internal.initial_preparation_admission_receipts;
    quota internal.ai_quota_reservations;
    attempt internal.identification_provider_attempts;
    charge internal.ai_quota_reservation_counters;
    counter_row internal.ai_quota_counters;
    usage_row internal.complimentary_scan_usage;
    invocation internal.identification_invocations;
    event_row public.ai_usage_events;
    event_id UUID; invocation_count INTEGER:=0; member RECORD; member_count BIGINT;
    member_bytes BIGINT; total_bytes BIGINT:=2; private_images JSONB;
    image_sizes JSONB:='{}'::JSONB; field_sizes JSONB; components JSONB:='{}'::JSONB;
    component_bytes BIGINT:=2; private_bytes BIGINT:=2; member_number INTEGER:=0; field_name TEXT; field_bytes TEXT;
    charges JSONB:='[]'::JSONB; source_rows JSONB; destination_rows JSONB;
    source_fence JSONB; media_fence JSONB; media_cohort JSONB; owner_epoch JSONB; cpm_prestate JSONB;
BEGIN
    PERFORM internal.require_service_role();
    -- This capture is a private prerequisite, not cancellation authority. The
    -- composer remains held until the statement witness and terminal chain land.
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
    IF internal.initial_admission_sealed() OR internal.initial_cancellation_sealed()
        OR EXISTS(SELECT 1 FROM pg_catalog.pg_locks l WHERE l.locktype='advisory'
            AND l.pid=pg_catalog.pg_backend_pid() AND l.classid=1396920143::OID
            AND l.objid::BIGINT=(pg_catalog.hashtext(pg_catalog.pg_current_xact_id()::TEXT)::BIGINT & 4294967295)
            AND l.objsubid=2 AND l.granted)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging WHERE transaction_id=pg_catalog.pg_current_xact_id())
        OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR admitted.owner_id IS DISTINCT FROM p_owner OR (admitted.binding_version IS NULL OR admitted.binding_version IS NULL OR admitted.binding_version NOT IN (3,4))
        OR internal.initial_admission_sealed()
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    IF NOT FOUND OR receipt.owner_id IS DISTINCT FROM p_owner THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
    SELECT * INTO quota FROM internal.ai_quota_reservations WHERE id=admitted.funding_binding_id FOR UPDATE;
    IF NOT FOUND OR quota.user_id IS DISTINCT FROM p_owner OR quota.request_id IS DISTINCT FROM p_scan
        OR quota.original_analysis_id IS DISTINCT FROM p_scan THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts
        WHERE reservation_id=quota.id AND attempt_count=1 FOR UPDATE;
    IF NOT FOUND OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=quota.id)<>1
        OR (SELECT count(*) FROM internal.ai_quota_reservation_counters WHERE reservation_id=quota.id)>3 THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
    -- Match release_ai_quota_reservation_counters' daily -> user -> IP order.
    -- The reservation lock precedes link/counter locks and usage follows them.
    FOR charge IN SELECT * FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=quota.id
        ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
            l.scope_key,l.bucket,l.window_start FOR UPDATE LOOP
        SELECT * INTO counter_row FROM internal.ai_quota_counters c
            WHERE c.scope_type=charge.scope_type AND c.scope_key=charge.scope_key
                AND c.bucket=charge.bucket AND c.window_start=charge.window_start FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
        END IF;
        charges:=charges||jsonb_build_array(jsonb_build_object('link',to_jsonb(charge),'counter',to_jsonb(counter_row),'release_delta',0));
    END LOOP;
    SELECT * INTO usage_row FROM internal.complimentary_scan_usage
        WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
    SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
        'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) INTO owner_epoch
        FROM public.users u WHERE u.id=p_owner;
    -- Lock every scan/reservation match in ID order, including ordinary or
    -- aliased rows; none may be hidden by filtering on initial classification.
    FOR invocation IN SELECT * FROM internal.identification_invocations
        WHERE scan_id=p_scan OR reservation_id=quota.id ORDER BY id FOR UPDATE LOOP
        invocation_count:=invocation_count+1;
        IF invocation_count<>1 OR NOT invocation.is_initial_analysis
            OR invocation.user_id IS DISTINCT FROM p_owner OR invocation.scan_id IS DISTINCT FROM p_scan
            OR invocation.reservation_id IS DISTINCT FROM quota.id OR invocation.attempt_count IS DISTINCT FROM 1
            OR invocation.initial_admission_receipt_id IS DISTINCT FROM receipt.admission_receipt_id
            OR invocation.lease_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(
                receipt.accounting::JSONB#>>'{reservation,lease_token}','UTF8'),'sha256'),'hex')
            OR invocation.provider IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,provider}'
            OR invocation.binding IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,binding}'
            OR invocation.input_profile IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,input_profile}'
            OR invocation.effective_plan IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,effective_plan}'
            OR invocation.policy_version::TEXT IS DISTINCT FROM receipt.accounting::JSONB#>>'{attempt,policy_version}'
            OR invocation.model IS DISTINCT FROM COALESCE(receipt.accounting::JSONB#>>'{attempt,provider_model}',
                receipt.accounting::JSONB#>>'{attempt,model}') THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    IF invocation_count<>1 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- The existing producer is the sole renderer. It may return early for an
    -- existing event, so independently validate the locked association below.
    event_id:=internal.complete_identification_usage(invocation.id,'unknown_execution','{}'::JSONB);
    SELECT * INTO STRICT invocation FROM internal.identification_invocations WHERE id=invocation.id FOR UPDATE;
    SELECT * INTO event_row FROM public.ai_usage_events WHERE id=event_id FOR UPDATE;
    IF NOT FOUND OR invocation.event_id IS DISTINCT FROM event_row.id
        OR NOT internal.identification_usage_matches_invocation(invocation,event_row)
        OR octet_length(to_jsonb(invocation)::TEXT)*2+octet_length(to_jsonb(event_row)::TEXT)>261120 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    -- No quota, counter or complimentary mutation occurs on this branch. The
    -- original lease is checked above; current lease/deadline is not authority.
    IF admitted.binding_version=4 THEN
        PERFORM internal.lock_initial_cpm_photo_capacity();
        PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
    END IF;
    -- All preparation source and prepared-output objects share this registry.
    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan ORDER BY photo_ordinal,role COLLATE "C" FOR UPDATE;
    IF admitted.binding_version=4 THEN
        PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
        PERFORM c.attempt_id FROM internal.initial_cpm_photo_write_closures c
            JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id)
            WHERE w.scan_id=p_scan ORDER BY c.attempt_id FOR UPDATE OF c;
    END IF;
    PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan FOR UPDATE;
    -- Transfer is locked before M1; new private rows join exact C1 images.
    PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_copy_progress WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    -- Known execution uses retained integrity, never the live unused proof.
    IF admitted.binding_version=3 THEN
        PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    ELSIF receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1' THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    PERFORM scan_id FROM internal.initial_analysis_results WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_completions WHERE scan_id=p_scan FOR UPDATE;
    IF EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;
    -- Size each occurrence before constructing any private/registry/CPM array.
    -- Locks above hold membership stable; only small numeric measurements accumulate.
    FOR member IN SELECT * FROM internal.measure_initial_cancellation_private_images(p_scan) LOOP
        image_sizes:=image_sizes||jsonb_build_object(member.relation_name,
            jsonb_build_object('count',member.row_count,'rows',member.row_bytes,'array',member.array_bytes));
        private_bytes:=private_bytes+octet_length(to_jsonb(member.relation_name)::TEXT)+2+member.array_bytes
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
        IF private_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    member_number:=0;
    FOR member IN SELECT * FROM internal.initial_accounted_cancellation_components() LOOP
        IF NOT image_sizes ? member.relation_name
            OR (NOT member.is_array AND (image_sizes#>>ARRAY[member.relation_name,'count'])::BIGINT>1) THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        member_bytes:=CASE WHEN member.is_array THEN (image_sizes#>>ARRAY[member.relation_name,'array'])::BIGINT
            WHEN (image_sizes#>>ARRAY[member.relation_name,'count'])::BIGINT=0 THEN 4
            ELSE (image_sizes#>>ARRAY[member.relation_name,'rows'])::BIGINT END;
        component_bytes:=component_bytes+octet_length(to_jsonb(member.component)::TEXT)+2+member_bytes
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
    END LOOP;
    field_sizes:=jsonb_build_object(
        'version',COALESCE(octet_length((to_jsonb(1))::TEXT),4),
        'authority',COALESCE(octet_length((to_jsonb('none'::TEXT))::TEXT),4),
        'transaction_id',COALESCE(octet_length((to_jsonb(pg_catalog.pg_current_xact_id()::TEXT))::TEXT),4),
        'variant',COALESCE(octet_length((to_jsonb('accounted_invocation'::TEXT))::TEXT),4),
        'invocation',COALESCE(octet_length((to_jsonb(invocation))::TEXT),4),
        'event',COALESCE(octet_length((to_jsonb(event_row))::TEXT),4),
        'owner_id',COALESCE(octet_length((to_jsonb(p_owner))::TEXT),4),
        'scan_id',COALESCE(octet_length((to_jsonb(p_scan))::TEXT),4),
        'admission_receipt_id',COALESCE(octet_length((to_jsonb(receipt.admission_receipt_id))::TEXT),4),
        'admission_receipt_digest',COALESCE(octet_length((to_jsonb(receipt.receipt_digest))::TEXT),4),
        'quota',COALESCE(octet_length((to_jsonb(quota))::TEXT),4),
        'attempt',COALESCE(octet_length((to_jsonb(attempt))::TEXT),4),
        'charges',COALESCE(octet_length((charges)::TEXT),4),
        'complimentary',COALESCE(octet_length((CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END)::TEXT),4),
        'owner_epoch',COALESCE(octet_length((owner_epoch)::TEXT),4),
        'private_components',component_bytes,'erasure_images',private_bytes);
    FOR member IN SELECT * FROM (VALUES
        ('source_registry','internal.initial_preparation_source_registry',8,TRUE),
        ('destination_registry','internal.initial_analysis_media_registry',8,TRUE),
        ('source_fence','internal.initial_preparation_source_fences',1,FALSE),
        ('media_fence','internal.initial_analysis_media_allocation_fences',1,FALSE),
        ('media_cohort','internal.initial_analysis_media_cohorts',1,FALSE),
        ('lifecycle','internal.initial_analysis_lifecycle_fences',1,FALSE)
    ) AS m(component,relation_name,row_limit,is_array) LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %s WHERE scan_id=$1 LIMIT %s) bounded',member.relation_name,member.row_limit+1)
            INTO member_count USING p_scan;
        IF member_count>member.row_limit THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        EXECUTE format('SELECT COALESCE(sum(octet_length(to_jsonb(t)::TEXT)),0) FROM %s t WHERE scan_id=$1',member.relation_name)
            INTO member_bytes USING p_scan;
        IF member_bytes>33554432 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        field_sizes:=field_sizes||jsonb_build_object(member.component,
            CASE WHEN member.is_array THEN 2+member_bytes+greatest(member_count-1,0)*2
            WHEN member_count=0 THEN 4 ELSE member_bytes END);
    END LOOP;
    IF admitted.binding_version=4 THEN
        field_sizes:=field_sizes||jsonb_build_object('cpm_retained',internal.measure_initial_cpm_cancellation_retained_images(receipt,FALSE));
    END IF;
    member_number:=0;
    FOR field_name,field_bytes IN SELECT key,value FROM jsonb_each_text(field_sizes) LOOP
        IF field_bytes IS NULL OR field_bytes::BIGINT<1 THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        total_bytes:=total_bytes+octet_length(to_jsonb(field_name)::TEXT)+2+field_bytes::BIGINT
            +CASE WHEN member_number>0 THEN 2 ELSE 0 END;
        member_number:=member_number+1;
        IF total_bytes>67108864 THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    END LOOP;
    private_images:=internal.capture_initial_cancellation_private_images(p_scan);
    FOR member IN SELECT * FROM internal.initial_accounted_cancellation_components() LOOP
        components:=components||jsonb_build_object(member.component,CASE WHEN member.is_array
            THEN private_images->member.relation_name ELSE private_images->member.relation_name->0 END);
    END LOOP;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO source_rows
        FROM internal.initial_preparation_source_registry r WHERE scan_id=p_scan;
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY object_id),'[]') INTO destination_rows
        FROM internal.initial_analysis_media_registry r WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO source_fence FROM internal.initial_preparation_source_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(f) INTO media_fence FROM internal.initial_analysis_media_allocation_fences f WHERE scan_id=p_scan;
    SELECT to_jsonb(c) INTO media_cohort FROM internal.initial_analysis_media_cohorts c WHERE scan_id=p_scan;
    cpm_prestate:=jsonb_build_object('version',1,'authority','none','transaction_id',pg_catalog.pg_current_xact_id()::TEXT,
        'variant','accounted_invocation','invocation',to_jsonb(invocation),'event',to_jsonb(event_row),
        'owner_id',p_owner,'scan_id',p_scan,'admission_receipt_id',receipt.admission_receipt_id,
        'admission_receipt_digest',receipt.receipt_digest,'quota',to_jsonb(quota),'attempt',to_jsonb(attempt),
        'charges',charges,'complimentary',CASE WHEN usage_row.client_scan_id IS NULL THEN 'null'::JSONB ELSE to_jsonb(usage_row) END,'owner_epoch',owner_epoch,
        'source_fence',source_fence,'source_registry',source_rows,'media_fence',media_fence,
        'media_cohort',media_cohort,'destination_registry',destination_rows,
        'private_components',components,
        'erasure_images',private_images,
        'lifecycle',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan));
    IF admitted.binding_version=4 THEN
        cpm_prestate:=cpm_prestate||jsonb_build_object('cpm_retained',internal.initial_cpm_cancellation_retained_images(receipt,FALSE));
        PERFORM internal.assert_initial_cpm_cancellation_images(p_scan,cpm_prestate,FALSE);
        PERFORM internal.assert_initial_cpm_cancellation_empty_destination(p_scan,cpm_prestate);
    END IF;
    IF octet_length(cpm_prestate::TEXT) IS DISTINCT FROM total_bytes OR octet_length(cpm_prestate::TEXT)>67108864 THEN
        RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
    RETURN cpm_prestate;
END;
$function$;

ALTER FUNCTION internal.initial_cancellation_invocation_event(internal.initial_admitted_cancellation_staging) STABLE;

ALTER FUNCTION internal.capture_initial_cancellation_accounting_images(internal.initial_admitted_cancellation_staging) VOLATILE;

ALTER FUNCTION internal.assert_initial_cancellation_terminal_shape(JSONB) STABLE;

CREATE OR REPLACE FUNCTION internal.report_initial_analysis_usage(p_owner UUID,p_scan UUID,p_submission_digest TEXT,
 p_invocation UUID,p_lease_token UUID,p_outcome TEXT,p_usage TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE receipt internal.initial_preparation_admission_receipts;
 original internal.identification_invocations;
 usage_value JSONB; event_uuid UUID; event_row public.ai_usage_events; context RECORD;
BEGIN
 SELECT * INTO STRICT context
 FROM internal.lock_initial_dispatched_original(p_owner,p_scan,p_submission_digest,p_invocation,p_lease_token,'report');
 receipt:=context.receipt_row;original:=context.invocation_row;
 IF original.event_id IS NULL THEN
  IF p_usage IS NULL OR octet_length(p_usage)>2048 THEN
   RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
  BEGIN usage_value:=p_usage::JSONB;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END;
  IF internal.initial_canonical(usage_value) IS DISTINCT FROM p_usage THEN
   RAISE EXCEPTION 'identification_usage_invalid' USING ERRCODE='22023'; END IF;
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
   admission_receipt_digest,reservation_id,invocation_id,expected_writes,report_invocation)
   VALUES(pg_current_xact_id(),p_scan,p_owner,'report',receipt.admission_receipt_id,receipt.receipt_digest,
    original.reservation_id,original.id,'[]',to_jsonb(original));
  event_uuid:=internal.complete_identification_usage(original.id,p_outcome,usage_value);
  DELETE FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id();
 ELSE
  -- Authenticated exact-original replay ignores new usage, including malformed
  -- text, and creates no witness or new accounting image.
  event_uuid:=internal.complete_identification_usage(original.id,NULL,NULL);
 END IF;
 SELECT * INTO event_row FROM public.ai_usage_events WHERE id=event_uuid FOR UPDATE;
 IF NOT FOUND OR NOT internal.identification_usage_matches_invocation(original,event_row)
  OR (SELECT event_id FROM internal.identification_invocations WHERE id=original.id) IS DISTINCT FROM event_row.id THEN
  RAISE EXCEPTION 'initial_analysis_report_conflict' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'submission_digest',p_submission_digest,'invocation_id',original.id,'event_id',event_uuid);
END;
$body$;

ALTER FUNCTION internal.decode_initial_result_numbers_v1(JSONB,JSONB) STABLE;

ALTER FUNCTION internal.initial_dispatch_invocation_matches(JSONB,JSONB) STABLE;

ALTER FUNCTION internal.initial_dispatch_expected_writes(JSONB,JSONB,TIMESTAMPTZ) STABLE;

CREATE OR REPLACE FUNCTION internal.assert_initial_dispatch_terminal(p_stage internal.initial_consuming_staging)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE charge JSONB; counter_image JSONB; original JSONB:=p_stage.dispatch_prestate;
BEGIN
 IF p_stage.operation<>'dispatch' OR original IS NULL THEN RETURN; END IF;
 IF NOT p_stage.sealed OR p_stage.next_statement<>4 OR p_stage.statement_active
  OR p_stage.pending_rows<>'{}'::INTEGER[] OR p_stage.observed_rows<>'{}'::INTEGER[]
  OR p_stage.invocation_id IS NULL OR p_stage.dispatch_invocation IS NULL
  OR p_stage.dispatch_invocation->>'id' IS DISTINCT FROM p_stage.invocation_id::TEXT
  OR p_stage.expected_writes IS DISTINCT FROM internal.initial_dispatch_expected_writes(original,p_stage.dispatch_invocation,
    (p_stage.expected_writes#>>'{0,0,new,committed_at}')::TIMESTAMPTZ)
  OR internal.initial_dispatch_root_images(p_stage.scan_id) IS DISTINCT FROM original->'roots'
  OR (SELECT internal.initial_consuming_row_image('internal.ai_quota_reservations',to_jsonb(q)) FROM internal.ai_quota_reservations q
    WHERE id=p_stage.reservation_id) IS DISTINCT FROM p_stage.expected_writes#>'{0,0,new}'
  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=p_stage.reservation_id)
  OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=p_stage.reservation_id)<>1
  OR (SELECT to_jsonb(a) FROM internal.identification_provider_attempts a WHERE reservation_id=p_stage.reservation_id AND attempt_count=1)
    IS DISTINCT FROM original->'attempt'
  OR (SELECT count(*) FROM internal.identification_invocations WHERE scan_id=p_stage.scan_id OR reservation_id=p_stage.reservation_id)<>1
  OR (SELECT to_jsonb(i) FROM internal.identification_invocations i WHERE id=p_stage.invocation_id) IS DISTINCT FROM p_stage.dispatch_invocation
  OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id=p_stage.scan_id) IS DISTINCT FROM p_stage.expected_writes#>'{3,0,new}'
  OR (SELECT jsonb_build_object('id',u.id,'entitlement_version',u.entitlement_version,
    'complimentary_entitlement_epoch',u.complimentary_entitlement_epoch) FROM public.users u WHERE u.id=p_stage.owner_id) IS DISTINCT FROM original->'owner_epoch'
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=p_stage.scan_id)
    <>(CASE WHEN original->'hold'='null'::JSONB THEN 0 ELSE 1 END)
  OR COALESCE((SELECT to_jsonb(h) FROM internal.complimentary_scan_usage h WHERE user_id=p_stage.owner_id AND client_scan_id=p_stage.scan_id),'null'::JSONB)
    IS DISTINCT FROM original->'hold'
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_stage.scan_id)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_stage.owner_id AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 FOR charge IN SELECT value FROM jsonb_array_elements(original->'charges') LOOP
  SELECT to_jsonb(c) INTO counter_image FROM internal.ai_quota_counters c
   WHERE c.scope_type=charge#>>'{counter,scope_type}' AND c.scope_key=charge#>>'{counter,scope_key}'
    AND c.bucket=charge#>>'{counter,bucket}' AND c.window_start=(charge#>>'{counter,window_start}')::TIMESTAMPTZ;
  IF counter_image IS DISTINCT FROM charge->'counter' THEN
   RAISE EXCEPTION 'initial_analysis_dispatch_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
END;
$body$;

ALTER FUNCTION internal.initial_completion_event_catalog_v1(TEXT,TEXT,TEXT) STABLE;

CREATE OR REPLACE FUNCTION internal.initial_completion_credit_prefix_v1(p_original JSONB,p_clock TIMESTAMPTZ)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' SET timezone='UTC' AS $body$
DECLARE app_user public.users; usage internal.complimentary_scan_usage; hold_image JSONB; owner_image JSONB;
 hold_after JSONB; owner_after JSONB; funding TEXT; events JSONB:='[]'::JSONB; spec JSONB; before_image JSONB; after_image JSONB;
BEGIN
 IF p_clock IS NULL OR NOT isfinite(p_clock) OR p_clock<transaction_timestamp() OR p_clock>clock_timestamp() THEN
  RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
 -- Validate here as well as through the settlement caller: the stage guard
 -- independently recomputes this prefix for every direct attachment attempt.
 -- No prepared credit events may exist before finalized original media.
 IF p_original->>'media_case'='legacy' THEN
  PERFORM internal.assert_initial_transferred_preparation(
   (p_original->>'owner_id')::UUID,(p_original->>'scan_id')::UUID);
 ELSIF p_original->>'media_case'='cpm' THEN
  PERFORM internal.assert_initial_completion_adoption_stage_v1(p_original);
 ELSE
  RAISE EXCEPTION 'initial_completion_adoption_unavailable' USING ERRCODE='55000';
 END IF;
 SELECT * INTO STRICT app_user FROM public.users WHERE id=(p_original->>'owner_id')::UUID;
 SELECT * INTO usage FROM internal.complimentary_scan_usage
  WHERE user_id=app_user.id AND client_scan_id=(p_original->>'scan_id')::UUID;
 hold_image:=CASE WHEN FOUND THEN to_jsonb(usage) ELSE 'null'::JSONB END;
 owner_image:=internal.initial_completion_owner_image_v1(to_jsonb(app_user));
 IF hold_image IS DISTINCT FROM p_original->'hold' OR owner_image IS DISTINCT FROM p_original->'owner'
  OR internal.initial_dispatch_root_images((p_original->>'scan_id')::UUID) IS DISTINCT FROM p_original->'roots' THEN
  RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
 owner_after:=owner_image;hold_after:=hold_image;
 IF hold_image='null'::JSONB THEN funding:='none';
 ELSE
  IF usage.state IS DISTINCT FROM 'held' THEN RAISE EXCEPTION 'initial_completion_credit_invalid' USING ERRCODE='55000'; END IF;
  funding:=CASE WHEN app_user.subscription_tier='pro' AND (app_user.subscription_expires_at IS NULL OR app_user.subscription_expires_at>p_clock)
   THEN 'paid_release' ELSE 'consumed' END;
  hold_after:=hold_image||jsonb_build_object('state',CASE funding WHEN 'consumed' THEN 'consumed' ELSE 'released' END,
   'settled_at',p_clock,'updated_at',p_clock,'settlement_reason',CASE funding WHEN 'consumed' THEN 'durable_result_complete' ELSE 'paid_before_completion' END);
  owner_after:=owner_image||jsonb_build_object('complimentary_entitlement_epoch',app_user.complimentary_entitlement_epoch+1,
   'entitlement_version',app_user.entitlement_version+1);
  FOR spec IN SELECT value FROM jsonb_array_elements(internal.initial_completion_event_catalog_v1(
   p_original->>'media_case',funding,p_original->>'species_case')) WHERE (value->>'ordinal')::INTEGER<8 LOOP
   before_image:='null';after_image:='null';
   IF spec->>'level'='ROW' THEN
    before_image:=CASE spec->>'slot' WHEN 'credit.settle' THEN hold_image ELSE owner_image END;
    after_image:=CASE spec->>'slot' WHEN 'credit.settle' THEN hold_after ELSE owner_after END;
   END IF;
   events:=events||jsonb_build_array(spec||jsonb_build_object('old',before_image,'new',after_image));
  END LOOP;
 END IF;
 RETURN jsonb_build_object('clock',p_clock,'case',funding,'hold_after',hold_after,'owner_after',owner_after,'events',events)
  ||CASE WHEN p_original->>'media_case'='cpm' THEN jsonb_build_object('adoption',
   (SELECT completion_adoption FROM internal.initial_consuming_staging WHERE transaction_id=pg_current_xact_id())) ELSE '{}'::JSONB END;
END; $body$;

CREATE OR REPLACE FUNCTION internal.initial_completion_legacy_media_image_v1(
 p_owner UUID,p_scan UUID,p_roots JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE admitted internal.initial_preparation_admission_receipts;
 transfer internal.initial_preparation_transfer_receipts; input JSONB; mapping JSONB;
 owner_item JSONB; source_item JSONB; mapped JSONB; chosen JSONB; poster JSONB;
 result JSONB; items JSONB:='[]'::JSONB; source_index INTEGER; frame_source_index INTEGER;
BEGIN
 PERFORM internal.assert_initial_transferred_preparation(p_owner,p_scan);
 SELECT * INTO STRICT admitted FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
 SELECT * INTO STRICT transfer FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan;
 input:=admitted.input::JSONB;mapping:=admitted.mapping::JSONB;
 -- Owner timeline order is authoritative. Frames and companion audio belong
 -- to their video owner and must not become extra History media items.
 FOR owner_item IN SELECT value FROM jsonb_array_elements(input->'owner_timeline') LOOP
  IF owner_item->>'kind'<>'media' THEN CONTINUE; END IF;
  source_index:=(owner_item->>'index')::INTEGER;
  source_item:=input->'media'->source_index;
  mapped:=mapping->'items'->source_index;
  IF (mapped->>'index')::INTEGER IS DISTINCT FROM source_index THEN
   RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
  chosen:=CASE WHEN source_item->>'kind'='video' OR mapped->'prepared'='null'::JSONB
    THEN mapped->'source' ELSE mapped->'prepared' END;
  poster:=NULL;
  IF source_item->>'kind'='video' THEN
   -- First original frame in source order, regardless of inference selection.
   SELECT (ordinality-1)::INTEGER INTO frame_source_index
    FROM jsonb_array_elements(input->'media') WITH ORDINALITY AS f(value,ordinality)
    WHERE value->>'kind'='image' AND value->'clip_index'=source_item->'clip_index'
    ORDER BY ordinality LIMIT 1;
   IF FOUND THEN
    poster:=mapping->'items'->frame_source_index;
    poster:=CASE WHEN poster->'prepared'='null'::JSONB THEN poster->'source' ELSE poster->'prepared' END;
   END IF;
  END IF;
  items:=items||jsonb_build_array(jsonb_build_object(
   'ordinal',jsonb_array_length(items),'kind',source_item->'kind',
   'media_id',(chosen->>'destination_object_id')::UUID,
   'content_type',chosen#>'{bytes,content_type}','byte_count',chosen#>'{bytes,byte_count}',
   'sha256',chosen#>'{bytes,sha256}','poster_media_id',(poster->>'destination_object_id')::UUID));
 END LOOP;
 result:=jsonb_build_object('kind','legacy_transfer_v1','receipt_digest',transfer.receipt_digest,'items',items);
 IF jsonb_array_length(items) NOT BETWEEN 1 AND 64
  OR octet_length(result::TEXT)>65536 OR octet_length(internal.initial_canonical(result))>65536
  OR internal.initial_dispatch_root_images(p_scan) IS DISTINCT FROM p_roots THEN
  RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $body$;

CREATE OR REPLACE FUNCTION internal.initial_completion_tail_images_v1(
 p_original JSONB,p_credit JSONB,p_completion JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE events JSONB:='[]'::JSONB; spec JSONB; before_image JSONB; after_image JSONB;
 owner_before JSONB; owner_after JSONB; count_before JSONB; count_after JSONB;
 attempted_insert JSONB:='null'::JSONB; funding TEXT; species_case TEXT; prefix_length INTEGER;
BEGIN
 funding:=p_credit->>'case';species_case:=p_original->>'species_case';
 IF p_original->>'media_case' IS NULL OR p_original->>'media_case' NOT IN ('legacy','cpm')
  OR funding IS NULL OR funding NOT IN ('none','consumed','paid_release')
  OR species_case IS NULL OR species_case NOT IN ('none','new','existing')
  OR p_original#>>'{scan_final,id}' IS DISTINCT FROM p_original->>'scan_id'
  OR p_original#>>'{scan_final,user_id}' IS DISTINCT FROM p_original->>'owner_id'
  OR p_credit#>>'{owner_after,id}' IS DISTINCT FROM p_original->>'owner_id'
  OR p_original->>'owner_id' IS NULL OR p_original->>'scan_id' IS NULL
  OR p_completion->>'scan_id' IS DISTINCT FROM p_original->>'scan_id'
  OR p_completion->>'owner_id' IS DISTINCT FROM p_original->>'owner_id'
  OR p_completion->>'result_evidence_id' IS DISTINCT FROM p_original->>'result_evidence_id'
  OR p_original->>'result_evidence_id' IS NULL
  OR p_completion->'receipt_version' IS DISTINCT FROM '1'::JSONB
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_completion) key)
   IS DISTINCT FROM ARRAY['completion_projection_snapshot','owner_id','receipt_snapshot','receipt_version','result_evidence_id','scan_id']::TEXT[]
  OR jsonb_typeof(p_completion->'receipt_snapshot') IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_completion->'completion_projection_snapshot') IS DISTINCT FROM 'object'
  OR octet_length((p_completion->'receipt_snapshot')::TEXT)>16384
  OR octet_length((p_completion->'completion_projection_snapshot')::TEXT)>65536 THEN
  RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 -- A CPM event image must carry its own closed adoption row. A legacy
 -- credit prefix cannot manufacture an empty media.adopt event.
 IF p_original->>'media_case'='cpm' THEN
  IF jsonb_typeof(p_credit->'adoption') IS DISTINCT FROM 'object' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_credit->'adoption') key)
    IS DISTINCT FROM ARRAY['owner_id','receipt','receipt_digest','scan_id']::TEXT[]
   OR p_credit#>>'{adoption,owner_id}' IS DISTINCT FROM p_original->>'owner_id'
   OR p_credit#>>'{adoption,scan_id}' IS DISTINCT FROM p_original->>'scan_id'
   OR NOT internal.initial_cpm_adoption_shape_v1((p_original->>'owner_id')::UUID,(p_original->>'scan_id')::UUID,
    p_credit#>>'{adoption,receipt}',p_credit#>>'{adoption,receipt_digest}') THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  IF (p_credit#>>'{adoption,receipt}')::JSONB->>'result_evidence_id' IS DISTINCT FROM p_original->>'result_evidence_id' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 END IF;
 prefix_length:=CASE WHEN funding='none' THEN 0 ELSE 8 END;
 IF jsonb_array_length(p_credit->'events') IS DISTINCT FROM prefix_length THEN
  RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 owner_before:=p_credit->'owner_after';owner_after:=owner_before;
 count_before:=COALESCE(p_original->'species_count','null'::JSONB);count_after:=count_before;
 IF species_case='none' THEN
  IF p_original->'species' IS DISTINCT FROM 'null'::JSONB OR count_before<>'null'::JSONB THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
 ELSE
  IF p_original#>>'{species,id}' IS NULL
   OR p_original#>>'{scan_final,species_id}' IS DISTINCT FROM p_original#>>'{species,id}' THEN
   RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
  attempted_insert:=jsonb_build_object('user_id',p_original->'owner_id',
   'species_id',p_original#>'{species,id}','scan_count',1);
  IF species_case='new' THEN
   IF count_before<>'null'::JSONB THEN RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
   count_after:=attempted_insert;
   owner_after:=jsonb_set(owner_before,'{total_species_discovered}',
    to_jsonb((owner_before->>'total_species_discovered')::INTEGER+1));
  ELSE
   IF count_before->>'user_id' IS DISTINCT FROM p_original->>'owner_id'
    OR count_before->>'species_id' IS DISTINCT FROM p_original#>>'{species,id}'
    OR (count_before->>'scan_count')::BIGINT IS NULL OR (count_before->>'scan_count')::BIGINT<1 THEN
    RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023'; END IF;
   count_after:=jsonb_set(count_before,'{scan_count}',to_jsonb((count_before->>'scan_count')::BIGINT+1));
  END IF;
 END IF;
 FOR spec IN SELECT value FROM jsonb_array_elements(
  internal.initial_completion_event_catalog_v1(p_original->>'media_case',funding,species_case))
  WHERE (value->>'ordinal')::INTEGER>=prefix_length LOOP
  before_image:='null';after_image:='null';
  IF spec->>'level'='ROW' THEN
   CASE spec->>'slot'
    WHEN 'media.adopt' THEN after_image:=p_credit->'adoption';
    WHEN 'scan.insert' THEN after_image:=p_original->'scan_final';
    WHEN 'species.increment' THEN before_image:=count_before;after_image:=count_after;
    WHEN 'species.insert' THEN after_image:=attempted_insert;
    WHEN 'species.new_total' THEN before_image:=owner_before;after_image:=owner_after;
    WHEN 'completion.insert' THEN after_image:=p_completion;
    ELSE RAISE EXCEPTION 'initial_completion_tail_invalid' USING ERRCODE='22023';
   END CASE;
  END IF;
  events:=events||jsonb_build_array(spec||jsonb_build_object('old',before_image,'new',after_image));
 END LOOP;
 -- The attempted ON CONFLICT row is distinct from the actual winner. The
 -- eventual observer must compare the locked winner at INSERT AFTER STATEMENT.
 RETURN jsonb_build_object('events',events,'owner_after',owner_after,
  'species_after',count_after,'attempted_species_insert',attempted_insert,
  'scan_after',p_original->'scan_final','completion_after',p_completion)
  ||CASE WHEN p_original->>'media_case'='cpm' THEN jsonb_build_object('adoption_after',p_credit->'adoption') ELSE '{}'::JSONB END;
END; $body$;

CREATE OR REPLACE FUNCTION internal.initial_completion_accounting_image_v1(p_owner UUID,p_scan UUID,p_invocation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $body$
DECLARE event public.ai_usage_events; result JSONB:='null'::JSONB; count_rows INTEGER:=0;
BEGIN
 -- Invocation is already locked before this event lock, preserving accounting
 -- order. Keep only a bounded digest in the stage, never copied metadata.
 FOR event IN SELECT * FROM public.ai_usage_events
  WHERE scan_id=p_scan OR (source_type='identification_invocation' AND source_id=p_invocation)
  ORDER BY id FOR SHARE LOOP
  count_rows:=count_rows+1;
  IF count_rows<>1 OR event.user_id IS DISTINCT FROM p_owner OR event.scan_id IS DISTINCT FROM p_scan
   OR event.source_type IS DISTINCT FROM 'identification_invocation' OR event.source_id IS DISTINCT FROM p_invocation
   OR event.operation IS DISTINCT FROM 'scan_identification' THEN
   RAISE EXCEPTION 'initial_completion_accounting_conflict' USING ERRCODE='55000'; END IF;
  result:=jsonb_build_object('id',event.id,'sha256',encode(extensions.digest(convert_to(
   internal.initial_consuming_row_image('public.ai_usage_events',to_jsonb(event))::TEXT,'UTF8'),'sha256'),'hex'));
 END LOOP;
 RETURN result;
END; $body$;

CREATE OR REPLACE FUNCTION internal.prepare_initial_cpm_retention_v1(p_owner UUID,p_scan UUID,p_submission TEXT,
 p_result UUID,p_result_digest TEXT,p_policy TEXT)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $body$
DECLARE original JSONB; receipt internal.initial_preparation_admission_receipts;
 policy internal.initial_cpm_photo_retention_policies; saved JSONB; member JSONB;
 objects JSONB:='[]'::JSONB; reads JSONB:='[]'::JSONB; result JSONB; object JSONB;
BEGIN
 original:=internal.prepare_initial_completion_v1(p_owner,p_scan,p_submission,p_result,p_result_digest);
 IF original->>'media_case' IS DISTINCT FROM 'cpm' THEN
  RAISE EXCEPTION 'initial_completion_media_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO STRICT receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan;
 saved:=receipt.cpm_retained_roles::JSONB;
 SELECT p.* INTO policy FROM internal.initial_cpm_photo_retention_policies p
 JOIN internal.initial_cpm_photo_write_policies w ON w.digest=p.write_policy_digest
 JOIN internal.initial_preparation_backend_eligibility b ON b.generation=w.backend_generation
 WHERE p.digest=p_policy AND p.state='eligible' AND w.state='eligible' AND b.state='eligible'
  AND w.backend_generation::TEXT=saved->>'backend_generation'
  AND w.backend_configuration_digest=saved->>'backend_configuration_digest'
  AND b.configuration_digest=w.backend_configuration_digest
 FOR SHARE OF p,w,b NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_completion_retention_policy_unavailable' USING ERRCODE='55000'; END IF;
 FOR member IN SELECT value FROM jsonb_array_elements(saved->'members') LOOP
  IF member#>>'{attempt,write_policy_digest}' IS DISTINCT FROM policy.write_policy_digest
   OR member#>>'{closure,policy_digest}' IS DISTINCT FROM policy.write_policy_digest THEN
   RAISE EXCEPTION 'initial_completion_retention_policy_unavailable' USING ERRCODE='55000'; END IF;
  object:=jsonb_build_object('photo_ordinal',member#>'{role,photo_ordinal}','role',member#>'{role,role}',
   'reference_id',member#>'{role,declaration,reference_id}','object_id',member#>'{role,object_id}',
   'backend_generation',saved->'backend_generation','backend_configuration_digest',saved->'backend_configuration_digest',
   'namespace','initial-preparation/v2','byte_count',member#>'{role,declaration,byte_count}',
   'sha256',member#>'{role,declaration,sha256}','content_type',member#>'{role,declaration,declared_content_type}');
  objects:=objects||jsonb_build_array(object);
  reads:=reads||jsonb_build_array(jsonb_build_object('attempt_id',member#>'{attempt,attempt_id}',
   'scan_id',p_scan,'object_id',object->'object_id','assignment_digest',saved->'assignment_digest',
   'backend_generation',saved->'backend_generation','backend_configuration_digest',saved->'backend_configuration_digest',
   'issued_at_ms',floor(extract(epoch FROM (member#>>'{attempt,issued_at}')::TIMESTAMPTZ)*1000)::BIGINT,
   'verification_policy_digest',policy.write_policy_digest));
 END LOOP;
 result:=jsonb_build_object('version',1,'variant','cpm_in_place_adoption_v1','owner_id',p_owner,'scan_id',p_scan,
  'admission_receipt_id',receipt.admission_receipt_id,'admission_receipt_digest',receipt.receipt_digest,
  'cpm_verification_digest',receipt.cpm_verification_digest,
  'retained_roles_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||chr(10)||receipt.cpm_retained_roles,'UTF8'),'sha256'),'hex'),
  'result_evidence_id',p_result,'result_digest',p_result_digest,'retention_policy_digest',policy.digest,
  'retention_build_digest',policy.retention_build_digest,'objects',objects);
 result:=jsonb_build_object('binding',result,'reads',reads,'profile_digest',saved->'profile_digest',
  'verifier_build_digest',saved->'verifier_build_digest','policy',to_jsonb(policy)-ARRAY['digest','state']);
 IF octet_length(result::TEXT)>65536 OR octet_length(internal.initial_canonical(result))>65536 THEN
  RAISE EXCEPTION 'initial_completion_retention_verification_invalid' USING ERRCODE='22023'; END IF;
 RETURN result;
END; $body$;

CREATE OR REPLACE FUNCTION internal.initial_cpm_adoption_shape_v1(p_owner UUID,p_scan UUID,p_text TEXT,p_digest TEXT)
RETURNS BOOLEAN LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE v JSONB; m JSONB; n INTEGER:=0; k TEXT; ids UUID[]:='{}'::UUID[]; refs UUID[]:='{}'::UUID[];
BEGIN
 IF p_owner IS NULL OR p_scan IS NULL OR p_text IS NULL OR octet_length(p_text)>65536 OR p_digest IS NULL THEN RETURN FALSE; END IF;
 v:=p_text::JSONB;
 IF internal.initial_canonical(v) IS DISTINCT FROM p_text OR octet_length(v::TEXT)>65536
  OR v->'version' IS DISTINCT FROM '1'::JSONB OR v->>'variant' IS DISTINCT FROM 'cpm_in_place_adoption_v1'
  OR v->>'owner_id' IS DISTINCT FROM p_owner::TEXT OR v->>'scan_id' IS DISTINCT FROM p_scan::TEXT
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v) key) IS DISTINCT FROM
   ARRAY['admission_receipt_digest','admission_receipt_id','adopted_at_ms','cpm_verification_digest','objects','owner_id','result_digest','result_evidence_id','retained_roles_digest','retention_build_digest','retention_policy_digest','scan_id','variant','verification_started_at_ms','verified_at_ms','version']::TEXT[]
  OR p_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.cpm-adoption.v1'||chr(10)||p_text,'UTF8'),'sha256'),'hex') THEN RETURN FALSE; END IF;
 FOREACH k IN ARRAY ARRAY['admission_receipt_id','result_evidence_id'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'string' OR v->>k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN FALSE; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['admission_receipt_digest','cpm_verification_digest','result_digest','retained_roles_digest','retention_build_digest','retention_policy_digest'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'string' OR v->>k !~ '^[0-9a-f]{64}$' THEN RETURN FALSE; END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['verification_started_at_ms','verified_at_ms','adopted_at_ms'] LOOP
  IF jsonb_typeof(v->k) IS DISTINCT FROM 'number' OR (v->>k)::NUMERIC<>trunc((v->>k)::NUMERIC)
   OR (v->>k)::NUMERIC NOT BETWEEN 1 AND 9007199254740991 THEN RETURN FALSE; END IF;
 END LOOP;
 IF jsonb_typeof(v->'objects') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'objects') NOT IN (3,6) THEN RETURN FALSE; END IF;
 FOR m IN SELECT value FROM jsonb_array_elements(v->'objects') LOOP
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(m) key) IS DISTINCT FROM
   ARRAY['backend_configuration_digest','backend_generation','byte_count','content_type','namespace','object_id','photo_ordinal','reference_id','role','sha256']::TEXT[]
   OR m->'photo_ordinal' IS DISTINCT FROM to_jsonb(n/3) OR m->>'role' IS DISTINCT FROM (ARRAY['source','ai','display'])[n%3+1]
   OR m->>'namespace' IS DISTINCT FROM 'initial-preparation/v2' THEN RETURN FALSE; END IF;
  FOREACH k IN ARRAY ARRAY['object_id','reference_id','backend_generation'] LOOP
   IF jsonb_typeof(m->k) IS DISTINCT FROM 'string' OR m->>k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN FALSE; END IF;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['sha256','backend_configuration_digest'] LOOP
   IF jsonb_typeof(m->k) IS DISTINCT FROM 'string' OR m->>k !~ '^[0-9a-f]{64}$' THEN RETURN FALSE; END IF;
  END LOOP;
  IF (m->>'object_id')::UUID=ANY(ids) OR (m->>'reference_id')::UUID=ANY(refs)
   OR jsonb_typeof(m->'byte_count') IS DISTINCT FROM 'number' OR (m->>'byte_count')::NUMERIC<>trunc((m->>'byte_count')::NUMERIC)
   OR (m->>'byte_count')::NUMERIC NOT BETWEEN 1 AND (CASE m->>'role' WHEN 'source' THEN 33554432 WHEN 'ai' THEN 5242880 ELSE 4194304 END)
   OR jsonb_typeof(m->'content_type') IS DISTINCT FROM 'string'
   OR NOT (m->>'content_type'='image/jpeg' OR (m->>'role'='source' AND m->>'content_type' IN ('image/png','image/webp','image/heic','image/heif')))
   THEN RETURN FALSE; END IF;
  ids:=ids||(m->>'object_id')::UUID;refs:=refs||(m->>'reference_id')::UUID;n:=n+1;
 END LOOP;
 RETURN TRUE;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_parameter_value THEN RETURN FALSE;
END; $body$;

CREATE OR REPLACE FUNCTION internal.assert_initial_cpm_adoption_binding_v1(p_row JSONB)
RETURNS VOID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $body$
DECLARE v JSONB; r internal.initial_preparation_admission_receipts; result internal.initial_analysis_results;
 policy internal.initial_cpm_photo_retention_policies; original JSONB; objects JSONB:='[]'::JSONB; m JSONB; expected JSONB;
BEGIN
 IF NOT internal.initial_cpm_adoption_shape_v1((p_row->>'owner_id')::UUID,(p_row->>'scan_id')::UUID,p_row->>'receipt',p_row->>'receipt_digest')
  OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_row) key) IS DISTINCT FROM ARRAY['owner_id','receipt','receipt_digest','scan_id']::TEXT[] THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 v:=(p_row->>'receipt')::JSONB;
 SELECT * INTO r FROM internal.initial_preparation_admission_receipts WHERE scan_id=(p_row->>'scan_id')::UUID;
 IF NOT FOUND OR r.owner_id::TEXT IS DISTINCT FROM p_row->>'owner_id'
  OR r.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
  OR r.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(r) THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO result FROM internal.initial_analysis_results WHERE scan_id=r.scan_id;
 IF NOT FOUND OR result.owner_id IS DISTINCT FROM r.owner_id THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 SELECT * INTO policy FROM internal.initial_cpm_photo_retention_policies WHERE digest=v->>'retention_policy_digest';
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 original:=r.cpm_retained_roles::JSONB;
 FOR m IN SELECT value FROM jsonb_array_elements(original->'members') LOOP
  IF m#>>'{attempt,write_policy_digest}' IS DISTINCT FROM policy.write_policy_digest
   OR m#>>'{closure,policy_digest}' IS DISTINCT FROM policy.write_policy_digest THEN
   RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
  objects:=objects||jsonb_build_array(jsonb_build_object('photo_ordinal',m#>'{role,photo_ordinal}','role',m#>'{role,role}',
   'reference_id',m#>'{role,declaration,reference_id}','object_id',m#>'{role,object_id}',
   'backend_generation',original->'backend_generation','backend_configuration_digest',original->'backend_configuration_digest',
   'namespace','initial-preparation/v2','byte_count',m#>'{role,declaration,byte_count}',
   'sha256',m#>'{role,declaration,sha256}','content_type',m#>'{role,declaration,declared_content_type}'));
 END LOOP;
 expected:=jsonb_build_object('version',1,'variant','cpm_in_place_adoption_v1','owner_id',r.owner_id,'scan_id',r.scan_id,
  'admission_receipt_id',r.admission_receipt_id,'admission_receipt_digest',r.receipt_digest,'cpm_verification_digest',r.cpm_verification_digest,
  'retained_roles_digest',encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||chr(10)||r.cpm_retained_roles,'UTF8'),'sha256'),'hex'),
  'result_evidence_id',result.result_evidence_id,'result_digest',encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(result.result_snapshot),'UTF8'),'sha256'),'hex'),
  'retention_policy_digest',policy.digest,'retention_build_digest',policy.retention_build_digest,'objects',objects);
 IF v-ARRAY['verification_started_at_ms','verified_at_ms','adopted_at_ms'] IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_completion_adoption_invalid' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_cpm_retention_interval_v1(policy,v->'verification_started_at_ms',v->'verified_at_ms',(v->>'adopted_at_ms')::BIGINT);
END; $body$;

-- Dependency closure discovered by strict lint after the leaf corrections.
ALTER FUNCTION internal.initial_cancellation_cleanup_count(JSONB) STABLE;

RESET statement_timeout;
RESET lock_timeout;

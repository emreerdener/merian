-- Work in progress: coordinated CPM stage, proof and existing writer branches.
-- Closed variant storage joins original receipt, capacity and funding witnesses.
-- Public coordinator integration remains unfinished. No API permission/activation.
SET statement_timeout='60s';
SET lock_timeout='5s';

-- Same stage owner and transaction, with the original retained source cohort.
-- This constructor must be called by the fixed verification coordinator, never
-- a client proof endpoint. Matching declared bytes is not proof of media I/O.
CREATE FUNCTION internal.build_initial_cpm_admission_stage(
 p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_verification TEXT
) RETURNS internal.initial_preparation_admission_staging
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents;
 stage internal.initial_preparation_admission_staging;
 capacity internal.initial_cpm_photo_capacity_reservations;
 a JSONB; snapshot TEXT; snapshot_digest TEXT; expected TEXT; objects JSONB;
 projection JSONB; now_at TIMESTAMPTZ;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR p_assignment_digest IS NULL
  OR p_assignment_digest !~ '^[0-9a-f]{64}$'
  OR p_verification IS NULL OR octet_length(p_verification) NOT BETWEEN 1 AND 65536 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 IF num_nonnulls(saved.cpm_verification_attempt_id,saved.cpm_verification_started_at,
  saved.cpm_verification_snapshot_digest)<>3 THEN
  RAISE EXCEPTION 'initial_analysis_verification_required' USING ERRCODE='55000'; END IF;
 now_at:=clock_timestamp();
 IF now_at<saved.cpm_verification_started_at OR now_at>=saved.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 -- Existing outer account/deletion/scan scope, then fail-fast capacity before
 -- ordered registry/attempt rows. This transaction performs no storage GET.
 PERFORM internal.lock_initial_cpm_photo_capacity();
 SELECT * INTO STRICT capacity FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 a:=internal.parse_initial_cpm_photo_assignment(saved.canonical_candidate,saved.canonical_assignment);
 IF internal.initial_cpm_photo_digest('assignment',saved.canonical_assignment) IS DISTINCT FROM saved.assignment_digest
  OR capacity.owner_id IS DISTINCT FROM p_owner OR capacity.state IS DISTINCT FROM 'pending'
  OR capacity.write_capability_state IS DISTINCT FROM 'may_have_issued' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 snapshot:=internal.initial_cpm_verification_start_snapshot(p_owner,p_scan);
 snapshot_digest:=encode(extensions.digest(convert_to(
  'merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex');
 IF snapshot_digest IS DISTINCT FROM saved.cpm_verification_snapshot_digest THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 -- Construct the whole accepted evidence image from saved facts. Exact string
 -- comparison rejects missing/extra keys, reordered roles, changed declarations,
 -- noncanonical/duplicate JSON keys and any structural_acceptance except true.
 SELECT jsonb_agg(jsonb_build_object('object_id',m#>'{role,object_id}',
  'photo_ordinal',m#>'{role,photo_ordinal}','role',m#>'{role,role}',
  'byte_count',m#>'{role,declaration,byte_count}','sha256',m#>'{role,declaration,sha256}',
  'content_type',m#>'{role,declaration,declared_content_type}','structural_acceptance',TRUE) ORDER BY ordinal)
 INTO objects FROM jsonb_array_elements(snapshot::JSONB->'members') WITH ORDINALITY t(m,ordinal);
 expected:=internal.initial_canonical(jsonb_build_object('version',1,'protocol','cpm_photo_full_bytes_v1',
  'attempt_id',saved.cpm_verification_attempt_id,'snapshot_digest',snapshot_digest,
  'profile_digest',a#>'{preparation,profile_digest}',
  'verifier_build_digest',a#>'{preparation,verifier_build_digest}','objects',objects));
 IF p_verification IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_analysis_verification_required' USING ERRCODE='55000'; END IF;
 -- Fresh admission still requires current eligibility. Retained receipt recovery
 -- is a separate existing owner and must not pass through this fresh constructor.
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
  WHERE w.scan_id=p_scan ORDER BY p.digest FOR SHARE OF p NOWAIT;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts w
  JOIN internal.initial_cpm_photo_write_policies p ON p.digest=w.write_policy_digest
  WHERE w.scan_id=p_scan AND p.state<>'eligible') THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 projection:=internal.initial_cpm_admission_submission(saved.canonical_candidate,saved.canonical_assignment);
 IF clock_timestamp()>=saved.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 stage.scan_id:=p_scan; stage.owner_id:=p_owner;
 stage.transaction_id:=pg_catalog.pg_current_xact_id(); stage.stage_token:=pg_catalog.gen_random_uuid();
 stage.phase:='validated'; stage.admission_receipt_id:=pg_catalog.gen_random_uuid();
 stage.candidate:=saved.canonical_candidate; stage.assignment:=saved.canonical_assignment;
 stage.input:=projection->>'submission_canonical'; stage.admission_variant:='client_prepared_photo_v1';
 stage.cpm_verification:=p_verification;
 stage.cpm_verification_digest:=encode(extensions.digest(convert_to(
  'merian.initial-analysis.cpm-photo-verification.v1'||E'\n'||p_verification,'UTF8'),'sha256'),'hex');
 -- Retain the complete original start snapshot, including ordered roles, write
 -- attempts and positive closures. No fabricated M1 copy/mapping is introduced.
 stage.cpm_retained_roles:=snapshot; stage.cpm_capacity_predecessor:=to_jsonb(capacity);
 stage.original_admission_expires_at:=saved.expires_at;
 stage.completion_event_seq:=0; stage.cleanup_cursor:=0;
 RETURN stage;
END; $$;
REVOKE ALL ON FUNCTION internal.build_initial_cpm_admission_stage(UUID,UUID,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.create_initial_admission_stage(
 p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_verification TEXT
) RETURNS UUID LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE stage internal.initial_preparation_admission_staging;
BEGIN
 stage:=internal.build_initial_cpm_admission_stage(p_owner,p_scan,p_assignment_digest,p_verification);
 -- The closed storage union below requires the complete receipt/capacity/
 -- funding/C1 contract; this constructor grants no public admission authority.
 INSERT INTO internal.initial_preparation_admission_staging SELECT (stage).*;
 RETURN stage.stage_token;
END; $$;
REVOKE ALL ON FUNCTION internal.create_initial_admission_stage(UUID,UUID,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;

-- Shared assertion for already strictly parsed proof documents. Variant-specific
-- parsers own shape/canonical validation and receipt domains; this routine only
-- preserves the existing accounting associations. It grants no funding authority.
CREATE FUNCTION internal.assert_initial_admitted_accounting(
 p_execution_configuration JSONB,p_admission JSONB,p_funding JSONB,
 p_accounting JSONB,p_manifest JSONB
) RETURNS VOID LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE a JSONB:=p_execution_configuration; funding JSONB:=p_funding;
 accounting JSONB:=p_accounting; manifest JSONB:=p_manifest;
 original JSONB; reservation JSONB; attempt JSONB; policy JSONB; links JSONB;
 link JSONB; scopes TEXT[]; complimentary JSONB; charge_index INTEGER; k TEXT;
BEGIN
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
  OR p_admission->'client_protocol' IS DISTINCT FROM a->'accepted_client_protocol'
  OR p_admission->'identification_protocol' IS DISTINCT FROM a->'accepted_identification_protocol'
  OR p_admission->'expected_processor_permission' IS DISTINCT FROM a->'processor_permission' THEN
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
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_admitted_accounting(JSONB,JSONB,JSONB,JSONB,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

-- Extract the exact reviewed legacy tail; preserve parsing, canonical proof
-- references, all domains and the receipt digest return byte-for-byte.
DO $accounting$
DECLARE definition TEXT; first_at INTEGER; last_at INTEGER; original_tail TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef(
  'internal.validate_initial_admitted_proof(text,text,text,text,text,text,text,text,text,text,text,text)'::REGPROCEDURE);
 first_at:=strpos(definition,$start$ original:=funding->'original'; reservation:=accounting->'reservation'; attempt:=accounting->'attempt';$start$);
 last_at:=strpos(definition,$end$ RETURN encode(extensions.digest(convert_to('merian.initial-analysis.handoff.admitted-receipt.v1'$end$);
 IF first_at=0 OR last_at<=first_at THEN RAISE EXCEPTION 'initial admitted accounting source drift'; END IF;
 original_tail:=substr(definition,first_at,last_at-first_at);
 IF encode(extensions.digest(convert_to(original_tail,'UTF8'),'sha256'),'hex')<>'4ab681e0f4b64d283cb0afa950eb09fb40ede24c2950a74d148c8001c4d91083' THEN RAISE EXCEPTION 'initial admitted accounting source drift'; END IF;
 EXECUTE overlay(definition PLACING
  E' PERFORM internal.assert_initial_admitted_accounting(a,input_value->\'admission\',funding,accounting,manifest);\n'
  FROM first_at FOR last_at-first_at);
END; $accounting$;

-- Closed CPM proof documents; these codecs confer neither admission nor I/O
-- authority. Recovery uses retained original facts, without a current clock.
CREATE FUNCTION internal.parse_initial_cpm_admitted_document(p_kind TEXT,p_text TEXT)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE cap INTEGER; value JSONB;
BEGIN
 cap:=CASE p_kind WHEN 'snapshot' THEN 65536 WHEN 'verification' THEN 65536 WHEN 'manifest' THEN 8192 END;
 IF cap IS NULL OR p_text IS NULL OR octet_length(p_text) NOT BETWEEN 1 AND cap THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 BEGIN value:=p_text::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 IF jsonb_typeof(value) IS DISTINCT FROM 'object' OR internal.initial_canonical(value) IS DISTINCT FROM p_text THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN value;
END; $$;
REVOKE ALL ON FUNCTION internal.parse_initial_cpm_admitted_document(TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.build_initial_cpm_admitted_manifest(
 p_receipt internal.initial_preparation_admission_receipts,p_authorized_at_ms BIGINT
) RETURNS TEXT LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts:=p_receipt;
 candidate JSONB; configuration JSONB; a JSONB; projection JSONB; funding JSONB; accounting JSONB;
 snapshot JSONB; verification JSONB; m JSONB; role JSONB; w JSONB; c JSONB; expected JSONB;
 objects JSONB:='[]'::JSONB; attempt_ids TEXT[]:=ARRAY[]::TEXT[]; attempt_id TEXT; k TEXT;
 created TIMESTAMPTZ; issued TIMESTAMPTZ; closed TIMESTAMPTZ; capability TIMESTAMPTZ;
 assignment_digest TEXT; snapshot_digest TEXT; capacity_text TEXT; manifest TEXT;
 retained BIGINT:=0; n INTEGER; proof JSONB:='{}'::JSONB; metadata JSONB:='{}'::JSONB;
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
 FOR m,n IN SELECT value,(ordinal-1)::INTEGER FROM jsonb_array_elements(snapshot->'members') WITH ORDINALITY t(value,ordinal) LOOP
  role:=a#>ARRAY['preparation','role_mapping',n::TEXT]; w:=m->'attempt'; c:=m->'closure';
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
REVOKE ALL ON FUNCTION internal.build_initial_cpm_admitted_manifest(internal.initial_preparation_admission_receipts,BIGINT)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.validate_initial_cpm_admitted_proof(p_receipt internal.initial_preparation_admission_receipts)
RETURNS TEXT LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE manifest JSONB; authorized NUMERIC; expected TEXT;
BEGIN
 manifest:=internal.parse_initial_cpm_admitted_document('manifest',p_receipt.manifest);
 IF jsonb_typeof(manifest->'authorized_at_ms') IS DISTINCT FROM 'number' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 authorized:=(manifest->>'authorized_at_ms')::NUMERIC;
 IF authorized<1 OR authorized>8640000000000000 OR mod(authorized,1)<>0 THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 expected:=internal.build_initial_cpm_admitted_manifest(p_receipt,authorized::BIGINT);
 IF p_receipt.manifest IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN encode(extensions.digest(convert_to('merian.initial-analysis.cpm-photo-admitted-receipt.v1'||E'\n'||expected,'UTF8'),'sha256'),'hex');
END; $$;
REVOKE ALL ON FUNCTION internal.validate_initial_cpm_admitted_proof(internal.initial_preparation_admission_receipts)
 FROM PUBLIC,anon,authenticated,service_role;

-- Branch existing policy/receipt owners with exact closed variant proofs
-- until the complete finite materialization/retention transition is installed.
DO $writers$
DECLARE definition TEXT; original TEXT; replacement TEXT; signature TEXT;
BEGIN
 signature:='internal.freeze_initial_admission_policy(uuid,uuid,text,boolean,uuid,boolean,timestamptz)';
 definition:=pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
 original:='a := stage.assignment::JSONB; input_value := stage.input::JSONB;';
 replacement:=$branch$a := CASE stage.admission_variant WHEN 'client_prepared_photo_v1' THEN stage.assignment::JSONB->'configuration' ELSE stage.assignment::JSONB END;
    input_value := CASE stage.admission_variant WHEN 'client_prepared_photo_v1' THEN stage.candidate::JSONB ELSE stage.input::JSONB END;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM policy source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$IF floor(extract(epoch FROM clock_timestamp())*1000)>=(stage.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN$anchor$;
 replacement:=$branch$IF (stage.admission_variant='client_prepared_photo_v1' AND stage.original_admission_expires_at IS NULL)
        OR floor(extract(epoch FROM clock_timestamp())*1000)>=(CASE stage.admission_variant
            WHEN 'client_prepared_photo_v1' THEN extract(epoch FROM stage.original_admission_expires_at)*1000
            ELSE (stage.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC END) THEN$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM policy deadline source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.build_initial_admission_receipt(uuid)'::REGPROCEDURE);
 original:='a:=stage.assignment::JSONB;';
 replacement:=original||E'\n    result.admission_variant:=stage.admission_variant;';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM receipt source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$jsonb_build_object('version',2,'assignment',a)$anchor$;
 replacement:=$branch$jsonb_build_object('version',CASE stage.admission_variant WHEN 'client_prepared_photo_v1' THEN 3 ELSE 2 END,'assignment',a)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM configuration source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'model',a->'effective_model'$anchor$;
 replacement:=$branch$'model',CASE stage.admission_variant WHEN 'client_prepared_photo_v1' THEN a#>'{configuration,effective_model}' ELSE a->'effective_model' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM funding source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='    -- Domains are fixed by component name.';
 replacement:=$branch$    IF stage.admission_variant='client_prepared_photo_v1' THEN
        result.cpm_verification:=stage.cpm_verification;
        result.cpm_verification_digest:=stage.cpm_verification_digest;
        result.cpm_retained_roles:=stage.cpm_retained_roles;
        result.cpm_capacity_predecessor:=stage.cpm_capacity_predecessor;
        result.original_admission_expires_at:=stage.original_admission_expires_at;
        result.manifest:=internal.build_initial_cpm_admitted_manifest(result,floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT);
        result.receipt_digest:=internal.validate_initial_cpm_admitted_proof(result);
        RETURN result;
    END IF;
    -- Domains are fixed by component name.$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM receipt branch source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_prospective(internal.initial_preparation_admission_staging)'::REGPROCEDURE);
 original:='OR r.media_binding IS DISTINCT FROM s.media_binding';
 replacement:=original||$branch$
        OR r.admission_variant IS DISTINCT FROM s.admission_variant
        OR r.cpm_verification IS DISTINCT FROM s.cpm_verification
        OR r.cpm_verification_digest IS DISTINCT FROM s.cpm_verification_digest
        OR r.cpm_retained_roles IS DISTINCT FROM s.cpm_retained_roles
        OR r.cpm_capacity_predecessor IS DISTINCT FROM s.cpm_capacity_predecessor
        OR r.original_admission_expires_at IS DISTINCT FROM s.original_admission_expires_at$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM prospective image source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$jsonb_build_object('version',2,'assignment',s.assignment::JSONB)$anchor$;
 replacement:=$branch$jsonb_build_object('version',CASE s.admission_variant WHEN 'client_prepared_photo_v1' THEN 3 ELSE 2 END,'assignment',s.assignment::JSONB)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM prospective configuration source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest)$anchor$;
 replacement:=$branch$(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN internal.validate_initial_cpm_admitted_proof(r)
            ELSE $branch$||original||' END)';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM prospective proof source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'model',s.assignment::JSONB->'effective_model'$anchor$;
 replacement:=$branch$'model',CASE s.admission_variant WHEN 'client_prepared_photo_v1' THEN s.assignment::JSONB#>'{configuration,effective_model}' ELSE s.assignment::JSONB->'effective_model' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM prospective funding source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$OR floor(extract(epoch FROM clock_timestamp())*1000)>=(s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN$anchor$;
 replacement:=$branch$OR (s.admission_variant='client_prepared_photo_v1' AND s.original_admission_expires_at IS NULL)
        OR floor(extract(epoch FROM clock_timestamp())*1000)>=(CASE s.admission_variant
            WHEN 'client_prepared_photo_v1' THEN extract(epoch FROM s.original_admission_expires_at)*1000
            ELSE (s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC END) THEN$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM prospective deadline source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_live_snapshot(internal.initial_preparation_admission_staging)'::REGPROCEDURE);
 original:=$anchor$'model',s.assignment::JSONB->'effective_model'$anchor$;
 replacement:=$branch$'model',CASE s.admission_variant WHEN 'client_prepared_photo_v1' THEN s.assignment::JSONB#>'{configuration,effective_model}' ELSE s.assignment::JSONB->'effective_model' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM live funding source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
END; $writers$;

-- Extend the same finite statement inventory and its witnesses. The capacity
-- state/storage guards still deny execution until retained cohort and C1 support
-- are installed; no constraints are relaxed at this editing checkpoint.
DO $members$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.initial_admission_statement_contract(text)'::REGPROCEDURE);
 original:=$anchor$WHEN 'M1.fence.insert' THEN$anchor$;
 replacement:=$branch$WHEN 'CPM.capacity.update' THEN 'internal.initial_cpm_photo_capacity_reservations'
        WHEN 'M1.fence.insert' THEN$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_statement_contract anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'C4.remaining.update','C8.attachment.update')$anchor$;
 replacement:=$branch$'C4.remaining.update','C8.attachment.update','CPM.capacity.update')$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_statement_contract anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_write_registration(uuid,text,text,text,jsonb,jsonb)'::REGPROCEDURE);
 original:=$anchor$(stage.phase<>'admitted' AND p_key LIKE 'M1.%')$anchor$;
 replacement:=$branch$(stage.phase<>'admitted' AND (p_key LIKE 'M1.%' OR p_key='CPM.capacity.update'))$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_write_registration anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$    IF p_relation='public.users'$anchor$;
 replacement:=$branch$    IF p_key='CPM.capacity.update' AND (
        stage.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
        OR p_old IS DISTINCT FROM stage.cpm_capacity_predecessor
        OR p_new IS DISTINCT FROM stage.cpm_capacity_predecessor||jsonb_build_object('state','admitted')) THEN
        RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000';
    END IF;
    IF p_relation='public.users'$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_write_registration anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.initial_admission_expected_write(uuid,text,text,jsonb,jsonb,boolean)'::REGPROCEDURE);
 original:=$anchor$(stage.phase<>'admitted' AND expected.statement_key LIKE 'M1.%')$anchor$;
 replacement:=$branch$(stage.phase<>'admitted' AND (expected.statement_key LIKE 'M1.%' OR expected.statement_key='CPM.capacity.update'))$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_expected_write anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.initial_admission_member_images(internal.initial_preparation_admission_receipts)'::REGPROCEDURE);
 original:=$anchor$BEGIN
    statement_key:=$anchor$;
 replacement:=$branch$BEGIN
    IF r.admission_variant IS NULL OR r.admission_variant NOT IN ('server_prepared_v3','client_prepared_photo_v1')
        OR (r.admission_variant='client_prepared_photo_v1'
            AND r.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(r)) THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
    END IF;
    statement_key:=$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'input_schema_version',1$anchor$;
 replacement:=$branch$'input_schema_version',CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN 2 ELSE 1 END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'ordered_descriptions',r.input::JSONB->'ordered_descriptions'$anchor$;
 replacement:=$branch$'ordered_descriptions',CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN r.input::JSONB->'contexts' ELSE r.input::JSONB->'ordered_descriptions' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 2 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'binding_version',3$anchor$;
 replacement:=$branch$'binding_version',CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN 4 ELSE 3 END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 3 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'preparation_outcome_digest',m#>'{proof,outcome,digest}'$anchor$;
 replacement:=$branch$'preparation_outcome_digest',CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN m#>'{proof,verification,digest}' ELSE m#>'{proof,outcome,digest}' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 4 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$    statement_key:='M1.fence.insert';$anchor$;
 replacement:=$branch$    IF r.admission_variant='client_prepared_photo_v1' THEN
        statement_key:='CPM.capacity.update'; relation_name:='internal.initial_cpm_photo_capacity_reservations';
        new_image:=r.cpm_capacity_predecessor||jsonb_build_object('state','admitted'); RETURN NEXT;
        RETURN;
    END IF;
    statement_key:='M1.fence.insert';$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM initial_admission_member_images anchor 5 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.materialize_initial_admission(uuid)'::REGPROCEDURE);
 original:=$anchor$image.statement_key LIKE 'M1.%' THEN CONTINUE$anchor$;
 replacement:=$branch$(image.statement_key LIKE 'M1.%' OR image.statement_key='CPM.capacity.update') THEN CONTINUE$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM materialize_initial_admission anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$        IF image.statement_key NOT LIKE 'M1.%' THEN CONTINUE; END IF;$anchor$;
 replacement:=$branch$        IF image.statement_key='CPM.capacity.update' THEN
            PERFORM internal.register_initial_admission_write(p_scan,image.statement_key,image.relation_name,
                'UPDATE',r.cpm_capacity_predecessor,image.new_image);
            UPDATE internal.initial_cpm_photo_capacity_reservations c SET state='admitted'
                WHERE c.scan_id=p_scan AND to_jsonb(c)=r.cpm_capacity_predecessor;
            IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
            CONTINUE;
        END IF;
        IF image.statement_key NOT LIKE 'M1.%' THEN CONTINUE; END IF;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM materialize_initial_admission anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_materialized(uuid,boolean)'::REGPROCEDURE);
 original:=$anchor$IF NOT p_media AND image.statement_key LIKE 'M1.%'$anchor$;
 replacement:=$branch$IF NOT p_media AND (image.statement_key LIKE 'M1.%' OR image.statement_key='CPM.capacity.update')$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_materialized anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$w.operation='INSERT'
            AND w.old_image IS NULL$anchor$;
 replacement:=$branch$w.operation=(CASE image.statement_key WHEN 'CPM.capacity.update' THEN 'UPDATE' ELSE 'INSERT' END)
            AND w.old_image IS NOT DISTINCT FROM (CASE image.statement_key WHEN 'CPM.capacity.update' THEN r.cpm_capacity_predecessor ELSE NULL::JSONB END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_materialized anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$IF amount<>jsonb_array_length(r.mapping::JSONB->'objects')$anchor$;
 replacement:=$branch$IF amount<>(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN 0 ELSE jsonb_array_length(r.mapping::JSONB->'objects') END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_materialized anchor 2 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_ledger(internal.initial_preparation_admission_staging)'::REGPROCEDURE);
 original:=$anchor$OR r.media_binding IS DISTINCT FROM s.media_binding$anchor$;
 replacement:=$branch$OR r.media_binding IS DISTINCT FROM s.media_binding
        OR r.admission_variant IS DISTINCT FROM s.admission_variant
        OR r.cpm_verification IS DISTINCT FROM s.cpm_verification
        OR r.cpm_verification_digest IS DISTINCT FROM s.cpm_verification_digest
        OR r.cpm_retained_roles IS DISTINCT FROM s.cpm_retained_roles
        OR r.cpm_capacity_predecessor IS DISTINCT FROM s.cpm_capacity_predecessor
        OR r.original_admission_expires_at IS DISTINCT FROM s.original_admission_expires_at$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_ledger anchor 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$jsonb_build_object('version',2,'assignment',s.assignment::JSONB)$anchor$;
 replacement:=$branch$jsonb_build_object('version',CASE s.admission_variant WHEN 'client_prepared_photo_v1' THEN 3 ELSE 2 END,'assignment',s.assignment::JSONB)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_ledger anchor 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest)$anchor$;
 replacement:=$branch$(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN internal.validate_initial_cpm_admitted_proof(r)
            ELSE internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_ledger anchor 2 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$IF w.new_image IS DISTINCT FROM image.new_image THEN$anchor$;
 replacement:=$branch$IF w.new_image IS DISTINCT FROM image.new_image
            OR w.old_image IS DISTINCT FROM (CASE image.statement_key WHEN 'CPM.capacity.update' THEN r.cpm_capacity_predecessor ELSE NULL::JSONB END) THEN$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM assert_initial_admission_ledger anchor 3 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;
END; $members$;

CREATE TRIGGER a00_initial_admission_seal BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON internal.initial_cpm_photo_capacity_reservations FOR EACH STATEMENT
 EXECUTE FUNCTION internal.guard_initial_admission_seal();
CREATE TRIGGER zz_initial_admission_member_before BEFORE INSERT OR UPDATE OR DELETE
 ON internal.initial_cpm_photo_capacity_reservations FOR EACH ROW
 EXECUTE FUNCTION internal.guard_initial_admission_member();
CREATE TRIGGER zz_initial_admission_member_after AFTER INSERT OR UPDATE OR DELETE
 ON internal.initial_cpm_photo_capacity_reservations FOR EACH ROW
 EXECUTE FUNCTION internal.guard_initial_admission_member();
CREATE TRIGGER zz_initial_admission_member_truncate BEFORE TRUNCATE
 ON internal.initial_cpm_photo_capacity_reservations FOR EACH STATEMENT
 EXECUTE FUNCTION internal.guard_initial_admission_member();

-- Cohort association only, never a proof/funding/IO authority. Callers validate
-- the complete receipt independently. FALSE checks the original pending image
-- immediately before materialization; TRUE checks the retained admitted image.
-- No current eligibility or clock test may renew or invalidate historical proof.
CREATE FUNCTION internal.assert_initial_cpm_receipt_cohort(
 p_receipt internal.initial_preparation_admission_receipts,p_admitted BOOLEAN
) RETURNS VOID LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE r internal.initial_preparation_admission_receipts:=p_receipt;
 saved internal.initial_analysis_preparation_intents; snapshot TEXT; verified JSONB;
 members INTEGER; capacity JSONB;
BEGIN
 IF p_admitted IS NULL OR r.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
  OR r.owner_id IS NULL OR r.scan_id IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM r.owner_id OR saved.canonical_candidate IS DISTINCT FROM r.candidate
  OR r.configuration IS DISTINCT FROM internal.initial_canonical(jsonb_build_object('version',3,'assignment',saved.canonical_assignment::JSONB))
  OR r.input IS DISTINCT FROM saved.canonical_candidate::JSONB->>'content_canonical'
  OR r.original_admission_expires_at IS DISTINCT FROM saved.expires_at
  OR num_nonnulls(saved.cpm_verification_attempt_id,saved.cpm_verification_started_at,saved.cpm_verification_snapshot_digest)<>3
  OR saved.assignment_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('assignment',saved.canonical_assignment) THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 PERFORM internal.initial_cpm_admission_submission(saved.canonical_candidate,saved.canonical_assignment);
 verified:=internal.parse_initial_cpm_admitted_document('verification',r.cpm_verification);
 IF verified->>'attempt_id' IS DISTINCT FROM saved.cpm_verification_attempt_id::TEXT
  OR verified->>'snapshot_digest' IS DISTINCT FROM saved.cpm_verification_snapshot_digest
  OR r.cpm_verification_digest IS DISTINCT FROM encode(extensions.digest(convert_to(
   'merian.initial-analysis.cpm-photo-verification.v1'||E'\n'||r.cpm_verification,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 members:=jsonb_array_length(saved.canonical_assignment::JSONB#>'{preparation,role_mapping}');
 SELECT to_jsonb(c) INTO capacity FROM internal.initial_cpm_photo_capacity_reservations c WHERE scan_id=r.scan_id;
 IF capacity IS DISTINCT FROM (r.cpm_capacity_predecessor||jsonb_build_object('state',CASE WHEN p_admitted THEN 'admitted' ELSE 'pending' END))
  OR (SELECT count(*) FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=r.scan_id)<>members
  OR (SELECT count(*) FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts w
   ON w.attempt_id=c.attempt_id WHERE w.scan_id=r.scan_id)<>members
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id AND claim_expires_at IS NOT NULL)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_cohorts WHERE scan_id=r.scan_id)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id) THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 -- Existing snapshot owner reconstructs every original role, issued attempt,
 -- positive closure and immutable backend identity; it never re-verifies bytes.
 snapshot:=internal.initial_cpm_verification_start_snapshot(r.owner_id,r.scan_id);
 IF snapshot IS DISTINCT FROM r.cpm_retained_roles OR saved.cpm_verification_snapshot_digest IS DISTINCT FROM
  encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_receipt_cohort(internal.initial_preparation_admission_receipts,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

DO $retained$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.initial_cpm_photo_cohort_complete(uuid)'::REGPROCEDURE);
 original:=$anchor$AND owner_id=saved.owner_id AND state='pending' AND declared_retained_bytes=retained$anchor$;
 replacement:=$branch$AND owner_id=saved.owner_id AND state IN ('pending','admitted') AND declared_retained_bytes=retained$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.initial_cpm_photo_cohort_complete 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$ RETURN TRUE;
END;$anchor$;
 replacement:=$branch$ -- Admitted capacity must retain the exact immutable receipt and predecessor.
 -- Keep this proof-only: calling the live cohort assertion here would recurse
 -- through initial_cpm_verification_start_snapshot.
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan AND state='admitted')
  AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts r
   JOIN internal.initial_cpm_photo_capacity_reservations c USING(scan_id)
   WHERE r.scan_id=p_scan AND r.owner_id=saved.owner_id AND r.admission_variant='client_prepared_photo_v1'
    AND r.candidate=saved.canonical_candidate
    AND r.configuration=internal.initial_canonical(jsonb_build_object('version',3,'assignment',saved.canonical_assignment::JSONB))
    AND r.original_admission_expires_at=saved.expires_at
    AND to_jsonb(c)=r.cpm_capacity_predecessor||jsonb_build_object('state','admitted')
    AND r.receipt_digest=internal.validate_initial_cpm_admitted_proof(r)) THEN RETURN FALSE; END IF;
 RETURN TRUE;
END;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.initial_cpm_photo_cohort_complete 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.materialize_initial_admission(uuid)'::REGPROCEDURE);
 original:=$anchor$r:=internal.build_initial_admission_receipt(p_scan);$anchor$;
 replacement:=$branch$r:=internal.build_initial_admission_receipt(p_scan);
    IF r.admission_variant='client_prepared_photo_v1' THEN
        PERFORM internal.assert_initial_cpm_receipt_cohort(r,FALSE);
    END IF;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.materialize_initial_admission 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_materialized(uuid,boolean)'::REGPROCEDURE);
 original:=$anchor$    IF p_media THEN$anchor$;
 replacement:=$branch$    IF p_media THEN
        IF r.admission_variant='client_prepared_photo_v1' THEN
            PERFORM internal.assert_initial_cpm_receipt_cohort(r,TRUE);
        END IF;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.assert_initial_admission_materialized 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_admission_live_receipt(uuid,uuid,uuid)'::REGPROCEDURE);
 original:=$anchor$internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest)$anchor$;
 replacement:=$branch$(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN internal.validate_initial_cpm_admitted_proof(r)
            ELSE internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.assert_initial_admission_live_receipt 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$    IF EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN$anchor$;
 replacement:=$branch$    IF r.admission_variant='client_prepared_photo_v1' THEN
        PERFORM internal.assert_initial_cpm_receipt_cohort(r,TRUE);
    ELSIF EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.assert_initial_admission_live_receipt 1 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$<>jsonb_array_length(r.mapping::JSONB->'objects')$anchor$;
 replacement:=$branch$<>(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN 0 ELSE jsonb_array_length(r.mapping::JSONB->'objects') END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.assert_initial_admission_live_receipt 2 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:=$anchor$'model',r.configuration::JSONB#>'{assignment,effective_model}'$anchor$;
 replacement:=$branch$'model',CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN r.configuration::JSONB#>'{assignment,configuration,effective_model}' ELSE r.configuration::JSONB#>'{assignment,effective_model}' END$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.assert_initial_admission_live_receipt 3 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;

 definition:=pg_catalog.pg_get_functiondef('internal.initial_admission_retained_receipt(uuid,uuid,uuid)'::REGPROCEDURE);
 original:=$anchor$internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest)$anchor$;
 replacement:=$branch$(CASE r.admission_variant WHEN 'client_prepared_photo_v1' THEN internal.validate_initial_cpm_admitted_proof(r)
            ELSE internal.validate_initial_admitted_proof(r.candidate,r.input,r.configuration,r.funding,
            r.outcome,r.installation,r.protocol,r.destination,r.mapping,r.media_binding,r.accounting,r.manifest) END)$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained internal.initial_admission_retained_receipt 0 source drift'; END IF;
 definition:=replace(definition,original,replacement);
 EXECUTE definition;
END; $retained$;

-- Admitted is a permanent admission footprint and conservative physical-byte
-- liability. It frees the pending-upload slot, never the retained-byte charge.
-- No admitted->released transition is installed; C1 must preserve this row.
DO $capacity_constraint$
DECLARE constraint_name TEXT;
BEGIN
 SELECT c.conname INTO STRICT constraint_name FROM pg_catalog.pg_constraint c
 WHERE c.conrelid='internal.initial_cpm_photo_capacity_reservations'::REGCLASS AND c.contype='c'
  AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
   WHERE attrelid=c.conrelid AND attname='state')]::SMALLINT[];
 EXECUTE format('ALTER TABLE internal.initial_cpm_photo_capacity_reservations DROP CONSTRAINT %I',constraint_name);
END; $capacity_constraint$;
ALTER TABLE internal.initial_cpm_photo_capacity_reservations
 ADD CONSTRAINT initial_cpm_photo_capacity_state_check CHECK(state IN ('pending','admitted','released')),
 ADD CONSTRAINT initial_cpm_photo_admitted_write_check CHECK(state<>'admitted' OR write_capability_state='may_have_issued');

DO $capacity$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.guard_initial_cpm_photo_capacity()'::REGPROCEDURE);
 original:='DECLARE owner_pending BIGINT; global_pending BIGINT; owner_retained BIGINT; global_retained BIGINT;';
 replacement:=original||E'\n receipt internal.initial_preparation_admission_receipts;';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM capacity declaration source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='SELECT count(*) FILTER(WHERE owner_id=NEW.owner_id),count(*),';
 replacement:='SELECT count(*) FILTER(WHERE owner_id=NEW.owner_id AND state=''pending''),count(*) FILTER(WHERE state=''pending''),';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM pending count source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='FROM internal.initial_cpm_photo_capacity_reservations WHERE state=''pending'';';
 replacement:='FROM internal.initial_cpm_photo_capacity_reservations WHERE state IN (''pending'',''admitted'');';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retained budget source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='  IF OLD.state=''pending'' AND OLD.write_capability_state=''never_issued''';
 replacement:=$branch$  IF OLD.state='pending' AND NEW.state='admitted' THEN
   IF OLD.owner_id IS NULL OR OLD.write_capability_state IS DISTINCT FROM 'may_have_issued'
    OR to_jsonb(NEW)-'state' IS DISTINCT FROM to_jsonb(OLD)-'state'
    OR NOT internal.initial_admission_expected_write(OLD.scan_id,
     'internal.initial_cpm_photo_capacity_reservations','UPDATE',to_jsonb(OLD),to_jsonb(NEW),FALSE) THEN
    RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
   SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=OLD.scan_id;
   IF NOT FOUND OR receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
    OR receipt.cpm_capacity_predecessor IS DISTINCT FROM to_jsonb(OLD)
    OR receipt.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(receipt) THEN
    RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
   PERFORM internal.assert_initial_cpm_receipt_cohort(receipt,FALSE);
   RETURN NEW;
  END IF;
  IF OLD.state='pending' AND OLD.write_capability_state='never_issued'$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM admitted capacity source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.retire_initial_preparation_source_objects(uuid)'::REGPROCEDURE);
 original:='WHERE scan_id=p_scan AND state=''pending'') THEN';
 replacement:='WHERE scan_id=p_scan AND state IN (''pending'',''admitted'')) THEN';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retirement capacity source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.initial_cpm_photo_retired_write_hold(uuid)'::REGPROCEDURE);
 original:='WHERE scan_id=p_scan AND state=''pending'' AND write_capability_state=''may_have_issued''';
 replacement:='WHERE scan_id=p_scan AND state IN (''pending'',''admitted'') AND write_capability_state=''may_have_issued''';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM retired liability source drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.initial_admitted_settlement_blocked(uuid)'::REGPROCEDURE);
 original:='WHERE scan_id=p_scan AND binding_version=3';
 replacement:='WHERE scan_id=p_scan AND binding_version IN (3,4)';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM settlement binding source drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan)';
 replacement:=original||E'\n  OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan AND state=''admitted'')';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'initial CPM settlement footprint source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
END; $capacity$;

-- C1 retains original physical-liability images separately from private evidence.
-- These projections confer no cancellation, funding or execution authority.
CREATE FUNCTION internal.initial_cpm_cancellation_retained_images(
 p_receipt internal.initial_preparation_admission_receipts,p_after BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE snapshot JSONB; attempts JSONB; closures JSONB;
BEGIN
 IF p_after IS NULL OR p_receipt.receipt_digest IS DISTINCT FROM internal.validate_initial_cpm_admitted_proof(p_receipt) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 snapshot:=p_receipt.cpm_retained_roles::JSONB;
 SELECT jsonb_agg(to_jsonb(w)||jsonb_build_object('retired',p_after) ORDER BY w.object_id) INTO attempts
  FROM jsonb_array_elements(snapshot->'members') m
  CROSS JOIN LATERAL jsonb_populate_record(NULL::internal.initial_cpm_photo_write_attempts,m->'attempt') w;
 SELECT jsonb_agg(to_jsonb(c) ORDER BY c.attempt_id) INTO closures
  FROM jsonb_array_elements(snapshot->'members') m
  CROSS JOIN LATERAL jsonb_populate_record(NULL::internal.initial_cpm_photo_write_closures,m->'closure') c;
 RETURN jsonb_build_object('capacity',to_jsonb(jsonb_populate_record(NULL::internal.initial_cpm_photo_capacity_reservations,
  p_receipt.cpm_capacity_predecessor))||jsonb_build_object('state','admitted'),
  'attempts',attempts,'closures',closures);
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_cancellation_retained_images(internal.initial_preparation_admission_receipts,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_cpm_cancellation_images(p_scan UUID,p_prestate JSONB,p_after BOOLEAN)
 RETURNS VOID LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE receipt internal.initial_preparation_admission_receipts; expected JSONB; actual JSONB;
BEGIN
 SELECT * INTO receipt FROM jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,
  p_prestate#>'{private_components,receipt}');
 IF p_scan IS NULL OR p_prestate->>'scan_id' IS DISTINCT FROM p_scan::TEXT
  OR receipt.scan_id IS DISTINCT FROM p_scan OR receipt.owner_id::TEXT IS DISTINCT FROM p_prestate->>'owner_id'
  OR p_prestate#>>'{private_components,admission,binding_version}' IS DISTINCT FROM '4'
  OR p_prestate->>'admission_receipt_id' IS DISTINCT FROM receipt.admission_receipt_id::TEXT
  OR p_prestate->>'admission_receipt_digest' IS DISTINCT FROM receipt.receipt_digest
  OR p_prestate->'cpm_retained' IS DISTINCT FROM internal.initial_cpm_cancellation_retained_images(receipt,FALSE) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 expected:=internal.initial_cpm_cancellation_retained_images(receipt,p_after);
 SELECT jsonb_build_object('capacity',(SELECT to_jsonb(c) FROM internal.initial_cpm_photo_capacity_reservations c WHERE scan_id=p_scan),
  'attempts',(SELECT COALESCE(jsonb_agg(to_jsonb(w) ORDER BY object_id),'[]') FROM internal.initial_cpm_photo_write_attempts w WHERE scan_id=p_scan),
  'closures',(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.attempt_id),'[]') FROM internal.initial_cpm_photo_write_closures c
   JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id) WHERE w.scan_id=p_scan)) INTO actual;
 IF actual IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_cancellation_images(UUID,JSONB,BOOLEAN)
 FROM PUBLIC,anon,authenticated,service_role;

-- A CPM destination is proven absent, not an already-retired legacy transfer.
CREATE FUNCTION internal.assert_initial_cpm_cancellation_empty_destination(p_scan UUID,p_prestate JSONB)
 RETURNS VOID LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE receipt internal.initial_preparation_admission_receipts; relation_name TEXT;
BEGIN
 SELECT * INTO receipt FROM jsonb_populate_record(NULL::internal.initial_preparation_admission_receipts,
  p_prestate#>'{private_components,receipt}');
 IF p_scan IS NULL OR p_prestate->>'scan_id' IS DISTINCT FROM p_scan::TEXT
  OR receipt.scan_id IS DISTINCT FROM p_scan OR receipt.owner_id::TEXT IS DISTINCT FROM p_prestate->>'owner_id'
  OR p_prestate#>>'{private_components,admission,binding_version}' IS DISTINCT FROM '4'
  OR p_prestate->>'admission_receipt_id' IS DISTINCT FROM receipt.admission_receipt_id::TEXT
  OR p_prestate->>'admission_receipt_digest' IS DISTINCT FROM receipt.receipt_digest
  OR p_prestate->'cpm_retained' IS DISTINCT FROM internal.initial_cpm_cancellation_retained_images(receipt,FALSE)
  OR p_prestate->'media_fence' IS DISTINCT FROM 'null'::JSONB
  OR p_prestate->'media_cohort' IS DISTINCT FROM 'null'::JSONB
  OR p_prestate->'destination_registry' IS DISTINCT FROM '[]'::JSONB THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 FOREACH relation_name IN ARRAY ARRAY['internal.initial_analysis_media_cohorts',
  'internal.initial_analysis_media_preparations','internal.initial_analysis_media_verifications',
  'internal.initial_media_copy_progress','internal.initial_media_verification_claims_v2',
  'internal.initial_media_verification_receipts_v2','internal.initial_preparation_transfer_receipts'] LOOP
  IF p_prestate->'erasure_images'->relation_name IS DISTINCT FROM '[]'::JSONB THEN
   RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_media_verification_claims_v2 WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_cancellation_empty_destination(UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

DO $cpm_cancellation$
DECLARE definition TEXT; original TEXT; replacement TEXT; signature TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.capture_initial_admitted_cancellation_prestate(uuid,uuid)'::REGPROCEDURE);
 original:='owner_epoch JSONB;'; replacement:=original||' cpm_prestate JSONB;';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 declaration drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='admitted.binding_version IS DISTINCT FROM 3'; replacement:='(admitted.binding_version IS NULL OR admitted.binding_version NOT IN (3,4))';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 binding drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='    -- All preparation source and prepared-output objects share this registry.';
 replacement:=$branch$    IF admitted.binding_version=4 THEN
        PERFORM internal.lock_initial_cpm_photo_capacity();
        PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
    END IF;
$branch$||original;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 capacity lock drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='    SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;';
 replacement:=$branch$    IF admitted.binding_version=4 THEN
        PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
        PERFORM c.attempt_id FROM internal.initial_cpm_photo_write_closures c
            JOIN internal.initial_cpm_photo_write_attempts w USING(attempt_id)
            WHERE w.scan_id=p_scan ORDER BY c.attempt_id FOR UPDATE OF c;
    END IF;
$branch$||original;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 attempt lock drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='    PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);';
 replacement:=$branch$    IF admitted.binding_version=3 THEN
        PERFORM internal.assert_initial_media_handoff_chain(p_owner,p_scan);
    ELSIF receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1' THEN
        RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000';
    END IF;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 chain drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='    RETURN jsonb_build_object(''version'',1,''authority'',''none'',''transaction_id'',pg_catalog.pg_current_xact_id()::TEXT,';
 replacement:='    cpm_prestate:=jsonb_build_object(''version'',1,''authority'',''none'',''transaction_id'',pg_catalog.pg_current_xact_id()::TEXT,';
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 image drift'; END IF;
 definition:=replace(definition,original,replacement);
 original:='        ''lifecycle'',(SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=p_scan));';
 replacement:=original||$branch$
    IF admitted.binding_version=4 THEN
        cpm_prestate:=cpm_prestate||jsonb_build_object('cpm_retained',internal.initial_cpm_cancellation_retained_images(receipt,FALSE));
        PERFORM internal.assert_initial_cpm_cancellation_images(p_scan,cpm_prestate,FALSE);
        PERFORM internal.assert_initial_cpm_cancellation_empty_destination(p_scan,cpm_prestate);
    END IF;
    RETURN cpm_prestate;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 return drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.initial_cancellation_retirement_events(internal.initial_admitted_cancellation_staging,text)'::REGPROCEDURE);
 original:='    IF p_side=''source'' THEN';
 replacement:=$branch$    IF p_side='destination' AND p_stage.prestate#>>'{private_components,receipt,admission_variant}'='client_prepared_photo_v1' THEN
        IF p_stage.owner_id::TEXT IS DISTINCT FROM p_stage.prestate->>'owner_id' THEN
            RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_initial_cpm_cancellation_empty_destination(p_stage.scan_id,p_stage.prestate);
        RETURN '[]'::JSONB;
    END IF;
$branch$||original;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 retirement drift'; END IF;
 EXECUTE replace(definition,original,replacement);

 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean,jsonb)'::REGPROCEDURE);
 original:='    IF p_events IS DISTINCT FROM ''[]''::JSONB THEN';
 replacement:=$branch$    IF p_prestate#>>'{private_components,receipt,admission_variant}'='client_prepared_photo_v1' THEN
        IF p_after IS NULL THEN RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
        IF p_side='source' THEN
            PERFORM internal.assert_initial_cpm_cancellation_images(p_scan,p_prestate,p_after);
        ELSIF p_side='destination' THEN
            IF p_events IS DISTINCT FROM '[]'::JSONB THEN
                RAISE EXCEPTION 'initial_analysis_cancellation_incomplete' USING ERRCODE='55000'; END IF;
            PERFORM internal.assert_initial_cpm_cancellation_empty_destination(p_scan,p_prestate);
            RETURN;
        END IF;
    END IF;
$branch$||original;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C1 images drift'; END IF;
 EXECUTE replace(definition,original,replacement);
 definition:=pg_catalog.pg_get_functiondef('internal.lock_initial_merge_target_terminal(uuid,uuid)'::REGPROCEDURE);
 original:='    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;';
 replacement:=$branch$    IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan) THEN
        PERFORM internal.lock_initial_cpm_photo_capacity();
        PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
    END IF;
$branch$||original;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM merge capacity lock drift'; END IF;
 EXECUTE replace(definition,original,replacement);
 -- The four-argument overload remains strict: empty events without authenticated
 -- prestate must fail. All C1 retirement/erasure/terminal owners use five arguments.
END; $cpm_cancellation$;

-- Shape permits the proven-empty CPM destination. The existing BEFORE witness
-- guard derives expected events itself; callers must submit NULL. Its captured
-- five-argument checks require the exact CPM receipt/prestate and current M1/M2
-- absence before insertion, completion and reentry. Legacy source-empty rules
-- and all finite member accounting remain unchanged.
ALTER TABLE internal.initial_cancellation_retirement_witness
 DROP CONSTRAINT initial_cancellation_retirement_witness_expected_check;
ALTER TABLE internal.initial_cancellation_retirement_witness
 ADD CONSTRAINT initial_cancellation_retirement_witness_expected_check
 CHECK(jsonb_typeof(expected)='array' AND
  (jsonb_array_length(expected) BETWEEN 2 AND 17 OR
   (side IN ('source','destination') AND expected='[]'::JSONB)));

-- The existing quota owner compares the saved CPM assignment using its original
-- time/object projection; current policy drift rejects rather than replacing it.
DO $cpm_funding_assignment$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.assert_initial_preparation_assignment(uuid,uuid,text,boolean,boolean)'::REGPROCEDURE);
 original:=' actual:=internal.resolve_initial_preparation_assignment(p_owner,p_scan,saved.canonical_candidate,p_plan,p_fallback);';
 replacement:=$branch$ IF saved.canonical_candidate::JSONB->>'variant'='client_prepared_photo' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging s WHERE s.scan_id=p_scan
   AND s.owner_id=p_owner AND s.admission_variant='client_prepared_photo_v1'
   AND s.transaction_id=pg_catalog.pg_current_xact_id()
   AND s.stage_token::TEXT=current_setting('merian.initial_admission_stage',TRUE)
   AND s.assignment=saved.canonical_assignment AND s.candidate=saved.canonical_candidate) THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  actual:=internal.resolve_initial_cpm_photo_assignment(p_owner,p_scan,saved.canonical_candidate,p_plan,p_fallback,
   saved.created_at,(SELECT jsonb_agg(m->'object_id' ORDER BY ordinal)
    FROM jsonb_array_elements(saved.canonical_assignment::JSONB#>'{preparation,role_mapping}') WITH ORDINALITY e(m,ordinal)));
 ELSE
  actual:=internal.resolve_initial_preparation_assignment(p_owner,p_scan,saved.canonical_candidate,p_plan,p_fallback);
 END IF;$branch$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM funding assignment source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
END; $cpm_funding_assignment$;

-- Enroll the closed CPM assignment in the same C8/C4/provider witnesses.
DO $cpm_accounting_dispatch$
DECLARE definition TEXT; original TEXT; replacement TEXT; signature TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY['internal.reserve_ai_quota_core(uuid,text,uuid,text)',
  'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'] LOOP
  definition:=pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
  original:=$a$WHERE scan_id=p_request_id AND canonical_assignment::JSONB->>'version'='3'$a$;
  replacement:=$b$WHERE scan_id=p_request_id AND (canonical_assignment::JSONB->>'version'='3'
   OR (canonical_assignment::JSONB->>'version'='1' AND canonical_assignment::JSONB->>'variant'='client_prepared_photo'))$b$;
  IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM accounting dispatch source drift'; END IF;
  EXECUTE replace(definition,original,replacement);
 END LOOP;
 definition:=pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE);
 original:=$a$IF (SELECT canonical_assignment::JSONB->>'version' FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id)='3' THEN$a$;
 replacement:=$b$IF EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_request_id
  AND (canonical_assignment::JSONB->>'version'='3' OR (canonical_assignment::JSONB->>'version'='1'
   AND canonical_assignment::JSONB->>'variant'='client_prepared_photo'))) THEN$b$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM C8 dispatch source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
 definition:=pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE);
 original:='atomic_stage.assignment::JSONB';
 replacement:=$b$(CASE atomic_stage.admission_variant WHEN 'client_prepared_photo_v1' THEN atomic_stage.assignment::JSONB->'configuration' ELSE atomic_stage.assignment::JSONB END)$b$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>5 THEN RAISE EXCEPTION 'CPM provider assignment source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
 definition:=pg_catalog.pg_get_functiondef('internal.finish_initial_admission(uuid)'::REGPROCEDURE);
 original:=$a$    IF final_checked_at<(s.phase_window::JSONB->>'anchor_ms')::NUMERIC
        OR final_checked_at>=(s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC THEN$a$;
 replacement:=$b$    IF (s.admission_variant='client_prepared_photo_v1' AND
         (s.original_admission_expires_at IS NULL
          OR final_checked_at<(s.assignment::JSONB->>'created_at_ms')::NUMERIC
          OR final_checked_at>=extract(epoch FROM s.original_admission_expires_at)*1000))
        OR (s.admission_variant='server_prepared_v3' AND
         (final_checked_at<(s.phase_window::JSONB->>'anchor_ms')::NUMERIC
          OR final_checked_at>=(s.phase_window::JSONB#>>'{cutoffs,admission}')::NUMERIC)) THEN$b$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM final admission deadline source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
END; $cpm_accounting_dispatch$;

DO $cpm_submission_storage$
DECLARE definition TEXT; original TEXT; replacement TEXT;
BEGIN
 definition:=pg_catalog.pg_get_functiondef('internal.guard_initial_analysis_storage()'::REGPROCEDURE);
 original:=$a$    IF TG_TABLE_NAME='initial_analysis_submissions' THEN
      IF EXISTS($a$;
 replacement:=$b$    IF TG_TABLE_NAME='initial_analysis_submissions' THEN
      IF NEW.input_schema_version=2 THEN
        IF internal.parse_initial_cpm_photo_content(internal.initial_canonical(NEW.input_snapshot))->>'scan_id'
             IS DISTINCT FROM NEW.scan_id::TEXT
          OR NEW.ordered_descriptions IS DISTINCT FROM NEW.input_snapshot->'contexts' THEN
          RAISE EXCEPTION 'initial_analysis_description_invalid' USING ERRCODE='22023'; END IF;
      ELSIF NEW.input_schema_version IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
      ELSIF EXISTS($b$;
 IF (length(definition)-length(replace(definition,original,'')))/length(original)<>1 THEN RAISE EXCEPTION 'CPM submission guard source drift'; END IF;
 EXECUTE replace(definition,original,replacement);
END; $cpm_submission_storage$;

-- Coordinated storage union: constructors, exact witnesses, retained liability
-- and C1 comparisons above must precede this private persistence branch.
-- No endpoint or execution permission is installed by these constraints.
ALTER TABLE internal.initial_preparation_admission_staging
 ALTER COLUMN outcome DROP NOT NULL, ALTER COLUMN installation DROP NOT NULL,
 ALTER COLUMN protocol DROP NOT NULL, ALTER COLUMN destination DROP NOT NULL,
 ALTER COLUMN phase_window DROP NOT NULL, ALTER COLUMN mapping DROP NOT NULL,
 ALTER COLUMN media_binding DROP NOT NULL;
ALTER TABLE internal.initial_preparation_admission_receipts
 ALTER COLUMN outcome DROP NOT NULL, ALTER COLUMN installation DROP NOT NULL,
 ALTER COLUMN protocol DROP NOT NULL, ALTER COLUMN destination DROP NOT NULL,
 ALTER COLUMN mapping DROP NOT NULL, ALTER COLUMN media_binding DROP NOT NULL,
 DROP CONSTRAINT initial_preparation_admission_receipts_check,
 ADD CONSTRAINT initial_admission_receipt_variant_proof CHECK (
  receipt_digest = CASE admission_variant
   WHEN 'server_prepared_v3' THEN internal.validate_initial_admitted_proof(candidate,input,configuration,funding,
    outcome,installation,protocol,destination,mapping,media_binding,accounting,manifest)
   WHEN 'client_prepared_photo_v1' THEN internal.validate_initial_cpm_admitted_proof(initial_preparation_admission_receipts.*)
  END);
ALTER TABLE internal.initial_analysis_submissions
 DROP CONSTRAINT initial_analysis_submissions_input_schema_version_check,
 ADD CONSTRAINT initial_submission_input_variant CHECK (
  input_schema_version=1 OR (input_schema_version=2
   AND internal.parse_initial_cpm_photo_content(internal.initial_canonical(input_snapshot))->>'scan_id'=scan_id::TEXT
   AND ordered_descriptions IS NOT DISTINCT FROM input_snapshot->'contexts'));
ALTER TABLE internal.initial_analysis_admissions
 DROP CONSTRAINT initial_analysis_admissions_binding_version_check,
 ADD CONSTRAINT initial_analysis_admissions_binding_version_check CHECK (binding_version IN (1,2,3,4)),
 DROP CONSTRAINT initial_analysis_admissions_check,
 ADD CONSTRAINT initial_admission_input_variant_digest CHECK (submission_digest=CASE WHEN binding_version=4
  THEN internal.initial_cpm_photo_digest('content',canonical_input)
  ELSE internal.initial_digest('input',canonical_input) END);
DO $binding$
DECLARE definition TEXT;
BEGIN
 SELECT pg_catalog.pg_get_constraintdef(oid) INTO STRICT definition FROM pg_catalog.pg_constraint
  WHERE conrelid='internal.initial_analysis_admissions'::REGCLASS AND conname='initial_admission_preparation_version';
 IF (length(definition)-length(replace(definition,'binding_version = 3','')))/length('binding_version = 3')<>1 THEN
  RAISE EXCEPTION 'initial CPM admission binding constraint drift'; END IF;
 ALTER TABLE internal.initial_analysis_admissions DROP CONSTRAINT initial_admission_preparation_version;
 EXECUTE 'ALTER TABLE internal.initial_analysis_admissions ADD CONSTRAINT initial_admission_preparation_version '
  ||replace(definition,'binding_version = 3','binding_version IN (3,4)');
END; $binding$;

RESET lock_timeout;
RESET statement_timeout;

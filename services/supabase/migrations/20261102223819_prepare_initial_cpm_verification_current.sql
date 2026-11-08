-- Dormant complete-cohort observation for the original fresh verifier only.
-- No renewed start, stored state, media access lease, funding or execution authority.
SET statement_timeout='60s';
SET lock_timeout='5s';
CREATE FUNCTION internal.initial_cpm_verification_current_response_schema() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"outcome":{"type":"string","max_bytes":7,"enum":["current"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"attempt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"snapshot_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}}$json$::JSONB; $schema$;
REVOKE ALL ON FUNCTION internal.initial_cpm_verification_current_response_schema() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_cpm_verification_current(
 p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_attempt UUID,p_snapshot_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents;
 capacity internal.initial_cpm_photo_capacity_reservations;
 a JSONB; snapshot TEXT; digest TEXT; result JSONB; now_at TIMESTAMPTZ;
BEGIN
 PERFORM internal.require_service_role();
 IF p_owner IS NULL OR p_scan IS NULL OR p_attempt IS NULL
  OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$'
  OR p_snapshot_digest IS NULL OR p_snapshot_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo'
  OR num_nonnulls(saved.cpm_verification_attempt_id,saved.cpm_verification_started_at,saved.cpm_verification_snapshot_digest)<>3
  OR saved.cpm_verification_attempt_id IS DISTINCT FROM p_attempt
  OR saved.cpm_verification_snapshot_digest IS DISTINCT FROM p_snapshot_digest THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 SELECT * INTO STRICT capacity FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context WHERE scan_id=p_scan)
  OR capacity.owner_id IS DISTINCT FROM p_owner OR capacity.state IS DISTINCT FROM 'pending'
  OR capacity.write_capability_state IS DISTINCT FROM 'may_have_issued' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 a:=internal.parse_initial_cpm_photo_assignment(saved.canonical_candidate,saved.canonical_assignment);
 IF saved.assignment_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('assignment',saved.canonical_assignment)
  OR saved.candidate_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('candidate',saved.canonical_candidate) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 now_at:=clock_timestamp();
 IF now_at<saved.cpm_verification_started_at OR now_at>=saved.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 snapshot:=internal.initial_cpm_verification_start_snapshot(p_owner,p_scan);
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex');
 IF digest IS DISTINCT FROM p_snapshot_digest OR digest IS DISTINCT FROM saved.cpm_verification_snapshot_digest THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
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

 result:=jsonb_build_object('version',1,'outcome','current','authority','none','owner_id',p_owner,
  'scan_id',p_scan,'assignment_digest',p_assignment_digest,'attempt_id',p_attempt,'snapshot_digest',digest);
 IF NOT internal.initial_schema_matches(result,internal.initial_cpm_verification_current_response_schema()) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 now_at:=clock_timestamp();
 IF now_at<saved.cpm_verification_started_at OR now_at>=saved.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_verification_current(UUID,UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.assert_initial_cpm_photo_verification_current(
 p_owner UUID,p_scan UUID,p_assignment_digest TEXT,p_attempt UUID,p_snapshot_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.assert_initial_cpm_verification_current(p_owner,p_scan,p_assignment_digest,p_attempt,p_snapshot_digest);
END; $$;
REVOKE ALL ON FUNCTION public.assert_initial_cpm_photo_verification_current(UUID,UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.assert_initial_cpm_photo_verification_current(UUID,UUID,TEXT,UUID,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.assert_initial_cpm_photo_verification_current(uuid,uuid,text,uuid,text)',
  'Dormant exact committed verification-start/current-cohort observation; no fresh start, renewed deadline, lease or execution authority');
RESET lock_timeout;
RESET statement_timeout;

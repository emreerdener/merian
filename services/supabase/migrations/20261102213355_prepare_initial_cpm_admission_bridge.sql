-- Dormant service-only CPM bridge. No client proof route or runtime activation.
-- The fixed server verifier supplies evidence; SQL rederives every stored fact.
SET statement_timeout='60s';
SET lock_timeout='5s';
CREATE FUNCTION internal.initial_cpm_admission_bridge_response_schema() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $schema$ SELECT $json${"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"outcome":{"type":"string","max_bytes":10,"enum":["unadmitted","admitted"]},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"candidate_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$","nullable":true},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$","nullable":true}}}$json$::JSONB; $schema$;
REVOKE ALL ON FUNCTION internal.initial_cpm_admission_bridge_response_schema() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.initial_cpm_admission_bridge_response(
 p_saved internal.initial_analysis_preparation_intents,p_receipt internal.initial_preparation_admission_receipts
) RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE result JSONB;
BEGIN
 result:=jsonb_build_object('version',1,'variant','client_prepared_photo','authority','none',
  'outcome',CASE WHEN p_receipt.admission_receipt_id IS NULL THEN 'unadmitted' ELSE 'admitted' END,
  'owner_id',p_saved.owner_id,'scan_id',p_saved.scan_id,'candidate_digest',p_saved.candidate_digest,
  'assignment_digest',p_saved.assignment_digest,'admission_receipt_id',p_receipt.admission_receipt_id,
  'admission_receipt_digest',p_receipt.receipt_digest);
 IF NOT internal.initial_schema_matches(result,internal.initial_cpm_admission_bridge_response_schema())
  OR (p_receipt.admission_receipt_id IS NULL) IS DISTINCT FROM (p_receipt.receipt_digest IS NULL) THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_admission_bridge_response(internal.initial_analysis_preparation_intents,internal.initial_preparation_admission_receipts)
 FROM PUBLIC,anon,authenticated,service_role;

-- Serialize first. Missing or contradictory state is never conclusive absence.
-- Historical receipt validation never checks fresh eligibility or elapsed time.
CREATE FUNCTION internal.read_initial_cpm_admission_state(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_assignment_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; admitted internal.initial_analysis_admissions;
 receipt internal.initial_preparation_admission_receipts;
BEGIN
 PERFORM internal.require_service_role();
 IF p_candidate IS NULL OR octet_length(p_candidate) NOT BETWEEN 1 AND 1048576
  OR p_assignment IS NULL OR octet_length(p_assignment) NOT BETWEEN 1 AND 65536
  OR p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.canonical_candidate IS DISTINCT FROM p_candidate
  OR saved.canonical_assignment IS DISTINCT FROM p_assignment OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.parse_initial_cpm_photo_assignment(saved.canonical_candidate,saved.canonical_assignment);
 IF saved.assignment_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('assignment',saved.canonical_assignment)
  OR saved.candidate_digest IS DISTINCT FROM internal.initial_cpm_photo_digest('candidate',saved.canonical_candidate) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO admitted FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 SELECT * INTO receipt FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
 IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 IF admitted.scan_id IS NOT NULL OR receipt.scan_id IS NOT NULL THEN
  IF admitted.owner_id IS DISTINCT FROM p_owner OR admitted.binding_version IS DISTINCT FROM 4
   OR receipt.owner_id IS DISTINCT FROM p_owner OR receipt.admission_variant IS DISTINCT FROM 'client_prepared_photo_v1'
   OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan
    AND state IN ('pending_pre_dispatch','dispatch_authorized')) THEN
   RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
  receipt:=internal.initial_admission_retained_receipt(p_owner,p_scan,receipt.admission_receipt_id);
  PERFORM internal.assert_initial_cpm_receipt_cohort(receipt,TRUE);
 ELSE
  PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
   OR NOT internal.initial_cpm_photo_cohort_complete(p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_admission_incomplete' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN internal.initial_cpm_admission_bridge_response(saved,receipt);
END; $$;
REVOKE ALL ON FUNCTION internal.read_initial_cpm_admission_state(UUID,UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_initial_cpm_photo_admission(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_assignment_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.read_initial_cpm_admission_state(p_owner,p_scan,p_candidate,p_assignment,p_assignment_digest);
END; $$;

CREATE FUNCTION public.begin_initial_cpm_photo_admission(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_assignment_digest TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE state JSONB;
BEGIN
 PERFORM internal.require_service_role();
 state:=internal.read_initial_cpm_admission_state(p_owner,p_scan,p_candidate,p_assignment,p_assignment_digest);
 IF state->>'outcome'='admitted' THEN RETURN jsonb_build_object('version',1,'outcome','held','authority','none'); END IF;
 RETURN internal.begin_initial_cpm_photo_verification(p_owner,p_scan,p_assignment_digest);
END; $$;

CREATE FUNCTION public.admit_initial_cpm_photo(
 p_owner UUID,p_scan UUID,p_candidate TEXT,p_assignment TEXT,p_assignment_digest TEXT,p_verification TEXT,p_ip_hash TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE state JSONB; saved internal.initial_analysis_preparation_intents;
 receipt internal.initial_preparation_admission_receipts; token UUID; input JSONB; configuration JSONB;
 old_stage TEXT; old_funding TEXT; old_admission TEXT; old_compared TEXT;
BEGIN
 PERFORM internal.require_service_role();
 IF p_verification IS NULL OR octet_length(p_verification) NOT BETWEEN 1 AND 65536
  OR p_ip_hash IS NULL OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 state:=internal.read_initial_cpm_admission_state(p_owner,p_scan,p_candidate,p_assignment,p_assignment_digest);
 IF state->>'outcome'='admitted' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan AND cpm_verification=p_verification) THEN
   RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  RETURN state;
 END IF;
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 input:=saved.canonical_candidate::JSONB; configuration:=saved.canonical_assignment::JSONB->'configuration';
 old_stage:=current_setting('merian.initial_admission_stage',TRUE);
 old_funding:=current_setting('merian.initial_preparation_funding',TRUE);
 old_admission:=current_setting('merian.initial_analysis_admission',TRUE);
 old_compared:=current_setting('merian.initial_preparation_compared',TRUE);
 token:=internal.create_initial_admission_stage(p_owner,p_scan,p_assignment_digest,p_verification);
 PERFORM set_config('merian.initial_admission_stage',token::TEXT,TRUE);
 PERFORM set_config('merian.initial_preparation_funding',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 PERFORM set_config('merian.initial_analysis_admission',p_owner::TEXT||':'||p_scan::TEXT,TRUE);
 -- Media is never description-only. Saved protocols, processor and profile are
 -- compared again by original C8/C4/provider owners before their first mutation.
 PERFORM * FROM public.reserve_identification_quota(p_owner,'scan_identification',p_scan,p_ip_hash,p_scan,
  FALSE,(input#>>'{admission,client_protocol}')::INTEGER,FALSE,configuration->>'input_profile',
  input#>>'{admission,expected_processor_permission}',(input#>>'{admission,identification_protocol}')::INTEGER);
 PERFORM internal.materialize_initial_admission(p_scan);
 PERFORM internal.freeze_initial_admission_ledger(p_scan);
 PERFORM internal.begin_initial_admission_consumption(p_scan);
 receipt:=internal.finish_initial_admission(p_scan);
 PERFORM set_config('merian.initial_admission_stage',COALESCE(old_stage,''),TRUE);
 PERFORM set_config('merian.initial_preparation_funding',COALESCE(old_funding,''),TRUE);
 PERFORM set_config('merian.initial_analysis_admission',COALESCE(old_admission,''),TRUE);
 PERFORM set_config('merian.initial_preparation_compared',COALESCE(old_compared,''),TRUE);
 -- No exception handler may turn partial funding into a committed held reply.
 -- PostgREST sends success only after transaction commit, including its guards.
 RETURN internal.initial_cpm_admission_bridge_response(saved,receipt);
END; $$;

REVOKE ALL ON FUNCTION public.read_initial_cpm_photo_admission(UUID,UUID,TEXT,TEXT,TEXT),
 public.begin_initial_cpm_photo_admission(UUID,UUID,TEXT,TEXT,TEXT),
 public.admit_initial_cpm_photo(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_initial_cpm_photo_admission(UUID,UUID,TEXT,TEXT,TEXT),
 public.begin_initial_cpm_photo_admission(UUID,UUID,TEXT,TEXT,TEXT),
 public.admit_initial_cpm_photo(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.read_initial_cpm_photo_admission(uuid,uuid,text,text,text)','Dormant exact CPM admission observation; no fresh verification or execution authority'),
 ('service_role','public.begin_initial_cpm_photo_admission(uuid,uuid,text,text,text)','Dormant fixed CPM verification begin; only fresh committed acknowledgement authorizes server verification'),
 ('service_role','public.admit_initial_cpm_photo(uuid,uuid,text,text,text,text,text)','Dormant trusted verifier CPM atomic admission; original funding owners, no authenticated client proof endpoint');
RESET lock_timeout;
RESET statement_timeout;

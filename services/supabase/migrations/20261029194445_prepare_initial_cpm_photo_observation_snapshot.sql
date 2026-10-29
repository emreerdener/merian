SET statement_timeout='2min';
SET lock_timeout='5s';

-- Inactive database-owner read boundary for the existing observation coordinator.
-- No public facade, API grant, claim acquisition, signer or settlement action.
CREATE FUNCTION internal.read_initial_cpm_photo_observation(
 p_attempt UUID,p_outcome TEXT,p_claim UUID,p_expected JSONB DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts;
 r internal.initial_preparation_source_registry;
 b internal.initial_preparation_source_backends;
 i internal.initial_analysis_preparation_intents;
 owner_id UUID; member JSONB; target JSONB; claim JSONB; result JSONB;
BEGIN
 IF p_attempt IS NULL OR p_outcome IS NULL OR p_outcome NOT IN ('live_object','retired_marker')
  OR (p_outcome='retired_marker')<>(p_claim IS NOT NULL) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 -- Match settlement's outer order. Retired reads need no erased private intent.
 IF p_outcome='live_object' THEN
  SELECT x.owner_id INTO owner_id FROM internal.initial_analysis_preparation_intents x WHERE scan_id=a.scan_id;
  IF owner_id IS NULL THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.lock_initial_preparation_scope(owner_id,a.scan_id);
 END IF;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 SELECT * INTO r FROM internal.initial_preparation_source_registry WHERE object_id=a.object_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 IF a.state<>'may_have_issued' OR a.write_policy_digest IS NULL
  OR r.scan_id IS DISTINCT FROM a.scan_id OR r.backend_generation IS DISTINCT FROM a.backend_generation THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.initial_cpm_photo_write_policies p
  JOIN internal.initial_preparation_backend_eligibility e ON e.generation=p.backend_generation
  WHERE p.digest=a.write_policy_digest AND p.state='eligible' AND e.state='eligible'
   AND p.backend_generation=a.backend_generation
   AND p.backend_configuration_digest=a.backend_configuration_digest
   AND e.configuration_digest=a.backend_configuration_digest FOR SHARE OF p,e NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO b FROM internal.initial_preparation_source_backends
  WHERE generation=a.backend_generation AND configuration_digest=a.backend_configuration_digest;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF p_outcome='live_object' THEN
  IF a.retired OR r.retired OR r.marker_confirmed OR r.claim_token IS NOT NULL
   OR clock_timestamp()>=a.admission_expires_at OR NOT internal.initial_cpm_photo_cohort_complete(a.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_preparation_unfunded(owner_id,a.scan_id);
  SELECT * INTO i FROM internal.initial_analysis_preparation_intents WHERE scan_id=a.scan_id;
  SELECT m INTO STRICT member FROM jsonb_array_elements(i.canonical_assignment::JSONB#>'{preparation,role_mapping}') m
   WHERE m->>'object_id'=a.object_id::TEXT;
  target:=jsonb_build_object('outcome',p_outcome,'role',member->>'role',
   'byte_count',(member#>>'{declaration,byte_count}')::BIGINT,
   'content_type',member#>>'{declaration,declared_content_type}','sha256',member#>>'{declaration,sha256}');
  claim:=NULL;
 ELSE
  IF NOT a.retired OR NOT r.retired OR r.marker_confirmed
   OR r.claim_token IS DISTINCT FROM p_claim OR r.claim_expires_at<=clock_timestamp() THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  target:=jsonb_build_object('outcome',p_outcome);
  -- Existing claim guard derives its lower bound from expiry minus one minute.
  -- Ceil the lower bound and floor expiry: never enlarge the valid interval.
  -- The original token remains the identity; no claim is acquired or renewed.
  claim:=jsonb_build_object('token',p_claim,
   'issued_at_ms',ceil(extract(epoch FROM r.claim_expires_at-INTERVAL '1 minute')*1000)::BIGINT,
   'expires_at_ms',floor(extract(epoch FROM r.claim_expires_at)*1000)::BIGINT);
 END IF;
 result:=jsonb_build_object('binding',jsonb_build_object(
  'attempt_id',a.attempt_id,'scan_id',a.scan_id,'object_id',a.object_id,
  'assignment_digest',a.assignment_digest,'backend_generation',a.backend_generation,
  'backend_configuration_digest',a.backend_configuration_digest,
  'issued_at_ms',ceil(extract(epoch FROM a.issued_at)*1000)::BIGINT,
  'verification_policy_digest',a.write_policy_digest),
  'target',target,'backend',jsonb_build_object('generation',b.generation,
   'configuration_digest',b.configuration_digest,'provider',b.provider,
   'direct_endpoint',b.direct_endpoint,'private_bucket',b.private_bucket,
   'namespace',b.namespace,'credential_profile',b.credential_profile,'storage_protocol',b.storage_protocol),
  'admission_expires_at_ms',floor(extract(epoch FROM a.admission_expires_at)*1000)::BIGINT,
  'erasure_claim',claim);
 IF p_expected IS NOT NULL AND p_expected IS DISTINCT FROM result THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION internal.read_initial_cpm_photo_observation(UUID,TEXT,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.read_initial_cpm_photo_observation(UUID,TEXT,UUID,JSONB) IS
 'Inactive exact original CPM observation snapshot/current check. Owner only; each call is a short transaction with no network IO. Explicit original claim, conservative temporal projection, no receipt/closure/release authority. No production adapter installed.';
RESET lock_timeout;
RESET statement_timeout;

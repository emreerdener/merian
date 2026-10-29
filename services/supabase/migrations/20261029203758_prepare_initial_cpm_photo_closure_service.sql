SET statement_timeout='2min';
SET lock_timeout='5s';

-- Dormant server boundary. No policies/installations are seeded, no route or
-- signer is installed, and no issuance, renewal or release operation is added.
CREATE FUNCTION internal.initial_cpm_photo_closure_reply(p_saved internal.initial_cpm_photo_write_closures)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_saved.attempt_id IS NULL THEN NULL ELSE jsonb_build_object(
  'attempt_id',p_saved.attempt_id,'outcome',p_saved.outcome,'policy_digest',p_saved.policy_digest,
  'observed_at',to_char(p_saved.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'claim_digest',p_saved.claim_digest) END;
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_closure_reply(internal.initial_cpm_photo_write_closures)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_initial_cpm_photo_write_closure(p_attempt UUID,p_outcome TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE saved internal.initial_cpm_photo_write_closures;
BEGIN
 PERFORM internal.require_service_role();
 IF p_attempt IS NULL OR p_outcome IS NULL OR p_outcome NOT IN ('live_object','retired_marker') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 -- Permanent content-free receipts precede fresh lifecycle/eligibility checks.
 -- Reading a receipt never grants fresh IO, even after private/account erasure.
 SELECT * INTO saved FROM internal.initial_cpm_photo_write_closures
  WHERE attempt_id=p_attempt AND outcome=p_outcome;
 RETURN internal.initial_cpm_photo_closure_reply(saved);
END; $$;

CREATE FUNCTION public.read_initial_cpm_photo_observation(p_attempt UUID,p_outcome TEXT,p_claim UUID,p_expected JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 IF p_expected IS NOT NULL AND (jsonb_typeof(p_expected)<>'object' OR octet_length(p_expected::TEXT)>8192) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 -- Caller already owns this exact token. Never discover, acquire or renew one.
 RETURN internal.read_initial_cpm_photo_observation(p_attempt,p_outcome,p_claim,p_expected);
END; $$;

CREATE FUNCTION public.settle_initial_cpm_photo_write_closure(
 p_attempt UUID,p_policy TEXT,p_outcome TEXT,p_observed_at TEXT,p_claim UUID
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE observed TIMESTAMPTZ; saved internal.initial_cpm_photo_write_closures;
BEGIN
 PERFORM internal.require_service_role();
 IF p_policy IS NULL OR p_policy !~ '^[0-9a-f]{64}$' OR p_observed_at IS NULL
  OR p_observed_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 observed:=p_observed_at::TIMESTAMPTZ;
 IF NOT isfinite(observed) OR to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')<>p_observed_at THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 saved:=internal.settle_initial_cpm_photo_write_closure(p_attempt,p_policy,p_outcome,observed,p_claim);
 RETURN internal.initial_cpm_photo_closure_reply(saved);
END; $$;

DO $grants$ DECLARE signature TEXT; BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.read_initial_cpm_photo_write_closure(uuid,text)',
  'public.read_initial_cpm_photo_observation(uuid,text,uuid,jsonb)',
  'public.settle_initial_cpm_photo_write_closure(uuid,text,text,text,uuid)'
 ] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',signature);
  INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose)
   VALUES('service_role',signature,'Dormant exact CPM observation/closure bridge; original claim and historical microsecond receipt recovery, no signer or release');
 END LOOP;
END; $grants$;
COMMENT ON FUNCTION public.read_initial_cpm_photo_write_closure(UUID,TEXT) IS
 'Service-only content-free exact receipt or null; usable after retirement/revocation/erasure, never fresh IO authority.';
COMMENT ON FUNCTION public.read_initial_cpm_photo_observation(UUID,TEXT,UUID,JSONB) IS
 'Service-only fresh snapshot/current check under existing SQL fences; original caller-owned token only, no claim acquisition or renewal.';
COMMENT ON FUNCTION public.settle_initial_cpm_photo_write_closure(UUID,TEXT,TEXT,TEXT,UUID) IS
 'Service-only exact closure through existing owner; canonical six-digit UTC timestamp preserves historical microseconds. No route/signer/activation.';
RESET lock_timeout;
RESET statement_timeout;

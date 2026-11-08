SET statement_timeout='2min';
SET lock_timeout='5s';

-- Dormant service boundary. No policy, signer, credentials or route is installed.
-- Only this transaction's bound -> may_have_issued transition returns fresh.
-- The caller must receive COMMIT acknowledgement before any signer IO. A lost
-- acknowledgement after COMMIT replays held. Rollback leaves no transition;
-- unknown outcomes never authorize signing or automatic retry.
CREATE FUNCTION public.begin_initial_cpm_photo_write(
 p_owner UUID,p_scan UUID,p_digest TEXT,p_object UUID,p_policy TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts; observation JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF p_policy IS NULL OR p_policy !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 -- Reuse owner/scan -> capacity -> registry -> attempt ordering. Locks stay
 -- held across inspection, policy binding, advancement and snapshot projection.
 a:=internal.initial_cpm_photo_write_action('bind',p_owner,p_scan,p_digest,p_object);
 IF a.write_policy_digest IS NOT NULL AND a.write_policy_digest<>p_policy THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 IF a.state='may_have_issued' OR a.retired OR a.write_closed THEN
  RETURN jsonb_build_object('outcome','held','attempt_id',a.attempt_id);
 END IF;
 a:=internal.bind_initial_cpm_photo_write_policy(p_owner,a.attempt_id,p_policy);
 a:=internal.initial_cpm_photo_write_action('may_have_issued',p_owner,p_scan,p_digest,p_object);
 observation:=internal.read_initial_cpm_photo_observation(a.attempt_id,'live_object',NULL,NULL);
 RETURN jsonb_build_object('outcome','fresh','attempt_id',a.attempt_id,
  'observation',observation,
  'created_at_ms',floor(extract(epoch FROM a.created_at)*1000)::BIGINT,
  'capability_expires_at_ms',floor(extract(epoch FROM a.capability_expires_at)*1000)::BIGINT);
END; $$;
REVOKE ALL ON FUNCTION public.begin_initial_cpm_photo_write(UUID,UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.begin_initial_cpm_photo_write(UUID,UUID,TEXT,UUID,TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose)
 VALUES('service_role','public.begin_initial_cpm_photo_write(uuid,uuid,text,uuid,text)',
  'Dormant fresh-only CPM possible-issuance transition; replay is held, no signer, refresh or release');
COMMENT ON FUNCTION public.begin_initial_cpm_photo_write(UUID,UUID,TEXT,UUID,TEXT) IS
 'Fresh only for this atomic transition; commit acknowledgement required before future qualified signer IO. Committed replay is held with no snapshot; unavailable/cancelled scope can deny. Unknown outcomes do not authorize automatic retry. Exact clocks, original role, no installed signer/route or activation.';
RESET lock_timeout;
RESET statement_timeout;

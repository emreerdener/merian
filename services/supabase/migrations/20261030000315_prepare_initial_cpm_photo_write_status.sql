SET statement_timeout='2min';
SET lock_timeout='5s';

-- Dormant observation boundary for exact recovery. No bearer capability and no
-- transition: even a missing attempt does not authorize a new begin or PUT.
CREATE FUNCTION public.read_initial_cpm_photo_write_status(
 p_owner UUID,p_scan UUID,p_digest TEXT,p_object UUID
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts;
BEGIN
 PERFORM internal.require_service_role();
 IF p_digest IS NULL OR p_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 -- Reuse owner/scan -> capacity -> registry -> attempt locks and denial fences.
 -- The status branch never inserts, advances, renews, verifies or releases.
 a:=internal.initial_cpm_photo_write_action('status',p_owner,p_scan,p_digest,p_object);
 IF a.attempt_id IS NOT NULL AND (a.scan_id IS DISTINCT FROM p_scan
  OR a.object_id IS DISTINCT FROM p_object OR a.assignment_digest IS DISTINCT FROM p_digest) THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('version',1,'authority','none','scan_id',p_scan,
  'assignment_digest',p_digest,'object_id',p_object,
  'attempt',CASE WHEN a.attempt_id IS NULL THEN NULL ELSE jsonb_build_object(
   'attempt_id',a.attempt_id,'state',a.state,
   'created_at_ms',floor(extract(epoch FROM a.created_at)*1000)::BIGINT,
   'capability_expires_at_ms',floor(extract(epoch FROM a.capability_expires_at)*1000)::BIGINT,
   'write_closed',a.write_closed) END);
END; $$;
REVOKE ALL ON FUNCTION public.read_initial_cpm_photo_write_status(UUID,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_initial_cpm_photo_write_status(UUID,UUID,TEXT,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose)
 VALUES('service_role','public.read_initial_cpm_photo_write_status(uuid,uuid,text,uuid)',
  'Dormant exact non-transition CPM status; no bearer, issuance, retry, verification or release authority');
COMMENT ON FUNCTION public.read_initial_cpm_photo_write_status(UUID,UUID,TEXT,UUID) IS
 'Exact saved role status under existing owner/account/deletion/cancellation fences. Missing, bound, issued and closed are observations only. Original clocks and capacity unchanged, no backend/configuration or credentials exposed. No installed route or native consumer.';
RESET lock_timeout;
RESET statement_timeout;

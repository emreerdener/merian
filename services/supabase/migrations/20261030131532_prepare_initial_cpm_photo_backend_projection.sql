SET statement_timeout='2min';
SET lock_timeout='5s';

-- Negotiated metadata only. Existing private v1 callers remain byte-shape compatible.
CREATE FUNCTION internal.initial_cpm_photo_recovery_schema_v3() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SET search_path='' AS $$
 SELECT $schema${"allocated":{"type":"object","properties":{"version":{"type":"integer","minimum":3,"maximum":3},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"outcome":{"type":"string","max_bytes":24,"enum":["allocated"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"assignment_canonical":{"type":"string","max_bytes":65536},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_configuration_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"terminal_held":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"variant":{"type":"string","max_bytes":24,"enum":["client_prepared_photo"]},"outcome":{"type":"string","max_bytes":24,"enum":["terminal_held"]},"authority":{"type":"string","max_bytes":4,"enum":["none"]},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"reason":{"type":"string","max_bytes":16,"enum":["not_found","expired","cancelled"]}}}}$schema$::JSONB;
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_recovery_schema_v3() FROM PUBLIC,anon,authenticated,service_role;

-- Invoked only after the existing lifecycle owner acquired its transaction
-- locks. No eligibility lookup, current selector, clock renewal or authority.
CREATE FUNCTION internal.initial_cpm_photo_bound_response(p_owner UUID,p_scan UUID,p_response JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; assignment JSONB;
 saved_generation UUID; configuration TEXT; response JSONB;
BEGIN
 IF p_response->>'outcome'='terminal_held' THEN
  IF NOT internal.initial_schema_matches(p_response,internal.initial_cpm_photo_recovery_schema_v1()->'terminal_held')
   OR p_response->>'scan_id' IS DISTINCT FROM p_scan::TEXT THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  RETURN p_response;
 END IF;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner THEN
  RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM internal.parse_initial_cpm_photo_recovery(saved.canonical_candidate,
  internal.initial_canonical(p_response),saved.canonical_assignment);
 IF p_response->>'assignment_digest' IS DISTINCT FROM saved.assignment_digest THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 assignment:=saved.canonical_assignment::JSONB;
 saved_generation:=(assignment#>>'{preparation,backend_generation}')::UUID;
 SELECT configuration_digest INTO configuration FROM internal.initial_preparation_source_backends WHERE generation=saved_generation;
 IF NOT FOUND OR configuration IS NULL OR NOT internal.initial_cpm_photo_cohort_complete(p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry r WHERE r.scan_id=p_scan AND r.backend_generation IS DISTINCT FROM saved_generation) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 response:=p_response||jsonb_build_object('version',3,'backend_generation',saved_generation,'backend_configuration_digest',configuration);
 IF NOT internal.initial_schema_matches(response,internal.initial_cpm_photo_recovery_schema_v3()->'allocated') THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN response;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_bound_response(UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.create_initial_cpm_photo_v3_allocation(p_owner UUID,p_scan UUID,p_candidate TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE response JSONB;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.parse_initial_cpm_photo_candidate(p_candidate);
 response:=public.create_initial_preparation_intent(p_owner,p_scan,p_candidate);
 RETURN internal.initial_cpm_photo_bound_response(p_owner,p_scan,response);
END; $$;
REVOKE ALL ON FUNCTION public.create_initial_cpm_photo_v3_allocation(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_initial_cpm_photo_v3_allocation(UUID,UUID,TEXT) TO service_role;

CREATE FUNCTION public.get_initial_cpm_photo_v3_status(p_owner UUID,p_scan UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE response JSONB;
BEGIN
 PERFORM internal.require_service_role();
 response:=public.get_initial_preparation_status(p_owner,p_scan);
 RETURN internal.initial_cpm_photo_bound_response(p_owner,p_scan,response);
END; $$;
REVOKE ALL ON FUNCTION public.get_initial_cpm_photo_v3_status(UUID,UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_initial_cpm_photo_v3_status(UUID,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.create_initial_cpm_photo_v3_allocation(uuid,uuid,text)','Negotiated CPM metadata projection through existing allocation owner; no upload or execution authority'),
 ('service_role','public.get_initial_cpm_photo_v3_status(uuid,uuid)','Exact saved CPM backend metadata through existing recovery owner; no renewal or fresh issuance');
COMMENT ON FUNCTION public.create_initial_cpm_photo_v3_allocation(UUID,UUID,TEXT) IS
 'Inactive negotiated backend tuple. Saved assignment generation and immutable registry only. Legacy RPCs unchanged; no installed native caller or storage capability.';
COMMENT ON FUNCTION public.get_initial_cpm_photo_v3_status(UUID,UUID) IS
 'Inactive exact recovery, including original backend tuple after rotation or revocation. Existing lifecycle owner may terminalize expiry. No capability or release authority.';
RESET lock_timeout;
RESET statement_timeout;

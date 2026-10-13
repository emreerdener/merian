-- Pure admitted media proof parity. No stored issuance, I/O or execution authority.
SET lock_timeout='5s';
SET statement_timeout='30s';
CREATE FUNCTION internal.initial_media_handoff_proof_schema() RETURNS JSONB
LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $f$
SELECT $json${"claim":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"binding":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"submission_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"outcome_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"mapping_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"phase_window":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"handoff_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"handoff_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"anchor_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"original_expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"cutoffs":{"type":"object","properties":{"admission":{"type":"integer","minimum":0,"maximum":9007199254740991},"copy":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_claim":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_settlement":{"type":"integer","minimum":0,"maximum":9007199254740991},"transfer":{"type":"integer","minimum":0,"maximum":9007199254740991},"reconciliation":{"type":"integer","minimum":0,"maximum":9007199254740991},"protocol_margin":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"claim_token":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"verification_receipt":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"claim":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"binding":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"submission_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"outcome_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"mapping_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"phase_window":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"handoff_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"handoff_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"anchor_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"original_expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"cutoffs":{"type":"object","properties":{"admission":{"type":"integer","minimum":0,"maximum":9007199254740991},"copy":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_claim":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_settlement":{"type":"integer","minimum":0,"maximum":9007199254740991},"transfer":{"type":"integer","minimum":0,"maximum":9007199254740991},"reconciliation":{"type":"integer","minimum":0,"maximum":9007199254740991},"protocol_margin":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"claim_token":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"claim_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"objects":{"type":"array","max_items":10,"items":{"type":"object","properties":{"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}}},"authorized_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"transfer_receipt":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_receipt":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"claim":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"binding":{"type":"object","properties":{"version":{"type":"integer","minimum":2,"maximum":2},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"submission_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"assignment_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"outcome_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"mapping_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"destination_backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"phase_window":{"type":"object","properties":{"version":{"type":"integer","minimum":1,"maximum":1},"owner_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"scan_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"admission_receipt_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"handoff_profile_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"handoff_installation_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"protocol_artifact_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"anchor_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"original_expires_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991},"cutoffs":{"type":"object","properties":{"admission":{"type":"integer","minimum":0,"maximum":9007199254740991},"copy":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_claim":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification":{"type":"integer","minimum":0,"maximum":9007199254740991},"verification_settlement":{"type":"integer","minimum":0,"maximum":9007199254740991},"transfer":{"type":"integer","minimum":0,"maximum":9007199254740991},"reconciliation":{"type":"integer","minimum":0,"maximum":9007199254740991},"protocol_margin":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"phase_window_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"}}},"admission_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"verification_adapter_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"claim_token":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"issued_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"claim_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"objects":{"type":"array","max_items":10,"items":{"type":"object","properties":{"object_id":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"backend_generation":{"type":"string","max_bytes":36,"pattern":"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"},"byte_count":{"type":"integer","minimum":1,"maximum":12582912},"sha256":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"content_type":{"type":"string","max_bytes":128,"enum":["image/jpeg","image/png","image/webp","image/heic","image/heif","audio/wav","video/mp4"]}}}},"authorized_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"verification_receipt_digest":{"type":"string","max_bytes":64,"pattern":"^[0-9a-f]{64}$"},"authorized_at_ms":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}$json$::JSONB;
$f$;

CREATE FUNCTION internal.parse_initial_media_handoff_proof(p_kind TEXT,p_text TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE v JSONB; cap INTEGER; shape JSONB;
BEGIN
 cap:=CASE p_kind WHEN 'claim' THEN 32768 WHEN 'verification_receipt' THEN 65536 WHEN 'transfer_receipt' THEN 98304 END;
 IF cap IS NULL OR p_text IS NULL OR pg_catalog.octet_length(p_text)>cap THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 BEGIN v:=p_text::JSONB;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END;
 shape:=internal.initial_media_handoff_proof_schema()->p_kind;
 IF internal.initial_canonical(v) IS DISTINCT FROM p_text OR NOT internal.initial_schema_matches(v,shape) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 IF p_kind='claim' THEN
  PERFORM internal.parse_initial_admission_metadata('media_binding',internal.initial_canonical(v->'binding'));
 ELSIF p_kind='verification_receipt' THEN
  IF pg_catalog.jsonb_array_length(v->'objects')=0 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
  PERFORM internal.parse_initial_media_handoff_proof('claim',internal.initial_canonical(v->'claim'));
 ELSE
  PERFORM internal.parse_initial_media_handoff_proof('verification_receipt',internal.initial_canonical(v->'verification_receipt'));
 END IF;
 RETURN v;
END; $$;

CREATE FUNCTION internal.initial_media_handoff_proof_digest(p_kind TEXT,p_text TEXT)
RETURNS TEXT LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE domain_name TEXT;
BEGIN
 PERFORM internal.parse_initial_media_handoff_proof(p_kind,p_text);
 domain_name:=CASE p_kind WHEN 'claim' THEN 'verification-claim.v2' WHEN 'verification_receipt' THEN 'verification-receipt.v2' WHEN 'transfer_receipt' THEN 'transfer-receipt.v1' END;
 RETURN pg_catalog.encode(extensions.digest(pg_catalog.convert_to('merian.initial-analysis.handoff.'||domain_name||pg_catalog.chr(10)||p_text,'UTF8'),'sha256'),'hex');
END; $$;

-- Fixed independent TEXT components: no aggregate canonical proof or trusted caller context.
-- Later documents must be SQL NULL when validating an earlier stage.
CREATE FUNCTION internal.validate_initial_media_handoff_proof(
 p_kind TEXT,p_candidate TEXT,p_input TEXT,p_configuration TEXT,p_funding TEXT,p_outcome TEXT,
 p_installation TEXT,p_protocol TEXT,p_destination TEXT,p_mapping TEXT,p_media_binding TEXT,
 p_accounting TEXT,p_manifest TEXT,p_claim TEXT,p_verification_receipt TEXT,p_transfer_receipt TEXT
) RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE claim JSONB; receipt JSONB; transfer JSONB; binding JSONB; mapping JSONB;
 admitted_digest TEXT; claim_digest TEXT; receipt_digest TEXT; expected_objects JSONB; canonical TEXT;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('claim','verification_receipt','transfer_receipt')
  OR (p_kind='claim' AND (p_verification_receipt IS NOT NULL OR p_transfer_receipt IS NOT NULL))
  OR (p_kind='verification_receipt' AND p_transfer_receipt IS NOT NULL) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 claim:=internal.parse_initial_media_handoff_proof('claim',p_claim);
 IF p_kind<>'claim' THEN receipt:=internal.parse_initial_media_handoff_proof('verification_receipt',p_verification_receipt); END IF;
 IF p_kind='transfer_receipt' THEN transfer:=internal.parse_initial_media_handoff_proof('transfer_receipt',p_transfer_receipt); END IF;
 admitted_digest:=internal.validate_initial_admitted_proof(p_candidate,p_input,p_configuration,p_funding,p_outcome,p_installation,p_protocol,p_destination,p_mapping,p_media_binding,p_accounting,p_manifest);
 binding:=p_media_binding::JSONB; mapping:=p_mapping::JSONB;
 IF internal.initial_canonical(claim->'binding') IS DISTINCT FROM p_media_binding
  OR claim->>'admission_receipt_digest' IS DISTINCT FROM admitted_digest
  OR claim->'verification_adapter_digest' IS DISTINCT FROM p_configuration::JSONB#>'{assignment,handoff,profile,verification_adapter_digest}'
  OR (claim->>'issued_at_ms')::NUMERIC<(p_manifest::JSONB->>'authorized_at_ms')::NUMERIC
  OR (claim->>'issued_at_ms')::NUMERIC>=(binding#>>'{phase_window,cutoffs,verification_claim}')::NUMERIC THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
 END IF;
 claim_digest:=internal.initial_media_handoff_proof_digest('claim',p_claim);
 canonical:=p_claim;
 IF p_kind<>'claim' THEN
  SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('object_id',o->'object_id','backend_generation',mapping->'destination_backend_generation')||(o->'bytes') ORDER BY ordinal)
  INTO expected_objects FROM pg_catalog.jsonb_array_elements(mapping->'objects') WITH ORDINALITY AS x(o,ordinal);
  IF internal.initial_canonical(receipt->'claim') IS DISTINCT FROM p_claim
   OR receipt->>'claim_digest' IS DISTINCT FROM claim_digest
   OR receipt->'objects' IS DISTINCT FROM expected_objects
   OR (receipt->>'authorized_at_ms')::NUMERIC<(claim->>'issued_at_ms')::NUMERIC
   OR (receipt->>'authorized_at_ms')::NUMERIC>=(binding#>>'{phase_window,cutoffs,verification_settlement}')::NUMERIC THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
  END IF;
  receipt_digest:=internal.initial_media_handoff_proof_digest('verification_receipt',p_verification_receipt);
  canonical:=p_verification_receipt;
 END IF;
 IF p_kind='transfer_receipt' THEN
  IF transfer->>'admission_receipt_digest' IS DISTINCT FROM admitted_digest
   OR transfer->'protocol_artifact_digest' IS DISTINCT FROM binding#>'{phase_window,protocol_artifact_digest}'
   OR internal.initial_canonical(transfer->'verification_receipt') IS DISTINCT FROM p_verification_receipt
   OR transfer->>'verification_receipt_digest' IS DISTINCT FROM receipt_digest
   OR (transfer->>'authorized_at_ms')::NUMERIC<(receipt->>'authorized_at_ms')::NUMERIC
   OR (transfer->>'authorized_at_ms')::NUMERIC>=(binding#>>'{phase_window,cutoffs,transfer}')::NUMERIC THEN
   RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023';
  END IF;
  canonical:=p_transfer_receipt;
 END IF;
 RETURN pg_catalog.jsonb_build_object('authority','none','canonical',canonical,'digest',internal.initial_media_handoff_proof_digest(p_kind,canonical));
END; $$;

REVOKE ALL ON FUNCTION internal.initial_media_handoff_proof_schema(),
 internal.parse_initial_media_handoff_proof(TEXT,TEXT),internal.initial_media_handoff_proof_digest(TEXT,TEXT),
 internal.validate_initial_media_handoff_proof(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;
RESET lock_timeout;
RESET statement_timeout;

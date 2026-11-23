SET lock_timeout='5s';
SET statement_timeout='2min';

-- Scheduling only. The original job, provider attempt and funding reservation
-- remain unchanged; the existing entitlement finalizer is still the only seal.
CREATE TABLE internal.private_capture_finalization_leases (
 scan_id UUID PRIMARY KEY REFERENCES internal.ordinary_initial_evidence(scan_id) ON DELETE CASCADE,
 retry_at TIMESTAMPTZ NOT NULL
);
ALTER TABLE internal.private_capture_finalization_leases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.private_capture_finalization_leases FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX ordinary_initial_private_finalization_candidates
 ON internal.ordinary_initial_evidence(created_at,scan_id)
 WHERE private_capture_request_sha256 IS NOT NULL AND accepted_result IS NOT NULL
 AND retired_at IS NULL AND sealed_at IS NULL;

CREATE FUNCTION public.claim_private_capture_finalizations(p_limit INTEGER DEFAULT 5)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE candidate RECORD; saved internal.ordinary_initial_evidence;
 intent public.scan_ingestion_intents; witness internal.capture_source_admissions;
 request JSONB; accepted JSONB; output JSONB:='[]'; claimed INTEGER:=0;
BEGIN
 PERFORM internal.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 5 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 FOR candidate IN
  SELECT e.scan_id,e.owner_id FROM internal.ordinary_initial_evidence e
  LEFT JOIN internal.private_capture_finalization_leases l USING(scan_id)
  WHERE e.private_capture_request_sha256 IS NOT NULL AND e.accepted_result IS NOT NULL
   AND e.retired_at IS NULL AND e.sealed_at IS NULL
   AND (l.retry_at IS NULL OR l.retry_at<=clock_timestamp())
  ORDER BY e.created_at,e.scan_id LIMIT p_limit*4
 LOOP
  -- Match retirement -> owner -> scan -> evidence -> job/intent order. A busy
  -- owner/scan is skipped, never waited on while another owner's locks are held.
  IF NOT pg_try_advisory_xact_lock(hashtextextended('merian-capture-account-retirement:'||candidate.owner_id::TEXT,0)) THEN CONTINUE; END IF;
  PERFORM id FROM public.users WHERE id=candidate.owner_id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||candidate.scan_id::TEXT,0)) THEN CONTINUE; END IF;
  SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=candidate.scan_id FOR UPDATE;
  IF NOT FOUND OR saved.owner_id IS DISTINCT FROM candidate.owner_id OR saved.retired_at IS NOT NULL
   OR saved.sealed_at IS NOT NULL OR saved.accepted_result IS NULL OR saved.private_capture_request_sha256 IS NULL
   OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=candidate.owner_id)
   OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=candidate.scan_id)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=candidate.scan_id)
   OR EXISTS(SELECT 1 FROM internal.private_capture_finalization_leases WHERE scan_id=candidate.scan_id AND retry_at>clock_timestamp()) THEN CONTINUE; END IF;
  -- Also delay malformed candidates. They stay held, without terminalization,
  -- so a bad row cannot indefinitely starve other accepted observations.
  INSERT INTO internal.private_capture_finalization_leases(scan_id,retry_at)
   VALUES(saved.scan_id,clock_timestamp()+interval '5 minutes')
   ON CONFLICT(scan_id) DO UPDATE SET retry_at=EXCLUDED.retry_at;
  BEGIN
   request:=jsonb_build_object('schema_version',1,'scan_id',saved.scan_id,'generation',saved.generation,
    'evidence_manifest',saved.evidence_manifest,'evidence_digest',saved.evidence_digest);
   -- Reuses exact request, live original job/intent, retirement, ready-artifact
   -- and accepted-result digest checks. This never invokes a provider.
   accepted:=public.recover_owned_initial_result(saved.owner_id,request);
   SELECT * INTO intent FROM public.scan_ingestion_intents WHERE scan_id=saved.scan_id::TEXT AND user_id=saved.owner_id;
   SELECT * INTO witness FROM internal.capture_source_admissions WHERE scan_id=saved.scan_id AND owner_id=saved.owner_id;
   IF accepted IS NULL OR saved.evidence_manifest->'schema_version' IS DISTINCT FROM '9'::JSONB
    OR witness.scan_id IS NULL OR witness.retired_at IS NOT NULL
    OR witness.recovery->>'kind' IS DISTINCT FROM 'private_capture_stage_v1'
    OR intent.payload_schema_version IS DISTINCT FROM 4
    OR intent.request_payload IS DISTINCT FROM witness.recovery#>'{intent,request_payload}'
    OR intent.payload_checksum IS DISTINCT FROM witness.recovery#>>'{intent,payload_checksum}'
    OR intent.payload_checksum IS DISTINCT FROM saved.payload_checksum
    OR intent.request_payload#>>'{privateCaptureStage,requestSHA256}' IS DISTINCT FROM saved.private_capture_request_sha256
    OR intent.request_payload#>>'{privateCaptureStage,generation}' IS DISTINCT FROM saved.generation::TEXT
    OR intent.request_payload->'initialEvidence' IS DISTINCT FROM request
    OR jsonb_typeof(intent.request_payload->'telemetry') IS DISTINCT FROM 'object'
    OR (intent.request_payload#>>'{telemetry,geoprivacy}' IN ('open','obscured','private')) IS NOT TRUE THEN
     CONTINUE;
   END IF;
   output:=output||jsonb_build_array(jsonb_build_object('schema_version',1,'owner_id',saved.owner_id,
    'request',request,'telemetry',intent.request_payload->'telemetry'));
   claimed:=claimed+1;
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' OR SQLSTATE 'P0002' THEN
   -- An immutable or missing-proof conflict is held for diagnosis/recovery.
   -- Lease expiry never retires it or settles its original funding reservation.
   NULL;
  END;
  EXIT WHEN claimed>=p_limit;
 END LOOP;
 RETURN output;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_private_capture_finalizations(INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_private_capture_finalizations(INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.claim_private_capture_finalizations(integer)','Lease accepted private capture results for finalization only; preserve original jobs, provider attempts and funding.');

RESET statement_timeout;
RESET lock_timeout;

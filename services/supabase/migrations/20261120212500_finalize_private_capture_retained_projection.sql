SET lock_timeout='5s';
SET statement_timeout='2min';

-- Called inside the existing entitlement completion transaction, which owns
-- account/owner/scan fences. Private V4 never falls back to public-media proof.
CREATE FUNCTION internal.private_capture_finalization_ready(p_scan UUID,p_owner UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE job public.scan_ingestion_jobs; intent public.scan_ingestion_intents;
 witness internal.capture_source_admissions; evidence internal.ordinary_initial_evidence;
 scan public.scans; contract JSONB; receipt JSONB; artifacts JSONB; expected JSONB;
BEGIN
 IF current_setting('merian.complimentary_completion_fence',true) IS DISTINCT FROM p_owner::TEXT||':'||p_scan::TEXT
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=p_scan) THEN RETURN FALSE; END IF;
 SELECT * INTO job FROM public.scan_ingestion_jobs WHERE scan_id=p_scan::TEXT AND user_id=p_owner;
 SELECT * INTO intent FROM public.scan_ingestion_intents WHERE scan_id=p_scan::TEXT AND user_id=p_owner;
 SELECT * INTO witness FROM internal.capture_source_admissions WHERE scan_id=p_scan AND owner_id=p_owner;
 SELECT * INTO evidence FROM internal.ordinary_initial_evidence WHERE scan_id=p_scan AND owner_id=p_owner;
 SELECT * INTO scan FROM public.scans WHERE id=p_scan AND user_id=p_owner;
 IF job.id IS NULL OR intent.scan_id IS NULL OR witness.scan_id IS NULL OR evidence.scan_id IS NULL OR scan.id IS NULL
  OR intent.payload_schema_version IS DISTINCT FROM 4 OR intent.request_payload->'schemaVersion' IS DISTINCT FROM '4'::JSONB
  OR witness.retired_at IS NOT NULL OR witness.recovery->>'kind' IS DISTINCT FROM 'private_capture_stage_v1'
  OR intent.request_payload IS DISTINCT FROM witness.recovery#>'{intent,request_payload}'
  OR intent.payload_checksum IS DISTINCT FROM witness.recovery#>>'{intent,payload_checksum}'
  OR evidence.payload_checksum IS DISTINCT FROM intent.payload_checksum
  OR evidence.job_id IS DISTINCT FROM job.id OR evidence.generation IS DISTINCT FROM job.initial_evidence_generation
  OR evidence.evidence_manifest->'schema_version' IS DISTINCT FROM '9'::JSONB
  OR evidence.allocated_at IS NULL OR evidence.retired_at IS NOT NULL OR evidence.sealed_at IS NOT NULL
  OR evidence.accepted_result IS NULL OR evidence.accepted_result_digest IS DISTINCT FROM
    encode(extensions.digest(convert_to(jsonb_build_object('result',evidence.accepted_result,'species_id',evidence.accepted_species_id)::TEXT,'UTF8'),'sha256'),'hex')
  OR job.media_counts IS DISTINCT FROM internal.private_capture_media_counts(evidence.evidence_manifest)
  OR intent.media_counts IS DISTINCT FROM job.media_counts
  OR job.media_object_keys IS DISTINCT FROM '{"image":[],"audio":[],"video":[]}'::JSONB
  OR intent.media_object_keys IS DISTINCT FROM job.media_object_keys
  OR job.upload_session_ids IS DISTINCT FROM '{}'::UUID[] OR intent.upload_session_ids IS DISTINCT FROM '{}'::UUID[]
  OR scan.image_storage_urls IS DISTINCT FROM '{}'::TEXT[] OR scan.video_storage_urls IS DISTINCT FROM '{}'::TEXT[]
  OR scan.audio_storage_urls IS DISTINCT FROM '{}'::TEXT[] OR scan.captured_media IS DISTINCT FROM '[]'::JSONB
  OR EXISTS(SELECT 1 FROM public.scan_media_assets WHERE scan_id=p_scan OR client_scan_id=p_scan) THEN RETURN FALSE; END IF;
 expected:=jsonb_build_object('schema_version',1,'scan_id',p_scan,'generation',evidence.generation,
   'evidence_digest',evidence.evidence_digest,'evidence_manifest',evidence.evidence_manifest);
 IF intent.request_payload->'initialEvidence' IS DISTINCT FROM expected
  OR intent.request_payload#>'{privateCaptureStage,generation}' IS DISTINCT FROM to_jsonb(evidence.generation) THEN RETURN FALSE; END IF;
 contract:=internal.initial_evidence_contract(evidence.evidence_manifest,p_scan::TEXT,evidence.generation::TEXT);
 IF contract->>'evidence_digest' IS DISTINCT FROM evidence.evidence_digest THEN RETURN FALSE; END IF;
 receipt:=internal.ordinary_initial_evidence_receipt(evidence);
 SELECT COALESCE(jsonb_agg(x-'object_id'-'ready' ORDER BY n),'[]'::JSONB) INTO artifacts
  FROM jsonb_array_elements(receipt->'items') WITH ORDINALITY AS items(x,n);
 RETURN artifacts IS NOT DISTINCT FROM contract->'items'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB);
END;
$$;
REVOKE ALL ON FUNCTION internal.private_capture_finalization_ready(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'::regprocedure);
 anchor:='    IF NOT internal.scan_canonical_media_projection_complete(p_scan_id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_finalization_join_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=p_scan_id::TEXT
        AND (payload_schema_version=4 OR request_payload ? 'privateCaptureStage'))
      OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=p_scan_id
        AND recovery->>'kind'='private_capture_stage_v1') THEN
        IF NOT internal.private_capture_finalization_ready(p_scan_id,p_user_id) THEN
            RAISE EXCEPTION 'canonical_scan_media_incomplete' USING ERRCODE='55000';
        END IF;
    ELSIF NOT internal.scan_canonical_media_projection_complete(p_scan_id) THEN
$body$);
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;

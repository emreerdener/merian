SET lock_timeout='5s';
SET statement_timeout='2min';

-- Provider counts are a projection of the sealed ordered graph, never inferred
-- from the deliberately empty public object-key arrays in the private successor.
CREATE FUNCTION internal.private_capture_media_counts(p_manifest JSONB)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object(
  'image_count',count(*) FILTER(WHERE x->>'kind'='image')+COALESCE(sum(jsonb_array_length(x->'frames')) FILTER(WHERE x->>'kind'='video'),0),
  'audio_count',count(*) FILTER(WHERE x->>'kind'='audio' OR (x->>'kind'='video' AND x->'audio'<>'null'::JSONB)),
  'video_count',count(*) FILTER(WHERE x->>'kind'='video'),
  'required_video_count',count(*) FILTER(WHERE x->>'kind'='video'),
  'video_frame_count',COALESCE(sum(jsonb_array_length(x->'frames')) FILTER(WHERE x->>'kind'='video'),0),
  'video_inference_frame_count',COALESCE(sum(jsonb_array_length(x->'frames')) FILTER(WHERE x->>'kind'='video'),0),
  'has_description',count(*) FILTER(WHERE x->>'kind'='description')>0)
 FROM jsonb_array_elements(p_manifest->'items') x;
$$;

-- Reached only from the existing begin transaction, after account/owner/scan
-- fences. The same immutable admission witness and all-writer guards apply.
CREATE FUNCTION internal.prepare_private_capture_stage_admission(
 p_owner UUID,p_scan UUID,p_endpoint TEXT,p_payload JSONB,p_counts JSONB,p_keys JSONB,
 p_storage TEXT[],p_resumable BOOLEAN,p_inline BOOLEAN,p_redacted JSONB,p_schema INTEGER
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE saved internal.capture_source_admissions; stage internal.initial_capture_audio_stages;
 proof JSONB; request JSONB; contract JSONB; identity JSONB; payload JSONB; projection JSONB; manifest TEXT; checksum TEXT; contexts JSONB;
BEGIN
 IF p_schema IS DISTINCT FROM 4 OR p_endpoint IS DISTINCT FROM 'identify-multimodal'
  OR p_resumable IS DISTINCT FROM TRUE OR p_inline IS DISTINCT FROM FALSE
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::TEXT)>2097152
  OR NOT(p_payload ?& ARRAY['schemaVersion','clientScanId','endpoint','privateCaptureStage','initialEvidence','media','mediaCounts','redactedMediaCounts','uploadSessionIds','observationContexts','telemetry'])
  OR p_payload-ARRAY['schemaVersion','clientScanId','endpoint','privateCaptureStage','initialEvidence','media','mediaCounts','redactedMediaCounts','uploadSessionIds','observationContexts','telemetry','preferredGoal','manifestChecksum']<>'{}'
  OR p_payload->'schemaVersion' IS DISTINCT FROM '4'::JSONB
  OR p_payload->>'clientScanId' IS DISTINCT FROM p_scan::TEXT OR p_payload->>'endpoint' IS DISTINCT FROM p_endpoint
  OR p_keys IS DISTINCT FROM '{"image":[],"audio":[],"video":[]}'::JSONB
  OR p_storage IS DISTINCT FROM '{}'::TEXT[] OR p_payload->'uploadSessionIds' IS DISTINCT FROM '[]'::JSONB
  OR p_payload->'media' IS DISTINCT FROM '{"r2ObjectKeys":[],"audioR2ObjectKeys":[],"videoR2ObjectKeys":[]}'::JSONB
  OR p_redacted IS DISTINCT FROM '{"image_base64_count":0,"audio_base64_count":0}'::JSONB
  OR p_payload->'redactedMediaCounts' IS DISTINCT FROM p_redacted OR p_payload->'mediaCounts' IS DISTINCT FROM p_counts
  OR jsonb_typeof(p_payload->'telemetry') IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023'; END IF;
 proof:=p_payload->'privateCaptureStage'; request:=p_payload->'initialEvidence';
 IF jsonb_typeof(proof) IS DISTINCT FROM 'object' OR NOT(proof ?& ARRAY['version','generation','requestSHA256'])
  OR proof-ARRAY['version','generation','requestSHA256']<>'{}' OR proof->'version' IS DISTINCT FROM '1'::JSONB
  OR jsonb_typeof(proof->'requestSHA256') IS DISTINCT FROM 'string' OR proof->>'requestSHA256' !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(request) IS DISTINCT FROM 'object'
  OR NOT(request ?& ARRAY['schema_version','scan_id','generation','evidence_manifest','evidence_digest'])
  OR request-ARRAY['schema_version','scan_id','generation','evidence_manifest','evidence_digest']<>'{}'
  OR request->'schema_version' IS DISTINCT FROM '1'::JSONB OR request->>'scan_id' IS DISTINCT FROM p_scan::TEXT
  OR request->'generation' IS DISTINCT FROM proof->'generation'
  OR request#>'{evidence_manifest,schema_version}' IS DISTINCT FROM '9'::JSONB THEN
  RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023'; END IF;
 contract:=internal.initial_evidence_contract(request->'evidence_manifest',p_scan::TEXT,request->>'generation');
 SELECT COALESCE(jsonb_agg(jsonb_build_object('freeText',x->'text') ORDER BY n),'[]'::JSONB) INTO contexts
  FROM jsonb_array_elements(request#>'{evidence_manifest,items}') WITH ORDINALITY AS items(x,n) WHERE x->>'kind'='description';
 IF contract->>'evidence_digest' IS DISTINCT FROM request->>'evidence_digest'
  OR internal.private_capture_media_counts(request->'evidence_manifest') IS DISTINCT FROM p_counts
  OR contexts IS DISTINCT FROM p_payload->'observationContexts' THEN
  RAISE EXCEPTION 'capture_source_admission_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO saved FROM internal.capture_source_admissions WHERE scan_id=p_scan;
 IF EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=p_scan)
  OR (saved.scan_id IS NOT NULL AND (saved.owner_id<>p_owner OR saved.retired_at IS NOT NULL)) THEN
  RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000'; END IF;
 identity:=jsonb_build_object('endpoint',p_endpoint,'payload',p_payload-'manifestChecksum',
  'mediaCounts',p_counts,'mediaObjectKeys',p_keys,'storageKeys',to_jsonb(p_storage),'resumable',p_resumable,
  'inlineMediaRedacted',p_inline,'redactedMediaCounts',p_redacted,'schema',p_schema);
 IF saved.scan_id IS NOT NULL THEN
  IF saved.recovery->>'kind' IS DISTINCT FROM 'private_capture_stage_v1' OR identity IS DISTINCT FROM saved.recovery->'identity' THEN
   RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000'; END IF;
  -- Cold replay after retained adoption must use the original witness, without
  -- requiring or recreating erased stage rows or mutable public staging assets.
  RETURN saved.recovery->'intent';
 END IF;
 IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=p_scan::TEXT)
  OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=p_scan::TEXT) THEN
  RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000'; END IF;
 SELECT * INTO stage FROM internal.initial_capture_audio_stages WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR stage.owner_id IS DISTINCT FROM p_owner OR stage.generation::TEXT IS DISTINCT FROM proof->>'generation'
  OR stage.request_sha256 IS DISTINCT FROM proof->>'requestSHA256' OR stage.adopted_evidence_digest IS NOT NULL THEN
  RAISE EXCEPTION 'capture_source_admission_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_capture_client_stage(p_scan,true);
 PERFORM internal.assert_initial_capture_audio_retention(p_owner,request);
 manifest:=encode(sha256(convert_to(jsonb_build_object('privateCaptureStage',proof,'evidenceDigest',request->'evidence_digest','mediaCounts',p_counts)::TEXT,'UTF8')),'hex');
 payload:=p_payload||jsonb_build_object('manifestChecksum',manifest);
 checksum:=encode(sha256(convert_to(payload::TEXT,'UTF8')),'hex');
 projection:=jsonb_build_object('endpoint',p_endpoint,'payload_schema_version',4,'request_payload',payload,
  'media_counts',p_counts,'media_object_keys',p_keys,'upload_session_ids','[]'::JSONB,'manifest_checksum',manifest,
  'payload_checksum',checksum,'inline_media_redacted',false,'redacted_media_counts',p_redacted);
 INSERT INTO internal.capture_source_admissions(scan_id,owner_id,recovery)
  VALUES(p_scan,p_owner,jsonb_build_object('kind','private_capture_stage_v1','identity',identity,'intent',projection,'stage_backend_sha256',stage.backend_sha256));
 RETURN projection;
END;
$$;
REVOKE ALL ON FUNCTION internal.private_capture_media_counts(JSONB),
 internal.prepare_private_capture_stage_admission(UUID,UUID,TEXT,JSONB,JSONB,JSONB,TEXT[],BOOLEAN,BOOLEAN,JSONB,INTEGER)
 FROM PUBLIC,anon,authenticated,service_role;

DO $join$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.prepare_capture_source_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)'::regprocedure);
 anchor:='    -- Caller holds account intake -> owner -> scan fences.';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_admission_dispatch_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF p_schema=4 OR COALESCE(p_payload ? 'privateCaptureStage',false)
        OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=p_scan AND recovery->>'kind'='private_capture_stage_v1') THEN
        RETURN internal.prepare_private_capture_stage_admission(p_owner,p_scan,p_endpoint,p_payload,p_counts,p_keys,
            p_storage,p_resumable,p_inline,p_redacted,p_schema);
    END IF;
$body$||anchor);
 definition:=pg_get_functiondef('internal.guard_capture_source_admission()'::regprocedure);
 anchor:='ARRAY[''captureSourceObservations'',''captureSourceProofs'']';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_guard_identity_drift'; END IF;
 definition:=replace(definition,anchor,'ARRAY[''captureSourceObservations'',''captureSourceProofs'',''privateCaptureStage'']');
 anchor:='    IF saved.scan_id IS NULL THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_guard_witness_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
        IF actual#>'{request_payload,privateCaptureStage}' IS NOT NULL OR actual->'payload_schema_version'='4'::JSONB
            OR EXISTS(SELECT 1 FROM internal.initial_capture_audio_stages WHERE scan_id=scan AND client_inventory_at IS NOT NULL) THEN
            RAISE EXCEPTION 'capture_source_admission_conflict' USING ERRCODE='55000';
        END IF;
$body$);
END;
$join$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- One private stage owns the complete frozen plan. Client-known artifacts have
-- a separate capability/inventory from server-produced DSP outputs.
ALTER TABLE internal.initial_capture_audio_stages
 ADD COLUMN client_inventory_at TIMESTAMPTZ,
 ADD COLUMN preparation_claimed_at TIMESTAMPTZ;
CREATE TABLE internal.initial_capture_client_stage_objects (
 object_id UUID PRIMARY KEY,
 scan_id UUID NOT NULL REFERENCES internal.initial_capture_audio_stages(scan_id),
 media_id UUID NOT NULL UNIQUE,
 position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 127),
 artifact JSONB NOT NULL,
 write_issued_at TIMESTAMPTZ,
 ready_at TIMESTAMPTZ,
 UNIQUE(scan_id,position),
 CHECK(artifact->>'media_id'=media_id::TEXT),
 CHECK(artifact->>'role' IN('source_image','prepared_image','source_audio','source_video','playback_video','inference_frame','source_companion_audio')),
 CHECK(ready_at IS NULL OR write_issued_at IS NOT NULL)
);
ALTER TABLE internal.initial_capture_client_stage_objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_capture_client_stage_objects FROM PUBLIC,anon,authenticated,service_role;

-- The canonical parser enforces per-role, cohort and aggregate bounds. Compare
-- the complete ordered inventory as well as each individual ready marker.
CREATE FUNCTION internal.assert_initial_capture_client_stage(p_scan UUID,p_ready BOOLEAN)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_capture_audio_stages; expected JSONB; actual JSONB;
BEGIN
 SELECT * INTO stage FROM internal.initial_capture_audio_stages WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR stage.retired_at IS NOT NULL OR stage.client_inventory_at IS NULL THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 expected:=internal.initial_capture_plan_contract(stage.owner_id,stage.request_body->'plan')->'uploads';
 SELECT COALESCE(jsonb_agg(artifact ORDER BY position),'[]'::JSONB) INTO actual
  FROM internal.initial_capture_client_stage_objects WHERE scan_id=p_scan;
 IF actual IS DISTINCT FROM expected OR (p_ready AND EXISTS(
  SELECT 1 FROM internal.initial_capture_client_stage_objects WHERE scan_id=p_scan AND ready_at IS NULL)) THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
END;
$$;
CREATE FUNCTION internal.initial_capture_client_stage_receipt(p_scan UUID,p_media UUID)
RETURNS JSONB LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('request_sha256',s.request_sha256,'object_id',o.object_id,
  'artifact',o.artifact,'write_issued',o.write_issued_at IS NOT NULL,'ready',o.ready_at IS NOT NULL)
 FROM internal.initial_capture_audio_stages s JOIN internal.initial_capture_client_stage_objects o USING(scan_id)
 WHERE s.scan_id=p_scan AND o.media_id=p_media AND s.retired_at IS NULL;
$$;

-- No caller-selected object ID, role override or DSP artifact can enter here.
-- The authenticated Edge ingress supplies owner-bound canonical text, verifies
-- incoming bytes, then invokes write; complete attests private readback bytes.
CREATE FUNCTION public.initial_capture_client_stage_action(
 p_request TEXT,p_sha256 TEXT,p_backend TEXT,p_action TEXT,p_media UUID
) RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE body JSONB; contract JSONB; owner UUID; scan UUID; generation UUID;
 saved internal.initial_capture_audio_stages; item JSONB; candidate UUID; n INTEGER;
 obj internal.initial_capture_client_stage_objects;
BEGIN
 PERFORM internal.require_service_role();
 IF p_action IS NULL OR p_action NOT IN('reserve','write','verify','read','complete') OR p_media IS NULL
  OR p_request IS NULL OR octet_length(p_request)>1044480 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 body:=p_request::JSONB;
 owner:=(body->>'owner_id')::UUID;
 contract:=internal.initial_capture_plan_contract(owner,body->'plan');
 scan:=(contract->>'scan_id')::UUID; generation:=(contract->>'generation')::UUID;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'uploads') x WHERE x->>'media_id'=p_media::TEXT) THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF p_action<>'reserve' AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stages WHERE scan_id=scan) THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 -- Reuse the exact canonical/hash/backend validation and account -> owner ->
 -- scan -> stage lock order. This cannot acquire provider or funding authority.
 PERFORM public.initial_capture_audio_stage_action(p_request,p_sha256,p_backend,'reserve',gen_random_uuid(),NULL,NULL);
 SELECT * INTO saved FROM internal.initial_capture_audio_stages WHERE scan_id=scan FOR UPDATE;
 IF saved.client_inventory_at IS NULL THEN
  IF p_action<>'reserve' OR saved.bound_at IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id=scan::TEXT)
   OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE scan_id=scan::TEXT)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=scan)
   OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000'; END IF;
  n:=0;
  FOR item IN SELECT value FROM jsonb_array_elements(contract->'uploads') LOOP
   FOR attempt IN 1..4 LOOP
    candidate:=gen_random_uuid();
    PERFORM pg_advisory_xact_lock(hashtextextended('merian-capture-stage-object:'||candidate::TEXT,0));
    EXIT WHEN candidate NOT IN(owner,scan,generation,saved.attempt_id)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'uploads') x WHERE x->>'media_id'=candidate::TEXT)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(contract->'audio') x WHERE x->>'prepared_media_id'=candidate::TEXT)
     AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_client_stage_objects WHERE object_id=candidate)
     AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_objects WHERE object_id=candidate)
     AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_erasure WHERE object_id=candidate);
    IF attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
   END LOOP;
   INSERT INTO internal.initial_capture_client_stage_objects(object_id,scan_id,media_id,position,artifact)
    VALUES(candidate,scan,(item->>'media_id')::UUID,n,item);
   n:=n+1;
  END LOOP;
  UPDATE internal.initial_capture_audio_stages SET client_inventory_at=clock_timestamp(),
   bound_at=CASE WHEN jsonb_array_length(contract->'audio')=0 THEN clock_timestamp() ELSE bound_at END WHERE scan_id=scan;
 END IF;
 PERFORM internal.assert_initial_capture_client_stage(scan,false);
 SELECT * INTO obj FROM internal.initial_capture_client_stage_objects WHERE scan_id=scan AND media_id=p_media FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 IF p_action='reserve' THEN RETURN internal.initial_capture_client_stage_receipt(scan,p_media); END IF;
 IF p_action='write' THEN
  IF obj.write_issued_at IS NOT NULL THEN RETURN 'false'::JSONB; END IF;
  UPDATE internal.initial_capture_client_stage_objects SET write_issued_at=clock_timestamp() WHERE object_id=obj.object_id;
  RETURN 'true'::JSONB;
 END IF;
 IF obj.write_issued_at IS NULL OR (p_action='read' AND obj.ready_at IS NULL) THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 IF p_action IN('verify','read') THEN RETURN 'true'::JSONB; END IF;
 UPDATE internal.initial_capture_client_stage_objects SET ready_at=COALESCE(ready_at,clock_timestamp()) WHERE object_id=obj.object_id;
 RETURN internal.initial_capture_client_stage_receipt(scan,p_media);
END;
$$;

-- A new server invocation may claim preparation exactly once, only after all
-- client bytes are ready. A lost pre-bind acknowledgement stays held. A bound
-- retry reads the existing output and never performs DSP again.
CREATE FUNCTION public.claim_initial_capture_stage_preparation(p_request TEXT,p_sha256 TEXT,p_backend TEXT,p_attempt UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_capture_audio_stages; scan UUID; receipt JSONB;
BEGIN
 PERFORM internal.require_service_role();
 receipt:=public.initial_capture_audio_stage_action(p_request,p_sha256,p_backend,'reserve',p_attempt,NULL,NULL);
 scan:=((p_request::JSONB)#>>'{plan,scan_id}')::UUID;
 PERFORM internal.assert_initial_capture_client_stage(scan,true);
 SELECT * INTO saved FROM internal.initial_capture_audio_stages WHERE scan_id=scan FOR UPDATE;
 IF saved.preparation_claimed_at IS NULL THEN
  IF saved.bound_at IS NOT NULL AND EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_objects WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_capture_audio_stages SET attempt_id=p_attempt,preparation_claimed_at=clock_timestamp() WHERE scan_id=scan;
 ELSIF saved.bound_at IS NULL AND saved.attempt_id<>p_attempt THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
 END IF;
 RETURN internal.initial_capture_audio_stage_receipt(scan);
END;
$$;

-- Extend the same retirement owner and permanent V4 outbox. Never allow a
-- client object to be retired through the History namespace or generic TTL.
CREATE OR REPLACE FUNCTION internal.retire_initial_capture_audio_stage(p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
 INSERT INTO internal.initial_capture_audio_stage_erasure(object_id,backend_sha256)
  SELECT o.object_id,s.backend_sha256 FROM internal.initial_capture_client_stage_objects o
  JOIN internal.initial_capture_audio_stages s USING(scan_id) WHERE s.scan_id=p_scan
  UNION ALL
  SELECT o.object_id,s.backend_sha256 FROM internal.initial_capture_audio_stage_objects o
  JOIN internal.initial_capture_audio_stages s USING(scan_id) WHERE s.scan_id=p_scan
  ON CONFLICT(object_id) DO NOTHING;
 DELETE FROM internal.initial_capture_client_stage_objects WHERE scan_id=p_scan;
 DELETE FROM internal.initial_capture_audio_stage_objects WHERE scan_id=p_scan;
 UPDATE internal.initial_capture_audio_stages SET request_body=NULL,retired_at=COALESCE(retired_at,clock_timestamp()) WHERE scan_id=p_scan;
END;
$$;
DO $extend$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.initial_capture_audio_stage_action(text,text,text,text,uuid,jsonb,uuid)'::regprocedure);
 anchor:='jsonb_array_length(contract->''audio'') NOT BETWEEN 1 AND 2';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_client_audio_count_drift'; END IF;
 definition:=replace(definition,anchor,'jsonb_array_length(contract->''audio'') NOT BETWEEN 0 AND 2');
 anchor:='AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_objects WHERE object_id=candidate)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_client_object_identity_drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n                    AND NOT EXISTS(SELECT 1 FROM internal.initial_capture_client_stage_objects WHERE object_id=candidate)');
 anchor:='    IF p_action=''bind'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_client_dsp_claim_drift'; END IF;
 definition:=replace(definition,anchor,anchor||$body$
        IF saved.client_inventory_at IS NOT NULL THEN
            PERFORM internal.assert_initial_capture_client_stage(scan,true);
            IF saved.preparation_claimed_at IS NULL THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
        END IF;
$body$);
 EXECUTE definition;
 definition:=pg_get_functiondef('internal.assert_initial_capture_audio_retention(uuid,jsonb)'::regprocedure);
 anchor:=' expected_count:=jsonb_array_length';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_client_retention_drift'; END IF;
 EXECUTE replace(definition,anchor,' IF stage.client_inventory_at IS NOT NULL THEN PERFORM internal.assert_initial_capture_client_stage(stage.scan_id,true); END IF;'||E'\n'||anchor);
END;
$extend$;
REVOKE ALL ON FUNCTION internal.assert_initial_capture_client_stage(UUID,BOOLEAN),
 internal.initial_capture_client_stage_receipt(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.initial_capture_client_stage_action(TEXT,TEXT,TEXT,TEXT,UUID),
 public.claim_initial_capture_stage_preparation(TEXT,TEXT,TEXT,UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.initial_capture_client_stage_action(TEXT,TEXT,TEXT,TEXT,UUID),
 public.claim_initial_capture_stage_preparation(TEXT,TEXT,TEXT,UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.initial_capture_client_stage_action(text,text,text,text,uuid)','Authenticated private capture ingress: exact client-known inventory, one-shot write and server readback attestation; excludes DSP roles and admission.'),
 ('service_role','public.claim_initial_capture_stage_preparation(text,text,text,uuid)','Exclusive DSP preparation of a fully ready private client graph; no job, funding, provider or native-release authority.');
RESET statement_timeout;
RESET lock_timeout;

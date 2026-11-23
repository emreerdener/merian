SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.initial_capture_audio_stages
 ADD COLUMN adopted_evidence_digest TEXT CHECK(adopted_evidence_digest ~ '^[0-9a-f]{64}$');

-- Called only after the existing ordinary owner/scan fences. A fully verified
-- stage fixes the exact eventual manifest, including all original associations
-- and review geometry; an equal output count is not an adoption proof.
CREATE FUNCTION internal.assert_initial_capture_audio_retention(p_owner UUID,p_request JSONB)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE stage internal.initial_capture_audio_stages; node JSONB; output JSONB; audio JSONB;
    items JSONB:='[]'; final_manifest JSONB; expected_count INTEGER;
BEGIN
 SELECT * INTO stage FROM internal.initial_capture_audio_stages WHERE scan_id=(p_request->>'scan_id')::UUID FOR UPDATE;
 IF NOT FOUND THEN
    -- Historical V7/V8 meanings remain unchanged. New V9 audio must originate
    -- in the durable server preparation owner; absence is never readiness.
    IF p_request#>'{evidence_manifest,schema_version}'='9'::JSONB AND EXISTS(
        SELECT 1 FROM jsonb_array_elements(internal.initial_evidence_contract(p_request->'evidence_manifest',
            p_request->>'scan_id',p_request->>'generation')->'items') x
        WHERE x->>'role' IN('prepared_audio','prepared_companion_audio')) THEN
        RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000';
    END IF;
    RETURN;
 END IF;
 IF stage.owner_id IS DISTINCT FROM p_owner OR stage.generation::TEXT IS DISTINCT FROM p_request->>'generation' THEN
    RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000'; END IF;
 IF stage.adopted_evidence_digest IS NOT NULL THEN
    IF stage.retired_at IS NULL OR stage.adopted_evidence_digest IS DISTINCT FROM p_request->>'evidence_digest' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000'; END IF;
    RETURN;
 END IF;
 IF stage.retired_at IS NOT NULL OR stage.bound_at IS NULL OR stage.request_body IS NULL THEN
    RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 expected_count:=jsonb_array_length(internal.initial_capture_plan_contract(p_owner,stage.request_body->'plan')->'audio');
 IF (SELECT count(*) FROM internal.initial_capture_audio_stage_objects WHERE scan_id=stage.scan_id)<>expected_count
    OR EXISTS(SELECT 1 FROM internal.initial_capture_audio_stage_objects WHERE scan_id=stage.scan_id AND (ready_at IS NULL OR artifact IS NULL)) THEN
    RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 FOR node IN SELECT value FROM jsonb_array_elements(stage.request_body#>'{plan,items}') LOOP
    audio:=CASE WHEN node->>'kind'='audio' THEN node WHEN node->>'kind'='video' THEN node->'audio' ELSE NULL END;
    IF audio IS NOT NULL AND audio<>'null'::JSONB THEN
        SELECT artifact INTO output FROM internal.initial_capture_audio_stage_objects
            WHERE scan_id=stage.scan_id AND media_id=(audio->>'prepared_media_id')::UUID;
        IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
        IF node->>'kind'='audio' THEN node:=(node-'prepared_media_id')||jsonb_build_object('prepared',output);
        ELSE node:=jsonb_set(node,'{audio}',(audio-'prepared_media_id')||jsonb_build_object('prepared',output)); END IF;
    END IF;
    items:=items||jsonb_build_array(node);
 END LOOP;
 final_manifest:=jsonb_build_object('schema_version',9,'items',items);
 IF final_manifest IS DISTINCT FROM p_request->'evidence_manifest'
    OR internal.initial_evidence_contract(final_manifest,stage.scan_id::TEXT,stage.generation::TEXT)->>'evidence_digest'
       IS DISTINCT FROM p_request->>'evidence_digest' THEN
    RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000'; END IF;
END;
$$;

-- Completion's existing trusted byte-verifying service owns ready_at. Retire
-- the source stage only when the entire matching retained manifest is ready.
-- The same transaction fixes adoption and records permanent marker obligations;
-- an acknowledgement loss replays from ordinary retained evidence, not DSP.
CREATE FUNCTION internal.adopt_initial_capture_audio_retention(p_saved internal.ordinary_initial_evidence)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE receipt JSONB; expected JSONB; stage internal.initial_capture_audio_stages;
BEGIN
 SELECT * INTO stage FROM internal.initial_capture_audio_stages WHERE scan_id=p_saved.scan_id FOR UPDATE;
 PERFORM internal.assert_initial_capture_audio_retention(p_saved.owner_id,jsonb_build_object('scan_id',p_saved.scan_id,
    'generation',p_saved.generation,'evidence_digest',p_saved.evidence_digest,'evidence_manifest',p_saved.evidence_manifest));
 IF stage.scan_id IS NULL OR stage.adopted_evidence_digest IS NOT NULL THEN RETURN; END IF;
 expected:=internal.initial_evidence_contract(p_saved.evidence_manifest,p_saved.scan_id::TEXT,p_saved.generation::TEXT)->'items';
 receipt:=internal.ordinary_initial_evidence_receipt(p_saved);
 IF jsonb_array_length(receipt->'items')<>jsonb_array_length(expected)
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB) THEN RETURN; END IF;
 UPDATE internal.initial_capture_audio_stages SET adopted_evidence_digest=p_saved.evidence_digest WHERE scan_id=p_saved.scan_id;
 PERFORM internal.retire_initial_capture_audio_stage(p_saved.scan_id);
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_initial_capture_audio_retention(UUID,JSONB),
 internal.adopt_initial_capture_audio_retention(internal.ordinary_initial_evidence) FROM PUBLIC,anon,authenticated,service_role;

DO $join$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.lock_ordinary_initial_evidence(uuid,jsonb)'::regprocedure);
 anchor:='    SELECT * INTO saved FROM internal.ordinary_initial_evidence WHERE scan_id=scan FOR UPDATE;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_stage_retention_lock_drift'; END IF;
 EXECUTE replace(definition,anchor,'    PERFORM internal.assert_initial_capture_audio_retention(p_owner,p_request);'||E'\n'||anchor);
 definition:=pg_get_functiondef('internal.complete_ordinary_initial_evidence(uuid,jsonb,uuid)'::regprocedure);
 anchor:='    RETURN internal.ordinary_initial_evidence_receipt(saved);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'capture_stage_retention_completion_drift'; END IF;
 EXECUTE replace(definition,anchor,'    PERFORM internal.adopt_initial_capture_audio_retention(saved);'||E'\n'||anchor);
END;
$join$;
COMMENT ON COLUMN internal.initial_capture_audio_stages.adopted_evidence_digest IS
 'Exact ordinary retained manifest adoption, set only after every private destination is verified ready. Distinguishes adopted replay from deletion; never grants provider execution or releases client original holds.';
RESET statement_timeout;
RESET lock_timeout;

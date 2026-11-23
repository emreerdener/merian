SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private prerequisites only. These assertions grant neither a quota lease nor
-- permission to dispatch; the future admission/claim owner must call them in
-- the same transaction while retaining the canonical locks.
CREATE FUNCTION internal.assert_ready_composition_analysis_evidence(
 p_owner UUID,p_observation UUID,p_analysis UUID,p_expected_input JSONB
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path=''
SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_analysis_source_bindings;
 cohort internal.observation_composition_evidence_upload_cohorts;
 allocation internal.observation_composition_evidence_allocations; receipt JSONB;
BEGIN
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 -- Owner/parent -> original source -> child ingestion -> evidence, exactly as
 -- allocation/retirement. Never inspect a caller-selected current version.
 binding:=internal.lock_owned_observation_composition_source_binding(p_owner,p_observation,p_analysis,p_expected_input);
 SELECT * INTO cohort FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=p_analysis FOR UPDATE;
 IF NOT FOUND OR cohort.owner_id IS DISTINCT FROM p_owner OR cohort.observation_id IS DISTINCT FROM p_observation
  OR cohort.source_analysis_id IS DISTINCT FROM binding.source_analysis_id
  OR cohort.items IS DISTINCT FROM internal.observation_composition_source_cohort_items(p_expected_input)
  OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
  OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis)
  OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO allocation FROM internal.observation_composition_evidence_allocations WHERE analysis_id=p_analysis FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis ORDER BY media_id FOR UPDATE;
 -- Closed receipt validation includes every object's exact identity, metadata,
 -- inventory membership and erasure status. A partially ready set never passes.
 receipt:=internal.composition_evidence_receipt(binding);
 IF receipt->>'state' IS DISTINCT FROM 'ready' OR allocation.expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_ready_composition_analysis_evidence(UUID,UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_composition_execution_profile(p_input JSONB)
RETURNS TEXT LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE node JSONB; has_video BOOLEAN:=FALSE; has_visual BOOLEAN:=FALSE; has_audio BOOLEAN:=FALSE;
BEGIN
 -- Reject malformed/text-only graphs and unsupported protocols before deriving
 -- the shared quota profile from all nodes, including companion video sound.
 PERFORM internal.observation_composition_source_contract(p_input);
 FOR node IN SELECT value FROM jsonb_array_elements(p_input#>'{evidence_manifest,items}') LOOP
  IF node->>'kind'='video' THEN
   has_video:=TRUE; has_visual:=TRUE;
   has_audio:=has_audio OR node#>'{provenance,audio}' IS DISTINCT FROM 'null'::JSONB;
  ELSIF node->>'kind'='image' THEN has_visual:=TRUE;
  ELSIF node->>'kind'='audio' THEN has_audio:=TRUE;
  END IF;
 END LOOP;
 RETURN CASE WHEN has_video THEN CASE WHEN has_audio THEN 'multimodal_video_audio_v1' ELSE 'multimodal_video_frames_v1' END
  WHEN has_visual THEN CASE WHEN has_audio THEN 'multimodal_photo_audio_v1' ELSE 'multimodal_photo_v1' END
  WHEN has_audio THEN 'multimodal_audio_v1' ELSE NULL END;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_composition_execution_profile(JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.assert_ready_composition_analysis_evidence(UUID,UUID,UUID,JSONB) IS
 'Private transaction-local complete V5 ready/unexpired evidence assertion. No admission, quota, execution, release or API grant.';
RESET statement_timeout;
RESET lock_timeout;

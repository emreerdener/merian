SET lock_timeout='5s';
SET statement_timeout='2min';

-- Private prerequisite for future admission/dispatch. A successful assertion
-- is valid only within the caller's transaction; it grants no execution lease.
CREATE FUNCTION internal.assert_ready_video_analysis_evidence(
 p_owner UUID,p_observation UUID,p_analysis UUID,p_expected_input JSONB
) RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path=''
SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_analysis_source_bindings;
 cohort internal.observation_video_evidence_upload_cohorts;
 allocation internal.observation_video_evidence_allocations; receipt JSONB;
BEGIN
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 -- Owner/parent -> original source -> child ingestion -> evidence. The shared
 -- binding guard also verifies the immutable V4 fingerprint and live occupancy.
 binding:=internal.lock_owned_observation_video_source_binding(p_owner,p_observation,p_analysis,p_expected_input);
 SELECT * INTO cohort FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis FOR UPDATE;
 IF NOT FOUND OR cohort.owner_id IS DISTINCT FROM p_owner OR cohort.observation_id IS DISTINCT FROM p_observation
  OR cohort.source_analysis_id IS DISTINCT FROM binding.source_analysis_id
  OR cohort.items IS DISTINCT FROM internal.observation_video_source_cohort_items(p_expected_input)
  OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
  OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations WHERE analysis_id=p_analysis FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis ORDER BY media_id FOR UPDATE;
 -- Reuse the closed receipt's exact inventory, object identity, owner, metadata,
 -- count and permanent erasure checks; partial readiness never admits inference.
 receipt:=internal.video_evidence_receipt(binding);
 IF receipt->>'state' IS DISTINCT FROM 'ready' OR allocation.expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_ready_video_analysis_evidence(UUID,UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.assert_ready_video_analysis_evidence(UUID,UUID,UUID,JSONB) IS
 'Private transaction-local exact V4 ready/unexpired cohort assertion. No admission, quota, execution claim, retry, completion or cleanup authority; no API caller.';
RESET statement_timeout;
RESET lock_timeout;

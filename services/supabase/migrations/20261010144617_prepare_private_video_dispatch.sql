SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN video_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Identity-only lock for private V4 work. Replay does not require retained
-- media or live occupancy. Generic execution and public recovery stay unchanged.
CREATE FUNCTION internal.lock_video_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS internal.observation_analysis_intents LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_analysis_source_bindings; saved internal.observation_analysis_intents;
BEGIN
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
 IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner OR binding.observation_id IS DISTINCT FROM p_observation
  OR binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_owned_observation_source(p_owner,p_observation,binding.source_analysis_id);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_analysis::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
 SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
  OR saved.input_snapshot IS DISTINCT FROM binding.input_snapshot OR binding.fingerprint_version IS DISTINCT FROM 1
  OR binding.fingerprint IS DISTINCT FROM internal.observation_video_source_fingerprint(saved.input_snapshot)
  OR EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN saved;
END;
$$;

-- Caller holds the canonical identity/intent locks. This is fresh-dispatch
-- validation only; it neither allocates quota nor creates a dispatch witness.
CREATE FUNCTION internal.assert_video_observation_dispatchable(p_saved internal.observation_analysis_intents)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE reserved internal.ai_quota_reservations; assigned internal.identification_provider_attempts; profile TEXT;
BEGIN
 IF p_saved.state IS DISTINCT FROM 'admitted' OR p_saved.invocation_id IS NOT NULL OR p_saved.provider_outcome IS NOT NULL
  OR p_saved.provider_usage IS NOT NULL OR p_saved.draft IS NOT NULL OR p_saved.receipt IS NOT NULL OR p_saved.terminal_reason IS NOT NULL
  OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_saved.analysis_id)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_saved.analysis_id)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=p_saved.analysis_id)
  OR EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=p_saved.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000'; END IF;
 IF (SELECT admission_enabled AND protected_analysis_enabled AND media_enabled AND video_analysis_enabled
  AND source_dispatch_enabled AND dispatch_enabled AND append_enabled AND video_dispatch_enabled
  FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_ready_video_analysis_evidence(p_saved.owner_id,p_saved.observation_id,p_saved.analysis_id,p_saved.input_snapshot);
 PERFORM internal.assert_observation_source_input_chain(p_saved.owner_id,p_saved.observation_id,p_saved.analysis_id,p_saved.input_snapshot);
 SELECT * INTO reserved FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(p_saved.quota->>'reservation_id') FOR UPDATE;
 IF NOT FOUND OR reserved.user_id IS DISTINCT FROM p_saved.owner_id OR reserved.original_analysis_id IS DISTINCT FROM p_saved.analysis_id
  OR reserved.request_id IS DISTINCT FROM p_saved.analysis_id OR reserved.operation IS DISTINCT FROM 'scan_identification'
  OR reserved.state IS DISTINCT FROM 'reserved' OR reserved.lease_token::TEXT IS DISTINCT FROM p_saved.quota->>'lease_token'
  OR reserved.attempt_count IS DISTINCT FROM 1 OR reserved.lease_expires_at<=clock_timestamp()
  OR p_saved.quota->'attempt_count' IS DISTINCT FROM '1'::JSONB OR p_saved.quota->>'reservation_state' IS DISTINCT FROM 'reserved'
  OR p_saved.quota->>'request_id' IS DISTINCT FROM p_saved.analysis_id::TEXT
  OR p_saved.quota->>'original_analysis_id' IS DISTINCT FROM p_saved.analysis_id::TEXT THEN
  RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000'; END IF;
 profile:=CASE WHEN p_saved.input_snapshot#>'{evidence_manifest,provenance,audio}'='null'::JSONB
  THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END;
 SELECT * INTO assigned FROM internal.identification_provider_attempts WHERE reservation_id=reserved.id AND attempt_count=1;
 IF NOT FOUND OR assigned.input_profile IS DISTINCT FROM profile OR assigned.input_profile IS DISTINCT FROM p_saved.quota->>'input_profile'
  OR assigned.operation IS DISTINCT FROM reserved.operation
  OR p_saved.quota->>'processor_permission' IS DISTINCT FROM p_saved.input_snapshot->>'expected_processor_permission' THEN
  RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000'; END IF;
 PERFORM internal.require_identification_processor_consent(p_saved.owner_id,p_saved.quota->>'processor_permission');
END;
$$;

CREATE FUNCTION internal.claim_video_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents;
BEGIN
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 -- This entry prepares initial dispatch only. Received-result recovery has its
 -- own future contract; unknown execution can never acquire another claim.
 IF saved.state<>'admitted' OR saved.work_expires_at>clock_timestamp() THEN
  RETURN jsonb_build_object('state',saved.state,'claimed',FALSE); END IF;
 PERFORM internal.assert_video_observation_dispatchable(saved);
 UPDATE internal.observation_analysis_intents SET work_token=gen_random_uuid(),work_expires_at=clock_timestamp()+INTERVAL '120 seconds'
  WHERE analysis_id=p_analysis RETURNING * INTO saved;
 RETURN jsonb_build_object('state',saved.state,'claimed',TRUE,'work_token',saved.work_token,'input',saved.input_snapshot,'quota',saved.quota);
END;
$$;

CREATE FUNCTION internal.dispatch_video_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_work_token UUID,p_provenance JSONB)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.observation_analysis_intents; dispatched RECORD; prior_fence TEXT;
BEGIN
 saved:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 IF p_work_token IS NULL OR saved.work_token IS DISTINCT FROM p_work_token THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF saved.state IN ('dispatched','draft','complete') THEN
  IF NOT EXISTS(SELECT 1 FROM internal.identification_invocations v JOIN internal.observation_analysis_dispatch_witnesses w ON w.analysis_id=v.scan_id
   WHERE v.id=saved.invocation_id AND v.scan_id=p_analysis AND v.provenance=p_provenance
    AND w.owner_id=p_owner AND w.observation_id=p_observation AND w.provenance=p_provenance
    AND w.reservation_id=internal.source_child_uuid(saved.quota->>'reservation_id') AND w.attempt_count=1
    AND w.lease_sha256=encode(extensions.digest(saved.quota->>'lease_token','sha256'),'hex')) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('invocation_id',saved.invocation_id,'may_dispatch',FALSE);
 END IF;
 IF saved.work_expires_at IS NULL OR saved.work_expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_video_observation_dispatchable(saved);
 INSERT INTO internal.observation_analysis_dispatch_witnesses
  SELECT p_analysis,p_owner,p_observation,b.source_analysis_id,b.fingerprint,(saved.quota->>'reservation_id')::UUID,
   encode(extensions.digest(saved.quota->>'lease_token','sha256'),'hex'),1,p_provenance,pg_catalog.pg_current_xact_id()
  FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=p_analysis;
 prior_fence:=current_setting('merian.observation_analysis_provider',TRUE);
 PERFORM set_config('merian.observation_analysis_provider',p_owner::TEXT||':'||p_analysis::TEXT,TRUE);
 SELECT * INTO STRICT dispatched FROM public.commit_identification_invocation((saved.quota->>'reservation_id')::UUID,p_owner,
  (saved.quota->>'lease_token')::UUID,1,p_provenance);
 PERFORM set_config('merian.observation_analysis_provider',COALESCE(prior_fence,''),TRUE);
 IF NOT dispatched.may_dispatch THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 UPDATE internal.observation_analysis_intents SET state='dispatched',invocation_id=dispatched.invocation_id WHERE analysis_id=p_analysis;
 RETURN to_jsonb(dispatched);
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_video_observation_analysis(UUID,UUID,UUID),
 internal.assert_video_observation_dispatchable(internal.observation_analysis_intents),
 internal.claim_video_observation_analysis(UUID,UUID,UUID),
 internal.dispatch_video_observation_analysis(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON COLUMN internal.observation_history_rollout.video_dispatch_enabled IS
 'Default-off private V4 claim and one-shot dispatch preparation. No API callers; result/reader/settlement integration remains required.';
-- Forward-only lint repair: retain V4 input validation without storing a value
-- that admission never reads. The already-applied admission migration is intact.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.admit_video_observation_analysis(uuid,jsonb,text)'::regprocedure) INTO STRICT definition;
 anchor:='fingerprint TEXT; ';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed video admission declaration changed'; END IF;
 definition:=replace(definition,anchor,'');
 anchor:='fingerprint:=internal.observation_video_source_fingerprint(p_input);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed video admission validation changed'; END IF;
 EXECUTE replace(definition,anchor,'PERFORM internal.observation_video_source_fingerprint(p_input);');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN video_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Extend only the lock-free durable metadata check used by initial funding.
-- Callers must already hold the canonical source and child locks.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)'::regprocedure) INTO STRICT definition;
 anchor:='internal.observation_source_fingerprint(p_input)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed input chain fingerprint changed'; END IF;
 definition:=replace(definition,anchor,'(CASE WHEN p_input->''schema_version''=''4''::JSONB THEN internal.observation_video_source_fingerprint(p_input) ELSE internal.observation_source_fingerprint(p_input) END)');
 anchor:=$anchor$    IF p_input->'schema_version'='2'::JSONB THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed input chain branch changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF p_input->'schema_version'='4'::JSONB THEN
        IF NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts v
            WHERE v.analysis_id=p_analysis AND v.owner_id=p_owner AND v.observation_id=p_observation
              AND v.source_analysis_id=binding.source_analysis_id
              AND v.items=internal.observation_video_source_cohort_items(p_input))
          OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
          OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN;
    END IF;
$body$||anchor);

 -- Intent insertion is still private. Keep a direct storage backstop on V4
 -- readiness without acquiring a source lock after the generic child trigger.
 SELECT pg_get_functiondef('internal.guard_source_bound_analysis_intent()'::regprocedure) INTO STRICT definition;
 anchor:='    PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed intent entry changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF NEW.input_snapshot->'schema_version'='4'::JSONB THEN
        IF (SELECT admission_enabled AND protected_analysis_enabled AND media_enabled AND video_analysis_enabled
            FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
        END IF;
        PERFORM internal.assert_ready_video_analysis_evidence(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot);
        PERFORM internal.assert_observation_source_input_chain(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot);
        RETURN NEW;
    END IF;
$body$||anchor);

 SELECT pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::regprocedure) INTO STRICT definition;
 anchor:=$anchor$CASE b.input_snapshot->>'schema_version' WHEN '2' THEN 'multimodal_photo_v1' WHEN '3' THEN 'multimodal_audio_v1' END$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed quota profile binding changed'; END IF;
 EXECUTE replace(definition,anchor,$body$CASE b.input_snapshot->>'schema_version' WHEN '2' THEN 'multimodal_photo_v1' WHEN '3' THEN 'multimodal_audio_v1'
            WHEN '4' THEN CASE WHEN b.input_snapshot#>'{evidence_manifest,provenance,audio}'='null'::JSONB THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END END$body$);
END;
$patch$;

CREATE FUNCTION internal.admit_video_observation_analysis(p_owner UUID,p_input JSONB,p_ip_hash TEXT)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE observation UUID; analysis UUID; saved internal.observation_analysis_intents;
 fingerprint TEXT; admitted RECORD; previous_fence TEXT; profile TEXT;
BEGIN
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 fingerprint:=internal.observation_video_source_fingerprint(p_input);
 observation:=(p_input->>'observation_id')::UUID; analysis:=(p_input->>'analysis_id')::UUID;
 PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
 -- Parent ownership/deletion fencing precedes exact replay. Saved funding is
 -- returned before live occupancy, expiry, consent or gates; never re-reserve.
 SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
 IF FOUND THEN
  IF saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM observation
   OR saved.input_snapshot IS DISTINCT FROM p_input OR jsonb_typeof(saved.quota) IS DISTINCT FROM 'object'
   OR internal.source_child_uuid(saved.quota->>'reservation_id') IS NULL
   OR internal.source_child_uuid(saved.quota->>'lease_token') IS NULL
   OR saved.quota->>'request_id' IS DISTINCT FROM analysis::TEXT
   OR saved.quota->>'original_analysis_id' IS DISTINCT FROM analysis::TEXT
   OR saved.quota->>'reservation_state' IS DISTINCT FROM 'reserved'
   OR saved.quota->'attempt_count' IS DISTINCT FROM '1'::JSONB THEN
    RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN to_jsonb(saved)-'draft';
 END IF;
 PERFORM internal.assert_ready_video_analysis_evidence(p_owner,observation,analysis,p_input);
 IF (SELECT admission_enabled AND protected_analysis_enabled AND media_enabled AND video_analysis_enabled
     FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT internal.observation_video_evidence_execution_clear(analysis) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot)
 VALUES(analysis,observation,p_owner,p_input);
 profile:=CASE WHEN p_input#>'{evidence_manifest,provenance,audio}'='null'::JSONB
  THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END;
 previous_fence:=current_setting('merian.observation_analysis_admission',TRUE);
 PERFORM set_config('merian.observation_analysis_admission',p_owner::TEXT||':'||analysis::TEXT,TRUE);
 SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(p_owner,'scan_identification',analysis,p_ip_hash,analysis,FALSE,
  3,FALSE,profile,p_input->>'expected_processor_permission',6);
 PERFORM set_config('merian.observation_analysis_admission',COALESCE(previous_fence,''),TRUE);
 IF admitted.original_analysis_id IS DISTINCT FROM analysis OR admitted.reservation_state IS DISTINCT FROM 'reserved'
  OR to_jsonb(admitted)->'attempt_count' IS DISTINCT FROM '1'::JSONB THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 UPDATE internal.observation_analysis_intents SET quota=to_jsonb(admitted) WHERE analysis_id=analysis RETURNING * INTO saved;
 RETURN to_jsonb(saved)-'draft';
END;
$$;
REVOKE ALL ON FUNCTION internal.admit_video_observation_analysis(UUID,JSONB,TEXT) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON COLUMN internal.observation_history_rollout.video_analysis_enabled IS
 'Default-off private V4 initial admission. No public begin, claim, dispatch, result or completion integration is installed.';
RESET statement_timeout;
RESET lock_timeout;

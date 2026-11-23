SET lock_timeout='5s';
SET statement_timeout='2min';

-- V5 has its own funding/dispatch boundary. Saved V1-V4 bytes and workers are
-- unchanged; no service facade is granted by this migration.
ALTER TABLE internal.observation_history_rollout
 ADD COLUMN composition_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN composition_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)'::regprocedure);
 anchor:=$a$CASE WHEN p_input->'schema_version'='4'::JSONB THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_input_fingerprint_drift'; END IF;
 definition:=replace(definition,anchor,$a$CASE WHEN p_input->'schema_version'='5'::JSONB THEN internal.observation_composition_source_fingerprint(p_input) WHEN p_input->'schema_version'='4'::JSONB THEN$a$);
 anchor:=$a$    IF p_input->'schema_version'='4'::JSONB THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_input_cohort_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$    IF p_input->'schema_version'='5'::JSONB THEN
        IF NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts c
            WHERE c.analysis_id=p_analysis AND c.owner_id=p_owner AND c.observation_id=p_observation
              AND c.source_analysis_id=binding.source_analysis_id
              AND c.items=internal.observation_composition_source_cohort_items(p_input))
          OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
          OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis)
          OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis) THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        RETURN;
    END IF;
$a$||anchor);
 definition:=pg_get_functiondef('internal.guard_source_bound_analysis_intent()'::regprocedure);
 anchor:=$a$    IF NEW.input_snapshot->'schema_version'='4'::JSONB THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_intent_guard_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$    IF NEW.input_snapshot->'schema_version'='5'::JSONB THEN
        IF (SELECT admission_enabled AND protected_analysis_enabled AND media_enabled
            AND composition_runtime_enabled AND composition_analysis_enabled AND selection_enabled
            FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
            RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_ready_composition_analysis_evidence(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot);
        PERFORM internal.assert_observation_source_input_chain(NEW.owner_id,NEW.observation_id,NEW.analysis_id,NEW.input_snapshot);
        RETURN NEW;
    END IF;
$a$||anchor);
 definition:=pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::regprocedure);
 anchor:=$a$CASE b.input_snapshot->>'schema_version' WHEN '2' THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_quota_profile_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$CASE b.input_snapshot->>'schema_version' WHEN '5' THEN internal.observation_composition_execution_profile(b.input_snapshot) WHEN '2' THEN$a$);
END;
$patch$;

-- Reuse the effective one-shot lifecycle implementation, including all later
-- safety fixes. Translate only explicitly named sibling owners and V5 facts.
DO $clone$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'internal.admit_video_observation_analysis(uuid,jsonb,text)',
 'internal.lock_video_observation_analysis(uuid,uuid,uuid)',
 'internal.assert_video_observation_dispatchable(internal.observation_analysis_intents)',
 'internal.claim_video_observation_analysis(uuid,uuid,uuid)',
 'internal.dispatch_video_observation_analysis(uuid,uuid,uuid,uuid,jsonb)',
 'internal.assert_video_analysis_dispatch_identity(internal.observation_analysis_intents)',
 'internal.record_video_observation_outcome(uuid,uuid,uuid,uuid,jsonb)',
 'internal.read_video_observation_outcome(uuid,uuid,uuid)',
 'internal.record_video_observation_draft(uuid,uuid,uuid,uuid,jsonb)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  FOR anchor,replacement IN SELECT * FROM (VALUES
   ('admit_video_observation_analysis','admit_composition_observation_analysis'),
   ('lock_video_observation_analysis','lock_composition_observation_analysis'),
   ('assert_video_observation_dispatchable','assert_composition_observation_dispatchable'),
   ('claim_video_observation_analysis','claim_composition_observation_analysis'),
   ('dispatch_video_observation_analysis','dispatch_composition_observation_analysis'),
   ('assert_video_analysis_dispatch_identity','assert_composition_analysis_dispatch_identity'),
   ('record_video_observation_outcome','record_composition_observation_outcome'),
   ('read_video_observation_outcome','read_composition_observation_outcome'),
   ('record_video_observation_draft','record_composition_observation_draft'),
   ('assert_ready_video_analysis_evidence','assert_ready_composition_analysis_evidence'),
   ('observation_video_source_fingerprint','observation_composition_source_fingerprint'),
   ('observation_video_evidence_execution_clear','observation_composition_evidence_execution_clear'),
   ('video_analysis_enabled','composition_analysis_enabled AND composition_runtime_enabled AND selection_enabled'),
   ('video_dispatch_enabled','composition_dispatch_enabled')
  ) changes(anchor,replacement) LOOP definition:=replace(definition,anchor,replacement); END LOOP;
  IF signature='internal.admit_video_observation_analysis(uuid,jsonb,text)' THEN
   anchor:=$a$profile:=CASE WHEN p_input#>'{evidence_manifest,provenance,audio}'='null'::JSONB
  THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END;$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_admission_profile_drift'; END IF;
   definition:=replace(definition,anchor,'profile:=internal.observation_composition_execution_profile(p_input);');
   anchor:=$a$p_input->>'expected_processor_permission',6$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_admission_protocol_drift'; END IF;
   definition:=replace(definition,anchor,$a$p_input->>'expected_processor_permission',7$a$);
  ELSIF signature='internal.lock_video_observation_analysis(uuid,uuid,uuid)' THEN
   anchor:=$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_lock_schema_drift'; END IF;
   definition:=replace(definition,anchor,$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$);
   -- A V5 child can never possess a legacy retirement receipt. Keep this
   -- cross-family denial; V5 source release requires its separate proof.
  ELSIF signature='internal.assert_video_observation_dispatchable(internal.observation_analysis_intents)' THEN
   anchor:=$a$profile:=CASE WHEN p_saved.input_snapshot#>'{evidence_manifest,provenance,audio}'='null'::JSONB
  THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END;$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_dispatch_profile_drift'; END IF;
   definition:=replace(definition,anchor,'profile:=internal.observation_composition_execution_profile(p_saved.input_snapshot);');
  END IF;
  EXECUTE definition;
 END LOOP;
END;
$clone$;
REVOKE ALL ON FUNCTION internal.admit_composition_observation_analysis(UUID,JSONB,TEXT),
 internal.lock_composition_observation_analysis(UUID,UUID,UUID),
 internal.assert_composition_observation_dispatchable(internal.observation_analysis_intents),
 internal.claim_composition_observation_analysis(UUID,UUID,UUID),
 internal.dispatch_composition_observation_analysis(UUID,UUID,UUID,UUID,JSONB),
 internal.assert_composition_analysis_dispatch_identity(internal.observation_analysis_intents),
 internal.record_composition_observation_outcome(UUID,UUID,UUID,UUID,JSONB),
 internal.read_composition_observation_outcome(UUID,UUID,UUID),
 internal.record_composition_observation_draft(UUID,UUID,UUID,UUID,JSONB)
 FROM PUBLIC,anon,authenticated,service_role;

-- Generic workers must neither claim nor capture V5, including direct calls
-- that bypass bounded discovery. No uncertain request gains another attempt.
DO $fence$
DECLARE signature TEXT; definition TEXT; anchor TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'internal.claim_observation_analysis(uuid,uuid,uuid)',
 'public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:=$a$    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;$a$;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_generic_worker_drift'; END IF;
  EXECUTE replace(definition,anchor,anchor||$a$
    IF saved.input_snapshot->'schema_version'='5'::JSONB THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
$a$);
 END LOOP;
 definition:=pg_get_functiondef('public.list_observation_analysis_recovery()'::regprocedure);
 anchor:=$a$input_snapshot->'schema_version'<>'4'::JSONB$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_generic_discovery_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$input_snapshot->'schema_version' NOT IN ('4'::JSONB,'5'::JSONB)$a$);
END;
$fence$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';
ALTER TABLE internal.observation_history_rollout ADD COLUMN composition_orchestration_enabled BOOLEAN NOT NULL DEFAULT FALSE;
DO $clone$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'public.begin_owned_observation_video_analysis(uuid,jsonb,text)',
 'public.claim_observation_video_analysis_recovery(uuid,uuid,uuid)',
 'public.list_observation_video_analysis_recovery()',
 'public.advance_owned_observation_video_analysis(uuid,uuid,uuid,uuid,text,jsonb)'
 ] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  FOR anchor,replacement IN SELECT * FROM (VALUES
   ('begin_owned_observation_video_analysis','begin_owned_observation_composition_analysis'),
   ('claim_observation_video_analysis_recovery','claim_observation_composition_analysis_recovery'),
   ('list_observation_video_analysis_recovery','list_observation_composition_analysis_recovery'),
   ('advance_owned_observation_video_analysis','advance_owned_observation_composition_analysis'),
   ('admit_video_observation_analysis','admit_composition_observation_analysis'),
   ('claim_video_observation_analysis','claim_composition_observation_analysis'),
   ('lock_video_observation_analysis','lock_composition_observation_analysis'),
   ('assert_video_analysis_dispatch_identity','assert_composition_analysis_dispatch_identity'),
   ('record_video_observation_outcome','record_composition_observation_outcome'),
   ('assert_video_observation_dispatchable','assert_composition_observation_dispatchable'),
   ('video_evidence_receipt','composition_evidence_receipt'),
   ('dispatch_video_observation_analysis','dispatch_composition_observation_analysis'),
   ('record_video_observation_draft','record_composition_observation_draft'),
   ('account_video_observation_draft','account_composition_observation_draft'),
   ('complete_video_observation_analysis','complete_composition_observation_analysis'),
   ('settle_video_observation_terminal','settle_composition_observation_terminal'),
   ('video_orchestration_enabled','composition_orchestration_enabled AND composition_runtime_enabled')
  ) changes(anchor,replacement) LOOP definition:=replace(definition,anchor,replacement); END LOOP;
  IF signature='public.list_observation_video_analysis_recovery()' THEN
   anchor:=$a$input_snapshot->'schema_version'='4'::JSONB$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_recovery_schema_drift'; END IF;
   definition:=replace(definition,anchor,$a$input_snapshot->'schema_version'='5'::JSONB$a$);
  END IF;
  EXECUTE definition;
 END LOOP;
END;
$clone$;
REVOKE ALL ON FUNCTION public.begin_owned_observation_composition_analysis(uuid,jsonb,text),public.claim_observation_composition_analysis_recovery(uuid,uuid,uuid),public.list_observation_composition_analysis_recovery(),public.advance_owned_observation_composition_analysis(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_owned_observation_composition_analysis(uuid,jsonb,text),public.claim_observation_composition_analysis_recovery(uuid,uuid,uuid),public.list_observation_composition_analysis_recovery(),public.advance_owned_observation_composition_analysis(uuid,uuid,uuid,uuid,text,jsonb) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.begin_owned_observation_composition_analysis(uuid,jsonb,text)','Default-off V5 composition orchestration; exact original dispatch and known-result recovery only.'),
 ('service_role','public.claim_observation_composition_analysis_recovery(uuid,uuid,uuid)','Default-off V5 composition orchestration; exact original dispatch and known-result recovery only.'),
 ('service_role','public.list_observation_composition_analysis_recovery()','Default-off V5 composition orchestration; exact original dispatch and known-result recovery only.'),
 ('service_role','public.advance_owned_observation_composition_analysis(uuid,uuid,uuid,uuid,text,jsonb)','Default-off V5 composition orchestration; exact original dispatch and known-result recovery only.');

-- Page/state reader14 adds snapshot6. Older readers refuse the whole affected
-- history even if their selected page happens to contain only legacy results.
DO $readers$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOR signature,anchor,replacement IN SELECT * FROM (VALUES
 ('public.get_owned_observation_analysis_page(jsonb,integer)','p_reader NOT IN (7,8,9,10,11,13)','p_reader NOT IN (7,8,9,10,11,13,14)'),
 ('public.get_owned_observation_analysis_state(jsonb,integer)','p_reader NOT IN (9,10,11,13)','p_reader NOT IN (9,10,11,13,14)'),
 ('public.get_owned_observation_analysis_page(jsonb,integer)',
 $a$(p_reader IN (11,13) AND result_row.evidence_manifest->'schema_version'='4'::JSONB)$a$,
 $a$(p_reader IN (11,13,14) AND result_row.evidence_manifest->'schema_version'='4'::JSONB)
                OR (p_reader=14 AND result_row.evidence_manifest->'schema_version'='5'::JSONB)$a$)
 ) patches(signature,anchor,replacement) LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_reader_drift'; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
 FOREACH signature IN ARRAY ARRAY['public.get_owned_observation_analysis_page(jsonb,integer)','public.get_owned_observation_analysis_state(jsonb,integer)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:='    IF p_reader <> 13 AND EXISTS(';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_reader_provenance_drift'; END IF;
  EXECUTE replace(definition,anchor,$a$    IF p_reader<>14 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND evidence_manifest->'schema_version'='5'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (13,14) AND EXISTS($a$);
 END LOOP;
 -- Reader14 has completed-result selection/review capabilities, not permission
 -- for legacy execution/retirement APIs (those keep their narrower allowlists).
 definition:=pg_get_functiondef('internal.require_observation_action_reader(uuid,integer,uuid)'::regprocedure);
 anchor:='p_reader NOT IN (9,10,11)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_action_reader_drift'; END IF;
 definition:=replace(definition,anchor,'p_reader NOT IN (9,10,11,14)');
 anchor:='(p_reader=11 AND p_analysis IS NOT NULL)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_action_guard_drift'; END IF;
 definition:=replace(definition,anchor,'(p_reader IN (11,14) AND p_analysis IS NOT NULL)');
 anchor:='(p_reader<>11 AND EXISTS(';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_action_guard_drift'; END IF;
 definition:=replace(definition,anchor,'(p_reader NOT IN (11,14) AND EXISTS(');
 anchor:='    IF p_reader=9 AND (';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_action_fence_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$    IF (p_reader<>14 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='5'::JSONB))
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=p_observation
            AND analysis_id=p_analysis AND input_snapshot->'schema_version'='5'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
$a$||anchor);
 FOREACH signature IN ARRAY ARRAY[
 'public.select_owned_observation_analysis(jsonb,integer)',
 'public.review_owned_observation_analysis(jsonb,integer)',
 'public.get_owned_observation_confirmation_undo(jsonb,integer)',
 'public.get_owned_observation_rejection_undo(jsonb,integer)',
 'internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:='(p_reader IS NULL OR p_reader NOT IN (9,10,11))';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_action_entry_drift'; END IF;
  EXECUTE replace(definition,anchor,'(p_reader IS NULL OR p_reader NOT IN (9,10,11,14))');
 END LOOP;
END;
$readers$;
-- A successful V5 child releases its source through its own immutable proof.
-- Refusals and uncertain outcomes remain occupied/held; legacy proofs never parse V5.
DO $successors$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)',
 'public.reserve_owned_observation_video_source(uuid,jsonb,integer)',
 'public.reserve_owned_observation_composition_source(uuid,jsonb,integer)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:=$a$WHERE b.observation_id=observation AND b.source_analysis_id=source AND b.input_snapshot->'schema_version'='5'::JSONB) THEN$a$;
  replacement:=$a$WHERE b.observation_id=observation AND b.source_analysis_id=source AND b.input_snapshot->'schema_version'='5'::JSONB
    AND NOT internal.composition_source_completion_proven(b)) THEN$a$;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_successor_hold_drift'; END IF;
  definition:=replace(definition,anchor,replacement);
  IF signature='public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)' THEN
   anchor:=$a$AND internal.observation_source_completion_proven(b))) THEN$a$;
   replacement:=$a$AND CASE WHEN b.input_snapshot->'schema_version'='5'::JSONB THEN internal.composition_source_completion_proven(b)
       ELSE internal.observation_source_completion_proven(b) END)) THEN$a$;
  ELSE
   anchor:=$a$AND ((b.input_snapshot->'schema_version'='4'::JSONB AND internal.observation_video_source_release_proven(b))
 OR (b.input_snapshot->'schema_version'<>'4'::JSONB AND internal.observation_source_completion_proven(b))))) THEN$a$;
   replacement:=$a$AND CASE WHEN b.input_snapshot->'schema_version'='5'::JSONB THEN internal.composition_source_completion_proven(b)
       WHEN b.input_snapshot->'schema_version'='4'::JSONB THEN internal.observation_video_source_release_proven(b)
       ELSE internal.observation_source_completion_proven(b) END)) THEN$a$;
  END IF;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_successor_result_drift'; END IF;
  definition:=replace(definition,anchor,replacement);
  IF signature='public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)' THEN
   anchor:=$a$IF predecessor.owner_id<>p_owner OR NOT internal.observation_source_release_proven(predecessor) THEN$a$;
   replacement:=$a$IF predecessor.owner_id<>p_owner OR NOT (CASE
       WHEN predecessor.input_snapshot->'schema_version'='5'::JSONB THEN internal.composition_source_completion_proven(predecessor)
       ELSE internal.observation_source_release_proven(predecessor) END) THEN$a$;
  ELSE
   anchor:=$a$  IF predecessor.input_snapshot->'schema_version'='4'::JSONB THEN$a$;
   replacement:=$a$  IF predecessor.input_snapshot->'schema_version'='5'::JSONB THEN
   IF predecessor.owner_id<>p_owner OR NOT internal.composition_source_completion_proven(predecessor) THEN
    RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
   CONTINUE;
  END IF;
$a$||anchor;
  END IF;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_successor_predecessor_drift'; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$successors$;
-- The existing bounded recovery scheduler discovers both explicit families.
-- Disabled families contribute no candidates; claims still enforce every gate.
DO $discovery$
DECLARE signature TEXT; definition TEXT; anchor TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY['public.list_observation_video_analysis_recovery()',
 'public.list_observation_composition_analysis_recovery()'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:=$a$RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;$a$;
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_discovery_gate_drift'; END IF;
  EXECUTE replace(definition,anchor,$a$RETURN '[]'::JSONB; END IF;$a$);
 END LOOP;
END;
$discovery$;
-- First-import reconciliation must use the same complete reader for both
-- baseline and current state, including when the selected result is V6.
DO $enrollment$
DECLARE definition TEXT; anchor TEXT := 'p_reader IS DISTINCT FROM 11';
BEGIN
 definition:=pg_get_functiondef('public.get_owned_observation_enrollment_selection(jsonb,integer)'::regprocedure);
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_enrollment_reader_drift'; END IF;
 EXECUTE replace(definition,anchor,'(p_reader IS NULL OR p_reader NOT IN (11,14))');
END;
$enrollment$;
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

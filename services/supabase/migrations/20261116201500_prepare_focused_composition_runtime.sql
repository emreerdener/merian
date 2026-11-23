SET lock_timeout='5s';
SET statement_timeout='2min';

-- V6/FV2 focused reanalysis uses the existing execution and settlement owner.
-- All focused capabilities remain default false. No release or initial V8
-- baseline activation is implied. V5 fingerprints and replay bytes are unchanged.
DO $patch$
DECLARE signature TEXT; anchor TEXT; replacement TEXT; expected INTEGER; definition TEXT;
BEGIN
 FOR signature,anchor,replacement,expected IN SELECT * FROM (VALUES
  ('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)',$a$binding.fingerprint_version IS DISTINCT FROM 1$a$,$b$binding.fingerprint_version IS DISTINCT FROM (CASE WHEN p_input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)$b$,1),
  ('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)',$a$CASE WHEN p_input->'schema_version'='5'::JSONB THEN internal.observation_composition_source_fingerprint(p_input)$a$,$b$CASE WHEN p_input->'schema_version' IN ('5'::JSONB,'6'::JSONB) THEN internal.observation_composition_request_fingerprint(p_input)$b$,1),
  ('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)',$a$p_input->'schema_version'='5'::JSONB$a$,$b$p_input->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.admit_composition_observation_analysis(uuid,jsonb,text)',$a$internal.observation_composition_source_fingerprint($a$,$b$internal.observation_composition_request_fingerprint($b$,1),
  ('internal.lock_composition_observation_analysis(uuid,uuid,uuid)',$a$internal.observation_composition_source_fingerprint($a$,$b$internal.observation_composition_request_fingerprint($b$,1),
  ('internal.observation_composition_execution_profile(jsonb)',$a$internal.observation_composition_source_contract($a$,$b$internal.observation_composition_request_contract($b$,1),
  ('internal.composition_analysis_accounting_product(internal.observation_analysis_intents)',$a$i.input_snapshot->'schema_version'='5'::JSONB$a$,$b$i.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.composition_analysis_terminal_product(internal.observation_analysis_intents)',$a$i.input_snapshot->'schema_version'='5'::JSONB$a$,$b$i.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.composition_source_completion_product(internal.observation_analysis_source_bindings)',$a$internal.observation_composition_source_fingerprint($a$,$b$internal.observation_composition_request_fingerprint($b$,1),
  ('internal.composition_source_completion_product(internal.observation_analysis_source_bindings)',$a$b.input_snapshot->'schema_version'='5'::JSONB$a$,$b$b.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('public.list_observation_composition_analysis_recovery()',$a$input_snapshot->'schema_version'='5'::JSONB$a$,$b$input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.lock_composition_observation_analysis(uuid,uuid,uuid)',$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$,$b$(binding.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)) IS NOT TRUE$b$,1),
  ('internal.lock_composition_observation_analysis(uuid,uuid,uuid)',$a$binding.fingerprint_version IS DISTINCT FROM 1$a$,$b$binding.fingerprint_version IS DISTINCT FROM (CASE WHEN saved.input_snapshot->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)$b$,1),
  ('internal.composition_source_completion_product(internal.observation_analysis_source_bindings)',$a$b.fingerprint_version=1$a$,$b$b.fingerprint_version=(CASE WHEN b.input_snapshot->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)$b$,1),
  ('internal.composition_analysis_completion_matches(internal.observation_analysis_intents)',$a$jsonb_build_object('schema_version',6,'observation_id'$a$,$b$jsonb_build_object('schema_version',CASE WHEN i.input_snapshot->'schema_version'='6'::JSONB THEN 7 ELSE 6 END,'observation_id'$b$,1),
  ('internal.guard_source_bound_analysis_intent()',$a$NEW.input_snapshot->'schema_version'='5'::JSONB$a$,$b$NEW.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.guard_source_bound_analysis_intent()',$a$AND composition_runtime_enabled AND composition_analysis_enabled AND selection_enabled$a$,$b$AND composition_runtime_enabled AND composition_analysis_enabled AND selection_enabled AND (NEW.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_runtime_enabled AND focused_composition_analysis_enabled))$b$,1),
  ('internal.admit_composition_observation_analysis(uuid,jsonb,text)',$a$composition_analysis_enabled AND composition_runtime_enabled AND selection_enabled$a$,$b$composition_analysis_enabled AND composition_runtime_enabled AND selection_enabled AND (p_input->'schema_version'<>'6'::JSONB OR (focused_composition_runtime_enabled AND focused_composition_analysis_enabled))$b$,1),
  ('internal.assert_composition_observation_dispatchable(internal.observation_analysis_intents)',$a$AND source_dispatch_enabled AND dispatch_enabled AND append_enabled AND composition_dispatch_enabled$a$,$b$AND source_dispatch_enabled AND dispatch_enabled AND append_enabled AND composition_dispatch_enabled AND (p_saved.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_runtime_enabled AND focused_composition_analysis_enabled AND focused_composition_dispatch_enabled))$b$,1),
  ('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)',$a$CASE b.input_snapshot->>'schema_version' WHEN '5' THEN$a$,$b$CASE b.input_snapshot->>'schema_version' WHEN '6' THEN internal.observation_composition_execution_profile(b.input_snapshot) WHEN '5' THEN$b$,1),
  ('public.begin_owned_observation_composition_analysis(uuid,jsonb,text)',$a$composition_orchestration_enabled AND composition_runtime_enabled FROM$a$,$b$composition_orchestration_enabled AND composition_runtime_enabled AND (p_input->'schema_version'<>'6'::JSONB OR (focused_composition_runtime_enabled AND focused_composition_orchestration_enabled)) FROM$b$,1),
  ('internal.guard_observation_media_binding()',$a$NEW.evidence_manifest->'schema_version'='5'::JSONB$a$,$b$NEW.evidence_manifest->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.guard_observation_media_binding()',$a$saved.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$,$b$saved.input_snapshot->'schema_version' IS DISTINCT FROM NEW.evidence_manifest->'schema_version'$b$,1),
  ('internal.observation_analysis_snapshot(uuid,uuid,uuid,text,integer,timestamp with time zone,jsonb,jsonb)',$a$CASE WHEN evidence->'schema_version'='5'::JSONB THEN 6$a$,$b$CASE WHEN evidence->'schema_version'='6'::JSONB THEN 7 WHEN evidence->'schema_version'='5'::JSONB THEN 6$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$(7,8,9,10,11,13,14)$a$,$b$(7,8,9,10,11,13,14,15)$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$p_reader<>14$a$,$b$p_reader NOT IN (14,15)$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$(13,14)$a$,$b$(13,14,15)$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$(11,13,14)$a$,$b$(11,13,14,15)$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$p_reader=14 AND result_row.evidence_manifest->'schema_version'='5'::JSONB$a$,$b$p_reader IN (14,15) AND result_row.evidence_manifest->'schema_version'='5'::JSONB) OR (p_reader=15 AND result_row.evidence_manifest->'schema_version'='6'::JSONB$b$,1),
  ('public.get_owned_observation_analysis_page(jsonb,integer)',$a$    IF p_reader NOT IN (14,15) AND EXISTS($a$,$b$    IF p_reader<>15 AND (EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='6'::JSONB) OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=observation AND input_snapshot->'schema_version'='6'::JSONB)) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (14,15) AND EXISTS($b$,1),
  ('public.get_owned_observation_analysis_state(jsonb,integer)',$a$(9,10,11,13,14)$a$,$b$(9,10,11,13,14,15)$b$,1),
  ('public.get_owned_observation_analysis_state(jsonb,integer)',$a$p_reader<>14$a$,$b$p_reader NOT IN (14,15)$b$,1),
  ('public.get_owned_observation_analysis_state(jsonb,integer)',$a$(13,14)$a$,$b$(13,14,15)$b$,1),
  ('public.get_owned_observation_analysis_state(jsonb,integer)',$a$    IF p_reader NOT IN (14,15) AND EXISTS($a$,$b$    IF p_reader<>15 AND (EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='6'::JSONB) OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=observation AND input_snapshot->'schema_version'='6'::JSONB)) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader NOT IN (14,15) AND EXISTS($b$,1),
  ('internal.require_observation_action_reader(uuid,integer,uuid)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('internal.require_observation_action_reader(uuid,integer,uuid)',$a$(11,14)$a$,$b$(11,14,15)$b$,2),
  ('internal.require_observation_action_reader(uuid,integer,uuid)',$a$p_reader<>14$a$,$b$p_reader NOT IN (14,15)$b$,1),
  ('internal.require_observation_action_reader(uuid,integer,uuid)',$a$input_snapshot->'schema_version'='5'::JSONB$a$,$b$input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.require_observation_action_reader(uuid,integer,uuid)',$a$    IF (p_reader NOT IN (14,15) AND EXISTS($a$,$b$    IF p_reader<>15 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='6'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF (p_reader NOT IN (14,15) AND EXISTS($b$,1),
  ('public.select_owned_observation_analysis(jsonb,integer)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('public.review_owned_observation_analysis(jsonb,integer)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('public.get_owned_observation_confirmation_undo(jsonb,integer)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('public.get_owned_observation_rejection_undo(jsonb,integer)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('internal.confirm_observation_analysis(uuid,jsonb,integer,boolean,text,jsonb)',$a$(9,10,11,14)$a$,$b$(9,10,11,14,15)$b$,1),
  ('public.get_owned_observation_enrollment_selection(jsonb,integer)',$a$(11,14)$a$,$b$(11,14,15)$b$,1),
  ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)',$a$p_protocol IS DISTINCT FROM 1$a$,$b$(p_protocol IS NULL OR p_protocol NOT IN (1,2))$b$,1),
  ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)',$a$('2'::JSONB,'3'::JSONB,'4'::JSONB,'5'::JSONB)$a$,$b$('2'::JSONB,'3'::JSONB,'4'::JSONB,'5'::JSONB,'6'::JSONB)$b$,1),
  ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)',$a$    IF manifest->'schema_version' IN ('2'::JSONB,'3'::JSONB) THEN$a$,$b$    IF manifest->'schema_version'='6'::JSONB AND p_protocol<>2 THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF manifest->'schema_version' IN ('2'::JSONB,'3'::JSONB) THEN$b$,1),
  ('public.resolve_owned_observation_media(uuid,uuid,uuid,uuid,integer)',$a$ELSIF manifest->'schema_version'='5'::JSONB THEN$a$,$b$ELSIF manifest->'schema_version' IN ('5'::JSONB,'6'::JSONB) THEN$b$,1),
  ('internal.claim_observation_analysis(uuid,uuid,uuid)',$a$saved.input_snapshot->'schema_version'='5'::JSONB$a$,$b$saved.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)',$a$saved.input_snapshot->'schema_version'='5'::JSONB$a$,$b$saved.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('public.list_observation_analysis_recovery()',$a$NOT IN ('4'::JSONB,'5'::JSONB)$a$,$b$NOT IN ('4'::JSONB,'5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.guard_composition_completion_selection()',$a$r.evidence_manifest->'schema_version'='5'::JSONB$a$,$b$r.evidence_manifest->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1)
 ) changes(signature,anchor,replacement,expected) LOOP
  definition:=pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>expected THEN
   RAISE EXCEPTION 'focused_composition_runtime_drift: %',signature; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;
DO $constraint$
DECLARE definition TEXT; anchor TEXT:=$a$ARRAY['4'::jsonb, '5'::jsonb]$a$;
BEGIN
 SELECT pg_get_constraintdef(oid) INTO STRICT definition FROM pg_constraint
 WHERE conrelid='internal.observation_analysis_results'::regclass AND conname='observation_analysis_origin';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'focused_composition_origin_drift'; END IF;
 ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_origin;
 EXECUTE 'ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin '||
  replace(definition,anchor,$a$ARRAY['4'::jsonb, '5'::jsonb, '6'::jsonb]$a$);
END;
$constraint$;
NOTIFY pgrst,'reload schema';
RESET statement_timeout;
RESET lock_timeout;

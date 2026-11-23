SET lock_timeout='5s';
SET statement_timeout='2min';

-- Add focused source/allocation support behind independent default-false gates.
-- V5 codecs remain byte-for-byte unchanged; this is not runtime activation.
ALTER TABLE internal.observation_history_rollout
 ADD COLUMN focused_composition_source_reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_source_recovery_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_runtime_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN focused_composition_orchestration_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE FUNCTION internal.observation_composition_request_contract(p_input JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
 CASE p_input->'schema_version'
  WHEN '5'::JSONB THEN RETURN internal.observation_composition_source_contract(p_input);
  WHEN '6'::JSONB THEN RETURN internal.observation_focused_composition_contract(p_input);
  ELSE RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
 END CASE;
END;
$$;
CREATE FUNCTION internal.observation_composition_request_fingerprint(p_input JSONB)
RETURNS TEXT LANGUAGE SQL STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT internal.observation_composition_request_contract(p_input)->>'fingerprint';
$$;
REVOKE ALL ON FUNCTION internal.observation_composition_request_contract(JSONB),
 internal.observation_composition_request_fingerprint(JSONB) FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE internal.observation_analysis_source_bindings
 DROP CONSTRAINT observation_analysis_source_bindings_fingerprint_version_check,
 ADD CONSTRAINT observation_analysis_source_bindings_fingerprint_version_check CHECK(
  fingerprint_version=CASE WHEN input_snapshot->'schema_version'='6'::JSONB THEN 2 ELSE 1 END);

-- Every replacement asserts the exact installed anchor count. Later repairs
-- are retained; source codec definitions are never relabelled as a new version.
DO $patch$
DECLARE signature TEXT; anchor TEXT; replacement TEXT; expected INTEGER; definition TEXT;
BEGIN
 FOR signature,anchor,replacement,expected IN SELECT * FROM (VALUES
  ('internal.observation_composition_source_cohort_items(jsonb)',$a$internal.observation_composition_source_contract(p_input)$a$,$b$internal.observation_composition_request_contract(p_input)$b$,1),
  ('internal.validate_observation_source_binding()',$a$(CASE WHEN NEW.input_snapshot->'schema_version'='5'::JSONB THEN$a$,$b$(CASE WHEN NEW.input_snapshot->'schema_version'='6'::JSONB THEN internal.observation_composition_request_fingerprint(NEW.input_snapshot) WHEN NEW.input_snapshot->'schema_version'='5'::JSONB THEN$b$,1),
  ('internal.lock_owned_observation_composition_source_binding(uuid,uuid,uuid,jsonb)',$a$internal.observation_composition_source_fingerprint(p_expected_input)$a$,$b$internal.observation_composition_request_fingerprint(p_expected_input)$b$,1),
  ('internal.lock_owned_observation_composition_source_binding(uuid,uuid,uuid,jsonb)',$a$binding.fingerprint_version IS DISTINCT FROM 1$a$,$b$binding.fingerprint_version IS DISTINCT FROM (CASE WHEN p_expected_input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$p_reader IS DISTINCT FROM 14$a$,$b$p_reader IS DISTINCT FROM (CASE WHEN p_request->'fingerprint_version'='2'::JSONB THEN 15 ELSE 14 END)$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB$a$,$b$(p_request->'fingerprint_version' IN ('1'::JSONB,'2'::JSONB)) IS NOT TRUE$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$p_reader IS DISTINCT FROM 14$a$,$b$p_reader IS DISTINCT FROM (CASE WHEN p_request->'fingerprint_version'='2'::JSONB THEN 15 ELSE 14 END)$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB$a$,$b$(p_request->'fingerprint_version' IN ('1'::JSONB,'2'::JSONB)) IS NOT TRUE$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$fingerprint:=internal.observation_composition_source_fingerprint(input);$a$,$b$fingerprint:=internal.observation_composition_request_fingerprint(input);
 IF p_request->'fingerprint_version' IS DISTINCT FROM to_jsonb((CASE WHEN input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)) THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$'fingerprint_version',1,'fingerprint',fingerprint$a$,$b$'fingerprint_version',(CASE WHEN input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END),'fingerprint',fingerprint$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$binding.fingerprint_version<>1$a$,$b$binding.fingerprint_version IS DISTINCT FROM (CASE WHEN input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END)$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$VALUES(child,p_owner,observation,source,input,1,fingerprint)$a$,$b$VALUES(child,p_owner,observation,source,input,(CASE WHEN input->'schema_version'='6'::JSONB THEN 2 ELSE 1 END),fingerprint)$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$SELECT composition_source_reservation_enabled AND composition_runtime_enabled FROM$a$,$b$SELECT composition_source_reservation_enabled AND composition_runtime_enabled AND (input->'schema_version'<>'6'::JSONB OR (focused_composition_source_reservation_enabled AND focused_composition_runtime_enabled)) FROM$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$SELECT composition_source_recovery_enabled FROM$a$,$b$SELECT composition_source_recovery_enabled AND (p_request->'fingerprint_version'<>'2'::JSONB OR focused_composition_source_recovery_enabled) FROM$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$,$b$(binding.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)) IS NOT TRUE$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$binding.fingerprint_version IS DISTINCT FROM 1$a$,$b$to_jsonb(binding.fingerprint_version) IS DISTINCT FROM p_request->'fingerprint_version'$b$,1),
  ('get_owned_observation_composition_source(uuid,jsonb,integer)',$a$internal.observation_composition_source_fingerprint(binding.input_snapshot)$a$,$b$internal.observation_composition_request_fingerprint(binding.input_snapshot)$b$,1),
  ('internal.lock_composition_evidence_request(uuid,jsonb,integer)',$a$p_reader IS DISTINCT FROM 14$a$,$b$p_reader IS DISTINCT FROM (CASE WHEN p_request->'fingerprint_version'='2'::JSONB THEN 15 ELSE 14 END)$b$,1),
  ('internal.guard_composition_evidence_allocation()',$a$composition_evidence_enabled AND composition_runtime_enabled$a$,$b$composition_evidence_enabled AND composition_runtime_enabled AND (binding.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_evidence_enabled AND focused_composition_runtime_enabled))$b$,1),
  ('internal.guard_composition_evidence_object()',$a$composition_evidence_enabled AND composition_runtime_enabled$a$,$b$composition_evidence_enabled AND composition_runtime_enabled AND (binding.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_evidence_enabled AND focused_composition_runtime_enabled))$b$,1),
  ('reserve_owned_observation_composition_evidence(uuid,jsonb,integer)',$a$composition_evidence_enabled AND composition_runtime_enabled$a$,$b$composition_evidence_enabled AND composition_runtime_enabled AND (binding.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_evidence_enabled AND focused_composition_runtime_enabled))$b$,1),
  ('complete_owned_observation_composition_evidence(uuid,jsonb,uuid,uuid,integer)',$a$composition_evidence_enabled AND composition_runtime_enabled$a$,$b$composition_evidence_enabled AND composition_runtime_enabled AND (binding.input_snapshot->'schema_version'<>'6'::JSONB OR (focused_composition_evidence_enabled AND focused_composition_runtime_enabled))$b$,1),
  ('internal.guard_composition_evidence_object()',$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$,$b$(binding.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)) IS NOT TRUE$b$,1),
  ('internal.validate_observation_source_cohort()',$a$input_snapshot->'schema_version'='5'::JSONB$a$,$b$input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('internal.guard_observation_source_storage()',$a$b.input_snapshot->'schema_version'='5'::JSONB$a$,$b$b.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('reserve_owned_observation_analysis_source(uuid,jsonb,integer)',$a$predecessor.input_snapshot->'schema_version'='5'::JSONB$a$,$b$predecessor.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('reserve_owned_observation_analysis_source(uuid,jsonb,integer)',$a$b.input_snapshot->'schema_version'='5'::JSONB$a$,$b$b.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,2),
  ('reserve_owned_observation_video_source(uuid,jsonb,integer)',$a$predecessor.input_snapshot->'schema_version'='5'::JSONB$a$,$b$predecessor.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('reserve_owned_observation_video_source(uuid,jsonb,integer)',$a$b.input_snapshot->'schema_version'='5'::JSONB$a$,$b$b.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,2),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$predecessor.input_snapshot->'schema_version'='5'::JSONB$a$,$b$predecessor.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,1),
  ('reserve_owned_observation_composition_source(uuid,jsonb,integer)',$a$b.input_snapshot->'schema_version'='5'::JSONB$a$,$b$b.input_snapshot->'schema_version' IN ('5'::JSONB,'6'::JSONB)$b$,2)
 ) changes(signature,anchor,replacement,expected) LOOP
  definition:=pg_catalog.pg_get_functiondef(signature::REGPROCEDURE);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>expected THEN
   RAISE EXCEPTION 'focused_composition_owner_drift: %',signature; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

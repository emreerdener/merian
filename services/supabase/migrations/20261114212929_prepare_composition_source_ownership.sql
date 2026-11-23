SET lock_timeout='5s';
SET statement_timeout='2min';

-- Composition metadata ownership only. Existing lane bytes and readers stay
-- unchanged. Upload, inference and release are separate closed capabilities.
CREATE FUNCTION internal.lock_owned_observation_composition_source_binding(
    p_owner UUID,p_observation UUID,p_analysis UUID,p_expected_input JSONB
) RETURNS internal.observation_analysis_source_bindings
LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; source UUID; fingerprint TEXT;
BEGIN
    -- Authorization/deletion precedes payload inspection. Never infer the source
    -- from a mutable selected result or an unrelated child binding.
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    fingerprint:=internal.observation_composition_source_fingerprint(p_expected_input);
    source:=(p_expected_input->>'source_analysis_id')::UUID;
    IF p_analysis IS NULL OR p_analysis IN (p_observation,source)
        OR p_expected_input->>'observation_id' IS DISTINCT FROM p_observation::TEXT
        OR p_expected_input->>'analysis_id' IS DISTINCT FROM p_analysis::TEXT THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_source(p_owner,p_observation,source);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || p_analysis::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-history-evidence:' || p_analysis::TEXT,0::BIGINT));
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
    IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner
        OR binding.observation_id IS DISTINCT FROM p_observation
        OR binding.source_analysis_id IS DISTINCT FROM source
        OR binding.input_snapshot IS DISTINCT FROM p_expected_input
        OR binding.fingerprint_version IS DISTINCT FROM 1
        OR binding.fingerprint IS DISTINCT FROM fingerprint
        OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy
            WHERE owner_id=p_owner AND observation_id=p_observation
                AND source_analysis_id=source AND analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN binding;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_owned_observation_composition_source_binding(UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.observation_composition_evidence_upload_cohorts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 items JSONB NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 1 AND 8 AND octet_length(items::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
  REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_composition_evidence_cohorts_parent
 ON internal.observation_composition_evidence_upload_cohorts(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_composition_evidence_upload_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_composition_evidence_upload_cohorts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_composition_cohort()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings;
BEGIN
 IF TG_OP='UPDATE' THEN
  RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023';
 END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
   AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
  END IF;
  RETURN OLD;
 END IF;
 -- Owner/parent -> source -> child locks precede inventory and namespace reads.
 PERFORM internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id);
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_owned_observation_composition_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 IF binding.analysis_id IS NULL OR binding.source_analysis_id IS DISTINCT FROM NEW.source_analysis_id
  OR NEW.items IS DISTINCT FROM internal.observation_composition_source_cohort_items(binding.input_snapshot)
  OR NOT internal.observation_source_child_is_unused(NEW.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_composition_cohort() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_composition_cohort BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_composition_evidence_upload_cohorts FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_composition_cohort();

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN composition_source_reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN composition_source_recovery_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN composition_runtime_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Explicit V5 branches; historical validators and retained proof bytes stay intact.
DO $patch$
DECLARE definition TEXT; anchor TEXT; replacement TEXT; routine TEXT;
BEGIN
 FOR routine,anchor,replacement IN SELECT * FROM (VALUES
 ('internal.validate_observation_source_binding()',
 $a$(CASE WHEN NEW.input_snapshot->'schema_version'='4'::JSONB THEN$a$,
 $b$(CASE WHEN NEW.input_snapshot->'schema_version'='5'::JSONB THEN internal.observation_composition_source_fingerprint(NEW.input_snapshot) WHEN NEW.input_snapshot->'schema_version'='4'::JSONB THEN$b$),
 ('internal.validate_observation_source_binding()',
 $a$        OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)$a$,
 $b$        OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)$b$),
 ('internal.observation_source_child_is_unused(uuid)',
 $a$ AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis)$a$,
 $b$ AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=p_analysis)$b$),
 ('internal.validate_observation_source_cohort()',
 $a$    IF NEW.binding_analysis_id IS NULL THEN RETURN NEW; END IF;$a$,
 $b$    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings
        WHERE analysis_id=NEW.analysis_id AND input_snapshot->'schema_version'='5'::JSONB)
        OR EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF NEW.binding_analysis_id IS NULL THEN RETURN NEW; END IF;$b$),
 ('internal.guard_observation_source_storage()',
 $a$    IF TG_OP='DELETE' THEN$a$,
 $b$    IF TG_OP='DELETE' THEN
        -- V5 has no release proof yet. In particular, never evaluate old proof
        -- codecs against its input. Parent/account deletion still owns erasure.
        IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
            WHERE b.analysis_id=OLD.analysis_id AND b.input_snapshot->'schema_version'='5'::JSONB) THEN
            IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
                AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
                RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
            RETURN OLD;
        END IF;$b$)
 ) patches(routine,anchor,replacement) LOOP
  definition:=pg_catalog.pg_get_functiondef(routine::REGPROCEDURE);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'composition_source_owner_drift: %',routine; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;

 -- Both old reservation lanes account for the new independent namespace.
 FOREACH routine IN ARRAY ARRAY['public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)',
  'public.reserve_owned_observation_video_source(uuid,jsonb,integer)'] LOOP
  definition:=pg_catalog.pg_get_functiondef(routine::REGPROCEDURE);
  anchor:=' OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_reserve_sentinel_drift'; END IF;
  definition:=replace(definition,anchor,anchor||E'
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64');
  anchor:='  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_reserve_coverage_drift'; END IF;
  definition:=replace(definition,anchor,anchor||E'
  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_composition_evidence_upload_cohorts WHERE observation_id=observation');
  anchor:=' IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.observation_id=observation';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_reserve_release_drift'; END IF;
  definition:=replace(definition,anchor,$b$ IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
  WHERE b.observation_id=observation AND b.source_analysis_id=source AND b.input_snapshot->'schema_version'='5'::JSONB) THEN
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
$b$||anchor);
  EXECUTE definition;
 END LOOP;

 definition:=pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_source(uuid,jsonb,integer)'::REGPROCEDURE);
 anchor:='    -- Bounded conservative coverage, not a partial page from which to infer vacancy.';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_discovery_sentinel_drift'; END IF;
 definition:=replace(definition,anchor,anchor||$b$
    IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts
        WHERE observation_id=observation LIMIT 65) q)>64 THEN
        RETURN answer || '{"state":"held","reason":"coverage_incomplete"}'::JSONB;
    END IF;
$b$);
 anchor:='            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_discovery_coverage_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'
            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_composition_evidence_upload_cohorts WHERE observation_id=observation');
END;
$patch$;

-- Copy the currently installed, repaired video reservation logic, changing only
-- closed input/reader identity and the fresh-admission capability. Existing
-- predecessor proofs, account locks and bounded namespace coverage are retained.
DO $codec$
DECLARE definition TEXT; anchor TEXT; replacement TEXT; operation TEXT;
BEGIN
 FOREACH operation IN ARRAY ARRAY['reserve','get'] LOOP
  definition:=pg_catalog.pg_get_functiondef(('public.'||operation||'_owned_observation_video_source(uuid,jsonb,integer)')::REGPROCEDURE);
  FOR anchor,replacement IN SELECT * FROM (VALUES
   ('public.'||operation||'_owned_observation_video_source(', 'public.'||operation||'_owned_observation_composition_source('),
   ('p_reader IS DISTINCT FROM 12', 'p_reader IS DISTINCT FROM 14'),
   ($a$p_request->'schema_version' IS DISTINCT FROM '2'::JSONB$a$, $b$p_request->'schema_version' IS DISTINCT FROM '3'::JSONB$b$)
  ) patches(anchor,replacement) LOOP
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_source_codec_drift'; END IF;
   definition:=replace(definition,anchor,replacement);
  END LOOP;
  IF operation='reserve' THEN
   FOR anchor,replacement IN SELECT * FROM (VALUES
    ('fingerprint:=internal.observation_video_source_fingerprint(input);', 'fingerprint:=internal.observation_composition_source_fingerprint(input);'),
    ($a$jsonb_build_object('schema_version',2,'owner_id',p_owner$a$, $b$jsonb_build_object('schema_version',3,'owner_id',p_owner$b$),
    ('SELECT video_source_reservation_enabled FROM internal.observation_history_rollout', 'SELECT composition_source_reservation_enabled AND composition_runtime_enabled FROM internal.observation_history_rollout')
   ) patches(anchor,replacement) LOOP
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_source_reserve_drift'; END IF;
    definition:=replace(definition,anchor,replacement);
   END LOOP;
  ELSE
   FOR anchor,replacement IN SELECT * FROM (VALUES
    ('SELECT video_source_recovery_enabled FROM internal.observation_history_rollout', 'SELECT composition_source_recovery_enabled FROM internal.observation_history_rollout'),
    ($a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB$a$, $b$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$b$),
    ('internal.observation_video_source_fingerprint(binding.input_snapshot)', 'internal.observation_composition_source_fingerprint(binding.input_snapshot)'),
    ('internal.lock_owned_observation_video_source_binding(p_owner,observation,child,binding.input_snapshot)', 'internal.lock_owned_observation_composition_source_binding(p_owner,observation,child,binding.input_snapshot)')
   ) patches(anchor,replacement) LOOP
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_source_get_drift'; END IF;
    definition:=replace(definition,anchor,replacement);
   END LOOP;
  END IF;
  EXECUTE definition;
 END LOOP;
END;
$codec$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_composition_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_owned_observation_composition_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_composition_source(UUID,JSONB,INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_composition_source(UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_observation_composition_source(uuid,jsonb,integer)','Reader14 schema3 exact V5 metadata reservation, default closed; no upload, quota or execution authority.'),
 ('service_role','public.get_owned_observation_composition_source(uuid,jsonb,integer)','Reader14 exact V5 source lookup, default closed; no vacancy or release proof.');
COMMENT ON TABLE internal.observation_composition_evidence_upload_cohorts IS
 'Immutable ordered V5 artifact inventory under source occupancy; no allocation/readiness or dispatch authority. Retained until parent deletion.';
RESET statement_timeout;
RESET lock_timeout;

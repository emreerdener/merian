SET lock_timeout='5s';
SET statement_timeout='2min';

-- Metadata storage only. The public reservation codec remains photo/audio;
-- no upload receipt, provider admission or new API grant is installed.
CREATE FUNCTION internal.lock_owned_observation_video_source_binding(
    p_owner UUID,p_observation UUID,p_analysis UUID,p_expected_input JSONB
) RETURNS internal.observation_analysis_source_bindings
LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; source UUID; fingerprint TEXT;
BEGIN
    -- Authorization/deletion precedes payload inspection. Never infer the source
    -- from a mutable selected result or an unrelated child binding.
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    fingerprint:=internal.observation_video_source_fingerprint(p_expected_input);
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
REVOKE ALL ON FUNCTION internal.lock_owned_observation_video_source_binding(UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.observation_video_evidence_upload_cohorts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 items JSONB NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 6 AND 7 AND octet_length(items::TEXT)<=4096),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
  REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_video_evidence_cohorts_parent
 ON internal.observation_video_evidence_upload_cohorts(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_video_evidence_upload_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_video_evidence_upload_cohorts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_video_cohort()
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
 binding:=internal.lock_owned_observation_video_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 IF binding.analysis_id IS NULL OR binding.source_analysis_id IS DISTINCT FROM NEW.source_analysis_id
  OR NEW.items IS DISTINCT FROM internal.observation_video_source_cohort_items(binding.input_snapshot)
  OR NOT internal.observation_source_child_is_unused(NEW.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_video_cohort() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_video_cohort BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_video_evidence_upload_cohorts FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_video_cohort();

-- Guarded edits preserve installed replay, completion-proof and lock contracts.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.validate_observation_source_binding()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='internal.observation_source_fingerprint(NEW.input_snapshot)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed binding fingerprint changed'; END IF;
 definition:=replace(definition,anchor,'(CASE WHEN NEW.input_snapshot->''schema_version''=''4''::JSONB THEN internal.observation_video_source_fingerprint(NEW.input_snapshot) ELSE internal.observation_source_fingerprint(NEW.input_snapshot) END)');
 anchor:='        OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed binding namespaces changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n        OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)');

 SELECT pg_catalog.pg_get_functiondef('internal.observation_source_child_is_unused(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' AND NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed child namespaces changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis)');

 SELECT pg_catalog.pg_get_functiondef('public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed reservation sentinel changed'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64');
 anchor:='  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed reservation coverage changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation');

 SELECT pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    -- Bounded conservative coverage, not a partial page from which to infer vacancy.';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed discovery sentinel changed'; END IF;
 definition:=replace(definition,anchor,anchor||$body$
    IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_evidence_upload_cohorts
        WHERE observation_id=observation LIMIT 65) q)>64 THEN
        RETURN answer || '{"state":"held","reason":"coverage_incomplete"}'::JSONB;
    END IF;
$body$);
 anchor:='            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed discovery coverage changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n            UNION ALL SELECT owner_id,analysis_id FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation');

 -- Legacy trusted cohort inserts cannot claim a V4 binding, even with NULL
 -- linkage. Supported RPC writers already take the canonical source locks.
 SELECT pg_catalog.pg_get_functiondef('internal.validate_observation_source_cohort()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF NEW.binding_analysis_id IS NULL THEN RETURN NEW; END IF;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed cohort backstop changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings
        WHERE analysis_id=NEW.analysis_id AND input_snapshot->'schema_version'='4'::JSONB)
        OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$body$||anchor);

END;
$patch$;

COMMENT ON TABLE internal.observation_video_evidence_upload_cohorts IS
 'Private immutable whole V4 inventory bound to live source occupancy. No API writer, object receipt, deadline, readiness or execution authority. Retained until parent deletion; participates in coverage and prevents unfunded retirement.';
RESET statement_timeout;
RESET lock_timeout;

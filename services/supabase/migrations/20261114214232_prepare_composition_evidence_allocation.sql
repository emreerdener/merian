SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN composition_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Raw provenance inventory remains immutable in the original cohort. This
-- separate retained allocation survives receipt cleanup and forbids new keys.
CREATE TABLE internal.observation_composition_evidence_allocations (
 analysis_id UUID PRIMARY KEY REFERENCES internal.observation_composition_evidence_upload_cohorts(analysis_id) ON DELETE CASCADE,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 items JSONB NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 1 AND 8 AND octet_length(items::TEXT)<=16384),
 expires_at TIMESTAMPTZ NOT NULL,
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_composition_evidence_allocations_due ON internal.observation_composition_evidence_allocations(expires_at,analysis_id);
CREATE INDEX observation_composition_evidence_allocations_parent ON internal.observation_composition_evidence_allocations(observation_id);
ALTER TABLE internal.observation_composition_evidence_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_composition_evidence_allocations FROM PUBLIC,anon,authenticated,service_role;


CREATE FUNCTION internal.observation_composition_source_identity(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('schema_version',3,'observation_id',p_binding.observation_id,
 'source_analysis_id',p_binding.source_analysis_id,'analysis_id',p_binding.analysis_id,
 'request_digest',p_binding.input_snapshot->>'request_digest','fingerprint_version',p_binding.fingerprint_version,'fingerprint',p_binding.fingerprint);
$$;
REVOKE ALL ON FUNCTION internal.observation_composition_source_identity(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;
DO $fences$
DECLARE definition TEXT; anchor TEXT; clean TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.observation_source_child_is_unused(uuid)'::regprocedure);
 anchor:=' AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=p_analysis)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_allocation_namespace_drift'; END IF;
 clean:=replace(definition,anchor,'');
 clean:=replace(clean,'internal.observation_source_child_is_unused(', 'internal.observation_composition_source_preexecution_clear(');
 clean:=replace(clean,' AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)',
 ' AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)'||E'\n AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_allocations WHERE analysis_id=p_analysis)');
 EXECUTE clean;
 clean:=replace(definition,anchor,'');
 anchor:=' AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)';
 IF (length(clean)-length(replace(clean,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_allocation_object_drift'; END IF;
 EXECUTE replace(replace(clean,anchor,''),'internal.observation_source_child_is_unused(', 'internal.observation_composition_evidence_execution_clear(');
END;
$fences$;
REVOKE ALL ON FUNCTION internal.observation_composition_source_preexecution_clear(UUID),internal.observation_composition_evidence_execution_clear(UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $clone$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'internal.lock_video_evidence_request(uuid,jsonb,integer)',
 'internal.guard_video_evidence_allocation()',
 'internal.guard_video_evidence_object()',
 'internal.video_evidence_receipt(internal.observation_analysis_source_bindings)',
 'public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)',
 'public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)',
 'internal.retire_expired_observation_video_evidence_worker_impl()',
 'public.retire_expired_observation_video_evidence_for_dispatch(uuid)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  -- Only these exact sibling identifiers are translated; generic lifecycle,
  -- locking, immutable expiry and erasure-obligation owners remain shared.
  FOR anchor,replacement IN SELECT * FROM (VALUES
   ('observation_video_evidence','observation_composition_evidence'),
   ('observation_video_source_identity','observation_composition_source_identity'),
   ('observation_video_source_cohort_items','observation_composition_source_cohort_items'),
   ('observation_video_source_preexecution_clear','observation_composition_source_preexecution_clear'),
   ('lock_owned_observation_video_source_binding','lock_owned_observation_composition_source_binding'),
   ('lock_video_evidence_request','lock_composition_evidence_request'),
   ('guard_video_evidence_allocation','guard_composition_evidence_allocation'),
   ('guard_video_evidence_object','guard_composition_evidence_object'),
   ('video_evidence_receipt','composition_evidence_receipt'),
   ('video_evidence_enabled','composition_evidence_enabled AND composition_runtime_enabled')
  ) changes(anchor,replacement) LOOP
   definition:=replace(definition,anchor,replacement);
  END LOOP;
  IF signature='internal.lock_video_evidence_request(uuid,jsonb,integer)' THEN
   anchor:='p_reader IS DISTINCT FROM 12';
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_evidence_reader_drift'; END IF;
   definition:=replace(definition,anchor,'p_reader IS DISTINCT FROM 14');
   anchor:='octet_length(p_request::TEXT)>4096';
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_evidence_bound_drift'; END IF;
   definition:=replace(definition,anchor,'octet_length(p_request::TEXT)>16384');
  ELSIF signature='internal.guard_video_evidence_object()' THEN
   anchor:=$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_object_schema_drift'; END IF;
   definition:=replace(definition,anchor,$a$binding.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB$a$);
  END IF;
  EXECUTE definition;
 END LOOP;
END;
$clone$;
CREATE TRIGGER guard_composition_evidence_allocation BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_composition_evidence_allocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_evidence_allocation();
CREATE TRIGGER a_guard_composition_evidence_object BEFORE INSERT OR UPDATE ON internal.observation_evidence_objects
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_evidence_object();
-- The object guard must run before the shared receipt guard; an allocation is
-- the only authority for this new lane's keys, immutable expiry and readiness.
DO $patch$
DECLARE definition TEXT; anchor TEXT; signature TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.guard_observation_upload_receipt()'::regprocedure);
 anchor:='    SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_receipt_guard_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$
    IF EXISTS(SELECT 1 FROM internal.observation_composition_evidence_allocations WHERE analysis_id=NEW.analysis_id) THEN
        -- a_guard_composition_evidence_object already validated all associations.
        RETURN NEW;
    END IF;
$a$||anchor);
 definition:=pg_get_functiondef('internal.retire_expired_observation_evidence_worker_impl()'::regprocedure);
 anchor:='            AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations v WHERE v.analysis_id=e.analysis_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_orphan_cleanup_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n            AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_allocations v WHERE v.analysis_id=e.analysis_id)');
 FOREACH signature IN ARRAY ARRAY['internal.expire_observation_evidence(uuid)','internal.expire_unbound_observation_evidence(uuid)'] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:='        AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations WHERE analysis_id=saved.analysis_id)';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_single_object_cleanup_drift'; END IF;
  EXECUTE replace(definition,anchor,anchor||E'\n        AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_allocations WHERE analysis_id=saved.analysis_id)');
 END LOOP;
END;
$patch$;
REVOKE ALL ON FUNCTION internal.lock_composition_evidence_request(UUID,JSONB,INTEGER),
 internal.guard_composition_evidence_allocation(),internal.guard_composition_evidence_object(),
 internal.composition_evidence_receipt(internal.observation_analysis_source_bindings),
 internal.retire_expired_observation_composition_evidence_worker_impl() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_composition_evidence(UUID,JSONB,INTEGER),
 public.complete_owned_observation_composition_evidence(UUID,JSONB,UUID,UUID,INTEGER),
 public.retire_expired_observation_composition_evidence_for_dispatch(UUID) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_composition_evidence(UUID,JSONB,INTEGER),
 public.complete_owned_observation_composition_evidence(UUID,JSONB,UUID,UUID,INTEGER),
 public.retire_expired_observation_composition_evidence_for_dispatch(UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_observation_composition_evidence(uuid,jsonb,integer)','Default-closed reader14 whole-composition allocation under source ownership; no inference.'),
 ('service_role','public.complete_owned_observation_composition_evidence(uuid,jsonb,uuid,uuid,integer)','Acknowledge one byte-verified member of an immutable complete mixed inventory.'),
 ('service_role','public.retire_expired_observation_composition_evidence_for_dispatch(uuid)','Retire one expired composition only under the current correlated private cleanup dispatch.');
RESET statement_timeout;
RESET lock_timeout;

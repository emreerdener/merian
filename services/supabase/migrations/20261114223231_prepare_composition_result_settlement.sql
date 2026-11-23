SET lock_timeout='5s';
SET statement_timeout='2min';

-- V5 result and settlement evidence has separate private proof tables; old
-- receipts cannot authorize this lane. Nothing grants a public execution entry.

CREATE TABLE internal.observation_composition_accounting_receipts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_composition_accounting_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_composition_accounting_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.observation_composition_terminal_receipts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_composition_terminal_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_composition_terminal_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE internal.observation_composition_source_completions (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.observation_composition_source_completions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_composition_source_completions FROM PUBLIC,anon,authenticated,service_role;

-- A server-generated selection operation cannot be preclaimed through the public
-- selection API. It commits atomically with the result and its selection receipt.
CREATE TABLE internal.composition_completion_selections (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 operation_id UUID NOT NULL,
 UNIQUE(observation_id,operation_id),
 CHECK(operation_id NOT IN (owner_id,observation_id,analysis_id,source_analysis_id)),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
ALTER TABLE internal.composition_completion_selections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.composition_completion_selections FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.guard_composition_completion_selection()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
  AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN OLD;
 END IF;
 IF current_setting('merian.composition_completion',TRUE) IS DISTINCT FROM NEW.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT
 OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=NEW.analysis_id
  AND r.observation_id=NEW.observation_id AND r.source_analysis_id=NEW.source_analysis_id
  AND r.evidence_manifest->'schema_version'='5'::JSONB) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER guard_composition_completion_selection BEFORE INSERT OR UPDATE OR DELETE ON internal.composition_completion_selections
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_completion_selection();
REVOKE ALL ON FUNCTION internal.guard_composition_completion_selection() FROM PUBLIC,anon,authenticated,service_role;

CREATE INDEX observation_composition_source_completions_source
 ON internal.observation_composition_source_completions(observation_id,source_analysis_id,analysis_id);
DO $clone$
DECLARE signature TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'internal.video_analysis_accounting_product(internal.observation_analysis_intents)',
 'internal.video_analysis_accounting_invocation(internal.observation_analysis_intents)',
 'internal.video_analysis_accounting_candidate(internal.observation_analysis_intents)',
 'internal.guard_video_analysis_accounting()',
 'internal.account_video_observation_draft(uuid,uuid,uuid,uuid)',
 'internal.video_analysis_terminal_product(internal.observation_analysis_intents)',
 'internal.video_analysis_terminal_accounting(internal.observation_analysis_intents)',
 'internal.video_analysis_terminal_candidate(internal.observation_analysis_intents)',
 'internal.guard_video_analysis_terminal()',
 'internal.settle_video_observation_terminal(uuid,uuid,uuid,uuid)',
 'internal.assert_accounted_video_analysis(internal.observation_analysis_intents)',
 'internal.assert_video_completion_evidence(internal.observation_analysis_intents)',
 'internal.video_analysis_completion_matches(internal.observation_analysis_intents)',
 'internal.complete_video_observation_analysis(uuid,uuid,uuid,uuid)',
 'internal.video_source_completion_product(internal.observation_analysis_source_bindings)',
 'internal.video_source_completion_candidate(internal.observation_analysis_source_bindings)',
 'internal.video_source_completion_proven(internal.observation_analysis_source_bindings)',
 'internal.guard_video_source_completion()',
 'internal.release_completed_video_source(uuid,uuid,uuid)'
 ] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  FOR anchor,replacement IN SELECT * FROM (VALUES
   ('observation_video_evidence_upload_cohorts','observation_composition_evidence_upload_cohorts'),
   ('assert_video_analysis_dispatch_identity','assert_composition_analysis_dispatch_identity'),
   ('observation_video_evidence_allocations','observation_composition_evidence_allocations'),
   ('observation_video_source_cohort_items','observation_composition_source_cohort_items'),
   ('observation_video_accounting_receipts','observation_composition_accounting_receipts'),
   ('video_analysis_accounting_invocation','composition_analysis_accounting_invocation'),
   ('observation_video_source_fingerprint','observation_composition_source_fingerprint'),
   ('observation_video_source_completions','observation_composition_source_completions'),
   ('video_analysis_accounting_candidate','composition_analysis_accounting_candidate'),
   ('complete_video_observation_analysis','complete_composition_observation_analysis'),
   ('observation_video_terminal_receipts','observation_composition_terminal_receipts'),
   ('video_analysis_terminal_accounting','composition_analysis_terminal_accounting'),
   ('video_analysis_accounting_product','composition_analysis_accounting_product'),
   ('video_analysis_terminal_candidate','composition_analysis_terminal_candidate'),
   ('settle_video_observation_terminal','settle_composition_observation_terminal'),
   ('video_analysis_completion_matches','composition_analysis_completion_matches'),
   ('video_source_completion_candidate','composition_source_completion_candidate'),
   ('assert_video_completion_evidence','assert_composition_completion_evidence'),
   ('guard_video_analysis_accounting','guard_composition_analysis_accounting'),
   ('account_video_observation_draft','account_composition_observation_draft'),
   ('video_analysis_terminal_product','composition_analysis_terminal_product'),
   ('assert_accounted_video_analysis','assert_accounted_composition_analysis'),
   ('video_source_completion_product','composition_source_completion_product'),
   ('lock_video_observation_analysis','lock_composition_observation_analysis'),
   ('video_source_completion_proven','composition_source_completion_proven'),
   ('release_completed_video_source','release_completed_composition_source'),
   ('merian.video_source_completion','merian.composition_source_completion'),
   ('guard_video_analysis_terminal','guard_composition_analysis_terminal'),
   ('guard_video_source_completion','guard_composition_source_completion'),
   ('merian.video_accounting','merian.composition_accounting'),
   ('merian.video_completion','merian.composition_completion'),
   ('video_evidence_receipt','composition_evidence_receipt'),
   ('merian.video_terminal','merian.composition_terminal')
  ) changes(anchor,replacement) LOOP definition:=replace(definition,anchor,replacement); END LOOP;
  -- Only input/manifest generation and completion snapshot generation change;
  -- proof schema1, identities, funding and captured-result replay stay exact.
  definition:=replace(definition,$a$input_snapshot->'schema_version'='4'::JSONB$a$,$a$input_snapshot->'schema_version'='5'::JSONB$a$);
  IF signature='internal.video_analysis_accounting_invocation(internal.observation_analysis_intents)' THEN
   anchor:=$a$(CASE WHEN i.input_snapshot#>'{evidence_manifest,provenance,audio}'='null'::JSONB THEN 'multimodal_video_frames_v1' ELSE 'multimodal_video_audio_v1' END)$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_accounting_profile_drift'; END IF;
   definition:=replace(definition,anchor,'internal.observation_composition_execution_profile(i.input_snapshot)');
  ELSIF signature='internal.video_analysis_completion_matches(internal.observation_analysis_intents)' THEN
   anchor:=$a$jsonb_build_object('schema_version',5,'observation_id'$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_completion_snapshot_drift'; END IF;
   definition:=replace(definition,anchor,$a$jsonb_build_object('schema_version',6,'observation_id'$a$);
   -- Auto-selection is proved by its immutable receipt, not by mutable current state.
   anchor:=$a$ AND EXISTS(SELECT 1 FROM internal.observation_analysis_results r$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_selection_proof_drift'; END IF;
   definition:=replace(definition,anchor,$a$ AND EXISTS(SELECT 1 FROM internal.observation_selection_receipts s
     JOIN internal.composition_completion_selections c ON c.observation_id=s.observation_id AND c.operation_id=s.operation_id
     WHERE c.analysis_id=i.analysis_id AND c.owner_id=i.owner_id AND c.observation_id=i.observation_id
       AND c.source_analysis_id=internal.source_child_uuid(i.input_snapshot->>'source_analysis_id')
       AND s.request_identity=jsonb_build_object('schema_version',1,'observation_id',i.observation_id,'analysis_id',i.analysis_id,
         'operation_id',s.operation_id,'expected_observation_revision',s.request_identity->'expected_observation_revision','expected_review_revision',0)
       AND s.receipt->>'outcome' IS DISTINCT FROM 'revision_conflict'
       AND s.receipt->>'operation_id'=s.operation_id::TEXT AND s.receipt->>'observation_id'=i.observation_id::TEXT
       AND s.receipt->>'selected_analysis_id'=i.analysis_id::TEXT AND s.receipt->'review_revision'='0'::JSONB
       AND (s.receipt->>'observation_revision')::BIGINT=(s.request_identity->>'expected_observation_revision')::BIGINT+1)
$a$||anchor);
  ELSIF signature='internal.complete_video_observation_analysis(uuid,uuid,uuid,uuid)' THEN
   anchor:=' initial_authority JSONB:=';
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_selection_declaration_drift'; END IF;
   definition:=replace(definition,anchor,$a$ selection_receipt JSONB; selection_operation UUID:=gen_random_uuid();
$a$||anchor);
   anchor:=' INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) VALUES(p_observation,p_analysis,initial_authority);';
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_selection_authority_drift'; END IF;
   definition:=replace(definition,anchor,anchor||$a$
 -- The existing private selection transaction owns projection, revision and reconciliation.
 -- The parent lock includes any selection made while analysis was running.
 -- This occurs only on first completion; replay never reselects the child.
 IF selection_operation IN (p_owner,p_observation,p_analysis,internal.source_child_uuid(i.input_snapshot->>'source_analysis_id')) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 PERFORM set_config('merian.composition_completion',p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT,TRUE);
 INSERT INTO internal.composition_completion_selections(analysis_id,owner_id,observation_id,source_analysis_id,operation_id)
 VALUES(p_analysis,p_owner,p_observation,internal.source_child_uuid(i.input_snapshot->>'source_analysis_id'),selection_operation);
 PERFORM set_config('merian.composition_completion',COALESCE(prior_fence,''),TRUE);
 selection_receipt:=internal.select_observation_analysis(p_owner,jsonb_build_object('schema_version',1,
  'observation_id',p_observation,'analysis_id',p_analysis,'operation_id',selection_operation,
  'expected_observation_revision',history.state_revision,'expected_review_revision',0));
 IF selection_receipt->>'operation_id' IS DISTINCT FROM selection_operation::TEXT
  OR selection_receipt->>'observation_id' IS DISTINCT FROM p_observation::TEXT
  OR selection_receipt->>'selected_analysis_id' IS DISTINCT FROM p_analysis::TEXT
  OR selection_receipt->>'previous_analysis_id' IS DISTINCT FROM history.selected_analysis_id::TEXT
  OR selection_receipt->'observation_revision' IS DISTINCT FROM to_jsonb(history.state_revision+1)
  OR selection_receipt->'review_revision' IS DISTINCT FROM '0'::JSONB THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
$a$);
   definition:=replace(definition,'-- Initialized selection, review authority, reconciliation and occupancy stay',
      '-- Selection and reconciliation were committed above; saved review and occupancy stay');
  ELSIF signature='internal.assert_video_completion_evidence(internal.observation_analysis_intents)' THEN
   anchor:=$a$ OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=i.analysis_id)$a$;
   IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_completion_cohort_drift'; END IF;
   definition:=replace(definition,anchor,anchor||$a$
 OR EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=i.analysis_id)$a$);
  END IF;
  EXECUTE definition;
 END LOOP;
END;
$clone$;
CREATE TRIGGER guard_composition_analysis_accounting BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_composition_accounting_receipts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_analysis_accounting();
CREATE TRIGGER guard_composition_analysis_terminal BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_composition_terminal_receipts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_analysis_terminal();
CREATE TRIGGER guard_composition_source_completion BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_composition_source_completions
 FOR EACH ROW EXECUTE FUNCTION internal.guard_composition_source_completion();
REVOKE ALL ON FUNCTION internal.composition_analysis_accounting_product(internal.observation_analysis_intents),
 internal.composition_analysis_accounting_invocation(internal.observation_analysis_intents),
 internal.composition_analysis_accounting_candidate(internal.observation_analysis_intents),
 internal.guard_composition_analysis_accounting(),
 internal.account_composition_observation_draft(uuid,uuid,uuid,uuid),
 internal.composition_analysis_terminal_product(internal.observation_analysis_intents),
 internal.composition_analysis_terminal_accounting(internal.observation_analysis_intents),
 internal.composition_analysis_terminal_candidate(internal.observation_analysis_intents),
 internal.guard_composition_analysis_terminal(),
 internal.settle_composition_observation_terminal(uuid,uuid,uuid,uuid),
 internal.assert_accounted_composition_analysis(internal.observation_analysis_intents),
 internal.assert_composition_completion_evidence(internal.observation_analysis_intents),
 internal.composition_analysis_completion_matches(internal.observation_analysis_intents),
 internal.complete_composition_observation_analysis(uuid,uuid,uuid,uuid),
 internal.composition_source_completion_product(internal.observation_analysis_source_bindings),
 internal.composition_source_completion_candidate(internal.observation_analysis_source_bindings),
 internal.composition_source_completion_proven(internal.observation_analysis_source_bindings),
 internal.guard_composition_source_completion(),
 internal.release_completed_composition_source(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Snapshot6 is distinct from video snapshot5. Every result insert is backed by
-- the exact accounted draft and full retained allocation, never caller claims.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.observation_analysis_snapshot(uuid,uuid,uuid,text,integer,timestamp with time zone,jsonb,jsonb)'::regprocedure);
 anchor:=$a$CASE WHEN evidence->'schema_version'='4'::JSONB THEN 5$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_snapshot_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$CASE WHEN evidence->'schema_version'='5'::JSONB THEN 6 WHEN evidence->'schema_version'='4'::JSONB THEN 5$a$);
 SELECT pg_get_constraintdef(oid) INTO STRICT definition FROM pg_constraint
 WHERE conrelid='internal.observation_analysis_results'::regclass AND conname='observation_analysis_origin';
 -- PostgreSQL normalizes this CHECK; permit V5 only in the existing required
 -- source/digest/completion arm, without weakening legacy imported results.
 anchor:=$a$(evidence_manifest -> 'schema_version'::text) = '4'::jsonb$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_origin_constraint_drift'; END IF;
 ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_origin;
 EXECUTE 'ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin '||
 replace(definition,anchor,$a$(evidence_manifest -> 'schema_version'::text) IN ('4'::jsonb,'5'::jsonb)$a$);
 definition:=pg_get_functiondef('internal.guard_observation_media_binding()'::regprocedure);
 anchor:=$a$    IF NEW.evidence_manifest->'schema_version'='4'::JSONB THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_media_guard_drift'; END IF;
 EXECUTE replace(definition,anchor,$a$    IF NEW.evidence_manifest->'schema_version'='5'::JSONB THEN
        SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id AND observation_id=NEW.observation_id;
        IF NOT FOUND OR saved.state IS DISTINCT FROM 'draft' OR saved.input_snapshot->'schema_version' IS DISTINCT FROM '5'::JSONB
        OR saved.draft->'result_snapshot' IS DISTINCT FROM NEW.result_snapshot OR saved.input_snapshot->'evidence_manifest' IS DISTINCT FROM NEW.evidence_manifest
        OR saved.input_snapshot->>'source_analysis_id' IS DISTINCT FROM NEW.source_analysis_id::TEXT
        OR saved.input_snapshot->>'request_digest' IS DISTINCT FROM NEW.request_digest
        OR current_setting('merian.composition_completion',TRUE) IS DISTINCT FROM saved.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT THEN
            RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_accounted_composition_analysis(saved);
        PERFORM internal.assert_composition_completion_evidence(saved);
        RETURN NEW;
    ELSIF EXISTS(SELECT 1 FROM internal.observation_composition_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$a$||anchor);
 definition:=pg_get_functiondef('internal.guard_observation_source_storage()'::regprocedure);
 anchor:=$a$            WHERE b.analysis_id=OLD.analysis_id AND b.input_snapshot->'schema_version'='5'::JSONB) THEN$a$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_release_guard_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||$a$
            IF TG_TABLE_NAME='observation_analysis_source_occupancy' AND EXISTS(
                SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=OLD.analysis_id
                AND b.owner_id=OLD.owner_id AND b.observation_id=OLD.observation_id AND b.source_analysis_id=OLD.source_analysis_id
                AND internal.composition_source_completion_proven(b)) THEN RETURN OLD; END IF;
$a$);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

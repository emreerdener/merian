SET lock_timeout='5s';
SET statement_timeout='2min';

-- Separate from photo/audio completion and pre-execution video retirement.
-- The existing source_completion_release_enabled gate remains default false.
CREATE TABLE internal.observation_video_source_completions (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_video_source_completions_source ON internal.observation_video_source_completions(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_video_source_completions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_video_source_completions FROM PUBLIC,anon,authenticated,service_role;

-- Permanent product identity excludes mutable review, selection and entitlement.
CREATE FUNCTION internal.video_source_completion_product(b internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('identity',internal.observation_video_source_identity(b),'owner_id',b.owner_id,
 'accounted_product',internal.video_analysis_accounting_product(i),
 'receipt_sha256',encode(extensions.digest(i.receipt::TEXT,'sha256'),'hex'),
 'ordinal',r.ordinal,'completed_at_us',floor(extract(epoch FROM r.completed_at)*1000000),
 'result_sha256',encode(extensions.digest(r.result_snapshot::TEXT,'sha256'),'hex'),
 'evidence_sha256',encode(extensions.digest(r.evidence_manifest::TEXT,'sha256'),'hex'))
 FROM internal.observation_analysis_intents i JOIN internal.observation_analysis_results r USING(analysis_id)
 WHERE i.analysis_id=b.analysis_id AND i.owner_id=b.owner_id AND i.observation_id=b.observation_id
 AND i.input_snapshot=b.input_snapshot AND b.input_snapshot->'schema_version'='4'::JSONB
 AND b.source_analysis_id::TEXT=i.input_snapshot->>'source_analysis_id' AND b.fingerprint_version=1
 AND b.fingerprint=internal.observation_video_source_fingerprint(b.input_snapshot)
 AND i.provider_usage=i.provider_outcome->'usage'
 AND internal.video_analysis_accounting_product(i) IS NOT NULL AND internal.video_analysis_completion_matches(i);
$$;

-- Called only after successful completion under its canonical locks. Durable
-- accounting proof replaces live invocation/ledger lookups; expiry is irrelevant.
CREATE FUNCTION internal.video_source_completion_candidate(b internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE i internal.observation_analysis_intents; a internal.observation_video_accounting_receipts;
 q internal.ai_quota_reservations; c internal.complimentary_scan_usage; product JSONB; settlement JSONB;
BEGIN
 product:=internal.video_source_completion_product(b);
 IF product IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO i FROM internal.observation_analysis_intents WHERE analysis_id=b.analysis_id;
 SELECT * INTO a FROM internal.observation_video_accounting_receipts WHERE analysis_id=b.analysis_id;
 IF NOT FOUND OR a.owner_id IS DISTINCT FROM b.owner_id OR a.observation_id IS DISTINCT FROM b.observation_id
 OR a.source_analysis_id IS DISTINCT FROM b.source_analysis_id OR a.proof->'product' IS DISTINCT FROM internal.video_analysis_accounting_product(i)
 OR i.provider_usage IS DISTINCT FROM i.provider_outcome->'usage'
 OR EXISTS(SELECT 1 FROM internal.observation_video_terminal_receipts WHERE analysis_id=b.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=b.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=b.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE analysis_id=b.analysis_id)
 OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses w WHERE w.analysis_id=b.analysis_id
 AND w.owner_id=b.owner_id AND w.observation_id=b.observation_id AND w.source_analysis_id=b.source_analysis_id
 AND w.fingerprint=b.fingerprint AND w.reservation_id::TEXT=i.quota->>'reservation_id' AND w.attempt_count=1
 AND w.lease_sha256=encode(extensions.digest(i.quota->>'lease_token','sha256'),'hex') AND w.provenance=i.provider_outcome->'provenance')
 THEN RETURN NULL; END IF;
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(i.quota->>'reservation_id') FOR UPDATE;
 IF NOT FOUND OR q.user_id IS DISTINCT FROM b.owner_id OR q.original_analysis_id IS DISTINCT FROM b.analysis_id
 OR q.request_id IS DISTINCT FROM b.analysis_id OR q.operation IS DISTINCT FROM 'scan_identification'
 OR q.state IS DISTINCT FROM 'committed' OR q.committed_at IS NULL OR q.failed_at IS NOT NULL OR q.refund_count<>0 OR q.attempt_count<>1
 OR q.lease_token::TEXT IS DISTINCT FROM i.quota->>'lease_token'
 OR to_jsonb(q.complimentary_client_scan_id) IS DISTINCT FROM NULLIF(i.quota->'complimentary_client_scan_id','null'::JSONB)
 THEN RETURN NULL; END IF;
 SELECT * INTO c FROM internal.complimentary_scan_usage WHERE user_id=b.owner_id AND client_scan_id=b.analysis_id FOR UPDATE;
 IF i.quota->'complimentary_client_scan_id'='null'::JSONB THEN
  IF FOUND OR i.receipt->'credit_consumed' IS DISTINCT FROM 'false'::JSONB THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state','not_allocated','reason',NULL,'settled_at_us',NULL,'credit_consumed',FALSE);
 ELSE
  IF NOT FOUND OR i.quota->>'complimentary_client_scan_id' IS DISTINCT FROM b.analysis_id::TEXT OR c.settled_at IS NULL
  OR ((c.state='consumed' AND c.settlement_reason='durable_result_complete' AND i.receipt->'credit_consumed'='true'::JSONB)
   OR (c.state='released' AND c.settlement_reason='paid_before_completion' AND i.receipt->'credit_consumed'='false'::JSONB)) IS NOT TRUE THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state',c.state,'reason',c.settlement_reason,'settled_at_us',floor(extract(epoch FROM c.settled_at)*1000000),'credit_consumed',i.receipt->'credit_consumed');
 END IF;
 RETURN jsonb_build_object('schema_version',1,'product',product,'execution',a.proof->'execution','accounting',a.proof->'accounting','settlement',settlement);
END;
$$;

CREATE FUNCTION internal.video_source_completion_proven(b internal.observation_analysis_source_bindings)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM internal.observation_video_source_completions c WHERE c.analysis_id=b.analysis_id
 AND c.owner_id=b.owner_id AND c.observation_id=b.observation_id AND c.source_analysis_id=b.source_analysis_id
 AND c.proof->'schema_version'='1'::JSONB AND c.proof->'product'=internal.video_source_completion_product(b));
$$;

CREATE FUNCTION internal.guard_video_source_completion()
RETURNS TRIGGER LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE b internal.observation_analysis_source_bindings; expected JSONB;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
  AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN OLD;
 END IF;
 IF current_setting('merian.video_source_completion',TRUE) IS DISTINCT FROM NEW.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO b FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND OR b.owner_id IS DISTINCT FROM NEW.owner_id OR b.observation_id IS DISTINCT FROM NEW.observation_id
 OR b.source_analysis_id IS DISTINCT FROM NEW.source_analysis_id
 OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy o WHERE o.analysis_id=b.analysis_id
 AND o.owner_id=b.owner_id AND o.observation_id=b.observation_id AND o.source_analysis_id=b.source_analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 expected:=internal.video_source_completion_candidate(b);
 IF expected IS NULL OR NEW.proof IS DISTINCT FROM expected THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER guard_video_source_completion BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_video_source_completions FOR EACH ROW EXECUTE FUNCTION internal.guard_video_source_completion();

CREATE FUNCTION internal.release_completed_video_source(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE b internal.observation_analysis_source_bindings; proof JSONB;
BEGIN
 IF current_setting('merian.video_source_completion',TRUE) IS DISTINCT FROM p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF (SELECT source_completion_release_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN; END IF;
 SELECT * INTO b FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
 IF NOT FOUND OR b.owner_id IS DISTINCT FROM p_owner OR b.observation_id IS DISTINCT FROM p_observation
 OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy o WHERE o.analysis_id=p_analysis
 AND o.owner_id=p_owner AND o.observation_id=p_observation AND o.source_analysis_id=b.source_analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 proof:=internal.video_source_completion_candidate(b);
 IF proof IS NULL THEN RETURN; END IF;
 INSERT INTO internal.observation_video_source_completions VALUES(p_analysis,p_owner,p_observation,b.source_analysis_id,proof);
 DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_analysis AND owner_id=p_owner
 AND observation_id=p_observation AND source_analysis_id=b.source_analysis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.video_source_completion_product(internal.observation_analysis_source_bindings),
 internal.video_source_completion_candidate(internal.observation_analysis_source_bindings),
 internal.video_source_completion_proven(internal.observation_analysis_source_bindings),
 internal.guard_video_source_completion(),internal.release_completed_video_source(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE routine TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOR routine,anchor,replacement IN SELECT * FROM (VALUES
 ('internal.complete_video_observation_analysis(uuid,uuid,uuid,uuid)',
 $old$ -- Initialized selection, review authority, reconciliation and occupancy stay
 -- unchanged. Source release requires its separate durable proof contract.$old$,
 $new$ prior_fence:=current_setting('merian.video_source_completion',TRUE);
 PERFORM set_config('merian.video_source_completion',p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT,TRUE);
 PERFORM internal.release_completed_video_source(p_owner,p_observation,p_analysis);
 PERFORM set_config('merian.video_source_completion',COALESCE(prior_fence,''),TRUE);
 -- Selection, review authority and reconciliation remain unchanged.$new$),
 ('internal.guard_observation_source_storage()',
 $old$    IF TG_OP='DELETE' THEN$old$,
 $new$    IF TG_OP='DELETE' THEN
        IF TG_TABLE_NAME='observation_analysis_source_occupancy' AND EXISTS(
            SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=OLD.analysis_id
            AND b.owner_id=OLD.owner_id AND b.observation_id=OLD.observation_id AND b.source_analysis_id=OLD.source_analysis_id
            AND internal.video_source_completion_proven(b)) THEN RETURN OLD; END IF;$new$),
 ('internal.guard_observation_source_storage()',
 $old$    RETURN NEW;$old$,
 $new$    IF EXISTS(SELECT 1 FROM internal.observation_video_source_completions WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    RETURN NEW;$new$),
 ('internal.observation_video_source_release_proven(internal.observation_analysis_source_bindings)',
 $old$ SELECT internal.observation_video_retirement_record_valid(p_binding)$old$,
 $new$ SELECT (internal.video_source_completion_proven(p_binding)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_binding.analysis_id))
 OR internal.observation_video_retirement_record_valid(p_binding)$new$),
 ('public.reserve_owned_observation_video_source(uuid,jsonb,integer)',
 $old$ IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source) THEN$old$,
 $new$ IF EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.observation_id=observation AND r.source_analysis_id=source
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=r.analysis_id
 AND b.owner_id=p_owner AND b.observation_id=observation AND b.source_analysis_id=source
 AND ((b.input_snapshot->'schema_version'='4'::JSONB AND internal.observation_video_source_release_proven(b))
 OR (b.input_snapshot->'schema_version'<>'4'::JSONB AND internal.observation_source_completion_proven(b))))) THEN$new$),
 ('public.reserve_owned_observation_video_source(uuid,jsonb,integer)',
 $old$ OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_source_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64$old$,
 $new$ OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_source_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_source_completions WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_completion_receipts WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64$new$)
 ) patches(routine,anchor,replacement) LOOP
 definition:=pg_get_functiondef(routine::regprocedure);
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'video_source_completion_drift'; END IF;
 EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- Durable accounting, not a work lease or a fresh admission, authorizes known
-- result completion. This proof survives invocation retention.
CREATE FUNCTION internal.assert_accounted_video_analysis(i internal.observation_analysis_intents)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE a internal.observation_video_accounting_receipts; q internal.ai_quota_reservations; product JSONB;
BEGIN
 PERFORM internal.assert_video_analysis_dispatch_identity(i);
 product:=internal.video_analysis_accounting_product(i);
 SELECT * INTO a FROM internal.observation_video_accounting_receipts WHERE analysis_id=i.analysis_id;
 IF NOT FOUND OR product IS NULL OR a.owner_id IS DISTINCT FROM i.owner_id OR a.observation_id IS DISTINCT FROM i.observation_id
 OR a.source_analysis_id::TEXT IS DISTINCT FROM i.input_snapshot->>'source_analysis_id' OR a.proof->'product' IS DISTINCT FROM product
 OR i.state NOT IN ('draft','complete') OR i.terminal_reason IS NOT NULL OR i.provider_usage IS DISTINCT FROM i.provider_outcome->'usage'
 OR EXISTS(SELECT 1 FROM internal.observation_video_terminal_receipts WHERE analysis_id=i.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=internal.source_child_uuid(i.quota->>'reservation_id') FOR UPDATE;
 IF NOT FOUND OR q.user_id IS DISTINCT FROM i.owner_id OR q.original_analysis_id IS DISTINCT FROM i.analysis_id
 OR q.request_id IS DISTINCT FROM i.analysis_id OR q.operation IS DISTINCT FROM 'scan_identification'
 OR q.state IS DISTINCT FROM 'committed' OR q.committed_at IS NULL OR q.failed_at IS NOT NULL OR q.refund_count<>0 OR q.attempt_count<>1
 OR q.lease_token::TEXT IS DISTINCT FROM i.quota->>'lease_token'
 OR to_jsonb(q.complimentary_client_scan_id) IS DISTINCT FROM NULLIF(i.quota->'complimentary_client_scan_id','null'::JSONB) THEN
  RAISE EXCEPTION 'analysis_history_accounting_unproven' USING ERRCODE='55000'; END IF;
END;
$$;

-- Caller already holds canonical owner/source/child/intent locks. Expiration
-- limits fresh execution only; retained exact ready bytes may complete late.
CREATE FUNCTION internal.assert_video_completion_evidence(i internal.observation_analysis_intents)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE b internal.observation_analysis_source_bindings; c internal.observation_video_evidence_upload_cohorts;
BEGIN
 SELECT * INTO b FROM internal.observation_analysis_source_bindings WHERE analysis_id=i.analysis_id;
 SELECT * INTO c FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=i.analysis_id FOR UPDATE;
 IF NOT FOUND OR c.owner_id IS DISTINCT FROM i.owner_id OR c.observation_id IS DISTINCT FROM i.observation_id
 OR c.source_analysis_id IS DISTINCT FROM b.source_analysis_id OR c.items IS DISTINCT FROM internal.observation_video_source_cohort_items(i.input_snapshot)
 OR EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=i.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=i.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.observation_video_evidence_allocations WHERE analysis_id=i.analysis_id FOR UPDATE;
 PERFORM 1 FROM internal.observation_evidence_objects WHERE analysis_id=i.analysis_id ORDER BY media_id FOR UPDATE;
 IF internal.video_evidence_receipt(b)->>'state' IS DISTINCT FROM 'ready' THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
END;
$$;

-- Existing audio result4 and imported result3 remain unchanged. Video's input
-- and manifest version4 maps to its distinct result snapshot5.
DO $patch$
DECLARE definition TEXT; old TEXT:=$old$CASE WHEN internal.is_audio_analysis_manifest(evidence) THEN 4$old$;
BEGIN
 definition:=pg_get_functiondef('internal.observation_analysis_snapshot(uuid,uuid,uuid,text,integer,timestamp with time zone,jsonb,jsonb)'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'video_completion_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$CASE WHEN evidence->'schema_version'='4'::JSONB THEN 5
            WHEN internal.is_audio_analysis_manifest(evidence) THEN 4$new$);
END;
$patch$;
DO $patch$
DECLARE definition TEXT; old TEXT:=$old$WHEN internal.is_audio_analysis_manifest(evidence_manifest)$old$;
BEGIN
 SELECT pg_get_constraintdef(oid) INTO STRICT definition FROM pg_constraint WHERE conrelid='internal.observation_analysis_results'::regclass AND conname='observation_analysis_origin';
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'video_completion_source_drift'; END IF;
 ALTER TABLE internal.observation_analysis_results DROP CONSTRAINT observation_analysis_origin;
 EXECUTE 'ALTER TABLE internal.observation_analysis_results ADD CONSTRAINT observation_analysis_origin '||replace(definition,old,
 $new$WHEN evidence_manifest->'schema_version'='4'::JSONB THEN request_digest IS NOT NULL AND completed_at IS NOT NULL AND source_analysis_id IS NOT NULL
 WHEN internal.is_audio_analysis_manifest(evidence_manifest)$new$);
END;
$patch$;
DO $patch$
DECLARE definition TEXT; old TEXT:=$old$    IF internal.is_audio_analysis_manifest(NEW.evidence_manifest) THEN$old$;
BEGIN
 definition:=pg_get_functiondef('internal.guard_observation_media_binding()'::regprocedure);
 IF (length(definition)-length(replace(definition,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'video_completion_source_drift'; END IF;
 EXECUTE replace(definition,old,$new$    IF NEW.evidence_manifest->'schema_version'='4'::JSONB THEN
        SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=NEW.analysis_id AND observation_id=NEW.observation_id;
        IF NOT FOUND OR saved.state IS DISTINCT FROM 'draft' OR saved.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB
        OR saved.draft->'result_snapshot' IS DISTINCT FROM NEW.result_snapshot OR saved.input_snapshot->'evidence_manifest' IS DISTINCT FROM NEW.evidence_manifest
        OR saved.input_snapshot->>'source_analysis_id' IS DISTINCT FROM NEW.source_analysis_id::TEXT
        OR saved.input_snapshot->>'request_digest' IS DISTINCT FROM NEW.request_digest
        OR current_setting('merian.video_completion',TRUE) IS DISTINCT FROM saved.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT THEN
            RAISE EXCEPTION 'analysis_history_completion_required' USING ERRCODE='55000'; END IF;
        PERFORM internal.assert_accounted_video_analysis(saved);
        PERFORM internal.assert_video_completion_evidence(saved);
        RETURN NEW;
    ELSIF EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF internal.is_audio_analysis_manifest(NEW.evidence_manifest) THEN$new$);
END;
$patch$;

-- Mutable selection/review authority is intentionally excluded from receipt
-- replay; initial blank authority is inserted atomically below.
CREATE FUNCTION internal.video_analysis_completion_matches(i internal.observation_analysis_intents)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE(i.state='complete' AND i.work_token IS NULL AND i.work_expires_at IS NULL AND i.terminal_reason IS NULL
 AND jsonb_typeof(i.receipt)='object' AND i.receipt ?& ARRAY['snapshot','plan_used','credit_consumed','entitlement_after']
 AND i.receipt-ARRAY['snapshot','plan_used','credit_consumed','entitlement_after']='{}'::JSONB
 AND jsonb_typeof(i.receipt->'snapshot')='string' AND jsonb_typeof(i.receipt->'credit_consumed')='boolean'
 AND jsonb_typeof(i.receipt->'entitlement_after')='object' AND i.receipt->>'plan_used'=i.quota->>'effective_plan'
 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=i.analysis_id AND r.observation_id=i.observation_id
 AND r.source_analysis_id::TEXT=i.input_snapshot->>'source_analysis_id' AND r.request_digest=i.input_snapshot->>'request_digest'
 AND r.result_snapshot=i.draft->'result_snapshot' AND r.evidence_manifest=i.input_snapshot->'evidence_manifest'
 AND (i.receipt->>'snapshot')::JSONB=jsonb_build_object('schema_version',5,'observation_id',r.observation_id,'analysis_id',r.analysis_id,
 'ordinal',r.ordinal,'source_analysis_id',r.source_analysis_id,'request_digest',r.request_digest,
 'completed_at_ms',floor(extract(epoch FROM r.completed_at)*1000),'result',r.result_snapshot,'evidence_manifest',r.evidence_manifest)),FALSE);
$$;

CREATE FUNCTION internal.complete_video_observation_analysis(p_owner UUID,p_observation UUID,p_analysis UUID,p_quota_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE i internal.observation_analysis_intents; history internal.observation_histories; credit internal.complimentary_scan_usage;
 result JSONB; evidence JSONB; snapshot TEXT; settlement JSONB; entitlement RECORD; prior_fence TEXT; prior_funded_fence TEXT;
 initial_authority JSONB:='{"confirmed_species_identity":null,"confirmed_species_identity_revision":0,"confirmed_species_id":null,"user_identification_override":null,"user_confirmed_identification":false,"user_review_state":"unreviewed","ai_identification_review":null}'::JSONB;
 resolved_species UUID; scientific_name TEXT; needs_species BOOLEAN; next_ordinal INTEGER; completion_time TIMESTAMPTZ;
BEGIN
 i:=internal.lock_video_observation_analysis(p_owner,p_observation,p_analysis);
 IF p_quota_token IS NULL OR p_quota_token::TEXT IS DISTINCT FROM i.quota->>'lease_token' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.assert_accounted_video_analysis(i);
 IF i.state='complete' THEN
  IF NOT internal.video_analysis_completion_matches(i) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN i.receipt;
 END IF;
 IF i.receipt IS NOT NULL OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO history FROM internal.observation_histories WHERE observation_id=p_observation FOR UPDATE;
 IF NOT FOUND OR NOT history.selection_initialized OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results
  WHERE analysis_id=internal.source_child_uuid(i.input_snapshot->>'source_analysis_id') AND observation_id=p_observation) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO credit FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis FOR UPDATE;
 IF i.quota->'complimentary_client_scan_id'='null'::JSONB THEN
  IF FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 ELSE
  IF NOT FOUND OR credit.state IS DISTINCT FROM 'held' OR credit.settled_at IS NOT NULL OR credit.settlement_reason IS NOT NULL
   OR i.quota->>'complimentary_client_scan_id' IS DISTINCT FROM p_analysis::TEXT THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 END IF;
 PERFORM internal.assert_video_completion_evidence(i);
 result:=i.draft->'result_snapshot'; evidence:=i.input_snapshot->'evidence_manifest';
 IF result->>'scan_id' IS DISTINCT FROM p_observation::TEXT
  OR jsonb_typeof(result->'is_biological_subject') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(result->'is_live_capture') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(result->'confidence_score') IS DISTINCT FROM 'number'
  OR NOT(result ? 'species_id')
  OR result ?| ARRAY['ai_identification_review','confirmed_species_identity','confirmed_species_identity_revision','confirmed_species_id','user_identification_override','user_confirmed_identification','user_review_state','entitlement'] THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF (result->>'confidence_score')::NUMERIC NOT BETWEEN 0 AND 1 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF result->'species_id'<>'null'::JSONB THEN
  IF jsonb_typeof(result->'species_id') IS DISTINCT FROM 'string' OR result->>'species_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  resolved_species:=(result->>'species_id')::UUID;
 END IF;
 needs_species:=(result->>'is_biological_subject')::BOOLEAN AND (
  result#>>'{primary_identification,resolution}'='species'
  OR (NOT(result ? 'primary_identification') AND NULLIF(btrim(result->>'scientific_name'),'') IS NOT NULL));
 IF COALESCE(needs_species,FALSE)<>(resolved_species IS NOT NULL) THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 IF resolved_species IS NOT NULL THEN
  SELECT dictionary.scientific_name INTO scientific_name FROM public.species_dictionary dictionary WHERE dictionary.id=resolved_species FOR SHARE;
  IF NOT FOUND OR lower(btrim(scientific_name)) IS DISTINCT FROM lower(btrim(result->>'scientific_name')) THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END IF;
 PERFORM internal.observation_analysis_projection(result,'{"confirmed_species_identity":null,"confirmed_species_identity_revision":0,"confirmed_species_id":null,"user_identification_override":null,"user_confirmed_identification":false,"user_review_state":"unreviewed","ai_identification_review":null}'::JSONB);
 SELECT COALESCE(MAX(ordinal),0)+1 INTO next_ordinal FROM internal.observation_analysis_results WHERE observation_id=p_observation;
 IF next_ordinal>=2147483647 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 completion_time:=date_trunc('milliseconds',clock_timestamp());
 snapshot:=internal.observation_analysis_snapshot(p_observation,p_analysis,internal.source_child_uuid(i.input_snapshot->>'source_analysis_id'),
 i.input_snapshot->>'request_digest',next_ordinal,completion_time,result,evidence);
 IF octet_length(snapshot)>1048576 THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 prior_funded_fence:=current_setting('merian.observation_analysis_completion',TRUE);
 PERFORM set_config('merian.observation_analysis_completion',p_owner::TEXT||':'||p_analysis::TEXT,TRUE);
 prior_fence:=current_setting('merian.video_completion',TRUE);
 PERFORM set_config('merian.video_completion',p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT,TRUE);
 INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
 VALUES(p_analysis,p_observation,next_ordinal,internal.source_child_uuid(i.input_snapshot->>'source_analysis_id'),i.input_snapshot->>'request_digest',result,evidence,completion_time);
 PERFORM set_config('merian.video_completion',COALESCE(prior_fence,''),TRUE);
 PERFORM set_config('merian.observation_analysis_completion',COALESCE(prior_funded_fence,''),TRUE);
 INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) VALUES(p_observation,p_analysis,initial_authority);
 settlement:=internal.settle_complimentary_analysis(p_owner,p_analysis);
 SELECT * INTO credit FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_analysis;
 IF i.quota->'complimentary_client_scan_id'='null'::JSONB THEN
  IF FOUND OR settlement IS DISTINCT FROM '{"credit_consumed":false,"credit_released":false}'::JSONB THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 ELSE
  IF NOT FOUND OR credit.settled_at IS NULL OR (
   (credit.state='consumed' AND credit.settlement_reason='durable_result_complete' AND settlement='{"credit_consumed":true,"credit_released":false}'::JSONB)
   OR (credit.state='released' AND credit.settlement_reason='paid_before_completion' AND settlement='{"credit_consumed":false,"credit_released":true}'::JSONB)) IS NOT TRUE THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 END IF;
 SELECT * INTO STRICT entitlement FROM internal.resolve_effective_entitlement(p_owner);
 UPDATE internal.observation_analysis_intents SET state='complete',work_token=NULL,work_expires_at=NULL,
 receipt=jsonb_build_object('snapshot',snapshot,'plan_used',i.quota->>'effective_plan','credit_consumed',settlement->'credit_consumed','entitlement_after',to_jsonb(entitlement))
 WHERE analysis_id=p_analysis RETURNING * INTO i;
 IF NOT internal.video_analysis_completion_matches(i) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 -- Initialized selection, review authority, reconciliation and occupancy stay
 -- unchanged. Source release requires its separate durable proof contract.
 RETURN i.receipt;
END;
$$;
REVOKE ALL ON FUNCTION internal.assert_accounted_video_analysis(internal.observation_analysis_intents),
 internal.assert_video_completion_evidence(internal.observation_analysis_intents),
 internal.video_analysis_completion_matches(internal.observation_analysis_intents),
 internal.complete_video_observation_analysis(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
-- No current public reader understands result5. Reject the whole history,
-- including cursor pages and actions aimed at an older selected child.
DO $patch$
DECLARE routine TEXT; definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 FOR routine,anchor,replacement IN SELECT * FROM (VALUES
 ('public.get_owned_observation_analysis_page(jsonb,integer)',
 '    FOR result_row IN SELECT * FROM internal.observation_analysis_results',
 $new$    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='4'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    FOR result_row IN SELECT * FROM internal.observation_analysis_results$new$),
 ('public.get_owned_observation_analysis_state(jsonb,integer)',
 '    target := COALESCE(target,history.selected_analysis_id);',
 $new$    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND evidence_manifest->'schema_version'='4'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    target := COALESCE(target,history.selected_analysis_id);$new$),
 ('internal.require_observation_action_reader(uuid,integer,uuid)',
 '    IF p_reader=9 AND (',
 $new$    IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=p_observation AND evidence_manifest->'schema_version'='4'::JSONB)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=p_observation AND analysis_id=p_analysis AND input_snapshot->'schema_version'='4'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000'; END IF;
    IF p_reader=9 AND ($new$)) patches(routine,anchor,replacement)
 LOOP
  definition:=pg_get_functiondef(routine::regprocedure);
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'video_completion_source_drift'; END IF;
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

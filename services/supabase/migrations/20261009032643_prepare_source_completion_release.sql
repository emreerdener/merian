SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN source_completion_release_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_source_completion_receipts (
 analysis_id UUID PRIMARY KEY,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 proof JSONB NOT NULL CHECK(jsonb_typeof(proof)='object' AND octet_length(proof::TEXT)<=16384),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_source_completion_receipts_source
 ON internal.observation_source_completion_receipts(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_source_completion_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_source_completion_receipts FROM PUBLIC,anon,authenticated,service_role;

-- Immutable product bytes only. No current selection, review or entitlement.
-- Saved snapshot text is hashed as written, never rebuilt by a future reader.
CREATE FUNCTION internal.observation_source_completion_product(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('identity',internal.observation_source_identity(p_binding),'owner_id',p_binding.owner_id,
 'ordinal',r.ordinal,'completed_at_us',floor(extract(epoch FROM r.completed_at)*1000000),
 'result_sha256',encode(extensions.digest(r.result_snapshot::TEXT,'sha256'),'hex'),
 'evidence_sha256',encode(extensions.digest(r.evidence_manifest::TEXT,'sha256'),'hex'),
 'snapshot_sha256',encode(extensions.digest(i.receipt->>'snapshot','sha256'),'hex'),
 'receipt_sha256',encode(extensions.digest(i.receipt::TEXT,'sha256'),'hex'),
 'draft_sha256',encode(extensions.digest(i.draft::TEXT,'sha256'),'hex'),
 'outcome_sha256',encode(extensions.digest(i.provider_outcome::TEXT,'sha256'),'hex'),
 'usage_sha256',encode(extensions.digest(i.provider_usage::TEXT,'sha256'),'hex'),
 'funding_sha256',encode(extensions.digest(i.quota::TEXT,'sha256'),'hex'))
 FROM internal.observation_analysis_intents i
 JOIN internal.observation_analysis_results r USING(analysis_id)
 WHERE i.analysis_id=p_binding.analysis_id AND i.owner_id=p_binding.owner_id
 AND i.observation_id=p_binding.observation_id AND i.input_snapshot=p_binding.input_snapshot
 AND p_binding.fingerprint_version=1 AND p_binding.fingerprint=internal.observation_source_fingerprint(i.input_snapshot)
 AND i.state='complete' AND i.terminal_reason IS NULL AND i.work_token IS NULL AND i.work_expires_at IS NULL
 AND r.observation_id=p_binding.observation_id AND r.source_analysis_id=p_binding.source_analysis_id
 AND r.request_digest=p_binding.input_snapshot->>'request_digest' AND isfinite(r.completed_at)
 AND r.result_snapshot=i.draft->'result_snapshot' AND r.evidence_manifest=i.input_snapshot->'evidence_manifest'
 AND i.draft->'evidence_manifest'=r.evidence_manifest
 AND i.provider_outcome#>>'{outcome,kind}'='draft'
 AND (i.draft->'result_snapshot')-'species_id'=i.provider_outcome#>'{outcome,result}'
 AND i.provider_usage=i.provider_outcome->'usage'
 AND jsonb_typeof(i.receipt)='object' AND i.receipt ?& ARRAY['snapshot','plan_used','credit_consumed','entitlement_after']
 AND i.receipt-ARRAY['snapshot','plan_used','credit_consumed','entitlement_after']='{}'
 AND jsonb_typeof(i.receipt->'snapshot')='string'
 AND i.receipt->>'plan_used'=i.quota->>'effective_plan';
$$;
REVOKE ALL ON FUNCTION internal.observation_source_completion_product(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

-- Projection matches complete_identification_usage's null-preserving native
-- accounting. Price availability is deliberately outside execution eligibility.
CREATE FUNCTION internal.observation_source_expected_usage(invocation internal.identification_invocations,p_usage JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE breakdown JSONB:='{}'::JSONB; category TEXT; unit TEXT; units JSONB; value BIGINT; metadata JSONB;
BEGIN
 IF invocation.provider='gemini' THEN
  FOREACH category IN ARRAY ARRAY['prompt','cached','candidates','tool'] LOOP
   units:='{}'::JSONB;
   FOREACH unit IN ARRAY ARRAY['text','image','audio','video'] LOOP
    value:=internal.identification_usage_count(p_usage->'modality_breakdown'->category,unit);
    IF value IS NOT NULL THEN units:=units||jsonb_build_object(unit,value); END IF;
   END LOOP;
   breakdown:=breakdown||jsonb_build_object(category,units);
  END LOOP;
 END IF;
 metadata:=jsonb_build_object('writer','identification_invocation','ai_provider',invocation.provider,
 'ai_binding',invocation.binding,'ai_policy_version',invocation.policy_version,
 'ai_input_profile',invocation.input_profile,'ai_attribution','attempt_snapshot','ai_outcome','draft',
 'ai_prompt',invocation.provenance->>'prompt','ai_schema',invocation.provenance->>'schema',
 'ai_provenance',invocation.provenance,'ai_usage_contract',CASE invocation.provider
 WHEN 'openai' THEN 'openai_responses_tokens_v1' WHEN 'gemini' THEN 'gemini_token_counts_v1' END);
 IF invocation.provider='openai' THEN
  metadata:=metadata||jsonb_build_object('ai_output_tokens',internal.identification_usage_count(p_usage,'output_tokens'),
  'ai_cache_write_tokens',internal.identification_usage_count(p_usage,'cache_write_tokens'),
  'ai_service_tier',CASE WHEN p_usage->>'service_tier'='default' THEN 'default' ELSE NULL END);
 END IF;
 RETURN jsonb_build_object('occurred_at',invocation.occurred_at,'user_id',invocation.user_id,
 'operation','scan_identification','model',invocation.model,'effective_plan',invocation.effective_plan,
 'input_modality',CASE invocation.input_profile WHEN 'multimodal_text_v1' THEN 'text'
 WHEN 'multimodal_photo_v1' THEN 'image' WHEN 'multimodal_audio_v1' THEN 'audio'
 WHEN 'multimodal_video_frames_v1' THEN 'video' ELSE 'mixed' END,
 'prompt_tokens',internal.identification_usage_count(p_usage,'input_tokens'),
 'cached_tokens',internal.identification_usage_count(p_usage,'cached_tokens'),
 'candidate_tokens',internal.identification_usage_count(p_usage,'candidate_tokens'),
 'thinking_tokens',internal.identification_usage_count(p_usage,'thinking_tokens'),
 'tool_tokens',internal.identification_usage_count(p_usage,'tool_tokens'),
 'total_tokens',internal.identification_usage_count(p_usage,'total_tokens'),
 'prompt_tokens_by_modality',breakdown,'outcome','success','scan_id',invocation.scan_id,
 'source_type','identification_invocation','source_id',invocation.id,'metadata',metadata);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_source_expected_usage(internal.identification_invocations,JSONB) FROM PUBLIC,anon,authenticated,service_role;

-- Caller holds canonical owner/parent/source/child/intent locks. Only the
-- original completion owner invokes this; missing accounting holds occupancy.
CREATE FUNCTION internal.observation_source_completion_candidate(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.observation_analysis_intents; q internal.ai_quota_reservations;
 w internal.observation_analysis_dispatch_witnesses; v internal.identification_invocations;
 e public.ai_usage_events; allocation internal.complimentary_scan_usage;
 product JSONB; expected JSONB; settlement JSONB;
BEGIN
 product:=internal.observation_source_completion_product(p_binding);
 IF product IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO i FROM internal.observation_analysis_intents WHERE analysis_id=p_binding.analysis_id;
 IF i.receipt->>'snapshot' IS DISTINCT FROM (SELECT internal.observation_analysis_snapshot(r.observation_id,r.analysis_id,r.source_analysis_id,r.request_digest,r.ordinal,r.completed_at,r.result_snapshot,r.evidence_manifest) FROM internal.observation_analysis_results r WHERE r.analysis_id=i.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=i.analysis_id)
 OR EXISTS(SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE analysis_id=i.analysis_id) THEN RETURN NULL; END IF;
 SELECT * INTO w FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=i.analysis_id;
 IF NOT FOUND OR w.owner_id IS DISTINCT FROM p_binding.owner_id OR w.observation_id IS DISTINCT FROM p_binding.observation_id
 OR w.source_analysis_id IS DISTINCT FROM p_binding.source_analysis_id OR w.fingerprint IS DISTINCT FROM p_binding.fingerprint
 OR w.reservation_id::TEXT IS DISTINCT FROM i.quota->>'reservation_id' OR w.attempt_count<>1
 OR w.lease_sha256 IS DISTINCT FROM encode(extensions.digest(i.quota->>'lease_token','sha256'),'hex')
 OR i.quota->'attempt_count' IS DISTINCT FROM '1'::JSONB
 OR i.quota->>'original_analysis_id' IS DISTINCT FROM i.analysis_id::TEXT
 OR i.quota->>'request_id' IS DISTINCT FROM i.analysis_id::TEXT
 OR i.quota->>'reservation_state' IS DISTINCT FROM 'reserved' THEN RETURN NULL; END IF;
 SELECT * INTO q FROM internal.ai_quota_reservations WHERE id=w.reservation_id FOR UPDATE;
 IF NOT FOUND OR q.user_id IS DISTINCT FROM i.owner_id OR q.original_analysis_id IS DISTINCT FROM i.analysis_id
 OR q.request_id IS DISTINCT FROM i.analysis_id OR q.operation IS DISTINCT FROM 'scan_identification'
 OR q.state IS DISTINCT FROM 'committed' OR q.committed_at IS NULL OR q.failed_at IS NOT NULL OR q.refund_count<>0
 OR q.attempt_count<>1 OR q.lease_token::TEXT IS DISTINCT FROM i.quota->>'lease_token' THEN RETURN NULL; END IF;
 SELECT * INTO v FROM internal.identification_invocations WHERE id=i.invocation_id FOR UPDATE;
 IF NOT FOUND OR v.reservation_id IS DISTINCT FROM q.id OR v.user_id IS DISTINCT FROM i.owner_id
 OR v.scan_id IS DISTINCT FROM i.analysis_id OR v.attempt_count<>1 OR v.lease_sha256 IS DISTINCT FROM w.lease_sha256
 OR v.provenance IS DISTINCT FROM w.provenance OR v.provenance IS DISTINCT FROM i.provider_outcome->'provenance'
 OR v.provenance IS DISTINCT FROM i.draft#>'{result_snapshot,identification_provenance}'
 OR v.provider IS DISTINCT FROM i.quota->>'provider' OR v.model IS DISTINCT FROM i.quota->>'model'
 OR v.binding IS DISTINCT FROM i.quota->>'binding' OR v.input_profile IS DISTINCT FROM i.quota->>'input_profile'
 OR v.effective_plan IS DISTINCT FROM i.quota->>'effective_plan' OR v.policy_version::TEXT IS DISTINCT FROM i.quota->>'policy_version'
 OR v.input_profile IS DISTINCT FROM (CASE i.input_snapshot->>'schema_version' WHEN '2' THEN 'multimodal_photo_v1' WHEN '3' THEN 'multimodal_audio_v1' END)
 THEN RETURN NULL; END IF;
 SELECT * INTO e FROM public.ai_usage_events WHERE id=v.event_id FOR SHARE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 expected:=internal.observation_source_expected_usage(v,i.provider_usage);
 IF (SELECT jsonb_object_agg(key,to_jsonb(e)->key) FROM jsonb_object_keys(expected) key) IS DISTINCT FROM expected
 OR e.conversation_id IS NOT NULL OR e.message_id IS NOT NULL OR e.is_backfilled
 THEN RETURN NULL; END IF;
 SELECT * INTO allocation FROM internal.complimentary_scan_usage WHERE user_id=i.owner_id AND client_scan_id=i.analysis_id FOR UPDATE;
 IF i.quota->>'complimentary_client_scan_id' IS NULL THEN
  IF FOUND OR q.complimentary_client_scan_id IS NOT NULL
   OR NOT(i.quota ? 'complimentary_client_scan_id') OR i.quota->'complimentary_client_scan_id'<>'null'::JSONB
   OR i.receipt->'credit_consumed' IS DISTINCT FROM 'false'::JSONB THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state','not_allocated','reason',NULL,'settled_at',NULL,'credit_consumed',FALSE);
 ELSE
  IF NOT FOUND OR i.quota->>'complimentary_client_scan_id' IS DISTINCT FROM i.analysis_id::TEXT
   OR q.complimentary_client_scan_id IS DISTINCT FROM i.analysis_id OR allocation.settled_at IS NULL
   OR ((allocation.state='consumed' AND allocation.settlement_reason='durable_result_complete' AND i.receipt->'credit_consumed'='true'::JSONB)
    OR (allocation.state='released' AND allocation.settlement_reason='paid_before_completion' AND i.receipt->'credit_consumed'='false'::JSONB)) IS NOT TRUE
  THEN RETURN NULL; END IF;
  settlement:=jsonb_build_object('state',allocation.state,'reason',allocation.settlement_reason,
   'settled_at',allocation.settled_at,'credit_consumed',i.receipt->'credit_consumed');
 END IF;
 RETURN jsonb_build_object('schema_version',1,'product',product,
 'execution',jsonb_build_object('reservation_id',q.id,'lease_sha256',w.lease_sha256,'attempt_count',1,
 'committed_at',q.committed_at,'invocation_id',v.id,'provider',v.provider,'model',v.model,'binding',v.binding,
 'input_profile',v.input_profile,'effective_plan',v.effective_plan,'policy_version',v.policy_version,'provenance',v.provenance),
 'accounting',jsonb_build_object('event_id',e.id,'facts',expected,'estimated_cost_microusd',e.estimated_cost_microusd,'pricing_version',e.pricing_version),
 'settlement',settlement);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_source_completion_candidate(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_source_completion_proven(p_binding internal.observation_analysis_source_bindings)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM internal.observation_source_completion_receipts r WHERE r.analysis_id=p_binding.analysis_id
 AND r.owner_id=p_binding.owner_id AND r.observation_id=p_binding.observation_id AND r.source_analysis_id=p_binding.source_analysis_id
 AND r.proof->'schema_version'='1'::JSONB AND r.proof->'product'=internal.observation_source_completion_product(p_binding));
$$;
REVOKE ALL ON FUNCTION internal.observation_source_completion_proven(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_source_completion()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; expected JSONB;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
  AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN OLD;
 END IF;
 IF current_setting('merian.source_completion',TRUE) IS DISTINCT FROM NEW.owner_id::TEXT||':'||NEW.analysis_id::TEXT||':'||pg_current_xact_id()::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND OR NEW.owner_id IS DISTINCT FROM binding.owner_id OR NEW.observation_id IS DISTINCT FROM binding.observation_id
 OR NEW.source_analysis_id IS DISTINCT FROM binding.source_analysis_id THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 expected:=internal.observation_source_completion_candidate(binding);
 IF expected IS NULL OR NEW.proof IS DISTINCT FROM expected THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_source_completion() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_source_completion BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_source_completion_receipts FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_source_completion();

CREATE FUNCTION internal.release_completed_observation_source(p_owner UUID,p_observation UUID,p_analysis UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; proof JSONB; prior_fence TEXT;
BEGIN
 IF (SELECT source_completion_release_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
 IF NOT FOUND THEN RETURN; END IF;
 IF binding.owner_id IS DISTINCT FROM p_owner OR binding.observation_id IS DISTINCT FROM p_observation THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_analysis
 AND owner_id=p_owner AND observation_id=p_observation AND source_analysis_id=binding.source_analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 proof:=internal.observation_source_completion_candidate(binding);
 IF proof IS NULL THEN RETURN; END IF;
 prior_fence:=current_setting('merian.source_completion',TRUE);
 PERFORM set_config('merian.source_completion',p_owner::TEXT||':'||p_analysis::TEXT||':'||pg_current_xact_id()::TEXT,TRUE);
 INSERT INTO internal.observation_source_completion_receipts VALUES(p_analysis,p_owner,p_observation,binding.source_analysis_id,proof);
 PERFORM set_config('merian.source_completion',COALESCE(prior_fence,''),TRUE);
 DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_analysis AND owner_id=p_owner
 AND observation_id=p_observation AND source_analysis_id=binding.source_analysis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION internal.release_completed_observation_source(UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('public.advance_owned_observation_analysis(uuid,uuid,uuid,uuid,text,jsonb)'::REGPROCEDURE) INTO STRICT definition;
 anchor:='        PERFORM internal.complete_observation_analysis(p_owner,p_observation,p_analysis);
        UPDATE internal.observation_analysis_intents SET work_token=NULL,work_expires_at=NULL WHERE analysis_id=p_analysis;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed completion branch changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
        -- saved is the locked PRE-transition intent. Never mint on replay.
        IF saved.state='draft' THEN PERFORM internal.release_completed_observation_source(p_owner,p_observation,p_analysis); END IF;
$body$);
 SELECT pg_get_functiondef('internal.observation_source_release_proven(internal.observation_analysis_source_bindings)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' SELECT * INTO retired FROM internal.observation_source_unfunded_retirements WHERE analysis_id=p_binding.analysis_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed release proof changed'; END IF;
 EXECUTE replace(definition,anchor,' IF internal.observation_source_completion_proven(p_binding) THEN RETURN TRUE; END IF;'||E'\n'||anchor);
 SELECT pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF TG_OP=''DELETE'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed occupancy guard changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||$body$
        IF TG_TABLE_NAME='observation_analysis_source_occupancy' AND EXISTS(
            SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=OLD.analysis_id
            AND b.owner_id=OLD.owner_id AND b.observation_id=OLD.observation_id AND b.source_analysis_id=OLD.source_analysis_id
            AND internal.observation_source_completion_proven(b)) THEN RETURN OLD; END IF;
$body$);
 SELECT pg_get_functiondef('public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=observation LIMIT 65) q)>64';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed reservation bound changed'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_completion_receipts WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64');
 anchor:=' IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed result blocker changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
 IF EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.observation_id=observation AND r.source_analysis_id=source
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=r.analysis_id
 AND b.owner_id=p_owner AND b.observation_id=observation AND b.source_analysis_id=source
 AND internal.observation_source_completion_proven(b))) THEN
$body$);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

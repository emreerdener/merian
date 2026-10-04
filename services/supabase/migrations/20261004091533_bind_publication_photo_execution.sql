SET lock_timeout='5s';
SET statement_timeout='2min';

-- No API grants or live publisher. Proof and bounded output are private and
-- disappear with their attempt under the existing observation deletion fence.
CREATE TABLE internal.observation_photo_execution_proofs (
    attempt_id UUID PRIMARY KEY REFERENCES internal.observation_photo_moderation_attempts(id) ON DELETE CASCADE,
    observation_id UUID NOT NULL,
    proof JSONB NOT NULL CHECK(pg_catalog.octet_length(proof::TEXT)<=2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.now()
);
CREATE TABLE internal.observation_photo_execution_results (
    attempt_id UUID PRIMARY KEY REFERENCES internal.observation_photo_execution_proofs(attempt_id) ON DELETE CASCADE,
    observation_id UUID NOT NULL,
    result JSONB NOT NULL CHECK(pg_catalog.octet_length(result::TEXT)<=2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.now()
);
ALTER TABLE internal.observation_photo_execution_proofs ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.observation_photo_execution_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_photo_execution_proofs,internal.observation_photo_execution_results FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_photo_execution_proof BEFORE INSERT OR UPDATE ON internal.observation_photo_execution_proofs FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_photo_execution_proof_update BEFORE UPDATE ON internal.observation_photo_execution_proofs FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();
CREATE TRIGGER guard_observation_photo_execution_result BEFORE INSERT OR UPDATE ON internal.observation_photo_execution_results FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_history_generation();
CREATE TRIGGER reject_observation_photo_execution_result_update BEFORE UPDATE ON internal.observation_photo_execution_results FOR EACH ROW EXECUTE FUNCTION internal.reject_observation_history_evidence_update();

CREATE FUNCTION internal.prepare_publication_photo_execution(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID,p_proof JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; job internal.observation_photo_moderations; saved JSONB; expected JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    SELECT * INTO STRICT job FROM internal.observation_photo_moderations WHERE operation_id=attempt.operation_id AND media_id=attempt.media_id;
    expected:=jsonb_build_object('schema_version',1,'policy_version',job.policy_version,
        'policy_sha256','b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9',
        'request_sha256',p_proof->'request_sha256','provider',job.provider,'model',job.model,'processor_permission',job.processor_permission,'source',job.source);
    IF p_proof IS DISTINCT FROM expected OR jsonb_typeof(p_proof->'request_sha256') IS DISTINCT FROM 'string'
        OR (p_proof->>'request_sha256') !~ '^[0-9a-f]{64}$'
        OR (job.source->>'byte_count')::BIGINT>12582912 OR job.source->>'content_type' NOT IN ('image/jpeg','image/png','image/heic') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    SELECT proof INTO saved FROM internal.observation_photo_execution_proofs WHERE attempt_id=p_attempt;
    IF FOUND THEN
        IF saved IS DISTINCT FROM p_proof THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        RETURN saved;
    END IF;
    IF attempt.state<>'reserved' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    IF (SELECT publication_moderation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
    INSERT INTO internal.observation_photo_execution_proofs(attempt_id,observation_id,proof) VALUES(p_attempt,p_observation,p_proof);
    RETURN p_proof;
END;
$$;
REVOKE ALL ON FUNCTION internal.prepare_publication_photo_execution(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.valid_publication_photo_result(p_result JSONB) RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE category JSONB; count_categories INTEGER; input_tokens BIGINT; output_tokens BIGINT; total_tokens BIGINT; confidence NUMERIC; expected_decision TEXT;
BEGIN
    IF jsonb_typeof(p_result) IS DISTINCT FROM 'object' OR pg_catalog.octet_length(p_result::TEXT)>2048
        OR p_result-ARRAY['decision','classification','confidence','categories','model','usage']<>'{}'::JSONB
        OR jsonb_typeof(p_result->'decision') IS DISTINCT FROM 'string'
        OR jsonb_typeof(p_result->'classification') IS DISTINCT FROM 'string'
        OR p_result->>'classification' NOT IN ('allow','reject','review')
        OR jsonb_typeof(p_result->'confidence') IS DISTINCT FROM 'number'
        OR jsonb_typeof(p_result->'categories') IS DISTINCT FROM 'array'
        OR p_result->>'model' IS DISTINCT FROM 'gemini-2.5-flash'
        OR jsonb_typeof(p_result->'usage') IS DISTINCT FROM 'object'
        OR (p_result->'usage')-ARRAY['input_tokens','output_tokens','total_tokens']<>'{}'::JSONB THEN RETURN FALSE; END IF;
    confidence:=(p_result->>'confidence')::NUMERIC;
    IF confidence<0 OR confidence>1 THEN RETURN FALSE; END IF;
    count_categories:=jsonb_array_length(p_result->'categories');
    IF count_categories>8 OR (SELECT count(DISTINCT value) FROM jsonb_array_elements(p_result->'categories'))<>count_categories THEN RETURN FALSE; END IF;
    FOR category IN SELECT value FROM jsonb_array_elements(p_result->'categories') LOOP
        IF jsonb_typeof(category)<>'string' OR category#>>'{}' NOT IN ('sexual_content','child_safety','hate_or_harassment','violence_or_gore','self_harm','dangerous_or_illegal_acts','personal_data','other_harmful_content') THEN RETURN FALSE; END IF;
    END LOOP;
    IF p_result->>'classification'='allow' AND count_categories<>0 THEN RETURN FALSE; END IF;
    IF jsonb_typeof(p_result#>'{usage,input_tokens}') IS DISTINCT FROM 'number'
        OR jsonb_typeof(p_result#>'{usage,output_tokens}') IS DISTINCT FROM 'number'
        OR jsonb_typeof(p_result#>'{usage,total_tokens}') IS DISTINCT FROM 'number'
        OR (p_result#>>'{usage,input_tokens}') !~ '^[0-9]{1,9}$'
        OR (p_result#>>'{usage,output_tokens}') !~ '^[0-9]{1,9}$'
        OR (p_result#>>'{usage,total_tokens}') !~ '^[0-9]{1,9}$' THEN RETURN FALSE; END IF;
    input_tokens:=(p_result#>>'{usage,input_tokens}')::BIGINT;
    output_tokens:=(p_result#>>'{usage,output_tokens}')::BIGINT;
    total_tokens:=(p_result#>>'{usage,total_tokens}')::BIGINT;
    IF input_tokens<1 OR output_tokens<1 OR total_tokens>100000000 OR total_tokens<>input_tokens+output_tokens THEN RETURN FALSE; END IF;
    expected_decision:=CASE WHEN p_result->>'classification'='allow' AND confidence>=0.95 THEN 'approved' ELSE 'rejected' END;
    RETURN p_result->>'decision'=expected_decision;
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_publication_photo_result(JSONB) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.dispatch_publication_photo_moderation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; job internal.observation_photo_moderations;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    IF attempt.state<>'reserved' THEN RETURN jsonb_build_object('dispatch_allowed',FALSE,'receipt',internal.publication_moderation_receipt(p_attempt)); END IF;
    IF NOT EXISTS(SELECT 1 FROM internal.observation_photo_execution_proofs WHERE attempt_id=p_attempt AND observation_id=p_observation) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    IF (SELECT publication_moderation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO STRICT job FROM internal.observation_photo_moderations WHERE operation_id=attempt.operation_id AND media_id=attempt.media_id;
    PERFORM internal.require_current_ai_consent(p_owner,job.processor_permission);
    PERFORM public.finalize_ai_quota_reservation((attempt.quota->>'reservation_id')::UUID,p_owner,p_token,'committed');
    UPDATE internal.observation_photo_moderation_attempts SET state='dispatched',dispatch_expires_at=clock_timestamp()+INTERVAL '2 minutes' WHERE id=p_attempt;
    RETURN jsonb_build_object('dispatch_allowed',TRUE,'receipt',internal.publication_moderation_receipt(p_attempt));
END;
$$;
REVOKE ALL ON FUNCTION internal.dispatch_publication_photo_moderation(UUID,UUID,UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION internal.complete_publication_photo_moderation(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID,p_decision TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; reservation internal.ai_quota_reservations;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF NOT EXISTS(SELECT 1 FROM internal.observation_photo_execution_results WHERE attempt_id=p_attempt AND observation_id=p_observation AND result->>'decision'=p_decision) THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF attempt.state=p_decision THEN RETURN internal.publication_moderation_receipt(p_attempt); END IF;
    IF attempt.state<>'dispatched' OR attempt.dispatch_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    PERFORM internal.revalidate_observation_publication_intent(p_owner,p_observation,attempt.operation_id);
    SELECT * INTO reservation FROM internal.ai_quota_reservations WHERE id=(attempt.quota->>'reservation_id')::UUID FOR UPDATE;
    IF NOT FOUND OR reservation.state<>'committed' OR reservation.user_id IS DISTINCT FROM p_owner
        OR reservation.lease_token IS DISTINCT FROM p_token OR reservation.attempt_count<>attempt.attempt_count THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    UPDATE internal.observation_photo_moderation_attempts SET state=p_decision,lease_token=NULL WHERE id=p_attempt;
    RETURN internal.publication_moderation_receipt(p_attempt);
END;
$$;
REVOKE ALL ON FUNCTION internal.complete_publication_photo_moderation(UUID,UUID,UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.complete_publication_photo_execution(p_owner UUID,p_observation UUID,p_attempt UUID,p_token UUID,p_proof JSONB,p_result JSONB)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE attempt internal.observation_photo_moderation_attempts; saved_proof JSONB; saved_result JSONB;
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.lock_owned_observation_evidence(p_owner,p_observation);
    SELECT * INTO attempt FROM internal.observation_photo_moderation_attempts WHERE id=p_attempt AND observation_id=p_observation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF p_token IS NULL OR attempt.lease_hash<>encode(extensions.digest(p_token::TEXT,'sha256'),'hex') THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    SELECT proof INTO saved_proof FROM internal.observation_photo_execution_proofs WHERE attempt_id=p_attempt AND observation_id=p_observation;
    IF NOT FOUND OR saved_proof IS DISTINCT FROM p_proof THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    IF internal.valid_publication_photo_result(p_result) IS NOT TRUE THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
    SELECT result INTO saved_result FROM internal.observation_photo_execution_results WHERE attempt_id=p_attempt;
    IF FOUND THEN
        IF saved_result IS DISTINCT FROM p_result THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
    ELSE
        IF attempt.state<>'dispatched' OR attempt.dispatch_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
        INSERT INTO internal.observation_photo_execution_results(attempt_id,observation_id,result) VALUES(p_attempt,p_observation,p_result);
    END IF;
    -- Completion revalidates authority/source and metered reservation under the
    -- same locks. Any denial rolls back the result insertion in this transaction.
    RETURN internal.complete_publication_photo_moderation(p_owner,p_observation,p_attempt,p_token,p_result->>'decision');
END;
$$;
REVOKE ALL ON FUNCTION internal.complete_publication_photo_execution(UUID,UUID,UUID,UUID,JSONB,JSONB) FROM PUBLIC,anon,authenticated,service_role;

RESET statement_timeout;
RESET lock_timeout;

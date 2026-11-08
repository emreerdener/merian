SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout ADD COLUMN source_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE;
-- Audit evidence survives quota pruning. Only its creating transaction can use
-- it as authority; a committed row never authorizes another provider call.
CREATE TABLE internal.observation_analysis_dispatch_witnesses (
    analysis_id UUID PRIMARY KEY REFERENCES internal.observation_analysis_intents(analysis_id) ON DELETE CASCADE,
    owner_id UUID NOT NULL,
    observation_id UUID NOT NULL,
    source_analysis_id UUID NOT NULL,
    fingerprint TEXT NOT NULL CHECK(fingerprint ~ '^[0-9a-f]{64}$'),
    reservation_id UUID NOT NULL UNIQUE,
    lease_sha256 TEXT NOT NULL CHECK(lease_sha256 ~ '^[0-9a-f]{64}$'),
    attempt_count INTEGER NOT NULL CHECK(attempt_count=1),
    provenance JSONB NOT NULL CHECK(internal.identification_provenance_is_valid(provenance)),
    dispatch_transaction XID8 NOT NULL
);
ALTER TABLE internal.observation_analysis_dispatch_witnesses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_analysis_dispatch_witnesses FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_dispatch_witness BEFORE UPDATE OR DELETE
    ON internal.observation_analysis_dispatch_witnesses FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_source_storage();

-- Caller already holds owner/parent/source/child/intent locks. No late source
-- lock is acquired here. The original reservation is never replaced/reopened.
CREATE FUNCTION internal.prepare_source_dispatch_witness(p_owner UUID,p_observation UUID,p_analysis UUID,p_token UUID,p_provenance JSONB)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.observation_analysis_intents; reserved internal.ai_quota_reservations; assigned internal.identification_provider_attempts;
BEGIN
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;
    IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner OR saved.observation_id IS DISTINCT FROM p_observation
        OR saved.state IS DISTINCT FROM 'admitted' OR saved.invocation_id IS NOT NULL OR saved.provider_outcome IS NOT NULL
        OR saved.provider_usage IS NOT NULL OR saved.draft IS NOT NULL OR saved.receipt IS NOT NULL OR saved.terminal_reason IS NOT NULL
        OR saved.quota->>'lease_token' IS DISTINCT FROM p_token::TEXT
        OR saved.quota->'attempt_count' IS DISTINCT FROM '1'::JSONB
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=p_analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
    IF (SELECT source_dispatch_enabled AND admission_enabled AND dispatch_enabled AND append_enabled
        AND CASE saved.input_snapshot->>'schema_version' WHEN '2' THEN protected_analysis_enabled AND media_enabled
            WHEN '3' THEN audio_analysis_enabled AND prepared_audio_evidence_enabled ELSE FALSE END
        FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    PERFORM internal.assert_observation_source_input_chain(p_owner,p_observation,p_analysis,saved.input_snapshot);
    IF saved.input_snapshot->'schema_version'='2'::JSONB THEN
        PERFORM internal.assert_protected_analysis_evidence(p_owner,p_observation,p_analysis,saved.input_snapshot->'evidence_manifest',FALSE);
    ELSE
        PERFORM internal.assert_audio_analysis_evidence(p_owner,p_observation,p_analysis,saved.input_snapshot->'evidence_manifest',FALSE);
    END IF;
    SELECT * INTO reserved FROM internal.ai_quota_reservations WHERE id=(saved.quota->>'reservation_id')::UUID FOR UPDATE;
    IF NOT FOUND OR reserved.user_id IS DISTINCT FROM p_owner OR reserved.original_analysis_id IS DISTINCT FROM p_analysis
        OR reserved.request_id IS DISTINCT FROM p_analysis OR reserved.operation IS DISTINCT FROM 'scan_identification'
        OR reserved.state IS DISTINCT FROM 'reserved' OR reserved.lease_token IS DISTINCT FROM p_token
        OR reserved.attempt_count IS DISTINCT FROM 1 OR reserved.lease_expires_at<=clock_timestamp()
        OR saved.quota->>'request_id' IS DISTINCT FROM p_analysis::TEXT
        OR saved.quota->>'original_analysis_id' IS DISTINCT FROM p_analysis::TEXT THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
    SELECT * INTO assigned FROM internal.identification_provider_attempts WHERE reservation_id=reserved.id AND attempt_count=1;
    IF NOT FOUND OR assigned.input_profile IS DISTINCT FROM (CASE saved.input_snapshot->>'schema_version'
            WHEN '2' THEN 'multimodal_photo_v1' WHEN '3' THEN 'multimodal_audio_v1' END)
        OR assigned.input_profile IS DISTINCT FROM saved.quota->>'input_profile'
        OR assigned.operation IS DISTINCT FROM reserved.operation
        OR saved.quota->>'processor_permission' IS DISTINCT FROM saved.input_snapshot->>'expected_processor_permission' THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
    PERFORM internal.require_identification_processor_consent(p_owner,saved.quota->>'processor_permission');
    INSERT INTO internal.observation_analysis_dispatch_witnesses
    SELECT p_analysis,p_owner,p_observation,b.source_analysis_id,b.fingerprint,reserved.id,
        encode(extensions.digest(p_token::TEXT,'sha256'),'hex'),reserved.attempt_count,p_provenance,pg_catalog.pg_current_xact_id()
    FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=p_analysis;
END;
$$;
REVOKE ALL ON FUNCTION internal.prepare_source_dispatch_witness(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.dispatch_observation_analysis(uuid,uuid,uuid,uuid,jsonb)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    old_fence:=current_setting(''merian.observation_analysis_provider'',TRUE);';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed dispatch entry changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis) THEN
        PERFORM internal.prepare_source_dispatch_witness(p_owner,p_observation,p_analysis,p_token,p_provenance);
    END IF;
$body$ || anchor);

    SELECT pg_catalog.pg_get_functiondef('public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id) THEN
        RAISE EXCEPTION ''analysis_history_dispatch_required'' USING ERRCODE=''55000'';
    END IF;';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed invocation hold changed'; END IF;
    definition:=replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=reserved.original_analysis_id) THEN
        RAISE EXCEPTION 'scan_generation_deleted' USING ERRCODE='55000';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id)
        AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses w
            WHERE w.analysis_id=reserved.original_analysis_id AND w.owner_id=p_user_id
                AND w.reservation_id=p_reservation_id AND w.attempt_count=p_attempt_count
                AND w.lease_sha256=encode(extensions.digest(p_lease_token::TEXT,'sha256'),'hex')
                AND w.provenance=p_provenance AND w.dispatch_transaction=pg_catalog.pg_current_xact_id()) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
$body$);
    anchor:='    PERFORM public.finalize_ai_quota_reservation(p_reservation_id, p_user_id, p_lease_token, ''committed'');';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed invocation finalizer changed'; END IF;
    EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id) THEN
        PERFORM internal.finalize_ai_quota_reservation_core(p_reservation_id,p_user_id,p_lease_token,'committed');
    ELSE
        PERFORM public.finalize_ai_quota_reservation(p_reservation_id,p_user_id,p_lease_token,'committed');
    END IF;
$body$);

    SELECT pg_catalog.pg_get_functiondef('internal.erase_observation_analysis_intent()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='                AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=OLD.analysis_id)';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed erasure proof changed'; END IF;
    EXECUTE replace(definition,anchor,anchor || E'\n                AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=OLD.analysis_id)');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

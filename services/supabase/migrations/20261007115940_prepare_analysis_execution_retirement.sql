SET lock_timeout = '5s';
SET statement_timeout = '2min';

ALTER TABLE internal.observation_history_rollout
    ADD COLUMN execution_retirement_api_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_analysis_retirement_receipts (
    operation_id UUID PRIMARY KEY,
    analysis_id UUID NOT NULL UNIQUE REFERENCES internal.observation_analysis_intents(analysis_id) ON DELETE CASCADE,
    observation_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    request_identity JSONB NOT NULL CHECK(pg_catalog.jsonb_typeof(request_identity)='object' AND pg_catalog.octet_length(request_identity::TEXT)<=2048),
    receipt JSONB NOT NULL CHECK(pg_catalog.octet_length(receipt::TEXT)<=4096),
    CHECK(receipt=request_identity || '{"state":"retired_before_dispatch"}'::JSONB)
);
ALTER TABLE internal.observation_analysis_retirement_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_analysis_retirement_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.reject_analysis_retirement_receipt_update()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
END;
$$;
REVOKE ALL ON FUNCTION internal.reject_analysis_retirement_receipt_update() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_analysis_retirement_receipt BEFORE UPDATE ON internal.observation_analysis_retirement_receipts
    FOR EACH ROW EXECUTE FUNCTION internal.reject_analysis_retirement_receipt_update();

-- Authenticated Edge derives p_owner; no caller can choose a user at the HTTP boundary.
-- Funding settlement remains service-only. Never impersonate JWT claims here.
CREATE FUNCTION public.retire_owned_observation_analysis_execution(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE
    observation UUID; analysis UUID; source UUID; operation UUID; field TEXT;
    saved internal.observation_analysis_intents;
    prior internal.observation_analysis_retirement_receipts;
    reservation internal.ai_quota_reservations;
    answer JSONB;
BEGIN
    PERFORM internal.require_service_role();
    IF p_owner IS NULL OR p_reader IS DISTINCT FROM 9
        OR pg_catalog.jsonb_typeof(p_request) IS DISTINCT FROM 'object'
        OR pg_catalog.octet_length(p_request::TEXT)>2048
        OR NOT(p_request ?& ARRAY['schema_version','operation_id','observation_id','analysis_id','source_analysis_id','request_digest'])
        OR p_request-ARRAY['schema_version','operation_id','observation_id','analysis_id','source_analysis_id','request_digest']<>'{}'::JSONB
        OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB
        OR pg_catalog.jsonb_typeof(p_request->'request_digest') IS DISTINCT FROM 'string'
        OR p_request->>'request_digest' !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    FOREACH field IN ARRAY ARRAY['operation_id','observation_id','analysis_id'] LOOP
        IF pg_catalog.jsonb_typeof(p_request->field) IS DISTINCT FROM 'string'
            OR p_request->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
        END IF;
    END LOOP;
    IF p_request->'source_analysis_id'<>'null'::JSONB AND (
        pg_catalog.jsonb_typeof(p_request->'source_analysis_id') IS DISTINCT FROM 'string'
        OR p_request->>'source_analysis_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    observation:=(p_request->>'observation_id')::UUID; analysis:=(p_request->>'analysis_id')::UUID;
    source:=(p_request->>'source_analysis_id')::UUID; operation:=(p_request->>'operation_id')::UUID;
    IF analysis=observation OR source IN (observation,analysis) OR operation IN (observation,analysis,source) THEN
        RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023';
    END IF;
    PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-analysis-retirement:' || operation::TEXT,0::BIGINT));
    SELECT * INTO prior FROM internal.observation_analysis_retirement_receipts WHERE operation_id=operation;
    IF FOUND THEN
        IF prior.owner_id IS DISTINCT FROM p_owner OR prior.observation_id IS DISTINCT FROM observation
            OR prior.analysis_id IS DISTINCT FROM analysis OR prior.request_identity IS DISTINCT FROM p_request THEN
            RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
        END IF;
        RETURN prior.receipt;
    END IF;
    IF NOT COALESCE((SELECT execution_retirement_api_enabled FROM internal.observation_history_rollout WHERE singleton),FALSE) THEN
        RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000';
    END IF;
    SELECT * INTO saved FROM internal.observation_analysis_intents
        WHERE analysis_id=analysis AND observation_id=observation AND owner_id=p_owner FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_not_found' USING ERRCODE='P0002'; END IF;
    IF saved.input_snapshot->>'observation_id' IS DISTINCT FROM observation::TEXT
        OR saved.input_snapshot->>'analysis_id' IS DISTINCT FROM analysis::TEXT
        OR saved.input_snapshot->>'source_analysis_id' IS DISTINCT FROM source::TEXT
        OR saved.input_snapshot->>'request_digest' IS DISTINCT FROM p_request->>'request_digest'
        OR saved.state IS DISTINCT FROM 'admitted'
        OR saved.invocation_id IS NOT NULL OR saved.provider_outcome IS NOT NULL OR saved.draft IS NOT NULL
        OR saved.receipt IS NOT NULL OR saved.terminal_reason IS NOT NULL OR saved.provider_usage IS NOT NULL
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=analysis)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=analysis)
        OR pg_catalog.jsonb_typeof(saved.quota) IS DISTINCT FROM 'object'
        OR pg_catalog.jsonb_typeof(saved.quota->'reservation_id') IS DISTINCT FROM 'string'
        OR saved.quota->>'reservation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR pg_catalog.jsonb_typeof(saved.quota->'lease_token') IS DISTINCT FROM 'string'
        OR saved.quota->>'lease_token' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO reservation FROM internal.ai_quota_reservations
        WHERE id=(saved.quota->>'reservation_id')::UUID FOR UPDATE;
    IF NOT FOUND OR reservation.user_id IS DISTINCT FROM p_owner
        OR reservation.original_analysis_id IS DISTINCT FROM analysis OR reservation.request_id IS DISTINCT FROM analysis
        OR reservation.operation IS DISTINCT FROM 'scan_identification' OR reservation.state IS DISTINCT FROM 'reserved'
        OR reservation.lease_token::TEXT IS DISTINCT FROM saved.quota->>'lease_token'
        OR pg_catalog.to_jsonb(reservation.attempt_count) IS DISTINCT FROM saved.quota->'attempt_count'
        OR saved.quota->>'original_analysis_id' IS DISTINCT FROM analysis::TEXT
        OR saved.quota->>'reservation_state' IS DISTINCT FROM 'reserved'
        OR reservation.committed_at IS NOT NULL OR reservation.failed_at IS NOT NULL
        OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE reservation_id=reservation.id)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage
            WHERE client_scan_id=analysis AND (user_id IS DISTINCT FROM p_owner OR state IS DISTINCT FROM 'held')) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    -- The same parent lock serializes dispatch. A live worker claim is revoked,
    -- not mistaken for evidence that a provider was invoked.
    PERFORM internal.finalize_observation_provider_reservation(p_owner,analysis,reservation.id,reservation.lease_token,'refunded');
    PERFORM internal.settle_complimentary_analysis(p_owner,analysis,'retired_before_dispatch');
    UPDATE internal.observation_analysis_intents SET state='failed_terminal',terminal_reason='retired_before_dispatch',
        provider_usage='{}'::JSONB,work_token=NULL,work_expires_at=NULL WHERE analysis_id=analysis;
    answer:=p_request || '{"state":"retired_before_dispatch"}'::JSONB;
    INSERT INTO internal.observation_analysis_retirement_receipts(operation_id,analysis_id,observation_id,owner_id,request_identity,receipt)
        VALUES(operation,analysis,observation,p_owner,p_request,answer);
    RETURN answer;
END;
$$;
REVOKE ALL ON FUNCTION public.retire_owned_observation_analysis_execution(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_owned_observation_analysis_execution(UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
    ('service_role','public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)',
     'Retire exact never-dispatched admitted analysis atomically; permanent receipt, no uncertain-execution refund.');
COMMENT ON FUNCTION public.retire_owned_observation_analysis_execution(UUID,JSONB,INTEGER) IS
    'Authenticated Edge owner only; exact retirement replay precedes fresh gate after owner/deletion locks. Absent, dispatched, malformed or other terminal work never gains retirement proof.';

RESET statement_timeout;
RESET lock_timeout;

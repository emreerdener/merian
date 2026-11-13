-- HQ-334: pg_net response.created is transaction start, not HTTP completion.
-- Transport IDs can repeat after unlogged-storage recovery; a durable random
-- nonce must match the terminal receipt. Do not backfill legacy pending slots.
SET lock_timeout = '5s';
SET statement_timeout = '2min';
ALTER TABLE internal.observation_evidence_worker_state ADD COLUMN pending_dispatch_id UUID;
COMMENT ON COLUMN internal.observation_evidence_worker_state.pending_dispatch_id IS
    'Private UUIDv4 dispatch correlation; NULL legacy slots require explicit reconciliation. Never exposed in health telemetry.';

-- The one-argument six-counter validator remains for legacy receipt inspection.
CREATE FUNCTION internal.valid_observation_evidence_worker_receipt(p_receipt JSONB,p_dispatch_id UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF p_dispatch_id IS NULL OR p_receipt IS NULL
       OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' THEN RETURN FALSE; END IF;
    RETURN COALESCE(p_receipt->'schema_version' = '2'::JSONB
       AND jsonb_typeof(p_receipt->'dispatch_id') = 'string'
       AND p_receipt->>'dispatch_id' = p_dispatch_id::TEXT
       AND internal.valid_observation_evidence_worker_receipt(p_receipt - 'schema_version' - 'dispatch_id'),FALSE);
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_observation_evidence_worker_receipt(JSONB,UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.dispatch_observation_evidence_erasure()
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' SET statement_timeout = '5s' AS $$
DECLARE
    state internal.observation_evidence_worker_state%ROWTYPE;
    response net._http_response%ROWTYPE;
    receipt JSONB;
    transport JSONB;
    observed_at TIMESTAMPTZ := clock_timestamp();
    succeeded BOOLEAN := FALSE;
    valid_receipt BOOLEAN := FALSE;
    request_id BIGINT;
    dispatch_id UUID;
    response_missing BOOLEAN := FALSE;
BEGIN
    -- The durable slot survives the transaction and covers asynchronous work.
    SELECT * INTO state FROM internal.observation_evidence_worker_state WHERE singleton FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    IF state.pending_request_id IS NOT NULL THEN
        -- Legacy in-flight requests have no durable nonce. Preserve them for
        -- separately authorized reconciliation; never bind a new nonce later.
        IF state.pending_dispatch_id IS NULL THEN
            UPDATE internal.observation_evidence_worker_state
            SET last_observed_at=observed_at,last_result='unknown' WHERE singleton;
            RETURN;
        END IF;
        BEGIN
            SELECT * INTO STRICT response FROM net._http_response WHERE id=state.pending_request_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN response_missing := TRUE;
            WHEN TOO_MANY_ROWS THEN
                UPDATE internal.observation_evidence_worker_state
                SET last_observed_at=observed_at,last_result='unknown' WHERE singleton;
                RETURN;
        END;
        IF response_missing OR response.timed_out IS TRUE OR response.error_msg IS NOT NULL THEN
            UPDATE internal.observation_evidence_worker_state
            SET last_observed_at=observed_at,
                last_result=CASE WHEN observed_at-last_dispatched_at >= INTERVAL '3 minutes'
                    OR response.timed_out IS TRUE OR response.error_msg IS NOT NULL THEN 'unknown' ELSE 'pending' END
            WHERE singleton;
            RETURN;
        END IF;
        -- Bounded parse; never persist or emit content/headers/error strings.
        IF response.status_code=200 AND octet_length(response.content) <= 2048
           AND isfinite(response.created)
           AND response.created <= observed_at THEN
            BEGIN
                receipt := response.content::JSONB;
                valid_receipt := internal.valid_observation_evidence_worker_receipt(receipt,state.pending_dispatch_id);
            EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN valid_receipt := FALSE;
            END;
        END IF;
        IF NOT valid_receipt THEN
            -- Proxy errors and malformed/uncorrelated bodies do not prove that
            -- the remote worker stopped. Keep the original slot until reviewed
            -- quiescence/reconciliation; elapsed time is not that proof.
            UPDATE internal.observation_evidence_worker_state
            SET last_observed_at=observed_at,last_result='unknown',last_http_status=response.status_code
            WHERE singleton;
            RETURN;
        END IF;
        succeeded := (receipt->>'retirement_failures')::INTEGER=0
            AND receipt->>'claimed'=receipt->>'marked' AND receipt->>'claimed'=receipt->>'acknowledged';
        UPDATE internal.observation_evidence_worker_state
        SET pending_request_id=NULL,pending_dispatch_id=NULL,last_observed_at=observed_at,last_completed_at=response.created,
            last_http_status=response.status_code,last_result=CASE WHEN succeeded THEN 'success' ELSE 'failure' END,
            last_success_at=CASE WHEN succeeded THEN response.created ELSE last_success_at END,
            last_marker_success_at=CASE WHEN succeeded AND receipt->>'marked'='1' THEN response.created ELSE last_marker_success_at END,
            consecutive_failures=CASE WHEN succeeded THEN 0 ELSE least(consecutive_failures,2147483646)+1 END,
            last_retired=CASE WHEN valid_receipt THEN (receipt->>'retired')::INTEGER END,
            last_video_retired=CASE WHEN valid_receipt THEN (receipt->>'video_retired')::INTEGER END,
            last_retirement_failures=CASE WHEN valid_receipt THEN (receipt->>'retirement_failures')::INTEGER END,
            last_claimed=CASE WHEN valid_receipt THEN (receipt->>'claimed')::INTEGER END,
            last_marked=CASE WHEN valid_receipt THEN (receipt->>'marked')::INTEGER END,
            last_acknowledged=CASE WHEN valid_receipt THEN (receipt->>'acknowledged')::INTEGER END
        WHERE singleton;
    END IF;
    -- Pausing stops new transport; an existing result can still be reconciled.
    IF NOT state.enabled THEN RETURN; END IF;
    transport := internal.observation_evidence_worker_transport(state.approved_project);
    IF transport IS NULL THEN
        UPDATE internal.observation_evidence_worker_state
        SET last_observed_at=observed_at,last_result='configuration_unavailable' WHERE singleton;
        RETURN;
    END IF;
    dispatch_id := gen_random_uuid();
    SELECT net.http_post(url:=transport->>'url',
        headers:=(transport->'headers') || jsonb_build_object('X-Merian-Evidence-Dispatch',dispatch_id::TEXT),body:='{}'::JSONB,
        timeout_milliseconds:=120000) INTO request_id;
    IF request_id IS NULL THEN RAISE EXCEPTION 'evidence_worker_dispatch_unacknowledged'; END IF;
    -- A recycled transport ID with a retained response must roll back the
    -- enqueue and state change together. The nonce also protects late responses.
    IF EXISTS(SELECT 1 FROM net._http_response WHERE id=request_id) THEN
        RAISE EXCEPTION 'evidence_worker_dispatch_id_collision';
    END IF;
    UPDATE internal.observation_evidence_worker_state
    SET pending_request_id=request_id,pending_dispatch_id=dispatch_id,last_dispatched_at=observed_at,last_observed_at=observed_at
    WHERE singleton;
END;
$$;
REVOKE ALL ON FUNCTION internal.dispatch_observation_evidence_erasure()
    FROM PUBLIC, anon, authenticated, service_role;
-- No gate, scheduler, credentials, original pending identity or response changes.
RESET statement_timeout;
RESET lock_timeout;

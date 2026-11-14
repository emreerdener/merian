-- Dormant release/dispatch accounting. Installing this migration cannot activate routing.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE TABLE internal.gemini_routing_revisions (
    revision BIGINT PRIMARY KEY CHECK (revision >= 0),
    release_id UUID UNIQUE,
    configuration_digest TEXT CHECK (configuration_digest ~ '^[0-9a-f]{64}$'),
    status TEXT NOT NULL CHECK (status IN ('active','suspended','superseded')),
    activated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    suspended_at TIMESTAMPTZ
);
INSERT INTO internal.gemini_routing_revisions(revision,status) VALUES (0,'active');
CREATE TABLE internal.gemini_routing_head (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    revision BIGINT NOT NULL REFERENCES internal.gemini_routing_revisions(revision)
);
INSERT INTO internal.gemini_routing_head VALUES (TRUE,0);
CREATE TABLE internal.gemini_assignment_revisions (
    operation TEXT NOT NULL,
    effective_plan TEXT NOT NULL,
    policy_version BIGINT NOT NULL,
    requested_model TEXT NOT NULL,
    revision BIGINT NOT NULL REFERENCES internal.gemini_routing_revisions(revision),
    PRIMARY KEY (operation,effective_plan,policy_version,requested_model)
);
INSERT INTO internal.gemini_assignment_revisions
SELECT operation,effective_plan,policy_version,model,0 FROM internal.ai_quota_policies
WHERE allowed AND model IN ('gemini-2.5-flash','gemini-2.5-pro');

CREATE TABLE internal.gemini_invocation_receipts (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    reservation_id UUID NOT NULL REFERENCES internal.ai_quota_reservations(id) ON DELETE CASCADE,
    attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
    lease_token UUID NOT NULL,
    assignment_revision BIGINT NOT NULL REFERENCES internal.gemini_routing_revisions(revision),
    requested_model TEXT NOT NULL,
    returned_model TEXT,
    state TEXT NOT NULL CHECK (state IN ('dispatch_intent','received','unknown','not_invoked')),
    dispatch_intent_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    response_received_at TIMESTAMPTZ,
    receipt JSONB CHECK (pg_catalog.octet_length(receipt::TEXT) <= 4096),
    UNIQUE (reservation_id,attempt_count)
);
COMMENT ON TABLE internal.gemini_invocation_receipts IS
'Content-free requested/returned identity and partial usage. Dispatch intent is neither proof of invocation nor non-invocation. Expiry never permits another call.';

CREATE TABLE internal.gemini_activation_releases (
    id UUID PRIMARY KEY,
    target TEXT NOT NULL CHECK (target ~ '^[a-z0-9_-]{3,80}$'),
    backend_sha TEXT NOT NULL CHECK (backend_sha ~ '^[0-9a-f]{40}$'),
    configuration_digest TEXT NOT NULL CHECK (configuration_digest ~ '^[0-9a-f]{64}$'),
    manifest TEXT NOT NULL CHECK (pg_catalog.octet_length(manifest) <= 65536),
    app_version TEXT NOT NULL CHECK (length(app_version) BETWEEN 1 AND 40),
    app_build TEXT NOT NULL CHECK (app_build ~ '^[0-9]{1,12}$'),
    app_source_fingerprint TEXT NOT NULL CHECK (app_source_fingerprint ~ '^[0-9a-f]{64}$'),
    authorization_reference TEXT NOT NULL CHECK (length(authorization_reference) BETWEEN 1 AND 256),
    expected_previous_revision BIGINT NOT NULL REFERENCES internal.gemini_routing_revisions(revision),
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL CHECK (window_end > window_start AND window_end <= window_start + INTERVAL '24 hours'),
    spending_cap_microusd BIGINT NOT NULL CHECK (spending_cap_microusd > 0),
    reserved_microusd BIGINT NOT NULL DEFAULT 0 CHECK (reserved_microusd >= 0 AND reserved_microusd <= spending_cap_microusd),
    status TEXT NOT NULL DEFAULT 'prepared' CHECK (status IN ('prepared','verified','activated','unhealthy','superseded')),
    verification JSONB,
    activated_revision BIGINT UNIQUE REFERENCES internal.gemini_routing_revisions(revision),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    UNIQUE(target,backend_sha,configuration_digest)
);
CREATE TABLE internal.gemini_release_smokes (
    release_id UUID NOT NULL REFERENCES internal.gemini_activation_releases(id),
    case_id TEXT NOT NULL CHECK (case_id ~ '^[a-z][a-z0-9_]{1,79}$'),
    case_digest TEXT NOT NULL CHECK (case_digest ~ '^[0-9a-f]{64}$'),
    requested_model TEXT NOT NULL CHECK (requested_model IN ('gemini-3.8-flash','gemini-3.5-flash-lite')),
    reservation_microusd BIGINT NOT NULL CHECK (reservation_microusd > 0),
    owner_token UUID,
    state TEXT NOT NULL DEFAULT 'ready' CHECK (state IN ('ready','claimed','dispatch_intent','passed','failed','uncertain','not_invoked')),
    claimed_at TIMESTAMPTZ,
    dispatch_intent_at TIMESTAMPTZ,
    outcome_at TIMESTAMPTZ,
    receipt JSONB CHECK (pg_catalog.octet_length(receipt::TEXT) <= 4096),
    settlement TEXT NOT NULL DEFAULT 'unreserved' CHECK (settlement IN ('unreserved','reserved','settled','unresolved')),
    PRIMARY KEY(release_id,case_id)
);
COMMENT ON TABLE internal.gemini_release_smokes IS
'One durable owner per authorized case. Neither claim/lease expiry nor missing response permits reclaim or replay. Uncertain cases cannot pass activation.';
CREATE TABLE internal.gemini_release_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    release_id UUID NOT NULL REFERENCES internal.gemini_activation_releases(id),
    revision BIGINT REFERENCES internal.gemini_routing_revisions(revision),
    kind TEXT NOT NULL CHECK (kind IN ('verified','activated','suspended','verification_passed')),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    evidence JSONB NOT NULL CHECK (pg_catalog.octet_length(evidence::TEXT) <= 65536)
);

ALTER TABLE internal.gemini_routing_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_routing_head ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_assignment_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_invocation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_activation_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_release_smokes ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.gemini_release_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.gemini_routing_revisions,internal.gemini_routing_head,
    internal.gemini_assignment_revisions,internal.gemini_invocation_receipts,
    internal.gemini_activation_releases,internal.gemini_release_smokes,
    internal.gemini_release_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE internal.gemini_release_events_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.gemini_dispatch_open(p_model TEXT,p_revision BIGINT)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path = '' AS $$
    SELECT p_model IN ('gemini-2.5-flash','gemini-2.5-pro','gemini-3.8-flash','gemini-3.5-flash-lite')
      AND (p_model NOT IN ('gemini-2.5-flash','gemini-2.5-pro') OR pg_catalog.clock_timestamp() < TIMESTAMPTZ '2026-11-30 00:00:00+00')
      AND EXISTS(SELECT 1 FROM internal.gemini_routing_revisions WHERE revision=p_revision AND status IN ('active','superseded'));
$$;
REVOKE ALL ON FUNCTION internal.gemini_dispatch_open(TEXT,BIGINT) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.authorize_gemini_transport(p_reservation_id UUID,p_user_id UUID,p_lease_token UUID,p_attempt_count INTEGER)
RETURNS UUID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s' AS $$
DECLARE saved internal.ai_quota_reservations; assigned BIGINT; receipt_id UUID;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.ai_quota_reservations WHERE id=p_reservation_id FOR UPDATE;
    IF NOT FOUND OR saved.user_id IS DISTINCT FROM p_user_id OR saved.lease_token IS DISTINCT FROM p_lease_token
      OR saved.attempt_count IS DISTINCT FROM p_attempt_count OR saved.state <> 'committed'
      OR saved.lease_expires_at <= pg_catalog.clock_timestamp() THEN
      RAISE EXCEPTION 'gemini_dispatch_not_owned' USING ERRCODE='55000';
    END IF;
    SELECT revision INTO assigned FROM internal.gemini_assignment_revisions
      WHERE operation=saved.operation AND effective_plan=saved.effective_plan
        AND policy_version=saved.policy_version AND requested_model=saved.model;
    IF assigned IS NULL AND saved.model IN ('gemini-2.5-flash','gemini-2.5-pro') THEN assigned:=0; END IF;
    -- Lock the revision through authorization, serializing with suspension. The
    -- network boundary remains external: once this returns, ambiguity is liability.
    PERFORM 1 FROM internal.gemini_routing_revisions WHERE revision=assigned FOR SHARE;
    IF NOT COALESCE(internal.gemini_dispatch_open(saved.model,assigned),FALSE) THEN
      RAISE EXCEPTION 'gemini_dispatch_closed' USING ERRCODE='55000';
    END IF;
    INSERT INTO internal.gemini_invocation_receipts(reservation_id,attempt_count,lease_token,assignment_revision,requested_model,state)
      VALUES(saved.id,saved.attempt_count,p_lease_token,assigned,saved.model,'dispatch_intent')
      ON CONFLICT(reservation_id,attempt_count) DO NOTHING RETURNING id INTO receipt_id;
    IF receipt_id IS NULL THEN RAISE EXCEPTION 'gemini_dispatch_already_owned' USING ERRCODE='55000'; END IF;
    RETURN receipt_id;
END;
$$;
REVOKE ALL ON FUNCTION public.authorize_gemini_transport(UUID,UUID,UUID,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.authorize_gemini_transport(UUID,UUID,UUID,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.authorize_gemini_transport(uuid,uuid,uuid,integer)','One owning committed reservation obtains a final Gemini transport witness; no retry, model selection or admission.');

CREATE FUNCTION public.record_gemini_invocation_receipt(p_receipt_id UUID,p_lease_token UUID,p_receipt JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s' AS $$
DECLARE saved internal.gemini_invocation_receipts; returned TEXT; key TEXT;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO saved FROM internal.gemini_invocation_receipts WHERE id=p_receipt_id FOR UPDATE;
    IF NOT FOUND OR saved.lease_token IS DISTINCT FROM p_lease_token THEN RAISE EXCEPTION 'gemini_receipt_not_owned' USING ERRCODE='55000'; END IF;
    IF pg_catalog.jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' OR pg_catalog.octet_length(p_receipt::TEXT)>4096
      OR NOT p_receipt ?& ARRAY['returnedModel','usage','usageConsistent','finishReason','failure']
      OR p_receipt-ARRAY['returnedModel','usage','usageConsistent','finishReason','failure']<>'{}'::JSONB
      OR p_receipt->'usageConsistent' NOT IN ('true'::JSONB,'false'::JSONB) THEN
      RAISE EXCEPTION 'gemini_receipt_invalid' USING ERRCODE='22023'; END IF;
    returned:=p_receipt->>'returnedModel';
    IF returned IS NOT NULL AND returned !~ '^gemini-[a-zA-Z0-9.-]{1,100}$' THEN RAISE EXCEPTION 'gemini_receipt_invalid' USING ERRCODE='22023'; END IF;
    IF p_receipt->'usage' <> 'null'::JSONB THEN
      IF pg_catalog.jsonb_typeof(p_receipt->'usage') IS DISTINCT FROM 'object'
        OR (p_receipt->'usage')-ARRAY['promptTokens','candidateTokens','thinkingTokens','cachedTokens','toolTokens','totalTokens','modalityBreakdown']<>'{}'::JSONB THEN RAISE EXCEPTION 'gemini_receipt_invalid' USING ERRCODE='22023'; END IF;
      FOREACH key IN ARRAY ARRAY['promptTokens','candidateTokens','thinkingTokens','cachedTokens','toolTokens','totalTokens'] LOOP
        IF p_receipt->'usage'->key <> 'null'::JSONB AND (pg_catalog.jsonb_typeof(p_receipt->'usage'->key)<>'number'
          OR p_receipt->'usage'->>key !~ '^[0-9]{1,9}$' OR (p_receipt->'usage'->>key)::NUMERIC>100000000) THEN RAISE EXCEPTION 'gemini_receipt_invalid' USING ERRCODE='22023'; END IF;
      END LOOP;
    END IF;
    IF saved.receipt IS NOT NULL THEN
      IF saved.receipt IS DISTINCT FROM p_receipt THEN RAISE EXCEPTION 'gemini_receipt_conflict' USING ERRCODE='23505'; END IF;
      RETURN TRUE;
    END IF;
    UPDATE internal.gemini_invocation_receipts SET returned_model=returned,receipt=p_receipt,
      state='received',response_received_at=pg_catalog.clock_timestamp() WHERE id=saved.id;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.record_gemini_invocation_receipt(UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_gemini_invocation_receipt(UUID,UUID,JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
('service_role','public.record_gemini_invocation_receipt(uuid,uuid,jsonb)','Durable content-free response facts for the owning transport witness, including rejected responses.');

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;

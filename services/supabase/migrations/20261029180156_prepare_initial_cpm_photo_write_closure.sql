SET statement_timeout='2min';
SET lock_timeout='5s';

-- Inactive database-owner contract only. No installed policy, API grant,
-- signer, storage request, funding, admission or capacity-release authority.
CREATE TABLE internal.initial_cpm_photo_write_policies(
 digest TEXT PRIMARY KEY CHECK(digest ~ '^[0-9a-f]{64}$'),
 backend_generation UUID NOT NULL,
 backend_configuration_digest TEXT NOT NULL,
 observation_build_digest TEXT NOT NULL CHECK(observation_build_digest ~ '^[0-9a-f]{64}$'),
 enforcement_evidence_digest TEXT NOT NULL CHECK(enforcement_evidence_digest ~ '^[0-9a-f]{64}$'),
 reviewed_revision TEXT NOT NULL CHECK(reviewed_revision ~ '^[0-9a-f]{40}$'),
 protocol TEXT NOT NULL CHECK(protocol='conditional_create_permanent_same_key_marker_v1'),
 state TEXT NOT NULL CHECK(state IN ('eligible','revoked')),
 FOREIGN KEY(backend_generation,backend_configuration_digest)
  REFERENCES internal.initial_preparation_source_backends(generation,configuration_digest),
 CHECK(digest=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-write-policy.v1'||E'\n'||
  internal.initial_canonical(jsonb_build_object('version',1,'backend_generation',backend_generation,
   'backend_configuration_digest',backend_configuration_digest,'observation_build_digest',observation_build_digest,
   'enforcement_evidence_digest',enforcement_evidence_digest,'reviewed_revision',reviewed_revision,'protocol',protocol)),
  'UTF8'),'sha256'),'hex'))
);
CREATE INDEX initial_cpm_photo_write_policy_backend ON internal.initial_cpm_photo_write_policies(backend_generation,backend_configuration_digest);
ALTER TABLE internal.initial_cpm_photo_write_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cpm_photo_write_policies FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_write_policy_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_write_policies
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_preparation_eligibility();
CREATE TRIGGER initial_cpm_photo_write_policy_no_truncate BEFORE TRUNCATE ON internal.initial_cpm_photo_write_policies
 FOR EACH STATEMENT EXECUTE FUNCTION internal.reject_initial_permanent_mutation();

ALTER TABLE internal.initial_cpm_photo_write_attempts
 ADD COLUMN write_policy_digest TEXT REFERENCES internal.initial_cpm_photo_write_policies(digest),
 ADD COLUMN write_closed BOOLEAN NOT NULL DEFAULT FALSE,
 ADD CONSTRAINT initial_cpm_photo_closed_requires_issued CHECK(NOT write_closed OR (state='may_have_issued' AND write_policy_digest IS NOT NULL));
CREATE INDEX initial_cpm_photo_write_attempt_policy ON internal.initial_cpm_photo_write_attempts(write_policy_digest);
DROP INDEX internal.initial_cpm_photo_one_outstanding_write;
CREATE UNIQUE INDEX initial_cpm_photo_one_outstanding_write ON internal.initial_cpm_photo_write_attempts(scan_id)
 WHERE state='may_have_issued' AND NOT write_closed;

-- Content-free permanent closure history. A live receipt survives later
-- retirement; a separate marker receipt records the terminal observation.
-- Claim tokens are not retained, only a domain-separated equality digest.
CREATE TABLE internal.initial_cpm_photo_write_closures(
 attempt_id UUID NOT NULL REFERENCES internal.initial_cpm_photo_write_attempts(attempt_id),
 outcome TEXT NOT NULL CHECK(outcome IN ('live_object','retired_marker')),
 policy_digest TEXT NOT NULL REFERENCES internal.initial_cpm_photo_write_policies(digest),
 observed_at TIMESTAMPTZ NOT NULL CHECK(isfinite(observed_at)),
 claim_digest TEXT CHECK(claim_digest ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY(attempt_id,outcome),
 CHECK((outcome='retired_marker')=(claim_digest IS NOT NULL))
);
CREATE INDEX initial_cpm_photo_write_closure_policy ON internal.initial_cpm_photo_write_closures(policy_digest);
ALTER TABLE internal.initial_cpm_photo_write_closures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cpm_photo_write_closures FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_write_closure_immutable BEFORE UPDATE OR DELETE ON internal.initial_cpm_photo_write_closures
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE TRIGGER initial_cpm_photo_write_closure_no_truncate BEFORE TRUNCATE ON internal.initial_cpm_photo_write_closures
 FOR EACH STATEMENT EXECUTE FUNCTION internal.reject_initial_permanent_mutation();

CREATE FUNCTION internal.guard_initial_cpm_photo_write_closure() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts; r internal.initial_preparation_source_registry;
BEGIN
 -- Match existing retirement order. Never acquire outer owner locks here.
 PERFORM internal.lock_initial_cpm_photo_capacity();
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=NEW.attempt_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM internal.initial_preparation_source_registry WHERE object_id=a.object_id FOR UPDATE;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=NEW.attempt_id FOR UPDATE;
 IF a.state<>'may_have_issued' OR a.write_policy_digest IS DISTINCT FROM NEW.policy_digest
  OR NEW.observed_at<a.issued_at OR NEW.observed_at>clock_timestamp() THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.initial_cpm_photo_write_policies p
  JOIN internal.initial_preparation_backend_eligibility b ON b.generation=p.backend_generation
  WHERE p.digest=NEW.policy_digest AND p.backend_generation=a.backend_generation
   AND p.backend_configuration_digest=a.backend_configuration_digest AND p.state='eligible' AND b.state='eligible'
  FOR SHARE OF p,b NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF NEW.outcome='live_object' THEN
  IF a.retired OR r.retired OR r.marker_confirmed OR r.claim_token IS NOT NULL OR NEW.claim_digest IS NOT NULL
   OR clock_timestamp()>=a.admission_expires_at
   OR NOT internal.initial_cpm_photo_cohort_complete(a.scan_id) THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 ELSE
  IF NOT a.retired OR NOT r.retired OR r.marker_confirmed OR r.claim_token IS NULL
   OR r.claim_expires_at<=clock_timestamp() OR NEW.observed_at<r.claim_expires_at-INTERVAL '1 minute'
   OR NEW.claim_digest IS DISTINCT FROM encode(extensions.digest(convert_to('merian.initial-analysis.cpm-erasure-claim.v1'||E'\n'||r.claim_token::TEXT,'UTF8'),'sha256'),'hex') THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cpm_photo_write_closure() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_write_closure_guard BEFORE INSERT ON internal.initial_cpm_photo_write_closures
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_photo_write_closure();

CREATE OR REPLACE FUNCTION internal.guard_initial_cpm_photo_write_attempt() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents;
BEGIN
 IF TG_OP='UPDATE' AND NOT OLD.retired AND NEW.retired
  AND to_jsonb(NEW)-'retired'=to_jsonb(OLD)-'retired'
  AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry
   WHERE scan_id=OLD.scan_id AND object_id=OLD.object_id AND retired) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NOT OLD.write_closed AND NEW.write_closed
  AND to_jsonb(NEW)-'write_closed'=to_jsonb(OLD)-'write_closed'
  AND EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_closures WHERE attempt_id=OLD.attempt_id) THEN RETURN NEW; END IF;
 IF TG_OP IN ('DELETE','TRUNCATE') THEN
  RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
 -- Raw inserts/advances share retirement's fail-fast serialization. Never
 -- acquire an outer owner lock from a row trigger. After the lock, each SQL
 -- command uses its fresh READ COMMITTED snapshot; registry precedes attempt
 -- creation. A conflicting capacity owner fails instead of forming a cycle.
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM 1 FROM internal.initial_preparation_source_registry
  WHERE scan_id=NEW.scan_id AND object_id=NEW.object_id FOR UPDATE;
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=NEW.scan_id;
 IF NOT FOUND OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo'
  OR NEW.retired OR NEW.assignment_digest IS DISTINCT FROM saved.assignment_digest
  OR NEW.admission_expires_at IS DISTINCT FROM saved.expires_at
  OR NEW.created_at<saved.created_at OR NEW.created_at>clock_timestamp()
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry r
   JOIN internal.initial_cpm_photo_role_mapping m USING(scan_id,object_id)
   JOIN internal.initial_preparation_source_backends b ON b.generation=r.backend_generation
   WHERE r.scan_id=NEW.scan_id AND r.object_id=NEW.object_id
    AND NOT r.retired AND NOT r.marker_confirmed AND r.claim_token IS NULL
    AND r.backend_generation=NEW.backend_generation AND b.configuration_digest=NEW.backend_configuration_digest
    AND r.backend_generation::TEXT=(saved.canonical_assignment::JSONB#>>'{preparation,backend_generation}')) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 IF TG_OP='UPDATE' AND OLD.state='bound' AND OLD.write_policy_digest IS NULL
  AND NEW.write_policy_digest IS NOT NULL AND NOT NEW.write_closed
  AND to_jsonb(NEW)-'write_policy_digest'=to_jsonb(OLD)-'write_policy_digest'
  AND clock_timestamp()<NEW.capability_expires_at THEN
  PERFORM 1 FROM internal.initial_cpm_photo_write_policies p
   JOIN internal.initial_preparation_backend_eligibility b ON b.generation=p.backend_generation
   WHERE p.digest=NEW.write_policy_digest AND p.state='eligible' AND b.state='eligible'
    AND p.backend_generation=NEW.backend_generation AND p.backend_configuration_digest=NEW.backend_configuration_digest
   FOR SHARE OF p,b NOWAIT;
  IF FOUND THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000';
 END IF;
 IF TG_OP='INSERT' AND NEW.state='bound' AND NEW.write_policy_digest IS NULL AND NOT NEW.write_closed AND NEW.issued_at IS NULL
  AND clock_timestamp()<NEW.capability_expires_at
  AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=NEW.scan_id AND state='may_have_issued' AND NOT write_closed) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.state='bound' AND NEW.state='may_have_issued' AND OLD.write_policy_digest IS NOT NULL THEN
  PERFORM 1 FROM internal.initial_cpm_photo_write_policies p
   JOIN internal.initial_preparation_backend_eligibility b ON b.generation=p.backend_generation
   WHERE p.digest=OLD.write_policy_digest AND p.state='eligible' AND b.state='eligible'
    AND p.backend_generation=OLD.backend_generation AND p.backend_configuration_digest=OLD.backend_configuration_digest
    AND b.configuration_digest=OLD.backend_configuration_digest
   FOR SHARE OF p,b NOWAIT;
  IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.state='bound' AND NEW.state='may_have_issued'
  AND NOT OLD.retired AND NEW.issued_at IS NOT NULL AND NEW.issued_at<=clock_timestamp()
  AND clock_timestamp()<NEW.capability_expires_at
  AND to_jsonb(NEW)-ARRAY['state','issued_at']=to_jsonb(OLD)-ARRAY['state','issued_at']
  AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=NEW.scan_id AND state='may_have_issued' AND NOT write_closed) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_cpm_photo_write_action(
 p_action TEXT,p_owner UUID,p_scan UUID,p_digest TEXT,p_object UUID
) RETURNS internal.initial_cpm_photo_write_attempts
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents;
 attempt internal.initial_cpm_photo_write_attempts;
 registry internal.initial_preparation_source_registry;
 backend internal.initial_preparation_source_backends;
 now_at TIMESTAMPTZ;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('bind','status','may_have_issued')
  OR p_owner IS NULL OR p_scan IS NULL OR p_object IS NULL OR p_digest IS NULL THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR saved.owner_id IS DISTINCT FROM p_owner
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 IF saved.assignment_digest IS DISTINCT FROM p_digest THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 SELECT * INTO registry FROM internal.initial_preparation_source_registry
  WHERE scan_id=p_scan AND object_id=p_object FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO attempt FROM internal.initial_cpm_photo_write_attempts WHERE object_id=p_object FOR UPDATE;
 IF FOUND AND (p_action IN ('bind','status') OR attempt.state='may_have_issued') THEN RETURN attempt; END IF;
 IF p_action='status' THEN RETURN NULL; END IF;
 IF NOT internal.initial_cpm_photo_cohort_complete(p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,p_scan);
 now_at:=date_trunc('milliseconds',clock_timestamp());
 IF now_at>=saved.expires_at OR (attempt.attempt_id IS NOT NULL AND now_at>=attempt.capability_expires_at) THEN
  RAISE EXCEPTION 'initial_analysis_preparation_expired' USING ERRCODE='55000'; END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan AND state='may_have_issued' AND NOT write_closed) THEN
  RAISE EXCEPTION 'initial_analysis_cpm_write_outstanding' USING ERRCODE='55000'; END IF;
 -- Current revocation blocks new transitions. Saved status above remains exact.
 PERFORM 1 FROM internal.initial_preparation_backend_eligibility
  WHERE generation=registry.backend_generation AND state='eligible' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM 1 FROM internal.initial_cpm_photo_profile_eligibility
  WHERE profile_digest=(saved.canonical_assignment::JSONB#>>'{preparation,profile_digest}') AND state='eligible' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF p_action='bind' THEN
  SELECT * INTO STRICT backend FROM internal.initial_preparation_source_backends WHERE generation=registry.backend_generation;
  INSERT INTO internal.initial_cpm_photo_write_attempts(scan_id,object_id,assignment_digest,backend_generation,
   backend_configuration_digest,created_at,admission_expires_at,capability_expires_at)
  VALUES(p_scan,p_object,p_digest,registry.backend_generation,backend.configuration_digest,now_at,saved.expires_at,
   LEAST(saved.expires_at,now_at+INTERVAL '10 minutes')) RETURNING * INTO attempt;
 ELSE
  IF attempt.attempt_id IS NULL THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  UPDATE internal.initial_cpm_photo_write_attempts SET state='may_have_issued',issued_at=now_at
   WHERE attempt_id=attempt.attempt_id RETURNING * INTO attempt;
  UPDATE internal.initial_cpm_photo_capacity_reservations SET write_capability_state='may_have_issued'
   WHERE scan_id=p_scan AND write_capability_state='never_issued';
 END IF;
 RETURN attempt;
END; $$;


CREATE FUNCTION internal.bind_initial_cpm_photo_write_policy(p_owner UUID,p_attempt UUID,p_policy TEXT)
 RETURNS internal.initial_cpm_photo_write_attempts LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts;
BEGIN
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt;
 IF NOT FOUND OR p_owner IS NULL OR p_policy IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,a.scan_id);
 PERFORM internal.assert_initial_preparation_unfunded(p_owner,a.scan_id);
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM 1 FROM internal.initial_preparation_source_registry WHERE object_id=a.object_id FOR UPDATE;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 IF a.write_policy_digest=p_policy THEN RETURN a; END IF;
 IF a.write_policy_digest IS NOT NULL THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 UPDATE internal.initial_cpm_photo_write_attempts SET write_policy_digest=p_policy WHERE attempt_id=p_attempt RETURNING * INTO a;
 RETURN a;
END; $$;
REVOKE ALL ON FUNCTION internal.bind_initial_cpm_photo_write_policy(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

-- Called only by a future trusted observation coordinator, never by accepting
-- client JSON. Original token is captured before IO. No network runs in SQL.
CREATE FUNCTION internal.settle_initial_cpm_photo_write_closure(
 p_attempt UUID,p_policy TEXT,p_outcome TEXT,p_observed_at TIMESTAMPTZ,p_claim UUID
) RETURNS internal.initial_cpm_photo_write_closures LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a internal.initial_cpm_photo_write_attempts; saved internal.initial_cpm_photo_write_closures;
 owner_id UUID; claim_hash TEXT;
BEGIN
 IF p_attempt IS NULL OR p_policy IS NULL OR p_outcome IS NULL OR p_outcome NOT IN ('live_object','retired_marker')
  OR p_observed_at IS NULL OR NOT isfinite(p_observed_at) OR (p_outcome='retired_marker')<>(p_claim IS NOT NULL) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 claim_hash:=CASE WHEN p_claim IS NULL THEN NULL ELSE encode(extensions.digest(convert_to('merian.initial-analysis.cpm-erasure-claim.v1'||E'\n'||p_claim::TEXT,'UTF8'),'sha256'),'hex') END;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 -- Live settlement uses the existing outer order; cleanup never takes it.
 IF p_outcome='live_object' THEN
  SELECT i.owner_id INTO owner_id FROM internal.initial_analysis_preparation_intents i WHERE scan_id=a.scan_id;
  IF owner_id IS NOT NULL THEN PERFORM internal.lock_initial_preparation_scope(owner_id,a.scan_id); END IF;
 END IF;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM 1 FROM internal.initial_preparation_source_registry WHERE object_id=a.object_id FOR UPDATE;
 SELECT * INTO a FROM internal.initial_cpm_photo_write_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO saved FROM internal.initial_cpm_photo_write_closures WHERE attempt_id=p_attempt AND outcome=p_outcome;
 IF FOUND THEN
  IF saved.policy_digest IS DISTINCT FROM p_policy OR saved.observed_at IS DISTINCT FROM p_observed_at
   OR saved.claim_digest IS DISTINCT FROM claim_hash THEN RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
  RETURN saved;
 END IF;
 IF p_outcome='live_object' THEN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.assert_initial_preparation_unfunded(owner_id,a.scan_id);
 END IF;
 INSERT INTO internal.initial_cpm_photo_write_closures(attempt_id,outcome,policy_digest,observed_at,claim_digest)
 VALUES(p_attempt,p_outcome,p_policy,p_observed_at,claim_hash) RETURNING * INTO saved;
 UPDATE internal.initial_cpm_photo_write_attempts SET write_closed=TRUE WHERE attempt_id=p_attempt AND NOT write_closed;
 RETURN saved;
END; $$;
REVOKE ALL ON FUNCTION internal.settle_initial_cpm_photo_write_closure(UUID,TEXT,TEXT,TIMESTAMPTZ,UUID) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_cpm_photo_write_closures IS 'Inactive database-owner closure metadata under separately qualified immutable policy; not byte proof, cleanup completion, release authority or issuer. No installed coordinator. Retains content-free exact replay through erasure.';
COMMENT ON FUNCTION internal.initial_cpm_photo_write_action(TEXT,UUID,UUID,TEXT,UUID) IS 'Inactive bookkeeping only. Historical may-have-issued status is exact, never permission to sign. Only durable policy-bound closure removes the outstanding-role exclusion. Capacity remains held. No close-by-expiry, retry, funding or provider authority.';
RESET lock_timeout;
RESET statement_timeout;

SET statement_timeout='2min';
SET lock_timeout='5s';

-- Inactive metadata only. No API-role grants, signer, ticket, upload, closure,
-- verification or funding authority. A future qualified capability contract is
-- required before any adapter can consume these database-owner transitions.
CREATE TABLE internal.initial_cpm_photo_write_attempts(
 attempt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 scan_id UUID NOT NULL REFERENCES internal.initial_cpm_photo_capacity_reservations(scan_id),
 object_id UUID NOT NULL UNIQUE,
 assignment_digest TEXT NOT NULL CHECK(assignment_digest ~ '^[0-9a-f]{64}$'),
 backend_generation UUID NOT NULL REFERENCES internal.initial_preparation_source_backends(generation),
 backend_configuration_digest TEXT NOT NULL CHECK(backend_configuration_digest ~ '^[0-9a-f]{64}$'),
 created_at TIMESTAMPTZ NOT NULL,
 admission_expires_at TIMESTAMPTZ NOT NULL,
 capability_expires_at TIMESTAMPTZ NOT NULL,
 state TEXT NOT NULL DEFAULT 'bound' CHECK(state IN ('bound','may_have_issued')),
 issued_at TIMESTAMPTZ,
 retired BOOLEAN NOT NULL DEFAULT FALSE,
 FOREIGN KEY(scan_id,object_id) REFERENCES internal.initial_preparation_source_registry(scan_id,object_id),
 CHECK(isfinite(created_at) AND isfinite(admission_expires_at) AND isfinite(capability_expires_at)),
 CHECK(date_trunc('milliseconds',created_at)=created_at),
 CHECK(capability_expires_at=LEAST(admission_expires_at,created_at+INTERVAL '10 minutes')),
 CHECK(capability_expires_at>created_at),
 CHECK((state='bound')=(issued_at IS NULL)),
 CHECK(issued_at IS NULL OR (isfinite(issued_at) AND issued_at>=created_at AND issued_at<capability_expires_at))
);
CREATE UNIQUE INDEX initial_cpm_photo_one_outstanding_write ON internal.initial_cpm_photo_write_attempts(scan_id) WHERE state='may_have_issued';
CREATE INDEX initial_cpm_photo_write_attempts_scan ON internal.initial_cpm_photo_write_attempts(scan_id,object_id);
CREATE INDEX initial_cpm_photo_write_attempts_backend ON internal.initial_cpm_photo_write_attempts(backend_generation);
ALTER TABLE internal.initial_cpm_photo_write_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cpm_photo_write_attempts FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE internal.initial_cpm_photo_write_attempts IS 'Permanent content-free role attempt identity and conservative outstanding-write liability. Exact private declarations remain solely in erasable preparation assignments. No owner reparenting, API access, issued capability or physical proof. Bound is not issued; may_have_issued can never close or release capacity in this increment.';

-- PostgreSQL shortens automatically generated constraint names. Resolve the
-- unique single-column check from the catalog instead of guessing its spelling.
DO $constraint$
DECLARE constraint_name TEXT;
BEGIN
 SELECT c.conname INTO STRICT constraint_name FROM pg_catalog.pg_constraint c
 WHERE c.conrelid='internal.initial_cpm_photo_capacity_reservations'::REGCLASS AND c.contype='c'
  AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
   WHERE attrelid=c.conrelid AND attname='write_capability_state')]::SMALLINT[];
 EXECUTE format('ALTER TABLE internal.initial_cpm_photo_capacity_reservations DROP CONSTRAINT %I',constraint_name);
END; $constraint$;
ALTER TABLE internal.initial_cpm_photo_capacity_reservations
 ADD CONSTRAINT initial_cpm_photo_capacity_write_state_check
 CHECK(write_capability_state IN ('never_issued','may_have_issued'));

-- Cleanup retains registry->attempt ordering and never takes outer owner locks.
CREATE FUNCTION internal.retire_initial_cpm_photo_write_attempt() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 UPDATE internal.initial_cpm_photo_write_attempts SET retired=TRUE
 WHERE object_id=NEW.object_id AND NOT retired;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.retire_initial_cpm_photo_write_attempt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_write_retirement AFTER UPDATE OF retired ON internal.initial_preparation_source_registry
 FOR EACH ROW WHEN(NEW.retired AND NOT OLD.retired) EXECUTE FUNCTION internal.retire_initial_cpm_photo_write_attempt();

CREATE FUNCTION internal.guard_initial_cpm_photo_write_attempt() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents;
BEGIN
 IF TG_OP='UPDATE' AND NOT OLD.retired AND NEW.retired
  AND to_jsonb(NEW)-'retired'=to_jsonb(OLD)-'retired'
  AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry
   WHERE scan_id=OLD.scan_id AND object_id=OLD.object_id AND retired) THEN RETURN NEW; END IF;
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
 IF TG_OP='INSERT' AND NEW.state='bound' AND NEW.issued_at IS NULL
  AND clock_timestamp()<NEW.capability_expires_at
  AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=NEW.scan_id AND state='may_have_issued') THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.state='bound' AND NEW.state='may_have_issued'
  AND NOT OLD.retired AND NEW.issued_at IS NOT NULL AND NEW.issued_at<=clock_timestamp()
  AND clock_timestamp()<NEW.capability_expires_at
  AND to_jsonb(NEW)-ARRAY['state','issued_at']=to_jsonb(OLD)-ARRAY['state','issued_at']
  AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=NEW.scan_id AND state='may_have_issued') THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;
REVOKE ALL ON FUNCTION internal.guard_initial_cpm_photo_write_attempt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_photo_write_attempt_guard BEFORE INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_write_attempts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_cpm_photo_write_attempt();

CREATE TRIGGER initial_cpm_photo_write_attempt_no_truncate BEFORE TRUNCATE ON internal.initial_cpm_photo_write_attempts
 FOR EACH STATEMENT EXECUTE FUNCTION internal.guard_initial_cpm_photo_write_attempt();

-- Only this exact terminal graph permits an outstanding reservation after
-- private erasure. No private declaration, current owner or signed URL survives.
CREATE FUNCTION internal.initial_cpm_photo_retired_write_hold(p_scan UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations
   WHERE scan_id=p_scan AND state='pending' AND write_capability_state='may_have_issued')
 AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences
   WHERE scan_id=p_scan AND state='retired' AND execution_state='unissued' AND provider_barrier='blocked_pre_admission')
 AND EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan AND state='may_have_issued')
 AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan AND NOT retired)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan AND NOT retired)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=p_scan);
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_retired_write_hold(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Cohort validity is structural. It never authorizes IO or asserts closure.
CREATE OR REPLACE FUNCTION internal.guard_initial_cpm_photo_capacity() RETURNS TRIGGER
LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE owner_pending BIGINT; global_pending BIGINT; owner_retained BIGINT; global_retained BIGINT;
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.owner_id IS NULL OR NEW.state IS DISTINCT FROM 'pending'
   OR NEW.write_capability_state IS DISTINCT FROM 'never_issued' THEN
   RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
  PERFORM internal.lock_initial_preparation_scope(NEW.owner_id,NEW.scan_id);
  PERFORM internal.lock_initial_cpm_photo_capacity();
  -- Each command below observes the snapshot after global serialization. Both
  -- the per-owner and global pending pools reserve192MiB for every intent.
  SELECT count(*) FILTER(WHERE owner_id=NEW.owner_id),count(*),
   COALESCE(sum(declared_retained_bytes) FILTER(WHERE owner_id=NEW.owner_id),0),
   COALESCE(sum(declared_retained_bytes),0)
   INTO owner_pending,global_pending,owner_retained,global_retained
   FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending';
  IF owner_pending>=2 OR global_pending>=16
   OR owner_retained+NEW.declared_retained_bytes>5368709120
   OR global_retained+NEW.declared_retained_bytes>53687091200 THEN
   RAISE EXCEPTION 'initial_analysis_capacity_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 ELSIF TG_OP='UPDATE' THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
  IF OLD.owner_id IS NOT NULL AND NEW.owner_id IS NULL
   AND to_jsonb(NEW)-'owner_id'=to_jsonb(OLD)-'owner_id'
   AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id) THEN RETURN NEW; END IF;
  IF OLD.state='pending' AND OLD.write_capability_state='never_issued'
   AND NEW.write_capability_state='may_have_issued'
   AND to_jsonb(NEW)-'write_capability_state'=to_jsonb(OLD)-'write_capability_state'
   AND EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts
    WHERE scan_id=OLD.scan_id AND state='may_have_issued' AND NOT retired) THEN RETURN NEW; END IF;
  IF OLD.state='pending' AND NEW.state='released'
   AND to_jsonb(NEW)-'state'=to_jsonb(OLD)-'state'
   AND OLD.write_capability_state='never_issued'
   AND EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=OLD.scan_id
    AND state='retired' AND execution_state='unissued' AND provider_barrier='blocked_pre_admission')
   AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=OLD.scan_id AND NOT retired)
   AND (OLD.owner_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.owner_id)
    OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id)
    OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL))
   AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=OLD.scan_id)
   AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=OLD.scan_id) THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END; $$;

CREATE OR REPLACE FUNCTION internal.initial_cpm_photo_cohort_complete(p_scan UUID) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; member JSONB; members INTEGER; retained BIGINT;
BEGIN
 SELECT * INTO saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF NOT FOUND OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo'
  OR NOT internal.initial_cpm_photo_saved_profile_matches(saved.canonical_candidate,saved.canonical_assignment) THEN RETURN FALSE; END IF;
 a:=saved.canonical_assignment::JSONB; members:=jsonb_array_length(a#>'{preparation,role_mapping}');
 SELECT sum((m#>>'{declaration,byte_count}')::BIGINT) INTO retained FROM jsonb_array_elements(a#>'{preparation,role_mapping}') m;
 IF extract(epoch FROM saved.created_at)*1000<>(a->>'created_at_ms')::NUMERIC
  OR extract(epoch FROM saved.expires_at)*1000<>(a->>'expires_at_ms')::NUMERIC
  OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan
   AND state='allocated' AND execution_state='unissued' AND provider_barrier='blocked_pre_admission')
  OR NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan
   AND owner_id=saved.owner_id AND state='pending' AND declared_retained_bytes=retained
   AND (write_capability_state='may_have_issued')=EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan AND state='may_have_issued'))
  OR (SELECT count(*) FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=p_scan)<>members
  OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan)<>members
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan) THEN RETURN FALSE; END IF;
 FOR member IN SELECT m FROM jsonb_array_elements(a#>'{preparation,role_mapping}') m LOOP
  IF NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping m JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
   WHERE m.scan_id=p_scan AND m.photo_ordinal=(member->>'photo_ordinal')::INTEGER AND m.role=member->>'role'
    AND m.reference_id::TEXT=member#>>'{declaration,reference_id}' AND m.object_id::TEXT=member->>'object_id'
    AND r.backend_generation::TEXT=a#>>'{preparation,backend_generation}' AND NOT r.retired AND NOT r.marker_confirmed AND r.claim_token IS NULL) THEN RETURN FALSE; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts w
  JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
  JOIN internal.initial_preparation_source_backends b ON b.generation=r.backend_generation
  WHERE w.scan_id=p_scan AND (w.retired OR w.assignment_digest<>saved.assignment_digest
   OR w.admission_expires_at<>saved.expires_at OR w.backend_generation<>r.backend_generation
   OR w.backend_configuration_digest<>b.configuration_digest)) THEN RETURN FALSE; END IF;
 RETURN TRUE;
END; $$;

CREATE OR REPLACE FUNCTION internal.require_initial_cpm_photo_cohort() RETURNS TRIGGER
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE identity UUID; candidate TEXT;
BEGIN
 identity:=CASE WHEN TG_OP='DELETE' THEN OLD.scan_id ELSE NEW.scan_id END;
 SELECT canonical_candidate INTO candidate FROM internal.initial_analysis_preparation_intents WHERE scan_id=identity;
 IF candidate IS NOT NULL AND candidate::JSONB->>'variant'='client_prepared_photo' THEN
  IF NOT internal.initial_cpm_photo_cohort_complete(identity) THEN
   RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 ELSIF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id=identity)
  OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=identity AND NOT retired)
  OR (EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=identity AND state<>'released')
   AND NOT internal.initial_cpm_photo_retired_write_hold(identity)) THEN
  RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;

CREATE OR REPLACE FUNCTION internal.retire_initial_preparation_source_objects(p_scan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE object UUID;
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan AND state='pending') THEN
  PERFORM internal.lock_initial_cpm_photo_capacity();
 END IF;
 PERFORM internal.advance_initial_cancellation_retirement(p_scan,'source','begin');
 UPDATE internal.initial_preparation_source_fences SET state='retired' WHERE scan_id=p_scan AND state='allocated';
 FOR object IN SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  UPDATE internal.initial_preparation_source_registry SET retired=TRUE WHERE object_id=object AND NOT retired;
 END LOOP;
 PERFORM internal.advance_initial_cancellation_retirement(p_scan,'source','end');
 -- Closed never-issued proof is enforced again by the reservation guard.
 UPDATE internal.initial_cpm_photo_capacity_reservations SET state='released' WHERE scan_id=p_scan AND state='pending' AND write_capability_state='never_issued';
END; $function$;

CREATE CONSTRAINT TRIGGER initial_cpm_photo_write_attempt_cohort AFTER INSERT OR UPDATE OR DELETE ON internal.initial_cpm_photo_write_attempts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION internal.require_initial_cpm_photo_cohort();

-- Database-owner metadata only. No API wrapper, grants or qualified signer.
-- The may-have-issued transaction must commit BEFORE any future signer IO.
-- Replays never extend a clock or mint a replacement attempt/capability.
CREATE FUNCTION internal.initial_cpm_photo_write_action(
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
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan AND state='may_have_issued') THEN
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
REVOKE ALL ON FUNCTION internal.initial_cpm_photo_write_action(TEXT,UUID,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.initial_cpm_photo_write_action(TEXT,UUID,UUID,TEXT,UUID) IS 'Inactive database-owner bookkeeping only; not an issuance capability. Requires a separately reviewed backend capability contract before use by a signer. No close, refresh, verify, release or provider action. Commit may_have_issued before any future external signing; lost acknowledgements retain liability.';
RESET lock_timeout;
RESET statement_timeout;

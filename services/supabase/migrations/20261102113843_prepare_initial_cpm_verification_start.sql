-- Inactive durable start boundary for the coordinated CPM verifier/admission.
-- No public RPC/grant, verifier installation, media I/O or funding is added.
-- Unknown acknowledgement stays held; expiry never renews this attempt.
SET statement_timeout='60s';
SET lock_timeout='5s';

ALTER TABLE internal.initial_analysis_preparation_intents
 ADD COLUMN cpm_verification_attempt_id UUID,
 ADD COLUMN cpm_verification_started_at TIMESTAMPTZ,
 ADD COLUMN cpm_verification_snapshot_digest TEXT,
 ADD CONSTRAINT initial_cpm_verification_start_shape CHECK (COALESCE(
  num_nonnulls(cpm_verification_attempt_id,cpm_verification_started_at,cpm_verification_snapshot_digest)=0
  OR (num_nonnulls(cpm_verification_attempt_id,cpm_verification_started_at,cpm_verification_snapshot_digest)=3
   AND canonical_candidate::JSONB->>'variant'='client_prepared_photo'
   AND isfinite(cpm_verification_started_at)
   AND cpm_verification_started_at>=created_at AND cpm_verification_started_at<expires_at
   AND cpm_verification_snapshot_digest ~ '^[0-9a-f]{64}$'),FALSE));
CREATE UNIQUE INDEX initial_cpm_verification_attempt_identity
 ON internal.initial_analysis_preparation_intents(cpm_verification_attempt_id)
 WHERE cpm_verification_attempt_id IS NOT NULL;

-- A transient write context, not a second verification result/claim store.
-- Only the fixed lock-owning begin function inserts here. No API role can
-- construct it, and no insertion helper is exposed. It must vanish before commit.
CREATE TABLE internal.initial_cpm_verification_start_context(
 transaction_id XID8 PRIMARY KEY,
 owner_id UUID NOT NULL,
 scan_id UUID NOT NULL UNIQUE,
 attempt_id UUID NOT NULL UNIQUE,
 old_digest TEXT NOT NULL CHECK(old_digest ~ '^[0-9a-f]{64}$'),
 new_digest TEXT NOT NULL CHECK(new_digest ~ '^[0-9a-f]{64}$')
);
ALTER TABLE internal.initial_cpm_verification_start_context ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_cpm_verification_start_context FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER initial_cpm_verification_context_no_update BEFORE UPDATE OR TRUNCATE
 ON internal.initial_cpm_verification_start_context FOR EACH STATEMENT EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
CREATE FUNCTION internal.require_initial_cpm_verification_context_consumed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context WHERE transaction_id=NEW.transaction_id) THEN
  RAISE EXCEPTION 'initial_analysis_verification_start_incomplete' USING ERRCODE='55000'; END IF;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION internal.require_initial_cpm_verification_context_consumed() FROM PUBLIC,anon,authenticated,service_role;
CREATE CONSTRAINT TRIGGER initial_cpm_verification_context_consumed AFTER INSERT
 ON internal.initial_cpm_verification_start_context DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION internal.require_initial_cpm_verification_context_consumed();

CREATE FUNCTION internal.initial_cpm_verification_intent_digest(p_row internal.initial_analysis_preparation_intents)
RETURNS TEXT LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT encode(extensions.digest(convert_to(((to_jsonb(p_row)-ARRAY['created_at','expires_at','cpm_verification_started_at'])
  ||jsonb_build_object('created_at',internal.initial_admission_timestamp(p_row.created_at),
   'expires_at',internal.initial_admission_timestamp(p_row.expires_at),
   'cpm_verification_started_at',CASE WHEN p_row.cpm_verification_started_at IS NOT NULL
    THEN internal.initial_admission_timestamp(p_row.cpm_verification_started_at) END))::TEXT,'UTF8'),'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_verification_intent_digest(internal.initial_analysis_preparation_intents)
 FROM PUBLIC,anon,authenticated,service_role;

-- Only the original intent/cohort is captured. No backend credential, URL,
-- cleanup claim or fabricated M1 destination is verification authority.
CREATE FUNCTION internal.initial_cpm_verification_start_snapshot(p_owner UUID,p_scan UUID)
RETURNS TEXT LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; a JSONB; members JSONB;
 snapshot TEXT; backend internal.initial_preparation_source_backends;
BEGIN
 PERFORM internal.require_service_role();
 -- Caller already owns the outer scope and cohort locks. This helper is also
 -- used by the row validator, which must never acquire outer locks itself.
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan;
 IF saved.owner_id IS DISTINCT FROM p_owner
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_preparation_required' USING ERRCODE='55000'; END IF;
 a:=saved.canonical_assignment::JSONB;
 IF NOT internal.initial_cpm_photo_cohort_complete(p_scan) THEN
  RAISE EXCEPTION 'initial_analysis_source_cohort_invalid' USING ERRCODE='23514'; END IF;
 SELECT * INTO STRICT backend FROM internal.initial_preparation_source_backends
  WHERE generation=(a#>>'{preparation,backend_generation}')::UUID;
 -- write_closed alone also describes retired-marker closure. Require each exact
 -- issued attempt and its positive LIVE receipt, with no erasure claim/retirement.
 SELECT jsonb_agg(jsonb_build_object('role',m,
  'attempt',(to_jsonb(w)-ARRAY['created_at','admission_expires_at','capability_expires_at','issued_at'])||jsonb_build_object(
   'created_at',internal.initial_admission_timestamp(w.created_at),
   'admission_expires_at',internal.initial_admission_timestamp(w.admission_expires_at),
   'capability_expires_at',internal.initial_admission_timestamp(w.capability_expires_at),
   'issued_at',internal.initial_admission_timestamp(w.issued_at)),
  'closure',(to_jsonb(c)-'observed_at')||jsonb_build_object('observed_at',internal.initial_admission_timestamp(c.observed_at))) ORDER BY ordinal)
 INTO members FROM jsonb_array_elements(a#>'{preparation,role_mapping}') WITH ORDINALITY roles(m,ordinal)
 JOIN internal.initial_cpm_photo_write_attempts w ON w.scan_id=p_scan AND w.object_id=(m->>'object_id')::UUID
 JOIN internal.initial_cpm_photo_write_closures c ON c.attempt_id=w.attempt_id AND c.outcome='live_object'
 WHERE w.state='may_have_issued' AND w.write_closed AND NOT w.retired
  AND w.assignment_digest=saved.assignment_digest AND w.admission_expires_at=saved.expires_at
  AND w.backend_generation=backend.generation AND w.backend_configuration_digest=backend.configuration_digest
  AND c.policy_digest=w.write_policy_digest AND c.claim_digest IS NULL;
 IF members IS NULL OR jsonb_array_length(members)<>jsonb_array_length(a#>'{preparation,role_mapping}') THEN
  RAISE EXCEPTION 'initial_analysis_verification_required' USING ERRCODE='55000'; END IF;
 snapshot:=internal.initial_canonical(jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,
  'candidate_digest',saved.candidate_digest,'content_digest',a->'content_digest','assignment_digest',saved.assignment_digest,
  'profile_digest',a#>'{preparation,profile_digest}','verifier_build_digest',a#>'{preparation,verifier_build_digest}',
  'backend_generation',backend.generation,'backend_configuration_digest',backend.configuration_digest,
  'original_expires_at_ms',a->'expires_at_ms','members',members));
 IF octet_length(snapshot)>65536 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 RETURN snapshot;
END; $$;
REVOKE ALL ON FUNCTION internal.initial_cpm_verification_start_snapshot(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.assert_initial_cpm_verification_start(
 p_old internal.initial_analysis_preparation_intents,p_new internal.initial_analysis_preparation_intents
) RETURNS VOID LANGUAGE plpgsql VOLATILE SET search_path='' AS $$
DECLARE snapshot TEXT; a JSONB:=p_old.canonical_assignment::JSONB; now_at TIMESTAMPTZ:=clock_timestamp();
 context internal.initial_cpm_verification_start_context;
BEGIN
 PERFORM internal.require_service_role();
 -- Consume the protected exact context before any nested work. A forged GUC,
 -- copied attempt or matching digest cannot substitute for this private row.
 DELETE FROM internal.initial_cpm_verification_start_context
 WHERE transaction_id=pg_catalog.pg_current_xact_id() AND owner_id=p_old.owner_id
  AND scan_id=p_old.scan_id AND attempt_id=p_new.cpm_verification_attempt_id
  AND old_digest=internal.initial_cpm_verification_intent_digest(p_old)
  AND new_digest=internal.initial_cpm_verification_intent_digest(p_new)
 RETURNING * INTO context;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_cpm_photo_capacity();
 IF num_nonnulls(p_old.cpm_verification_attempt_id,p_old.cpm_verification_started_at,p_old.cpm_verification_snapshot_digest)<>0
  OR num_nonnulls(p_new.cpm_verification_attempt_id,p_new.cpm_verification_started_at,p_new.cpm_verification_snapshot_digest)<>3
  OR to_jsonb(p_new)-ARRAY['cpm_verification_attempt_id','cpm_verification_started_at','cpm_verification_snapshot_digest']
   IS DISTINCT FROM to_jsonb(p_old)-ARRAY['cpm_verification_attempt_id','cpm_verification_started_at','cpm_verification_snapshot_digest']
  OR p_new.cpm_verification_started_at>now_at OR p_new.cpm_verification_started_at<now_at-INTERVAL '5 seconds'
  OR now_at>=p_old.expires_at THEN
  RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023'; END IF;
 snapshot:=internal.initial_cpm_verification_start_snapshot(p_old.owner_id,p_old.scan_id);
 PERFORM internal.assert_initial_preparation_unfunded(p_old.owner_id,p_old.scan_id);
 PERFORM singleton FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM profile_digest FROM internal.initial_cpm_photo_profile_eligibility
  WHERE profile_digest=a#>>'{preparation,profile_digest}' AND state='eligible'
   AND installation_digest=a#>>'{preparation,installation_digest}' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM generation FROM internal.initial_preparation_backend_eligibility
  WHERE generation=(a#>>'{preparation,backend_generation}')::UUID AND state='eligible'
   AND installation_digest=a#>>'{preparation,backend_installation_digest}' FOR SHARE NOWAIT;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM p.digest FROM internal.initial_cpm_photo_write_policies p
  JOIN internal.initial_cpm_photo_write_attempts w ON w.write_policy_digest=p.digest
  WHERE w.scan_id=p_old.scan_id ORDER BY p.digest FOR SHARE OF p NOWAIT;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts w
  JOIN internal.initial_cpm_photo_write_policies p ON p.digest=w.write_policy_digest
  WHERE w.scan_id=p_old.scan_id AND p.state<>'eligible') THEN
  RAISE EXCEPTION 'initial_analysis_preparation_unavailable' USING ERRCODE='55000'; END IF;
 IF p_new.cpm_verification_snapshot_digest IS DISTINCT FROM encode(extensions.digest(convert_to(
  'merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
END; $$;
REVOKE ALL ON FUNCTION internal.assert_initial_cpm_verification_start(internal.initial_analysis_preparation_intents,internal.initial_analysis_preparation_intents)
 FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the existing intent writer/erasure owner and every legacy branch.
DO $guard$
DECLARE d TEXT; insert_anchor TEXT:='IF TG_OP=''INSERT'' THEN';
 delete_anchor TEXT:='ELSIF TG_OP=''DELETE'' THEN';
BEGIN
 d:=pg_catalog.pg_get_functiondef('internal.guard_initial_preparation_storage()'::REGPROCEDURE);
 IF (length(d)-length(replace(d,insert_anchor,'')))/length(insert_anchor)<>1
  OR (length(d)-length(replace(d,delete_anchor,'')))/length(delete_anchor)<>1 THEN
  RAISE EXCEPTION 'initial preparation storage guard source drift'; END IF;
 d:=replace(d,insert_anchor,insert_anchor||E'\n'
  ||' IF num_nonnulls(NEW.cpm_verification_attempt_id,NEW.cpm_verification_started_at,NEW.cpm_verification_snapshot_digest)<>0 THEN'
  ||' RAISE EXCEPTION ''initial_analysis_storage_immutable'' USING ERRCODE=''22023''; END IF;');
 d:=replace(d,delete_anchor,'ELSIF TG_OP=''UPDATE'' THEN'
  ||' PERFORM internal.assert_initial_cpm_verification_start(OLD,NEW); RETURN NEW; '||delete_anchor);
 EXECUTE d;
END; $guard$;

CREATE FUNCTION internal.begin_initial_cpm_photo_verification(p_owner UUID,p_scan UUID,p_assignment_digest TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE saved internal.initial_analysis_preparation_intents; proposed internal.initial_analysis_preparation_intents;
 snapshot TEXT; attempt UUID; started TIMESTAMPTZ; digest TEXT;
BEGIN
 PERFORM internal.require_service_role();
 IF p_assignment_digest IS NULL OR p_assignment_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan);
 SELECT * INTO STRICT saved FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
 IF saved.owner_id IS DISTINCT FROM p_owner OR saved.assignment_digest IS DISTINCT FROM p_assignment_digest
  OR saved.canonical_candidate::JSONB->>'variant' IS DISTINCT FROM 'client_prepared_photo' THEN
  RAISE EXCEPTION 'initial_analysis_identity_conflict' USING ERRCODE='22023'; END IF;
 -- A repeated call is recovery-only even after timeout, revocation or process
 -- death. Do not return the original fresh acknowledgement/IO authority again.
 IF saved.cpm_verification_attempt_id IS NOT NULL THEN
  RETURN jsonb_build_object('version',1,'outcome','held','authority','none'); END IF;
 -- Same outer owner/scan scope, then fail-fast capacity before registry/attempt.
 PERFORM internal.lock_initial_cpm_photo_capacity();
 PERFORM scan_id FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=p_scan FOR UPDATE;
 PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
 snapshot:=internal.initial_cpm_verification_start_snapshot(p_owner,p_scan);
 attempt:=pg_catalog.gen_random_uuid(); started:=clock_timestamp();
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.cpm-verification-start.v1'||E'\n'||snapshot,'UTF8'),'sha256'),'hex');
 proposed:=saved; proposed.cpm_verification_attempt_id:=attempt;
 proposed.cpm_verification_started_at:=started; proposed.cpm_verification_snapshot_digest:=digest;
 INSERT INTO internal.initial_cpm_verification_start_context(transaction_id,owner_id,scan_id,attempt_id,old_digest,new_digest)
 VALUES(pg_catalog.pg_current_xact_id(),p_owner,p_scan,attempt,
  internal.initial_cpm_verification_intent_digest(saved),internal.initial_cpm_verification_intent_digest(proposed));
 UPDATE internal.initial_analysis_preparation_intents SET cpm_verification_attempt_id=attempt,
  cpm_verification_started_at=started,cpm_verification_snapshot_digest=digest WHERE scan_id=p_scan;
 IF EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context WHERE transaction_id=pg_catalog.pg_current_xact_id()) THEN
  RAISE EXCEPTION 'initial_analysis_verification_start_incomplete' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('version',1,'outcome','started','attempt_id',attempt,
  'snapshot_canonical',snapshot,'snapshot_digest',digest);
END; $$;
REVOKE ALL ON FUNCTION internal.begin_initial_cpm_photo_verification(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;

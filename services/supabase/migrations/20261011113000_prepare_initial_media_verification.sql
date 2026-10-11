SET lock_timeout='5s';
SET statement_timeout='2min';

-- M2 remains inactive. Preparation is storage authority only; a verification
-- receipt is neither executable-transform attestation nor provider evidence.
CREATE TABLE internal.initial_analysis_media_preparations(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_media_cohorts(scan_id) ON DELETE CASCADE,
 owner_id UUID NOT NULL,
 token UUID NOT NULL,
 issued_at BIGINT NOT NULL CHECK(issued_at>0 AND issued_at<=9007199254740991),
 expires_at BIGINT NOT NULL CHECK(expires_at>issued_at AND expires_at<=issued_at+60000),
 FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE
);
CREATE INDEX initial_media_preparations_owner ON internal.initial_analysis_media_preparations(owner_id,scan_id);
CREATE TABLE internal.initial_analysis_media_verifications(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_media_cohorts(scan_id) ON DELETE CASCADE,
 owner_id UUID NOT NULL,
 receipt JSONB NOT NULL CHECK(jsonb_typeof(receipt)='object' AND octet_length(receipt::TEXT)<=1024),
 FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE
);
CREATE INDEX initial_media_verifications_owner ON internal.initial_analysis_media_verifications(owner_id,scan_id);
ALTER TABLE internal.initial_analysis_media_preparations ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_media_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_media_preparations,internal.initial_analysis_media_verifications FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION internal.guard_initial_media_verification_state() RETURNS TRIGGER
LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' AND TG_TABLE_NAME='initial_analysis_media_preparations' THEN
  IF NEW.scan_id=OLD.scan_id AND NEW.owner_id=OLD.owner_id AND NEW.token<>OLD.token
   AND NEW.issued_at>=OLD.expires_at AND OLD.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT
   AND NEW.expires_at<=(SELECT (binding->>'expires_at')::BIGINT FROM internal.initial_analysis_media_cohorts WHERE scan_id=OLD.scan_id)
   THEN RETURN NEW; END IF;
 ELSIF TG_OP='DELETE' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id AND internal.initial_cancellation_dispatch(state) IS NOT NULL)
   OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id) THEN RETURN OLD; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END;
$$;
CREATE TRIGGER guard_initial_media_preparation BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_preparations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_verification_state();
CREATE TRIGGER guard_initial_media_verification BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_verifications
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_verification_state();

-- Keep the original strict no-provider/no-consumer predicate distinct from
-- expiry retirement, which must now exclude active preparation and receipts.
CREATE FUNCTION internal.initial_media_pending(p_scan UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND state='pending_pre_dispatch')
 AND NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
 AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan);
$$;
CREATE OR REPLACE FUNCTION internal.initial_media_abandonable(p_scan UUID) RETURNS BOOLEAN
LANGUAGE SQL VOLATILE SET search_path='' AS $$
 SELECT internal.initial_media_pending(p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan
  AND expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT);
$$;
CREATE FUNCTION internal.lock_initial_media_binding(p_owner UUID,p_scan UUID,p_digest TEXT,p_manifest TEXT) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding JSONB;
BEGIN
 IF p_manifest IS NULL OR p_manifest !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_initial_media_scope(p_owner,p_scan,p_digest);
 SELECT c.binding INTO binding FROM internal.initial_analysis_media_cohorts c WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND binding->>'manifest_digest' IS DISTINCT FROM p_manifest THEN
  RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
 RETURN binding;
END;
$$;
CREATE FUNCTION internal.initial_media_verification_action(p_action TEXT,p_owner UUID,p_scan UUID,p_digest TEXT,p_manifest TEXT,p_token UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding JSONB; receipt JSONB; claim internal.initial_analysis_media_preparations;
 issued BIGINT; deadline BIGINT; object internal.initial_analysis_media_registry; expected_count INTEGER;
BEGIN
 IF p_action NOT IN ('claim','settle','read') OR p_action IS NULL OR (p_action='settle' AND p_token IS NULL) THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_initial_media_binding(p_owner,p_scan,p_digest,p_manifest);
 IF binding IS NULL THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 SELECT * INTO claim FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
 SELECT v.receipt INTO receipt FROM internal.initial_analysis_media_verifications v WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN RETURN jsonb_build_object('version',1,'outcome','replay','receipt',receipt); END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan AND state='retired') THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','retired'); END IF;
 IF p_action='read' THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 IF NOT internal.initial_media_pending(p_scan) THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','in_use'); END IF;
 -- All registry locks follow the outer lifecycle and private locks. Cleanup
 -- touches retired rows only; it never takes an outer lock in reverse order.
 expected_count:=0;
 FOR object IN SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  IF object.retired THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','retired'); END IF;
  IF object.backend_generation::TEXT IS DISTINCT FROM binding->>'backend_generation'
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(binding->'items') item
    CROSS JOIN LATERAL (VALUES(item->'source'),(item->'prepared')) AS roles(role) WHERE role->>'object_id'=object.object_id::TEXT) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  expected_count:=expected_count+1;
 END LOOP;
 IF expected_count<>(SELECT count(DISTINCT role->>'object_id') FROM jsonb_array_elements(binding->'items') item
  CROSS JOIN LATERAL (VALUES(item->'source'),(item->'prepared')) AS roles(role) WHERE role<>'null'::JSONB) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 IF p_action='claim' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled) THEN
   RETURN jsonb_build_object('version',1,'outcome','held','reason','disabled'); END IF;
  issued:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT;
  deadline:=least(issued+60000,(binding->>'expires_at')::BIGINT);
  IF deadline<=issued THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','expired'); END IF;
  IF claim.expires_at>issued THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','busy'); END IF;
  INSERT INTO internal.initial_analysis_media_preparations(scan_id,owner_id,token,issued_at,expires_at)
   VALUES(p_scan,p_owner,gen_random_uuid(),issued,deadline)
   ON CONFLICT(scan_id) DO UPDATE SET token=EXCLUDED.token,issued_at=EXCLUDED.issued_at,expires_at=EXCLUDED.expires_at RETURNING * INTO claim;
  RETURN jsonb_build_object('version',1,'outcome','claimed','binding',binding,'claim',jsonb_build_object('token',claim.token,'issued_at',claim.issued_at,'expires_at',claim.expires_at));
 END IF;
 IF claim.token IS DISTINCT FROM p_token OR claim.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','stale'); END IF;
 -- A token alone is not durable proof of verification before expiry. Only a
 -- current claim inserts; an existing exact receipt already returned above.
 receipt:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,'submission_digest',p_digest,
  'manifest_digest',p_manifest,'backend_generation',binding->'backend_generation',
  'verified_at',floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT);
 INSERT INTO internal.initial_analysis_media_verifications(scan_id,owner_id,receipt) VALUES(p_scan,p_owner,receipt);
 RETURN jsonb_build_object('version',1,'outcome','verified','receipt',receipt);
END;
$$;
CREATE FUNCTION public.claim_initial_media_preparation(p_owner UUID,p_scan UUID,p_submission_digest TEXT,p_manifest_digest TEXT) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.initial_media_verification_action('claim',p_owner,p_scan,p_submission_digest,p_manifest_digest);
END;
$$;
CREATE FUNCTION public.settle_initial_media_verification(p_owner UUID,p_scan UUID,p_submission_digest TEXT,p_manifest_digest TEXT,p_preparation_token UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.initial_media_verification_action('settle',p_owner,p_scan,p_submission_digest,p_manifest_digest,p_preparation_token);
END;
$$;
CREATE FUNCTION public.get_initial_media_verification(p_owner UUID,p_scan UUID,p_submission_digest TEXT,p_manifest_digest TEXT) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 RETURN internal.initial_media_verification_action('read',p_owner,p_scan,p_submission_digest,p_manifest_digest);
END;
$$;
CREATE FUNCTION public.get_initial_media_backend(p_generation UUID) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE backend internal.initial_analysis_media_backends;
BEGIN
 PERFORM internal.require_service_role();
 IF p_generation IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 SELECT * INTO backend FROM internal.initial_analysis_media_backends WHERE generation=p_generation;
 IF NOT FOUND THEN RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 RETURN jsonb_build_object('version',1,'outcome','resolved','backend',to_jsonb(backend));
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_media_verification_state(),internal.initial_media_pending(UUID),internal.lock_initial_media_binding(UUID,UUID,TEXT,TEXT),
 internal.initial_media_verification_action(TEXT,UUID,UUID,TEXT,TEXT,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.claim_initial_media_preparation(UUID,UUID,TEXT,TEXT),public.settle_initial_media_verification(UUID,UUID,TEXT,TEXT,UUID),
 public.get_initial_media_verification(UUID,UUID,TEXT,TEXT),public.get_initial_media_backend(UUID) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_initial_media_preparation(UUID,UUID,TEXT,TEXT),public.settle_initial_media_verification(UUID,UUID,TEXT,TEXT,UUID),
 public.get_initial_media_verification(UUID,UUID,TEXT,TEXT),public.get_initial_media_backend(UUID) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.claim_initial_media_preparation(uuid,uuid,text,text)','Inactive original cohort storage preparation; never provider permission'),
 ('service_role','public.settle_initial_media_verification(uuid,uuid,text,text,uuid)','Record original all-items retained byte verification only'),
 ('service_role','public.get_initial_media_verification(uuid,uuid,text,text)','Exact private retained verification recovery only'),
 ('service_role','public.get_initial_media_backend(uuid)','Read original immutable nonsecret backend configuration only');
RESET lock_timeout;
RESET statement_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

-- M1 is allocation/retirement metadata only. No installed writer, verified
-- bytes, binding/dispatch permission or actual backend profile is provided.
CREATE TABLE internal.initial_analysis_media_backends(
 generation UUID PRIMARY KEY,
 provider TEXT NOT NULL CHECK(provider='r2'),
 direct_endpoint TEXT NOT NULL CHECK(direct_endpoint ~ '^https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com$'),
 private_bucket TEXT NOT NULL CHECK(private_bucket ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'),
 namespace TEXT NOT NULL CHECK(namespace='initial-analysis/v1'),
 credential_profile TEXT NOT NULL CHECK(credential_profile ~ '^[a-z][a-z0-9_]{0,63}$')
);
CREATE TRIGGER guard_initial_media_backend BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_backends
 FOR EACH ROW EXECUTE FUNCTION internal.reject_initial_permanent_mutation();
ALTER TABLE internal.initial_analysis_rollout ADD COLUMN media_backend_generation UUID
 REFERENCES internal.initial_analysis_media_backends(generation);
CREATE TABLE internal.initial_analysis_media_allocation_fences(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_operation_fences(scan_id),
 state TEXT NOT NULL CHECK(state IN ('allocated','retired'))
);
CREATE TABLE internal.initial_analysis_media_registry(
 object_id UUID PRIMARY KEY,
 scan_id UUID NOT NULL REFERENCES internal.initial_analysis_media_allocation_fences(scan_id),
 backend_generation UUID NOT NULL REFERENCES internal.initial_analysis_media_backends(generation),
 retired BOOLEAN NOT NULL DEFAULT FALSE,
 marker_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
 claim_token UUID,
 claim_expires_at TIMESTAMPTZ,
 CHECK((claim_token IS NULL)=(claim_expires_at IS NULL)),
 CHECK(retired OR (NOT marker_confirmed AND claim_token IS NULL)),
 CHECK(NOT marker_confirmed OR claim_token IS NULL)
);
CREATE INDEX initial_media_registry_operation ON internal.initial_analysis_media_registry(scan_id,object_id);
CREATE INDEX initial_media_registry_backend ON internal.initial_analysis_media_registry(backend_generation);
CREATE INDEX initial_media_registry_cleanup ON internal.initial_analysis_media_registry(claim_expires_at,object_id)
 WHERE retired AND NOT marker_confirmed;
CREATE TABLE internal.initial_analysis_media_cohorts(
 scan_id UUID PRIMARY KEY REFERENCES internal.initial_analysis_media_allocation_fences(scan_id),
 owner_id UUID NOT NULL,
 binding JSONB NOT NULL CHECK(jsonb_typeof(binding)='object' AND octet_length(binding::TEXT)<=65536),
 FOREIGN KEY(scan_id,owner_id) REFERENCES internal.initial_analysis_submissions(scan_id,owner_id) ON DELETE CASCADE
);
CREATE INDEX initial_media_cohorts_owner ON internal.initial_analysis_media_cohorts(owner_id,scan_id);
ALTER TABLE internal.initial_analysis_media_backends ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_media_allocation_fences ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_media_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.initial_analysis_media_cohorts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.initial_analysis_media_backends,internal.initial_analysis_media_allocation_fences,
 internal.initial_analysis_media_registry,internal.initial_analysis_media_cohorts FROM PUBLIC,anon,authenticated,service_role;
-- Ownership is subordinate to the immutable submission composite FK. Its
-- existing direct-user preserve policy covers this cohort; do not register a
-- nonexistent cohort-to-user FK in the catalog-driven merge policy table.

CREATE FUNCTION internal.guard_initial_media_state() RETURNS TRIGGER
LANGUAGE PLPGSQL SET search_path='' AS $$
BEGIN
 IF TG_OP='UPDATE' THEN
  IF TG_TABLE_NAME='initial_analysis_media_allocation_fences' THEN
   IF NEW.scan_id=OLD.scan_id AND OLD.state='allocated' AND NEW.state='retired' THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME='initial_analysis_media_registry' THEN
   IF NEW.object_id=OLD.object_id AND NEW.scan_id=OLD.scan_id AND NEW.backend_generation=OLD.backend_generation
    AND NEW.retired AND (NOT OLD.marker_confirmed OR NEW.marker_confirmed) THEN RETURN NEW; END IF;
  END IF;
 ELSIF TG_OP='DELETE' AND TG_TABLE_NAME='initial_analysis_media_cohorts' THEN
  IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=OLD.scan_id)
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=OLD.scan_id
    AND internal.initial_cancellation_dispatch(state) IS NOT NULL)
   OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.scan_id) THEN RETURN OLD; END IF;
 END IF;
 RAISE EXCEPTION 'initial_analysis_storage_immutable' USING ERRCODE='22023';
END;
$$;
CREATE TRIGGER guard_initial_media_allocation_fence BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_allocation_fences
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_state();
CREATE TRIGGER guard_initial_media_registry BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_registry
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_state();
CREATE TRIGGER guard_initial_media_cohort BEFORE UPDATE OR DELETE ON internal.initial_analysis_media_cohorts
 FOR EACH ROW EXECUTE FUNCTION internal.guard_initial_media_state();

-- Caller already owns the outer initial lifecycle scope. Registry locks are
-- deterministic; the cleanup owner only ever locks retired registry rows.
CREATE FUNCTION internal.retire_initial_media_objects(p_scan UUID) RETURNS VOID
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE object UUID;
BEGIN
 UPDATE internal.initial_analysis_media_allocation_fences SET state='retired' WHERE scan_id=p_scan AND state='allocated';
 FOR object IN SELECT object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE LOOP
  UPDATE internal.initial_analysis_media_registry SET retired=TRUE WHERE object_id=object AND NOT retired;
 END LOOP;
END;
$$;
CREATE FUNCTION internal.retire_initial_media_on_erasure() RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM internal.retire_initial_media_objects(OLD.scan_id);
 RETURN OLD;
END;
$$;
-- Runs after the existing BEFORE erasure guard. A failed deletion rolls all
-- retirement back; successful private cascade never loses cleanup identity.
CREATE TRIGGER retire_initial_media_on_erasure BEFORE DELETE ON internal.initial_analysis_submissions
 FOR EACH ROW EXECUTE FUNCTION internal.retire_initial_media_on_erasure();

CREATE FUNCTION internal.lock_initial_media_scope(p_owner UUID,p_scan UUID,p_digest TEXT)
RETURNS internal.initial_analysis_submissions
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE submission internal.initial_analysis_submissions; admission internal.initial_analysis_admissions; scan_owner UUID; receipt_owner UUID;
BEGIN
 IF p_owner IS NULL OR p_scan IS NULL OR p_digest IS NULL OR p_digest !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000'; END IF;
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_scan::TEXT,0::BIGINT));
 SELECT user_id INTO scan_owner FROM public.scans WHERE id=p_scan FOR UPDATE;
 IF FOUND AND scan_owner IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
 PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
 SELECT * INTO submission FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND AND submission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT owner_id INTO receipt_owner FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan;
 IF FOUND AND receipt_owner IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_scan)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner AND status IN ('pending','storage_pending','auth_pending')) THEN
  RAISE EXCEPTION 'initial_analysis_deleted' USING ERRCODE='55000'; END IF;
 IF receipt_owner=p_owner OR (submission.owner_id=p_owner AND EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan AND internal.initial_cancellation_dispatch(state) IS NOT NULL)) THEN RAISE EXCEPTION 'initial_analysis_cancelled' USING ERRCODE='55000'; END IF;
 IF submission.scan_id IS NULL THEN RAISE EXCEPTION 'initial_analysis_owner_unavailable' USING ERRCODE='P0002'; END IF;
 SELECT * INTO admission FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND OR admission.owner_id IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 IF admission.submission_digest<>p_digest THEN RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
 IF submission.input_snapshot IS DISTINCT FROM internal.parse_initial_input(admission.canonical_input)
  OR p_digest IS DISTINCT FROM internal.initial_digest('input',admission.canonical_input) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 RETURN submission;
END;
$$;
CREATE FUNCTION internal.initial_media_abandonable(p_scan UUID) RETURNS BOOLEAN
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
CREATE FUNCTION internal.initial_media_response(p_scan UUID,p_binding JSONB,p_outcome TEXT) RETURNS JSONB
LANGUAGE PLPGSQL VOLATILE SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan AND state='retired') THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','retired'); END IF;
 IF (p_binding->>'expires_at')::BIGINT<=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','expired','binding',p_binding); END IF;
 RETURN jsonb_build_object('version',1,'outcome',p_outcome,'binding',p_binding);
END;
$$;

CREATE FUNCTION public.allocate_initial_analysis_media(p_owner UUID,p_scan UUID,p_submission_digest TEXT,p_backend_generation UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE submission internal.initial_analysis_submissions; saved internal.initial_analysis_media_cohorts;
 input JSONB; source_role JSONB; prepared_role JSONB; items JSONB:='[]'::JSONB; binding JSONB;
 source_object UUID; prepared_object UUID; position INTEGER:=0; objects INTEGER:=0; bytes BIGINT:=0; deadline BIGINT;
BEGIN
 PERFORM internal.require_service_role();
 IF p_backend_generation IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 submission:=internal.lock_initial_media_scope(p_owner,p_scan,p_submission_digest);
 SELECT * INTO saved FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 IF FOUND THEN
  IF saved.binding->>'backend_generation' IS DISTINCT FROM p_backend_generation::TEXT THEN
   RAISE EXCEPTION 'initial_analysis_conflict' USING ERRCODE='23505'; END IF;
  RETURN internal.initial_media_response(p_scan,saved.binding,'replay');
 END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan)
  OR NOT internal.initial_media_abandonable(p_scan)
  OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE singleton AND initial_analysis_lifecycle_enabled AND media_backend_generation=p_backend_generation) THEN
  RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.initial_analysis_media_allocation_fences(scan_id,state) VALUES(p_scan,'allocated');
 deadline:=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT+300000;
 FOR input IN SELECT * FROM jsonb_array_elements(submission.input_snapshot->'media') LOOP
  source_object:=gen_random_uuid();
  source_role:=jsonb_build_object('object_id',source_object,'content_type',input->'source_content_type','byte_count',input->'source_byte_count','sha256',input->'source_sha256');
  INSERT INTO internal.initial_analysis_media_registry(object_id,scan_id,backend_generation) VALUES(source_object,p_scan,p_backend_generation);
  objects:=objects+1; bytes:=bytes+(input->>'source_byte_count')::BIGINT;
  prepared_role:=NULL;
  IF input->>'kind'<>'video' THEN
   IF input->'content_type'=input->'source_content_type' AND input->'byte_count'=input->'source_byte_count' AND input->'sha256'=input->'source_sha256' THEN
    prepared_object:=source_object;
   ELSE
    prepared_object:=gen_random_uuid();
    INSERT INTO internal.initial_analysis_media_registry(object_id,scan_id,backend_generation) VALUES(prepared_object,p_scan,p_backend_generation);
    objects:=objects+1; bytes:=bytes+(input->>'byte_count')::BIGINT;
   END IF;
   prepared_role:=jsonb_build_object('object_id',prepared_object,'content_type',input->'content_type','byte_count',input->'byte_count','sha256',input->'sha256');
  END IF;
  items:=items||jsonb_build_array(jsonb_build_object('index',position,'input',input,'source',source_role,'prepared',prepared_role));
  position:=position+1;
 END LOOP;
 IF position>8 OR objects>10 OR bytes>28625792 THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 binding:=jsonb_build_object('version',1,'owner_id',p_owner,'scan_id',p_scan,'submission_digest',p_submission_digest,
  'backend_generation',p_backend_generation,'expires_at',deadline,'items',items);
 binding:=binding||jsonb_build_object('manifest_digest',encode(extensions.digest(convert_to(E'merian.initial-analysis.media-allocation.v1\n'||internal.initial_canonical(binding),'UTF8'),'sha256'),'hex'));
 INSERT INTO internal.initial_analysis_media_cohorts(scan_id,owner_id,binding) VALUES(p_scan,p_owner,binding);
 RETURN internal.initial_media_response(p_scan,binding,'allocated');
END;
$$;
CREATE FUNCTION public.get_initial_analysis_media(p_owner UUID,p_scan UUID,p_submission_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_analysis_media_cohorts;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_media_scope(p_owner,p_scan,p_submission_digest);
 SELECT * INTO saved FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 RETURN internal.initial_media_response(p_scan,saved.binding,'replay');
END;
$$;
CREATE FUNCTION public.retire_initial_analysis_media(p_owner UUID,p_scan UUID,p_submission_digest TEXT)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE saved internal.initial_analysis_media_cohorts;
BEGIN
 PERFORM internal.require_service_role();
 PERFORM internal.lock_initial_media_scope(p_owner,p_scan,p_submission_digest);
 SELECT * INTO saved FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
 IF NOT FOUND THEN
  IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan) THEN
   RAISE EXCEPTION 'initial_analysis_unavailable' USING ERRCODE='55000'; END IF;
  RETURN jsonb_build_object('version',1,'outcome','held','reason','missing'); END IF;
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan AND state='retired') THEN
  RETURN jsonb_build_object('version',1,'outcome','retired'); END IF;
 IF NOT internal.initial_media_abandonable(p_scan) THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','in_use'); END IF;
 IF (saved.binding->>'expires_at')::BIGINT>floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT THEN
  RETURN jsonb_build_object('version',1,'outcome','held','reason','not_expired'); END IF;
 PERFORM internal.retire_initial_media_objects(p_scan);
 RETURN jsonb_build_object('version',1,'outcome','retired');
END;
$$;
CREATE FUNCTION public.claim_initial_analysis_media_erasure() RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE object internal.initial_analysis_media_registry;
BEGIN
 PERFORM internal.require_service_role();
 SELECT * INTO object FROM internal.initial_analysis_media_registry WHERE retired AND NOT marker_confirmed
  AND (claim_expires_at IS NULL OR claim_expires_at<=clock_timestamp()) ORDER BY object_id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('version',1,'outcome','empty'); END IF;
 UPDATE internal.initial_analysis_media_registry SET claim_token=gen_random_uuid(),claim_expires_at=clock_timestamp()+interval '1 minute'
 WHERE object_id=object.object_id RETURNING * INTO object;
 RETURN jsonb_build_object('version',1,'outcome','claimed','object',jsonb_build_object('scan_id',object.scan_id,'object_id',object.object_id,
  'backend_generation',object.backend_generation,'claim_token',object.claim_token,'claim_expires_at',floor(extract(epoch FROM object.claim_expires_at)*1000)::BIGINT));
END;
$$;
CREATE FUNCTION public.finish_initial_analysis_media_erasure(p_object UUID,p_claim UUID,p_success BOOLEAN) RETURNS JSONB
LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
BEGIN
 PERFORM internal.require_service_role();
 IF p_object IS NULL OR p_claim IS NULL OR p_success IS NULL THEN RAISE EXCEPTION 'initial_analysis_input_invalid' USING ERRCODE='22023'; END IF;
 UPDATE internal.initial_analysis_media_registry SET marker_confirmed=p_success,claim_token=NULL,claim_expires_at=NULL
 WHERE object_id=p_object AND retired AND NOT marker_confirmed AND claim_token=p_claim AND claim_expires_at>clock_timestamp();
 RETURN jsonb_build_object('version',1,'outcome',CASE WHEN FOUND THEN 'acknowledged' ELSE 'stale' END);
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_initial_media_state(),internal.retire_initial_media_objects(UUID),internal.retire_initial_media_on_erasure(),
 internal.lock_initial_media_scope(UUID,UUID,TEXT),internal.initial_media_abandonable(UUID),internal.initial_media_response(UUID,JSONB,TEXT)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.allocate_initial_analysis_media(UUID,UUID,TEXT,UUID),public.get_initial_analysis_media(UUID,UUID,TEXT),
 public.retire_initial_analysis_media(UUID,UUID,TEXT),public.claim_initial_analysis_media_erasure(),public.finish_initial_analysis_media_erasure(UUID,UUID,BOOLEAN)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_initial_analysis_media(UUID,UUID,TEXT,UUID),public.get_initial_analysis_media(UUID,UUID,TEXT),
 public.retire_initial_analysis_media(UUID,UUID,TEXT),public.claim_initial_analysis_media_erasure(),public.finish_initial_analysis_media_erasure(UUID,UUID,BOOLEAN) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.allocate_initial_analysis_media(uuid,uuid,text,uuid)','Inactive exact initial media cohort; no upload or dispatch authority'),
 ('service_role','public.get_initial_analysis_media(uuid,uuid,text)','Exact initial media metadata recovery; no allocation or invocation'),
 ('service_role','public.retire_initial_analysis_media(uuid,uuid,text)','Pending expired initial media cohort retirement; no funding settlement'),
 ('service_role','public.claim_initial_analysis_media_erasure()','Claim only permanently retired original media destination'),
 ('service_role','public.finish_initial_analysis_media_erasure(uuid,uuid,boolean)','Acknowledge current original media cleanup claim only');

RESET lock_timeout;
RESET statement_timeout;

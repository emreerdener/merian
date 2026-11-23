SET lock_timeout='5s';
SET statement_timeout='2min';

-- Existing private evidence has no durable proof that a primary call never
-- happened (invocation records may already have been pruned). Hold it rather
-- than backfill a guessed unused permit. Newly retained evidence opts in once.
ALTER TABLE internal.ordinary_initial_evidence
 ADD COLUMN primary_dispatch_fence_version INTEGER NOT NULL DEFAULT 0
 CHECK(primary_dispatch_fence_version IN (0,1));
ALTER TABLE internal.ordinary_initial_evidence ALTER COLUMN primary_dispatch_fence_version SET DEFAULT 1;

-- One primary permit per logical capture, across every quota attempt. Only
-- evidence erasure cascades this receipt; quota/invocation pruning cannot.
CREATE TABLE internal.private_capture_primary_dispatch (
 scan_id UUID PRIMARY KEY REFERENCES internal.ordinary_initial_evidence(scan_id) ON DELETE CASCADE,
 owner_id UUID NOT NULL,
 generation UUID NOT NULL UNIQUE,
 job_id UUID NOT NULL,
 evidence_digest TEXT NOT NULL CHECK(evidence_digest ~ '^[0-9a-f]{64}$'),
 payload_checksum TEXT NOT NULL CHECK(payload_checksum ~ '^[0-9a-f]{64}$'),
 request_sha256 TEXT NOT NULL CHECK(request_sha256 ~ '^[0-9a-f]{64}$'),
 reservation_id UUID NOT NULL,
 attempt_count INTEGER NOT NULL CHECK(attempt_count>0),
 lease_sha256 TEXT NOT NULL CHECK(lease_sha256 ~ '^[0-9a-f]{64}$'),
 invocation_id UUID NOT NULL UNIQUE,
 assignment JSONB NOT NULL,
 provenance JSONB NOT NULL,
 dispatch_transaction XID8 NOT NULL,
 permitted_at TIMESTAMPTZ NOT NULL
);
ALTER TABLE internal.private_capture_primary_dispatch ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.private_capture_primary_dispatch FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX private_capture_primary_dispatch_reservation ON internal.private_capture_primary_dispatch(reservation_id);

-- Called before the generic invocation owner acquires user/reservation locks.
-- Classification is server-retained; request flags cannot opt out. A changed
-- classification is checked again at the actual invocation insert.
CREATE FUNCTION internal.lock_private_capture_dispatch(p_reservation UUID,p_owner UUID)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE scan UUID; evidence internal.ordinary_initial_evidence;
 job public.scan_ingestion_jobs; intent public.scan_ingestion_intents;
 witness internal.capture_source_admissions; contract JSONB; receipt JSONB;
 artifacts JSONB; expected JSONB;
BEGIN
 SELECT q.original_analysis_id INTO scan FROM internal.ai_quota_reservations q WHERE q.id=p_reservation;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=scan)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=scan AND (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM p_owner)) THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=scan AND private_capture_request_sha256 IS NOT NULL) THEN
  IF EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=scan AND recovery->>'kind'='private_capture_stage_v1')
   OR EXISTS(SELECT 1 FROM internal.private_capture_primary_dispatch WHERE scan_id=scan) THEN
   RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
  RETURN NULL;
 END IF;
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-capture-account-retirement:'||p_owner::TEXT,0));
 PERFORM id FROM public.users WHERE id=p_owner FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0));
 SELECT * INTO evidence FROM internal.ordinary_initial_evidence WHERE scan_id=scan FOR UPDATE;
 IF NOT FOUND OR evidence.owner_id IS DISTINCT FROM p_owner OR evidence.private_capture_request_sha256 IS NULL
  OR evidence.primary_dispatch_fence_version IS DISTINCT FROM 1
  OR evidence.evidence_manifest->'schema_version' IS DISTINCT FROM '9'::JSONB
  OR evidence.allocated_at IS NULL OR evidence.retired_at IS NOT NULL OR evidence.sealed_at IS NOT NULL
  OR evidence.accepted_result IS NOT NULL
  OR EXISTS(SELECT 1 FROM internal.private_capture_primary_dispatch WHERE scan_id=scan)
  OR EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=p_owner)
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=scan)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=scan)
  OR EXISTS(SELECT 1 FROM public.scans WHERE id=scan)
  OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=p_reservation AND user_id=p_owner AND original_analysis_id=scan) THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO job FROM public.scan_ingestion_jobs WHERE scan_id=scan::TEXT AND user_id=p_owner FOR UPDATE;
 SELECT * INTO intent FROM public.scan_ingestion_intents WHERE scan_id=scan::TEXT AND user_id=p_owner FOR UPDATE;
 SELECT * INTO witness FROM internal.capture_source_admissions WHERE scan_id=scan AND owner_id=p_owner FOR UPDATE;
 IF job.id IS NULL OR intent.scan_id IS NULL OR witness.scan_id IS NULL
  OR job.status IN ('complete','failed_terminal') OR job.endpoint IS DISTINCT FROM 'identify-multimodal'
  OR intent.payload_schema_version IS DISTINCT FROM 4 OR intent.request_payload->'schemaVersion' IS DISTINCT FROM '4'::JSONB
  OR witness.retired_at IS NOT NULL OR witness.recovery->>'kind' IS DISTINCT FROM 'private_capture_stage_v1'
  OR intent.request_payload IS DISTINCT FROM witness.recovery#>'{intent,request_payload}'
  OR intent.payload_checksum IS DISTINCT FROM witness.recovery#>>'{intent,payload_checksum}'
  OR evidence.payload_checksum IS DISTINCT FROM intent.payload_checksum
  OR evidence.job_id IS DISTINCT FROM job.id OR evidence.generation IS DISTINCT FROM job.initial_evidence_generation
  OR intent.request_payload#>>'{privateCaptureStage,requestSHA256}' IS DISTINCT FROM evidence.private_capture_request_sha256
  OR job.media_counts IS DISTINCT FROM internal.private_capture_media_counts(evidence.evidence_manifest)
  OR intent.media_counts IS DISTINCT FROM job.media_counts
  OR job.media_object_keys IS DISTINCT FROM '{"image":[],"audio":[],"video":[]}'::JSONB
  OR intent.media_object_keys IS DISTINCT FROM job.media_object_keys
  OR job.upload_session_ids IS DISTINCT FROM '{}'::UUID[] OR intent.upload_session_ids IS DISTINCT FROM '{}'::UUID[] THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 expected:=jsonb_build_object('schema_version',1,'scan_id',scan,'generation',evidence.generation,
  'evidence_digest',evidence.evidence_digest,'evidence_manifest',evidence.evidence_manifest);
 IF intent.request_payload->'initialEvidence' IS DISTINCT FROM expected
  OR intent.request_payload#>'{privateCaptureStage,generation}' IS DISTINCT FROM to_jsonb(evidence.generation) THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 contract:=internal.initial_evidence_contract(evidence.evidence_manifest,scan::TEXT,evidence.generation::TEXT);
 receipt:=internal.ordinary_initial_evidence_receipt(evidence);
 SELECT COALESCE(jsonb_agg(x-'object_id'-'ready' ORDER BY n),'[]'::JSONB) INTO artifacts
  FROM jsonb_array_elements(receipt->'items') WITH ORDINALITY AS items(x,n);
 IF contract->>'evidence_digest' IS DISTINCT FROM evidence.evidence_digest OR artifacts IS DISTINCT FROM contract->'items'
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(receipt->'items') x WHERE x->'ready' IS DISTINCT FROM 'true'::JSONB) THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('scan_id',scan,'owner_id',p_owner,'generation',evidence.generation,
  'job_id',job.id,'evidence_digest',evidence.evidence_digest,'payload_checksum',evidence.payload_checksum,
  'request_sha256',evidence.private_capture_request_sha256);
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_private_capture_dispatch(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.record_private_capture_dispatch(p_input JSONB,p_invocation internal.identification_invocations,p_assignment internal.identification_provider_attempts)
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF p_input IS NULL THEN
  IF EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_invocation.scan_id AND private_capture_request_sha256 IS NOT NULL)
   OR EXISTS(SELECT 1 FROM internal.private_capture_primary_dispatch WHERE scan_id=p_invocation.scan_id)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=p_invocation.scan_id)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=p_invocation.scan_id AND
    (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM p_invocation.user_id OR recovery->>'kind'='private_capture_stage_v1')) THEN
   RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
  RETURN;
 END IF;
 IF p_input->>'scan_id' IS DISTINCT FROM p_invocation.scan_id::TEXT
  OR p_input->>'owner_id' IS DISTINCT FROM p_invocation.user_id::TEXT
  OR p_assignment.reservation_id IS DISTINCT FROM p_invocation.reservation_id
  OR p_assignment.attempt_count IS DISTINCT FROM p_invocation.attempt_count THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
 INSERT INTO internal.private_capture_primary_dispatch(scan_id,owner_id,generation,job_id,evidence_digest,payload_checksum,request_sha256,
  reservation_id,attempt_count,lease_sha256,invocation_id,assignment,provenance,dispatch_transaction,permitted_at)
 VALUES(p_invocation.scan_id,p_invocation.user_id,(p_input->>'generation')::UUID,(p_input->>'job_id')::UUID,
  p_input->>'evidence_digest',p_input->>'payload_checksum',p_input->>'request_sha256',p_invocation.reservation_id,
  p_invocation.attempt_count,p_invocation.lease_sha256,p_invocation.id,to_jsonb(p_assignment),p_invocation.provenance,pg_current_xact_id(),p_invocation.occurred_at);
END;
$$;
REVOKE ALL ON FUNCTION internal.record_private_capture_dispatch(JSONB,internal.identification_invocations,internal.identification_provider_attempts) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_private_capture_dispatch()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
BEGIN
 RAISE EXCEPTION 'private_capture_dispatch_immutable' USING ERRCODE='55000';
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_private_capture_dispatch() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_private_capture_dispatch BEFORE UPDATE ON internal.private_capture_primary_dispatch
 FOR EACH ROW EXECUTE FUNCTION internal.guard_private_capture_dispatch();

CREATE FUNCTION internal.guard_private_capture_quota_state()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE permit internal.private_capture_primary_dispatch; scan UUID; known BOOLEAN;
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'reserved' AND (
   EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id IN (NEW.original_analysis_id,NEW.request_id) AND private_capture_request_sha256 IS NOT NULL)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id IN (NEW.original_analysis_id,NEW.request_id))
   OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id IN (NEW.original_analysis_id,NEW.request_id) AND
    (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM NEW.user_id OR recovery->>'kind'='private_capture_stage_v1'))) THEN
   RAISE EXCEPTION 'private_capture_dispatch_required' USING ERRCODE='55000'; END IF;
  RETURN NEW;
 END IF;
 known:=EXISTS(SELECT 1 FROM internal.private_capture_primary_dispatch WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id,NEW.original_analysis_id,NEW.request_id))
  OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id,NEW.original_analysis_id,NEW.request_id) AND private_capture_request_sha256 IS NOT NULL)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id,NEW.original_analysis_id,NEW.request_id))
  OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id,NEW.original_analysis_id,NEW.request_id) AND
   (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM NEW.user_id OR recovery->>'kind'='private_capture_stage_v1'));
 IF known AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.user_id IS DISTINCT FROM OLD.user_id
  OR NEW.original_analysis_id IS DISTINCT FROM OLD.original_analysis_id OR NEW.request_id IS DISTINCT FROM OLD.request_id
  OR NEW.operation IS DISTINCT FROM OLD.operation) THEN
  RAISE EXCEPTION 'private_capture_dispatch_immutable' USING ERRCODE='55000'; END IF;
 IF NEW.state IS NOT DISTINCT FROM OLD.state THEN RETURN NEW; END IF;
 scan:=OLD.original_analysis_id;
 IF OLD.operation='scan_identification' AND scan IS NOT NULL THEN
  -- Generic callers already hold a quota row. Never wait backwards on the
  -- source-admission/dispatch scan lock; contention holds rather than deadlocks.
  IF NOT pg_try_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||scan::TEXT,0)) THEN
   RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
  -- Refresh classification after the lock, including a witness inserted while
  -- this writer was acquiring its quota row. Never trust the pre-lock snapshot.
  known:=known OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id) AND private_capture_request_sha256 IS NOT NULL)
   OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id))
   OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id IN (OLD.original_analysis_id,OLD.request_id) AND
    (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM OLD.user_id OR recovery->>'kind'='private_capture_stage_v1'));
  SELECT * INTO permit FROM internal.private_capture_primary_dispatch WHERE scan_id=scan;
  IF permit.scan_id IS NOT NULL THEN
   IF OLD.state='reserved' AND NEW.state='committed' AND permit.reservation_id=OLD.id
    AND permit.owner_id=OLD.user_id AND permit.attempt_count=OLD.attempt_count
    AND permit.lease_sha256=encode(extensions.digest(OLD.lease_token::TEXT,'sha256'),'hex')
    AND permit.dispatch_transaction=pg_current_xact_id() THEN RETURN NEW; END IF;
   RAISE EXCEPTION 'private_capture_dispatch_consumed' USING ERRCODE='55000';
  END IF;
  IF NEW.state='committed' AND known THEN
   RAISE EXCEPTION 'private_capture_dispatch_required' USING ERRCODE='55000'; END IF;
 END IF;
 IF known AND NEW.state='committed' THEN
  RAISE EXCEPTION 'private_capture_dispatch_required' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_private_capture_quota_state() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_private_capture_quota_state BEFORE INSERT OR UPDATE ON internal.ai_quota_reservations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_private_capture_quota_state();

CREATE FUNCTION internal.guard_private_capture_invocation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path='' AS $$
DECLARE permit internal.private_capture_primary_dispatch;
BEGIN
 SELECT * INTO permit FROM internal.private_capture_primary_dispatch WHERE scan_id=NEW.scan_id;
 IF permit.scan_id IS NOT NULL THEN
  IF permit.dispatch_transaction=pg_current_xact_id() AND permit.invocation_id=NEW.id
   AND permit.reservation_id=NEW.reservation_id AND permit.attempt_count=NEW.attempt_count
   AND permit.owner_id=NEW.user_id AND permit.lease_sha256=NEW.lease_sha256
   AND permit.provenance=NEW.provenance THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'private_capture_dispatch_required' USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=NEW.scan_id AND private_capture_request_sha256 IS NOT NULL)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admission_stops WHERE scan_id=NEW.scan_id)
  OR EXISTS(SELECT 1 FROM internal.capture_source_admissions WHERE scan_id=NEW.scan_id AND
   (retired_at IS NOT NULL OR owner_id IS DISTINCT FROM NEW.user_id OR recovery->>'kind'='private_capture_stage_v1')) THEN
  RAISE EXCEPTION 'private_capture_dispatch_required' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_private_capture_invocation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_private_capture_invocation BEFORE INSERT ON internal.identification_invocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_private_capture_invocation();

-- Preserve the generic owner's validated assignment, provenance and quota
-- commit; insert the permanent receipt in that same transaction before permit.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)'::regprocedure);
 anchor:='    initial_dispatch BOOLEAN;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_dispatch_declaration_drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n    private_capture_input JSONB;');
 anchor:='    PERFORM internal.require_service_role();';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_dispatch_lock_drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n    private_capture_input:=internal.lock_private_capture_dispatch(p_reservation_id,p_user_id);');
 anchor:='    IF initial_dispatch OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_dispatch_insert_drift'; END IF;
 EXECUTE replace(definition,anchor,E'    PERFORM internal.record_private_capture_dispatch(private_capture_input,invocation,assigned);\n'||anchor);
 definition:=pg_get_functiondef('internal.prepare_private_capture_stage_admission(uuid,uuid,text,jsonb,jsonb,jsonb,text[],boolean,boolean,jsonb,integer)'::regprocedure);
 anchor:=' SELECT * INTO stage FROM internal.initial_capture_audio_stages WHERE scan_id=p_scan FOR UPDATE;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_dispatch_admission_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
 -- The admission transaction holds the same scan fence as generic quota
 -- commitment. Work committed before private classification cannot acquire a
 -- fresh V9 permit merely by adding evidence afterward.
 IF EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE p_scan IN (original_analysis_id,request_id) AND state IN ('committed','failed'))
  OR EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan) THEN
  RAISE EXCEPTION 'private_capture_dispatch_unavailable' USING ERRCODE='55000'; END IF;
$body$||anchor);
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;

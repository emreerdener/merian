SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN video_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Raw provenance inventory remains immutable in the original cohort. This
-- separate retained allocation survives receipt cleanup and forbids new keys.
CREATE TABLE internal.observation_video_evidence_allocations (
 analysis_id UUID PRIMARY KEY REFERENCES internal.observation_video_evidence_upload_cohorts(analysis_id) ON DELETE CASCADE,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 items JSONB NOT NULL CHECK(jsonb_typeof(items)='array' AND jsonb_array_length(items) BETWEEN 6 AND 7 AND octet_length(items::TEXT)<=8192),
 expires_at TIMESTAMPTZ NOT NULL,
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_video_evidence_allocations_due ON internal.observation_video_evidence_allocations(expires_at,analysis_id);
CREATE INDEX observation_video_evidence_allocations_parent ON internal.observation_video_evidence_allocations(observation_id);
ALTER TABLE internal.observation_video_evidence_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_video_evidence_allocations FROM PUBLIC,anon,authenticated,service_role;

-- Preserve all execution/funding/legacy namespace fences. Only private video
-- allocation/completion may inspect its own media rows without treating them as execution.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.observation_video_source_preexecution_clear(uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=' AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed video preexecution fence changed'; END IF;
 EXECUTE replace(replace(definition,'internal.observation_video_source_preexecution_clear(', 'internal.observation_video_evidence_execution_clear('),anchor,'');
 EXECUTE replace(definition,anchor,anchor||E'\n AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations WHERE analysis_id=p_analysis)');
END;
$patch$;
REVOKE ALL ON FUNCTION internal.observation_video_evidence_execution_clear(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.lock_video_evidence_request(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS internal.observation_analysis_source_bindings LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; observation UUID; child UUID;
BEGIN
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 12 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>4096
  OR NOT(p_request ?& ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','request_digest','fingerprint_version','fingerprint','items'])
  OR p_request-ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','request_digest','fingerprint_version','fingerprint','items']<>'{}'
  OR jsonb_typeof(p_request->'observation_id') IS DISTINCT FROM 'string'
  OR p_request->>'observation_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR jsonb_typeof(p_request->'analysis_id') IS DISTINCT FROM 'string'
  OR p_request->>'analysis_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 observation:=(p_request->>'observation_id')::UUID; child:=(p_request->>'analysis_id')::UUID;
 PERFORM internal.lock_owned_observation_evidence(p_owner,observation);
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=child;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_owned_observation_video_source_binding(p_owner,observation,child,binding.input_snapshot);
 IF p_request IS DISTINCT FROM internal.observation_video_source_identity(binding)||jsonb_build_object('items',internal.observation_video_source_cohort_items(binding.input_snapshot))
  OR NOT internal.observation_video_evidence_execution_clear(child) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN binding;
END;
$$;
REVOKE ALL ON FUNCTION internal.lock_video_evidence_request(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_video_evidence_allocation()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; cohort internal.observation_video_evidence_upload_cohorts;
 item JSONB; raw JSONB:='[]'::JSONB; seen UUID[]; object UUID;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_evidence_immutable' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
   AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN OLD;
 END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_owned_observation_video_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 SELECT * INTO cohort FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND OR cohort.owner_id IS DISTINCT FROM NEW.owner_id OR cohort.observation_id IS DISTINCT FROM NEW.observation_id
  OR cohort.source_analysis_id IS DISTINCT FROM NEW.source_analysis_id
  OR cohort.items IS DISTINCT FROM internal.observation_video_source_cohort_items(binding.input_snapshot)
  OR NOT internal.observation_video_source_preexecution_clear(NEW.analysis_id)
  OR (SELECT media_enabled AND video_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
  OR NOT isfinite(NEW.expires_at) OR NEW.expires_at IS DISTINCT FROM date_trunc('milliseconds',NEW.expires_at)
  OR NEW.expires_at<=clock_timestamp() OR NEW.expires_at>clock_timestamp()+INTERVAL '5 minutes' THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 seen:=ARRAY[NEW.owner_id,NEW.observation_id,NEW.source_analysis_id,NEW.analysis_id]||ARRAY(SELECT (value->>'media_id')::UUID FROM jsonb_array_elements(cohort.items));
 FOR item IN SELECT value FROM jsonb_array_elements(NEW.items) LOOP
  IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR jsonb_typeof(item->'object_id') IS DISTINCT FROM 'string'
   OR item->>'object_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
  object:=(item->>'object_id')::UUID;
  IF object=ANY(seen) OR EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=object)
   OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=object) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  seen:=array_append(seen,object); raw:=raw||jsonb_build_array(item-'object_id');
 END LOOP;
 IF raw IS DISTINCT FROM cohort.items THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_video_evidence_allocation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_video_evidence_allocation BEFORE INSERT OR UPDATE OR DELETE ON internal.observation_video_evidence_allocations
 FOR EACH ROW EXECUTE FUNCTION internal.guard_video_evidence_allocation();

-- All V4 rows must match the retained allocation; no legacy primitive may mint
-- an unallocated object. This trigger runs before the legacy receipt guard.
CREATE FUNCTION internal.guard_video_evidence_object()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; allocation internal.observation_video_evidence_allocations; item JSONB;
BEGIN
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND OR binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB THEN RETURN NEW; END IF;
 binding:=internal.lock_owned_observation_video_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations WHERE analysis_id=NEW.analysis_id;
 SELECT value INTO item FROM jsonb_array_elements(allocation.items) WHERE value->>'media_id'=NEW.media_id::TEXT;
 IF allocation.analysis_id IS NULL OR item IS NULL OR allocation.owner_id IS DISTINCT FROM NEW.owner_id
  OR allocation.observation_id IS DISTINCT FROM NEW.observation_id OR allocation.expires_at<=clock_timestamp()
  OR item->>'object_id' IS DISTINCT FROM NEW.object_id::TEXT OR item->>'content_type' IS DISTINCT FROM NEW.content_type
  OR (item->>'byte_count')::INTEGER IS DISTINCT FROM NEW.byte_count OR item->>'sha256' IS DISTINCT FROM NEW.sha256
  OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=NEW.object_id)
  OR NOT internal.observation_video_evidence_execution_clear(NEW.analysis_id)
  OR (SELECT media_enabled AND video_evidence_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
  OR (TG_OP='INSERT' AND NEW.ready_at IS NOT NULL)
  OR (TG_OP='UPDATE' AND (NEW.ready_at IS NULL OR NEW.ready_at>=allocation.expires_at OR NEW.ready_at IS DISTINCT FROM date_trunc('milliseconds',NEW.ready_at))) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='INSERT' THEN NEW.expires_at:=allocation.expires_at;
 ELSIF NEW.expires_at IS DISTINCT FROM allocation.expires_at THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_video_evidence_object() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a_guard_video_evidence_object BEFORE INSERT OR UPDATE ON internal.observation_evidence_objects
 FOR EACH ROW EXECUTE FUNCTION internal.guard_video_evidence_object();
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_get_functiondef('internal.guard_observation_upload_receipt()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    SELECT * INTO cohort FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed receipt guard changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations WHERE analysis_id=NEW.analysis_id) THEN
        -- a_guard_video_evidence_object has already validated the complete allocation.
        RETURN NEW;
    END IF;
$body$||anchor);
 SELECT pg_get_functiondef('public.retire_expired_observation_evidence()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='            AND NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts a WHERE a.analysis_id=e.analysis_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed orphan cleanup changed'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n            AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations v WHERE v.analysis_id=e.analysis_id)');
END;
$patch$;

-- Legacy expiry primitives must never split a retained video allocation.
DO $patch$
DECLARE signature TEXT; definition TEXT; anchor TEXT;
BEGIN
 FOREACH signature IN ARRAY ARRAY['internal.expire_observation_evidence(uuid)','internal.expire_unbound_observation_evidence(uuid)'] LOOP
  SELECT pg_get_functiondef(signature::REGPROCEDURE) INTO STRICT definition;
  anchor:='    DELETE FROM internal.observation_evidence_objects WHERE media_id=p_media';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed single-object expiry changed'; END IF;
  EXECUTE replace(definition,anchor,anchor||E'\n        AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations WHERE analysis_id=saved.analysis_id)');
 END LOOP;
END;
$patch$;

CREATE FUNCTION internal.video_evidence_receipt(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE allocation internal.observation_video_evidence_allocations; objects JSONB:='[]'::JSONB; item JSONB; saved internal.observation_evidence_objects; ready BOOLEAN:=TRUE;
BEGIN
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations WHERE analysis_id=p_binding.analysis_id;
 IF NOT FOUND OR allocation.owner_id IS DISTINCT FROM p_binding.owner_id OR allocation.observation_id IS DISTINCT FROM p_binding.observation_id
  OR allocation.source_analysis_id IS DISTINCT FROM p_binding.source_analysis_id
  OR (SELECT jsonb_agg(value-'object_id' ORDER BY ord) FROM jsonb_array_elements(allocation.items) WITH ORDINALITY q(value,ord)) IS DISTINCT FROM internal.observation_video_source_cohort_items(p_binding.input_snapshot)
  OR (SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id=p_binding.analysis_id)<>jsonb_array_length(allocation.items) THEN
  RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(allocation.items) LOOP
  SELECT * INTO saved FROM internal.observation_evidence_objects WHERE media_id=(item->>'media_id')::UUID;
  IF NOT FOUND OR saved.analysis_id IS DISTINCT FROM p_binding.analysis_id OR saved.owner_id IS DISTINCT FROM allocation.owner_id
   OR saved.observation_id IS DISTINCT FROM allocation.observation_id OR saved.object_id::TEXT IS DISTINCT FROM item->>'object_id'
   OR saved.content_type IS DISTINCT FROM item->>'content_type' OR saved.byte_count IS DISTINCT FROM (item->>'byte_count')::INTEGER
   OR saved.sha256 IS DISTINCT FROM item->>'sha256' OR saved.expires_at IS DISTINCT FROM allocation.expires_at
   OR EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=saved.object_id) THEN
   RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
  ready:=ready AND saved.ready_at IS NOT NULL;
  objects:=objects||jsonb_build_array(item||jsonb_build_object('ready_at',to_char(saved.ready_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
 END LOOP;
 RETURN internal.observation_video_source_identity(p_binding)||jsonb_build_object('owner_id',allocation.owner_id,
  'state',CASE WHEN ready THEN 'ready' ELSE 'allocated' END,'expires_at',to_char(allocation.expires_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'items',objects);
END;
$$;
REVOKE ALL ON FUNCTION internal.video_evidence_receipt(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.reserve_owned_observation_video_evidence(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_analysis_source_bindings; cohort internal.observation_video_evidence_upload_cohorts; allocation internal.observation_video_evidence_allocations;
 item JSONB; items JSONB:='[]'::JSONB; object UUID; seen UUID[];
BEGIN
 PERFORM internal.require_service_role();
 binding:=internal.lock_video_evidence_request(p_owner,p_request,p_reader);
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations WHERE analysis_id=binding.analysis_id;
 IF FOUND THEN RETURN internal.video_evidence_receipt(binding); END IF;
 IF (SELECT video_evidence_enabled AND media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 IF NOT internal.observation_video_source_preexecution_clear(binding.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 SELECT * INTO cohort FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=binding.analysis_id;
 IF NOT FOUND THEN
  INSERT INTO internal.observation_video_evidence_upload_cohorts VALUES(binding.analysis_id,p_owner,binding.observation_id,binding.source_analysis_id,p_request->'items') RETURNING * INTO cohort;
 ELSIF cohort.items IS DISTINCT FROM p_request->'items' OR cohort.owner_id IS DISTINCT FROM p_owner
  OR cohort.observation_id IS DISTINCT FROM binding.observation_id OR cohort.source_analysis_id IS DISTINCT FROM binding.source_analysis_id THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 seen:=ARRAY[p_owner,binding.observation_id,binding.source_analysis_id,binding.analysis_id]||ARRAY(SELECT (value->>'media_id')::UUID FROM jsonb_array_elements(cohort.items));
 FOR item IN SELECT value FROM jsonb_array_elements(cohort.items) LOOP
  FOR attempt IN 1..4 LOOP
   object:=gen_random_uuid();
   PERFORM pg_advisory_xact_lock(hashtextextended('merian-history-object:'||object::TEXT,0::BIGINT));
   EXIT WHEN NOT object=ANY(seen) AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE object_id=object)
    AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=object);
   IF attempt=4 THEN RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
  END LOOP;
  seen:=array_append(seen,object); items:=items||jsonb_build_array(item||jsonb_build_object('object_id',object));
 END LOOP;
 INSERT INTO internal.observation_video_evidence_allocations VALUES(binding.analysis_id,p_owner,binding.observation_id,binding.source_analysis_id,items,date_trunc('milliseconds',clock_timestamp())+INTERVAL '5 minutes') RETURNING * INTO allocation;
 FOR item IN SELECT value FROM jsonb_array_elements(items) LOOP
  INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,object_id,content_type,byte_count,sha256,expires_at)
   VALUES((item->>'media_id')::UUID,binding.observation_id,binding.analysis_id,p_owner,(item->>'object_id')::UUID,item->>'content_type',(item->>'byte_count')::INTEGER,item->>'sha256',allocation.expires_at);
 END LOOP;
 RETURN internal.video_evidence_receipt(binding);
END;
$$;

-- Trusted byte-verifying orchestration acknowledges one exact allocated item,
-- never timestamps. Every acknowledgement returns the complete closed receipt.
CREATE FUNCTION public.complete_owned_observation_video_evidence(p_owner UUID,p_request JSONB,p_media UUID,p_object UUID,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE binding internal.observation_analysis_source_bindings; allocation internal.observation_video_evidence_allocations; answer JSONB; item JSONB; stamp TIMESTAMPTZ;
BEGIN
 PERFORM internal.require_service_role();
 binding:=internal.lock_video_evidence_request(p_owner,p_request,p_reader);
 answer:=internal.video_evidence_receipt(binding);
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations WHERE analysis_id=binding.analysis_id;
 SELECT value INTO item FROM jsonb_array_elements(answer->'items') WHERE value->>'media_id'=p_media::TEXT;
 IF item IS NULL OR p_object IS NULL OR item->>'object_id' IS DISTINCT FROM p_object::TEXT THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF item->'ready_at'<>'null'::JSONB THEN RETURN answer; END IF;
 IF (SELECT video_evidence_enabled AND media_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
  OR allocation.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'analysis_history_evidence_unavailable' USING ERRCODE='55000'; END IF;
 stamp:=date_trunc('milliseconds',clock_timestamp());
 UPDATE internal.observation_evidence_objects SET ready_at=stamp WHERE analysis_id=binding.analysis_id AND media_id=p_media AND object_id=p_object AND ready_at IS NULL;
 RETURN internal.video_evidence_receipt(binding);
END;
$$;

CREATE FUNCTION public.retire_expired_observation_video_evidence()
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='10s' AS $$
DECLARE allocation internal.observation_video_evidence_allocations; binding internal.observation_analysis_source_bindings; removed INTEGER;
BEGIN
 PERFORM internal.require_service_role();
 IF (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN 0; END IF;
 SELECT * INTO allocation FROM internal.observation_video_evidence_allocations a WHERE a.expires_at<=clock_timestamp()
  AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=a.analysis_id)
  AND internal.observation_video_evidence_execution_clear(a.analysis_id)
  ORDER BY a.expires_at,a.analysis_id LIMIT 1;
 IF NOT FOUND THEN RETURN 0; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=allocation.analysis_id;
 binding:=internal.lock_owned_observation_video_source_binding(allocation.owner_id,allocation.observation_id,allocation.analysis_id,binding.input_snapshot);
 IF NOT internal.observation_video_evidence_execution_clear(binding.analysis_id)
  OR (SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN RETURN 0; END IF;
 -- A concurrent cleanup may have completed while this worker waited for locks.
 IF NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=binding.analysis_id) THEN RETURN 0; END IF;
 PERFORM internal.video_evidence_receipt(binding);
 DELETE FROM internal.observation_evidence_objects WHERE analysis_id=binding.analysis_id;
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
EXCEPTION WHEN SQLSTATE 'P0002' THEN RETURN 0;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_video_evidence(UUID,JSONB,INTEGER),
 public.complete_owned_observation_video_evidence(UUID,JSONB,UUID,UUID,INTEGER),public.retire_expired_observation_video_evidence() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_video_evidence(UUID,JSONB,INTEGER),
 public.complete_owned_observation_video_evidence(UUID,JSONB,UUID,UUID,INTEGER),public.retire_expired_observation_video_evidence() TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_observation_video_evidence(uuid,jsonb,integer)','Allocate the exact complete V4 video inventory under immutable binding and live occupancy; no inference.'),
 ('service_role','public.complete_owned_observation_video_evidence(uuid,jsonb,uuid,uuid,integer)','Record one trusted verified V4 item against its original object and fixed expiry; return the entire inventory.'),
 ('service_role','public.retire_expired_observation_video_evidence()','Erase expired exact V4 objects while retaining allocation identity and permanent erasure obligations.');
COMMENT ON TABLE internal.observation_video_evidence_upload_cohorts IS 'Immutable V4 source and derived inventory. Separate retained allocation owns object IDs and deadlines; service-only per-item completion returns whole receipts. No HTTP route or protected execution admission.';
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN video_source_retirement_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_video_source_retirements (
 operation_id UUID PRIMARY KEY,
 analysis_id UUID NOT NULL UNIQUE,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 request_identity JSONB NOT NULL CHECK(octet_length(request_identity::TEXT)<=2048),
 receipt JSONB NOT NULL CHECK(octet_length(receipt::TEXT)<=2048),
 -- JSON null explicitly records no cohort. Otherwise retain the exact inventory
 -- privately after removing its live metadata; it never enters the wire receipt.
 cohort_inventory JSONB NOT NULL CHECK(cohort_inventory='null'::JSONB OR
  (jsonb_typeof(cohort_inventory)='array' AND jsonb_array_length(cohort_inventory) BETWEEN 6 AND 7 AND octet_length(cohort_inventory::TEXT)<=4096)),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_video_source_retirements_source
 ON internal.observation_video_source_retirements(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_video_source_retirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_video_source_retirements FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_video_source_identity(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('schema_version',2,'observation_id',p_binding.observation_id,
 'source_analysis_id',p_binding.source_analysis_id,'analysis_id',p_binding.analysis_id,
 'request_digest',p_binding.input_snapshot->>'request_digest','fingerprint_version',p_binding.fingerprint_version,'fingerprint',p_binding.fingerprint);
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_identity(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_video_source_preexecution_clear(p_analysis UUID)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=p_analysis OR request_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE analysis_id=p_analysis)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_source_completion_receipts WHERE analysis_id=p_analysis);
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_preexecution_clear(UUID) FROM PUBLIC,anon,authenticated,service_role;

-- Called under canonical source locks. This is the pre-delete proof: it
-- deliberately allows the exact still-live V4 cohort and occupancy.
CREATE FUNCTION internal.observation_video_retirement_record_valid(p_binding internal.observation_analysis_source_bindings)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE retired internal.observation_video_source_retirements;
BEGIN
 IF p_binding.analysis_id IS NULL OR p_binding.fingerprint_version IS DISTINCT FROM 1
 OR p_binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB
 OR p_binding.input_snapshot->>'observation_id' IS DISTINCT FROM p_binding.observation_id::TEXT
 OR p_binding.input_snapshot->>'analysis_id' IS DISTINCT FROM p_binding.analysis_id::TEXT
 OR p_binding.input_snapshot->>'source_analysis_id' IS DISTINCT FROM p_binding.source_analysis_id::TEXT
 OR p_binding.fingerprint IS DISTINCT FROM internal.observation_video_source_fingerprint(p_binding.input_snapshot) THEN RETURN FALSE; END IF;
 SELECT * INTO retired FROM internal.observation_video_source_retirements WHERE analysis_id=p_binding.analysis_id;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 RETURN retired.owner_id=p_binding.owner_id AND retired.observation_id=p_binding.observation_id
  AND retired.source_analysis_id=p_binding.source_analysis_id
  AND retired.operation_id NOT IN(p_binding.analysis_id,p_binding.observation_id,p_binding.source_analysis_id)
  AND retired.request_identity=internal.observation_video_source_identity(p_binding)||jsonb_build_object('operation_id',retired.operation_id)
  AND retired.receipt=retired.request_identity||jsonb_build_object('owner_id',p_binding.owner_id,'state','retired_pre_execution')
  AND (retired.cohort_inventory='null'::JSONB OR retired.cohort_inventory=internal.observation_video_source_cohort_items(p_binding.input_snapshot))
  AND internal.observation_video_source_preexecution_clear(p_binding.analysis_id);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_retirement_record_valid(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

-- Final successor proof is stronger than pre-delete authorization. A retained
-- receipt alone cannot establish release while either live row still exists.
CREATE FUNCTION internal.observation_video_source_release_proven(p_binding internal.observation_analysis_source_bindings)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
 SELECT internal.observation_video_retirement_record_valid(p_binding)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_binding.analysis_id)
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_binding.analysis_id);
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_release_proven(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_video_retirement()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; cohort internal.observation_video_evidence_upload_cohorts; inventory JSONB;
BEGIN
 IF TG_OP='UPDATE' THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF TG_OP='DELETE' THEN
  IF EXISTS(SELECT 1 FROM public.scans WHERE id=OLD.observation_id AND NOT is_tombstoned)
   AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=OLD.observation_id) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
  END IF;
  RETURN OLD;
 END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=NEW.analysis_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 binding:=internal.lock_owned_observation_video_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 SELECT * INTO cohort FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id;
 inventory:='null'::JSONB;
 IF FOUND THEN
  IF cohort.owner_id IS DISTINCT FROM binding.owner_id OR cohort.observation_id IS DISTINCT FROM binding.observation_id
   OR cohort.source_analysis_id IS DISTINCT FROM binding.source_analysis_id
   OR cohort.items IS DISTINCT FROM internal.observation_video_source_cohort_items(binding.input_snapshot) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  inventory:=cohort.items;
 END IF;
 IF NEW.source_analysis_id IS DISTINCT FROM binding.source_analysis_id
  OR NEW.operation_id IN(binding.analysis_id,binding.observation_id,binding.source_analysis_id)
  OR NEW.request_identity IS DISTINCT FROM internal.observation_video_source_identity(binding)||jsonb_build_object('operation_id',NEW.operation_id)
  OR NEW.receipt IS DISTINCT FROM NEW.request_identity||jsonb_build_object('owner_id',NEW.owner_id,'state','retired_pre_execution')
  OR NEW.cohort_inventory IS DISTINCT FROM inventory
  OR NOT internal.observation_video_source_preexecution_clear(binding.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_video_retirement() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_video_retirement BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_video_source_retirements FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_video_retirement();

CREATE FUNCTION public.retire_owned_observation_video_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE observation UUID; source UUID; child UUID; operation UUID; field TEXT;
 binding internal.observation_analysis_source_bindings; prior internal.observation_video_source_retirements; answer JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 12 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>2048
  OR NOT(p_request ?& ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','operation_id','request_digest','fingerprint_version','fingerprint'])
  OR p_request-ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','operation_id','request_digest','fingerprint_version','fingerprint']<>'{}'
  OR p_request->'schema_version' IS DISTINCT FROM '2'::JSONB OR p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 FOREACH field IN ARRAY ARRAY['observation_id','source_analysis_id','analysis_id','operation_id'] LOOP
  IF jsonb_typeof(p_request->field) IS DISTINCT FROM 'string' OR p_request->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH field IN ARRAY ARRAY['request_digest','fingerprint'] LOOP
  IF jsonb_typeof(p_request->field) IS DISTINCT FROM 'string' OR p_request->>field !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END LOOP;
 observation:=(p_request->>'observation_id')::UUID; source:=(p_request->>'source_analysis_id')::UUID;
 child:=(p_request->>'analysis_id')::UUID; operation:=(p_request->>'operation_id')::UUID;
 IF child IN (observation,source) OR observation=source OR operation IN (observation,source,child) THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 PERFORM internal.lock_owned_observation_source(p_owner,observation,source);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||child::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||child::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-source-retirement:'||operation::TEXT,0::BIGINT));
 SELECT * INTO prior FROM internal.observation_video_source_retirements WHERE operation_id=operation;
 IF FOUND THEN
  IF prior.owner_id<>p_owner OR prior.request_identity<>p_request THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN prior.receipt;
 END IF;
 IF (SELECT video_source_retirement_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=child;
 IF NOT FOUND OR binding.owner_id<>p_owner OR binding.observation_id<>observation OR binding.source_analysis_id<>source
  OR internal.observation_video_source_identity(binding) IS DISTINCT FROM p_request-'operation_id'
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=child
   AND owner_id=p_owner AND observation_id=observation AND source_analysis_id=source)
  OR EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=child)
  OR NOT internal.observation_video_source_preexecution_clear(child) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 answer:=p_request||jsonb_build_object('owner_id',p_owner,'state','retired_pre_execution');
 INSERT INTO internal.observation_video_source_retirements
  SELECT operation,child,p_owner,observation,source,p_request,answer,
   coalesce((SELECT items FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=child),'null'::JSONB);
 DELETE FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=child;
 DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=child
  AND owner_id=p_owner AND observation_id=observation AND source_analysis_id=source;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 IF NOT internal.observation_video_source_release_proven(binding) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN answer;
END;
$$;
REVOKE ALL ON FUNCTION public.retire_owned_observation_video_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_owned_observation_video_source(UUID,JSONB,INTEGER) TO service_role;
-- Both live-row delete guards use this pre-delete proof under canonical locks.
-- SQL NULL items means occupancy; JSON array means the exact cohort being removed.
CREATE FUNCTION internal.observation_video_retirement_can_remove(p_owner UUID,p_observation UUID,p_source UUID,p_analysis UUID,p_items JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings; retired internal.observation_video_source_retirements;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis)
  OR NOT EXISTS(SELECT 1 FROM public.scans WHERE id=p_observation AND NOT is_tombstoned)
  OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_observation) THEN RETURN FALSE; END IF;
 PERFORM internal.lock_owned_observation_source(p_owner,p_observation,p_source);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||p_analysis::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||p_analysis::TEXT,0::BIGINT));
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;
 IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner OR binding.observation_id IS DISTINCT FROM p_observation
  OR binding.source_analysis_id IS DISTINCT FROM p_source OR NOT internal.observation_video_retirement_record_valid(binding)
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=p_analysis
   AND owner_id=p_owner AND observation_id=p_observation AND source_analysis_id=p_source) THEN RETURN FALSE; END IF;
 IF p_items IS NULL THEN
  RETURN NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=p_analysis);
 END IF;
 SELECT * INTO retired FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis;
 RETURN retired.cohort_inventory=p_items AND p_items=internal.observation_video_source_cohort_items(binding.input_snapshot);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_retirement_can_remove(UUID,UUID,UUID,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    IF TG_OP='DELETE' THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed source deletion changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF TG_OP='DELETE' THEN
        IF TG_TABLE_NAME='observation_analysis_source_occupancy' AND
            internal.observation_video_retirement_can_remove(OLD.owner_id,OLD.observation_id,OLD.source_analysis_id,OLD.analysis_id,NULL) THEN
            RETURN OLD;
        END IF;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    RETURN NEW;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed source resurrection changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=NEW.analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_video_cohort()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$ IF TG_OP='DELETE' THEN$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed video cohort deletion changed'; END IF;
 EXECUTE replace(definition,anchor,$body$ IF TG_OP='DELETE' THEN
  IF internal.observation_video_retirement_can_remove(OLD.owner_id,OLD.observation_id,OLD.source_analysis_id,OLD.analysis_id,OLD.items) THEN
   RETURN OLD; END IF;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.validate_observation_source_binding()'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$        OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed binding collision changed'; END IF;
 EXECUTE replace(definition,anchor,$body$        OR EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=NEW.analysis_id)$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.lock_owned_observation_video_source_binding(uuid,uuid,uuid,jsonb)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed retirement admission fence internal.lock_owned_observation_video_source_binding changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.assert_observation_source_input_chain(uuid,uuid,uuid,jsonb)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed retirement admission fence internal.assert_observation_source_input_chain changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_analysis;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.lock_observation_analysis_source(uuid,uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed retirement execution fence changed'; END IF;
 EXECUTE replace(definition,anchor,$body$    IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=p_analysis) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    SELECT * INTO saved FROM internal.observation_analysis_intents WHERE analysis_id=p_analysis;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('public.reserve_owned_observation_video_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$  -- V4 has no reviewed remote retirement/completion proof yet.$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed video terminal replay comment changed'; END IF;
 EXECUTE replace(definition,anchor,$body$  -- Existing child remains terminal; only a new identity can use proven release.$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('public.reserve_owned_observation_video_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$  IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed video retired replay changed'; END IF;
 EXECUTE replace(definition,anchor,$body$  IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=child) THEN
   RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
  IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('public.reserve_owned_observation_video_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$ OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed video retirement coverage changed'; END IF;
 EXECUTE replace(definition,anchor,$body$ OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_source_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('public.reserve_owned_observation_video_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$  IF predecessor.input_snapshot->'schema_version'='4'::JSONB THEN
   RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed V4 successor proof changed'; END IF;
 EXECUTE replace(definition,anchor,$body$  IF predecessor.input_snapshot->'schema_version'='4'::JSONB THEN
   IF predecessor.owner_id<>p_owner OR NOT internal.observation_video_source_release_proven(predecessor) THEN
    RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
   CONTINUE;
  END IF;$body$);
END;
$patch$;

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('public.get_owned_observation_video_source(uuid,jsonb,integer)'::REGPROCEDURE) INTO STRICT definition;
 anchor:=$anchor$ IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy$anchor$;
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'Reviewed video retired lookup changed'; END IF;
 EXECUTE replace(definition,anchor,$body$ IF EXISTS(SELECT 1 FROM internal.observation_video_source_retirements WHERE analysis_id=child) THEN
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy$body$);
END;
$patch$;

INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.retire_owned_observation_video_source(uuid,jsonb,integer)','Reader12 exact V4 pre-execution retirement, private inventory retention and atomic source release; no upload, dispatch or refund.');
COMMENT ON TABLE internal.observation_video_source_retirements IS
 'Permanent pre-execution V4 fence and exact replay receipt. Retains original identity and optional exact cohort inventory until parent erasure. No provider invocation or refund.';
COMMENT ON TABLE internal.observation_video_evidence_upload_cohorts IS
 'Private immutable whole V4 inventory bound to live source occupancy. Metadata only. Removal requires exact pre-execution retirement with retained inventory, or parent erasure; never local discard.';
RESET statement_timeout;
RESET lock_timeout;

SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN source_reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN source_unfunded_retirement_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE internal.observation_source_unfunded_retirements (
 operation_id UUID PRIMARY KEY,
 analysis_id UUID NOT NULL UNIQUE,
 owner_id UUID NOT NULL,
 observation_id UUID NOT NULL,
 source_analysis_id UUID NOT NULL,
 request_identity JSONB NOT NULL CHECK(octet_length(request_identity::TEXT)<=2048),
 receipt JSONB NOT NULL CHECK(octet_length(receipt::TEXT)<=2048),
 FOREIGN KEY(analysis_id,owner_id,observation_id,source_analysis_id)
 REFERENCES internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id) ON DELETE CASCADE
);
CREATE INDEX observation_source_unfunded_retirements_source
 ON internal.observation_source_unfunded_retirements(observation_id,source_analysis_id,analysis_id);
ALTER TABLE internal.observation_source_unfunded_retirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_source_unfunded_retirements FROM PUBLIC,anon,authenticated,service_role;

-- Caller holds owner/parent/source/child locks. Absence is proof only for a
-- retained never-admitted binding; generic quota absence alone is not proof.
CREATE FUNCTION internal.observation_source_child_is_unused(p_analysis UUID)
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
 AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=p_analysis);
$$;
REVOKE ALL ON FUNCTION internal.observation_source_child_is_unused(UUID) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_source_identity(p_binding internal.observation_analysis_source_bindings)
RETURNS JSONB LANGUAGE SQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id',p_binding.observation_id,
 'source_analysis_id',p_binding.source_analysis_id,'analysis_id',p_binding.analysis_id,
 'request_digest',p_binding.input_snapshot->>'request_digest','fingerprint_version',p_binding.fingerprint_version,'fingerprint',p_binding.fingerprint);
$$;
REVOKE ALL ON FUNCTION internal.observation_source_identity(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.observation_source_release_proven(p_binding internal.observation_analysis_source_bindings)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE retired internal.observation_source_unfunded_retirements;
BEGIN
 IF p_binding.analysis_id IS NULL OR p_binding.fingerprint_version IS DISTINCT FROM 1
 OR p_binding.input_snapshot->>'observation_id' IS DISTINCT FROM p_binding.observation_id::TEXT
 OR p_binding.input_snapshot->>'analysis_id' IS DISTINCT FROM p_binding.analysis_id::TEXT
 OR p_binding.input_snapshot->>'source_analysis_id' IS DISTINCT FROM p_binding.source_analysis_id::TEXT
 OR p_binding.fingerprint IS DISTINCT FROM internal.observation_source_fingerprint(p_binding.input_snapshot) THEN RETURN FALSE; END IF;
 SELECT * INTO retired FROM internal.observation_source_unfunded_retirements WHERE analysis_id=p_binding.analysis_id;
 IF FOUND THEN
  RETURN retired.owner_id=p_binding.owner_id AND retired.observation_id=p_binding.observation_id
   AND retired.source_analysis_id=p_binding.source_analysis_id
   AND retired.request_identity=internal.observation_source_identity(p_binding)||jsonb_build_object('operation_id',retired.operation_id)
   AND retired.receipt=retired.request_identity||jsonb_build_object('owner_id',p_binding.owner_id,'state','retired_unfunded')
   AND internal.observation_source_child_is_unused(p_binding.analysis_id);
 END IF;
 RETURN EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
                JOIN internal.observation_analysis_intents i ON i.analysis_id=b.analysis_id
                JOIN internal.observation_analysis_retirement_receipts r ON r.analysis_id=i.analysis_id
                JOIN internal.ai_quota_reservations q ON q.id=(i.quota->>'reservation_id')::UUID
                WHERE b.analysis_id=p_binding.analysis_id AND b.owner_id=p_binding.owner_id
                    AND b.observation_id=p_binding.observation_id AND b.source_analysis_id=p_binding.source_analysis_id
                    AND i.owner_id=b.owner_id AND i.observation_id=b.observation_id AND i.input_snapshot=b.input_snapshot
                    AND b.fingerprint_version=1 AND b.fingerprint=internal.observation_source_fingerprint(i.input_snapshot)
                    AND i.state='failed_terminal' AND i.terminal_reason='retired_before_dispatch'
                    AND i.provider_usage='{}'::JSONB AND i.invocation_id IS NULL AND i.provider_outcome IS NULL
                    AND i.draft IS NULL AND i.receipt IS NULL AND i.work_token IS NULL AND i.work_expires_at IS NULL
                    AND r.owner_id=b.owner_id AND r.observation_id=b.observation_id
                    AND r.request_identity=jsonb_build_object('schema_version',1,'operation_id',r.operation_id,
                        'observation_id',b.observation_id,'analysis_id',b.analysis_id,'source_analysis_id',b.source_analysis_id,
                        'request_digest',i.input_snapshot->>'request_digest')
                    AND r.receipt=r.request_identity || '{"state":"retired_before_dispatch"}'::JSONB
                    AND q.user_id=b.owner_id AND q.original_analysis_id=b.analysis_id AND q.request_id=b.analysis_id
                    AND q.operation='scan_identification' AND q.state='refunded' AND q.refund_count=1
                    AND q.committed_at IS NULL AND q.failed_at IS NULL
                    AND q.lease_token::TEXT=i.quota->>'lease_token' AND to_jsonb(q.attempt_count)=i.quota->'attempt_count'
                    AND i.quota->>'original_analysis_id'=b.analysis_id::TEXT AND i.quota->>'reservation_state'='reserved'
                    AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=b.analysis_id)
                    AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=b.analysis_id OR reservation_id=q.id)
                    AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=b.analysis_id));
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_source_release_proven(internal.observation_analysis_source_bindings) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION internal.guard_observation_unfunded_retirement()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE binding internal.observation_analysis_source_bindings;
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
 binding:=internal.lock_owned_observation_source_binding(NEW.owner_id,NEW.observation_id,NEW.analysis_id,binding.input_snapshot);
 IF NEW.source_analysis_id IS DISTINCT FROM binding.source_analysis_id
  OR NEW.operation_id IN (binding.analysis_id,binding.observation_id,binding.source_analysis_id)
  OR NEW.request_identity IS DISTINCT FROM internal.observation_source_identity(binding)||jsonb_build_object('operation_id',NEW.operation_id)
  OR NEW.receipt IS DISTINCT FROM NEW.request_identity||jsonb_build_object('owner_id',NEW.owner_id,'state','retired_unfunded')
  OR NOT internal.observation_source_child_is_unused(binding.analysis_id) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_observation_unfunded_retirement() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER guard_observation_unfunded_retirement BEFORE INSERT OR UPDATE OR DELETE
 ON internal.observation_source_unfunded_retirements FOR EACH ROW EXECUTE FUNCTION internal.guard_observation_unfunded_retirement();

-- Existing funded release proof and parent-deletion exceptions stay unchanged.
DO $guard$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
 anchor:='    IF TG_OP=''DELETE'' THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed source delete guard changed'; END IF;
 definition:=replace(definition,anchor,anchor||$body$
        IF TG_TABLE_NAME='observation_analysis_source_occupancy'
            AND EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
                JOIN internal.observation_source_unfunded_retirements r USING(analysis_id)
                WHERE b.analysis_id=OLD.analysis_id AND b.owner_id=OLD.owner_id
                AND b.observation_id=OLD.observation_id AND b.source_analysis_id=OLD.source_analysis_id
                AND internal.observation_source_release_proven(b)) THEN RETURN OLD; END IF;
$body$);
 anchor:='    RETURN NEW;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'Reviewed source insert guard changed'; END IF;
 EXECUTE replace(definition,anchor,$body$
    IF TG_TABLE_NAME='observation_analysis_source_occupancy' AND (
        EXISTS(SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_retirement_receipts WHERE analysis_id=NEW.analysis_id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=NEW.analysis_id)) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$body$||anchor);
END;
$guard$;

CREATE FUNCTION public.reserve_owned_observation_analysis_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE input JSONB; fingerprint TEXT; observation UUID; source UUID; child UUID; answer JSONB;
 binding internal.observation_analysis_source_bindings; predecessor internal.observation_analysis_source_bindings;
BEGIN
 PERFORM internal.require_service_role();
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 11 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>1048576
  OR NOT(p_request ?& ARRAY['schema_version','input','fingerprint_version','fingerprint'])
  OR p_request-ARRAY['schema_version','input','fingerprint_version','fingerprint']<>'{}'
  OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB OR p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB
  OR jsonb_typeof(p_request->'fingerprint') IS DISTINCT FROM 'string' THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 input:=p_request->'input'; fingerprint:=internal.observation_source_fingerprint(input);
 IF p_request->>'fingerprint' IS DISTINCT FROM fingerprint OR octet_length(input::TEXT)>1044480 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 observation:=(input->>'observation_id')::UUID; source:=(input->>'source_analysis_id')::UUID; child:=(input->>'analysis_id')::UUID;
 answer:=jsonb_build_object('schema_version',1,'owner_id',p_owner,'observation_id',observation,'source_analysis_id',source);
 BEGIN
  PERFORM internal.lock_owned_observation_source(p_owner,observation,source);
 EXCEPTION WHEN SQLSTATE 'P0002' THEN RETURN answer||'{"state":"unavailable"}'::JSONB;
 END;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||child::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||child::TEXT,0::BIGINT));
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=child;
 IF FOUND THEN
  IF binding.owner_id<>p_owner OR binding.observation_id<>observation OR binding.source_analysis_id<>source
   OR binding.input_snapshot<>input OR binding.fingerprint_version<>1 OR binding.fingerprint<>fingerprint THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy
    WHERE owner_id=p_owner AND observation_id=observation AND source_analysis_id=source AND analysis_id=child) THEN
   RETURN internal.observation_source_identity(binding)||answer||'{"state":"reserved"}'::JSONB;
  END IF;
  IF internal.observation_source_release_proven(binding) THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB;
 END IF;
 IF (SELECT source_reservation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RETURN answer||'{"state":"unavailable"}'::JSONB; END IF;
 -- Each independently growing namespace has its own sentinel. No pagination
 -- fragment, latest row, or read-only discovery response proves vacancy.
 IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_source_bindings WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_evidence_objects WHERE observation_id=observation LIMIT 65) q)>64 THEN
  RETURN answer||'{"state":"held","reason":"coverage_incomplete"}'::JSONB; END IF;
 IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE observation_id=observation AND source_analysis_id=source) THEN
  RETURN answer||'{"state":"held","reason":"source_occupied"}'::JSONB; END IF;
 IF EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.observation_id=observation
  AND (i.owner_id<>p_owner OR i.input_snapshot->>'observation_id' IS DISTINCT FROM observation::TEXT
   OR i.input_snapshot->>'analysis_id' IS DISTINCT FROM i.analysis_id::TEXT
   OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b WHERE b.analysis_id=i.analysis_id
    AND b.owner_id=p_owner AND b.observation_id=observation AND b.input_snapshot=i.input_snapshot))) THEN
  RETURN answer||'{"state":"held","reason":"coverage_incomplete"}'::JSONB; END IF;
 IF EXISTS(SELECT 1 FROM (
  SELECT owner_id,analysis_id FROM internal.observation_evidence_upload_cohorts WHERE observation_id=observation
  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation
  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_evidence_objects WHERE observation_id=observation
 ) media WHERE media.owner_id<>p_owner OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
  WHERE b.analysis_id=media.analysis_id AND b.owner_id=p_owner AND b.observation_id=observation)) THEN
  RETURN answer||'{"state":"held","reason":"coverage_incomplete"}'::JSONB; END IF;
 IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source) THEN
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 FOR predecessor IN SELECT * FROM internal.observation_analysis_source_bindings
  WHERE observation_id=observation AND source_analysis_id=source ORDER BY analysis_id LIMIT 64 LOOP
  IF predecessor.owner_id<>p_owner OR NOT internal.observation_source_release_proven(predecessor) THEN
   RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 END LOOP;
 IF NOT internal.observation_source_child_is_unused(child) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,p_owner,observation,source,input,1,fingerprint) RETURNING * INTO binding;
 INSERT INTO internal.observation_analysis_source_occupancy VALUES(p_owner,observation,source,child);
 RETURN internal.observation_source_identity(binding)||answer||'{"state":"reserved"}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_analysis_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_analysis_source(UUID,JSONB,INTEGER) TO service_role;

CREATE FUNCTION public.retire_owned_observation_analysis_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE observation UUID; source UUID; child UUID; operation UUID; field TEXT;
 binding internal.observation_analysis_source_bindings; prior internal.observation_source_unfunded_retirements; answer JSONB;
BEGIN
 PERFORM internal.require_service_role();
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 11 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>2048
  OR NOT(p_request ?& ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','operation_id','request_digest','fingerprint_version','fingerprint'])
  OR p_request-ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','operation_id','request_digest','fingerprint_version','fingerprint']<>'{}'
  OR p_request->'schema_version' IS DISTINCT FROM '1'::JSONB OR p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB THEN
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
 SELECT * INTO prior FROM internal.observation_source_unfunded_retirements WHERE operation_id=operation;
 IF FOUND THEN
  IF prior.owner_id<>p_owner OR prior.request_identity<>p_request THEN
   RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
  RETURN prior.receipt;
 END IF;
 IF (SELECT source_unfunded_retirement_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RAISE EXCEPTION 'analysis_history_unavailable' USING ERRCODE='55000'; END IF;
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=child;
 IF NOT FOUND OR binding.owner_id<>p_owner OR binding.observation_id<>observation OR binding.source_analysis_id<>source
  OR internal.observation_source_identity(binding) IS DISTINCT FROM p_request-'operation_id'
  OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy WHERE analysis_id=child
   AND owner_id=p_owner AND observation_id=observation AND source_analysis_id=source)
  OR EXISTS(SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE analysis_id=child)
  OR NOT internal.observation_source_child_is_unused(child) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 answer:=p_request||jsonb_build_object('owner_id',p_owner,'state','retired_unfunded');
 INSERT INTO internal.observation_source_unfunded_retirements VALUES(operation,child,p_owner,observation,source,p_request,answer);
 DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=child
  AND owner_id=p_owner AND observation_id=observation AND source_analysis_id=source;
 IF NOT FOUND THEN RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 RETURN answer;
END;
$$;
REVOKE ALL ON FUNCTION public.retire_owned_observation_analysis_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.retire_owned_observation_analysis_source(UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_observation_analysis_source(uuid,jsonb,integer)','Reader11 closed source reservation only; no funding or execution permission.'),
 ('service_role','public.retire_owned_observation_analysis_source(uuid,jsonb,integer)','Reader11 exact never-admitted retirement proof and atomic source release; no refund.');
RESET statement_timeout;
RESET lock_timeout;

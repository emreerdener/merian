SET lock_timeout='5s';
SET statement_timeout='2min';

ALTER TABLE internal.observation_history_rollout
 ADD COLUMN video_source_reservation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN video_source_recovery_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Reader12/schema2 only. Exact replay precedes fresh admission gates. This
-- reserves metadata and occupancy, never media upload, quota or execution.
CREATE FUNCTION public.reserve_owned_observation_video_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE input JSONB; fingerprint TEXT; observation UUID; source UUID; child UUID; answer JSONB;
 binding internal.observation_analysis_source_bindings; predecessor internal.observation_analysis_source_bindings;
BEGIN
 PERFORM internal.require_service_role();
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 12 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>1048576
  OR NOT(p_request ?& ARRAY['schema_version','input','fingerprint_version','fingerprint'])
  OR p_request-ARRAY['schema_version','input','fingerprint_version','fingerprint']<>'{}'
  OR p_request->'schema_version' IS DISTINCT FROM '2'::JSONB OR p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB
  OR jsonb_typeof(p_request->'fingerprint') IS DISTINCT FROM 'string' THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 input:=p_request->'input'; fingerprint:=internal.observation_video_source_fingerprint(input);
 IF p_request->>'fingerprint' IS DISTINCT FROM fingerprint OR octet_length(input::TEXT)>1044480 THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 observation:=(input->>'observation_id')::UUID; source:=(input->>'source_analysis_id')::UUID; child:=(input->>'analysis_id')::UUID;
 answer:=jsonb_build_object('schema_version',2,'owner_id',p_owner,'observation_id',observation,'source_analysis_id',source,
  'analysis_id',child,'request_digest',input->>'request_digest','fingerprint_version',1,'fingerprint',fingerprint);
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
   RETURN answer||'{"state":"reserved"}'::JSONB;
  END IF;
  -- V4 has no reviewed remote retirement/completion proof yet.
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB;
 END IF;
 IF (SELECT video_source_reservation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
 OR (SELECT source_reservation_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RETURN answer||'{"state":"unavailable"}'::JSONB; END IF;
 -- Each independently growing namespace has its own sentinel. No pagination
 -- fragment, latest row, or read-only discovery response proves vacancy.
 IF (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_intents WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_source_bindings WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_source_unfunded_retirements WHERE observation_id=observation AND source_analysis_id=source LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64
 OR (SELECT count(*) FROM (SELECT 1 FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation LIMIT 65) q)>64
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
  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=observation
  UNION ALL SELECT owner_id,analysis_id FROM internal.observation_evidence_objects WHERE observation_id=observation
 ) media WHERE media.owner_id<>p_owner OR NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings b
  WHERE b.analysis_id=media.analysis_id AND b.owner_id=p_owner AND b.observation_id=observation)) THEN
  RETURN answer||'{"state":"held","reason":"coverage_incomplete"}'::JSONB; END IF;
 IF EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND source_analysis_id=source) THEN
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 FOR predecessor IN SELECT * FROM internal.observation_analysis_source_bindings
  WHERE observation_id=observation AND source_analysis_id=source ORDER BY analysis_id LIMIT 64 LOOP
  IF predecessor.input_snapshot->'schema_version'='4'::JSONB THEN
   RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
  IF predecessor.owner_id<>p_owner OR NOT internal.observation_source_release_proven(predecessor) THEN
   RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 END LOOP;
 IF NOT internal.observation_source_child_is_unused(child) THEN
  RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023'; END IF;
 INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint)
 VALUES(child,p_owner,observation,source,input,1,fingerprint) RETURNING * INTO binding;
 INSERT INTO internal.observation_analysis_source_occupancy VALUES(p_owner,observation,source,child);
 RETURN answer||'{"state":"reserved"}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_owned_observation_video_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_owned_observation_video_source(UUID,JSONB,INTEGER) TO service_role;


-- Read-only exact lookup. No row creation, vacancy or retirement proof.
CREATE FUNCTION public.get_owned_observation_video_source(p_owner UUID,p_request JSONB,p_reader INTEGER)
RETURNS JSONB LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' SET statement_timeout='5s' AS $$
DECLARE observation UUID; source UUID; child UUID; field TEXT; answer JSONB;
 binding internal.observation_analysis_source_bindings;
BEGIN
 PERFORM internal.require_service_role();
 IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
  RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000'; END IF;
 IF p_reader IS DISTINCT FROM 12 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='22023'; END IF;
 IF p_owner IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' OR octet_length(p_request::TEXT)>2048
  OR NOT(p_request ?& ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','request_digest','fingerprint_version','fingerprint'])
  OR p_request-ARRAY['schema_version','observation_id','source_analysis_id','analysis_id','request_digest','fingerprint_version','fingerprint']<>'{}'
  OR p_request->'schema_version' IS DISTINCT FROM '2'::JSONB OR p_request->'fingerprint_version' IS DISTINCT FROM '1'::JSONB THEN
  RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 FOREACH field IN ARRAY ARRAY['observation_id','source_analysis_id','analysis_id'] LOOP
  IF jsonb_typeof(p_request->field) IS DISTINCT FROM 'string' OR p_request->>field !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH field IN ARRAY ARRAY['request_digest','fingerprint'] LOOP
  IF jsonb_typeof(p_request->field) IS DISTINCT FROM 'string' OR length(p_request->>field)<>64 OR p_request->>field !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 END LOOP;
 observation:=(p_request->>'observation_id')::UUID; source:=(p_request->>'source_analysis_id')::UUID; child:=(p_request->>'analysis_id')::UUID;
 IF child IN(observation,source) OR observation=source THEN RAISE EXCEPTION 'invalid_analysis_history' USING ERRCODE='22023'; END IF;
 answer:=p_request||jsonb_build_object('owner_id',p_owner);
 BEGIN
  PERFORM internal.lock_owned_observation_source(p_owner,observation,source);
 EXCEPTION WHEN SQLSTATE 'P0002' THEN RETURN answer||'{"state":"unavailable"}'::JSONB;
 END;
 IF (SELECT video_source_recovery_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE
 OR (SELECT source_discovery_enabled FROM internal.observation_history_rollout WHERE singleton) IS NOT TRUE THEN
  RETURN answer||'{"state":"unavailable"}'::JSONB; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||child::TEXT,0::BIGINT));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-history-evidence:'||child::TEXT,0::BIGINT));
 SELECT * INTO binding FROM internal.observation_analysis_source_bindings WHERE analysis_id=child;
 IF NOT FOUND OR binding.owner_id IS DISTINCT FROM p_owner OR binding.observation_id IS DISTINCT FROM observation
  OR binding.source_analysis_id IS DISTINCT FROM source OR binding.input_snapshot->'schema_version' IS DISTINCT FROM '4'::JSONB
  OR binding.input_snapshot->>'request_digest' IS DISTINCT FROM p_request->>'request_digest'
  OR binding.fingerprint_version IS DISTINCT FROM 1 OR binding.fingerprint IS DISTINCT FROM p_request->>'fingerprint' THEN
  RETURN answer||'{"state":"unavailable"}'::JSONB; END IF;
 IF binding.input_snapshot->>'observation_id' IS DISTINCT FROM observation::TEXT
  OR binding.input_snapshot->>'source_analysis_id' IS DISTINCT FROM source::TEXT
  OR binding.input_snapshot->>'analysis_id' IS DISTINCT FROM child::TEXT
  OR binding.fingerprint IS DISTINCT FROM internal.observation_video_source_fingerprint(binding.input_snapshot) THEN
  RETURN answer||'{"state":"unavailable"}'::JSONB; END IF;
 IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_source_occupancy
  WHERE owner_id=p_owner AND observation_id=observation AND source_analysis_id=source AND analysis_id=child) THEN
  RETURN answer||'{"state":"held","reason":"terminal_unproven"}'::JSONB; END IF;
 -- Revalidate the complete retained graph and immutable binding under the same locks.
 binding:=internal.lock_owned_observation_video_source_binding(p_owner,observation,child,binding.input_snapshot);
 RETURN answer||'{"state":"reserved"}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.get_owned_observation_video_source(UUID,JSONB,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_observation_video_source(UUID,JSONB,INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES
 ('service_role','public.reserve_owned_observation_video_source(uuid,jsonb,integer)','Reader12 exact V4 metadata reservation only; no upload, quota or execution authority.'),
 ('service_role','public.get_owned_observation_video_source(uuid,jsonb,integer)','Reader12 mutation-free exact V4 binding lookup; no absence or retirement proof.');
RESET statement_timeout;
RESET lock_timeout;

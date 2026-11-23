-- Local preparation only: no schedule, secret or rollout changes. Deployment
-- must pause/drain the worker before replacing its correlated receipt protocol.
SET lock_timeout='5s';
SET statement_timeout='2min';
ALTER TABLE internal.observation_evidence_worker_state
 ADD COLUMN last_composition_retired INTEGER CHECK(last_composition_retired BETWEEN 0 AND 8),
 ADD COLUMN last_receipt_schema_version INTEGER CHECK(last_receipt_schema_version IN (2,3));
DO $constraint$
DECLARE saved RECORD;
BEGIN
 -- PostgreSQL truncates generated names; identify the exact one-column check
 -- and validate its old bounds instead of guessing its physical name.
 SELECT c.conname,pg_get_constraintdef(c.oid) definition INTO STRICT saved
 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid
  AND a.attname='last_retirement_failures'
 WHERE c.conrelid='internal.observation_evidence_worker_state'::regclass
  AND c.contype='c' AND c.conkey=ARRAY[a.attnum];
 IF saved.definition IS DISTINCT FROM
  'CHECK (((last_retirement_failures >= 0) AND (last_retirement_failures <= 2)))' THEN
  RAISE EXCEPTION 'composition_worker_failure_constraint_drift'; END IF;
 EXECUTE format('ALTER TABLE internal.observation_evidence_worker_state DROP CONSTRAINT %I',saved.conname);
END;
$constraint$;
ALTER TABLE internal.observation_evidence_worker_state
 ADD CONSTRAINT evidence_worker_retirement_failure_bound CHECK(last_retirement_failures BETWEEN 0 AND 3);

CREATE FUNCTION internal.valid_composition_evidence_worker_counts(p_receipt JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE field TEXT;
BEGIN
 IF p_receipt IS NULL OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' THEN RETURN FALSE; END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(p_receipt))<>7 THEN RETURN FALSE; END IF;
 FOREACH field IN ARRAY ARRAY['retired','video_retired','composition_retired','retirement_failures','claimed','marked','acknowledged'] LOOP
  IF jsonb_typeof(p_receipt->field) IS DISTINCT FROM 'number' OR (p_receipt->>field)!~'^[0-9]$' THEN RETURN FALSE; END IF;
 END LOOP;
 RETURN (p_receipt->>'retired')::INTEGER<=5 AND (p_receipt->>'video_retired')::INTEGER<=7
  AND (p_receipt->>'composition_retired')::INTEGER<=8 AND (p_receipt->>'retirement_failures')::INTEGER<=3
  AND (p_receipt->>'claimed')::INTEGER<=1 AND (p_receipt->>'marked')::INTEGER<=(p_receipt->>'claimed')::INTEGER
  AND (p_receipt->>'acknowledged')::INTEGER<=(p_receipt->>'claimed')::INTEGER;
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_composition_evidence_worker_counts(JSONB) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION internal.valid_observation_evidence_worker_receipt(p_receipt JSONB,p_dispatch_id UUID)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF p_dispatch_id IS NULL OR p_receipt IS NULL OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' THEN RETURN FALSE; END IF;
 IF jsonb_typeof(p_receipt->'dispatch_id') IS DISTINCT FROM 'string' OR p_receipt->>'dispatch_id' IS DISTINCT FROM p_dispatch_id::TEXT THEN RETURN FALSE; END IF;
 IF p_receipt->'schema_version'='3'::JSONB THEN
  RETURN internal.valid_composition_evidence_worker_counts(p_receipt-'schema_version'-'dispatch_id');
 END IF;
 -- Previously dispatched V2 terminal receipts remain valid but never certify
 -- the availability of the new mixed cleanup stage.
 RETURN COALESCE(p_receipt->'schema_version'='2'::JSONB
  AND internal.valid_observation_evidence_worker_receipt(p_receipt-'schema_version'-'dispatch_id'),FALSE);
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_observation_evidence_worker_receipt(JSONB,UUID) FROM PUBLIC,anon,authenticated,service_role;
DO $patch$
DECLARE definition TEXT; anchor TEXT; extra TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.dispatch_observation_evidence_erasure()'::regprocedure);
 anchor:='            last_video_retired=CASE WHEN valid_receipt THEN (receipt->>''video_retired'')::INTEGER END,';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_dispatch_receipt_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n            last_composition_retired=CASE WHEN valid_receipt AND receipt->>''schema_version''=''3'' THEN (receipt->>''composition_retired'')::INTEGER END,\n            last_receipt_schema_version=CASE WHEN valid_receipt THEN (receipt->>''schema_version'')::INTEGER END,');
 definition:=pg_get_functiondef('internal.observation_evidence_retirement_candidates(timestamptz)'::regprocedure);
 anchor:='          AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations v WHERE v.analysis_id=e.analysis_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_health_orphan_drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n          AND NOT EXISTS(SELECT 1 FROM internal.observation_composition_evidence_allocations v WHERE v.analysis_id=e.analysis_id)');
 anchor:='          AND internal.observation_video_evidence_execution_clear(v.analysis_id)';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_health_inventory_drift'; END IF;
 extra:=$body$
        UNION ALL
        SELECT 'composition'::TEXT,v.owner_id,v.observation_id,v.analysis_id,NULL::UUID,v.expires_at
        FROM internal.observation_composition_evidence_allocations v
        WHERE v.expires_at<=p_observed_at
          AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=v.analysis_id)
          AND internal.observation_composition_evidence_execution_clear(v.analysis_id)
$body$;
 EXECUTE replace(definition,anchor,anchor||extra);
 definition:=pg_get_functiondef('public.get_observation_evidence_erasure_health()'::regprocedure);
 anchor:='        ''audio'',count(*) FILTER(WHERE kind=''audio''),''video'',count(*) FILTER(WHERE kind=''video''),';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_health_counts_drift'; END IF;
 definition:=replace(definition,anchor,anchor||E'\n        ''composition'',count(*) FILTER(WHERE kind=''composition''),');
 anchor:='        ''last_result'',state.last_result,''consecutive_failures'',state.consecutive_failures,';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'composition_health_protocol_drift'; END IF;
 EXECUTE replace(definition,anchor,anchor||E'\n        ''last_receipt_schema_version'',state.last_receipt_schema_version,');
END;
$patch$;
COMMENT ON COLUMN internal.observation_evidence_worker_state.last_receipt_schema_version IS
 'Observed correlated terminal receipt generation only. V2 never certifies the V3 composition cleanup stage; null remains unknown.';
RESET statement_timeout;
RESET lock_timeout;

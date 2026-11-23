SET lock_timeout='5s';
SET statement_timeout='2min';

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'::regprocedure);
 anchor:='WHERE scan_id=p_scan_id::TEXT
        AND (payload_schema_version=4';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_owner_classifier_drift'; END IF;
 definition:=replace(definition,anchor,'WHERE scan_id=p_scan_id::TEXT AND user_id=p_user_id
        AND (payload_schema_version=4');
 anchor:='WHERE scan_id=p_scan_id
        AND recovery->>''kind''=''private_capture_stage_v1''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_owner_witness_drift'; END IF;
 EXECUTE replace(definition,anchor,'WHERE scan_id=p_scan_id AND owner_id=p_user_id
        AND recovery->>''kind''=''private_capture_stage_v1''');

 definition:=pg_get_functiondef('internal.private_capture_finalization_ready(uuid,uuid)'::regprocedure);
 anchor:='OR evidence.payload_checksum IS DISTINCT FROM intent.payload_checksum';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_privacy_fence_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
 OR (intent.request_payload#>>'{telemetry,geoprivacy}' IN ('open','obscured','private')) IS NOT TRUE
 OR scan.geoprivacy IS DISTINCT FROM intent.request_payload#>>'{telemetry,geoprivacy}'
 OR evidence.payload_checksum IS DISTINCT FROM intent.payload_checksum
$body$);
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;

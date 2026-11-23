SET lock_timeout='5s';
SET statement_timeout='2min';
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.private_capture_finalization_ready(uuid,uuid)'::regprocedure);
 anchor:='scan.geoprivacy IS DISTINCT FROM intent.request_payload';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_privacy_type_drift'; END IF;
 EXECUTE replace(definition,anchor,'scan.geoprivacy::TEXT IS DISTINCT FROM intent.request_payload');
 definition:=pg_get_functiondef('public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'::regprocedure);
 anchor:='        IF NOT internal.private_capture_finalization_ready(p_scan_id,p_user_id) THEN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_finalizer_discriminator_drift'; END IF;
 -- The retained row outlives mutable intent/admission cleanup. Even if either
 -- disappears, a V9 private scan cannot fall through to legacy completion.
 EXECUTE replace(definition,
   'AND recovery->>''kind''=''private_capture_stage_v1'') THEN',
   'AND recovery->>''kind''=''private_capture_stage_v1'')
      OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence WHERE scan_id=p_scan_id AND owner_id=p_user_id
        AND evidence_manifest->''schema_version''=''9''::JSONB) THEN');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

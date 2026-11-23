SET lock_timeout='5s';
SET statement_timeout='2min';
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.private_capture_finalization_ready(uuid,uuid)'::regprocedure);
 anchor:=' OR scan.geoprivacy::TEXT IS DISTINCT FROM intent.request_payload#>>''{telemetry,geoprivacy}''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN RAISE EXCEPTION 'private_capture_mutable_privacy_fence_drift'; END IF;
 -- Admission freezes the default used for first insertion. Once inserted,
 -- privacy remains user-editable (including the account-default sync trigger).
 -- Completion must neither reject nor overwrite that later user choice.
 EXECUTE replace(definition,anchor,'');
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

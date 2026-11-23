SET lock_timeout='5s';
SET statement_timeout='2min';

-- Classification itself requires a fresh statement snapshot. A repeatable-read
-- caller can otherwise start before private admission, acquire its scan fence
-- afterward, and still see the old absence. Apply this before the first read,
-- including generic quota and invocation writers; a request cannot opt out by
-- omitting its private-evidence fields.
DO $patch$
DECLARE signature TEXT; definition TEXT; anchor TEXT; guard TEXT;
BEGIN
 guard:=E'BEGIN\n IF current_setting(''transaction_isolation'') NOT IN (''read committed'',''read uncommitted'') THEN\n  RAISE EXCEPTION ''analysis_history_current_snapshot_required'' USING ERRCODE=''25000''; END IF;\n';
 FOREACH signature IN ARRAY ARRAY[
  'internal.lock_private_capture_dispatch(uuid,uuid)',
  'internal.guard_private_capture_quota_state()',
  'internal.guard_private_capture_invocation()'
 ] LOOP
  definition:=pg_get_functiondef(signature::regprocedure);
  anchor:=E'BEGIN\n';
  IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'private_capture_snapshot_guard_drift'; END IF;
  EXECUTE replace(definition,anchor,guard);
 END LOOP;
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;

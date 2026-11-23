SET lock_timeout='5s';
SET statement_timeout='2min';

-- Refund of an unbound, uncommitted reservation is not dispatch. Preserve the
-- existing maintenance path without allowing stale identity classification,
-- committed settlement, token changes, or reopening a reserved attempt. This
-- exception only skips the isolation precondition: every existing guard still
-- runs, and concurrent modification of the row fails snapshot serialization.
DO $patch$
DECLARE definition TEXT; anchor TEXT; replacement TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.guard_private_capture_quota_state()'::regprocedure);
 anchor:=E'IF current_setting(''transaction_isolation'') NOT IN (''read committed'',''read uncommitted'') THEN\n  RAISE EXCEPTION ''analysis_history_current_snapshot_required'' USING ERRCODE=''25000''; END IF;';
 replacement:=E'IF current_setting(''transaction_isolation'') NOT IN (''read committed'',''read uncommitted'') THEN\n  IF TG_OP<>''UPDATE'' THEN\n   RAISE EXCEPTION ''analysis_history_current_snapshot_required'' USING ERRCODE=''25000''; END IF;\n  IF NOT (OLD.state=''reserved'' AND NEW.state=''refunded''\n   AND OLD.original_analysis_id IS NULL AND NEW.original_analysis_id IS NULL\n   AND NEW.refund_count=OLD.refund_count+1\n   AND (to_jsonb(NEW)-ARRAY[''state'',''refunded_at'',''refund_count'',''updated_at''])\n    IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY[''state'',''refunded_at'',''refund_count'',''updated_at''])) THEN\n   RAISE EXCEPTION ''analysis_history_current_snapshot_required'' USING ERRCODE=''25000''; END IF;\n END IF;';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'private_capture_refund_snapshot_guard_drift'; END IF;
 EXECUTE replace(definition,anchor,replacement);
END;
$patch$;

RESET statement_timeout;
RESET lock_timeout;

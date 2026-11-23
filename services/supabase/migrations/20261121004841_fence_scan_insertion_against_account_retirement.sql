SET lock_timeout='5s';
SET statement_timeout='2min';

-- Finalization inserts and account-deletion intake are separate requests.
-- Fence at the actual INSERT, not only at a prior claim/read. Apply to every
-- owned insert: retirement may already have erased private-origin classifiers.
CREATE FUNCTION internal.guard_scan_account_retirement()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.user_id IS NOT NULL THEN
  -- Some callers already hold the owner row; never wait in reverse order on
  -- intake's retirement fence. A busy writer retries without inserting a scan.
  IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:'||NEW.user_id::TEXT,0)) THEN
   RAISE EXCEPTION 'capture_owner_unavailable' USING ERRCODE='55000'; END IF;
  IF EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=NEW.user_id) THEN
   RAISE EXCEPTION 'capture_owner_unavailable' USING ERRCODE='55000'; END IF;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_scan_account_retirement() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a00000_guard_scan_account_retirement BEFORE INSERT ON public.scans
 FOR EACH ROW EXECUTE FUNCTION internal.guard_scan_account_retirement();

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
 definition:=pg_get_functiondef('internal.private_capture_finalization_ready(uuid,uuid)'::regprocedure);
 anchor:='BEGIN';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'private_finalization_retirement_fence_drift'; END IF;
 EXECUTE replace(definition,anchor,$body$
BEGIN
 IF NOT pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('merian-capture-account-retirement:'||p_owner::TEXT,0)) THEN RETURN FALSE; END IF;
$body$);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;

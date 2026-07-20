-- Repair early production scan_media_assets deployments that retained the
-- original table-level UNIQUE (scan_id, order_index) constraint. That broader
-- constraint prevents a promoted capture-upload audit row from coexisting with
-- the generated ready row for the same scan position, so the hourly
-- reconciliation worker retries the same assets indefinitely.

ALTER TABLE IF EXISTS public.scan_media_assets
    DROP CONSTRAINT IF EXISTS scan_media_assets_scan_id_order_index_key;

-- Recreate the intended source-aware uniqueness rules explicitly. Dropping the
-- named indexes first also repairs a deployment where an earlier draft created
-- either name with a different definition; the migration is transactional, so
-- callers never observe an unconstrained committed state.
DROP INDEX IF EXISTS public.idx_scan_media_assets_generated_unique;
CREATE UNIQUE INDEX idx_scan_media_assets_generated_unique
    ON public.scan_media_assets(scan_id, source, role, order_index)
    WHERE scan_id IS NOT NULL AND source IN ('scan_refresh', 'backfill');

DROP INDEX IF EXISTS public.idx_scan_media_assets_upload_session_unique;
CREATE UNIQUE INDEX idx_scan_media_assets_upload_session_unique
    ON public.scan_media_assets(upload_session_id, order_index)
    WHERE upload_session_id IS NOT NULL;

COMMENT ON INDEX public.idx_scan_media_assets_generated_unique IS
  'Prevents duplicate generated media positions within a source and role while allowing capture-upload lifecycle audit rows to coexist.';

COMMENT ON INDEX public.idx_scan_media_assets_upload_session_unique IS
  'Prevents duplicate media positions within a staged upload session.';

NOTIFY pgrst, 'reload schema';

-- Repair early scan_media_assets deployments that made scan_id NOT NULL.
--
-- Staged capture uploads are created before public.scans exists, then promoted
-- to the final scan row after identify persistence succeeds. Those staged rows
-- are keyed by (user_id, client_scan_id, upload_session_id) and must be allowed
-- to have scan_id = NULL until promotion.

ALTER TABLE IF EXISTS public.scan_media_assets
    ALTER COLUMN scan_id DROP NOT NULL;

COMMENT ON COLUMN public.scan_media_assets.scan_id IS
    'Final scan UUID for promoted or ready media. NULL is valid for staged capture_upload rows before scan persistence.';

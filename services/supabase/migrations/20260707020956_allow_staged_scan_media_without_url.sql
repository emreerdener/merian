-- Repair early scan_media_assets deployments that made url NOT NULL.
--
-- /generate-upload-urls creates capture_upload rows before public media URLs
-- exist. Those staged rows are keyed by user_id, client_scan_id,
-- upload_session_id, and storage_key; ready/promoted visible rows keep their
-- URL requirements through table check constraints.

ALTER TABLE IF EXISTS public.scan_media_assets
    ALTER COLUMN url DROP NOT NULL;

COMMENT ON COLUMN public.scan_media_assets.url IS
    'Current public media URL. Required for ready display/playback and promoted capture_upload assets; staged and failed rows may only have storage_key or diagnostics.';

NOTIFY pgrst, 'reload schema';

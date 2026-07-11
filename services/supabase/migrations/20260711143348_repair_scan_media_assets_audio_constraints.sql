-- Repair early production scan_media_assets tables created before standalone
-- audio became a durable media kind. CREATE TABLE IF NOT EXISTS cannot update
-- constraints on an already-existing table, so replace the full related set.

ALTER TABLE public.scan_media_assets
    DROP CONSTRAINT IF EXISTS scan_media_assets_kind_check,
    DROP CONSTRAINT IF EXISTS scan_media_assets_role_check,
    DROP CONSTRAINT IF EXISTS scan_media_assets_kind_role,
    DROP CONSTRAINT IF EXISTS scan_media_assets_ready_visible_url;

ALTER TABLE public.scan_media_assets
    ADD CONSTRAINT scan_media_assets_kind_check
        CHECK (kind IN ('image', 'video', 'audio')) NOT VALID,
    ADD CONSTRAINT scan_media_assets_role_check
        CHECK (role IN ('display', 'playback', 'thumbnail', 'inference_frame', 'audio')) NOT VALID,
    ADD CONSTRAINT scan_media_assets_kind_role
        CHECK (
            (kind = 'image' AND role IN ('display', 'thumbnail', 'inference_frame'))
            OR (kind = 'video' AND role = 'playback')
            OR (kind = 'audio' AND role = 'audio')
        ) NOT VALID,
    ADD CONSTRAINT scan_media_assets_ready_visible_url
        CHECK (
            status <> 'ready'
            OR role NOT IN ('display', 'playback', 'audio')
            OR (
                scan_id IS NOT NULL
                AND COALESCE(NULLIF(BTRIM(url), '') IS NOT NULL, FALSE)
            )
        ) NOT VALID;

ALTER TABLE public.scan_media_assets
    VALIDATE CONSTRAINT scan_media_assets_kind_check,
    VALIDATE CONSTRAINT scan_media_assets_role_check,
    VALIDATE CONSTRAINT scan_media_assets_kind_role,
    VALIDATE CONSTRAINT scan_media_assets_ready_visible_url;

DROP INDEX IF EXISTS public.idx_scan_media_assets_scan_ready_order;
CREATE INDEX idx_scan_media_assets_scan_ready_order
    ON public.scan_media_assets(scan_id, order_index)
    WHERE status = 'ready' AND role IN ('display', 'playback', 'audio');

COMMENT ON CONSTRAINT scan_media_assets_kind_check ON public.scan_media_assets IS
  'Durable scan assets support image, playback video, and standalone audio.';

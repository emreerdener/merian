-- Persist the canonical captured-media timeline for scans.
--
-- image_storage_urls and video_storage_urls remain as compatibility/indexing
-- surfaces, but they are lossy for video scans because sampled inference frames
-- and playback clips live in separate arrays. captured_media preserves the
-- app-facing media relationship so video frames do not hydrate as standalone
-- carousel images.

ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS captured_media JSONB;

COMMENT ON COLUMN public.scans.captured_media IS
  'Canonical captured media timeline. Uses the iOS SerializedMediaItem JSON shape; video inference frames may remain in image_storage_urls but should not be rendered as standalone media when captured_media is present.';

-- Store durable Cloudflare URLs for Pro Live Video Scan clips separately from
-- image_storage_urls so reference-image promotion and image thumbnails stay
-- still-image only. Explore snapshots public video media through
-- explore_post_media after share/publish.

ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS video_storage_urls TEXT[] NOT NULL DEFAULT '{}'::TEXT[];

COMMENT ON COLUMN public.scans.video_storage_urls IS
  'Durable Cloudflare URLs for saved short video scan clips. Kept separate from image_storage_urls.';

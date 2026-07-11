-- Durable, fail-closed moderation state for audio shared to Explore.

ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS audio_storage_urls TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE public.explore_post_media
    DROP CONSTRAINT IF EXISTS explore_post_media_kind_check;
ALTER TABLE public.explore_post_media
    ADD CONSTRAINT explore_post_media_kind_check CHECK (kind IN ('image', 'video', 'audio'));

COMMENT ON COLUMN public.scans.audio_storage_urls IS
  'Durable standalone scan audio. It is not Explore content unless an approved share snapshots it into explore_post_media.';

ALTER TABLE public.user_push_devices
    ADD COLUMN IF NOT EXISTS comment_mentions_enabled BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_user_push_devices_user_explore_mentions_active
    ON public.user_push_devices(user_id, explore_enabled, comment_mentions_enabled, is_active);

CREATE INDEX IF NOT EXISTS idx_user_push_devices_user_comment_mentions_active
    ON public.user_push_devices(user_id, comment_mentions_enabled, is_active);

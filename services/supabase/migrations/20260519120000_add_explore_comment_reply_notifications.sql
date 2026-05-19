DO $$
BEGIN
    ALTER TYPE public.explore_notification_type ADD VALUE IF NOT EXISTS 'comment_reply';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

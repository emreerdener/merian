-- Migration: Fix self-like notification trigger updates
-- Updates the explore post like triggers to skip notifying if the user performing the like/unlike is the author of the post.

CREATE OR REPLACE FUNCTION public.trg_explore_notification_like_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    post_owner_id UUID;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.explore_posts WHERE id = NEW.post_id;
    IF NEW.user_id <> post_owner_id THEN
        PERFORM public.sync_like_notification_for_post(NEW.post_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_like_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    post_owner_id UUID;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.explore_posts WHERE id = OLD.post_id;
    IF OLD.user_id <> post_owner_id THEN
        PERFORM public.sync_like_notification_for_post(OLD.post_id);
    END IF;
    RETURN OLD;
END;
$$;

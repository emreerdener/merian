DO $$
BEGIN
    CREATE TYPE public.explore_notification_type AS ENUM ('like_aggregated', 'comment');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.explore_post_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    type public.explore_notification_type NOT NULL,
    comment_id UUID REFERENCES public.explore_post_comments(id) ON DELETE CASCADE,
    triggering_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    recent_actor_ids UUID[] NOT NULL DEFAULT '{}'::UUID[],
    action_count INTEGER NOT NULL DEFAULT 1 CHECK (action_count >= 0),
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT explore_post_notifications_comment_shape CHECK (
        (
            type = 'comment'
            AND comment_id IS NOT NULL
            AND triggering_user_id IS NOT NULL
            AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
            AND action_count = 1
        )
        OR (
            type = 'like_aggregated'
            AND comment_id IS NULL
            AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
        )
    )
);

ALTER TABLE public.explore_post_notifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'explore_post_notifications'
          AND policyname = 'Users can read their own explore notifications'
    ) THEN
        CREATE POLICY "Users can read their own explore notifications"
            ON public.explore_post_notifications
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'explore_post_notifications'
          AND policyname = 'Users can update their own explore notifications'
    ) THEN
        CREATE POLICY "Users can update their own explore notifications"
            ON public.explore_post_notifications
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_explore_notifications_user_updated_at
    ON public.explore_post_notifications(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_explore_notifications_user_is_read
    ON public.explore_post_notifications(user_id, is_read);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_like_unique
    ON public.explore_post_notifications(user_id, post_id, type)
    WHERE type = 'like_aggregated';

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_comment_unique
    ON public.explore_post_notifications(comment_id)
    WHERE type = 'comment' AND comment_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_like_notification_for_post(target_post_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
    total_count INTEGER;
    recent_actor_ids UUID[];
    latest_actor_id UUID;
BEGIN
    SELECT ep.user_id
    INTO recipient_id
    FROM public.explore_posts ep
    WHERE ep.id = target_post_id
      AND ep.unshared_at IS NULL;

    IF recipient_id IS NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE post_id = target_post_id
          AND type = 'like_aggregated';
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO total_count
    FROM public.explore_post_likes epl
    WHERE epl.post_id = target_post_id
      AND epl.user_id <> recipient_id;

    IF COALESCE(total_count, 0) = 0 THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = recipient_id
          AND post_id = target_post_id
          AND type = 'like_aggregated';
        RETURN;
    END IF;

    recent_actor_ids := COALESCE(ARRAY(
        SELECT epl.user_id
        FROM public.explore_post_likes epl
        WHERE epl.post_id = target_post_id
          AND epl.user_id <> recipient_id
        ORDER BY epl.created_at DESC
        LIMIT 3
    ), ARRAY[]::UUID[]);

    latest_actor_id := recent_actor_ids[1];

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        type,
        triggering_user_id,
        recent_actor_ids,
        action_count,
        is_read,
        created_at,
        updated_at
    )
    VALUES (
        recipient_id,
        target_post_id,
        'like_aggregated',
        latest_actor_id,
        recent_actor_ids,
        total_count,
        FALSE,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, post_id, type)
    WHERE type = 'like_aggregated'
    DO UPDATE SET
        triggering_user_id = EXCLUDED.triggering_user_id,
        recent_actor_ids = EXCLUDED.recent_actor_ids,
        action_count = EXCLUDED.action_count,
        is_read = FALSE,
        updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_like_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.sync_like_notification_for_post(NEW.post_id);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_like_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.sync_like_notification_for_post(OLD.post_id);
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_notification_like_after_insert ON public.explore_post_likes;
CREATE TRIGGER trg_explore_notification_like_after_insert
AFTER INSERT ON public.explore_post_likes
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_like_after_insert();

DROP TRIGGER IF EXISTS trg_explore_notification_like_after_delete ON public.explore_post_likes;
CREATE TRIGGER trg_explore_notification_like_after_delete
AFTER DELETE ON public.explore_post_likes
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_like_after_delete();

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT ep.user_id
    INTO recipient_id
    FROM public.explore_posts ep
    WHERE ep.id = NEW.post_id
      AND ep.unshared_at IS NULL;

    IF recipient_id IS NULL OR recipient_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        type,
        comment_id,
        triggering_user_id,
        recent_actor_ids,
        action_count,
        is_read,
        created_at,
        updated_at
    )
    VALUES (
        recipient_id,
        NEW.post_id,
        'comment',
        NEW.id,
        NEW.user_id,
        ARRAY[]::UUID[],
        1,
        FALSE,
        COALESCE(NEW.created_at, NOW()),
        COALESCE(NEW.created_at, NOW())
    )
    ON CONFLICT (comment_id)
    WHERE type = 'comment' AND comment_id IS NOT NULL
    DO NOTHING;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = NEW.id
          AND type = 'comment';
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
        SELECT ep.user_id
        INTO recipient_id
        FROM public.explore_posts ep
        WHERE ep.id = NEW.post_id
          AND ep.unshared_at IS NULL;

        IF recipient_id IS NOT NULL AND recipient_id <> NEW.user_id THEN
            INSERT INTO public.explore_post_notifications (
                user_id,
                post_id,
                type,
                comment_id,
                triggering_user_id,
                recent_actor_ids,
                action_count,
                is_read,
                created_at,
                updated_at
            )
            VALUES (
                recipient_id,
                NEW.post_id,
                'comment',
                NEW.id,
                NEW.user_id,
                ARRAY[]::UUID[],
                1,
                FALSE,
                COALESCE(NEW.created_at, NOW()),
                COALESCE(NEW.created_at, NOW())
            )
            ON CONFLICT (comment_id)
            WHERE type = 'comment' AND comment_id IS NOT NULL
            DO NOTHING;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_notification_comment_after_insert ON public.explore_post_comments;
CREATE TRIGGER trg_explore_notification_comment_after_insert
AFTER INSERT ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_comment_after_insert();

DROP TRIGGER IF EXISTS trg_explore_notification_comment_after_update ON public.explore_post_comments;
CREATE TRIGGER trg_explore_notification_comment_after_update
AFTER UPDATE ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_comment_after_update();

CREATE OR REPLACE FUNCTION public.trg_explore_notification_post_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.unshared_at IS NULL AND NEW.unshared_at IS NOT NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE post_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_notification_post_after_update ON public.explore_posts;
CREATE TRIGGER trg_explore_notification_post_after_update
AFTER UPDATE ON public.explore_posts
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_post_after_update();

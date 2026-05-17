CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

CREATE TABLE IF NOT EXISTS public.user_push_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL CHECK (device_token ~ '^[A-Fa-f0-9]{32,512}$'),
    platform TEXT NOT NULL CHECK (platform IN ('ios')),
    environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
    explore_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error_at TIMESTAMPTZ,
    last_error_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_push_devices ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_push_devices'
          AND policyname = 'Users can read their own push devices'
    ) THEN
        CREATE POLICY "Users can read their own push devices"
            ON public.user_push_devices
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_push_devices'
          AND policyname = 'Users can update their own push devices'
    ) THEN
        CREATE POLICY "Users can update their own push devices"
            ON public.user_push_devices
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_push_devices_token_platform_environment
    ON public.user_push_devices(device_token, platform, environment);

CREATE INDEX IF NOT EXISTS idx_user_push_devices_user_platform_environment
    ON public.user_push_devices(user_id, platform, environment);

CREATE INDEX IF NOT EXISTS idx_user_push_devices_user_explore_active
    ON public.user_push_devices(user_id, explore_enabled, is_active);

CREATE OR REPLACE FUNCTION public.trg_user_push_devices_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_push_devices_set_updated_at ON public.user_push_devices;
CREATE TRIGGER trg_user_push_devices_set_updated_at
BEFORE UPDATE ON public.user_push_devices
FOR EACH ROW
EXECUTE FUNCTION public.trg_user_push_devices_set_updated_at();

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    comment_body TEXT,
    triggering_user_name TEXT,
    recent_actor_names TEXT[]
)
LANGUAGE SQL
STABLE
AS $$
    WITH visible_notification AS (
        SELECT n.*
        FROM public.explore_post_notifications n
        JOIN public.explore_posts ep
            ON ep.id = n.post_id
        JOIN public.scans s
            ON s.id = ep.scan_id
        JOIN public.users owner
            ON owner.id = ep.user_id
        LEFT JOIN public.explore_post_comments c
            ON c.id = n.comment_id
        WHERE n.id = target_notification_id
          AND ep.user_id = n.user_id
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND owner.is_shadowbanned = FALSE
          AND (
              n.type <> 'comment'
              OR (
                  c.id IS NOT NULL
                  AND c.deleted_at IS NULL
                  AND n.triggering_user_id IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks ub
                      WHERE (ub.blocker_id = n.user_id AND ub.blocked_id = n.triggering_user_id)
                         OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = n.user_id)
                  )
              )
          )
    )
    SELECT
        n.id AS notification_id,
        n.user_id AS recipient_user_id,
        n.post_id,
        n.type,
        n.action_count,
        c.body AS comment_body,
        CASE
            WHEN n.type = 'comment' THEN actor.public_author_name
            WHEN COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0 THEN actor_names.recent_actor_names[1]
            ELSE actor.public_author_name
        END AS triggering_user_name,
        COALESCE(actor_names.recent_actor_names, ARRAY[]::TEXT[]) AS recent_actor_names
    FROM visible_notification n
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
       AND c.deleted_at IS NULL
    LEFT JOIN public.users actor
        ON actor.id = n.triggering_user_id
    LEFT JOIN LATERAL (
        SELECT COALESCE(
            array_agg(u.public_author_name ORDER BY actor_ids.ord),
            ARRAY[]::TEXT[]
        ) AS recent_actor_names
        FROM unnest(n.recent_actor_ids) WITH ORDINALITY AS actor_ids(actor_id, ord)
        JOIN public.users u
            ON u.id = actor_ids.actor_id
        WHERE u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = n.user_id AND ub.blocked_id = u.id)
                 OR (ub.blocker_id = u.id AND ub.blocked_id = n.user_id)
          )
    ) actor_names ON TRUE
    WHERE (
        n.type <> 'like_aggregated'
        OR COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0
    );
$$;

CREATE OR REPLACE FUNCTION public.trigger_explore_notification_push_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    project_url TEXT;
    service_role_key TEXT;
    edge_endpoint TEXT;
    should_dispatch BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        should_dispatch := TRUE;
    ELSIF TG_OP = 'UPDATE' THEN
        should_dispatch := NEW.type = 'like_aggregated'
            AND COALESCE(NEW.action_count, 0) > COALESCE(OLD.action_count, 0);
    END IF;

    IF NOT should_dispatch THEN
        RETURN NEW;
    END IF;

    SELECT decrypted_secret INTO project_url
    FROM vault.decrypted_secrets
    WHERE name = 'SUPABASE_URL'
    LIMIT 1;

    SELECT decrypted_secret INTO service_role_key
    FROM vault.decrypted_secrets
    WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
    LIMIT 1;

    IF project_url IS NULL THEN
        project_url := current_setting('app.settings.supabase_url', true);
    END IF;

    IF service_role_key IS NULL THEN
        service_role_key := current_setting('app.settings.service_role_key', true);
    END IF;

    IF project_url IS NULL OR service_role_key IS NULL THEN
        RAISE NOTICE 'Explore push delivery skipped because Supabase edge settings were unavailable.';
        RETURN NEW;
    END IF;

    edge_endpoint := project_url || '/functions/v1/send-push-notification';

    PERFORM net.http_post(
        url := edge_endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object('notification_id', NEW.id)
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_notification_push_delivery ON public.explore_post_notifications;
CREATE TRIGGER trg_explore_notification_push_delivery
AFTER INSERT OR UPDATE OF action_count ON public.explore_post_notifications
FOR EACH ROW
EXECUTE FUNCTION public.trigger_explore_notification_push_delivery();

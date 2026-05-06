ALTER TABLE public.explore_post_notifications
ADD COLUMN IF NOT EXISTS reaction_emoji TEXT;

ALTER TABLE public.explore_post_notifications
DROP CONSTRAINT IF EXISTS explore_post_notifications_comment_shape;

ALTER TABLE public.explore_post_notifications
ADD CONSTRAINT explore_post_notifications_comment_shape CHECK (
    (
        type = 'comment'
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'like_aggregated'
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
    )
    OR (
        type = 'comment_reaction'
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NOT NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
        AND action_count >= 1
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_comment_reaction_unique
    ON public.explore_post_notifications(user_id, comment_id, reaction_emoji)
    WHERE type = 'comment_reaction' AND comment_id IS NOT NULL AND reaction_emoji IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_comment_reaction_notification_for_comment(
    target_comment_id UUID,
    target_emoji TEXT,
    mark_unread BOOLEAN DEFAULT TRUE
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
    target_post_id UUID;
    total_count INTEGER;
    recent_actor_ids UUID[];
    latest_actor_id UUID;
BEGIN
    SELECT
        c.user_id,
        c.post_id
    INTO
        recipient_id,
        target_post_id
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    WHERE c.id = target_comment_id
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL
      AND ep.unshared_at IS NULL;

    IF recipient_id IS NULL OR target_post_id IS NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = target_comment_id
          AND type = 'comment_reaction'
          AND reaction_emoji = target_emoji;
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO total_count
    FROM public.explore_comment_reactions r
    WHERE r.comment_id = target_comment_id
      AND r.emoji = target_emoji
      AND r.user_id <> recipient_id;

    IF COALESCE(total_count, 0) = 0 THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = recipient_id
          AND comment_id = target_comment_id
          AND type = 'comment_reaction'
          AND reaction_emoji = target_emoji;
        RETURN;
    END IF;

    recent_actor_ids := COALESCE(ARRAY(
        SELECT r.user_id
        FROM public.explore_comment_reactions r
        WHERE r.comment_id = target_comment_id
          AND r.emoji = target_emoji
          AND r.user_id <> recipient_id
        ORDER BY r.created_at DESC
        LIMIT 3
    ), ARRAY[]::UUID[]);

    latest_actor_id := recent_actor_ids[1];

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        type,
        comment_id,
        reaction_emoji,
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
        'comment_reaction',
        target_comment_id,
        target_emoji,
        latest_actor_id,
        recent_actor_ids,
        total_count,
        FALSE,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, comment_id, reaction_emoji)
    WHERE type = 'comment_reaction' AND comment_id IS NOT NULL AND reaction_emoji IS NOT NULL
    DO UPDATE SET
        post_id = EXCLUDED.post_id,
        triggering_user_id = EXCLUDED.triggering_user_id,
        recent_actor_ids = EXCLUDED.recent_actor_ids,
        action_count = EXCLUDED.action_count,
        is_read = CASE
            WHEN mark_unread THEN FALSE
            ELSE explore_post_notifications.is_read
        END,
        updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
    reaction_row RECORD;
    old_visible BOOLEAN := OLD.deleted_at IS NULL AND OLD.moderated_at IS NULL;
    new_visible BOOLEAN := NEW.deleted_at IS NULL AND NEW.moderated_at IS NULL;
BEGIN
    IF old_visible AND NOT new_visible THEN
        DELETE FROM public.explore_post_notifications
        WHERE comment_id = NEW.id
          AND type IN ('comment', 'comment_reaction');
    ELSIF NOT old_visible AND new_visible THEN
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

        FOR reaction_row IN
            SELECT DISTINCT r.emoji
            FROM public.explore_comment_reactions r
            WHERE r.comment_id = NEW.id
        LOOP
            PERFORM public.sync_comment_reaction_notification_for_comment(
                NEW.id,
                reaction_row.emoji,
                TRUE
            );
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_reaction_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
BEGIN
    SELECT c.user_id
    INTO recipient_id
    FROM public.explore_post_comments c
    WHERE c.id = NEW.comment_id;

    IF recipient_id IS NULL OR recipient_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    PERFORM public.sync_comment_reaction_notification_for_comment(
        NEW.comment_id,
        NEW.emoji,
        TRUE
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_notification_comment_reaction_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    recipient_id UUID;
BEGIN
    SELECT c.user_id
    INTO recipient_id
    FROM public.explore_post_comments c
    WHERE c.id = OLD.comment_id;

    IF recipient_id IS NULL OR recipient_id = OLD.user_id THEN
        RETURN OLD;
    END IF;

    PERFORM public.sync_comment_reaction_notification_for_comment(
        OLD.comment_id,
        OLD.emoji,
        FALSE
    );

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_notification_comment_reaction_after_insert ON public.explore_comment_reactions;
CREATE TRIGGER trg_explore_notification_comment_reaction_after_insert
AFTER INSERT ON public.explore_comment_reactions
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_comment_reaction_after_insert();

DROP TRIGGER IF EXISTS trg_explore_notification_comment_reaction_after_delete ON public.explore_comment_reactions;
CREATE TRIGGER trg_explore_notification_comment_reaction_after_delete
AFTER DELETE ON public.explore_comment_reactions
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_notification_comment_reaction_after_delete();

DROP FUNCTION IF EXISTS public.get_explore_notifications(UUID, INTEGER, TIMESTAMPTZ, UUID);

CREATE OR REPLACE FUNCTION public.get_explore_notifications(
    self_id UUID,
    max_limit INTEGER DEFAULT 50,
    before_updated_at TIMESTAMPTZ DEFAULT NULL,
    before_notification_id UUID DEFAULT NULL
)
RETURNS TABLE(
    notification_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    comment_id UUID,
    reaction_emoji TEXT,
    triggering_user_id UUID,
    triggering_user_name TEXT,
    comment_body TEXT,
    recent_actor_names TEXT[],
    action_count INTEGER,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
AS $$
    WITH visible_notifications AS (
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
        WHERE n.user_id = self_id
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND owner.is_shadowbanned = FALSE
          AND (
              n.type = 'like_aggregated'
              OR (
                  c.id IS NOT NULL
                  AND c.deleted_at IS NULL
                  AND c.moderated_at IS NULL
                  AND (
                      (
                          n.type = 'comment'
                          AND n.triggering_user_id IS NOT NULL
                          AND NOT EXISTS (
                              SELECT 1
                              FROM public.user_blocks ub
                              WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                                 OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                          )
                      )
                      OR (
                          n.type = 'comment_reaction'
                          AND n.reaction_emoji IS NOT NULL
                      )
                  )
              )
          )
    )
    SELECT
        n.id AS notification_id,
        n.post_id,
        n.type,
        n.comment_id,
        n.reaction_emoji,
        n.triggering_user_id,
        CASE
            WHEN n.type = 'comment' THEN actor.public_author_name
            WHEN COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0 THEN actor_names.recent_actor_names[1]
            ELSE NULL
        END AS triggering_user_name,
        c.body AS comment_body,
        COALESCE(actor_names.recent_actor_names, ARRAY[]::TEXT[]) AS recent_actor_names,
        n.action_count,
        n.is_read,
        n.created_at,
        n.updated_at
    FROM visible_notifications n
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
       AND c.deleted_at IS NULL
       AND c.moderated_at IS NULL
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
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = u.id)
                 OR (ub.blocker_id = u.id AND ub.blocked_id = self_id)
          )
    ) actor_names ON TRUE
    WHERE (
            before_updated_at IS NULL
            OR n.updated_at < before_updated_at
            OR (n.updated_at = before_updated_at AND n.id < before_notification_id)
        )
      AND (
            n.type <> 'comment_reaction'
            OR COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0
        )
    ORDER BY n.updated_at DESC, n.id DESC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0);
$$;

DROP FUNCTION IF EXISTS public.get_unread_explore_notification_count(UUID);

CREATE OR REPLACE FUNCTION public.get_unread_explore_notification_count(self_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.explore_post_notifications n
    JOIN public.explore_posts ep
        ON ep.id = n.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users owner
        ON owner.id = ep.user_id
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
    WHERE n.user_id = self_id
      AND n.is_read = FALSE
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND owner.is_shadowbanned = FALSE
      AND (
          n.type = 'like_aggregated'
          OR (
              c.id IS NOT NULL
              AND c.deleted_at IS NULL
              AND c.moderated_at IS NULL
              AND (
                  (
                      n.type = 'comment'
                      AND n.triggering_user_id IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM public.user_blocks ub
                          WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                             OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                      )
                  )
                  OR (
                      n.type = 'comment_reaction'
                      AND n.reaction_emoji IS NOT NULL
                      AND EXISTS (
                          SELECT 1
                          FROM unnest(n.recent_actor_ids) AS actor_ids(actor_id)
                          JOIN public.users u
                              ON u.id = actor_ids.actor_id
                          WHERE u.is_shadowbanned = FALSE
                            AND NOT EXISTS (
                                SELECT 1
                                FROM public.user_blocks ub
                                WHERE (ub.blocker_id = self_id AND ub.blocked_id = u.id)
                                   OR (ub.blocker_id = u.id AND ub.blocked_id = self_id)
                            )
                      )
                  )
              )
          )
      );
$$;

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    reaction_emoji TEXT,
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
          AND ep.unshared_at IS NULL
          AND s.is_tombstoned = FALSE
          AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
          AND s.geoprivacy <> 'private'
          AND owner.is_shadowbanned = FALSE
          AND (
              n.type = 'like_aggregated'
              OR (
                  c.id IS NOT NULL
                  AND c.deleted_at IS NULL
                  AND c.moderated_at IS NULL
                  AND (
                      (
                          n.type = 'comment'
                          AND n.triggering_user_id IS NOT NULL
                          AND NOT EXISTS (
                              SELECT 1
                              FROM public.user_blocks ub
                              WHERE (ub.blocker_id = n.user_id AND ub.blocked_id = n.triggering_user_id)
                                 OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = n.user_id)
                          )
                      )
                      OR (
                          n.type = 'comment_reaction'
                          AND n.reaction_emoji IS NOT NULL
                      )
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
        n.reaction_emoji,
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
       AND c.moderated_at IS NULL
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
        )
      AND (
            n.type <> 'comment_reaction'
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
        should_dispatch := NEW.type IN ('like_aggregated', 'comment_reaction')
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

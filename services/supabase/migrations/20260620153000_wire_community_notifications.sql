ALTER TABLE public.user_push_devices
ADD COLUMN IF NOT EXISTS community_identifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_user_push_devices_community_identifications
    ON public.user_push_devices(user_id, community_identifications_enabled, is_active);

ALTER TABLE public.explore_post_notifications
ADD COLUMN IF NOT EXISTS community_request_id UUID REFERENCES public.explore_community_requests(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_explore_notifications_community_request
    ON public.explore_post_notifications(community_request_id)
    WHERE community_request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_community_identification_added_unique
    ON public.explore_post_notifications(user_id, community_request_id, type)
    WHERE type = 'community_identification_added';

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_community_request_resolved_unique
    ON public.explore_post_notifications(user_id, community_request_id, type)
    WHERE type = 'community_request_resolved';

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_community_identification_helped_unique
    ON public.explore_post_notifications(user_id, community_request_id, type)
    WHERE type = 'community_identification_helped';

ALTER TABLE public.explore_post_notifications
DROP CONSTRAINT IF EXISTS explore_post_notifications_comment_shape;

ALTER TABLE public.explore_post_notifications
ADD CONSTRAINT explore_post_notifications_comment_shape CHECK (
    (
        type = 'comment'
        AND post_id IS NOT NULL
        AND community_request_id IS NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'comment_reply'
        AND post_id IS NOT NULL
        AND community_request_id IS NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'comment_mention'
        AND post_id IS NOT NULL
        AND community_request_id IS NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'like_aggregated'
        AND post_id IS NOT NULL
        AND community_request_id IS NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
    )
    OR (
        type = 'comment_reaction'
        AND post_id IS NOT NULL
        AND community_request_id IS NULL
        AND comment_id IS NOT NULL
        AND reaction_emoji IS NOT NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
        AND action_count >= 1
    )
    OR (
        type = 'follow'
        AND post_id IS NULL
        AND community_request_id IS NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
    OR (
        type = 'community_identification_added'
        AND post_id IS NOT NULL
        AND community_request_id IS NOT NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NOT NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) <= 3
        AND action_count >= 1
    )
    OR (
        type IN ('community_request_resolved', 'community_identification_helped')
        AND post_id IS NOT NULL
        AND community_request_id IS NOT NULL
        AND comment_id IS NULL
        AND reaction_emoji IS NULL
        AND triggering_user_id IS NULL
        AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
        AND action_count = 1
    )
);

CREATE OR REPLACE FUNCTION public.sync_community_identification_added_notification(target_request_id UUID)
RETURNS void
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_row RECORD;
    total_count INTEGER;
    recent_actor_ids UUID[];
    latest_actor_id UUID;
BEGIN
    SELECT
        ecr.id,
        ecr.post_id,
        ecr.requested_by
    INTO request_row
    FROM public.explore_community_requests ecr
    WHERE ecr.id = target_request_id
      AND ecr.withdrawn_at IS NULL
    LIMIT 1;

    IF request_row.id IS NULL THEN
        DELETE FROM public.explore_post_notifications
        WHERE community_request_id = target_request_id
          AND type = 'community_identification_added';
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO total_count
    FROM public.explore_identifications ei
    JOIN public.users identifier
        ON identifier.id = ei.user_id
    WHERE ei.request_id = target_request_id
      AND ei.withdrawn_at IS NULL
      AND ei.user_id <> request_row.requested_by
      AND identifier.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = request_row.requested_by AND ub.blocked_id = ei.user_id)
             OR (ub.blocker_id = ei.user_id AND ub.blocked_id = request_row.requested_by)
      );

    IF COALESCE(total_count, 0) = 0 THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = request_row.requested_by
          AND community_request_id = target_request_id
          AND type = 'community_identification_added';
        RETURN;
    END IF;

    recent_actor_ids := COALESCE(ARRAY(
        SELECT ei.user_id
        FROM public.explore_identifications ei
        JOIN public.users identifier
            ON identifier.id = ei.user_id
        WHERE ei.request_id = target_request_id
          AND ei.withdrawn_at IS NULL
          AND ei.user_id <> request_row.requested_by
          AND identifier.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = request_row.requested_by AND ub.blocked_id = ei.user_id)
                 OR (ub.blocker_id = ei.user_id AND ub.blocked_id = request_row.requested_by)
          )
        ORDER BY COALESCE(ei.restored_at, ei.created_at) DESC, ei.id DESC
        LIMIT 3
    ), ARRAY[]::UUID[]);

    latest_actor_id := recent_actor_ids[1];

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        community_request_id,
        type,
        triggering_user_id,
        recent_actor_ids,
        action_count,
        is_read,
        updated_at
    )
    VALUES (
        request_row.requested_by,
        request_row.post_id,
        target_request_id,
        'community_identification_added',
        latest_actor_id,
        recent_actor_ids,
        total_count,
        FALSE,
        NOW()
    )
    ON CONFLICT (user_id, community_request_id, type)
    WHERE type = 'community_identification_added'
    DO UPDATE SET
        triggering_user_id = EXCLUDED.triggering_user_id,
        recent_actor_ids = EXCLUDED.recent_actor_ids,
        action_count = EXCLUDED.action_count,
        is_read = CASE
            WHEN EXCLUDED.action_count > public.explore_post_notifications.action_count THEN FALSE
            ELSE public.explore_post_notifications.is_read
        END,
        updated_at = CASE
            WHEN EXCLUDED.action_count IS DISTINCT FROM public.explore_post_notifications.action_count
              OR EXCLUDED.recent_actor_ids IS DISTINCT FROM public.explore_post_notifications.recent_actor_ids
              OR EXCLUDED.triggering_user_id IS DISTINCT FROM public.explore_post_notifications.triggering_user_id
            THEN NOW()
            ELSE public.explore_post_notifications.updated_at
        END;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_community_identification_added_notification_from_identification()
RETURNS trigger
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.sync_community_identification_added_notification(NEW.request_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_community_identification_added_notification ON public.explore_identifications;
CREATE TRIGGER trg_sync_community_identification_added_notification
AFTER INSERT OR UPDATE OF withdrawn_at, restored_at
ON public.explore_identifications
FOR EACH ROW
EXECUTE FUNCTION public.sync_community_identification_added_notification_from_identification();

CREATE OR REPLACE FUNCTION public.create_community_resolution_notifications()
RETURNS trigger
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    request_row RECORD;
BEGIN
    IF NEW.new_status <> 'resolved' OR NEW.new_taxon_node_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        ecr.id,
        ecr.post_id,
        ecr.requested_by,
        resolved_taxon.path AS resolved_path
    INTO request_row
    FROM public.explore_community_requests ecr
    JOIN public.taxon_nodes resolved_taxon
        ON resolved_taxon.id = NEW.new_taxon_node_id
    WHERE ecr.id = NEW.request_id
      AND ecr.withdrawn_at IS NULL
    LIMIT 1;

    IF request_row.id IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        community_request_id,
        type,
        recent_actor_ids,
        action_count,
        is_read
    )
    VALUES (
        request_row.requested_by,
        request_row.post_id,
        request_row.id,
        'community_request_resolved',
        ARRAY[]::UUID[],
        1,
        FALSE
    )
    ON CONFLICT (user_id, community_request_id, type)
    WHERE type = 'community_request_resolved'
    DO NOTHING;

    INSERT INTO public.explore_post_notifications (
        user_id,
        post_id,
        community_request_id,
        type,
        recent_actor_ids,
        action_count,
        is_read
    )
    SELECT DISTINCT
        ei.user_id,
        request_row.post_id,
        request_row.id,
        'community_identification_helped'::public.explore_notification_type,
        ARRAY[]::UUID[],
        1,
        FALSE
    FROM public.explore_identifications ei
    JOIN public.taxon_nodes identified_taxon
        ON identified_taxon.id = ei.taxon_node_id
    JOIN public.users identifier
        ON identifier.id = ei.user_id
    WHERE ei.request_id = request_row.id
      AND ei.withdrawn_at IS NULL
      AND ei.user_id <> request_row.requested_by
      AND identifier.is_shadowbanned = FALSE
      AND (
          identified_taxon.path = request_row.resolved_path
          OR identified_taxon.path <@ request_row.resolved_path
          OR (
              identified_taxon.path @> request_row.resolved_path
              AND ei.disagreement_mode <> 'explicit_disagreement'
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = request_row.requested_by AND ub.blocked_id = ei.user_id)
             OR (ub.blocker_id = ei.user_id AND ub.blocked_id = request_row.requested_by)
      )
    ON CONFLICT (user_id, community_request_id, type)
    WHERE type = 'community_identification_helped'
    DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_community_resolution_notifications ON public.community_consensus_events;
CREATE TRIGGER trg_create_community_resolution_notifications
AFTER INSERT
ON public.community_consensus_events
FOR EACH ROW
EXECUTE FUNCTION public.create_community_resolution_notifications();

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);
DROP FUNCTION IF EXISTS public.get_unread_explore_notification_count(UUID);
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
    community_request_id UUID,
    type public.explore_notification_type,
    comment_id UUID,
    parent_comment_id UUID,
    reaction_emoji TEXT,
    triggering_user_id UUID,
    triggering_user_name TEXT,
    comment_body TEXT,
    recent_actor_names TEXT[],
    action_count INTEGER,
    is_read BOOLEAN,
    is_reply_to_viewer_comment BOOLEAN,
    community_taxon_common_name TEXT,
    community_taxon_scientific_name TEXT,
    community_request_display_name TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
AS $$
    WITH visible_notifications AS (
        SELECT n.*
        FROM public.explore_post_notifications n
        LEFT JOIN public.explore_posts ep
            ON ep.id = n.post_id
        LEFT JOIN public.scans s
            ON s.id = ep.scan_id
        LEFT JOIN public.users owner
            ON owner.id = ep.user_id
        LEFT JOIN public.explore_community_requests ecr
            ON ecr.id = n.community_request_id
        LEFT JOIN public.explore_post_comments c
            ON c.id = n.comment_id
        LEFT JOIN public.explore_post_comments parent
            ON parent.id = c.parent_comment_id
        LEFT JOIN public.users actor
            ON actor.id = n.triggering_user_id
        WHERE n.user_id = self_id
          AND (
              (
                  n.type = 'follow'
                  AND n.post_id IS NULL
                  AND n.triggering_user_id IS NOT NULL
                  AND actor.id IS NOT NULL
                  AND actor.is_shadowbanned = FALSE
                  AND EXISTS (
                      SELECT 1
                      FROM public.user_follows uf
                      WHERE uf.follower_user_id = n.triggering_user_id
                        AND uf.followee_user_id = n.user_id
                  )
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks ub
                      WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.triggering_user_id)
                         OR (ub.blocker_id = n.triggering_user_id AND ub.blocked_id = self_id)
                  )
              )
              OR (
                  n.type <> 'follow'
                  AND n.post_id IS NOT NULL
                  AND ep.id IS NOT NULL
                  AND ep.unshared_at IS NULL
                  AND s.is_tombstoned = FALSE
                  AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
                  AND s.geoprivacy <> 'private'
                  AND owner.is_shadowbanned = FALSE
                  AND (
                      n.type = 'like_aggregated'
                      OR (
                          n.type IN (
                              'community_identification_added',
                              'community_request_resolved',
                              'community_identification_helped'
                          )
                          AND n.community_request_id IS NOT NULL
                          AND ecr.id IS NOT NULL
                          AND ecr.withdrawn_at IS NULL
                          AND NOT EXISTS (
                              SELECT 1
                              FROM public.user_blocks ub
                              WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
                                 OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
                          )
                          AND (
                              n.type <> 'community_identification_added'
                              OR (
                                  n.triggering_user_id IS NOT NULL
                                  AND actor.id IS NOT NULL
                                  AND actor.is_shadowbanned = FALSE
                              )
                          )
                      )
                      OR (
                          c.id IS NOT NULL
                          AND c.deleted_at IS NULL
                          AND c.moderated_at IS NULL
                          AND (
                              c.parent_comment_id IS NULL
                              OR (
                                  parent.id IS NOT NULL
                                  AND parent.parent_comment_id IS NULL
                                  AND parent.deleted_at IS NULL
                                  AND parent.moderated_at IS NULL
                              )
                          )
                          AND (
                              (
                                  n.type IN ('comment', 'comment_reply', 'comment_mention')
                                  AND n.triggering_user_id IS NOT NULL
                                  AND actor.id IS NOT NULL
                                  AND actor.is_shadowbanned = FALSE
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
          )
    )
    SELECT
        n.id AS notification_id,
        n.post_id,
        n.community_request_id,
        n.type,
        n.comment_id,
        c.parent_comment_id,
        n.reaction_emoji,
        n.triggering_user_id,
        CASE
            WHEN n.type IN ('comment', 'comment_reply', 'comment_mention', 'follow') THEN actor.public_author_name
            WHEN COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0 THEN actor_names.recent_actor_names[1]
            ELSE NULL
        END AS triggering_user_name,
        c.body AS comment_body,
        COALESCE(actor_names.recent_actor_names, ARRAY[]::TEXT[]) AS recent_actor_names,
        n.action_count,
        n.is_read,
        (n.type = 'comment_reply' AND parent.user_id = self_id) AS is_reply_to_viewer_comment,
        display_taxon.common_name AS community_taxon_common_name,
        display_taxon.scientific_name AS community_taxon_scientific_name,
        COALESCE(
            NULLIF(BTRIM(display_taxon.common_name), ''),
            NULLIF(BTRIM(display_taxon.scientific_name), ''),
            NULLIF(BTRIM(initial_taxon.common_name), ''),
            NULLIF(BTRIM(initial_taxon.scientific_name), ''),
            'Community request'
        ) AS community_request_display_name,
        n.created_at,
        n.updated_at
    FROM visible_notifications n
    LEFT JOIN public.explore_post_comments c
        ON c.id = n.comment_id
       AND c.deleted_at IS NULL
       AND c.moderated_at IS NULL
    LEFT JOIN public.explore_post_comments parent
        ON parent.id = c.parent_comment_id
       AND parent.deleted_at IS NULL
       AND parent.moderated_at IS NULL
    LEFT JOIN public.users actor
        ON actor.id = n.triggering_user_id
    LEFT JOIN public.explore_community_requests ecr
        ON ecr.id = n.community_request_id
    LEFT JOIN public.taxon_nodes display_taxon
        ON display_taxon.id = COALESCE(
            ecr.resolved_taxon_node_id,
            ecr.current_community_taxon_node_id,
            ecr.initial_taxon_node_id
        )
    LEFT JOIN public.taxon_nodes initial_taxon
        ON initial_taxon.id = ecr.initial_taxon_node_id
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
            OR before_notification_id IS NULL
            OR n.updated_at < before_updated_at
            OR (n.updated_at = before_updated_at AND n.id < before_notification_id)
        )
      AND (
            n.type NOT IN ('comment_reaction', 'community_identification_added')
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
    FROM public.get_explore_notifications(self_id, 1000000, NULL, NULL) n
    WHERE n.is_read = FALSE;
$$;

DROP FUNCTION IF EXISTS public.get_explore_push_notification_payload(UUID);

CREATE OR REPLACE FUNCTION public.get_explore_push_notification_payload(target_notification_id UUID)
RETURNS TABLE(
    notification_id UUID,
    recipient_user_id UUID,
    post_id UUID,
    community_request_id UUID,
    comment_id UUID,
    parent_comment_id UUID,
    type public.explore_notification_type,
    action_count INTEGER,
    reaction_emoji TEXT,
    comment_body TEXT,
    triggering_user_name TEXT,
    recent_actor_names TEXT[],
    is_reply_to_viewer_comment BOOLEAN,
    community_taxon_common_name TEXT,
    community_taxon_scientific_name TEXT,
    community_request_display_name TEXT,
    unread_count INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        n.notification_id,
        epn.user_id AS recipient_user_id,
        n.post_id,
        n.community_request_id,
        n.comment_id,
        n.parent_comment_id,
        n.type,
        n.action_count,
        n.reaction_emoji,
        n.comment_body,
        n.triggering_user_name,
        n.recent_actor_names,
        n.is_reply_to_viewer_comment,
        n.community_taxon_common_name,
        n.community_taxon_scientific_name,
        n.community_request_display_name,
        public.get_unread_explore_notification_count(epn.user_id) AS unread_count
    FROM public.explore_post_notifications epn
    JOIN LATERAL public.get_explore_notifications(epn.user_id, 1000000, NULL, NULL) n
        ON n.notification_id = epn.id
    WHERE epn.id = target_notification_id
      AND n.type <> 'follow';
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
        should_dispatch := NEW.type <> 'follow';
    ELSIF TG_OP = 'UPDATE' THEN
        should_dispatch := NEW.type IN ('like_aggregated', 'comment_reaction', 'community_identification_added')
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
        service_role_key := current_setting('app.settings.supabase_service_role_key', true);
    END IF;

    IF project_url IS NULL OR service_role_key IS NULL THEN
        RAISE WARNING 'Explore push delivery skipped: missing Supabase URL or service role key.';
        RETURN NEW;
    END IF;

    edge_endpoint := RTRIM(project_url, '/') || '/functions/v1/send-push-notification';

    PERFORM net.http_post(
        url := edge_endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object('notification_id', NEW.id),
        timeout_milliseconds := 5000
    );

    RETURN NEW;
END;
$$;

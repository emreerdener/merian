COMMENT ON TABLE public.field_trip_publications IS
    'Field Trip-scoped published pages. Publishing here does not create Explore posts, map points, widgets, APNs, or normal Explore post notifications; V3 may create Field Trip-only in-app activity rows.';

CREATE TABLE IF NOT EXISTS public.field_trip_activity_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    actor_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    publication_id UUID NOT NULL REFERENCES public.field_trip_publications(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES public.field_trip_publication_comments(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (
        type IN (
            'field_trip_comment',
            'field_trip_reply',
            'field_trip_followed_publication'
        )
    ),
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

COMMENT ON TABLE public.field_trip_activity_notifications IS
    'Field Trip-only in-app activity rows surfaced in Explore activity. These rows never fan out to APNs, widgets, Explore feed cards, map rows, or explore_posts.';

CREATE INDEX IF NOT EXISTS idx_field_trip_activity_user_unread
    ON public.field_trip_activity_notifications(user_id, read_at, updated_at DESC, id DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_activity_publication
    ON public.field_trip_activity_notifications(publication_id)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_activity_comment
    ON public.field_trip_activity_notifications(comment_id)
    WHERE comment_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_activity_actor
    ON public.field_trip_activity_notifications(actor_user_id, updated_at DESC)
    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_field_trip_activity_followed_publication_unique
    ON public.field_trip_activity_notifications(user_id, actor_user_id, publication_id, type)
    WHERE type = 'field_trip_followed_publication' AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_field_trip_activity_comment_unique
    ON public.field_trip_activity_notifications(user_id, comment_id, type)
    WHERE type IN ('field_trip_comment', 'field_trip_reply') AND deleted_at IS NULL;

ALTER TABLE public.field_trip_activity_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own Field Trip activity" ON public.field_trip_activity_notifications;
CREATE POLICY "Users can view own Field Trip activity"
    ON public.field_trip_activity_notifications
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can mark own Field Trip activity read" ON public.field_trip_activity_notifications;
CREATE POLICY "Users can mark own Field Trip activity read"
    ON public.field_trip_activity_notifications
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own Field Trip activity" ON public.field_trip_activity_notifications;
CREATE POLICY "Users can delete own Field Trip activity"
    ON public.field_trip_activity_notifications
    FOR DELETE
    USING (auth.uid() = user_id);

GRANT SELECT, UPDATE, DELETE ON public.field_trip_activity_notifications TO authenticated;

CREATE INDEX IF NOT EXISTS idx_field_trip_publications_template_published
    ON public.field_trip_publications(template_id, published_at DESC, id DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_publications_published
    ON public.field_trip_publications(published_at DESC, id DESC)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.get_field_trip_community_publications(
    self_id UUID,
    mode TEXT DEFAULT 'smart',
    target_template_id UUID DEFAULT NULL,
    user_region TEXT DEFAULT NULL,
    viewer_habitat_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    viewer_season_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    max_limit INTEGER DEFAULT 20,
    before_rank_bucket INTEGER DEFAULT NULL,
    before_published_at TIMESTAMPTZ DEFAULT NULL,
    before_publication_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 20), 60));
    resolved_mode TEXT := LOWER(BTRIM(COALESCE(mode, 'smart')));
    normalized_region TEXT := NULLIF(LOWER(BTRIM(COALESCE(user_region, ''))), '');
    normalized_habitat_tags TEXT[] := public.field_trip_lower_text_array(viewer_habitat_tags);
    normalized_season_tags TEXT[] := public.field_trip_lower_text_array(viewer_season_tags);
    response JSONB := '[]'::jsonb;
BEGIN
    IF resolved_mode NOT IN ('smart', 'following', 'recent') THEN
        RAISE EXCEPTION 'Unsupported Field Trip community mode';
    END IF;

    IF (before_published_at IS NULL) <> (before_publication_id IS NULL) THEN
        RAISE EXCEPTION 'before_published_at and before_publication_id must be provided together';
    END IF;

    IF before_published_at IS NOT NULL AND before_rank_bucket IS NULL THEN
        RAISE EXCEPTION 'before_rank_bucket is required with a community cursor';
    END IF;

    WITH viewer_context AS (
        SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE) AS viewer_is_pro
        FROM public.users u
        WHERE u.id = self_id
    ),
    candidates AS (
        SELECT
            ftp.id AS publication_id,
            ftp.title,
            ftp.description,
            ftp.published_at,
            ftp.like_count,
            ftp.comment_count,
            ftp.profile_pin_position,
            t.id AS template_id,
            t.slug,
            t.title AS template_title,
            t.region_tags,
            t.season_tags,
            t.habitat_tags,
            public.field_trip_lower_text_array(t.region_tags) AS template_region_tags,
            public.field_trip_lower_text_array(t.season_tags) AS template_season_tags,
            public.field_trip_lower_text_array(t.habitat_tags) AS template_habitat_tags,
            ftp.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_username AS author_username,
            u.public_avatar_url AS author_avatar_url,
            EXISTS (
                SELECT 1
                FROM public.user_follows uf
                WHERE uf.follower_user_id = self_id
                  AND uf.followee_user_id = ftp.user_id
            ) AS viewer_is_following_author,
            (
                SELECT COALESCE(fpi.hero_image_url, fpi.reference_image_url)
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
                  AND COALESCE(NULLIF(BTRIM(fpi.hero_image_url), ''), NULLIF(BTRIM(fpi.reference_image_url), '')) IS NOT NULL
                ORDER BY fpi.sort_order
                LIMIT 1
            ) AS item_cover_image_url,
            t.cover_image_url AS template_cover_image_url,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_publication_items fpi
                WHERE fpi.publication_id = ftp.id
            ) AS item_count,
            EXISTS (
                SELECT 1
                FROM public.field_trip_publication_likes ftpl
                WHERE ftpl.publication_id = ftp.id
                  AND ftpl.user_id = self_id
            ) AS viewer_has_liked
        FROM public.field_trip_publications ftp
        JOIN public.field_trip_templates t
            ON t.id = ftp.template_id
        JOIN public.users u
            ON u.id = ftp.user_id
        CROSS JOIN viewer_context vc
        WHERE ftp.deleted_at IS NULL
          AND public.can_view_field_trip_publication(self_id, ftp.id)
          AND (target_template_id IS NULL OR ftp.template_id = target_template_id)
          AND (t.is_pro_only = FALSE OR t.is_rotating_free = TRUE OR vc.viewer_is_pro OR ftp.user_id = self_id)
    ),
    ranked AS (
        SELECT
            candidates.*,
            (
                target_template_id IS NOT NULL
                OR (normalized_region IS NOT NULL AND normalized_region = ANY(candidates.template_region_tags))
                OR EXISTS (
                    SELECT 1
                    FROM UNNEST(normalized_habitat_tags) AS viewer_tag(tag)
                    WHERE viewer_tag.tag = ANY(candidates.template_habitat_tags)
                )
                OR EXISTS (
                    SELECT 1
                    FROM UNNEST(normalized_season_tags) AS viewer_tag(tag)
                    WHERE viewer_tag.tag = ANY(candidates.template_season_tags)
                )
            ) AS has_local_or_template_relevance,
            (
                'global' = ANY(candidates.template_region_tags)
                OR COALESCE(ARRAY_LENGTH(candidates.region_tags, 1), 0) = 0
            ) AS is_global_fallback
        FROM candidates
        WHERE resolved_mode <> 'following'
           OR candidates.viewer_is_following_author = TRUE
    ),
    bucketed AS (
        SELECT
            ranked.*,
            CASE
                WHEN resolved_mode IN ('following', 'recent') THEN 0
                WHEN ranked.viewer_is_following_author AND ranked.has_local_or_template_relevance THEN 0
                WHEN ranked.viewer_is_following_author THEN 1
                WHEN ranked.has_local_or_template_relevance THEN 2
                WHEN ranked.is_global_fallback THEN 3
                ELSE 4
            END AS rank_bucket,
            CASE
                WHEN ranked.viewer_is_following_author THEN 'following'
                WHEN ranked.has_local_or_template_relevance THEN 'near_you'
                WHEN resolved_mode = 'recent' THEN 'new'
                WHEN ranked.is_global_fallback THEN 'global'
                ELSE 'new'
            END AS community_reason
        FROM ranked
    ),
    paged AS (
        SELECT *
        FROM bucketed
        WHERE (
                before_published_at IS NULL
                OR rank_bucket > before_rank_bucket
                OR (
                    rank_bucket = before_rank_bucket
                    AND (published_at, publication_id) < (before_published_at, before_publication_id)
                )
            )
        ORDER BY rank_bucket ASC, published_at DESC, publication_id DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'publication_id', publication_id,
            'template_id', template_id,
            'title', title,
            'description', description,
            'published_at', published_at,
            'like_count', like_count,
            'comment_count', comment_count,
            'slug', slug,
            'template_title', template_title,
            'region_tags', region_tags,
            'season_tags', season_tags,
            'habitat_tags', habitat_tags,
            'cover_image_url', COALESCE(item_cover_image_url, template_cover_image_url),
            'item_count', item_count,
            'viewer_has_liked', viewer_has_liked,
            'author_user_id', author_user_id,
            'author_name', author_name,
            'author_username', author_username,
            'author_avatar_url', author_avatar_url,
            'is_pinned', profile_pin_position IS NOT NULL,
            'pin_position', profile_pin_position,
            'rank_bucket', rank_bucket,
            'community_reason', community_reason,
            'viewer_is_following_author', viewer_is_following_author
        )
        ORDER BY rank_bucket ASC, published_at DESC, publication_id DESC
    ), '[]'::jsonb)
    INTO response
    FROM paged;

    RETURN response;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_recent_field_trip_publications(
    self_id UUID,
    user_region TEXT DEFAULT NULL,
    viewer_habitat_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    max_limit INTEGER DEFAULT 20,
    before_published_at TIMESTAMPTZ DEFAULT NULL,
    before_publication_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.get_field_trip_community_publications(
        self_id,
        'recent',
        NULL,
        user_region,
        viewer_habitat_tags,
        ARRAY[]::TEXT[],
        max_limit,
        CASE WHEN before_published_at IS NULL THEN NULL ELSE 0 END,
        before_published_at,
        before_publication_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.get_field_trip_community_publications(UUID, TEXT, UUID, TEXT, TEXT[], TEXT[], INTEGER, INTEGER, TIMESTAMPTZ, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_field_trip_comment_activity_notification(
    recipient_user_id UUID,
    actor_user_id UUID,
    target_publication_id UUID,
    target_comment_id UUID,
    notification_type TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF recipient_user_id IS NULL
       OR actor_user_id IS NULL
       OR recipient_user_id = actor_user_id
       OR notification_type NOT IN ('field_trip_comment', 'field_trip_reply') THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = actor_user_id
          AND u.is_shadowbanned = TRUE
    ) THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_blocks ub
        WHERE (ub.blocker_id = recipient_user_id AND ub.blocked_id = actor_user_id)
           OR (ub.blocker_id = actor_user_id AND ub.blocked_id = recipient_user_id)
    ) THEN
        RETURN;
    END IF;

    INSERT INTO public.field_trip_activity_notifications(
        user_id,
        actor_user_id,
        publication_id,
        comment_id,
        type
    )
    VALUES (
        recipient_user_id,
        actor_user_id,
        target_publication_id,
        target_comment_id,
        notification_type
    )
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_field_trip_comment_activity_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    publication_author_id UUID;
    parent_author_id UUID;
BEGIN
    SELECT ftp.user_id
    INTO publication_author_id
    FROM public.field_trip_publications ftp
    WHERE ftp.id = NEW.publication_id
      AND ftp.deleted_at IS NULL;

    IF publication_author_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_comment_id IS NULL THEN
        PERFORM public.create_field_trip_comment_activity_notification(
            publication_author_id,
            NEW.user_id,
            NEW.publication_id,
            NEW.id,
            'field_trip_comment'
        );
        RETURN NEW;
    END IF;

    SELECT parent.user_id
    INTO parent_author_id
    FROM public.field_trip_publication_comments parent
    WHERE parent.id = NEW.parent_comment_id
      AND parent.deleted_at IS NULL
      AND parent.moderated_at IS NULL;

    PERFORM public.create_field_trip_comment_activity_notification(
        parent_author_id,
        NEW.user_id,
        NEW.publication_id,
        NEW.id,
        'field_trip_reply'
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_comment_activity_after_insert ON public.field_trip_publication_comments;
CREATE TRIGGER trg_field_trip_comment_activity_after_insert
AFTER INSERT ON public.field_trip_publication_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_field_trip_comment_activity_after_insert();

CREATE OR REPLACE FUNCTION public.trg_field_trip_comment_activity_after_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
       OR (NEW.moderated_at IS NOT NULL AND OLD.moderated_at IS DISTINCT FROM NEW.moderated_at) THEN
        DELETE FROM public.field_trip_activity_notifications
        WHERE comment_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_comment_activity_after_update ON public.field_trip_publication_comments;
CREATE TRIGGER trg_field_trip_comment_activity_after_update
AFTER UPDATE OF deleted_at, moderated_at ON public.field_trip_publication_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_field_trip_comment_activity_after_update();

CREATE OR REPLACE FUNCTION public.trg_field_trip_followed_publication_activity_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = NEW.user_id
          AND u.is_shadowbanned = TRUE
    ) THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.field_trip_activity_notifications(
        user_id,
        actor_user_id,
        publication_id,
        type
    )
    SELECT
        uf.follower_user_id,
        NEW.user_id,
        NEW.id,
        'field_trip_followed_publication'
    FROM public.user_follows uf
    JOIN public.users follower
        ON follower.id = uf.follower_user_id
    WHERE uf.followee_user_id = NEW.user_id
      AND uf.follower_user_id <> NEW.user_id
      AND follower.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = uf.follower_user_id AND ub.blocked_id = NEW.user_id)
             OR (ub.blocker_id = NEW.user_id AND ub.blocked_id = uf.follower_user_id)
      )
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_followed_publication_activity_after_insert ON public.field_trip_publications;
CREATE TRIGGER trg_field_trip_followed_publication_activity_after_insert
AFTER INSERT ON public.field_trip_publications
FOR EACH ROW
EXECUTE FUNCTION public.trg_field_trip_followed_publication_activity_after_insert();

CREATE OR REPLACE FUNCTION public.trg_field_trip_publication_activity_after_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS DISTINCT FROM NEW.deleted_at THEN
        DELETE FROM public.field_trip_activity_notifications
        WHERE publication_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_publication_activity_after_update ON public.field_trip_publications;
CREATE TRIGGER trg_field_trip_publication_activity_after_update
AFTER UPDATE OF deleted_at ON public.field_trip_publications
FOR EACH ROW
EXECUTE FUNCTION public.trg_field_trip_publication_activity_after_update();

CREATE OR REPLACE FUNCTION public.trg_field_trip_activity_user_blocks_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.field_trip_activity_notifications
    WHERE (user_id = NEW.blocker_id AND actor_user_id = NEW.blocked_id)
       OR (user_id = NEW.blocked_id AND actor_user_id = NEW.blocker_id)
       OR EXISTS (
           SELECT 1
           FROM public.field_trip_publications ftp
           WHERE ftp.id = field_trip_activity_notifications.publication_id
             AND (
                 (field_trip_activity_notifications.user_id = NEW.blocker_id AND ftp.user_id = NEW.blocked_id)
                 OR (field_trip_activity_notifications.user_id = NEW.blocked_id AND ftp.user_id = NEW.blocker_id)
             )
       );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_activity_user_blocks_cleanup ON public.user_blocks;
CREATE TRIGGER trg_field_trip_activity_user_blocks_cleanup
AFTER INSERT ON public.user_blocks
FOR EACH ROW
EXECUTE FUNCTION public.trg_field_trip_activity_user_blocks_cleanup();

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
    field_trip_publication_id UUID,
    type TEXT,
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
    WITH visible_explore_notifications AS (
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
    ),
    explore_rows AS (
        SELECT
            n.id AS notification_id,
            n.post_id,
            n.community_request_id,
            NULL::UUID AS field_trip_publication_id,
            n.type::TEXT AS type,
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
        FROM visible_explore_notifications n
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
                n.type NOT IN ('comment_reaction', 'community_identification_added')
                OR COALESCE(ARRAY_LENGTH(actor_names.recent_actor_names, 1), 0) > 0
            )
    ),
    visible_field_trip_notifications AS (
        SELECT
            n.id AS notification_id,
            NULL::UUID AS post_id,
            NULL::UUID AS community_request_id,
            n.publication_id AS field_trip_publication_id,
            n.type,
            n.comment_id,
            c.parent_comment_id,
            NULL::TEXT AS reaction_emoji,
            n.actor_user_id AS triggering_user_id,
            actor.public_author_name AS triggering_user_name,
            c.body AS comment_body,
            ARRAY[]::TEXT[] AS recent_actor_names,
            1::INTEGER AS action_count,
            n.read_at IS NOT NULL AS is_read,
            (n.type = 'field_trip_reply' AND parent.user_id = self_id) AS is_reply_to_viewer_comment,
            NULL::TEXT AS community_taxon_common_name,
            NULL::TEXT AS community_taxon_scientific_name,
            NULL::TEXT AS community_request_display_name,
            n.created_at,
            n.updated_at
        FROM public.field_trip_activity_notifications n
        JOIN public.field_trip_publications ftp
            ON ftp.id = n.publication_id
        JOIN public.users actor
            ON actor.id = n.actor_user_id
        LEFT JOIN public.field_trip_publication_comments c
            ON c.id = n.comment_id
           AND c.deleted_at IS NULL
           AND c.moderated_at IS NULL
        LEFT JOIN public.field_trip_publication_comments parent
            ON parent.id = c.parent_comment_id
           AND parent.deleted_at IS NULL
           AND parent.moderated_at IS NULL
        WHERE n.user_id = self_id
          AND n.deleted_at IS NULL
          AND actor.is_shadowbanned = FALSE
          AND public.can_view_field_trip_publication(self_id, n.publication_id)
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = n.actor_user_id)
                 OR (ub.blocker_id = n.actor_user_id AND ub.blocked_id = self_id)
          )
          AND (
              (
                  n.type = 'field_trip_followed_publication'
                  AND n.comment_id IS NULL
                  AND ftp.user_id = n.actor_user_id
                  AND EXISTS (
                      SELECT 1
                      FROM public.user_follows uf
                      WHERE uf.follower_user_id = self_id
                        AND uf.followee_user_id = n.actor_user_id
                  )
              )
              OR (
                  n.type IN ('field_trip_comment', 'field_trip_reply')
                  AND n.comment_id IS NOT NULL
                  AND c.id IS NOT NULL
                  AND (
                      n.type = 'field_trip_comment'
                      OR (
                          parent.id IS NOT NULL
                          AND parent.parent_comment_id IS NULL
                      )
                  )
              )
          )
    ),
    combined AS (
        SELECT * FROM explore_rows
        UNION ALL
        SELECT * FROM visible_field_trip_notifications
    )
    SELECT *
    FROM combined n
    WHERE (
            before_updated_at IS NULL
            OR before_notification_id IS NULL
            OR n.updated_at < before_updated_at
            OR (n.updated_at = before_updated_at AND n.notification_id < before_notification_id)
        )
    ORDER BY n.updated_at DESC, n.notification_id DESC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_unread_explore_notification_count(self_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.get_explore_notifications(self_id, 1000000, NULL, NULL) n
    WHERE n.is_read = FALSE;
$$;

CREATE OR REPLACE FUNCTION public.mark_explore_notifications_read(self_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    post_updated_count INTEGER := 0;
    field_trip_updated_count INTEGER := 0;
BEGIN
    UPDATE public.explore_post_notifications
    SET is_read = TRUE
    WHERE user_id = self_id
      AND is_read = FALSE;

    GET DIAGNOSTICS post_updated_count = ROW_COUNT;

    UPDATE public.field_trip_activity_notifications
    SET read_at = NOW()
    WHERE user_id = self_id
      AND read_at IS NULL
      AND deleted_at IS NULL;

    GET DIAGNOSTICS field_trip_updated_count = ROW_COUNT;

    RETURN post_updated_count + field_trip_updated_count;
END;
$$;

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
        n.type::public.explore_notification_type AS type,
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
      AND n.field_trip_publication_id IS NULL
      AND n.type <> 'follow';
$$;

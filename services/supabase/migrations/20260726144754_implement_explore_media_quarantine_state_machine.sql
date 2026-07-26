-- Preserve published Explore posts and their engagement when durable media is
-- unexpectedly unavailable. Public projections omit only confirmed-missing
-- media and quarantine a post only when none of its media remains healthy.
--
-- A client/CDN failure never confirms loss. Only the service-role reconciler,
-- after direct R2 origin checks, can advance media to `missing`.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

ALTER TABLE public.explore_post_media
    ADD COLUMN IF NOT EXISTS health_status TEXT NOT NULL DEFAULT 'healthy',
    ADD COLUMN IF NOT EXISTS health_checked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS missing_first_observed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS missing_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS recovered_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS consecutive_missing_checks INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_health_check_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS last_health_http_status INTEGER,
    ADD COLUMN IF NOT EXISTS last_thumbnail_health_http_status INTEGER;

ALTER TABLE public.explore_post_media
    DROP CONSTRAINT IF EXISTS explore_post_media_health_status_check,
    DROP CONSTRAINT IF EXISTS explore_post_media_missing_checks_check,
    DROP CONSTRAINT IF EXISTS explore_post_media_http_status_check,
    DROP CONSTRAINT IF EXISTS explore_post_media_thumbnail_http_status_check;

ALTER TABLE public.explore_post_media
    ADD CONSTRAINT explore_post_media_health_status_check
        CHECK (health_status IN ('healthy', 'suspected_missing', 'missing')),
    ADD CONSTRAINT explore_post_media_missing_checks_check
        CHECK (consecutive_missing_checks >= 0),
    ADD CONSTRAINT explore_post_media_http_status_check
        CHECK (
            last_health_http_status IS NULL
            OR last_health_http_status BETWEEN 100 AND 599
        ),
    ADD CONSTRAINT explore_post_media_thumbnail_http_status_check
        CHECK (
            last_thumbnail_health_http_status IS NULL
            OR last_thumbnail_health_http_status BETWEEN 100 AND 599
        );

COMMENT ON COLUMN public.explore_post_media.health_status IS
    'Origin-verified lifecycle: healthy, suspected_missing after one R2 404, or missing after a spaced confirmation.';
COMMENT ON COLUMN public.explore_post_media.next_health_check_at IS
    'Earliest time the service-role R2 reconciler may lease this media item.';

CREATE INDEX IF NOT EXISTS idx_explore_post_media_health_due
    ON public.explore_post_media(next_health_check_at, id)
    WHERE health_status <> 'missing';

CREATE INDEX IF NOT EXISTS idx_explore_post_media_missing_recheck
    ON public.explore_post_media(next_health_check_at, id)
    WHERE health_status = 'missing';

ALTER TABLE public.explore_posts
    ADD COLUMN IF NOT EXISTS media_health_status TEXT NOT NULL DEFAULT 'healthy',
    ADD COLUMN IF NOT EXISTS media_health_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS media_quarantined_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS media_last_recovered_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS missing_media_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_media_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.explore_posts
    DROP CONSTRAINT IF EXISTS explore_posts_media_health_status_check,
    DROP CONSTRAINT IF EXISTS explore_posts_missing_media_count_check,
    DROP CONSTRAINT IF EXISTS explore_posts_total_media_count_check,
    DROP CONSTRAINT IF EXISTS explore_posts_media_count_order_check;

ALTER TABLE public.explore_posts
    ADD CONSTRAINT explore_posts_media_health_status_check
        CHECK (media_health_status IN ('healthy', 'degraded', 'quarantined')),
    ADD CONSTRAINT explore_posts_missing_media_count_check
        CHECK (missing_media_count >= 0),
    ADD CONSTRAINT explore_posts_total_media_count_check
        CHECK (total_media_count >= 0),
    ADD CONSTRAINT explore_posts_media_count_order_check
        CHECK (missing_media_count <= total_media_count);

COMMENT ON COLUMN public.explore_posts.media_health_status IS
    'System-owned media state, independent from author unpublish and moderation. Quarantine is reversible and preserves engagement.';

CREATE INDEX IF NOT EXISTS idx_explore_posts_owner_media_health
    ON public.explore_posts(user_id, media_health_status, media_health_updated_at DESC)
    WHERE media_health_status <> 'healthy';

CREATE TABLE IF NOT EXISTS internal.explore_media_health_check_claims (
    media_id UUID PRIMARY KEY
        REFERENCES public.explore_post_media(id) ON DELETE CASCADE,
    claim_token UUID NOT NULL UNIQUE,
    claimed_at TIMESTAMPTZ NOT NULL,
    claimed_until TIMESTAMPTZ NOT NULL,
    CONSTRAINT explore_media_health_claim_window_check
        CHECK (claimed_until > claimed_at)
);

ALTER TABLE internal.explore_media_health_check_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.explore_media_health_check_claims
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.explore_media_health_check_claims IS
    'Private short leases that make concurrent Explore R2 reconciliation idempotent.';

-- `refresh_explore_post_media` rebuilds a post snapshot with DELETE + INSERT.
-- Keep origin-confirmed health keyed by the stable post/kind/URL identity so a
-- routine snapshot refresh cannot silently make missing media public again.
CREATE TABLE IF NOT EXISTS internal.explore_media_health_history (
    post_id UUID NOT NULL
        REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    health_status TEXT NOT NULL,
    health_checked_at TIMESTAMPTZ,
    missing_first_observed_at TIMESTAMPTZ,
    missing_confirmed_at TIMESTAMPTZ,
    recovered_at TIMESTAMPTZ,
    consecutive_missing_checks INTEGER NOT NULL,
    next_health_check_at TIMESTAMPTZ NOT NULL,
    last_health_http_status INTEGER,
    last_thumbnail_health_http_status INTEGER,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (post_id, kind, url),
    CONSTRAINT explore_media_health_history_status_check
        CHECK (health_status IN ('healthy', 'suspected_missing', 'missing')),
    CONSTRAINT explore_media_health_history_missing_checks_check
        CHECK (consecutive_missing_checks >= 0)
);

ALTER TABLE internal.explore_media_health_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.explore_media_health_history
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.explore_media_health_history IS
    'Private health continuity ledger used only while Explore media snapshots are rebuilt.';

CREATE OR REPLACE FUNCTION internal.trg_preserve_explore_media_health()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    prior_health RECORD;
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- During a parent-post cascade there is nothing to preserve.
        IF EXISTS (
            SELECT 1
            FROM public.explore_posts AS post
            WHERE post.id = OLD.post_id
        ) THEN
            INSERT INTO internal.explore_media_health_history (
                post_id,
                kind,
                url,
                thumbnail_url,
                health_status,
                health_checked_at,
                missing_first_observed_at,
                missing_confirmed_at,
                recovered_at,
                consecutive_missing_checks,
                next_health_check_at,
                last_health_http_status,
                last_thumbnail_health_http_status,
                updated_at
            )
            VALUES (
                OLD.post_id,
                OLD.kind,
                OLD.url,
                OLD.thumbnail_url,
                OLD.health_status,
                OLD.health_checked_at,
                OLD.missing_first_observed_at,
                OLD.missing_confirmed_at,
                OLD.recovered_at,
                OLD.consecutive_missing_checks,
                OLD.next_health_check_at,
                OLD.last_health_http_status,
                OLD.last_thumbnail_health_http_status,
                pg_catalog.NOW()
            )
            ON CONFLICT (post_id, kind, url)
            DO UPDATE SET
                thumbnail_url = EXCLUDED.thumbnail_url,
                health_status = EXCLUDED.health_status,
                health_checked_at = EXCLUDED.health_checked_at,
                missing_first_observed_at =
                    EXCLUDED.missing_first_observed_at,
                missing_confirmed_at = EXCLUDED.missing_confirmed_at,
                recovered_at = EXCLUDED.recovered_at,
                consecutive_missing_checks =
                    EXCLUDED.consecutive_missing_checks,
                next_health_check_at = EXCLUDED.next_health_check_at,
                last_health_http_status = EXCLUDED.last_health_http_status,
                last_thumbnail_health_http_status =
                    EXCLUDED.last_thumbnail_health_http_status,
                updated_at = EXCLUDED.updated_at;
        END IF;

        RETURN OLD;
    END IF;

    SELECT
        history.thumbnail_url,
        history.health_status,
        history.health_checked_at,
        history.missing_first_observed_at,
        history.missing_confirmed_at,
        history.recovered_at,
        history.consecutive_missing_checks,
        history.next_health_check_at,
        history.last_health_http_status,
        history.last_thumbnail_health_http_status
    INTO prior_health
    FROM internal.explore_media_health_history AS history
    WHERE history.post_id = NEW.post_id
      AND history.kind = NEW.kind
      AND history.url = NEW.url;

    IF FOUND THEN
        NEW.health_status := prior_health.health_status;
        NEW.health_checked_at := prior_health.health_checked_at;
        NEW.missing_first_observed_at :=
            prior_health.missing_first_observed_at;
        NEW.missing_confirmed_at := prior_health.missing_confirmed_at;
        NEW.recovered_at := prior_health.recovered_at;
        NEW.consecutive_missing_checks :=
            prior_health.consecutive_missing_checks;
        NEW.next_health_check_at := CASE
            WHEN prior_health.thumbnail_url
                    IS DISTINCT FROM NEW.thumbnail_url
             AND NULLIF(
                 pg_catalog.BTRIM(COALESCE(NEW.thumbnail_url, '')),
                 ''
             ) IS NOT NULL
                THEN LEAST(
                    prior_health.next_health_check_at,
                    pg_catalog.NOW()
                )
            ELSE prior_health.next_health_check_at
        END;
        NEW.last_health_http_status := prior_health.last_health_http_status;
        NEW.last_thumbnail_health_http_status := CASE
            WHEN prior_health.thumbnail_url
                    IS NOT DISTINCT FROM NEW.thumbnail_url
                THEN prior_health.last_thumbnail_health_http_status
            ELSE NULL
        END;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.trg_preserve_explore_media_health()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_preserve_explore_media_health_before_delete
    ON public.explore_post_media;
DROP TRIGGER IF EXISTS trg_restore_explore_media_health_before_insert
    ON public.explore_post_media;

CREATE TRIGGER trg_preserve_explore_media_health_before_delete
BEFORE DELETE
ON public.explore_post_media
FOR EACH ROW
EXECUTE FUNCTION internal.trg_preserve_explore_media_health();

CREATE TRIGGER trg_restore_explore_media_health_before_insert
BEFORE INSERT
ON public.explore_post_media
FOR EACH ROW
EXECUTE FUNCTION internal.trg_preserve_explore_media_health();

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
            type IN (
                'community_request_resolved',
                'community_identification_helped'
            )
            AND post_id IS NOT NULL
            AND community_request_id IS NOT NULL
            AND comment_id IS NULL
            AND reaction_emoji IS NULL
            AND triggering_user_id IS NULL
            AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
            AND action_count = 1
        )
        OR (
            type IN ('media_missing', 'media_restored')
            AND post_id IS NOT NULL
            AND community_request_id IS NULL
            AND comment_id IS NULL
            AND reaction_emoji IS NULL
            AND triggering_user_id IS NULL
            AND COALESCE(ARRAY_LENGTH(recent_actor_ids, 1), 0) = 0
            AND action_count = 1
        )
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_media_missing_unique
    ON public.explore_post_notifications(user_id, post_id, type)
    WHERE type = 'media_missing';

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_notifications_media_restored_unique
    ON public.explore_post_notifications(user_id, post_id, type)
    WHERE type = 'media_restored';

CREATE OR REPLACE FUNCTION internal.refresh_explore_post_media_health(
    p_post_id UUID,
    p_emit_notification BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    post_row RECORD;
    v_total_count INTEGER;
    v_missing_count INTEGER;
    v_new_status TEXT;
    v_now TIMESTAMPTZ := pg_catalog.NOW();
BEGIN
    SELECT
        post.id,
        post.user_id,
        post.media_health_status,
        post.unshared_at,
        post.moderated_at
    INTO post_row
    FROM public.explore_posts AS post
    WHERE post.id = p_post_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.COUNT(*) FILTER (
            WHERE media.health_status = 'missing'
        )::INTEGER
    INTO v_total_count, v_missing_count
    FROM public.explore_post_media AS media
    WHERE media.post_id = p_post_id;

    v_new_status := CASE
        WHEN v_total_count = 0 OR v_missing_count = 0 THEN 'healthy'
        WHEN v_missing_count < v_total_count THEN 'degraded'
        ELSE 'quarantined'
    END;

    UPDATE public.explore_posts AS post
    SET media_health_status = v_new_status,
        media_health_updated_at = CASE
            WHEN post.media_health_status IS DISTINCT FROM v_new_status
                THEN v_now
            ELSE post.media_health_updated_at
        END,
        media_quarantined_at = CASE
            WHEN v_new_status = 'quarantined'
                THEN COALESCE(post.media_quarantined_at, v_now)
            ELSE NULL
        END,
        media_last_recovered_at = CASE
            WHEN post.media_health_status IN ('degraded', 'quarantined')
             AND v_new_status = 'healthy'
                THEN v_now
            ELSE post.media_last_recovered_at
        END,
        missing_media_count = v_missing_count,
        total_media_count = v_total_count
    WHERE post.id = p_post_id;

    IF NOT p_emit_notification
       OR post_row.unshared_at IS NOT NULL
       OR post_row.moderated_at IS NOT NULL
       OR post_row.media_health_status = v_new_status THEN
        RETURN;
    END IF;

    IF post_row.media_health_status = 'healthy'
       AND v_new_status IN ('degraded', 'quarantined') THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = post_row.user_id
          AND post_id = p_post_id
          AND type = 'media_restored';

        INSERT INTO public.explore_post_notifications (
            user_id,
            post_id,
            type,
            recent_actor_ids,
            action_count,
            is_read,
            created_at,
            updated_at
        )
        VALUES (
            post_row.user_id,
            p_post_id,
            'media_missing',
            ARRAY[]::UUID[],
            1,
            FALSE,
            v_now,
            v_now
        )
        ON CONFLICT (user_id, post_id, type)
        WHERE type = 'media_missing'
        DO UPDATE SET
            is_read = FALSE,
            updated_at = v_now;
    ELSIF post_row.media_health_status IN ('degraded', 'quarantined')
          AND v_new_status = 'healthy' THEN
        DELETE FROM public.explore_post_notifications
        WHERE user_id = post_row.user_id
          AND post_id = p_post_id
          AND type = 'media_missing';

        INSERT INTO public.explore_post_notifications (
            user_id,
            post_id,
            type,
            recent_actor_ids,
            action_count,
            is_read,
            created_at,
            updated_at
        )
        VALUES (
            post_row.user_id,
            p_post_id,
            'media_restored',
            ARRAY[]::UUID[],
            1,
            FALSE,
            v_now,
            v_now
        )
        ON CONFLICT (user_id, post_id, type)
        WHERE type = 'media_restored'
        DO UPDATE SET
            is_read = FALSE,
            updated_at = v_now;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION internal.refresh_explore_post_media_health(UUID, BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.trg_refresh_explore_post_media_health()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM internal.refresh_explore_post_media_health(NEW.post_id, FALSE);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Snapshot rebuilds aggregate on each replacement insert. Recompute
        -- once more at commit so an internal direct delete cannot leave stale
        -- counts, but do not manufacture user notifications for row cleanup.
        PERFORM internal.refresh_explore_post_media_health(OLD.post_id, FALSE);
        RETURN OLD;
    ELSE
        PERFORM internal.refresh_explore_post_media_health(NEW.post_id, TRUE);
        RETURN NEW;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION internal.trg_refresh_explore_post_media_health()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_refresh_explore_post_media_health
    ON public.explore_post_media;
DROP TRIGGER IF EXISTS trg_initialize_explore_post_media_health
    ON public.explore_post_media;
DROP TRIGGER IF EXISTS trg_finalize_explore_post_media_health_after_delete
    ON public.explore_post_media;
CREATE TRIGGER trg_initialize_explore_post_media_health
AFTER INSERT
ON public.explore_post_media
FOR EACH ROW
EXECUTE FUNCTION internal.trg_refresh_explore_post_media_health();

CREATE TRIGGER trg_refresh_explore_post_media_health
AFTER UPDATE OF health_status
ON public.explore_post_media
FOR EACH ROW
WHEN (OLD.health_status IS DISTINCT FROM NEW.health_status)
EXECUTE FUNCTION internal.trg_refresh_explore_post_media_health();

CREATE CONSTRAINT TRIGGER trg_finalize_explore_post_media_health_after_delete
AFTER DELETE
ON public.explore_post_media
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION internal.trg_refresh_explore_post_media_health();

CREATE OR REPLACE FUNCTION public.explore_post_media_items(target_post_id UUID)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'kind', epm.kind,
                'url', epm.url,
                'thumbnail_url', CASE
                    WHEN epm.last_thumbnail_health_http_status = 404 THEN NULL
                    ELSE epm.thumbnail_url
                END,
                'order_index', epm.order_index,
                'duration_seconds', epm.duration_seconds,
                'has_audio', epm.has_audio
            )
            ORDER BY epm.order_index, epm.created_at, epm.id
        ),
        '[]'::JSONB
    )
    FROM public.explore_post_media epm
    WHERE epm.post_id = target_post_id
      AND epm.health_status <> 'missing';
$$;

CREATE OR REPLACE FUNCTION public.explore_post_hero_image_url(target_post_id UUID)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT NULLIF(BTRIM(epm.thumbnail_url), '')
            FROM public.explore_post_media epm
            WHERE epm.post_id = target_post_id
              AND epm.health_status <> 'missing'
              AND epm.last_thumbnail_health_http_status IS DISTINCT FROM 404
              AND NULLIF(BTRIM(COALESCE(epm.thumbnail_url, '')), '') IS NOT NULL
            ORDER BY epm.order_index, epm.created_at, epm.id
            LIMIT 1
        ),
        (
            SELECT NULLIF(BTRIM(epm.url), '')
            FROM public.explore_post_media epm
            WHERE epm.post_id = target_post_id
              AND epm.health_status <> 'missing'
              AND epm.kind = 'image'
              AND NULLIF(BTRIM(epm.url), '') IS NOT NULL
            ORDER BY epm.order_index, epm.created_at, epm.id
            LIMIT 1
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.explore_projected_post_cards(viewer_id UUID)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
    public_latitude DOUBLE PRECISION,
    public_longitude DOUBLE PRECISION,
    coordinate_visibility TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    media_items JSONB
)
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        public.explore_post_hero_image_url(ep.id) AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        users.public_author_name AS author_name,
        users.public_avatar_url AS author_avatar_url,
        public.explore_post_community_common_name(
            CASE
                WHEN projection.projection_state = 'community_resolved'
                    THEN 'resolved'
                ELSE NULL
            END,
            community_taxon.common_name,
            community_taxon.scientific_name,
            ep.species_common_name,
            species.common_names,
            species.scientific_name
        ) AS species_common_name,
        public.explore_post_community_scientific_name(
            CASE
                WHEN projection.projection_state = 'community_resolved'
                    THEN 'resolved'
                ELSE NULL
            END,
            community_taxon.scientific_name,
            species.scientific_name
        ) AS species_scientific_name,
        scans.pet_identification,
        ep.public_location_label,
        ep.location_sharing,
        ep.public_latitude,
        ep.public_longitude,
        ep.public_coordinate_visibility AS coordinate_visibility,
        scans.time_of_day,
        scans.current_month,
        scans.weather_condition,
        scans.weather_temperature_f,
        ep.like_count,
        ep.comment_count,
        EXISTS (
            SELECT 1
            FROM public.explore_post_likes AS likes
            WHERE likes.post_id = ep.id
              AND likes.user_id = viewer_id
        ) AS viewer_has_liked,
        (ep.user_id = viewer_id) AS is_owned_by_viewer,
        public.explore_post_media_items(ep.id) AS media_items
    FROM public.explore_posts AS ep
    JOIN public.scans AS scans
      ON scans.id = ep.scan_id
    JOIN public.users AS users
      ON users.id = ep.user_id
    LEFT JOIN public.species_dictionary AS species
      ON species.id = COALESCE(
          scans.confirmed_species_id,
          scans.species_id
      )
    LEFT JOIN public.explore_observation_projection AS projection
      ON projection.post_id = ep.id
    LEFT JOIN public.taxon_nodes AS community_taxon
      ON community_taxon.id = projection.public_taxon_node_id
    WHERE ep.unshared_at IS NULL
      AND ep.moderated_at IS NULL
      AND ep.media_health_status <> 'quarantined'
      AND (
          COALESCE(
              projection.projection_state::TEXT,
              'normal'
          ) IN ('normal', 'withdrawn')
          OR (
              projection.projection_state = 'community_resolved'
              AND EXISTS (
                  SELECT 1
                  FROM public.explore_community_requests AS requests
                  WHERE requests.id = projection.community_request_id
                    AND requests.status = 'resolved'
                    AND requests.explore_published_at IS NOT NULL
              )
          )
      )
      AND scans.is_tombstoned = FALSE
      AND EXISTS (
          SELECT 1
          FROM public.explore_post_media AS media
          WHERE media.post_id = ep.id
            AND media.health_status <> 'missing'
      )
      AND COALESCE(
          scans.confirmed_species_id,
          scans.species_id
      ) IS NOT NULL
      AND users.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks AS blocks
          WHERE (
              blocks.blocker_id = viewer_id
              AND blocks.blocked_id = ep.user_id
          ) OR (
              blocks.blocker_id = ep.user_id
              AND blocks.blocked_id = viewer_id
          )
      );
$$;

COMMENT ON FUNCTION public.explore_projected_post_cards(UUID) IS
    'Canonical public Explore projection. Confirmed-missing items are omitted and all-missing posts are reversibly quarantined without changing author publication intent or engagement.';

-- The secondary detail RPC is fetched independently by native and web
-- clients. Apply the same quarantine boundary there so a known post UUID
-- cannot expose metadata for a post hidden by the canonical card projection.
CREATE OR REPLACE FUNCTION public.get_explore_post_detail(
    self_id UUID,
    target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    location_sharing TEXT,
    hashtags TEXT[],
    species_dictionary_id UUID,
    alternative_common_names TEXT[],
    pet_identification JSONB,
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT,
    ai_reasoning TEXT,
    habitat_description TEXT,
    gbif_taxon_key INTEGER,
    iucn_red_list_status TEXT,
    hazard_type TEXT,
    wikipedia_url TEXT,
    reference_image_url TEXT,
    wikipedia_overview TEXT,
    similar_species JSONB
)
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
    SELECT
        post.id AS post_id,
        NULLIF(BTRIM(COALESCE(post.field_notes, '')), '') AS field_notes,
        post.location_sharing,
        ARRAY(
            SELECT hashtag.tag
            FROM public.explore_post_hashtags AS hashtag
            WHERE hashtag.post_id = post.id
            ORDER BY hashtag.tag
        ) AS hashtags,
        species.id AS species_dictionary_id,
        ARRAY(
            SELECT NULLIF(BTRIM(names.raw_name), '')
            FROM UNNEST(
                COALESCE(
                    species.alternative_common_names,
                    ARRAY[]::TEXT[]
                )
            ) WITH ORDINALITY AS names(raw_name, ordinality)
            WHERE NULLIF(BTRIM(names.raw_name), '') IS NOT NULL
            ORDER BY names.ordinality
        ) AS alternative_common_names,
        scan.pet_identification,
        species.kingdom AS taxonomy_kingdom,
        species.phylum AS taxonomy_phylum,
        species."class" AS taxonomy_class,
        species."order" AS taxonomy_order,
        species.family AS taxonomy_family,
        species.genus AS taxonomy_genus,
        CASE
            WHEN COALESCE(
                scan.user_review_state,
                'unreviewed'::public.user_review_state
            ) <> 'user_overridden'::public.user_review_state
             AND scan.user_identification_override IS NULL
             AND NULLIF(BTRIM(COALESCE(scan.ai_reasoning, '')), '') IS NOT NULL
                THEN scan.ai_reasoning
            ELSE NULL
        END AS ai_reasoning,
        species.habitat_description,
        species.gbif_taxon_key,
        species.iucn_red_list_status,
        COALESCE(NULLIF(BTRIM(species.hazard_type), ''), 'none')
            AS hazard_type,
        species.wikipedia_url,
        public.public_species_reference_image_urls_excluding_media(
            species.id,
            species.reference_image_url,
            scan.image_storage_urls
        ) AS reference_image_url,
        species.wikipedia_overview,
        public.public_species_similar_species(species.id) AS similar_species
    FROM public.explore_posts AS post
    INNER JOIN public.scans AS scan
        ON scan.id = post.scan_id
    INNER JOIN public.users AS author
        ON author.id = post.user_id
    LEFT JOIN public.species_dictionary AS species
        ON species.id = COALESCE(
            scan.confirmed_species_id,
            scan.species_id
        )
    WHERE post.id = target_post_id
      AND post.unshared_at IS NULL
      AND post.moderated_at IS NULL
      AND post.media_health_status <> 'quarantined'
      AND scan.is_tombstoned = FALSE
      AND COALESCE(scan.confirmed_species_id, scan.species_id) IS NOT NULL
      AND author.is_shadowbanned = FALSE
      AND EXISTS (
          SELECT 1
          FROM public.explore_projected_post_cards(self_id) AS visible_post
          WHERE visible_post.post_id = post.id
      )
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks AS blocks
          WHERE (
              blocks.blocker_id = self_id
              AND blocks.blocked_id = post.user_id
          ) OR (
              blocks.blocker_id = post.user_id
              AND blocks.blocked_id = self_id
          )
      )
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_explore_post_detail(UUID, UUID) IS
    'Returns privacy-safe public Explore metadata and applies the canonical reversible media-quarantine visibility boundary.';

CREATE OR REPLACE FUNCTION public.claim_explore_media_health_checks(
    p_limit INTEGER DEFAULT 200,
    p_lease_seconds INTEGER DEFAULT 120
)
RETURNS TABLE(
    media_id UUID,
    post_id UUID,
    user_id UUID,
    kind TEXT,
    url TEXT,
    thumbnail_url TEXT,
    health_status TEXT,
    claim_token UUID
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    v_limit INTEGER;
    v_lease_seconds INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    v_limit := LEAST(
        GREATEST(COALESCE(p_limit, 200), 1),
        500
    );
    v_lease_seconds := LEAST(
        GREATEST(COALESCE(p_lease_seconds, 120), 30),
        600
    );

    RETURN QUERY
    WITH candidates AS (
        SELECT media.id
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        INNER JOIN public.scans AS scan
            ON scan.id = post.scan_id
        LEFT JOIN internal.explore_media_health_check_claims AS existing_claim
            ON existing_claim.media_id = media.id
           AND existing_claim.claimed_until > pg_catalog.NOW()
        WHERE media.next_health_check_at <= pg_catalog.NOW()
          AND post.unshared_at IS NULL
          AND post.moderated_at IS NULL
          AND NOT scan.is_tombstoned
          AND existing_claim.media_id IS NULL
        ORDER BY
            CASE media.health_status
                WHEN 'suspected_missing' THEN 0
                WHEN 'missing' THEN 1
                ELSE 2
            END,
            media.next_health_check_at,
            media.id
        FOR UPDATE OF media SKIP LOCKED
        LIMIT v_limit
    ),
    claimed AS (
        INSERT INTO internal.explore_media_health_check_claims (
            media_id,
            claim_token,
            claimed_at,
            claimed_until
        )
        SELECT
            candidate.id,
            pg_catalog.GEN_RANDOM_UUID(),
            pg_catalog.NOW(),
            pg_catalog.NOW()
                + pg_catalog.MAKE_INTERVAL(secs => v_lease_seconds)
        FROM candidates AS candidate
        ON CONFLICT (media_id) DO UPDATE
        SET claim_token = pg_catalog.GEN_RANDOM_UUID(),
            claimed_at = pg_catalog.NOW(),
            claimed_until = pg_catalog.NOW()
                + pg_catalog.MAKE_INTERVAL(secs => v_lease_seconds)
        WHERE internal.explore_media_health_check_claims.claimed_until
            <= pg_catalog.NOW()
        RETURNING
            internal.explore_media_health_check_claims.media_id,
            internal.explore_media_health_check_claims.claim_token
    )
    SELECT
        media.id,
        media.post_id,
        post.user_id,
        media.kind,
        media.url,
        media.thumbnail_url,
        media.health_status,
        claimed.claim_token
    FROM claimed
    INNER JOIN public.explore_post_media AS media
        ON media.id = claimed.media_id
    INNER JOIN public.explore_posts AS post
        ON post.id = media.post_id
    ORDER BY media.next_health_check_at, media.id;
END;
$$;

COMMENT ON FUNCTION public.claim_explore_media_health_checks(INTEGER, INTEGER) IS
    'Service-only bounded lease queue for direct R2 origin health checks of active Explore media.';

REVOKE ALL ON FUNCTION public.claim_explore_media_health_checks(INTEGER, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_explore_media_health_checks(INTEGER, INTEGER)
    TO service_role;

CREATE OR REPLACE FUNCTION public.record_explore_media_health_check(
    p_media_id UUID,
    p_claim_token UUID,
    p_outcome TEXT,
    p_url_http_status INTEGER DEFAULT NULL,
    p_thumbnail_http_status INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    media_row RECORD;
    v_now TIMESTAMPTZ := pg_catalog.NOW();
    v_new_status TEXT;
    v_missing_checks INTEGER;
    v_first_observed TIMESTAMPTZ;
    v_confirmed_at TIMESTAMPTZ;
    v_recovered_at TIMESTAMPTZ;
    v_next_check TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_media_id IS NULL
       OR p_claim_token IS NULL
       OR p_outcome NOT IN ('healthy', 'missing', 'retryable_error')
       OR (
            p_url_http_status IS NOT NULL
            AND p_url_http_status NOT BETWEEN 100 AND 599
       )
       OR (
            p_thumbnail_http_status IS NOT NULL
            AND p_thumbnail_http_status NOT BETWEEN 100 AND 599
       ) THEN
        RAISE EXCEPTION 'Invalid Explore media health result.'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        media.id,
        media.post_id,
        media.url,
        media.thumbnail_url,
        media.health_status,
        media.consecutive_missing_checks,
        media.missing_first_observed_at,
        media.missing_confirmed_at,
        media.recovered_at
    INTO media_row
    FROM public.explore_post_media AS media
    INNER JOIN internal.explore_media_health_check_claims AS claim
        ON claim.media_id = media.id
       AND claim.claim_token = p_claim_token
       AND claim.claimed_until >= v_now
    WHERE media.id = p_media_id
    FOR UPDATE OF media;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Explore media health lease is missing or expired.'
            USING ERRCODE = 'P0002';
    END IF;

    v_new_status := media_row.health_status;
    v_missing_checks := media_row.consecutive_missing_checks;
    v_first_observed := media_row.missing_first_observed_at;
    v_confirmed_at := media_row.missing_confirmed_at;
    v_recovered_at := media_row.recovered_at;

    IF p_outcome = 'healthy' THEN
        v_new_status := 'healthy';
        v_missing_checks := 0;
        v_first_observed := NULL;
        v_confirmed_at := NULL;
        IF media_row.health_status = 'missing' THEN
            v_recovered_at := v_now;
        END IF;
        v_next_check := CASE
            WHEN NULLIF(
                pg_catalog.BTRIM(COALESCE(media_row.thumbnail_url, '')),
                ''
            ) IS NOT NULL
             AND media_row.thumbnail_url IS DISTINCT FROM media_row.url
             AND (
                 p_thumbnail_http_status IS NULL
                 OR p_thumbnail_http_status NOT BETWEEN 200 AND 399
             )
                THEN v_now + INTERVAL '1 hour'
            ELSE v_now + INTERVAL '24 hours'
        END;
    ELSIF p_outcome = 'retryable_error' THEN
        v_next_check := v_now + INTERVAL '15 minutes';
    ELSIF media_row.health_status = 'missing' THEN
        v_missing_checks := media_row.consecutive_missing_checks + 1;
        v_next_check := v_now + INTERVAL '1 hour';
    ELSIF media_row.health_status = 'suspected_missing'
          AND media_row.missing_first_observed_at
                <= v_now - INTERVAL '5 minutes' THEN
        v_new_status := 'missing';
        v_missing_checks := media_row.consecutive_missing_checks + 1;
        v_confirmed_at := v_now;
        v_next_check := v_now + INTERVAL '1 hour';
    ELSE
        v_new_status := 'suspected_missing';
        v_missing_checks := media_row.consecutive_missing_checks + 1;
        v_first_observed := COALESCE(
            media_row.missing_first_observed_at,
            v_now
        );
        v_next_check := GREATEST(
            v_now + INTERVAL '5 minutes',
            v_first_observed + INTERVAL '5 minutes'
        );
    END IF;

    UPDATE public.explore_post_media AS media
    SET health_status = v_new_status,
        health_checked_at = v_now,
        missing_first_observed_at = v_first_observed,
        missing_confirmed_at = v_confirmed_at,
        recovered_at = v_recovered_at,
        consecutive_missing_checks = v_missing_checks,
        next_health_check_at = v_next_check,
        last_health_http_status = p_url_http_status,
        last_thumbnail_health_http_status = p_thumbnail_http_status,
        updated_at = v_now
    WHERE media.id = p_media_id;

    DELETE FROM internal.explore_media_health_check_claims AS claim
    WHERE claim.media_id = p_media_id
      AND claim.claim_token = p_claim_token;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'media_id', p_media_id,
        'post_id', media_row.post_id,
        'previous_status', media_row.health_status,
        'health_status', v_new_status,
        'next_health_check_at', v_next_check
    );
END;
$$;

COMMENT ON FUNCTION public.record_explore_media_health_check(
    UUID, UUID, TEXT, INTEGER, INTEGER
) IS
    'Service-only R2 result recorder. Two direct missing checks spaced by five minutes are required before public media quarantine.';

REVOKE ALL ON FUNCTION public.record_explore_media_health_check(
    UUID, UUID, TEXT, INTEGER, INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_explore_media_health_check(
    UUID, UUID, TEXT, INTEGER, INTEGER
) TO service_role;

CREATE TABLE IF NOT EXISTS public.explore_media_health_reconciliation_runs (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    started_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL CHECK (
        status IN ('success', 'partial_failure', 'failed', 'dry_run')
    ),
    claimed_count INTEGER NOT NULL DEFAULT 0 CHECK (claimed_count >= 0),
    healthy_count INTEGER NOT NULL DEFAULT 0 CHECK (healthy_count >= 0),
    missing_observation_count INTEGER NOT NULL DEFAULT 0 CHECK (
        missing_observation_count >= 0
    ),
    retryable_error_count INTEGER NOT NULL DEFAULT 0 CHECK (
        retryable_error_count >= 0
    ),
    error_count INTEGER NOT NULL DEFAULT 0 CHECK (error_count >= 0),
    errors JSONB NOT NULL DEFAULT '[]'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

CREATE INDEX IF NOT EXISTS idx_explore_media_health_runs_started
    ON public.explore_media_health_reconciliation_runs(started_at DESC);

ALTER TABLE public.explore_media_health_reconciliation_runs
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.explore_media_health_reconciliation_runs
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE
    ON TABLE public.explore_media_health_reconciliation_runs
    TO service_role;

COMMENT ON TABLE public.explore_media_health_reconciliation_runs IS
    'Service-role audit log for direct R2 Explore media checks and quarantine transitions.';

CREATE OR REPLACE FUNCTION public.get_owned_explore_media_incidents(
    self_id UUID
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    species_common_name TEXT,
    media_health_status TEXT,
    missing_media_count INTEGER,
    total_media_count INTEGER,
    media_quarantined_at TIMESTAMPTZ,
    media_health_updated_at TIMESTAMPTZ,
    missing_media_urls TEXT[]
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    IF auth.role() = 'service_role'
       OR SESSION_USER IN ('postgres', 'service_role') THEN
        PERFORM internal.require_service_role();
    ELSIF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM self_id THEN
        RAISE EXCEPTION 'Authenticated caller does not match self_id.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        post.id,
        post.scan_id,
        post.species_common_name,
        post.media_health_status,
        post.missing_media_count,
        post.total_media_count,
        post.media_quarantined_at,
        post.media_health_updated_at,
        COALESCE(
            ARRAY_AGG(media.url ORDER BY media.order_index, media.id)
                FILTER (WHERE media.health_status = 'missing'),
            ARRAY[]::TEXT[]
        )
    FROM public.explore_posts AS post
    INNER JOIN public.scans AS scan
        ON scan.id = post.scan_id
    LEFT JOIN public.explore_post_media AS media
        ON media.post_id = post.id
    WHERE post.user_id = self_id
      AND post.unshared_at IS NULL
      AND post.moderated_at IS NULL
      AND NOT scan.is_tombstoned
      AND post.media_health_status <> 'healthy'
    GROUP BY
        post.id,
        post.scan_id,
        post.species_common_name,
        post.media_health_status,
        post.missing_media_count,
        post.total_media_count,
        post.media_quarantined_at,
        post.media_health_updated_at
    ORDER BY post.media_health_updated_at DESC, post.id DESC;
END;
$$;

COMMENT ON FUNCTION public.get_owned_explore_media_incidents(UUID) IS
    'Owner-only recovery queue for active Explore posts with origin-confirmed missing media.';

REVOKE ALL ON FUNCTION public.get_owned_explore_media_incidents(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_owned_explore_media_incidents(UUID)
    TO authenticated, service_role;

-- Repairing a verified-missing URL must also clear its quarantine state. Patch
-- the already-reviewed atomic repair routine instead of duplicating its scan
-- and normalized-media replacement logic.
DO $migration$
DECLARE
    function_sql TEXT;
    original_fragment TEXT :=
        E'        END,\n'
        || E'        updated_at = pg_catalog.NOW()\n'
        || E'    FROM public.explore_posts AS explore_post\n'
        || E'    WHERE explore_post.id = post_media.post_id';
    replacement_fragment TEXT :=
        E'        END,\n'
        || E'        health_status = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN ''healthy''\n'
        || E'            ELSE post_media.health_status\n'
        || E'        END,\n'
        || E'        health_checked_at = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN pg_catalog.NOW()\n'
        || E'            ELSE post_media.health_checked_at\n'
        || E'        END,\n'
        || E'        missing_first_observed_at = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN NULL\n'
        || E'            ELSE post_media.missing_first_observed_at\n'
        || E'        END,\n'
        || E'        missing_confirmed_at = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN NULL\n'
        || E'            ELSE post_media.missing_confirmed_at\n'
        || E'        END,\n'
        || E'        recovered_at = CASE\n'
        || E'            WHEN post_media.url = p_source_url\n'
        || E'             AND post_media.health_status = ''missing''\n'
        || E'                THEN pg_catalog.NOW()\n'
        || E'            ELSE post_media.recovered_at\n'
        || E'        END,\n'
        || E'        consecutive_missing_checks = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN 0\n'
        || E'            ELSE post_media.consecutive_missing_checks\n'
        || E'        END,\n'
        || E'        next_health_check_at = CASE\n'
        || E'            WHEN post_media.url = p_source_url\n'
        || E'                THEN pg_catalog.NOW() + INTERVAL ''24 hours''\n'
        || E'            ELSE post_media.next_health_check_at\n'
        || E'        END,\n'
        || E'        last_health_http_status = CASE\n'
        || E'            WHEN post_media.url = p_source_url THEN 200\n'
        || E'            ELSE post_media.last_health_http_status\n'
        || E'        END,\n'
        || E'        last_thumbnail_health_http_status = CASE\n'
        || E'            WHEN post_media.thumbnail_url = p_source_url THEN 200\n'
        || E'            ELSE post_media.last_thumbnail_health_http_status\n'
        || E'        END,\n'
        || E'        updated_at = pg_catalog.NOW()\n'
        || E'    FROM public.explore_posts AS explore_post\n'
        || E'    WHERE explore_post.id = post_media.post_id';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.repair_owned_scan_image_reference(uuid,text,text)'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    IF pg_catalog.STRPOS(function_sql, original_fragment) = 0 THEN
        RAISE EXCEPTION
            'repair_owned_scan_image_reference does not match the expected Explore update';
    END IF;

    function_sql := pg_catalog.REPLACE(
        function_sql,
        original_fragment,
        replacement_fragment
    );
    EXECUTE function_sql;
END;
$migration$;

-- Keep owner media incidents visible in the combined Explore/Field Trip
-- notification RPC even while the affected public post is quarantined.
DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    original_fragment TEXT :=
        E'n.type = ''like_aggregated''\n'
        || E'                      OR (';
    replacement_fragment TEXT :=
        E'n.type = ''like_aggregated''\n'
        || E'                      OR n.type IN (''media_missing'', ''media_restored'')\n'
        || E'                      OR (';
    original_visibility_fragment TEXT :=
        E'AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0\n'
        || E'                  AND s.geoprivacy <> ''private''\n'
        || E'                  AND owner.is_shadowbanned = FALSE';
    replacement_visibility_fragment TEXT :=
        E'AND (\n'
        || E'                      n.type IN (''media_missing'', ''media_restored'')\n'
        || E'                      OR (\n'
        || E'                          COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0\n'
        || E'                          AND s.geoprivacy <> ''private''\n'
        || E'                          AND owner.is_shadowbanned = FALSE\n'
        || E'                      )\n'
        || E'                  )';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        original_fragment,
        replacement_fragment
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'get_explore_notifications does not match the expected Explore type branch';
    END IF;
    function_sql := patched_sql;
    patched_sql := pg_catalog.REPLACE(
        function_sql,
        original_visibility_fragment,
        replacement_visibility_fragment
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'get_explore_notifications does not match the expected media visibility branch';
    END IF;
    EXECUTE patched_sql;
END;
$migration$;

-- Missing-media incidents receive one push on insertion. Successful automatic
-- restoration is intentionally quieter and remains in-app only.
DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    original_fragment TEXT :=
        'should_dispatch := NEW.type <> ''follow'';';
    replacement_fragment TEXT :=
        'should_dispatch := NEW.type NOT IN (''follow'', ''media_restored'');';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.trigger_explore_notification_push_delivery()'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        original_fragment,
        replacement_fragment
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'trigger_explore_notification_push_delivery does not match the expected insert branch';
    END IF;
    EXECUTE patched_sql;
END;
$migration$;

-- A confirmed-missing observation must never become reference artwork. Scan
-- arrays are intentionally retained for repair, so gate curation by the
-- origin-verified Explore snapshot instead.
DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    original_fragment TEXT :=
        'AND NULLIF(BTRIM(media.raw_url), '''') IS NOT NULL';
    replacement_fragment TEXT :=
        E'AND NULLIF(BTRIM(media.raw_url), '''') IS NOT NULL\n'
        || E'              AND NOT EXISTS (\n'
        || E'                  SELECT 1\n'
        || E'                  FROM public.explore_post_media AS media_health\n'
        || E'                  WHERE media_health.post_id = ep.id\n'
        || E'                    AND media_health.url = NULLIF(BTRIM(media.raw_url), '''')\n'
        || E'                    AND media_health.health_status = ''missing''\n'
        || E'              )';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        'public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE
    )
    INTO STRICT function_sql;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        original_fragment,
        replacement_fragment
    );
    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'refresh_merian_reference_images does not match the expected media candidate gate';
    END IF;
    EXECUTE patched_sql;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.expedite_explore_media_health_checks(
    p_object_keys TEXT[]
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    v_key TEXT;
    v_updated_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_object_keys IS NULL
       OR pg_catalog.CARDINALITY(p_object_keys) < 1
       OR pg_catalog.CARDINALITY(p_object_keys) > 100 THEN
        RAISE EXCEPTION 'One to 100 R2 object keys are required.'
            USING ERRCODE = '22023';
    END IF;

    FOREACH v_key IN ARRAY p_object_keys LOOP
        IF v_key IS NULL
           OR pg_catalog.CHAR_LENGTH(v_key) > 512
           OR v_key LIKE '/%'
           OR v_key LIKE '%..%'
           OR v_key !~ '^public_uploads/(free|pro)/[^/]+/[^/]+$' THEN
            RAISE EXCEPTION 'Invalid durable scan-media R2 key.'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;

    UPDATE public.explore_post_media AS media
    SET next_health_check_at = LEAST(
            media.next_health_check_at,
            pg_catalog.NOW()
        ),
        updated_at = pg_catalog.NOW()
    WHERE media.url = ANY(
            SELECT 'https://media.merian.app/' || object_key
            FROM pg_catalog.UNNEST(p_object_keys) AS keys(object_key)
        )
       OR media.thumbnail_url = ANY(
            SELECT 'https://media.merian.app/' || object_key
            FROM pg_catalog.UNNEST(p_object_keys) AS keys(object_key)
        );

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$;

COMMENT ON FUNCTION public.expedite_explore_media_health_checks(TEXT[]) IS
    'Service-only R2 event hint. It makes matching rows due; only the origin reconciler can confirm missing or restored media.';

REVOKE ALL ON FUNCTION public.expedite_explore_media_health_checks(TEXT[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.expedite_explore_media_health_checks(TEXT[])
    TO service_role;

-- Existing rows are metadata-only until the reconciler checks R2. This
-- backfill never emits notifications or hides content.
UPDATE public.explore_posts AS post
SET total_media_count = counts.total_count,
    missing_media_count = counts.missing_count,
    media_health_status = CASE
        WHEN counts.total_count = 0 OR counts.missing_count = 0 THEN 'healthy'
        WHEN counts.missing_count < counts.total_count THEN 'degraded'
        ELSE 'quarantined'
    END,
    media_health_updated_at = pg_catalog.NOW(),
    media_quarantined_at = CASE
        WHEN counts.total_count > 0
         AND counts.missing_count = counts.total_count
            THEN COALESCE(post.media_quarantined_at, pg_catalog.NOW())
        ELSE NULL
    END
FROM (
    SELECT
        post_id,
        pg_catalog.COUNT(*)::INTEGER AS total_count,
        pg_catalog.COUNT(*) FILTER (
            WHERE health_status = 'missing'
        )::INTEGER AS missing_count
    FROM public.explore_post_media
    GROUP BY post_id
) AS counts
WHERE post.id = counts.post_id;

UPDATE public.explore_posts AS post
SET total_media_count = 0,
    missing_media_count = 0,
    media_health_status = 'healthy',
    media_quarantined_at = NULL
WHERE NOT EXISTS (
    SELECT 1
    FROM public.explore_post_media AS media
    WHERE media.post_id = post.id
);

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.claim_explore_media_health_checks(integer,integer)',
        'Leases bounded active Explore media rows for direct R2 origin verification.'
    ),
    (
        'service_role',
        'public.record_explore_media_health_check(uuid,uuid,text,integer,integer)',
        'Records a leased direct R2 result and applies the reversible quarantine state machine.'
    ),
    (
        'service_role',
        'public.expedite_explore_media_health_checks(text[])',
        'Turns authenticated R2 create/delete events into due origin-verification work without trusting the event as proof.'
    ),
    (
        'authenticated',
        'public.get_owned_explore_media_incidents(uuid)',
        'Lists only the authenticated owner recovery queue for active media incidents.'
    ),
    (
        'service_role',
        'public.get_owned_explore_media_incidents(uuid)',
        'Supports the authenticated Explore media incident Edge boundary using its auth-derived owner id.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

DO $$
BEGIN
    PERFORM cron.unschedule('reconcile_explore_media_health_every_five_minutes');
EXCEPTION WHEN OTHERS THEN
END;
$$;

SELECT cron.schedule(
    'reconcile_explore_media_health_every_five_minutes',
    '*/5 * * * *',
    $$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', TRUE);
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key := current_setting(
                'app.settings.supabase_service_role_key',
                TRUE
            );
        END IF;

        IF project_url IS NULL OR service_role_key IS NULL THEN
            RAISE WARNING
                'Explore media reconciliation skipped: missing Supabase URL or service role key.';
            RETURN;
        END IF;

        PERFORM net.http_post(
            url := pg_catalog.RTRIM(project_url, '/')
                || '/functions/v1/reconcile-explore-media-health',
            headers := pg_catalog.JSONB_BUILD_OBJECT(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := pg_catalog.JSONB_BUILD_OBJECT(
                'limit', 200,
                'leaseSeconds', 300
            ),
            timeout_milliseconds := 120000
        );
    END;
    $job$;
    $$
);

-- Advanced feed filters must not count an omitted confirmed-missing video or
-- image as an available media type.
DO $migration$
DECLARE
    function_row RECORD;
    function_sql TEXT;
    patched_sql TEXT;
    original_fragment TEXT :=
        'AND filtered_media.kind = ANY(requested_media_types)';
    replacement_fragment TEXT :=
        E'AND filtered_media.health_status <> ''missing''\n'
        || E'AND filtered_media.kind = ANY(requested_media_types)';
BEGIN
    FOR function_row IN
        SELECT
            routine.oid,
            routine.oid::REGPROCEDURE AS signature
        FROM pg_catalog.pg_proc AS routine
        INNER JOIN pg_catalog.pg_namespace AS namespace
            ON namespace.oid = routine.pronamespace
        WHERE namespace.nspname = 'public'
          AND routine.proname IN (
              'get_explore_feed',
              'get_explore_feed_following',
              'get_explore_feed_nearby',
              'get_explore_feed_trending'
          )
    LOOP
        SELECT pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid)
        INTO STRICT function_sql;
        patched_sql := pg_catalog.REPLACE(
            function_sql,
            original_fragment,
            replacement_fragment
        );
        IF patched_sql = function_sql THEN
            RAISE EXCEPTION
                'Explore feed function % does not match the expected media filter',
                function_row.signature;
        END IF;
        EXECUTE patched_sql;
    END LOOP;
END;
$migration$;

NOTIFY pgrst, 'reload schema';

COMMIT;

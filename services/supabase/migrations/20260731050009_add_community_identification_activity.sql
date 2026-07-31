-- Materialize privacy-safe, cursor-stable Community Identify activity groups.
--
-- Suggestion rows on the same request generation are grouped into one-hour
-- bursts. Consensus transitions enrich the latest suggestion burst when they
-- were caused by a submission, while non-submission consensus transitions and
-- resolutions remain independent milestones.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE TABLE internal.community_identification_activity_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL
        REFERENCES public.explore_community_requests(id) ON DELETE CASCADE,
    post_id UUID NOT NULL
        REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    request_generation_at TIMESTAMPTZ NOT NULL,
    activity_type TEXT NOT NULL CHECK (
        activity_type IN (
            'suggestion_burst',
            'consensus_changed',
            'resolved'
        )
    ),
    burst_started_at TIMESTAMPTZ NOT NULL,
    activity_at TIMESTAMPTZ NOT NULL,
    latest_taxon_node_id UUID
        REFERENCES public.taxon_nodes(id) ON DELETE SET NULL,
    consensus_score DOUBLE PRECISION CHECK (
        consensus_score IS NULL
        OR (consensus_score >= 0 AND consensus_score <= 1)
    ),
    source_consensus_event_id UUID
        REFERENCES public.community_consensus_events(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (activity_at >= burst_started_at),
    CHECK (
        (activity_type = 'suggestion_burst' AND source_consensus_event_id IS NULL)
        OR (
            activity_type IN ('consensus_changed', 'resolved')
            AND source_consensus_event_id IS NOT NULL
        )
    )
);

COMMENT ON TABLE internal.community_identification_activity_groups IS
    'Service-only projection of one-hour Community Identify suggestion bursts and immutable consensus milestones.';

CREATE INDEX idx_community_identification_activity_recent
    ON internal.community_identification_activity_groups(
        activity_at DESC,
        id DESC
    );

CREATE INDEX idx_community_identification_activity_request_generation
    ON internal.community_identification_activity_groups(
        request_id,
        request_generation_at,
        activity_type,
        activity_at DESC
    );

CREATE UNIQUE INDEX idx_community_identification_activity_consensus_event
    ON internal.community_identification_activity_groups(
        source_consensus_event_id
    )
    WHERE source_consensus_event_id IS NOT NULL;

CREATE TABLE internal.community_identification_activity_actors (
    activity_group_id UUID NOT NULL
        REFERENCES internal.community_identification_activity_groups(id)
        ON DELETE CASCADE,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    suggestion_count INTEGER NOT NULL DEFAULT 1
        CHECK (suggestion_count > 0),
    last_suggested_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (activity_group_id, user_id)
);

COMMENT ON TABLE internal.community_identification_activity_actors IS
    'Normalized actor counts for Community Identify suggestion bursts; public names are resolved only when activity is read.';

CREATE INDEX idx_community_identification_activity_actor_recent
    ON internal.community_identification_activity_actors(
        activity_group_id,
        last_suggested_at DESC,
        user_id DESC
    );

ALTER TABLE internal.community_identification_activity_groups
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.community_identification_activity_actors
    ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA internal TO service_role;

REVOKE ALL ON TABLE
    internal.community_identification_activity_groups,
    internal.community_identification_activity_actors
FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    internal.community_identification_activity_groups,
    internal.community_identification_activity_actors
TO service_role;

CREATE OR REPLACE FUNCTION internal.upsert_community_identification_suggestion_activity(
    p_request_id UUID,
    p_post_id UUID,
    p_user_id UUID,
    p_taxon_node_id UUID,
    p_suggested_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    request_row RECORD;
    target_group_id UUID;
BEGIN
    -- Locking the request serializes concurrent suggestions so they cannot
    -- create duplicate bursts for the same sixty-minute window.
    SELECT
        community_request.post_id,
        community_request.requested_at
    INTO request_row
    FROM public.explore_community_requests AS community_request
    WHERE community_request.id = p_request_id
      AND community_request.post_id = p_post_id
      AND p_suggested_at >= community_request.requested_at
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT activity_group.id
    INTO target_group_id
    FROM internal.community_identification_activity_groups AS activity_group
    WHERE activity_group.request_id = p_request_id
      AND activity_group.post_id = p_post_id
      AND activity_group.request_generation_at = request_row.requested_at
      AND activity_group.activity_type = 'suggestion_burst'
      AND activity_group.activity_at <= p_suggested_at
      AND activity_group.activity_at >= (
          p_suggested_at - INTERVAL '60 minutes'
      )
    ORDER BY activity_group.activity_at DESC, activity_group.id DESC
    LIMIT 1
    FOR UPDATE;

    IF target_group_id IS NULL THEN
        INSERT INTO internal.community_identification_activity_groups (
            request_id,
            post_id,
            request_generation_at,
            activity_type,
            burst_started_at,
            activity_at,
            latest_taxon_node_id
        )
        VALUES (
            p_request_id,
            p_post_id,
            request_row.requested_at,
            'suggestion_burst',
            p_suggested_at,
            p_suggested_at,
            p_taxon_node_id
        )
        RETURNING id INTO target_group_id;
    ELSE
        UPDATE internal.community_identification_activity_groups AS activity_group
        SET activity_at = GREATEST(activity_group.activity_at, p_suggested_at),
            latest_taxon_node_id = p_taxon_node_id,
            updated_at = NOW()
        WHERE activity_group.id = target_group_id;
    END IF;

    INSERT INTO internal.community_identification_activity_actors AS activity_actor (
        activity_group_id,
        user_id,
        suggestion_count,
        last_suggested_at
    )
    VALUES (
        target_group_id,
        p_user_id,
        1,
        p_suggested_at
    )
    ON CONFLICT (activity_group_id, user_id) DO UPDATE
    SET suggestion_count = activity_actor.suggestion_count + 1,
        last_suggested_at = GREATEST(
            activity_actor.last_suggested_at,
            EXCLUDED.last_suggested_at
        );

    RETURN target_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.record_community_identification_suggestion_activity()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    PERFORM internal.upsert_community_identification_suggestion_activity(
        NEW.request_id,
        NEW.post_id,
        NEW.user_id,
        NEW.taxon_node_id,
        NEW.created_at
    );
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.record_community_consensus_activity_event(
    p_event_id UUID,
    p_request_id UUID,
    p_post_id UUID,
    p_previous_status TEXT,
    p_new_status TEXT,
    p_previous_taxon_node_id UUID,
    p_new_taxon_node_id UUID,
    p_previous_rank TEXT,
    p_new_rank TEXT,
    p_new_score DOUBLE PRECISION,
    p_reason TEXT,
    p_created_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    request_row RECORD;
    target_group_id UUID;
BEGIN
    SELECT
        community_request.post_id,
        community_request.requested_at
    INTO request_row
    FROM public.explore_community_requests AS community_request
    WHERE community_request.id = p_request_id
      AND community_request.post_id = p_post_id
      AND p_created_at >= community_request.requested_at
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF p_new_status = 'resolved'
       AND p_previous_status IS DISTINCT FROM p_new_status
       AND p_new_taxon_node_id IS NOT NULL THEN
        INSERT INTO internal.community_identification_activity_groups (
            request_id,
            post_id,
            request_generation_at,
            activity_type,
            burst_started_at,
            activity_at,
            latest_taxon_node_id,
            consensus_score,
            source_consensus_event_id
        )
        VALUES (
            p_request_id,
            p_post_id,
            request_row.requested_at,
            'resolved',
            p_created_at,
            p_created_at,
            p_new_taxon_node_id,
            p_new_score,
            p_event_id
        )
        ON CONFLICT (source_consensus_event_id)
            WHERE source_consensus_event_id IS NOT NULL
        DO NOTHING
        RETURNING id INTO target_group_id;

        RETURN target_group_id;
    END IF;

    -- Submission-triggered count- or score-only recalculations are represented
    -- by the associated suggestion burst. The same change without a new
    -- suggestion falls through to a standalone consensus milestone.
    IF p_previous_status IS NOT DISTINCT FROM p_new_status
       AND p_previous_taxon_node_id IS NOT DISTINCT FROM p_new_taxon_node_id
       AND p_previous_rank IS NOT DISTINCT FROM p_new_rank THEN
        IF p_reason = 'identification_submitted' THEN
            SELECT activity_group.id
            INTO target_group_id
            FROM internal.community_identification_activity_groups AS activity_group
            WHERE activity_group.request_id = p_request_id
              AND activity_group.request_generation_at = request_row.requested_at
              AND activity_group.activity_type = 'suggestion_burst'
              AND activity_group.burst_started_at <= p_created_at
            ORDER BY
                activity_group.burst_started_at DESC,
                activity_group.id DESC
            LIMIT 1
            FOR UPDATE;

            IF target_group_id IS NOT NULL THEN
                UPDATE internal.community_identification_activity_groups
                SET latest_taxon_node_id = COALESCE(
                        p_new_taxon_node_id,
                        latest_taxon_node_id
                    ),
                    consensus_score = p_new_score,
                    updated_at = NOW()
                WHERE id = target_group_id;
            END IF;

            RETURN target_group_id;
        END IF;
    END IF;

    IF p_reason = 'identification_submitted' THEN
        SELECT activity_group.id
        INTO target_group_id
        FROM internal.community_identification_activity_groups AS activity_group
        WHERE activity_group.request_id = p_request_id
          AND activity_group.request_generation_at = request_row.requested_at
          AND activity_group.activity_type = 'suggestion_burst'
          AND activity_group.burst_started_at <= p_created_at
        ORDER BY
            activity_group.burst_started_at DESC,
            activity_group.id DESC
        LIMIT 1
        FOR UPDATE;

        IF target_group_id IS NOT NULL THEN
            UPDATE internal.community_identification_activity_groups
            SET latest_taxon_node_id = COALESCE(
                    p_new_taxon_node_id,
                    latest_taxon_node_id
                ),
                consensus_score = p_new_score,
                updated_at = NOW()
            WHERE id = target_group_id;
            RETURN target_group_id;
        END IF;
    END IF;

    INSERT INTO internal.community_identification_activity_groups (
        request_id,
        post_id,
        request_generation_at,
        activity_type,
        burst_started_at,
        activity_at,
        latest_taxon_node_id,
        consensus_score,
        source_consensus_event_id
    )
    VALUES (
        p_request_id,
        p_post_id,
        request_row.requested_at,
        'consensus_changed',
        p_created_at,
        p_created_at,
        p_new_taxon_node_id,
        p_new_score,
        p_event_id
    )
    ON CONFLICT (source_consensus_event_id)
        WHERE source_consensus_event_id IS NOT NULL
    DO NOTHING
    RETURNING id INTO target_group_id;

    RETURN target_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.record_community_consensus_activity()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    PERFORM internal.record_community_consensus_activity_event(
        NEW.id,
        NEW.request_id,
        NEW.post_id,
        NEW.previous_status::TEXT,
        NEW.new_status::TEXT,
        NEW.previous_taxon_node_id,
        NEW.new_taxon_node_id,
        NEW.previous_rank,
        NEW.new_rank,
        NEW.new_score,
        NEW.reason,
        NEW.created_at
    );
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION
    internal.upsert_community_identification_suggestion_activity(
        UUID,
        UUID,
        UUID,
        UUID,
        TIMESTAMPTZ
    ),
    internal.record_community_identification_suggestion_activity(),
    internal.record_community_consensus_activity_event(
        UUID,
        UUID,
        UUID,
        TEXT,
        TEXT,
        UUID,
        UUID,
        TEXT,
        TEXT,
        DOUBLE PRECISION,
        TEXT,
        TIMESTAMPTZ
    ),
    internal.record_community_consensus_activity()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    internal.upsert_community_identification_suggestion_activity(
        UUID,
        UUID,
        UUID,
        UUID,
        TIMESTAMPTZ
    ),
    internal.record_community_identification_suggestion_activity(),
    internal.record_community_consensus_activity_event(
        UUID,
        UUID,
        UUID,
        TEXT,
        TEXT,
        UUID,
        UUID,
        TEXT,
        TEXT,
        DOUBLE PRECISION,
        TEXT,
        TIMESTAMPTZ
    ),
    internal.record_community_consensus_activity()
TO service_role;

-- Seed the current request generation so Activity is useful immediately after
-- deployment. Prior withdrawn/reopened generations stay in the audit timeline.
DO $block$
DECLARE
    identification_row RECORD;
    consensus_event_row RECORD;
BEGIN
    FOR identification_row IN
        SELECT
            identification.request_id,
            identification.post_id,
            identification.user_id,
            identification.taxon_node_id,
            identification.created_at
        FROM public.explore_identifications AS identification
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = identification.request_id
        WHERE identification.created_at >= community_request.requested_at
        ORDER BY
            identification.request_id,
            identification.created_at,
            identification.id
    LOOP
        PERFORM internal.upsert_community_identification_suggestion_activity(
            identification_row.request_id,
            identification_row.post_id,
            identification_row.user_id,
            identification_row.taxon_node_id,
            identification_row.created_at
        );
    END LOOP;

    FOR consensus_event_row IN
        SELECT consensus_event.*
        FROM public.community_consensus_events AS consensus_event
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = consensus_event.request_id
        WHERE consensus_event.created_at >= community_request.requested_at
        ORDER BY
            consensus_event.request_id,
            consensus_event.created_at,
            consensus_event.id
    LOOP
        PERFORM internal.record_community_consensus_activity_event(
            consensus_event_row.id,
            consensus_event_row.request_id,
            consensus_event_row.post_id,
            consensus_event_row.previous_status::TEXT,
            consensus_event_row.new_status::TEXT,
            consensus_event_row.previous_taxon_node_id,
            consensus_event_row.new_taxon_node_id,
            consensus_event_row.previous_rank,
            consensus_event_row.new_rank,
            consensus_event_row.new_score,
            consensus_event_row.reason,
            consensus_event_row.created_at
        );
    END LOOP;
END;
$block$;

DROP TRIGGER IF EXISTS trg_record_community_identification_suggestion_activity
    ON public.explore_identifications;
CREATE TRIGGER trg_record_community_identification_suggestion_activity
AFTER INSERT
ON public.explore_identifications
FOR EACH ROW
EXECUTE FUNCTION internal.record_community_identification_suggestion_activity();

DROP TRIGGER IF EXISTS trg_record_community_consensus_activity
    ON public.community_consensus_events;
CREATE TRIGGER trg_record_community_consensus_activity
AFTER INSERT
ON public.community_consensus_events
FOR EACH ROW
EXECUTE FUNCTION internal.record_community_consensus_activity();

CREATE OR REPLACE FUNCTION public.community_identification_request_group(
    p_taxon_node_id UUID
)
RETURNS TEXT
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    WITH selected_taxon AS (
        SELECT
            taxon.taxonomy_version_id,
            taxon.path
        FROM public.taxon_nodes AS taxon
        WHERE taxon.id = p_taxon_node_id
    ),
    lineage AS (
        SELECT
            LOWER(ancestor.rank) AS rank,
            LOWER(BTRIM(ancestor.scientific_name)) AS scientific_name
        FROM selected_taxon
        INNER JOIN public.taxon_nodes AS ancestor
            ON ancestor.taxonomy_version_id
                = selected_taxon.taxonomy_version_id
           AND ancestor.path
                OPERATOR(public.@>) selected_taxon.path
    )
    SELECT CASE
        WHEN COALESCE(BOOL_OR(
            lineage.rank = 'kingdom'
            AND lineage.scientific_name = 'plantae'
        ), FALSE) THEN 'plants'
        WHEN COALESCE(BOOL_OR(
            lineage.rank = 'class'
            AND lineage.scientific_name = 'aves'
        ), FALSE) THEN 'birds'
        WHEN COALESCE(BOOL_OR(
            lineage.rank = 'class'
            AND lineage.scientific_name IN (
                'insecta',
                'entognatha',
                'arachnida'
            )
        ), FALSE) THEN 'insects'
        WHEN COALESCE(BOOL_OR(
            lineage.rank = 'kingdom'
            AND lineage.scientific_name = 'fungi'
        ), FALSE) THEN 'fungi'
        WHEN COALESCE(BOOL_OR(
            lineage.rank = 'class'
            AND lineage.scientific_name = 'mammalia'
        ), FALSE) THEN 'mammals'
        WHEN COALESCE(BOOL_OR(
            (
                lineage.rank = 'class'
                AND lineage.scientific_name IN ('reptilia', 'amphibia')
            )
            OR (
                lineage.rank = 'order'
                AND lineage.scientific_name = 'squamata'
            )
        ), FALSE) THEN 'reptiles_amphibians'
        ELSE 'all'
    END
    FROM lineage;
$function$;

REVOKE ALL ON FUNCTION public.community_identification_request_group(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.community_identification_request_group(UUID)
TO authenticated, service_role;

-- Keep the existing Requests feed and the new Activity feed on one taxonomy
-- classifier. Taxon paths use hashed ltree labels, so category matching must
-- inspect lineage names instead of matching literal names in path text.
CREATE OR REPLACE FUNCTION public.get_community_identification_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_requested_at TIMESTAMPTZ DEFAULT NULL,
    before_request_id UUID DEFAULT NULL,
    viewer_latitude DOUBLE PRECISION DEFAULT NULL,
    viewer_longitude DOUBLE PRECISION DEFAULT NULL,
    request_scope TEXT DEFAULT 'all',
    request_group_filter TEXT DEFAULT 'all'
)
RETURNS TABLE(
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    requested_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_avatar_url TEXT,
    taxonomy_version_id UUID,
    projection_state TEXT,
    consensus_processing_state TEXT,
    current_taxon_id UUID,
    current_common_name TEXT,
    current_scientific_name TEXT,
    current_rank TEXT,
    current_path TEXT,
    initial_taxon_id UUID,
    initial_common_name TEXT,
    initial_scientific_name TEXT,
    initial_rank TEXT,
    initial_path TEXT,
    request_group TEXT,
    consensus_score DOUBLE PRECISION,
    identification_count INTEGER,
    viewer_has_identified BOOLEAN,
    public_location_label TEXT,
    location_sharing TEXT
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    WITH visible_requests AS (
        SELECT
            community_request.id AS request_id,
            explore_post.id AS post_id,
            explore_post.scan_id,
            public.explore_post_hero_image_url(explore_post.id)
                AS hero_image_url,
            community_request.requested_at,
            explore_post.user_id AS author_user_id,
            request_owner.public_author_name AS author_name,
            request_owner.public_avatar_url AS author_avatar_url,
            community_request.taxonomy_version_id,
            projection.projection_state::TEXT AS projection_state,
            community_request.consensus_processing_state,
            COALESCE(
                community_request.current_community_taxon_node_id,
                community_request.initial_taxon_node_id
            ) AS current_taxon_id,
            current_taxon.common_name AS current_common_name,
            current_taxon.scientific_name AS current_scientific_name,
            current_taxon.rank AS current_rank,
            current_taxon.path::TEXT AS current_path,
            community_request.initial_taxon_node_id AS initial_taxon_id,
            initial_taxon.common_name AS initial_common_name,
            initial_taxon.scientific_name AS initial_scientific_name,
            initial_taxon.rank AS initial_rank,
            initial_taxon.path::TEXT AS initial_path,
            public.community_identification_request_group(
                COALESCE(
                    community_request.current_community_taxon_node_id,
                    community_request.initial_taxon_node_id
                )
            ) AS request_group,
            community_request.consensus_score,
            community_request.consensus_identification_count
                AS identification_count,
            EXISTS (
                SELECT 1
                FROM public.explore_identifications AS identification
                WHERE identification.request_id = community_request.id
                  AND identification.user_id = self_id
                  AND identification.withdrawn_at IS NULL
            ) AS viewer_has_identified,
            explore_post.public_location_label,
            explore_post.location_sharing::TEXT,
            CASE
                WHEN viewer_latitude IS NULL
                    OR viewer_longitude IS NULL
                    OR explore_post.public_latitude IS NULL
                    OR explore_post.public_longitude IS NULL
                    THEN NULL
                ELSE public.haversine_distance_meters(
                    explore_post.public_latitude,
                    explore_post.public_longitude,
                    viewer_latitude,
                    viewer_longitude
                )
            END AS distance_meters
        FROM public.explore_community_requests AS community_request
        INNER JOIN public.explore_observation_projection AS projection
            ON projection.community_request_id = community_request.id
           AND projection.projection_state = 'community_needs_id'
        INNER JOIN public.explore_posts AS explore_post
            ON explore_post.id = community_request.post_id
        INNER JOIN public.scans AS scan
            ON scan.id = explore_post.scan_id
        INNER JOIN public.users AS request_owner
            ON request_owner.id = explore_post.user_id
        LEFT JOIN public.taxon_nodes AS current_taxon
            ON current_taxon.id = COALESCE(
                community_request.current_community_taxon_node_id,
                community_request.initial_taxon_node_id
            )
        LEFT JOIN public.taxon_nodes AS initial_taxon
            ON initial_taxon.id = community_request.initial_taxon_node_id
        WHERE community_request.status = 'needs_id'
          AND community_request.withdrawn_at IS NULL
          AND explore_post.unshared_at IS NULL
          AND explore_post.moderated_at IS NULL
          AND explore_post.media_health_status <> 'quarantined'
          AND scan.is_tombstoned = FALSE
          AND request_owner.is_shadowbanned = FALSE
          AND EXISTS (
              SELECT 1
              FROM public.explore_post_media AS visible_media
              WHERE visible_media.post_id = explore_post.id
                AND visible_media.health_status <> 'missing'
          )
          AND (
              COALESCE(request_scope, 'all') = 'all'
              OR (
                  request_scope = 'mine'
                  AND community_request.requested_by = self_id
              )
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks AS owner_block
              WHERE (
                  owner_block.blocker_id = self_id
                  AND owner_block.blocked_id = explore_post.user_id
              ) OR (
                  owner_block.blocker_id = explore_post.user_id
                  AND owner_block.blocked_id = self_id
              )
          )
          AND (
              before_requested_at IS NULL
              OR before_request_id IS NULL
              OR community_request.requested_at < before_requested_at
              OR (
                  community_request.requested_at = before_requested_at
                  AND community_request.id < before_request_id
              )
          )
    )
    SELECT
        request_id,
        post_id,
        scan_id,
        hero_image_url,
        requested_at,
        author_user_id,
        author_name,
        author_avatar_url,
        taxonomy_version_id,
        projection_state,
        consensus_processing_state,
        current_taxon_id,
        current_common_name,
        current_scientific_name,
        current_rank,
        current_path,
        initial_taxon_id,
        initial_common_name,
        initial_scientific_name,
        initial_rank,
        initial_path,
        request_group,
        consensus_score,
        identification_count,
        viewer_has_identified,
        public_location_label,
        location_sharing
    FROM visible_requests
    WHERE COALESCE(request_group_filter, 'all') = 'all'
       OR request_group = request_group_filter
    ORDER BY
        CASE WHEN distance_meters IS NULL THEN 1 ELSE 0 END,
        distance_meters ASC NULLS LAST,
        requested_at DESC,
        request_id DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 30), 0), 100);
$function$;

CREATE OR REPLACE FUNCTION public.get_community_identification_activity(
    self_id UUID,
    max_limit INTEGER DEFAULT 30,
    before_activity_at TIMESTAMPTZ DEFAULT NULL,
    before_activity_id UUID DEFAULT NULL,
    request_scope TEXT DEFAULT 'all',
    request_group_filter TEXT DEFAULT 'all'
)
RETURNS TABLE(
    activity_id UUID,
    activity_type TEXT,
    request_id UUID,
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    activity_at TIMESTAMPTZ,
    suggestion_count INTEGER,
    recent_actor_names TEXT[],
    taxon_id UUID,
    taxon_common_name TEXT,
    taxon_scientific_name TEXT,
    taxon_rank TEXT,
    consensus_score DOUBLE PRECISION,
    request_group TEXT,
    media_items JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    WITH visible_activity AS (
        SELECT
            activity_group.id AS activity_id,
            activity_group.activity_type,
            community_request.id AS request_id,
            explore_post.id AS post_id,
            explore_post.scan_id,
            public.explore_post_hero_image_url(explore_post.id)
                AS hero_image_url,
            activity_group.activity_at,
            CASE
                WHEN activity_group.activity_type = 'suggestion_burst'
                THEN visible_actor_count.suggestion_count
                ELSE 0
            END AS suggestion_count,
            CASE
                WHEN activity_group.activity_type = 'suggestion_burst'
                THEN recent_actors.actor_names
                ELSE ARRAY[]::TEXT[]
            END AS recent_actor_names,
            display_taxon.id AS taxon_id,
            display_taxon.common_name AS taxon_common_name,
            display_taxon.scientific_name AS taxon_scientific_name,
            display_taxon.rank AS taxon_rank,
            activity_group.consensus_score,
            public.community_identification_request_group(filter_taxon.id)
                AS request_group,
            public.explore_post_media_items(explore_post.id) AS media_items
        FROM internal.community_identification_activity_groups AS activity_group
        INNER JOIN public.explore_community_requests AS community_request
            ON community_request.id = activity_group.request_id
           AND community_request.post_id = activity_group.post_id
           AND community_request.requested_at
                = activity_group.request_generation_at
        INNER JOIN public.explore_observation_projection AS projection
            ON projection.community_request_id = community_request.id
        INNER JOIN public.explore_posts AS explore_post
            ON explore_post.id = community_request.post_id
        INNER JOIN public.scans AS scan
            ON scan.id = explore_post.scan_id
        INNER JOIN public.users AS request_owner
            ON request_owner.id = explore_post.user_id
        LEFT JOIN public.taxon_nodes AS filter_taxon
            ON filter_taxon.id = COALESCE(
                community_request.current_community_taxon_node_id,
                community_request.resolved_taxon_node_id,
                community_request.initial_taxon_node_id
            )
        LEFT JOIN public.taxon_nodes AS display_taxon
            ON display_taxon.id = COALESCE(
                activity_group.latest_taxon_node_id,
                community_request.current_community_taxon_node_id,
                community_request.resolved_taxon_node_id,
                community_request.initial_taxon_node_id
            )
        LEFT JOIN LATERAL (
            SELECT COALESCE(
                SUM(activity_actor.suggestion_count),
                0
            )::INTEGER AS suggestion_count
            FROM internal.community_identification_activity_actors
                AS activity_actor
            INNER JOIN public.users AS actor_user
                ON actor_user.id = activity_actor.user_id
            WHERE activity_actor.activity_group_id = activity_group.id
              AND actor_user.is_shadowbanned = FALSE
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks AS actor_block
                  WHERE (
                      actor_block.blocker_id = self_id
                      AND actor_block.blocked_id = actor_user.id
                  ) OR (
                      actor_block.blocker_id = actor_user.id
                      AND actor_block.blocked_id = self_id
                  )
              )
        ) AS visible_actor_count ON TRUE
        LEFT JOIN LATERAL (
            SELECT COALESCE(
                ARRAY_AGG(
                    recent_actor.actor_name
                    ORDER BY
                        recent_actor.last_suggested_at DESC,
                        recent_actor.user_id DESC
                ),
                ARRAY[]::TEXT[]
            ) AS actor_names
            FROM (
                SELECT
                    activity_actor.user_id,
                    COALESCE(
                        NULLIF(BTRIM(actor_user.public_author_name), ''),
                        'Naturebook explorer'
                    ) AS actor_name,
                    activity_actor.last_suggested_at
                FROM internal.community_identification_activity_actors
                    AS activity_actor
                INNER JOIN public.users AS actor_user
                    ON actor_user.id = activity_actor.user_id
                WHERE activity_actor.activity_group_id = activity_group.id
                  AND actor_user.is_shadowbanned = FALSE
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.user_blocks AS actor_block
                      WHERE (
                          actor_block.blocker_id = self_id
                          AND actor_block.blocked_id = actor_user.id
                      ) OR (
                          actor_block.blocker_id = actor_user.id
                          AND actor_block.blocked_id = self_id
                      )
                  )
                ORDER BY
                    activity_actor.last_suggested_at DESC,
                    activity_actor.user_id DESC
                LIMIT 3
            ) AS recent_actor
        ) AS recent_actors ON TRUE
        WHERE community_request.withdrawn_at IS NULL
          AND explore_post.unshared_at IS NULL
          AND explore_post.moderated_at IS NULL
          AND explore_post.media_health_status <> 'quarantined'
          AND scan.is_tombstoned = FALSE
          AND request_owner.is_shadowbanned = FALSE
          AND EXISTS (
              SELECT 1
              FROM public.explore_post_media AS visible_media
              WHERE visible_media.post_id = explore_post.id
                AND visible_media.health_status <> 'missing'
          )
          AND (
              activity_group.activity_type <> 'suggestion_burst'
              OR visible_actor_count.suggestion_count > 0
          )
          AND (
              COALESCE(request_scope, 'all') = 'all'
              OR (
                  request_scope = 'mine'
                  AND community_request.requested_by = self_id
              )
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks AS owner_block
              WHERE (
                  owner_block.blocker_id = self_id
                  AND owner_block.blocked_id = explore_post.user_id
              ) OR (
                  owner_block.blocker_id = explore_post.user_id
                  AND owner_block.blocked_id = self_id
              )
          )
          AND (
              before_activity_at IS NULL
              OR before_activity_id IS NULL
              OR activity_group.activity_at < before_activity_at
              OR (
                  activity_group.activity_at = before_activity_at
                  AND activity_group.id < before_activity_id
              )
          )
    )
    SELECT
        activity_id,
        activity_type,
        request_id,
        post_id,
        scan_id,
        hero_image_url,
        activity_at,
        suggestion_count,
        recent_actor_names,
        taxon_id,
        taxon_common_name,
        taxon_scientific_name,
        taxon_rank,
        consensus_score,
        request_group,
        media_items
    FROM visible_activity
    WHERE COALESCE(request_group_filter, 'all') = 'all'
       OR request_group = request_group_filter
    ORDER BY activity_at DESC, activity_id DESC
    LIMIT LEAST(GREATEST(COALESCE(max_limit, 30), 0), 100);
$function$;

REVOKE ALL ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) TO service_role;

COMMENT ON FUNCTION public.get_community_identification_activity(
    UUID,
    INTEGER,
    TIMESTAMPTZ,
    UUID,
    TEXT,
    TEXT
) IS
    'Service-only cursor feed of visible grouped Community Identify activity.';

RESET statement_timeout;
RESET lock_timeout;

NOTIFY pgrst, 'reload schema';

-- Field Trips v4: curated seasonal community challenges.
-- Challenges are Field Trips-native, non-competitive, and separate from normal
-- Explore feed, map, widget, APNs, prize, and leaderboard infrastructure.

CREATE TABLE IF NOT EXISTS public.field_trip_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES public.field_trip_templates(id) ON DELETE CASCADE,
    slug TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9_\\-]{2,80}$'),
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    subtitle TEXT,
    description TEXT,
    cover_image_url TEXT,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    region_tags TEXT[] NOT NULL DEFAULT '{}',
    season_tags TEXT[] NOT NULL DEFAULT '{}',
    habitat_tags TEXT[] NOT NULL DEFAULT '{}',
    suggested_hashtags TEXT[] NOT NULL DEFAULT '{}',
    is_pro_only BOOLEAN NOT NULL DEFAULT FALSE,
    is_temporarily_free BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (starts_at < ends_at)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES public.field_trip_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_field_trip_id UUID NOT NULL REFERENCES public.user_field_trips(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_level_number INTEGER NOT NULL DEFAULT 1 CHECK (current_level_number > 0),
    completed_at TIMESTAMPTZ,
    badge_awarded_at TIMESTAMPTZ,
    is_profile_visible BOOLEAN NOT NULL DEFAULT TRUE,
    hidden_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, challenge_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_item_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participation_id UUID NOT NULL REFERENCES public.field_trip_challenge_participants(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.field_trip_checklist_items(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    common_name TEXT,
    scientific_name TEXT,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(participation_id, item_id),
    UNIQUE(participation_id, scan_id, item_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participation_id UUID NOT NULL UNIQUE REFERENCES public.field_trip_challenge_participants(id) ON DELETE CASCADE,
    challenge_id UUID NOT NULL REFERENCES public.field_trip_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    badge_key TEXT NOT NULL CHECK (badge_key ~ '^[a-z0-9][a-z0-9_\\-]{2,100}$'),
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    awarded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_profile_visible BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, challenge_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participation_id UUID NOT NULL UNIQUE REFERENCES public.field_trip_challenge_participants(id) ON DELETE CASCADE,
    challenge_id UUID NOT NULL REFERENCES public.field_trip_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES public.field_trip_templates(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    description TEXT,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    like_count INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES public.field_trip_challenge_entries(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.field_trip_checklist_items(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    species_id UUID REFERENCES public.species_dictionary(id) ON DELETE SET NULL,
    common_name TEXT,
    scientific_name TEXT,
    hero_image_url TEXT,
    reference_image_url TEXT,
    taxonomy JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(entry_id, item_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_likes (
    entry_id UUID NOT NULL REFERENCES public.field_trip_challenge_entries(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(entry_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.field_trip_challenge_entry_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES public.field_trip_challenge_entries(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES public.field_trip_challenge_entry_comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK (LENGTH(BTRIM(body)) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    moderated_at TIMESTAMPTZ
);

COMMENT ON TABLE public.field_trip_challenges IS
    'Curated seasonal Field Trip challenge definitions. Challenges are admin-created and never create Explore posts, maps, widgets, APNs, prizes, or leaderboards.';
COMMENT ON TABLE public.field_trip_challenge_participants IS
    'Private explicit challenge joins. Active progress is not public except aggregate counts and profile-visible completion badges.';
COMMENT ON TABLE public.field_trip_challenge_entries IS
    'Challenge-specific published completion snapshots. These are distinct from normal Field Trip publications so seasonal participation can repeat.';
COMMENT ON TABLE public.field_trip_challenge_badges IS
    'Completion badges for non-competitive Field Trip challenges. Profile-visible badges expose no scan evidence.';

CREATE INDEX IF NOT EXISTS idx_field_trip_challenges_active_window
    ON public.field_trip_challenges(is_active, starts_at, ends_at, sort_order);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenges_template
    ON public.field_trip_challenges(template_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenges_region_tags_gin
    ON public.field_trip_challenges USING GIN(region_tags);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenges_habitat_tags_gin
    ON public.field_trip_challenges USING GIN(habitat_tags);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_participants_user
    ON public.field_trip_challenge_participants(user_id, joined_at DESC)
    WHERE hidden_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_participants_challenge
    ON public.field_trip_challenge_participants(challenge_id, completed_at, joined_at DESC)
    WHERE hidden_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_completions_participant
    ON public.field_trip_challenge_item_completions(participation_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_badges_user_visible
    ON public.field_trip_challenge_badges(user_id, awarded_at DESC)
    WHERE is_profile_visible = TRUE;
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_entries_challenge_published
    ON public.field_trip_challenge_entries(challenge_id, published_at DESC, id DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_entries_user_published
    ON public.field_trip_challenge_entries(user_id, published_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_entry_items_entry_sort
    ON public.field_trip_challenge_entry_items(entry_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_field_trip_challenge_entry_comments_entry
    ON public.field_trip_challenge_entry_comments(entry_id, created_at, id)
    WHERE deleted_at IS NULL AND moderated_at IS NULL;

DROP TRIGGER IF EXISTS trg_field_trip_challenges_touch_updated_at ON public.field_trip_challenges;
CREATE TRIGGER trg_field_trip_challenges_touch_updated_at
BEFORE UPDATE ON public.field_trip_challenges
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

DROP TRIGGER IF EXISTS trg_field_trip_challenge_participants_touch_updated_at ON public.field_trip_challenge_participants;
CREATE TRIGGER trg_field_trip_challenge_participants_touch_updated_at
BEFORE UPDATE ON public.field_trip_challenge_participants
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

DROP TRIGGER IF EXISTS trg_field_trip_challenge_entries_touch_updated_at ON public.field_trip_challenge_entries;
CREATE TRIGGER trg_field_trip_challenge_entries_touch_updated_at
BEFORE UPDATE ON public.field_trip_challenge_entries
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_touch_updated_at();

DROP TRIGGER IF EXISTS trg_field_trip_challenge_comments_touch_updated_at ON public.field_trip_challenge_entry_comments;
CREATE TRIGGER trg_field_trip_challenge_comments_touch_updated_at
BEFORE UPDATE ON public.field_trip_challenge_entry_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_set_comment_updated_at();

CREATE OR REPLACE FUNCTION public.field_trip_challenge_entry_like_count_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.field_trip_challenge_entries
    SET like_count = like_count + 1
    WHERE id = NEW.entry_id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.field_trip_challenge_entry_like_count_after_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.field_trip_challenge_entries
    SET like_count = GREATEST(0, like_count - 1)
    WHERE id = OLD.entry_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_challenge_entry_like_count_after_insert ON public.field_trip_challenge_entry_likes;
CREATE TRIGGER trg_field_trip_challenge_entry_like_count_after_insert
AFTER INSERT ON public.field_trip_challenge_entry_likes
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_challenge_entry_like_count_after_insert();

DROP TRIGGER IF EXISTS trg_field_trip_challenge_entry_like_count_after_delete ON public.field_trip_challenge_entry_likes;
CREATE TRIGGER trg_field_trip_challenge_entry_like_count_after_delete
AFTER DELETE ON public.field_trip_challenge_entry_likes
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_challenge_entry_like_count_after_delete();

CREATE OR REPLACE FUNCTION public.recompute_field_trip_challenge_entry_comment_count(target_entry_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    computed_count INTEGER := 0;
BEGIN
    SELECT COUNT(*)::INTEGER
    INTO computed_count
    FROM public.field_trip_challenge_entry_comments c
    WHERE c.entry_id = target_entry_id
      AND c.deleted_at IS NULL
      AND c.moderated_at IS NULL;

    UPDATE public.field_trip_challenge_entries
    SET comment_count = computed_count
    WHERE id = target_entry_id;

    RETURN computed_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.field_trip_challenge_entry_comment_count_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recompute_field_trip_challenge_entry_comment_count(OLD.entry_id);
        RETURN OLD;
    END IF;

    PERFORM public.recompute_field_trip_challenge_entry_comment_count(NEW.entry_id);
    IF TG_OP = 'UPDATE' AND OLD.entry_id <> NEW.entry_id THEN
        PERFORM public.recompute_field_trip_challenge_entry_comment_count(OLD.entry_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_challenge_entry_comment_count ON public.field_trip_challenge_entry_comments;
CREATE TRIGGER trg_field_trip_challenge_entry_comment_count
AFTER INSERT OR UPDATE OF deleted_at, moderated_at, entry_id OR DELETE ON public.field_trip_challenge_entry_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_challenge_entry_comment_count_trigger();

CREATE OR REPLACE FUNCTION public.field_trip_challenge_validate_comment_parent()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    parent_row RECORD;
BEGIN
    IF NEW.parent_comment_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id, entry_id, parent_comment_id, deleted_at, moderated_at
    INTO parent_row
    FROM public.field_trip_challenge_entry_comments
    WHERE id = NEW.parent_comment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip challenge parent comment not found';
    END IF;
    IF parent_row.entry_id <> NEW.entry_id THEN
        RAISE EXCEPTION 'Field Trip challenge parent comment must belong to the same entry';
    END IF;
    IF parent_row.parent_comment_id IS NOT NULL THEN
        RAISE EXCEPTION 'Field Trip challenge replies can only target top-level comments';
    END IF;
    IF parent_row.deleted_at IS NOT NULL OR parent_row.moderated_at IS NOT NULL THEN
        RAISE EXCEPTION 'Field Trip challenge parent comment is no longer available';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_field_trip_challenge_comments_validate_parent ON public.field_trip_challenge_entry_comments;
CREATE TRIGGER trg_field_trip_challenge_comments_validate_parent
BEFORE INSERT OR UPDATE OF parent_comment_id, entry_id ON public.field_trip_challenge_entry_comments
FOR EACH ROW
EXECUTE FUNCTION public.field_trip_challenge_validate_comment_parent();

CREATE OR REPLACE FUNCTION public.field_trip_challenge_status(
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
        WHEN NOW() < starts_at THEN 'upcoming'
        WHEN NOW() > ends_at THEN 'ended'
        ELSE 'live'
    END;
$$;

CREATE OR REPLACE FUNCTION public.can_view_field_trip_challenge_entry(self_id UUID, target_entry_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_entries e
        JOIN public.users u
            ON u.id = e.user_id
        WHERE e.id = target_entry_id
          AND e.deleted_at IS NULL
          AND u.is_shadowbanned = FALSE
          AND (
              e.user_id = self_id
              OR NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = e.user_id)
                     OR (ub.blocker_id = e.user_id AND ub.blocked_id = self_id)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_publications(
    self_id UUID,
    target_challenge_id UUID,
    max_limit INTEGER DEFAULT 20,
    before_published_at TIMESTAMPTZ DEFAULT NULL,
    before_entry_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 20), 60));
    response JSONB := '[]'::jsonb;
BEGIN
    IF (before_published_at IS NULL) <> (before_entry_id IS NULL) THEN
        RAISE EXCEPTION 'before_published_at and before_entry_id must be provided together';
    END IF;

    WITH visible_entries AS (
        SELECT
            e.id AS entry_id,
            e.challenge_id,
            e.title,
            e.description,
            e.published_at,
            e.like_count,
            e.comment_count,
            c.slug AS challenge_slug,
            c.title AS challenge_title,
            c.region_tags,
            c.season_tags,
            c.habitat_tags,
            t.id AS template_id,
            t.slug AS template_slug,
            t.title AS template_title,
            e.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_username AS author_username,
            u.public_avatar_url AS author_avatar_url,
            (
                SELECT COALESCE(cei.hero_image_url, cei.reference_image_url)
                FROM public.field_trip_challenge_entry_items cei
                WHERE cei.entry_id = e.id
                  AND COALESCE(NULLIF(BTRIM(cei.hero_image_url), ''), NULLIF(BTRIM(cei.reference_image_url), '')) IS NOT NULL
                ORDER BY cei.sort_order
                LIMIT 1
            ) AS item_cover_image_url,
            COALESCE(c.cover_image_url, t.cover_image_url) AS template_cover_image_url,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_entry_items cei
                WHERE cei.entry_id = e.id
            ) AS item_count,
            EXISTS (
                SELECT 1
                FROM public.field_trip_challenge_entry_likes l
                WHERE l.entry_id = e.id
                  AND l.user_id = self_id
            ) AS viewer_has_liked
        FROM public.field_trip_challenge_entries e
        JOIN public.field_trip_challenges c
            ON c.id = e.challenge_id
        JOIN public.field_trip_templates t
            ON t.id = e.template_id
        JOIN public.users u
            ON u.id = e.user_id
        WHERE e.challenge_id = target_challenge_id
          AND e.deleted_at IS NULL
          AND public.can_view_field_trip_challenge_entry(self_id, e.id)
          AND (
              before_published_at IS NULL
              OR (e.published_at, e.id) < (before_published_at, before_entry_id)
          )
        ORDER BY e.published_at DESC, e.id DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'entry_id', entry_id,
            'challenge_id', challenge_id,
            'challenge_slug', challenge_slug,
            'challenge_title', challenge_title,
            'template_id', template_id,
            'template_slug', template_slug,
            'template_title', template_title,
            'title', title,
            'description', description,
            'published_at', published_at,
            'like_count', like_count,
            'comment_count', comment_count,
            'region_tags', region_tags,
            'season_tags', season_tags,
            'habitat_tags', habitat_tags,
            'cover_image_url', COALESCE(item_cover_image_url, template_cover_image_url),
            'item_count', item_count,
            'viewer_has_liked', viewer_has_liked,
            'author_user_id', author_user_id,
            'author_name', author_name,
            'author_username', author_username,
            'author_avatar_url', author_avatar_url
        )
        ORDER BY published_at DESC, entry_id DESC
    ), '[]'::jsonb)
    INTO response
    FROM visible_entries;

    RETURN response;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenges_catalog(
    self_id UUID,
    user_region TEXT DEFAULT NULL,
    max_limit INTEGER DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    normalized_region TEXT := NULLIF(LOWER(BTRIM(COALESCE(user_region, ''))), '');
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 20), 60));
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    WITH challenges AS (
        SELECT
            c.*,
            t.slug AS template_slug,
            t.title AS template_title,
            public.field_trip_challenge_status(c.starts_at, c.ends_at) AS status,
            (c.is_pro_only = FALSE OR c.is_temporarily_free OR user_is_pro) AS viewer_has_access,
            CASE
                WHEN c.is_pro_only AND NOT user_is_pro AND NOT c.is_temporarily_free THEN 'pro'
                WHEN c.is_temporarily_free THEN 'temporarily_free'
                ELSE 'free'
            END AS access_kind,
            CASE
                WHEN normalized_region IS NOT NULL AND normalized_region = ANY(public.field_trip_lower_text_array(c.region_tags)) THEN 0
                WHEN 'global' = ANY(public.field_trip_lower_text_array(c.region_tags))
                  OR COALESCE(ARRAY_LENGTH(c.region_tags, 1), 0) = 0 THEN 1
                ELSE 2
            END AS region_rank
        FROM public.field_trip_challenges c
        JOIN public.field_trip_templates t
            ON t.id = c.template_id
        WHERE c.is_active = TRUE
        ORDER BY
            CASE public.field_trip_challenge_status(c.starts_at, c.ends_at)
                WHEN 'live' THEN 0
                WHEN 'upcoming' THEN 1
                ELSE 2
            END,
            region_rank,
            c.sort_order,
            c.starts_at DESC,
            c.title
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'challenge_id', c.id,
            'template_id', c.template_id,
            'template_slug', c.template_slug,
            'template_title', c.template_title,
            'slug', c.slug,
            'title', c.title,
            'subtitle', c.subtitle,
            'description', c.description,
            'cover_image_url', c.cover_image_url,
            'starts_at', c.starts_at,
            'ends_at', c.ends_at,
            'status', c.status,
            'region_tags', c.region_tags,
            'season_tags', c.season_tags,
            'habitat_tags', c.habitat_tags,
            'suggested_hashtags', c.suggested_hashtags,
            'is_pro_only', c.is_pro_only,
            'is_temporarily_free', c.is_temporarily_free,
            'viewer_has_access', c.viewer_has_access,
            'access_kind', c.access_kind,
            'participant_count', counts.participant_count,
            'completion_count', counts.completion_count,
            'published_entry_count', counts.published_entry_count,
            'viewer_participation', CASE WHEN p.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
                'participation_id', p.id,
                'user_field_trip_id', p.user_field_trip_id,
                'joined_at', p.joined_at,
                'current_level_number', p.current_level_number,
                'completed_at', p.completed_at,
                'badge_awarded_at', p.badge_awarded_at,
                'completed_count', COALESCE(progress_counts.completed_count, 0),
                'target_count', COALESCE(progress_counts.target_count, 0)
            ) END
        )
        ORDER BY
            CASE c.status WHEN 'live' THEN 0 WHEN 'upcoming' THEN 1 ELSE 2 END,
            c.region_rank,
            c.sort_order,
            c.starts_at DESC,
            c.title
    ), '[]'::jsonb)
    INTO response
    FROM challenges c
    LEFT JOIN public.field_trip_challenge_participants p
        ON p.challenge_id = c.id
       AND p.user_id = self_id
       AND p.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(participants.id)::INTEGER AS participant_count,
            COUNT(participants.completed_at)::INTEGER AS completion_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_entries e
                WHERE e.challenge_id = c.id
                  AND e.deleted_at IS NULL
            ) AS published_entry_count
        FROM public.field_trip_challenge_participants participants
        WHERE participants.challenge_id = c.id
          AND participants.hidden_at IS NULL
    ) counts ON TRUE
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = fci.id
        WHERE fl.template_id = c.template_id
          AND fl.level_number = COALESCE(p.current_level_number, 1)
    ) progress_counts ON TRUE;

    RETURN response;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_detail(
    self_id UUID,
    target_challenge_id UUID DEFAULT NULL,
    target_slug TEXT DEFAULT NULL,
    entries_limit INTEGER DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_is_pro BOOLEAN := FALSE;
    resolved_entries_limit INTEGER := GREATEST(0, LEAST(COALESCE(entries_limit, 12), 30));
    challenge_row RECORD;
    detail_payload JSONB := NULL;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT
        c.*,
        t.slug AS template_slug,
        t.title AS template_title,
        t.cover_image_url AS template_cover_image_url,
        public.field_trip_challenge_status(c.starts_at, c.ends_at) AS status,
        (c.is_pro_only = FALSE OR c.is_temporarily_free OR user_is_pro) AS viewer_has_access,
        CASE
            WHEN c.is_pro_only AND NOT user_is_pro AND NOT c.is_temporarily_free THEN 'pro'
            WHEN c.is_temporarily_free THEN 'temporarily_free'
            ELSE 'free'
        END AS access_kind
    INTO challenge_row
    FROM public.field_trip_challenges c
    JOIN public.field_trip_templates t
        ON t.id = c.template_id
    WHERE c.is_active = TRUE
      AND (
          (target_challenge_id IS NOT NULL AND c.id = target_challenge_id)
          OR (target_slug IS NOT NULL AND c.slug = target_slug)
      )
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'challenge_id', challenge_row.id,
        'template_id', challenge_row.template_id,
        'template_slug', challenge_row.template_slug,
        'template_title', challenge_row.template_title,
        'slug', challenge_row.slug,
        'title', challenge_row.title,
        'subtitle', challenge_row.subtitle,
        'description', challenge_row.description,
        'cover_image_url', COALESCE(challenge_row.cover_image_url, challenge_row.template_cover_image_url),
        'starts_at', challenge_row.starts_at,
        'ends_at', challenge_row.ends_at,
        'status', challenge_row.status,
        'region_tags', challenge_row.region_tags,
        'season_tags', challenge_row.season_tags,
        'habitat_tags', challenge_row.habitat_tags,
        'suggested_hashtags', challenge_row.suggested_hashtags,
        'is_pro_only', challenge_row.is_pro_only,
        'is_temporarily_free', challenge_row.is_temporarily_free,
        'viewer_has_access', challenge_row.viewer_has_access,
        'access_kind', challenge_row.access_kind,
        'participant_count', counts.participant_count,
        'completion_count', counts.completion_count,
        'published_entry_count', counts.published_entry_count,
        'viewer_participation', CASE WHEN p.id IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
            'participation_id', p.id,
            'user_field_trip_id', p.user_field_trip_id,
            'joined_at', p.joined_at,
            'current_level_number', p.current_level_number,
            'completed_at', p.completed_at,
            'badge_awarded_at', p.badge_awarded_at,
            'completed_count', COALESCE(progress_counts.completed_count, 0),
            'target_count', COALESCE(progress_counts.target_count, 0)
        ) END,
        'template', public.get_field_trip_template_detail(self_id, challenge_row.template_id, NULL),
        'entries', public.get_field_trip_challenge_publications(
            self_id,
            challenge_row.id,
            resolved_entries_limit,
            NULL,
            NULL
        )
    )
    INTO detail_payload
    FROM (SELECT challenge_row.id AS id) c
    LEFT JOIN public.field_trip_challenge_participants p
        ON p.challenge_id = challenge_row.id
       AND p.user_id = self_id
       AND p.hidden_at IS NULL
    LEFT JOIN LATERAL (
        SELECT
            COUNT(participants.id)::INTEGER AS participant_count,
            COUNT(participants.completed_at)::INTEGER AS completion_count,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_entries e
                WHERE e.challenge_id = challenge_row.id
                  AND e.deleted_at IS NULL
            ) AS published_entry_count
        FROM public.field_trip_challenge_participants participants
        WHERE participants.challenge_id = challenge_row.id
          AND participants.hidden_at IS NULL
    ) counts ON TRUE
    LEFT JOIN LATERAL (
        SELECT
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM public.field_trip_levels fl
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = fci.id
        WHERE fl.template_id = challenge_row.template_id
          AND fl.level_number = COALESCE(p.current_level_number, 1)
    ) progress_counts ON TRUE;

    RETURN detail_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_field_trip_challenge(
    self_id UUID,
    target_challenge_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    challenge_row RECORD;
    user_is_pro BOOLEAN := FALSE;
    linked_user_field_trip_id UUID;
BEGIN
    SELECT COALESCE(u.subscription_tier = 'pro'::subscription_tier_enum, FALSE)
    INTO user_is_pro
    FROM public.users u
    WHERE u.id = self_id;

    SELECT *
    INTO challenge_row
    FROM public.field_trip_challenges c
    WHERE c.id = target_challenge_id
      AND c.is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip challenge not found' USING ERRCODE = 'P0002';
    END IF;

    IF NOW() < challenge_row.starts_at OR NOW() > challenge_row.ends_at THEN
        RAISE EXCEPTION 'Field Trip challenge is not open for joining' USING ERRCODE = 'P0001';
    END IF;

    IF challenge_row.is_pro_only AND NOT user_is_pro AND NOT challenge_row.is_temporarily_free THEN
        RAISE EXCEPTION 'Field Trip challenge requires Pro access' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.user_field_trips(user_id, template_id, started_at, current_level_number, is_profile_visible, hidden_at)
    VALUES (self_id, challenge_row.template_id, NOW(), 1, TRUE, NULL)
    ON CONFLICT(user_id, template_id) DO UPDATE
    SET hidden_at = NULL,
        is_profile_visible = TRUE,
        updated_at = NOW()
    RETURNING id INTO linked_user_field_trip_id;

    INSERT INTO public.field_trip_challenge_participants(
        challenge_id,
        user_id,
        user_field_trip_id,
        joined_at,
        current_level_number,
        hidden_at
    )
    VALUES (
        target_challenge_id,
        self_id,
        linked_user_field_trip_id,
        NOW(),
        1,
        NULL
    )
    ON CONFLICT(user_id, challenge_id) DO UPDATE
    SET hidden_at = NULL,
        user_field_trip_id = EXCLUDED.user_field_trip_id,
        updated_at = NOW();

    RETURN public.get_field_trip_challenge_detail(self_id, target_challenge_id, NULL, 12);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_field_trip_challenge_scan_progress(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    scan_row RECORD;
    inserted_count INTEGER := 0;
    response JSONB := '[]'::jsonb;
BEGIN
    SELECT
        s.id,
        s.user_id,
        s.timestamp,
        s.ecology_type::TEXT AS ecology_type,
        s.is_tombstoned,
        s.is_biological_subject,
        COALESCE(s.confirmed_species_id, s.species_id) AS resolved_species_id,
        sd.scientific_name,
        sd.common_names,
        sd.kingdom,
        sd.phylum,
        sd."class",
        sd."order",
        sd.family,
        sd.genus,
        sd.habitat_description,
        sd.group_tags
    INTO scan_row
    FROM public.scans s
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE s.id = target_scan_id
      AND s.user_id = self_id;

    IF NOT FOUND OR scan_row.is_tombstoned OR scan_row.is_biological_subject IS FALSE OR scan_row.resolved_species_id IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    DROP TABLE IF EXISTS pg_temp.field_trip_challenge_scan_matches;
    CREATE TEMP TABLE field_trip_challenge_scan_matches ON COMMIT DROP AS
    SELECT
        p.id AS participation_id,
        p.challenge_id,
        c.template_id,
        p.current_level_number,
        fl.id AS level_id,
        fci.id AS item_id,
        fci.prompt,
        scan_row.resolved_species_id::UUID AS species_id,
        public.field_trip_species_common_name(scan_row.common_names, scan_row.scientific_name, fci.prompt) AS common_name,
        scan_row.scientific_name::TEXT AS scientific_name
    FROM public.field_trip_challenge_participants p
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    JOIN public.field_trip_levels fl
        ON fl.template_id = c.template_id
       AND fl.level_number = p.current_level_number
    JOIN public.field_trip_checklist_items fci
        ON fci.level_id = fl.id
    WHERE p.user_id = self_id
      AND p.hidden_at IS NULL
      AND p.completed_at IS NULL
      AND c.is_active = TRUE
      AND scan_row.timestamp >= p.joined_at
      AND scan_row.timestamp <= c.ends_at
      AND public.field_trip_item_matches_scan(
          fci.match_type,
          fci.species_id,
          fci.scientific_name,
          fci.taxonomy_kingdom,
          fci.taxonomy_phylum,
          fci.taxonomy_class,
          fci.taxonomy_order,
          fci.taxonomy_family,
          fci.taxonomy_genus,
          fci.ecology_type,
          fci.habitat_tag,
          fci.semantic_tag,
          scan_row.resolved_species_id,
          scan_row.scientific_name,
          scan_row.common_names,
          scan_row.kingdom,
          scan_row.phylum,
          scan_row."class",
          scan_row."order",
          scan_row.family,
          scan_row.genus,
          scan_row.ecology_type,
          scan_row.habitat_description,
          scan_row.group_tags
      );

    WITH inserted AS (
        INSERT INTO public.field_trip_challenge_item_completions(
            participation_id,
            item_id,
            scan_id,
            species_id,
            common_name,
            scientific_name,
            completed_at
        )
        SELECT
            m.participation_id,
            m.item_id,
            target_scan_id,
            m.species_id,
            m.common_name,
            m.scientific_name,
            scan_row.timestamp
        FROM pg_temp.field_trip_challenge_scan_matches m
        ON CONFLICT(participation_id, item_id) DO NOTHING
        RETURNING participation_id, item_id
    )
    SELECT COUNT(*)::INTEGER
    INTO inserted_count
    FROM inserted;

    IF inserted_count = 0 THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH touched_participations AS (
        SELECT DISTINCT p.id, p.challenge_id, c.template_id, p.current_level_number
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        JOIN public.field_trip_challenges c
            ON c.id = p.challenge_id
        WHERE p.user_id = self_id
    ),
    level_counts AS (
        SELECT
            tp.id AS participation_id,
            tp.challenge_id,
            tp.template_id,
            tp.current_level_number,
            fl.id AS current_level_id,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM touched_participations tp
        JOIN public.field_trip_levels fl
            ON fl.template_id = tp.template_id
           AND fl.level_number = tp.current_level_number
        JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = tp.id
           AND comp.item_id = fci.id
        GROUP BY tp.id, tp.challenge_id, tp.template_id, tp.current_level_number, fl.id
    ),
    next_levels AS (
        SELECT
            lc.*,
            (
                SELECT MIN(next_fl.level_number)
                FROM public.field_trip_levels next_fl
                WHERE next_fl.template_id = lc.template_id
                  AND next_fl.level_number > lc.current_level_number
            ) AS next_level_number
        FROM level_counts lc
        WHERE lc.completed_count >= lc.target_count
    )
    UPDATE public.field_trip_challenge_participants p
    SET current_level_number = COALESCE(nl.next_level_number, p.current_level_number),
        completed_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(p.completed_at, NOW()) ELSE p.completed_at END,
        badge_awarded_at = CASE WHEN nl.next_level_number IS NULL THEN COALESCE(p.badge_awarded_at, NOW()) ELSE p.badge_awarded_at END
    FROM next_levels nl
    WHERE p.id = nl.participation_id;

    INSERT INTO public.field_trip_challenge_badges(
        participation_id,
        challenge_id,
        user_id,
        badge_key,
        title,
        awarded_at,
        is_profile_visible
    )
    SELECT
        p.id,
        p.challenge_id,
        p.user_id,
        c.slug || '_completed',
        c.title || ' Completed',
        COALESCE(p.badge_awarded_at, NOW()),
        TRUE
    FROM public.field_trip_challenge_participants p
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    JOIN pg_temp.field_trip_challenge_scan_matches m
        ON m.participation_id = p.id
    WHERE p.user_id = self_id
      AND p.completed_at IS NOT NULL
      AND p.badge_awarded_at IS NOT NULL
    ON CONFLICT(user_id, challenge_id) DO NOTHING;

    WITH touched_participations AS (
        SELECT DISTINCT p.id
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        WHERE p.user_id = self_id
    ),
    participation_counts AS (
        SELECT
            p.id AS participation_id,
            p.challenge_id,
            c.slug,
            c.title,
            c.suggested_hashtags,
            p.current_level_number,
            p.completed_at,
            p.badge_awarded_at,
            fl.title AS current_level_title,
            COUNT(fci.id)::INTEGER AS target_count,
            COUNT(comp.id)::INTEGER AS completed_count
        FROM touched_participations tp
        JOIN public.field_trip_challenge_participants p
            ON p.id = tp.id
        JOIN public.field_trip_challenges c
            ON c.id = p.challenge_id
        LEFT JOIN public.field_trip_levels fl
            ON fl.template_id = c.template_id
           AND fl.level_number = p.current_level_number
        LEFT JOIN public.field_trip_checklist_items fci
            ON fci.level_id = fl.id
        LEFT JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = fci.id
        GROUP BY p.id, p.challenge_id, c.slug, c.title, c.suggested_hashtags, p.current_level_number, p.completed_at, p.badge_awarded_at, fl.title
    ),
    newly_completed AS (
        SELECT
            p.id AS participation_id,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'item_id', fci.id,
                    'prompt', fci.prompt,
                    'common_name', comp.common_name,
                    'scientific_name', comp.scientific_name,
                    'completed_at', comp.completed_at
                )
                ORDER BY fci.sort_order
            ) AS items
        FROM public.field_trip_challenge_participants p
        JOIN pg_temp.field_trip_challenge_scan_matches m
            ON m.participation_id = p.id
        JOIN public.field_trip_challenge_item_completions comp
            ON comp.participation_id = p.id
           AND comp.item_id = m.item_id
           AND comp.scan_id = target_scan_id
        JOIN public.field_trip_checklist_items fci
            ON fci.id = comp.item_id
        WHERE p.user_id = self_id
        GROUP BY p.id
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'participation_id', pc.participation_id,
            'challenge_id', pc.challenge_id,
            'slug', pc.slug,
            'title', pc.title,
            'current_level_number', pc.current_level_number,
            'current_level_title', pc.current_level_title,
            'completed_count', pc.completed_count,
            'target_count', pc.target_count,
            'is_complete', pc.completed_at IS NOT NULL,
            'badge_awarded_at', pc.badge_awarded_at,
            'suggested_hashtags', pc.suggested_hashtags,
            'newly_completed_items', COALESCE(nc.items, '[]'::jsonb)
        )
        ORDER BY pc.title
    ), '[]'::jsonb)
    INTO response
    FROM participation_counts pc
    LEFT JOIN newly_completed nc
        ON nc.participation_id = pc.participation_id;

    RETURN response;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_hashtags_for_scan(self_id UUID, target_scan_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(JSONB_AGG(DISTINCT tag ORDER BY tag), '[]'::jsonb)
    FROM public.field_trip_challenge_item_completions comp
    JOIN public.field_trip_challenge_participants p
        ON p.id = comp.participation_id
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    CROSS JOIN LATERAL UNNEST(public.field_trip_lower_text_array(c.suggested_hashtags)) AS tag
    WHERE comp.scan_id = target_scan_id
      AND p.user_id = self_id
      AND c.is_active = TRUE
      AND comp.completed_at >= p.joined_at
      AND comp.completed_at <= c.ends_at;
$$;

CREATE OR REPLACE FUNCTION public.publish_field_trip_challenge_entry(
    self_id UUID,
    target_participation_id UUID,
    entry_title TEXT DEFAULT NULL,
    entry_description TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    participation_row RECORD;
    new_entry_id UUID;
    resolved_title TEXT;
BEGIN
    SELECT
        p.*,
        c.title AS challenge_title,
        c.template_id,
        t.title AS template_title
    INTO participation_row
    FROM public.field_trip_challenge_participants p
    JOIN public.field_trip_challenges c
        ON c.id = p.challenge_id
    JOIN public.field_trip_templates t
        ON t.id = c.template_id
    WHERE p.id = target_participation_id
      AND p.user_id = self_id
      AND p.hidden_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Field Trip challenge participation not found' USING ERRCODE = 'P0002';
    END IF;

    IF participation_row.completed_at IS NULL THEN
        RAISE EXCEPTION 'Field Trip challenge must be complete before publishing' USING ERRCODE = 'P0001';
    END IF;

    resolved_title := COALESCE(NULLIF(BTRIM(entry_title), ''), participation_row.challenge_title);

    INSERT INTO public.field_trip_challenge_entries(
        participation_id,
        challenge_id,
        user_id,
        template_id,
        title,
        description,
        published_at
    )
    VALUES (
        target_participation_id,
        participation_row.challenge_id,
        self_id,
        participation_row.template_id,
        resolved_title,
        NULLIF(BTRIM(entry_description), ''),
        NOW()
    )
    ON CONFLICT(participation_id) DO UPDATE
    SET title = EXCLUDED.title,
        description = EXCLUDED.description,
        deleted_at = NULL,
        updated_at = NOW()
    RETURNING id INTO new_entry_id;

    INSERT INTO public.field_trip_challenge_entry_items(
        entry_id,
        item_id,
        scan_id,
        species_id,
        common_name,
        scientific_name,
        hero_image_url,
        reference_image_url,
        taxonomy,
        sort_order
    )
    SELECT
        new_entry_id,
        fci.id,
        comp.scan_id,
        comp.species_id,
        comp.common_name,
        comp.scientific_name,
        s.image_storage_urls[1],
        sd.reference_image_url,
        JSONB_BUILD_OBJECT(
            'kingdom', sd.kingdom,
            'phylum', sd.phylum,
            'class', sd."class",
            'order', sd."order",
            'family', sd.family,
            'genus', sd.genus
        ),
        fci.sort_order
    FROM public.field_trip_challenge_item_completions comp
    JOIN public.field_trip_checklist_items fci
        ON fci.id = comp.item_id
    JOIN public.scans s
        ON s.id = comp.scan_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = comp.species_id
    WHERE comp.participation_id = target_participation_id
    ON CONFLICT(entry_id, item_id) DO UPDATE
    SET scan_id = EXCLUDED.scan_id,
        species_id = EXCLUDED.species_id,
        common_name = EXCLUDED.common_name,
        scientific_name = EXCLUDED.scientific_name,
        hero_image_url = EXCLUDED.hero_image_url,
        reference_image_url = EXCLUDED.reference_image_url,
        taxonomy = EXCLUDED.taxonomy,
        sort_order = EXCLUDED.sort_order;

    RETURN JSONB_BUILD_OBJECT('entry_id', new_entry_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_entry_detail(self_id UUID, target_entry_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    detail_payload JSONB := NULL;
BEGIN
    IF NOT public.can_view_field_trip_challenge_entry(self_id, target_entry_id) THEN
        RETURN NULL;
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'entry_id', e.id,
        'participation_id', e.participation_id,
        'challenge_id', e.challenge_id,
        'challenge_slug', c.slug,
        'challenge_title', c.title,
        'template_id', e.template_id,
        'template_slug', t.slug,
        'template_title', t.title,
        'title', e.title,
        'description', e.description,
        'published_at', e.published_at,
        'author_user_id', e.user_id,
        'author_name', u.public_author_name,
        'author_username', u.public_username,
        'author_avatar_url', u.public_avatar_url,
        'like_count', e.like_count,
        'comment_count', e.comment_count,
        'viewer_has_liked', EXISTS (
            SELECT 1
            FROM public.field_trip_challenge_entry_likes l
            WHERE l.entry_id = e.id
              AND l.user_id = self_id
        ),
        'is_owned_by_viewer', e.user_id = self_id,
        'items', COALESCE(items.items, '[]'::jsonb)
    )
    INTO detail_payload
    FROM public.field_trip_challenge_entries e
    JOIN public.field_trip_challenges c
        ON c.id = e.challenge_id
    JOIN public.field_trip_templates t
        ON t.id = e.template_id
    JOIN public.users u
        ON u.id = e.user_id
    LEFT JOIN LATERAL (
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'entry_item_id', cei.id,
                'item_id', cei.item_id,
                'prompt', fci.prompt,
                'common_name', cei.common_name,
                'scientific_name', cei.scientific_name,
                'hero_image_url', cei.hero_image_url,
                'reference_image_url', cei.reference_image_url,
                'taxonomy', cei.taxonomy
            )
            ORDER BY cei.sort_order
        ) AS items
        FROM public.field_trip_challenge_entry_items cei
        JOIN public.field_trip_checklist_items fci
            ON fci.id = cei.item_id
        WHERE cei.entry_id = e.id
    ) items ON TRUE
    WHERE e.id = target_entry_id
      AND e.deleted_at IS NULL;

    RETURN detail_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_entry_comments(
    self_id UUID,
    target_entry_id UUID,
    max_limit INTEGER DEFAULT 50,
    after_created_at TIMESTAMPTZ DEFAULT NULL,
    after_comment_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(1, LEAST(COALESCE(max_limit, 50), 100));
    comments_payload JSONB := '[]'::jsonb;
BEGIN
    IF NOT public.can_view_field_trip_challenge_entry(self_id, target_entry_id) THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH visible_comments AS (
        SELECT
            c.id AS comment_id,
            c.entry_id,
            c.parent_comment_id,
            c.user_id AS author_user_id,
            u.public_author_name AS author_name,
            u.public_username AS author_username,
            u.public_avatar_url AS author_avatar_url,
            c.body,
            c.created_at,
            EXISTS (SELECT 1 FROM public.field_trip_challenge_entries e WHERE e.id = c.entry_id AND e.user_id = self_id) AS viewer_owns_entry,
            (
                SELECT COUNT(*)::INTEGER
                FROM public.field_trip_challenge_entry_comments replies
                WHERE replies.parent_comment_id = c.id
                  AND replies.deleted_at IS NULL
                  AND replies.moderated_at IS NULL
            ) AS reply_count
        FROM public.field_trip_challenge_entry_comments c
        JOIN public.users u
            ON u.id = c.user_id
        WHERE c.entry_id = target_entry_id
          AND c.deleted_at IS NULL
          AND c.moderated_at IS NULL
          AND u.is_shadowbanned = FALSE
          AND (
              c.user_id = self_id
              OR NOT EXISTS (
                  SELECT 1
                  FROM public.user_blocks ub
                  WHERE (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
                     OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
              )
          )
          AND (
              after_created_at IS NULL
              OR (c.created_at, c.id) > (after_created_at, after_comment_id)
          )
        ORDER BY c.created_at ASC, c.id ASC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'comment_id', comment_id,
            'post_id', entry_id,
            'parent_comment_id', parent_comment_id,
            'author_user_id', author_user_id,
            'author_name', author_name,
            'author_username', author_username,
            'author_avatar_url', author_avatar_url,
            'body', body,
            'created_at', created_at,
            'viewer_can_delete', author_user_id = self_id,
            'viewer_can_moderate', viewer_owns_entry AND author_user_id <> self_id,
            'viewer_can_report', author_user_id <> self_id,
            'reply_count', reply_count,
            'reactions', '[]'::jsonb,
            'mentions', '[]'::jsonb
        )
        ORDER BY created_at ASC, comment_id ASC
    ), '[]'::jsonb)
    INTO comments_payload
    FROM visible_comments;

    RETURN comments_payload;
END;
$$;

CREATE OR REPLACE FUNCTION public.user_has_visible_field_trip_profile(self_id UUID, target_author_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = target_author_user_id
          AND u.is_shadowbanned = FALSE
          AND NOT EXISTS (
              SELECT 1
              FROM public.user_blocks ub
              WHERE (ub.blocker_id = self_id AND ub.blocked_id = target_author_user_id)
                 OR (ub.blocker_id = target_author_user_id AND ub.blocked_id = self_id)
          )
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.user_field_trips uft
                  WHERE uft.user_id = target_author_user_id
                    AND uft.is_profile_visible = TRUE
                    AND uft.hidden_at IS NULL
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.field_trip_publications ftp
                  WHERE ftp.user_id = target_author_user_id
                    AND ftp.deleted_at IS NULL
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.field_trip_challenge_badges b
                  WHERE b.user_id = target_author_user_id
                    AND b.is_profile_visible = TRUE
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.field_trip_challenge_entries e
                  WHERE e.user_id = target_author_user_id
                    AND e.deleted_at IS NULL
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_field_trip_challenge_badges(
    self_id UUID,
    target_author_user_id UUID,
    max_limit INTEGER DEFAULT 6
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_limit INTEGER := GREATEST(0, LEAST(COALESCE(max_limit, 6), 12));
    badge_payload JSONB := '[]'::jsonb;
BEGIN
    IF NOT public.user_has_visible_field_trip_profile(self_id, target_author_user_id) THEN
        RETURN '[]'::jsonb;
    END IF;

    WITH badges AS (
        SELECT
            b.id AS badge_id,
            b.challenge_id,
            b.badge_key,
            b.title,
            b.awarded_at,
            c.slug AS challenge_slug,
            c.title AS challenge_title,
            c.cover_image_url,
            c.region_tags,
            c.season_tags,
            c.habitat_tags
        FROM public.field_trip_challenge_badges b
        JOIN public.field_trip_challenges c
            ON c.id = b.challenge_id
        WHERE b.user_id = target_author_user_id
          AND b.is_profile_visible = TRUE
        ORDER BY b.awarded_at DESC
        LIMIT resolved_limit
    )
    SELECT COALESCE(JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'badge_id', badge_id,
            'challenge_id', challenge_id,
            'badge_key', badge_key,
            'title', title,
            'awarded_at', awarded_at,
            'challenge_slug', challenge_slug,
            'challenge_title', challenge_title,
            'cover_image_url', cover_image_url,
            'region_tags', region_tags,
            'season_tags', season_tags,
            'habitat_tags', habitat_tags
        )
        ORDER BY awarded_at DESC
    ), '[]'::jsonb)
    INTO badge_payload
    FROM badges;

    RETURN badge_payload;
END;
$$;

-- Seed a small curated catalog that exercises live and upcoming seasonal states.
INSERT INTO public.field_trip_challenges(
    template_id,
    slug,
    title,
    subtitle,
    description,
    cover_image_url,
    starts_at,
    ends_at,
    region_tags,
    season_tags,
    habitat_tags,
    suggested_hashtags,
    is_pro_only,
    is_temporarily_free,
    is_active,
    sort_order
)
SELECT
    t.id,
    seed.slug,
    seed.title,
    seed.subtitle,
    seed.description,
    t.cover_image_url,
    seed.starts_at,
    seed.ends_at,
    seed.region_tags,
    seed.season_tags,
    seed.habitat_tags,
    seed.suggested_hashtags,
    seed.is_pro_only,
    seed.is_temporarily_free,
    TRUE,
    seed.sort_order
FROM (
    VALUES
        (
            'summer_pollinator_watch',
            'Summer Pollinator Watch',
            'Find pollinators while flowers are active.',
            'A non-competitive seasonal challenge for bees, butterflies, and blooming habitats.',
            'park_pollinators',
            '2026-06-01T00:00:00Z'::timestamptz,
            '2026-08-31T23:59:59Z'::timestamptz,
            ARRAY['global']::TEXT[],
            ARRAY['summer']::TEXT[],
            ARRAY['park', 'garden', 'pollinator']::TEXT[],
            ARRAY['summerpollinators', 'pollinators']::TEXT[],
            FALSE,
            TRUE,
            10
        ),
        (
            'neighborhood_night_watch',
            'Neighborhood Night Watch',
            'Notice evening wildlife close to home.',
            'A fall challenge for dusk and night observations around familiar places.',
            'backyard_safari',
            '2026-09-01T00:00:00Z'::timestamptz,
            '2026-10-31T23:59:59Z'::timestamptz,
            ARRAY['global']::TEXT[],
            ARRAY['fall']::TEXT[],
            ARRAY['neighborhood', 'yard']::TEXT[],
            ARRAY['nightwatch', 'localwildlife']::TEXT[],
            FALSE,
            TRUE,
            20
        )
) AS seed(
    slug,
    title,
    subtitle,
    description,
    template_slug,
    starts_at,
    ends_at,
    region_tags,
    season_tags,
    habitat_tags,
    suggested_hashtags,
    is_pro_only,
    is_temporarily_free,
    sort_order
)
JOIN public.field_trip_templates t
    ON t.slug = seed.template_slug
ON CONFLICT(slug) DO UPDATE
SET title = EXCLUDED.title,
    subtitle = EXCLUDED.subtitle,
    description = EXCLUDED.description,
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    region_tags = EXCLUDED.region_tags,
    season_tags = EXCLUDED.season_tags,
    habitat_tags = EXCLUDED.habitat_tags,
    suggested_hashtags = EXCLUDED.suggested_hashtags,
    is_pro_only = EXCLUDED.is_pro_only,
    is_temporarily_free = EXCLUDED.is_temporarily_free,
    is_active = TRUE,
    sort_order = EXCLUDED.sort_order;

ALTER TABLE public.field_trip_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_item_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_entry_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_entry_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_trip_challenge_entry_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read active field trip challenges" ON public.field_trip_challenges;
CREATE POLICY "Users can read active field trip challenges"
    ON public.field_trip_challenges FOR SELECT
    TO authenticated
    USING (is_active = TRUE);

DROP POLICY IF EXISTS "Users can read own field trip challenge participation" ON public.field_trip_challenge_participants;
CREATE POLICY "Users can read own field trip challenge participation"
    ON public.field_trip_challenge_participants FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read own field trip challenge completions" ON public.field_trip_challenge_item_completions;
CREATE POLICY "Users can read own field trip challenge completions"
    ON public.field_trip_challenge_item_completions FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1
        FROM public.field_trip_challenge_participants p
        WHERE p.id = participation_id
          AND p.user_id = (SELECT auth.uid())
    ));

DROP POLICY IF EXISTS "Users can read visible field trip challenge badges" ON public.field_trip_challenge_badges;
CREATE POLICY "Users can read visible field trip challenge badges"
    ON public.field_trip_challenge_badges FOR SELECT
    TO authenticated
    USING (is_profile_visible = TRUE OR (SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read visible field trip challenge entries" ON public.field_trip_challenge_entries;
CREATE POLICY "Users can read visible field trip challenge entries"
    ON public.field_trip_challenge_entries FOR SELECT
    TO authenticated
    USING (public.can_view_field_trip_challenge_entry((SELECT auth.uid()), id));

DROP POLICY IF EXISTS "Users can read visible field trip challenge entry items" ON public.field_trip_challenge_entry_items;
CREATE POLICY "Users can read visible field trip challenge entry items"
    ON public.field_trip_challenge_entry_items FOR SELECT
    TO authenticated
    USING (public.can_view_field_trip_challenge_entry((SELECT auth.uid()), entry_id));

DROP POLICY IF EXISTS "Users can read field trip challenge entry likes" ON public.field_trip_challenge_entry_likes;
CREATE POLICY "Users can read field trip challenge entry likes"
    ON public.field_trip_challenge_entry_likes FOR SELECT
    TO authenticated
    USING (public.can_view_field_trip_challenge_entry((SELECT auth.uid()), entry_id));

DROP POLICY IF EXISTS "Users can insert own field trip challenge entry likes" ON public.field_trip_challenge_entry_likes;
CREATE POLICY "Users can insert own field trip challenge entry likes"
    ON public.field_trip_challenge_entry_likes FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id AND public.can_view_field_trip_challenge_entry((SELECT auth.uid()), entry_id));

DROP POLICY IF EXISTS "Users can delete own field trip challenge entry likes" ON public.field_trip_challenge_entry_likes;
CREATE POLICY "Users can delete own field trip challenge entry likes"
    ON public.field_trip_challenge_entry_likes FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read visible field trip challenge comments" ON public.field_trip_challenge_entry_comments;
CREATE POLICY "Users can read visible field trip challenge comments"
    ON public.field_trip_challenge_entry_comments FOR SELECT
    TO authenticated
    USING (public.can_view_field_trip_challenge_entry((SELECT auth.uid()), entry_id));

DROP POLICY IF EXISTS "Users can insert field trip challenge comments" ON public.field_trip_challenge_entry_comments;
CREATE POLICY "Users can insert field trip challenge comments"
    ON public.field_trip_challenge_entry_comments FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id AND public.can_view_field_trip_challenge_entry((SELECT auth.uid()), entry_id));

GRANT SELECT ON public.field_trip_challenges TO authenticated;
GRANT SELECT ON public.field_trip_challenge_participants TO authenticated;
GRANT SELECT ON public.field_trip_challenge_item_completions TO authenticated;
GRANT SELECT ON public.field_trip_challenge_badges TO authenticated;
GRANT SELECT ON public.field_trip_challenge_entries TO authenticated;
GRANT SELECT ON public.field_trip_challenge_entry_items TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.field_trip_challenge_entry_likes TO authenticated;
GRANT SELECT, INSERT ON public.field_trip_challenge_entry_comments TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_field_trip_challenge_entry(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenges_catalog(UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_detail(UUID, UUID, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_field_trip_challenge(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_field_trip_challenge_scan_progress(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_hashtags_for_scan(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_publications(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_field_trip_challenge_entry(UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_entry_detail(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_entry_comments(UUID, UUID, INTEGER, TIMESTAMPTZ, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_field_trip_challenge_badges(UUID, UUID, INTEGER) TO authenticated;

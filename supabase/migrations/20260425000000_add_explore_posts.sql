-- Explore V1: manual-share image feed backed by existing scan media.
-- Shared posts are ephemeral — if the underlying scan media expires or is purged,
-- the post simply drops out of the Explore feed.

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS public_author_name TEXT;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS public_identity_source TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_public_identity_source_check'
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_public_identity_source_check
            CHECK (public_identity_source IN ('alias', 'derived_name', 'display_name'));
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.build_default_public_alias(target_user_id UUID)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT 'Explorer ' || UPPER(SUBSTRING(REPLACE(target_user_id::TEXT, '-', '') FROM 1 FOR 6));
$$;

CREATE OR REPLACE FUNCTION public.derive_public_author_identity(
    raw_meta JSONB,
    target_user_id UUID
)
RETURNS TABLE(author_name TEXT, identity_source TEXT)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    raw_name TEXT := BTRIM(COALESCE(raw_meta->>'full_name', raw_meta->>'name', ''));
    normalized_name TEXT;
    name_parts TEXT[];
    first_name TEXT;
    last_name_initial TEXT;
BEGIN
    IF raw_name <> '' AND POSITION('@' IN raw_name) = 0 THEN
        normalized_name := REGEXP_REPLACE(raw_name, '\s+', ' ', 'g');
        name_parts := REGEXP_SPLIT_TO_ARRAY(normalized_name, ' ');
        first_name := NULLIF(INITCAP(COALESCE(name_parts[1], '')), '');

        IF first_name IS NOT NULL THEN
            IF COALESCE(ARRAY_LENGTH(name_parts, 1), 0) >= 2 THEN
                last_name_initial := UPPER(LEFT(COALESCE(name_parts[ARRAY_LENGTH(name_parts, 1)], ''), 1));
                IF last_name_initial <> '' THEN
                    RETURN QUERY SELECT first_name || ' ' || last_name_initial || '.', 'derived_name';
                    RETURN;
                END IF;
            END IF;

            RETURN QUERY SELECT first_name, 'derived_name';
            RETURN;
        END IF;
    END IF;

    RETURN QUERY
    SELECT public.build_default_public_alias(target_user_id), 'alias';
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_public_author_identity(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    auth_meta JSONB;
    existing_name TEXT;
    existing_source TEXT;
    resolved_name TEXT;
    resolved_source TEXT;
BEGIN
    SELECT public_author_name, public_identity_source
    INTO existing_name, existing_source
    FROM public.users
    WHERE id = target_user_id;

    IF existing_source = 'display_name' AND existing_name IS NOT NULL AND BTRIM(existing_name) <> '' THEN
        RETURN;
    END IF;

    SELECT raw_user_meta_data
    INTO auth_meta
    FROM auth.users
    WHERE id = target_user_id;

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(auth_meta, target_user_id);

    UPDATE public.users
    SET public_author_name = resolved_name,
        public_identity_source = resolved_source
    WHERE id = target_user_id;
END;
$$;

-- Backfill existing public users from auth metadata where possible.
UPDATE public.users AS u
SET public_author_name = derived.author_name,
    public_identity_source = derived.identity_source
FROM auth.users AS au
CROSS JOIN LATERAL public.derive_public_author_identity(au.raw_user_meta_data, au.id) AS derived
WHERE u.id = au.id
  AND (u.public_author_name IS NULL OR u.public_identity_source IS NULL);

-- Safety fallback for any rows missing auth metadata locally.
UPDATE public.users
SET public_author_name = public.build_default_public_alias(id),
    public_identity_source = 'alias'
WHERE public_author_name IS NULL OR public_identity_source IS NULL;

ALTER TABLE public.users
    ALTER COLUMN public_author_name SET NOT NULL;

ALTER TABLE public.users
    ALTER COLUMN public_identity_source SET NOT NULL;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    resolved_name TEXT;
    resolved_source TEXT;
BEGIN
    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(new.raw_user_meta_data, new.id);

    INSERT INTO public.users (id, email, public_author_name, public_identity_source)
    VALUES (new.id, new.email, resolved_name, resolved_source)
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

CREATE TABLE IF NOT EXISTS public.explore_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL UNIQUE REFERENCES public.scans(id) ON DELETE CASCADE,
    shared_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unshared_at TIMESTAMPTZ,
    like_count INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0)
);

CREATE TABLE IF NOT EXISTS public.explore_post_likes (
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.explore_post_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT explore_post_comments_body_not_blank CHECK (CHAR_LENGTH(BTRIM(body)) > 0),
    CONSTRAINT explore_post_comments_body_length CHECK (CHAR_LENGTH(body) <= 500)
);

ALTER TABLE public.explore_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_post_comments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_posts' AND policyname = 'Users can read their own explore posts'
    ) THEN
        CREATE POLICY "Users can read their own explore posts"
            ON public.explore_posts
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_posts' AND policyname = 'Users can insert their own explore posts'
    ) THEN
        CREATE POLICY "Users can insert their own explore posts"
            ON public.explore_posts
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_posts' AND policyname = 'Users can update their own explore posts'
    ) THEN
        CREATE POLICY "Users can update their own explore posts"
            ON public.explore_posts
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_likes' AND policyname = 'Users can read their own explore likes'
    ) THEN
        CREATE POLICY "Users can read their own explore likes"
            ON public.explore_post_likes
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_likes' AND policyname = 'Users can insert their own explore likes'
    ) THEN
        CREATE POLICY "Users can insert their own explore likes"
            ON public.explore_post_likes
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_likes' AND policyname = 'Users can delete their own explore likes'
    ) THEN
        CREATE POLICY "Users can delete their own explore likes"
            ON public.explore_post_likes
            FOR DELETE
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_comments' AND policyname = 'Users can read their own explore comments'
    ) THEN
        CREATE POLICY "Users can read their own explore comments"
            ON public.explore_post_comments
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_comments' AND policyname = 'Users can insert their own explore comments'
    ) THEN
        CREATE POLICY "Users can insert their own explore comments"
            ON public.explore_post_comments
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'explore_post_comments' AND policyname = 'Users can update their own explore comments'
    ) THEN
        CREATE POLICY "Users can update their own explore comments"
            ON public.explore_post_comments
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_explore_posts_active_shared_at
    ON public.explore_posts(shared_at DESC)
    WHERE unshared_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_explore_posts_user_id_shared_at
    ON public.explore_posts(user_id, shared_at DESC);

CREATE INDEX IF NOT EXISTS idx_explore_post_comments_post_created_at
    ON public.explore_post_comments(post_id, created_at)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.trg_explore_post_like_count_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.explore_posts
    SET like_count = like_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_like_count_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.explore_posts
    SET like_count = GREATEST(like_count - 1, 0)
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_post_like_count_after_insert ON public.explore_post_likes;
CREATE TRIGGER trg_explore_post_like_count_after_insert
AFTER INSERT ON public.explore_post_likes
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_like_count_after_insert();

DROP TRIGGER IF EXISTS trg_explore_post_like_count_after_delete ON public.explore_post_likes;
CREATE TRIGGER trg_explore_post_like_count_after_delete
AFTER DELETE ON public.explore_post_likes
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_like_count_after_delete();

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.deleted_at IS NULL THEN
        UPDATE public.explore_posts
        SET comment_count = comment_count + 1
        WHERE id = NEW.post_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        UPDATE public.explore_posts
        SET comment_count = GREATEST(comment_count - 1, 0)
        WHERE id = NEW.post_id;
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
        UPDATE public.explore_posts
        SET comment_count = comment_count + 1
        WHERE id = NEW.post_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_explore_post_comment_count_after_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.deleted_at IS NULL THEN
        UPDATE public.explore_posts
        SET comment_count = GREATEST(comment_count - 1, 0)
        WHERE id = OLD.post_id;
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_insert ON public.explore_post_comments;
CREATE TRIGGER trg_explore_post_comment_count_after_insert
AFTER INSERT ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_after_insert();

DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_update ON public.explore_post_comments;
CREATE TRIGGER trg_explore_post_comment_count_after_update
AFTER UPDATE ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_after_update();

DROP TRIGGER IF EXISTS trg_explore_post_comment_count_after_delete ON public.explore_post_comments;
CREATE TRIGGER trg_explore_post_comment_count_after_delete
AFTER DELETE ON public.explore_post_comments
FOR EACH ROW
EXECUTE FUNCTION public.trg_explore_post_comment_count_after_delete();

CREATE OR REPLACE FUNCTION public.sanitize_explore_location(raw_location TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    cleaned TEXT := BTRIM(COALESCE(raw_location, ''));
    parts TEXT[];
BEGIN
    IF cleaned = '' THEN
        RETURN NULL;
    END IF;

    parts := REGEXP_SPLIT_TO_ARRAY(cleaned, '\s*,\s*');

    IF COALESCE(ARRAY_LENGTH(parts, 1), 0) >= 2 THEN
        RETURN CONCAT_WS(', ', NULLIF(parts[1], ''), NULLIF(parts[2], ''));
    END IF;

    RETURN cleaned;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_explore_feed(
    self_id UUID,
    max_limit INTEGER DEFAULT 20,
    feed_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    species_common_name TEXT,
    species_scientific_name TEXT,
    public_location_label TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        ep.id AS post_id,
        ep.scan_id,
        s.image_storage_urls[1] AS hero_image_url,
        ep.shared_at,
        ep.user_id AS author_user_id,
        u.public_author_name AS author_name,
        COALESCE(NULLIF(sd.common_names->>'en', ''), sd.scientific_name, 'Unknown Subject') AS species_common_name,
        COALESCE(sd.scientific_name, 'Unknown Subject') AS species_scientific_name,
        public.sanitize_explore_location(s.semantic_location) AS public_location_label,
        s.time_of_day,
        s.current_month,
        s.weather_condition,
        s.weather_temperature_f,
        ep.like_count,
        ep.comment_count,
        EXISTS (
            SELECT 1
            FROM public.explore_post_likes epl
            WHERE epl.post_id = ep.id
              AND epl.user_id = self_id
        ) AS viewer_has_liked,
        (ep.user_id = self_id) AS is_owned_by_viewer
    FROM public.explore_posts ep
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = ep.user_id
    LEFT JOIN public.species_dictionary sd
        ON sd.id = COALESCE(s.confirmed_species_id, s.species_id)
    WHERE ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND COALESCE(s.confirmed_species_id, s.species_id) IS NOT NULL
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
      )
    ORDER BY ep.shared_at DESC
    LIMIT GREATEST(COALESCE(max_limit, 20), 0)
    OFFSET GREATEST(COALESCE(feed_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION public.get_explore_comments(
    self_id UUID,
    target_post_id UUID,
    max_limit INTEGER DEFAULT 50,
    comment_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    comment_id UUID,
    post_id UUID,
    author_user_id UUID,
    author_name TEXT,
    body TEXT,
    created_at TIMESTAMPTZ,
    viewer_can_delete BOOLEAN
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.id AS comment_id,
        c.post_id,
        c.user_id AS author_user_id,
        u.public_author_name AS author_name,
        c.body,
        c.created_at,
        (c.user_id = self_id OR ep.user_id = self_id) AS viewer_can_delete
    FROM public.explore_post_comments c
    JOIN public.explore_posts ep
        ON ep.id = c.post_id
    JOIN public.scans s
        ON s.id = ep.scan_id
    JOIN public.users u
        ON u.id = c.user_id
    WHERE c.post_id = target_post_id
      AND c.deleted_at IS NULL
      AND ep.unshared_at IS NULL
      AND s.is_tombstoned = FALSE
      AND COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0
      AND s.geoprivacy <> 'private'
      AND u.is_shadowbanned = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.user_blocks ub
          WHERE (ub.blocker_id = self_id AND ub.blocked_id = ep.user_id)
             OR (ub.blocker_id = ep.user_id AND ub.blocked_id = self_id)
             OR (ub.blocker_id = self_id AND ub.blocked_id = c.user_id)
             OR (ub.blocker_id = c.user_id AND ub.blocked_id = self_id)
      )
    ORDER BY c.created_at ASC
    LIMIT GREATEST(COALESCE(max_limit, 50), 0)
    OFFSET GREATEST(COALESCE(comment_offset, 0), 0);
$$;

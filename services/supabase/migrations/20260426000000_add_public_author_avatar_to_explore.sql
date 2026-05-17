ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS public_avatar_url TEXT;

CREATE OR REPLACE FUNCTION public.extract_public_avatar_url(raw_meta JSONB)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(raw_meta->>'avatar_url'), ''),
        NULLIF(BTRIM(raw_meta->>'picture'), '')
    );
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
    resolved_avatar_url TEXT;
BEGIN
    SELECT public_author_name, public_identity_source
    INTO existing_name, existing_source
    FROM public.users
    WHERE id = target_user_id;

    SELECT raw_user_meta_data
    INTO auth_meta
    FROM auth.users
    WHERE id = target_user_id;

    resolved_avatar_url := public.extract_public_avatar_url(auth_meta);

    IF existing_source = 'display_name' AND existing_name IS NOT NULL AND BTRIM(existing_name) <> '' THEN
        UPDATE public.users
        SET public_avatar_url = resolved_avatar_url
        WHERE id = target_user_id;
        RETURN;
    END IF;

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(auth_meta, target_user_id);

    UPDATE public.users
    SET public_author_name = resolved_name,
        public_identity_source = resolved_source,
        public_avatar_url = resolved_avatar_url
    WHERE id = target_user_id;
END;
$$;

UPDATE public.users AS u
SET public_avatar_url = public.extract_public_avatar_url(au.raw_user_meta_data)
FROM auth.users AS au
WHERE u.id = au.id;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
BEGIN
    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(new.raw_user_meta_data, new.id);

    resolved_avatar_url := public.extract_public_avatar_url(new.raw_user_meta_data);

    INSERT INTO public.users (id, email, public_author_name, public_identity_source, public_avatar_url)
    VALUES (new.id, new.email, resolved_name, resolved_source, resolved_avatar_url)
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        public_avatar_url = EXCLUDED.public_avatar_url;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP FUNCTION IF EXISTS public.get_explore_feed(UUID, INTEGER, INTEGER);

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
    author_avatar_url TEXT,
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
        u.public_avatar_url AS author_avatar_url,
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

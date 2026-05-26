CREATE OR REPLACE FUNCTION public.build_unique_public_username(raw_username TEXT, target_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    base_username TEXT := public.public_username_base(raw_username, target_user_id);
    candidate_username TEXT := base_username;
    suffix TEXT;
    attempt INTEGER := 0;
    max_base_length INTEGER;
BEGIN
    WHILE EXISTS (
        SELECT 1
        FROM public.users
        WHERE public_username = candidate_username
          AND id <> target_user_id
    ) LOOP
        attempt := attempt + 1;
        suffix := '_' || SUBSTRING(MD5(target_user_id::TEXT || ':' || attempt::TEXT) FROM 1 FOR 6);
        max_base_length := 24 - CHAR_LENGTH(suffix);
        candidate_username := RTRIM(LEFT(base_username, max_base_length), '_') || suffix;

        IF attempt > 128 THEN
            RAISE EXCEPTION 'Unable to generate unique username for user %', target_user_id;
        END IF;
    END LOOP;

    RETURN candidate_username;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
    resolved_meta JSONB;
    resolved_username TEXT;
BEGIN
    resolved_meta := COALESCE(public.public_author_metadata_for_auth_user(NEW.id), NEW.raw_user_meta_data, '{}'::jsonb);

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(resolved_meta, NEW.id);

    resolved_username := public.build_unique_public_username(resolved_name, NEW.id);
    IF resolved_source = 'alias' THEN
        resolved_name := resolved_username;
    END IF;

    resolved_avatar_url := public.extract_public_avatar_url(resolved_meta);

    INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source,
        public_avatar_url,
        public_username
    )
    VALUES (
        NEW.id,
        NEW.email,
        resolved_name,
        resolved_source,
        resolved_avatar_url,
        resolved_username
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        public_avatar_url = EXCLUDED.public_avatar_url;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

CREATE OR REPLACE FUNCTION public.handle_auth_user_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
    resolved_meta JSONB;
    resolved_username TEXT;
BEGIN
    IF OLD.email IS NOT DISTINCT FROM NEW.email
       AND OLD.raw_user_meta_data IS NOT DISTINCT FROM NEW.raw_user_meta_data THEN
        RETURN NEW;
    END IF;

    resolved_meta := COALESCE(public.public_author_metadata_for_auth_user(NEW.id), NEW.raw_user_meta_data, '{}'::jsonb);

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(resolved_meta, NEW.id);

    resolved_username := public.build_unique_public_username(resolved_name, NEW.id);
    IF resolved_source = 'alias' THEN
        resolved_name := resolved_username;
    END IF;

    resolved_avatar_url := public.extract_public_avatar_url(resolved_meta);

    INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source,
        public_avatar_url,
        public_username
    )
    VALUES (
        NEW.id,
        NEW.email,
        resolved_name,
        resolved_source,
        resolved_avatar_url,
        resolved_username
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email;

    PERFORM public.refresh_public_author_identity(NEW.id);

    RETURN NEW;
END;
$$;

UPDATE public.users
SET public_author_name = public_username
WHERE public_identity_source = 'alias'
  AND public_author_name IS DISTINCT FROM public_username;

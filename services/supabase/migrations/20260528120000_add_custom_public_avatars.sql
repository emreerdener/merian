ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS custom_avatar_url TEXT,
    ADD COLUMN IF NOT EXISTS custom_avatar_updated_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.resolve_public_avatar_url(
    custom_avatar_url TEXT,
    raw_meta JSONB
)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(custom_avatar_url), ''),
        public.extract_public_avatar_url(COALESCE(raw_meta, '{}'::jsonb))
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
    existing_username TEXT;
    existing_custom_avatar_url TEXT;
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
BEGIN
    SELECT public_author_name, public_identity_source, public_username, custom_avatar_url
    INTO existing_name, existing_source, existing_username, existing_custom_avatar_url
    FROM public.users
    WHERE id = target_user_id;

    auth_meta := COALESCE(public.public_author_metadata_for_auth_user(target_user_id), '{}'::jsonb);
    resolved_avatar_url := public.resolve_public_avatar_url(existing_custom_avatar_url, auth_meta);

    IF existing_source = 'display_name' AND existing_name IS NOT NULL AND BTRIM(existing_name) <> '' THEN
        UPDATE public.users
        SET public_avatar_url = resolved_avatar_url
        WHERE id = target_user_id;
        RETURN;
    END IF;

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(auth_meta, target_user_id);

    IF resolved_source = 'alias' THEN
        resolved_name := COALESCE(NULLIF(BTRIM(existing_username), ''), public.build_default_public_username(target_user_id));
    END IF;

    UPDATE public.users
    SET public_author_name = resolved_name,
        public_identity_source = resolved_source,
        public_avatar_url = resolved_avatar_url
    WHERE id = target_user_id;
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

    resolved_avatar_url := public.resolve_public_avatar_url(NULL, resolved_meta);

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
        public_avatar_url = public.resolve_public_avatar_url(users.custom_avatar_url, resolved_meta);

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

    resolved_avatar_url := public.resolve_public_avatar_url(NULL, resolved_meta);

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
SET public_avatar_url = public.resolve_public_avatar_url(custom_avatar_url, '{}'::jsonb)
WHERE custom_avatar_url IS NOT NULL
  AND public_avatar_url IS DISTINCT FROM public.resolve_public_avatar_url(custom_avatar_url, '{}'::jsonb);

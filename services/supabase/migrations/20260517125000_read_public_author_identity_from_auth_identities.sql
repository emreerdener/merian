-- Supabase provider profile payloads can live in auth.identities.identity_data
-- instead of auth.users.raw_user_meta_data, especially for linked OAuth
-- identities. Explore public author refreshes need to read both sources or
-- an upgraded user can keep their generated ghost alias indefinitely.

CREATE OR REPLACE FUNCTION public.public_author_metadata_for_auth_user(target_user_id UUID)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT jsonb_strip_nulls(
        COALESCE(identity.identity_data, '{}'::jsonb)
        || COALESCE(au.raw_user_meta_data, '{}'::jsonb)
    )
    FROM auth.users au
    LEFT JOIN LATERAL (
        SELECT i.identity_data
        FROM auth.identities i
        WHERE i.user_id = au.id
        ORDER BY
            CASE
                WHEN BTRIM(COALESCE(
                    i.identity_data->>'full_name',
                    i.identity_data->>'name',
                    i.identity_data->>'display_name',
                    i.identity_data->>'given_name',
                    i.identity_data->>'first_name',
                    ''
                )) <> '' THEN 0
                ELSE 1
            END,
            CASE
                WHEN BTRIM(COALESCE(
                    i.identity_data->>'avatar_url',
                    i.identity_data->>'picture',
                    i.identity_data->>'picture_url',
                    i.identity_data->>'avatar',
                    ''
                )) <> '' THEN 0
                ELSE 1
            END,
            COALESCE(i.last_sign_in_at, i.updated_at, i.created_at) DESC NULLS LAST
        LIMIT 1
    ) identity ON TRUE
    WHERE au.id = target_user_id;
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
    raw_name TEXT := BTRIM(COALESCE(
        raw_meta->>'full_name',
        raw_meta->>'name',
        raw_meta->>'display_name',
        ''
    ));
    given_name TEXT := BTRIM(COALESCE(
        raw_meta->>'given_name',
        raw_meta->>'first_name',
        ''
    ));
    family_name TEXT := BTRIM(COALESCE(
        raw_meta->>'family_name',
        raw_meta->>'last_name',
        ''
    ));
    normalized_name TEXT;
    name_parts TEXT[];
    first_name TEXT;
    last_name_initial TEXT;
BEGIN
    IF raw_name = '' AND given_name <> '' THEN
        raw_name := given_name;
        IF family_name <> '' THEN
            raw_name := raw_name || ' ' || family_name;
        END IF;
    END IF;

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

CREATE OR REPLACE FUNCTION public.extract_public_avatar_url(raw_meta JSONB)
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(raw_meta->>'avatar_url'), ''),
        NULLIF(BTRIM(raw_meta->>'picture'), ''),
        NULLIF(BTRIM(raw_meta->>'picture_url'), ''),
        NULLIF(BTRIM(raw_meta->>'avatar'), '')
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

    auth_meta := COALESCE(public.public_author_metadata_for_auth_user(target_user_id), '{}'::jsonb);
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
BEGIN
    IF OLD.email IS NOT DISTINCT FROM NEW.email
       AND OLD.raw_user_meta_data IS NOT DISTINCT FROM NEW.raw_user_meta_data THEN
        RETURN NEW;
    END IF;

    resolved_meta := COALESCE(public.public_author_metadata_for_auth_user(NEW.id), NEW.raw_user_meta_data, '{}'::jsonb);

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(resolved_meta, NEW.id);

    resolved_avatar_url := public.extract_public_avatar_url(resolved_meta);

    INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source,
        public_avatar_url
    )
    VALUES (
        NEW.id,
        NEW.email,
        resolved_name,
        resolved_source,
        resolved_avatar_url
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email;

    PERFORM public.refresh_public_author_identity(NEW.id);

    RETURN NEW;
END;
$$;

UPDATE public.users AS u
SET email = au.email,
    public_author_name = derived.author_name,
    public_identity_source = derived.identity_source,
    public_avatar_url = public.extract_public_avatar_url(resolved.meta)
FROM auth.users AS au
CROSS JOIN LATERAL (
    SELECT COALESCE(public.public_author_metadata_for_auth_user(au.id), au.raw_user_meta_data, '{}'::jsonb) AS meta
) resolved
CROSS JOIN LATERAL public.derive_public_author_identity(resolved.meta, au.id) AS derived
WHERE u.id = au.id
  AND COALESCE(u.public_identity_source, 'alias') <> 'display_name'
  AND (
      u.email IS DISTINCT FROM au.email
      OR u.public_author_name IS DISTINCT FROM derived.author_name
      OR u.public_identity_source IS DISTINCT FROM derived.identity_source
      OR u.public_avatar_url IS DISTINCT FROM public.extract_public_avatar_url(resolved.meta)
  );

UPDATE public.users AS u
SET email = au.email,
    public_avatar_url = public.extract_public_avatar_url(resolved.meta)
FROM auth.users AS au
CROSS JOIN LATERAL (
    SELECT COALESCE(public.public_author_metadata_for_auth_user(au.id), au.raw_user_meta_data, '{}'::jsonb) AS meta
) resolved
WHERE u.id = au.id
  AND u.public_identity_source = 'display_name'
  AND (
      u.email IS DISTINCT FROM au.email
      OR u.public_avatar_url IS DISTINCT FROM public.extract_public_avatar_url(resolved.meta)
  );

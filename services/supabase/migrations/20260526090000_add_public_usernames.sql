ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS public_username TEXT;

CREATE OR REPLACE FUNCTION public.normalize_public_username(raw_username TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT NULLIF(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                TRIM(BOTH '_' FROM REGEXP_REPLACE(LOWER(REGEXP_REPLACE(BTRIM(COALESCE(raw_username, '')), '^@+', '')), '[^a-z0-9]+', '_', 'g')),
                '_{2,}',
                '_',
                'g'
            ),
            '^_+|_+$',
            '',
            'g'
        ),
        ''
    );
$$;

CREATE OR REPLACE FUNCTION public.is_reserved_public_username(candidate_username TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT LOWER(BTRIM(COALESCE(candidate_username, ''))) = ANY (ARRAY[
        'admin',
        'administrator',
        'api',
        'explore',
        'help',
        'merian',
        'moderator',
        'null',
        'official',
        'root',
        'staff',
        'support',
        'system',
        'undefined'
    ]);
$$;

CREATE OR REPLACE FUNCTION public.is_valid_public_username(candidate_username TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT candidate_username IS NOT NULL
       AND candidate_username = LOWER(candidate_username)
       AND CHAR_LENGTH(candidate_username) BETWEEN 3 AND 24
       AND candidate_username ~ '^[a-z][a-z0-9_]*[a-z0-9]$'
       AND candidate_username !~ '__'
       AND NOT public.is_reserved_public_username(candidate_username);
$$;

CREATE OR REPLACE FUNCTION public.build_default_public_username(target_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    alias_hash BYTEA := DECODE(MD5(target_user_id::TEXT), 'hex');
    first_words TEXT[] := ARRAY[
        'amber', 'aster', 'briar', 'cedar',
        'clover', 'ember', 'fern', 'juniper',
        'maple', 'meadow', 'moss', 'oak',
        'river', 'sage', 'stone', 'willow'
    ];
    second_words TEXT[] := ARRAY[
        'brook', 'dawn', 'dune', 'field',
        'glen', 'grove', 'harbor', 'hollow',
        'path', 'ridge', 'sky', 'sprout',
        'trail', 'vale', 'vista', 'wren'
    ];
    first_index INTEGER;
    second_index INTEGER;
    suffix_number INTEGER;
BEGIN
    first_index := (GET_BYTE(alias_hash, 0) % ARRAY_LENGTH(first_words, 1)) + 1;
    second_index := (GET_BYTE(alias_hash, 1) % ARRAY_LENGTH(second_words, 1)) + 1;
    suffix_number := (((GET_BYTE(alias_hash, 2) * 256) + GET_BYTE(alias_hash, 3)) % 90) + 10;

    RETURN first_words[first_index] || '_' || second_words[second_index] || '_' || suffix_number::TEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.build_default_public_alias(target_user_id UUID)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT public.build_default_public_username(target_user_id);
$$;

CREATE OR REPLACE FUNCTION public.public_username_base(raw_username TEXT, target_user_id UUID)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN public.is_valid_public_username(public.normalize_public_username(raw_username))
            THEN public.normalize_public_username(raw_username)
        ELSE public.build_default_public_username(target_user_id)
    END;
$$;

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

WITH username_bases AS (
    SELECT
        id,
        public.public_username_base(COALESCE(public_username, public_author_name), id) AS base_username
    FROM public.users
),
ranked_usernames AS (
    SELECT
        id,
        base_username,
        ROW_NUMBER() OVER (PARTITION BY base_username ORDER BY id) AS username_rank
    FROM username_bases
)
UPDATE public.users AS u
SET public_username = CASE
        WHEN ranked_usernames.username_rank = 1 THEN ranked_usernames.base_username
        ELSE LEFT(ranked_usernames.base_username, 17) || '_' || SUBSTRING(MD5(ranked_usernames.id::TEXT) FROM 1 FOR 6)
    END
FROM ranked_usernames
WHERE u.id = ranked_usernames.id
  AND (
      u.public_username IS NULL
      OR NOT public.is_valid_public_username(u.public_username)
  );

UPDATE public.users
SET public_author_name = public_username
WHERE public_identity_source = 'alias'
  AND public_author_name IS DISTINCT FROM public_username;

ALTER TABLE public.users
    ALTER COLUMN public_username SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_public_username_valid_check'
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_public_username_valid_check
            CHECK (public.is_valid_public_username(public_username));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS users_public_username_unique_idx
    ON public.users(public_username);

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
    SELECT public.build_default_public_username(target_user_id), 'alias';
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
    existing_username TEXT;
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
BEGIN
    SELECT public_author_name, public_identity_source, public_username
    INTO existing_name, existing_source, existing_username
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

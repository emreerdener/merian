-- Keep public author identity refreshes idempotent and restrict the maintenance
-- surface to trusted backend callers. Auth triggers continue to execute these
-- functions as their owner, while Edge Functions use the service role.

CREATE OR REPLACE FUNCTION public.refresh_public_author_identity(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
    SELECT
        user_row.public_author_name,
        user_row.public_identity_source,
        user_row.public_username,
        user_row.custom_avatar_url
    INTO
        existing_name,
        existing_source,
        existing_username,
        existing_custom_avatar_url
    FROM public.users AS user_row
    WHERE user_row.id = target_user_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    auth_meta := COALESCE(
        public.public_author_metadata_for_auth_user(target_user_id),
        '{}'::JSONB
    );
    resolved_avatar_url := public.resolve_public_avatar_url(
        existing_custom_avatar_url,
        auth_meta
    );

    IF existing_source = 'display_name'
        AND existing_name IS NOT NULL
        AND BTRIM(existing_name) <> '' THEN
        UPDATE public.users AS user_row
        SET public_avatar_url = resolved_avatar_url
        WHERE user_row.id = target_user_id
          AND user_row.public_avatar_url IS DISTINCT FROM resolved_avatar_url;
        RETURN;
    END IF;

    SELECT identity.author_name, identity.identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(auth_meta, target_user_id) AS identity;

    IF resolved_source = 'alias' THEN
        resolved_name := COALESCE(
            NULLIF(BTRIM(existing_username), ''),
            public.build_default_public_username(target_user_id)
        );
    END IF;

    UPDATE public.users AS user_row
    SET public_author_name = resolved_name,
        public_identity_source = resolved_source,
        public_avatar_url = resolved_avatar_url
    WHERE user_row.id = target_user_id
      AND (
          user_row.public_author_name IS DISTINCT FROM resolved_name
          OR user_row.public_identity_source IS DISTINCT FROM resolved_source
          OR user_row.public_avatar_url IS DISTINCT FROM resolved_avatar_url
      );
END;
$$;

CREATE OR REPLACE FUNCTION public.repair_explore_post_ownership_for_user(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE public.explore_posts AS post
    SET user_id = scan.user_id
    FROM public.scans AS scan
    WHERE post.scan_id = scan.id
      AND scan.user_id = target_user_id
      AND post.user_id <> scan.user_id;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_public_author_identity(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_public_author_identity(UUID)
    TO service_role;

REVOKE ALL ON FUNCTION public.repair_explore_post_ownership_for_user(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.repair_explore_post_ownership_for_user(UUID)
    TO service_role;

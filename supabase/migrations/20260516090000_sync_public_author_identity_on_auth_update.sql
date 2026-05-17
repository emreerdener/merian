-- Keep public Explore author identity aligned when an anonymous auth user is
-- upgraded in-place by linking Google/Apple. The original insert trigger gives
-- ghost users a generated alias, but linking OAuth later updates auth.users
-- instead of inserting a new row.

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
BEGIN
    IF OLD.email IS NOT DISTINCT FROM NEW.email
       AND OLD.raw_user_meta_data IS NOT DISTINCT FROM NEW.raw_user_meta_data THEN
        RETURN NEW;
    END IF;

    SELECT author_name, identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(NEW.raw_user_meta_data, NEW.id);

    resolved_avatar_url := public.extract_public_avatar_url(NEW.raw_user_meta_data);

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

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
AFTER UPDATE OF email, raw_user_meta_data ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_auth_user_updated();

-- Repair accounts that already linked OAuth while public.users still contained
-- the generated alias from their ghost session. Preserve explicit display names.
UPDATE public.users AS u
SET email = au.email,
    public_author_name = derived.author_name,
    public_identity_source = derived.identity_source,
    public_avatar_url = public.extract_public_avatar_url(au.raw_user_meta_data)
FROM auth.users AS au
CROSS JOIN LATERAL public.derive_public_author_identity(au.raw_user_meta_data, au.id) AS derived
WHERE u.id = au.id
  AND u.public_identity_source <> 'display_name'
  AND (
      u.email IS DISTINCT FROM au.email
      OR u.public_author_name IS DISTINCT FROM derived.author_name
      OR u.public_identity_source IS DISTINCT FROM derived.identity_source
      OR u.public_avatar_url IS DISTINCT FROM public.extract_public_avatar_url(au.raw_user_meta_data)
  );

-- For users with an explicit public display name, keep the chosen name but still
-- refresh contact/avatar fields from the linked OAuth account.
UPDATE public.users AS u
SET email = au.email,
    public_avatar_url = public.extract_public_avatar_url(au.raw_user_meta_data)
FROM auth.users AS au
WHERE u.id = au.id
  AND u.public_identity_source = 'display_name'
  AND (
      u.email IS DISTINCT FROM au.email
      OR u.public_avatar_url IS DISTINCT FROM public.extract_public_avatar_url(au.raw_user_meta_data)
  );

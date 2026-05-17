-- Repair stale Explore author identity for accounts that linked or restored
-- OAuth after first publishing as a ghost user. This migration is intentionally
-- idempotent so it can be applied after earlier client-side fixes.

CREATE OR REPLACE FUNCTION public.repair_explore_post_ownership_for_user(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE public.explore_posts ep
    SET user_id = s.user_id
    FROM public.scans s
    WHERE ep.scan_id = s.id
      AND s.user_id = target_user_id
      AND ep.user_id <> s.user_id;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

-- Keep Explore post ownership aligned with the canonical scan owner. This
-- covers ghost-account merges where scans moved but denormalized post owners
-- were left behind.
UPDATE public.explore_posts ep
SET user_id = s.user_id
FROM public.scans s
WHERE ep.scan_id = s.id
  AND ep.user_id <> s.user_id;

-- Refresh OAuth-derived public names and avatars for existing users that still
-- show a generated ghost alias. Preserve explicit in-app display names.
UPDATE public.users AS u
SET email = au.email,
    public_author_name = derived.author_name,
    public_identity_source = derived.identity_source,
    public_avatar_url = public.extract_public_avatar_url(au.raw_user_meta_data)
FROM auth.users AS au
CROSS JOIN LATERAL public.derive_public_author_identity(au.raw_user_meta_data, au.id) AS derived
WHERE u.id = au.id
  AND COALESCE(u.public_identity_source, 'alias') <> 'display_name'
  AND (
      u.email IS DISTINCT FROM au.email
      OR u.public_author_name IS DISTINCT FROM derived.author_name
      OR u.public_identity_source IS DISTINCT FROM derived.identity_source
      OR u.public_avatar_url IS DISTINCT FROM public.extract_public_avatar_url(au.raw_user_meta_data)
  );

-- Display-name profiles keep their chosen name but should still pick up the
-- current auth email and avatar.
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

-- Keep Ask the Community ownership aligned with the canonical scan owner.
-- Community requests reference public.users through requested_by with
-- ON DELETE CASCADE, so stale ghost ownership can make requests disappear
-- during account merge or disappear from the signed-in user's "Yours" view.

CREATE OR REPLACE FUNCTION public.repair_community_request_ownership_for_user(target_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE public.explore_community_requests ecr
    SET requested_by = s.user_id,
        updated_at = now()
    FROM public.scans s
    WHERE ecr.scan_id = s.id
      AND s.user_id = target_user_id
      AND ecr.requested_by <> s.user_id;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$;

UPDATE public.explore_community_requests ecr
SET requested_by = s.user_id,
    updated_at = now()
FROM public.scans s
WHERE ecr.scan_id = s.id
  AND ecr.requested_by <> s.user_id;

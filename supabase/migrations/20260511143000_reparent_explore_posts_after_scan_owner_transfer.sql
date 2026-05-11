-- Explore posts denormalize the author user id for feed and profile queries.
-- Ghost-account merges already re-parent scans, but previously left matching
-- explore_posts rows attached to the deleted anonymous author. Repair existing
-- rows and keep own-profile Explore previews aligned with the current scan owner.

UPDATE public.explore_posts ep
SET user_id = s.user_id
FROM public.scans s
WHERE ep.scan_id = s.id
  AND ep.user_id <> s.user_id;

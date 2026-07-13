CREATE TABLE IF NOT EXISTS public.explore_post_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.explore_posts(id) ON DELETE CASCADE,
    reporter_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    post_author_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL CHECK (reason IN ('Spam', 'Harassment', 'Inappropriate content', 'Other')),
    details TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
        CHECK (status IN ('PENDING_REVIEW', 'DISMISSED', 'ACTIONED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_explore_post_reports_post_reporter_unique
    ON public.explore_post_reports (post_id, reporter_user_id);

CREATE INDEX IF NOT EXISTS idx_explore_post_reports_status_created
    ON public.explore_post_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_explore_post_reports_author
    ON public.explore_post_reports (post_author_user_id, created_at DESC);

ALTER TABLE public.explore_post_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.explore_post_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.explore_post_reports TO service_role;

COMMENT ON TABLE public.explore_post_reports IS
  'Moderation reports about public Explore post content. Separate from flagged_reviews, which is reserved for identification review.';

-- Repair reports previously sent through flag-issue by the native Explore UI.
INSERT INTO public.explore_post_reports (
    post_id,
    reporter_user_id,
    post_author_user_id,
    reason,
    details,
    status,
    created_at,
    updated_at
)
SELECT DISTINCT ON (ep.id, fr.user_id)
    ep.id,
    fr.user_id,
    ep.user_id,
    fr.flag_reason,
    NULLIF(BTRIM(fr.user_suggestion), ''),
    'PENDING_REVIEW',
    fr.created_at,
    fr.created_at
FROM public.flagged_reviews fr
JOIN public.explore_posts ep ON ep.scan_id = fr.scan_id
WHERE fr.flag_reason = 'Inappropriate content'
  AND fr.user_suggestion = 'Reported from Explore feed'
  AND ep.user_id <> fr.user_id
ORDER BY ep.id, fr.user_id, fr.created_at ASC
ON CONFLICT (post_id, reporter_user_id) DO UPDATE
SET reason = EXCLUDED.reason,
    details = EXCLUDED.details,
    updated_at = NOW();

UPDATE public.flagged_reviews
SET status = 'MIGRATED_TO_EXPLORE_POST_REPORT'
WHERE status = 'PENDING_REVIEW'
  AND flag_reason = 'Inappropriate content'
  AND user_suggestion = 'Reported from Explore feed';

UPDATE public.scans scan
SET is_flagged = EXISTS (
        SELECT 1
        FROM public.flagged_reviews fr
        WHERE fr.scan_id = scan.id
          AND fr.status = 'PENDING_REVIEW'
    ),
    human_intervention_notes = CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.flagged_reviews fr
            WHERE fr.scan_id = scan.id
              AND fr.status = 'PENDING_REVIEW'
        ) THEN scan.human_intervention_notes
        ELSE NULL
    END
WHERE EXISTS (
    SELECT 1
    FROM public.flagged_reviews fr
    WHERE fr.scan_id = scan.id
      AND fr.status = 'MIGRATED_TO_EXPLORE_POST_REPORT'
);

NOTIFY pgrst, 'reload schema';

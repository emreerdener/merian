-- The initial atomic flag-issue routine used INSERT ... RETURNING id only to
-- distinguish an admitted owner row from a zero-row conditional insert.
-- RETURNING requires SELECT on the returned column, but this SECURITY INVOKER
-- intentionally gives service_role INSERT-only access to flagged_reviews.
-- Detect the affected-row count without widening that table privilege.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.submit_owned_flag_issue(
    p_scan_id UUID,
    p_reporter_user_id UUID,
    p_flag_reason TEXT,
    p_user_suggestion TEXT
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    inserted_review_count INTEGER;
    scan_owner_id UUID;
    scan_is_tombstoned BOOLEAN;
BEGIN
    IF p_scan_id IS NULL
       OR p_reporter_user_id IS NULL
       OR p_flag_reason IS NULL
       OR p_flag_reason NOT IN (
           'Incorrect species',
           'Inappropriate content',
           'Bad image quality',
           'Other'
       ) THEN
        RAISE EXCEPTION 'invalid_flag_issue_input'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.flagged_reviews (
        scan_id,
        user_id,
        flag_reason,
        user_suggestion
    )
    SELECT
        p_scan_id,
        p_reporter_user_id,
        p_flag_reason,
        p_user_suggestion
    FROM public.scans AS scan
    WHERE scan.id = p_scan_id
      AND scan.user_id = p_reporter_user_id
      AND scan.is_tombstoned IS FALSE;

    GET DIAGNOSTICS inserted_review_count = ROW_COUNT;

    IF inserted_review_count = 0 THEN
        SELECT scan.user_id, scan.is_tombstoned
        INTO scan_owner_id, scan_is_tombstoned
        FROM public.scans AS scan
        WHERE scan.id = p_scan_id;

        IF NOT FOUND OR scan_is_tombstoned THEN
            RETURN 'not_found';
        END IF;
        RETURN 'not_owner';
    END IF;

    -- The flagged-review trigger acquires the review-case resource before it
    -- updates this scan. Revalidate only after that trigger so this path keeps
    -- the same review-case -> scan lock order as moderator transitions.
    SELECT scan.user_id, scan.is_tombstoned
    INTO scan_owner_id, scan_is_tombstoned
    FROM public.scans AS scan
    WHERE scan.id = p_scan_id
    FOR UPDATE OF scan;

    IF NOT FOUND
       OR scan_is_tombstoned
       OR scan_owner_id IS DISTINCT FROM p_reporter_user_id THEN
        RAISE EXCEPTION 'flag_issue_ownership_changed'
            USING ERRCODE = '40001';
    END IF;

    UPDATE public.scans AS scan
    SET is_flagged = TRUE,
        human_intervention_notes = pg_catalog.FORMAT(
            'Flag Reason: %s | Suggestion: %s',
            p_flag_reason,
            COALESCE(p_user_suggestion, 'None')
        )
    WHERE scan.id = p_scan_id
      AND scan.user_id = p_reporter_user_id
      AND scan.is_tombstoned IS FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'flag_issue_scan_update_failed'
            USING ERRCODE = '55000';
    END IF;

    RETURN 'submitted';
END;
$$;

COMMENT ON FUNCTION public.submit_owned_flag_issue(UUID, UUID, TEXT, TEXT) IS
    'Service-only atomic identification-dispute intake for a non-tombstoned scan owned by the authenticated reporter.';

REVOKE ALL ON FUNCTION public.submit_owned_flag_issue(
    UUID,
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_owned_flag_issue(
    UUID,
    UUID,
    TEXT,
    TEXT
) TO service_role;

GRANT INSERT ON TABLE public.flagged_reviews TO service_role;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;

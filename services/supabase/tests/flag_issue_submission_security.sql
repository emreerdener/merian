\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(17);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
SELECT
    '00000000-0000-0000-0000-000000000000',
    seed.user_id,
    'authenticated',
    'authenticated',
    seed.email,
    pg_catalog.NOW(),
    pg_catalog.JSONB_BUILD_OBJECT(
        'provider',
        'email',
        'providers',
        pg_catalog.JSONB_BUILD_ARRAY('email')
    ),
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
FROM (
    VALUES
        (
            '00000000-0000-0000-0000-00000000f101'::UUID,
            'flag-owner@naturebook.invalid'
        ),
        (
            '00000000-0000-0000-0000-00000000f102'::UUID,
            'flag-nonowner@naturebook.invalid'
        )
) AS seed(user_id, email);

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    native_region
)
VALUES (
    '00000000-0000-0000-0000-00000000f110',
    'Contractus flagissue',
    '{"en":"Flag issue contract species"}',
    'Test region'
);

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    ai_confidence_score,
    is_tombstoned
)
VALUES
    (
        '00000000-0000-0000-0000-00000000f120',
        '00000000-0000-0000-0000-00000000f101',
        '00000000-0000-0000-0000-00000000f110',
        0.91,
        FALSE
    ),
    (
        '00000000-0000-0000-0000-00000000f121',
        '00000000-0000-0000-0000-00000000f101',
        '00000000-0000-0000-0000-00000000f110',
        0.91,
        TRUE
    ),
    (
        '00000000-0000-0000-0000-00000000f122',
        '00000000-0000-0000-0000-00000000f101',
        '00000000-0000-0000-0000-00000000f110',
        0.91,
        FALSE
    );

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.submit_owned_flag_issue(uuid,uuid,text,text)',
        'EXECUTE'
    ),
    'service role can execute the atomic flag transaction'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.submit_owned_flag_issue(uuid,uuid,text,text)',
        'EXECUTE'
    ),
    'anonymous callers cannot execute the atomic flag transaction'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.submit_owned_flag_issue(uuid,uuid,text,text)',
        'EXECUTE'
    ),
    'authenticated clients cannot execute the atomic flag transaction directly'
);
SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.flagged_reviews',
        'INSERT'
    ),
    'the invoker transaction has its explicit flagged-review insert privilege'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'service_role',
        'public.flagged_reviews',
        'id',
        'SELECT'
    ),
    'the invoker transaction does not require flagged-review read access'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.submit_owned_flag_issue(
        '00000000-0000-0000-0000-00000000f120',
        '00000000-0000-0000-0000-00000000f101',
        'Incorrect species',
        'Expected species'
    ),
    'submitted',
    'the exact scan owner can submit an identification dispute'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.flagged_reviews AS review
        WHERE review.scan_id = '00000000-0000-0000-0000-00000000f120'
    ),
    1,
    'an owner submission inserts exactly one flagged review'
);
SELECT extensions.ok(
    (
        SELECT scan.is_flagged
        FROM public.scans AS scan
        WHERE scan.id = '00000000-0000-0000-0000-00000000f120'
    ),
    'an owner submission marks the same scan for review'
);
SELECT extensions.is(
    (
        SELECT scan.human_intervention_notes
        FROM public.scans AS scan
        WHERE scan.id = '00000000-0000-0000-0000-00000000f120'
    ),
    'Flag Reason: Incorrect species | Suggestion: Expected species',
    'the scan receives the submitted review context'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM internal.review_cases AS review_case
        WHERE review_case.case_type = 'identification'
          AND review_case.subject_id =
              '00000000-0000-0000-0000-00000000f120'
    ),
    1,
    'the existing trigger attaches the review to one internal case'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.submit_owned_flag_issue(
        '00000000-0000-0000-0000-00000000f120',
        '00000000-0000-0000-0000-00000000f102',
        'Other',
        NULL
    ),
    'not_owner',
    'a non-owner cannot submit an identification dispute'
);
SELECT extensions.is(
    public.submit_owned_flag_issue(
        '00000000-0000-0000-0000-00000000f121',
        '00000000-0000-0000-0000-00000000f101',
        'Other',
        NULL
    ),
    'not_found',
    'a tombstoned owner scan is unavailable'
);
SELECT extensions.throws_ok(
    $statement$
        SELECT public.submit_owned_flag_issue(
            '00000000-0000-0000-0000-00000000f120',
            '00000000-0000-0000-0000-00000000f101',
            'Unsupported reason',
            NULL
        )
    $statement$,
    '22023',
    'invalid_flag_issue_input',
    'the database rejects a reason outside the endpoint allowlist'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.flagged_reviews AS review
        WHERE review.scan_id IN (
            '00000000-0000-0000-0000-00000000f120',
            '00000000-0000-0000-0000-00000000f121'
        )
    ),
    1,
    'rejected submissions leave no additional review rows'
);

CREATE FUNCTION pg_temp.reject_flag_scan_update()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
    IF NEW.id = '00000000-0000-0000-0000-00000000f122' THEN
        RAISE EXCEPTION 'forced_scan_update_failure'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER reject_flag_scan_update
BEFORE UPDATE ON public.scans
FOR EACH ROW
EXECUTE FUNCTION pg_temp.reject_flag_scan_update();

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.submit_owned_flag_issue(
            '00000000-0000-0000-0000-00000000f122',
            '00000000-0000-0000-0000-00000000f101',
            'Bad image quality',
            NULL
        )
    $statement$,
    '55000',
    'forced_scan_update_failure',
    'a scan-update failure aborts the transaction'
);
RESET ROLE;

DROP TRIGGER reject_flag_scan_update ON public.scans;

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.flagged_reviews AS review
        WHERE review.scan_id = '00000000-0000-0000-0000-00000000f122'
    ),
    0,
    'a failed scan update rolls back the flagged review insert'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM internal.review_cases AS review_case
        WHERE review_case.case_type = 'identification'
          AND review_case.subject_id =
              '00000000-0000-0000-0000-00000000f122'
    ),
    0,
    'a failed scan update also rolls back the internal review case'
);

SELECT * FROM extensions.finish();
ROLLBACK;

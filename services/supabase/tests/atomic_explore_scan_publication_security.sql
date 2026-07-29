\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(22);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-4000-8000-00000000e101'::UUID,
    'authenticated',
    'authenticated',
    'atomic-explore@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-4000-8000-00000000e101',
    'atomic-explore@naturebook.invalid',
    'atomic_explore_e101',
    'Atomic Explore',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    native_region
)
VALUES (
    '00000000-0000-4000-8000-00000000e102',
    'Testus atomicus e102',
    '{"en":"Atomic test species"}'::JSONB,
    'Animalia',
    'Arthropoda',
    'Insecta',
    'Lepidoptera',
    'Nymphalidae',
    'Testus',
    'Test fixture'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    geoprivacy,
    ai_confidence_score,
    timestamp,
    is_biological_subject
)
VALUES (
    '00000000-0000-4000-8000-00000000e110',
    '00000000-0000-4000-8000-00000000e101',
    '00000000-0000-4000-8000-00000000e102',
    ARRAY[
        'https://media.merian.app/public_uploads/free/'
        || '00000000-0000-4000-8000-00000000e101/'
        || '00000000-0000-4000-8000-00000000e120.webp',
        'https://media.merian.app/public_uploads/free/'
        || '00000000-0000-4000-8000-00000000e101/'
        || '00000000-0000-4000-8000-00000000e121.webp'
    ],
    'obscured',
    0.95,
    pg_catalog.NOW(),
    TRUE
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.publish_scan_to_explore_atomically(uuid,uuid,text,text,text,jsonb,text[])',
        'EXECUTE'
    ),
    'anonymous callers cannot execute atomic Explore publication'
);
SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.publish_scan_to_explore_atomically(uuid,uuid,text,text,text,jsonb,text[])',
        'EXECUTE'
    ),
    'authenticated callers cannot execute atomic Explore publication'
);
SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.publish_scan_to_explore_atomically(uuid,uuid,text,text,text,jsonb,text[])',
        'EXECUTE'
    ),
    'service-role callers can execute atomic Explore publication'
);
SELECT extensions.ok(
    NOT (
        SELECT routine.prosecdef
        FROM pg_catalog.PG_PROC AS routine
        WHERE routine.oid = pg_catalog.TO_REGPROCEDURE(
            'public.publish_scan_to_explore_atomically(uuid,uuid,text,text,text,jsonb,text[])'
        )
    ),
    'atomic Explore publication retains invoker privileges'
);
SELECT extensions.ok(
    pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_community_requests',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_community_requests',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.species_dictionary',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_posts',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_posts',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_posts',
        'UPDATE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_media',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_media',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_media',
        'DELETE'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_hashtags',
        'SELECT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_hashtags',
        'INSERT'
    )
    AND pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_post_hashtags',
        'DELETE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.explore_community_requests',
        'UPDATE'
    )
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.explore_community_requests',
        'UPDATE'
    ),
    'atomic Explore invoker has its request lock privilege without browser writes'
);

SET LOCAL ROLE service_role;
SELECT extensions.is(
    public.publish_scan_to_explore_atomically(
        '00000000-0000-4000-8000-00000000e110',
        '00000000-0000-4000-8000-00000000e101',
        'Atomic test species',
        'Original field notes',
        NULL,
        '[
          {
            "kind":"image",
            "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e120.webp",
            "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e120.webp",
            "order_index":0,
            "duration_seconds":null,
            "has_audio":false
          }
        ]'::JSONB,
        ARRAY['pollinators']::TEXT[]
    ) ->> 'publication_status',
    'published',
    'service-role publication returns an explicit published result'
);
RESET ROLE;

SELECT extensions.is(
    (
        SELECT post.location_sharing::TEXT
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    'obscured',
    'omitted location sharing resolves from geoprivacy under the owner-row lock'
);

SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
          AND post.user_id = '00000000-0000-4000-8000-00000000e101'
          AND post.unshared_at IS NULL
    ),
    1,
    'atomic publication creates exactly one active owner post'
);
SELECT extensions.is(
    (
        SELECT post.field_notes
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    'Original field notes',
    'atomic publication writes post metadata'
);
SELECT extensions.is(
    (
        SELECT media.url
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    'https://media.merian.app/public_uploads/free/'
    || '00000000-0000-4000-8000-00000000e101/'
    || '00000000-0000-4000-8000-00000000e120.webp',
    'atomic publication writes the selected owner media snapshot'
);
SELECT extensions.is(
    (
        SELECT hashtag.tag
        FROM public.explore_post_hashtags AS hashtag
        INNER JOIN public.explore_posts AS post
            ON post.id = hashtag.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    'pollinators',
    'atomic publication writes normalized hashtags'
);

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.publish_scan_to_explore_atomically(
            '00000000-0000-4000-8000-00000000e110',
            '00000000-0000-4000-8000-00000000e199',
            NULL,
            NULL,
            'private',
            '[
              {
                "kind":"image",
                "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e120.webp",
                "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e120.webp",
                "order_index":0,
                "duration_seconds":null,
                "has_audio":false
              }
            ]'::JSONB,
            ARRAY[]::TEXT[]
        )
    $statement$,
    'P0001',
    'Owned share-eligible scan not found',
    'atomic publication rejects an owner mismatch'
);
SELECT extensions.throws_ok(
    $statement$
        SELECT public.publish_scan_to_explore_atomically(
            '00000000-0000-4000-8000-00000000e110',
            '00000000-0000-4000-8000-00000000e101',
            NULL,
            NULL,
            'private',
            '[
              {
                "kind":"image",
                "url":"https://media.merian.app/public_uploads/free/other/not-owned.webp",
                "thumbnail_url":"https://media.merian.app/public_uploads/free/other/not-owned.webp",
                "order_index":0,
                "duration_seconds":null,
                "has_audio":false
              }
            ]'::JSONB,
            ARRAY[]::TEXT[]
        )
    $statement$,
    '22023',
    'Explore image does not belong to the scan',
    'atomic publication rejects media outside the exact scan'
);
RESET ROLE;

CREATE TEMPORARY TABLE explore_publication_before_failure AS
SELECT
    post.id AS post_id,
    post.field_notes,
    post.shared_at,
    media.url AS media_url,
    hashtag.tag
FROM public.explore_posts AS post
INNER JOIN public.explore_post_media AS media
    ON media.post_id = post.id
INNER JOIN public.explore_post_hashtags AS hashtag
    ON hashtag.post_id = post.id
WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110';

CREATE FUNCTION pg_temp.force_explore_hashtag_failure()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $trigger$
BEGIN
    IF NEW.tag = 'force_failure' THEN
        RAISE EXCEPTION 'fixture forced hashtag failure'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$trigger$;

CREATE TRIGGER fixture_force_explore_hashtag_failure
BEFORE INSERT
ON public.explore_post_hashtags
FOR EACH ROW
EXECUTE FUNCTION pg_temp.force_explore_hashtag_failure();

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.publish_scan_to_explore_atomically(
            '00000000-0000-4000-8000-00000000e110',
            '00000000-0000-4000-8000-00000000e101',
            'Replacement name',
            'Replacement field notes',
            'open',
            '[
              {
                "kind":"image",
                "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e121.webp",
                "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e121.webp",
                "order_index":0,
                "duration_seconds":null,
                "has_audio":false
              }
            ]'::JSONB,
            ARRAY['force_failure']::TEXT[]
        )
    $statement$,
    'P0001',
    'fixture forced hashtag failure',
    'a late relational failure aborts the complete publication statement'
);
RESET ROLE;

DROP TRIGGER fixture_force_explore_hashtag_failure
    ON public.explore_post_hashtags;

SELECT extensions.is(
    (
        SELECT post.field_notes
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    (
        SELECT snapshot.field_notes
        FROM explore_publication_before_failure AS snapshot
    ),
    'failed publication restores the prior post metadata'
);
SELECT extensions.is(
    (
        SELECT post.shared_at
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    (
        SELECT snapshot.shared_at
        FROM explore_publication_before_failure AS snapshot
    ),
    'failed publication restores the prior publication timestamp'
);
SELECT extensions.is(
    (
        SELECT media.url
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    (
        SELECT snapshot.media_url
        FROM explore_publication_before_failure AS snapshot
    ),
    'failed publication restores the prior media snapshot'
);
SELECT extensions.is(
    (
        SELECT hashtag.tag
        FROM public.explore_post_hashtags AS hashtag
        INNER JOIN public.explore_posts AS post
            ON post.id = hashtag.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    (
        SELECT snapshot.tag
        FROM explore_publication_before_failure AS snapshot
    ),
    'failed publication restores the prior hashtag snapshot'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_post_media AS media
        INNER JOIN public.explore_posts AS post
            ON post.id = media.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    1,
    'failed publication leaves no partial media rows'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_post_hashtags AS hashtag
        INNER JOIN public.explore_posts AS post
            ON post.id = hashtag.post_id
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    1,
    'failed publication leaves no partial hashtag rows'
);
SELECT extensions.is(
    (
        SELECT pg_catalog.COUNT(*)::INTEGER
        FROM public.explore_posts AS post
        WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110'
    ),
    1,
    'failed publication leaves no duplicate post'
);

INSERT INTO public.explore_community_requests (
    post_id,
    scan_id,
    requested_by
)
SELECT
    post.id,
    post.scan_id,
    post.user_id
FROM public.explore_posts AS post
WHERE post.scan_id = '00000000-0000-4000-8000-00000000e110';

SET LOCAL ROLE service_role;
SELECT extensions.throws_ok(
    $statement$
        SELECT public.publish_scan_to_explore_atomically(
            '00000000-0000-4000-8000-00000000e110',
            '00000000-0000-4000-8000-00000000e101',
            'Must remain unchanged',
            'Must remain unchanged',
            'private',
            '[
              {
                "kind":"image",
                "url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e121.webp",
                "thumbnail_url":"https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e101/00000000-0000-4000-8000-00000000e121.webp",
                "order_index":0,
                "duration_seconds":null,
                "has_audio":false
              }
            ]'::JSONB,
            ARRAY[]::TEXT[]
        )
    $statement$,
    'P0001',
    'Wait for the community to identify this request before sharing it to Explore.',
    'transaction-time needs-id state blocks ordinary Explore publication'
);
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;

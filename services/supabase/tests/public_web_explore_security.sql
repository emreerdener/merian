\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

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
VALUES (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-4000-8000-00000000e801',
    'authenticated',
    'authenticated',
    'public-web-explore@naturebook.invalid',
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
    subscription_tier,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-4000-8000-00000000e801',
    'public-web-explore@naturebook.invalid',
    'pro',
    'public_web_e801',
    'Public Web Explorer',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    subscription_tier = EXCLUDED.subscription_tier,
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
    '00000000-0000-4000-8000-00000000e811',
    'Publicus webensis',
    '{"en":"Public web species"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Publicidae',
    'Publicus',
    'Test region'
);

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    ai_confidence_score,
    geoprivacy
)
VALUES (
    '00000000-0000-4000-8000-00000000e821',
    '00000000-0000-4000-8000-00000000e801',
    '00000000-0000-4000-8000-00000000e811',
    ARRAY['https://media.example.invalid/public-web.webp'],
    0.95,
    'private'
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    species_common_name,
    location_sharing,
    field_notes,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000e831',
    '00000000-0000-4000-8000-00000000e801',
    '00000000-0000-4000-8000-00000000e821',
    'Public web species',
    'private',
    'Public field note',
    pg_catalog.NOW()
);

INSERT INTO public.explore_post_media (
    id,
    post_id,
    kind,
    url,
    thumbnail_url,
    order_index
)
VALUES (
    '00000000-0000-4000-8000-00000000e841',
    '00000000-0000-4000-8000-00000000e831',
    'image',
    'https://media.example.invalid/public-web.webp',
    'https://media.example.invalid/public-web.webp',
    0
);

DO $test$
DECLARE
    returned_count INTEGER;
    returned_row RECORD;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_public_web_explore_posts(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_public_web_explore_posts(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_public_web_explore_post_detail(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_public_web_explore_post_detail(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_public_web_explore_post_page(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_public_web_explore_post_page(uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'a browser Data API role can directly execute the server projection';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_public_web_explore_posts(uuid,integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_public_web_explore_post_detail(uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_public_web_explore_post_page(uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'the server role cannot execute the public web projection';
    END IF;
END;
$test$;

SET LOCAL ROLE anon;

DO $anon$
BEGIN
    BEGIN
        PERFORM 1
        FROM public.get_public_web_explore_posts(NULL, 24);
        RAISE EXCEPTION
            'anon unexpectedly executed the public web server projection';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$anon$;

RESET ROLE;
SET LOCAL ROLE authenticated;

DO $authenticated$
BEGIN
    BEGIN
        PERFORM 1
        FROM public.get_public_web_explore_post_detail(
            '00000000-0000-4000-8000-00000000e831'
        );
        RAISE EXCEPTION
            'authenticated unexpectedly executed the public web server projection';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        PERFORM 1
        FROM public.get_public_web_explore_post_page(
            '00000000-0000-4000-8000-00000000e831'
        );
        RAISE EXCEPTION
            'authenticated unexpectedly executed the atomic public web page projection';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$authenticated$;

RESET ROLE;
SET LOCAL ROLE service_role;

DO $service$
DECLARE
    returned_count INTEGER;
    returned_row RECORD;
BEGIN
    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_count
    FROM public.get_public_web_explore_posts(NULL, 24);

    IF returned_count <> 1 THEN
        RAISE EXCEPTION
            'the fixed-anonymous server feed did not return the public post';
    END IF;

    SELECT *
    INTO STRICT returned_row
    FROM public.get_public_web_explore_posts(
        '00000000-0000-4000-8000-00000000e831',
        1
    );

    IF returned_row.author_username <> 'public_web_e801'
       OR NOT returned_row.author_is_pro
       OR returned_row.like_count <> 0
       OR returned_row.comment_count <> 0
       OR returned_row.viewer_has_liked
       OR returned_row.is_owned_by_viewer
       OR returned_row.public_location_label IS NOT NULL THEN
        RAISE EXCEPTION
            'the public web post projection exposed incorrect identity, engagement, viewer, or private-location state';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_count
    FROM public.get_public_web_explore_post_detail(
        '00000000-0000-4000-8000-00000000e831'
    ) AS detail
    WHERE detail.field_notes = 'Public field note';

    IF returned_count <> 1 THEN
        RAISE EXCEPTION
            'the public web detail projection did not preserve canonical visible metadata';
    END IF;

    SELECT *
    INTO STRICT returned_row
    FROM public.get_public_web_explore_post_page(
        '00000000-0000-4000-8000-00000000e831'
    );

    IF returned_row.post_payload ->> 'post_id' <>
            '00000000-0000-4000-8000-00000000e831'
       OR returned_row.detail_payload ->> 'post_id' <>
            '00000000-0000-4000-8000-00000000e831' THEN
        RAISE EXCEPTION
            'the atomic public web page projection did not return matching card and detail';
    END IF;
END;
$service$;

-- Fixture state changes run as the catalog-test owner. service_role must remain
-- unable to mutate source tables directly and may observe the transition only
-- through its explicitly granted public-web RPCs.
RESET ROLE;

UPDATE public.explore_posts AS post
SET moderated_at = pg_catalog.NOW()
WHERE post.id = '00000000-0000-4000-8000-00000000e831';

SET LOCAL ROLE service_role;

DO $moderated$
DECLARE
    returned_count INTEGER;
BEGIN
    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_count
    FROM public.get_public_web_explore_post_detail(
        '00000000-0000-4000-8000-00000000e831'
    );

    IF returned_count <> 0 THEN
        RAISE EXCEPTION
            'independent public web detail exposed a concurrently moderated post';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_count
    FROM public.get_public_web_explore_post_page(
        '00000000-0000-4000-8000-00000000e831'
    );

    IF returned_count <> 0 THEN
        RAISE EXCEPTION
            'atomic public web page exposed a concurrently moderated post';
    END IF;
END;
$moderated$;

RESET ROLE;

SELECT extensions.pass(
    'public web Explore is server-only, independently canonical, atomic for page reads, and reachable by the server role'
);
SELECT * FROM extensions.finish();
ROLLBACK;

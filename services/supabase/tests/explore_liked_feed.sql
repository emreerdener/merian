\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(14);

SELECT extensions.ok(
    NOT routine.prosecdef AND routine.provolatile = 's',
    'Liked feed uses a stable security-invoker routine'
)
FROM pg_catalog.pg_proc routine
WHERE routine.oid = 'public.get_explore_feed_liked(uuid,integer,timestamptz,uuid,text[],text[],timestamptz)'::regprocedure;

SELECT extensions.ok(
    pg_catalog.has_function_privilege(
        'service_role',
        'public.get_explore_feed_liked(uuid,integer,timestamptz,uuid,text[],text[],timestamptz)',
        'EXECUTE'
    ),
    'Only the trusted Edge service role can invoke the liked feed'
);
SELECT extensions.ok(
    NOT pg_catalog.has_function_privilege(
        'anon',
        'public.get_explore_feed_liked(uuid,integer,timestamptz,uuid,text[],text[],timestamptz)',
        'EXECUTE'
    ) AND NOT pg_catalog.has_function_privilege(
        'authenticated',
        'public.get_explore_feed_liked(uuid,integer,timestamptz,uuid,text[],text[],timestamptz)',
        'EXECUTE'
    ),
    'API roles cannot supply an arbitrary viewer through a direct RPC'
);
SELECT extensions.ok(
    idx.indisvalid AND idx.indisready
        AND pg_catalog.pg_get_indexdef(idx.indexrelid) LIKE '%(user_id, post_id)',
    'Liked membership has a valid viewer-leading index'
)
FROM pg_catalog.pg_index idx
WHERE idx.indexrelid = 'public.idx_explore_post_likes_user_id_post_id'::regclass;

SELECT extensions.is_empty(
    $$ SELECT source_relation FROM pg_catalog.unnest(ARRAY[
        'public.explore_post_likes',
        'public.explore_posts',
        'public.scans',
        'public.users',
        'public.species_dictionary',
        'public.species_reference_images',
        'public.explore_observation_projection',
        'public.taxon_nodes',
        'public.explore_community_requests',
        'public.explore_post_media',
        'public.user_blocks'
    ]) AS sources(source_relation)
    WHERE NOT pg_catalog.has_table_privilege('service_role', source_relation, 'SELECT') $$,
    'No liked-feed source is missing its service-role SELECT grant'
);

-- The static migration contracts require exactly the reviewed SELECT grants.
-- Existing privileges on these shared tables belong to other callers/flows;
-- these repairs preserve them rather than asserting a new global write ban.
SELECT extensions.is_empty(
    $$ SELECT helper FROM pg_catalog.unnest(ARRAY[
        'public.explore_projected_post_cards(uuid)',
        'public.public_species_first_reference_image_url(uuid,text)',
        'public.public_species_reference_image_source_rank(text)',
        'public.explore_feed_species_category(text,text)',
        'public.explore_post_community_common_name(text,text,text,text,jsonb,text)',
        'public.explore_post_community_scientific_name(text,text,text)',
        'public.explore_post_species_common_name(text,jsonb,text)',
        'public.explore_post_media_items(uuid)',
        'public.explore_post_hero_image_url(uuid)'
    ]) AS helpers(helper)
    WHERE NOT pg_catalog.has_function_privilege('service_role', helper, 'EXECUTE') $$,
    'No liked-feed helper is missing service-role EXECUTE'
);

SELECT extensions.ok(
    pg_catalog.bool_and(relation.relrowsecurity),
    'The repaired sources retain row-level security'
)
FROM pg_catalog.pg_class relation
WHERE relation.oid IN (
    'public.explore_post_likes'::regclass,
    'public.explore_observation_projection'::regclass,
    'public.user_blocks'::regclass,
    'public.species_reference_images'::regclass
);

SET LOCAL ROLE anon;
SELECT extensions.throws_ok(
    $$ SELECT * FROM public.get_explore_feed_liked('00000000-0000-4000-8000-000000000001') $$,
    '42501', 'permission denied for function get_explore_feed_liked',
    'Anonymous direct calls are denied'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok(
    $$ SELECT * FROM public.get_explore_feed_liked('00000000-0000-4000-8000-000000000001') $$,
    '42501', 'permission denied for function get_explore_feed_liked',
    'Authenticated direct calls are denied'
);
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.is_empty(
    $$ SELECT * FROM public.get_explore_feed_liked(
        '00000000-0000-4000-8000-000000000001', 20,
        NULL, NULL, ARRAY['birds'], ARRAY['image'], pg_catalog.now() - INTERVAL '7 days'
    ) $$,
    'The service role can execute the filtered projection with a nonzero limit'
);
RESET ROLE;

-- Populate a real card: an empty result does not execute reference/media helpers.
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
    '00000000-0000-4000-8000-00000000e901',
    'authenticated',
    'authenticated',
    'liked-feed-explore@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000e901',
    'liked-feed-explore@naturebook.invalid',
    'pro',
    'liked_feed_e901',
    'Liked Feed Fixture',
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
    '00000000-0000-4000-8000-00000000e911',
    'Likedus feedensis',
    '{"en":"Liked feed species"}'::JSONB,
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
    '00000000-0000-4000-8000-00000000e921',
    '00000000-0000-4000-8000-00000000e901',
    '00000000-0000-4000-8000-00000000e911',
    ARRAY['https://media.example.invalid/liked-feed.webp'],
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
    '00000000-0000-4000-8000-00000000e931',
    '00000000-0000-4000-8000-00000000e901',
    '00000000-0000-4000-8000-00000000e921',
    'Liked feed species',
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
    '00000000-0000-4000-8000-00000000e941',
    '00000000-0000-4000-8000-00000000e931',
    'image',
    'https://media.example.invalid/liked-feed.webp',
    'https://media.example.invalid/liked-feed.webp',
    0
);

INSERT INTO public.species_reference_images (species_id, url, source, license, attribution)
VALUES (
    '00000000-0000-4000-8000-00000000e911',
    'https://media.example.invalid/liked-reference.webp',
    'gbif', 'CC0', 'Catalog fixture'
);

INSERT INTO public.explore_post_likes (post_id, user_id)
VALUES (
    '00000000-0000-4000-8000-00000000e931',
    '00000000-0000-4000-8000-00000000e901'
);

SET LOCAL ROLE service_role;
SELECT extensions.results_eq(
    $$ SELECT post_id, scan_id, reference_thumbnail_url, viewer_has_liked,
              pg_catalog.jsonb_array_length(media_items)
       FROM public.get_explore_feed_liked(
           '00000000-0000-4000-8000-00000000e901', 20,
           NULL, NULL, ARRAY['birds'], ARRAY['image'], pg_catalog.now() - INTERVAL '7 days'
       ) $$,
    $$ VALUES (
        '00000000-0000-4000-8000-00000000e931'::UUID,
        '00000000-0000-4000-8000-00000000e921'::UUID,
        'https://media.example.invalid/liked-reference.webp'::TEXT,
        TRUE, 1
    ) $$,
    'A populated service-role liked feed resolves its reference thumbnail and media'
);
SELECT extensions.is_empty(
    $$ SELECT * FROM public.get_explore_feed_liked('00000000-0000-4000-8000-000000000001') $$,
    'A different viewer cannot inherit the fixture owner likes'
);
SELECT extensions.is_empty(
    $$ SELECT * FROM public.get_explore_feed_liked(
        '00000000-0000-4000-8000-00000000e901', 20, NULL, NULL, ARRAY['mammals']
    ) $$,
    'Advanced filters exclude a liked post from a different category'
);
RESET ROLE;
UPDATE public.explore_posts SET unshared_at = pg_catalog.now()
WHERE id = '00000000-0000-4000-8000-00000000e931';
SET LOCAL ROLE service_role;
SELECT extensions.is_empty(
    $$ SELECT * FROM public.get_explore_feed_liked('00000000-0000-4000-8000-00000000e901') $$,
    'A like cannot expose an unshared post'
);
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;

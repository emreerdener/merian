\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(10);

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

SELECT extensions.ok(
    pg_catalog.bool_and(pg_catalog.has_table_privilege('service_role', source_relation, 'SELECT')),
    'The service invoker can read every direct and canonical projection source'
)
FROM pg_catalog.unnest(ARRAY[
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
]) AS sources(source_relation);

SELECT extensions.ok(
    pg_catalog.bool_and(NOT pg_catalog.has_table_privilege(
        'service_role', source_relation, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
    )),
    'The repaired sources give the service role no write or maintenance privileges'
)
FROM pg_catalog.unnest(ARRAY[
    'public.explore_post_likes',
    'public.explore_observation_projection',
    'public.user_blocks'
]) AS sources(source_relation);

SELECT extensions.ok(
    pg_catalog.bool_and(relation.relrowsecurity),
    'The repaired sources retain row-level security'
)
FROM pg_catalog.pg_class relation
WHERE relation.oid IN (
    'public.explore_post_likes'::regclass,
    'public.explore_observation_projection'::regclass,
    'public.user_blocks'::regclass
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

SELECT * FROM extensions.finish();
ROLLBACK;

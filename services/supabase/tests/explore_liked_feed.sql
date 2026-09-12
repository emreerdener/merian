\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(7);

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
    $$ SELECT * FROM public.get_explore_feed_liked('00000000-0000-4000-8000-000000000001', 0) $$,
    'The service role can execute the complete projection'
);
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(4);

SELECT extensions.ok(
    pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_explore_post_detail(uuid,uuid)',
        'EXECUTE'
    ),
    'service role can read Explore detail through the authenticated Edge boundary'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_explore_post_detail(uuid,uuid)',
        'EXECUTE'
    ),
    'authenticated clients cannot call Explore detail with a chosen viewer identity'
);

SELECT extensions.ok(
    NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_explore_post_detail(uuid,uuid)',
        'EXECUTE'
    ),
    'anonymous clients cannot call Explore detail directly'
);

SELECT extensions.is(
    (
        SELECT routine.prosecdef
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid =
            'public.get_explore_post_detail(uuid,uuid)'::pg_catalog.REGPROCEDURE
    ),
    FALSE,
    'Explore detail remains a security-invoker function'
);

SELECT * FROM extensions.finish();
ROLLBACK;

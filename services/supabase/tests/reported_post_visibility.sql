\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(9);
SELECT extensions.ok(pg_catalog.has_function_privilege('service_role',
    'public.filter_reported_explore_media(uuid,text[])', 'EXECUTE'), 'Service can filter candidate media');
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('authenticated',
    'public.filter_reported_explore_media(uuid,text[])', 'EXECUTE'), 'Authenticated clients cannot choose another viewer');
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('anon',
    'public.filter_reported_explore_media(uuid,text[])', 'EXECUTE'), 'Anonymous clients cannot inspect reports');
SELECT extensions.ok(NOT pg_catalog.has_table_privilege('authenticated',
    'public.explore_post_reports', 'SELECT'), 'Report records remain service-only');
SELECT extensions.ok(pg_catalog.pg_get_functiondef('public.explore_projected_post_cards(uuid)'::regprocedure)
    LIKE '%public.viewer_has_reported_explore_post(viewer_id, ep.id)%', 'Card filtering applies before aggregation');
SELECT extensions.is_empty($$ SELECT p.proname FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
        'get_explore_feed','get_explore_feed_liked','get_explore_author_posts','get_explore_map_posts',
        'get_explore_species_posts','get_explore_post_detail','search_species_discovery')
      AND p.proargnames[1]='self_id' AND (p.prosrc LIKE '%public.public_species_%reference_image%' OR p.prosrc LIKE '%public.public_species_similar_species%')
$$, 'Authenticated readers use viewer-aware reference media');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SELECT extensions.is(public.viewer_has_reported_explore_post(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002'), false,
    'Authenticated reader can evaluate its own reports');
SELECT extensions.throws_ok($$ SELECT public.viewer_has_reported_explore_post(
    '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002') $$,
    '42501', 'Authenticated caller does not match self_id', 'Cannot inspect another viewer reports');
RESET ROLE;
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('anon',
    'public.viewer_has_reported_explore_post(uuid,uuid)', 'EXECUTE'), 'Anonymous callers cannot inspect report preference');
SELECT * FROM extensions.finish();
ROLLBACK;

\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(29);
SELECT extensions.ok((SELECT relrowsecurity FROM pg_catalog.pg_class
    WHERE oid='public.explore_post_reactions'::regclass), 'post reaction RLS is enabled');
SELECT extensions.ok(NOT pg_catalog.has_table_privilege('anon',
    'public.explore_post_reactions','SELECT,INSERT,UPDATE,DELETE'), 'anonymous callers have no reaction table access');
SELECT extensions.ok(NOT pg_catalog.has_table_privilege('authenticated',
    'public.explore_post_reactions','SELECT,INSERT,UPDATE,DELETE'), 'authenticated callers cannot bypass the mutation boundary');
SELECT extensions.ok(NOT pg_catalog.has_table_privilege('service_role',
    'public.explore_post_reactions','INSERT,UPDATE,DELETE'), 'service mutations must also use the guarded RPC');
SELECT extensions.ok(pg_catalog.has_function_privilege('service_role',
    'public.set_explore_reaction(uuid,text,uuid,text,boolean)','EXECUTE'), 'service role can execute the reaction mutation');
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('authenticated',
    'public.set_explore_reaction(uuid,text,uuid,text,boolean)','EXECUTE'), 'authenticated callers cannot impersonate a reaction actor');
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('anon',
    'public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)','EXECUTE'),
    'anonymous callers cannot impersonate an activity recipient');
SELECT extensions.is((SELECT pg_catalog.pg_get_expr(d.adbin,d.adrelid)
    FROM pg_catalog.pg_attrdef d JOIN pg_catalog.pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
    WHERE a.attrelid='public.user_push_devices'::regclass AND a.attname='supports_post_reactions'),
    'false', 'devices default to legacy notification compatibility');

-- Both capability paths remain service-only, including inherited PUBLIC grants.
SELECT extensions.ok((SELECT bool_and(NOT pg_catalog.has_function_privilege('anon', signature, 'EXECUTE'))
    FROM (VALUES ('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_unread_explore_notification_count(uuid)'),
    ('public.get_unread_explore_notification_count_with_reactions(uuid)'),
    ('public.mark_explore_notifications_read(uuid)'),
    ('public.mark_explore_notifications_read_with_reactions(uuid)')) rpc(signature)),
    'anon notification RPC privileges match the boundary');
SELECT extensions.ok((SELECT bool_and(NOT pg_catalog.has_function_privilege('authenticated', signature, 'EXECUTE'))
    FROM (VALUES ('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_unread_explore_notification_count(uuid)'),
    ('public.get_unread_explore_notification_count_with_reactions(uuid)'),
    ('public.mark_explore_notifications_read(uuid)'),
    ('public.mark_explore_notifications_read_with_reactions(uuid)')) rpc(signature)),
    'authenticated notification RPC privileges match the boundary');
SELECT extensions.ok((SELECT bool_and(pg_catalog.has_function_privilege('service_role', signature, 'EXECUTE'))
    FROM (VALUES ('public.get_explore_notifications(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_explore_notifications_with_reactions(uuid,integer,timestamp with time zone,uuid)'),
    ('public.get_unread_explore_notification_count(uuid)'),
    ('public.get_unread_explore_notification_count_with_reactions(uuid)'),
    ('public.mark_explore_notifications_read(uuid)'),
    ('public.mark_explore_notifications_read_with_reactions(uuid)')) rpc(signature)),
    'service_role notification RPC privileges match the boundary');

SET LOCAL ROLE anon;
SELECT extensions.throws_ok($probe$SELECT public.get_explore_notifications('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.get_explore_notifications');
SELECT extensions.throws_ok($probe$SELECT public.get_explore_notifications_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.get_explore_notifications_with_reactions');
SELECT extensions.throws_ok($probe$SELECT public.get_unread_explore_notification_count('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.get_unread_explore_notification_count');
SELECT extensions.throws_ok($probe$SELECT public.get_unread_explore_notification_count_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.get_unread_explore_notification_count_with_reactions');
SELECT extensions.throws_ok($probe$SELECT public.mark_explore_notifications_read('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.mark_explore_notifications_read');
SELECT extensions.throws_ok($probe$SELECT public.mark_explore_notifications_read_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'anon cannot call public.mark_explore_notifications_read_with_reactions');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($probe$SELECT public.get_explore_notifications('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.get_explore_notifications');
SELECT extensions.throws_ok($probe$SELECT public.get_explore_notifications_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.get_explore_notifications_with_reactions');
SELECT extensions.throws_ok($probe$SELECT public.get_unread_explore_notification_count('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.get_unread_explore_notification_count');
SELECT extensions.throws_ok($probe$SELECT public.get_unread_explore_notification_count_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.get_unread_explore_notification_count_with_reactions');
SELECT extensions.throws_ok($probe$SELECT public.mark_explore_notifications_read('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.mark_explore_notifications_read');
SELECT extensions.throws_ok($probe$SELECT public.mark_explore_notifications_read_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, '42501', NULL, 'authenticated cannot call public.mark_explore_notifications_read_with_reactions');
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT extensions.lives_ok($probe$SELECT public.get_explore_notifications('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.get_explore_notifications');
SELECT extensions.lives_ok($probe$SELECT public.get_explore_notifications_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.get_explore_notifications_with_reactions');
SELECT extensions.lives_ok($probe$SELECT public.get_unread_explore_notification_count('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.get_unread_explore_notification_count');
SELECT extensions.lives_ok($probe$SELECT public.get_unread_explore_notification_count_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.get_unread_explore_notification_count_with_reactions');
SELECT extensions.lives_ok($probe$SELECT public.mark_explore_notifications_read('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.mark_explore_notifications_read');
SELECT extensions.lives_ok($probe$SELECT public.mark_explore_notifications_read_with_reactions('00000000-0000-4000-8000-000000000099'::uuid)$probe$, 'service_role can call public.mark_explore_notifications_read_with_reactions');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

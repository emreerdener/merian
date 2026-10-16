\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT prosecdef AND provolatile='s' AND proconfig @> ARRAY['search_path=""'],
    'byte encoder is stable invoker with fixed search path') FROM pg_proc
    WHERE oid='internal.observation_video_source_fingerprint_bytes(jsonb)'::regprocedure;
SELECT extensions.ok(NOT prosecdef AND provolatile='s', 'hash encoder is stable invoker') FROM pg_proc
    WHERE oid='internal.observation_video_source_fingerprint(jsonb)'::regprocedure;
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),role_name || ' cannot call pure private encoder')
    FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
    CROSS JOIN unnest(ARRAY['internal.observation_video_source_fingerprint_bytes(jsonb)',
        'internal.observation_video_source_fingerprint(jsonb)',
        'internal.observation_video_fingerprint_integer(jsonb,bigint,bigint)',
        'internal.observation_video_fingerprint_artifact(jsonb,text[],bigint,bigint)']) signature;
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint_bytes(NULL)$$,
    '22023','invalid_analysis_history','SQL NULL rejected');
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint_bytes('{}')$$,
    '22023','invalid_analysis_history','missing fields rejected');
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint_bytes('[]')$$,
    '22023','invalid_analysis_history','array rejected');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint('{}')$$,'42501',NULL,'anon actual access denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint('{}')$$,'42501',NULL,'authenticated actual access denied');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.observation_video_source_fingerprint('{}')$$,'42501',NULL,'service actual access denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;

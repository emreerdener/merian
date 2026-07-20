\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, email_confirmed_at, last_sign_in_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
SELECT
  '00000000-0000-0000-0000-000000000000'::UUID,
  seed.user_id,
  'authenticated',
  'authenticated',
  seed.email,
  NOW(),
  NOW(),
  jsonb_build_object('provider', 'google', 'providers', jsonb_build_array('google')),
  '{}'::JSONB,
  NOW(),
  NOW(),
  seed.is_anonymous
FROM (VALUES
  ('00000000-0000-0000-0000-000000000101'::UUID, 'admin-owner-test@naturebook.invalid', FALSE),
  ('00000000-0000-0000-0000-000000000102'::UUID, 'admin-moderator-test@naturebook.invalid', FALSE),
  ('00000000-0000-0000-0000-000000000103'::UUID, 'admin-analyst-test@naturebook.invalid', FALSE),
  ('00000000-0000-0000-0000-000000000104'::UUID, 'admin-nonmember-test@naturebook.invalid', FALSE),
  ('00000000-0000-0000-0000-000000000105'::UUID, 'admin-disabled-test@naturebook.invalid', FALSE),
  ('00000000-0000-0000-0000-000000000106'::UUID, 'admin-ghost-test@naturebook.invalid', TRUE)
) AS seed(user_id, email, is_anonymous);

INSERT INTO auth.identities (
  provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
SELECT seed.user_id::TEXT, seed.user_id,
       jsonb_build_object('sub', seed.user_id::TEXT, 'email', seed.email),
       'google', NOW(), NOW(), NOW()
FROM (VALUES
  ('00000000-0000-0000-0000-000000000101'::UUID, 'admin-owner-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000102'::UUID, 'admin-moderator-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000103'::UUID, 'admin-analyst-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000104'::UUID, 'admin-nonmember-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000105'::UUID, 'admin-disabled-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000106'::UUID, 'admin-ghost-test@naturebook.invalid')
) AS seed(user_id, email);

INSERT INTO auth.sessions (id, user_id, created_at, updated_at, refreshed_at, aal, not_after)
SELECT seed.session_id, seed.user_id, NOW(), NOW(), NOW(), 'aal2'::auth.aal_level, NOW() + INTERVAL '1 day'
FROM (VALUES
  ('00000000-0000-0000-0000-000000000201'::UUID, '00000000-0000-0000-0000-000000000101'::UUID),
  ('00000000-0000-0000-0000-000000000202'::UUID, '00000000-0000-0000-0000-000000000102'::UUID),
  ('00000000-0000-0000-0000-000000000203'::UUID, '00000000-0000-0000-0000-000000000103'::UUID),
  ('00000000-0000-0000-0000-000000000204'::UUID, '00000000-0000-0000-0000-000000000104'::UUID),
  ('00000000-0000-0000-0000-000000000205'::UUID, '00000000-0000-0000-0000-000000000105'::UUID),
  ('00000000-0000-0000-0000-000000000206'::UUID, '00000000-0000-0000-0000-000000000106'::UUID)
) AS seed(session_id, user_id);

INSERT INTO internal.admin_memberships (user_id, role, is_active, created_by)
VALUES
  ('00000000-0000-0000-0000-000000000101', 'owner', TRUE, '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000102', 'moderator', TRUE, '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000103', 'analyst', TRUE, '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000105', 'moderator', FALSE, '00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000106', 'moderator', TRUE, '00000000-0000-0000-0000-000000000101');

DO $$
BEGIN
  IF has_schema_privilege('authenticated', 'internal', 'USAGE') THEN
    RAISE EXCEPTION 'authenticated unexpectedly has internal schema usage';
  END IF;
  IF has_table_privilege('authenticated', 'public.ai_usage_events', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated unexpectedly has AI ledger table access';
  END IF;
  IF has_function_privilege('anon', 'public.admin_get_overview(integer,text,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon unexpectedly has admin overview execute access';
  END IF;
END;
$$;

SET LOCAL ROLE authenticated;

-- Owner AAL1 must fail before an internal session is created.
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000101', 'role', 'authenticated',
  'aal', 'aal1', 'session_id', '00000000-0000-0000-0000-000000000201'
)::TEXT, TRUE);
DO $$
BEGIN
  BEGIN
    PERFORM public.admin_begin_session();
    RAISE EXCEPTION 'expected owner AAL1 denial';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END;
$$;

-- A registered non-member, disabled member, and anonymous/ghost member fail.
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000104', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000204')::TEXT, TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_begin_session(); RAISE EXCEPTION 'expected non-member denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000105', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000205')::TEXT, TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_begin_session(); RAISE EXCEPTION 'expected disabled-member denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000106', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000206')::TEXT, TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_begin_session(); RAISE EXCEPTION 'expected ghost-member denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;

-- Establish each active AAL2 role and exercise its permitted surface.
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000101', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000201')::TEXT, TRUE);
SELECT public.admin_begin_session();
SELECT public.admin_list_members();
DO $$ BEGIN BEGIN PERFORM public.admin_upsert_member('admin-owner-test@naturebook.invalid', 'moderator', TRUE); RAISE EXCEPTION 'expected final-owner protection'; EXCEPTION WHEN SQLSTATE '23514' THEN NULL; END; END $$;

SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000102', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000202')::TEXT, TRUE);
SELECT public.admin_begin_session();
SELECT public.admin_list_review_cases(p_limit => 1);

SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000103', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000203')::TEXT, TRUE);
SELECT public.admin_begin_session();
SELECT public.admin_get_overview(1, 'UTC', TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_list_review_cases(p_limit => 1); RAISE EXCEPTION 'expected analyst raw-data denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;

RESET ROLE;
UPDATE internal.admin_sessions SET revoked_at = NOW() WHERE session_id = '00000000-0000-0000-0000-000000000202';
UPDATE internal.admin_sessions SET expires_at = NOW() - INTERVAL '1 second' WHERE session_id = '00000000-0000-0000-0000-000000000203';
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000102', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000202')::TEXT, TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_list_review_cases(p_limit => 1); RAISE EXCEPTION 'expected revoked-session denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-0000-0000-000000000103', 'role', 'authenticated', 'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000203')::TEXT, TRUE);
DO $$ BEGIN BEGIN PERFORM public.admin_get_overview(1, 'UTC', TRUE); RAISE EXCEPTION 'expected expired-session denial'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END $$;

SELECT extensions.pass('admin MFA, RBAC, grants, sessions, and final-owner contracts hold');
SELECT * FROM extensions.finish();
ROLLBACK;

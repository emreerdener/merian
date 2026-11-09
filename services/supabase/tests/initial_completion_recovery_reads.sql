-- Public service-only façades delegate to the existing locked original readers.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

SELECT extensions.ok(has_function_privilege('service_role', signature, 'EXECUTE'),
 'service can call exact wrapper ' || signature)
FROM unnest(ARRAY[
 'public.discover_initial_completion_v1(uuid,uuid,text)',
 'public.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)']) signature;
SELECT extensions.ok(NOT has_function_privilege(role_name, signature, 'EXECUTE'),
 role_name || ' cannot call ' || signature)
FROM unnest(ARRAY['anon','authenticated']) role_name
CROSS JOIN unnest(ARRAY[
 'public.discover_initial_completion_v1(uuid,uuid,text)',
 'public.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)']) signature;
SELECT extensions.ok(NOT has_function_privilege(role_name, signature, 'EXECUTE'),
 'internal owner stays private to ' || role_name)
FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
CROSS JOIN unnest(ARRAY[
 'internal.discover_initial_completion_v1(uuid,uuid,text)',
 'internal.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)']) signature;
SELECT extensions.ok(p.prosecdef AND pg_catalog.pg_get_userbyid(p.proowner)='postgres'
 AND p.proconfig @> ARRAY['search_path=""','statement_timeout=5s'],
 'exact wrapper retains definer owner and closed configuration ' || p.oid::regprocedure::text)
FROM pg_catalog.pg_proc p WHERE p.oid IN (
 'public.discover_initial_completion_v1(uuid,uuid,text)'::regprocedure,
 'public.read_initial_cpm_saved_admission_v1(uuid,uuid,text,text,text,text,uuid,text)'::regprocedure);

-- Actual roles: spoofing a service claim cannot bypass EXECUTE permissions.
SELECT set_config('request.jwt.claim.role','service_role',TRUE);
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.discover_initial_completion_v1(NULL,NULL,NULL)$$,
 '42501',NULL,'actual anon cannot invoke completion wrapper');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_saved_admission_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,
 '42501',NULL,'actual anon cannot invoke saved admission wrapper');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.discover_initial_completion_v1(NULL,NULL,NULL)$$,
 '42501',NULL,'actual authenticated cannot invoke completion wrapper');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_saved_admission_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,
 '42501',NULL,'actual authenticated cannot invoke saved admission wrapper');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.discover_initial_completion_v1(NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','service delegates original completion validation');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_saved_admission_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','service delegates saved admission validation');
RESET ROLE;
SELECT set_config('request.jwt.claim.role','authenticated',TRUE);
SELECT extensions.throws_ok($$SELECT public.discover_initial_completion_v1(NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','direct migration owner remains permitted by the established guard');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_saved_admission_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','direct migration owner still delegates saved admission validation');

-- Opaque service keys use the protected role without a JWT role claim.
SELECT set_config('request.jwt.claim.role','',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.discover_initial_completion_v1(NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','opaque service role reaches completion validation');
SELECT extensions.throws_ok($$SELECT public.read_initial_cpm_saved_admission_v1(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,
 '22023','initial_completion_admission_invalid','opaque service role reaches saved admission validation');
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(17);
SELECT extensions.ok(relrowsecurity,'scheduling leases have RLS') FROM pg_catalog.pg_class
 WHERE oid='internal.private_capture_finalization_leases'::regclass;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.private_capture_finalization_leases','SELECT,INSERT,UPDATE,DELETE'),
 role_name||' cannot read or mutate scheduling leases') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,'public.claim_private_capture_finalizations(integer)','EXECUTE'),
 role_name||' cannot claim private finalizations') FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT extensions.ok(has_function_privilege('service_role','public.claim_private_capture_finalizations(integer)','EXECUTE'),
 'only the service worker can claim accepted results');
SELECT extensions.ok(prosecdef AND proconfig @> ARRAY['search_path=""'],'claim has an empty privileged search path')
 FROM pg_catalog.pg_proc WHERE oid='public.claim_private_capture_finalizations(integer)'::regprocedure;
SELECT extensions.ok(EXISTS(SELECT 1 FROM pg_catalog.pg_constraint
 WHERE conrelid='internal.private_capture_finalization_leases'::regclass
 AND confrelid='internal.ordinary_initial_evidence'::regclass AND confdeltype='c'),
 'evidence erasure also removes scheduling leases');
SELECT extensions.is(ordinary_initial_evidence_enabled,FALSE,'preparation does not activate capture')
 FROM internal.observation_history_rollout;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT extensions.throws_ok('SELECT public.claim_private_capture_finalizations(6)','22023','invalid_analysis_history',
 'claim batch is bounded to five');
SELECT extensions.ok(NOT has_function_privilege(role_name,'internal.guard_scan_account_retirement()','EXECUTE'),
 role_name||' cannot invoke the scan insertion guard directly') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.is(tgtype::INTEGER,7,'retirement is fenced on every owned scan INSERT')
 FROM pg_catalog.pg_trigger WHERE tgname='a00000_guard_scan_account_retirement' AND tgrelid='public.scans'::regclass;
SELECT extensions.ok(prosecdef AND proconfig @> ARRAY['search_path=""'],'scan insertion guard has an empty privileged search path')
 FROM pg_catalog.pg_proc WHERE oid='internal.guard_scan_account_retirement()'::regprocedure;
SELECT extensions.ok(position('merian-capture-account-retirement:' IN pg_get_functiondef('internal.private_capture_finalization_ready(uuid,uuid)'::regprocedure))>0,
 'the actual completion transaction shares account retirement serialization');
SELECT * FROM extensions.finish();
ROLLBACK;

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(relrowsecurity,'primary permits have RLS') FROM pg_catalog.pg_class
 WHERE oid='internal.private_capture_primary_dispatch'::regclass;
SELECT extensions.ok(NOT has_table_privilege(role_name,'internal.private_capture_primary_dispatch','SELECT,INSERT,UPDATE,DELETE'),
 role_name||' cannot access primary permits') FROM unnest(ARRAY['anon','authenticated','service_role']) role_name;
SELECT extensions.ok(NOT has_function_privilege(role_name,routine,'EXECUTE'),role_name||' cannot invoke '||routine)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name CROSS JOIN unnest(ARRAY[
 'internal.lock_private_capture_dispatch(uuid,uuid)',
 'internal.record_private_capture_dispatch(jsonb,internal.identification_invocations,internal.identification_provider_attempts)',
 'internal.guard_private_capture_dispatch()',
 'internal.guard_private_capture_quota_state()',
 'internal.guard_private_capture_invocation()']) routine;
SELECT extensions.is(count(*)::INTEGER,1,'receipt has exactly one foreign key') FROM pg_catalog.pg_constraint
 WHERE conrelid='internal.private_capture_primary_dispatch'::regclass AND contype='f';
SELECT extensions.ok(confrelid='internal.ordinary_initial_evidence'::regclass AND confdeltype='c',
 'only evidence erasure cascades the receipt') FROM pg_catalog.pg_constraint
 WHERE conrelid='internal.private_capture_primary_dispatch'::regclass AND contype='f';
SELECT extensions.is(tgtype::INTEGER,7,'all invocation inserts require private authority') FROM pg_catalog.pg_trigger
 WHERE tgrelid='internal.identification_invocations'::regclass AND tgname='guard_private_capture_invocation';
SELECT extensions.is(tgtype::INTEGER,23,'quota inserts and all updates are guarded') FROM pg_catalog.pg_trigger
 WHERE tgrelid='internal.ai_quota_reservations'::regclass AND tgname='guard_private_capture_quota_state';
SELECT extensions.ok(position('internal.record_private_capture_dispatch' IN definition)<position('PERFORM internal.finalize_ai_quota_reservation_core' IN definition),
 'permanent receipt precedes quota commit in the same owner')
 FROM (SELECT pg_get_functiondef('public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)'::regprocedure) definition) s;
SELECT extensions.ok(position('internal.lock_private_capture_dispatch' IN definition)<position('FOR KEY SHARE' IN definition),
 'retirement and capture locks precede generic user/reservation locks')
 FROM (SELECT pg_get_functiondef('public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)'::regprocedure) definition) s;
SELECT extensions.is(ordinary_initial_evidence_enabled,FALSE,'candidate never activates private capture') FROM internal.observation_history_rollout;
SELECT extensions.ok(position('analysis_history_current_snapshot_required' IN pg_get_functiondef(signature::regprocedure))
 <position(first_read IN pg_get_functiondef(signature::regprocedure)), 'snapshot guard precedes classification: '||signature)
 FROM (VALUES
 ('internal.lock_private_capture_dispatch(uuid,uuid)','SELECT q.original_analysis_id'),
 ('internal.guard_private_capture_quota_state()','IF NEW.state'),
 ('internal.guard_private_capture_invocation()','SELECT * INTO permit')) AS checks(signature,first_read);
SELECT extensions.is(provolatile::TEXT,'v','dispatch classifier remains volatile: '||oid::regprocedure::TEXT)
 FROM pg_proc WHERE oid IN ('internal.lock_private_capture_dispatch(uuid,uuid)'::regprocedure,
 'internal.guard_private_capture_quota_state()'::regprocedure,'internal.guard_private_capture_invocation()'::regprocedure);
SELECT extensions.ok(position(fragment IN definition)>0,'unbound refund requires '||fragment)
 FROM (SELECT pg_get_functiondef('internal.guard_private_capture_quota_state()'::regprocedure) definition) f
 CROSS JOIN unnest(ARRAY[
 'TG_OP<>''UPDATE''', 'OLD.state=''reserved'' AND NEW.state=''refunded''',
 'OLD.original_analysis_id IS NULL AND NEW.original_analysis_id IS NULL',
 'NEW.refund_count=OLD.refund_count+1',
 'to_jsonb(NEW)-ARRAY[''state'',''refunded_at'',''refund_count'',''updated_at'']',
 'IS NOT DISTINCT FROM (to_jsonb(OLD)',
 'private_capture_dispatch_immutable', 'private_capture_dispatch_consumed'
 ]) fragment;
SELECT * FROM extensions.finish();
ROLLBACK;

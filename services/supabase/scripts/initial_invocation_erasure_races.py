"""Bounded original-accounting/scan-erasure schedules on one synthetic invocation."""
import time
from initial_atomic_admission_sessions import Session

SCAN = '00000000-0000-4000-8000-000000000401'
ERASE = """INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at)
SELECT scan_id,user_id,clock_timestamp() FROM internal.identification_invocations
WHERE is_initial_analysis;"""
RETIRED = """DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation' AND outcome='unknown')<>1
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 THEN RAISE EXCEPTION USING ERRCODE='ZX701'; END IF;
END $$;"""


def wait_for_blocker(observer, blocked, blocker):
    end = time.monotonic() + 5
    while time.monotonic() < end:
        if observer.run('observe_exact_blocker',
                        f'SELECT {blocker.pid}=ANY(pg_blocking_pids({blocked.pid}));') == ['t']:
            return
        time.sleep(0.05)
    raise RuntimeError('expected accounting/erasure blocker absent')


def run(qualification):
    sessions = []
    passed = False
    order_one_blocked = False
    order_two_blocked = False
    try:
        for name in ('accounting', 'erasure', 'observer'):
            sessions.append(Session(qualification, 'invocation_' + name))
        accounting, erasure, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct accounting/erasure/observer backends required')
        # Actual five-minute accounting owns the invocation first. Erasure
        # obtains its owner lock and must wait for that exact invocation row.
        accounting.run('reconcile_first', """BEGIN;DO $$ BEGIN
 IF internal.reconcile_identification_usage(1000)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX702'; END IF;
END $$;""")
        erasure.start('erasure_waits_for_accounting', 'BEGIN;' + ERASE)
        wait_for_blocker(observer, erasure, accounting)
        order_one_blocked = True
        # The dangerous reverse acquisition is a direct retirement UPDATE after
        # accounting already owns the invocation. NOWAIT must reject it rather
        # than wait back on the eraser's owner row and form a cycle.
        accounting.run('direct_retirement_backstop_rejects_owner_inversion', """
DO $$ DECLARE rejected BOOLEAN:=FALSE; BEGIN
 BEGIN
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,
   lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE is_initial_analysis;
 EXCEPTION WHEN lock_not_available THEN rejected:=TRUE; END;
 IF NOT rejected THEN RAISE EXCEPTION USING ERRCODE='ZX703'; END IF;
END $$;
ROLLBACK;""")
        erasure.finish()
        erasure.run('erasure_after_accounting_rollback_is_atomic', RETIRED + 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
        observer.run('both_rollbacks_preserve_original_authority', """DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis AND event_id IS NULL AND scan_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>1
 OR EXISTS(SELECT 1 FROM public.ai_usage_events WHERE source_type='identification_invocation')
 OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones)
 THEN RAISE EXCEPTION USING ERRCODE='ZX704'; END IF;
END $$;""")
        # Reverse order: erasure reconciles and retires while retaining its row
        # lock; an original late accounting report waits, then reuses that event.
        erasure.run('erase_first', 'BEGIN;' + ERASE + RETIRED)
        accounting.start('original_report_waits_for_erasure', """BEGIN;
SELECT internal.complete_identification_usage(id,'draft','{}'::JSONB)
FROM internal.identification_invocations WHERE is_initial_analysis;""")
        wait_for_blocker(observer, accounting, erasure)
        order_two_blocked = True
        erasure.run('commit_retirement', 'SET LOCAL ROLE service_role;COMMIT;')
        report = accounting.finish()
        expected = observer.run('original_event_identity',
                                'SELECT event_id FROM internal.identification_invocations WHERE is_initial_analysis;')
        if report != expected or len(expected) != 1:
            raise RuntimeError('late report did not reuse the original accounting event')
        accounting.run('retired_state_under_original_report_lock', RETIRED)
        accounting.run('prune_retired_under_original_report_lock', """DO $$ DECLARE reconciled INTEGER; BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1 THEN
  RAISE EXCEPTION USING ERRCODE='ZX707'; END IF;
 reconciled:=internal.reconcile_identification_usage(1000);
 IF reconciled<>0
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation' AND outcome='unknown')<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX705'; END IF;
END $$;""")
        accounting.run('commit_late_report_and_prune', 'COMMIT;')
        observer.run('fresh_session_retains_one_event_after_pruning', """DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation' AND outcome='unknown')<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX706'; END IF;
END $$;""")
        passed = True
    finally:
        errors = []
        # Release whichever transaction is the blocker first, even on failure.
        ordered = sorted(sessions, key=lambda s: s.pending is not None)
        for session in ordered:
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
        qualification.record['checks'].append({
            'case': 'both_order_accounting_scan_erasure', 'passed': passed and not errors,
            'accounting_first_blocking_observed': order_one_blocked,
            'erasure_first_blocking_observed': order_two_blocked,
            'close_errors': errors,
            'scope': 'Reconciler-first rollback and erasure-first commit/late-report replay; no public account or C1 races',
        })
        qualification.save()
        if errors:
            raise RuntimeError('owned race-session cleanup failed')


C1_CANCEL = """SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$ DECLARE owner_id UUID; BEGIN
 SELECT user_id INTO STRICT owner_id FROM internal.identification_invocations WHERE is_initial_analysis;
 SET LOCAL ROLE service_role;
 IF public.cancel_initial_analysis(owner_id,'00000000-0000-4000-8000-000000000401')->>'dispatch'
  IS DISTINCT FROM 'dispatch_outcome_unknown' THEN RAISE EXCEPTION USING ERRCODE='ZX711'; END IF;
 RESET ROLE;
END $$;"""
C1_FINAL = """DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones)
 OR (SELECT count(*) FROM internal.initial_analysis_cancellations WHERE dispatch='dispatch_outcome_unknown')<>1
 OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation' AND outcome='unknown'
  AND scan_id='00000000-0000-4000-8000-000000000401' AND source_id=(SELECT id FROM internal.identification_invocations WHERE is_initial_analysis))<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX712'; END IF;
 PERFORM internal.assert_initial_cancellation_transients_absent('00000000-0000-4000-8000-000000000401');
END $$;"""
# Synthetic rows remain inside the owned SQL sessions, never in artifacts.
C1_FUNDING = """SELECT jsonb_build_object(
 'quota',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM internal.ai_quota_reservations r),
 'attempt',(SELECT jsonb_agg(to_jsonb(r) ORDER BY reservation_id,attempt_count) FROM internal.identification_provider_attempts r),
 'links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::TEXT) FROM internal.ai_quota_reservation_counters r),
 'counters',(SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::TEXT) FROM internal.ai_quota_counters r),
 'hold',(SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::TEXT) FROM internal.complimentary_scan_usage r),
 'owner',(SELECT jsonb_agg(jsonb_build_object('id',id,'entitlement_version',entitlement_version,
 'complimentary_entitlement_epoch',complimentary_entitlement_epoch) ORDER BY id) FROM public.users)) image"""



# Expected pre-call image permits only retirement bits on this original cohort.
# Actual post-call image must retain those bits, capacity, and closure evidence.
C1_CPM_RETENTION = """SELECT jsonb_build_object(
 'capacity',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.scan_id) FROM internal.initial_cpm_photo_capacity_reservations c WHERE c.scan_id='00000000-0000-4000-8000-000000000401'),
 'attempts',(SELECT jsonb_agg(CASE WHEN __RETIRED__ THEN to_jsonb(a)||'{"retired":true}'::JSONB ELSE to_jsonb(a) END ORDER BY a.object_id) FROM internal.initial_cpm_photo_write_attempts a WHERE a.scan_id='00000000-0000-4000-8000-000000000401'),
 'closures',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.attempt_id) FROM internal.initial_cpm_photo_write_closures c JOIN internal.initial_cpm_photo_write_attempts a USING(attempt_id) WHERE a.scan_id='00000000-0000-4000-8000-000000000401')) image"""
C1_CPM_CHECK = """DO $$ BEGIN
 IF (""" + C1_CPM_RETENTION.replace('__RETIRED__', 'FALSE') + """) IS DISTINCT FROM (SELECT image FROM c1_cpm_expected)
 OR EXISTS(SELECT 1 FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='00000000-0000-4000-8000-000000000401')
 THEN RAISE EXCEPTION USING ERRCODE='ZX722'; END IF;
END $$;"""


def run_c1(qualification):
    """Actual public C1 versus original row-first accounting in both orders."""
    sessions = []
    passed = False
    first_blocked = False
    second_blocked = False
    try:
        for name in ('accounting', 'cancellation', 'observer'):
            sessions.append(Session(qualification, 'c1_' + name))
        accounting, cancellation, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct C1/accounting/observer backends required')
        observer.run('capture_expected_cpm_retention', 'CREATE TEMP TABLE c1_cpm_expected AS ' + C1_CPM_RETENTION.replace('__RETIRED__', 'TRUE') + ';')
        observer.run('capture_original_funding', 'CREATE TEMP TABLE c1_funding_before AS ' + C1_FUNDING + ';')
        accounting.run('c1_reconcile_first', """BEGIN;DO $$ BEGIN
 IF internal.reconcile_identification_usage(1000)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX713'; END IF;
END $$;""")
        cancellation.start('public_c1_waits_for_original_accounting', 'BEGIN;' + C1_CANCEL)
        wait_for_blocker(observer, cancellation, accounting)
        first_blocked = True
        accounting.run('c1_reverse_owner_acquisition_rejected', """DO $$ DECLARE rejected BOOLEAN:=FALSE; BEGIN
 BEGIN
  UPDATE internal.identification_invocations SET user_id=NULL,scan_id=NULL,reservation_id=NULL,
   lease_sha256=NULL,initial_admission_receipt_id=NULL WHERE is_initial_analysis;
 EXCEPTION WHEN lock_not_available THEN rejected:=TRUE; END;
 IF NOT rejected THEN RAISE EXCEPTION USING ERRCODE='ZX714'; END IF;
END $$;ROLLBACK;""")
        cancellation.finish()
        cancellation.run('public_c1_after_accounting_rollback', C1_FINAL + 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
        observer.run('c1_first_order_rollback_preserves_identity', """DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis AND event_id IS NULL AND scan_id IS NOT NULL)<>1
 OR (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>1
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations)
 OR EXISTS(SELECT 1 FROM public.ai_usage_events WHERE source_type='identification_invocation')
 THEN RAISE EXCEPTION USING ERRCODE='ZX715'; END IF;
END $$;""")
        cancellation.run('public_c1_first', 'BEGIN;' + C1_CANCEL + C1_FINAL)
        accounting.start('original_late_report_waits_for_c1', """BEGIN;
SELECT internal.complete_identification_usage(id,'draft','{}'::JSONB)
FROM internal.identification_invocations WHERE is_initial_analysis;""")
        wait_for_blocker(observer, accounting, cancellation)
        second_blocked = True
        cancellation.run('commit_public_c1', 'SET LOCAL ROLE service_role;COMMIT;')
        report = accounting.finish()
        expected = observer.run('c1_original_event_identity',
                                'SELECT event_id FROM internal.identification_invocations WHERE is_initial_analysis;')
        if report != expected or len(expected) != 1:
            raise RuntimeError('late report did not reuse the C1 original accounting event')
        accounting.run('late_report_preserves_committed_c1', C1_FINAL + 'COMMIT;')
        observer.run('fresh_session_c1_funding_and_receipt', C1_FINAL + """DO $$ BEGIN
 IF (""" + C1_FUNDING + """) IS DISTINCT FROM (SELECT image FROM c1_funding_before) THEN
  RAISE EXCEPTION USING ERRCODE='ZX716'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 IF public.cancel_initial_analysis((SELECT owner_id FROM internal.initial_analysis_cancellations),
  '00000000-0000-4000-8000-000000000401')->>'dispatch' IS DISTINCT FROM 'dispatch_outcome_unknown' THEN
  RAISE EXCEPTION USING ERRCODE='ZX717'; END IF;
END $$;""")
        observer.run('committed_c1_preserves_original_cpm_liability', C1_CPM_CHECK)
        # This fixture's invocation is older than the production thirty-day
        # retention window. Use the actual reconciler after C1 commits; the
        # permanent scan tombstone branch is deliberately absent here.
        observer.run('capture_c1_pruning_survivors', """
CREATE TEMP TABLE c1_prune_before AS SELECT
 (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE source_type='identification_invocation') event,
 (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c) cancellation,
 (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id='00000000-0000-4000-8000-000000000401') lifecycle,
 (SELECT id FROM internal.identification_invocations WHERE is_initial_analysis) invocation;
""")
        accounting.run('prune_committed_c1_retired_invocation', """BEGIN;DO $$
DECLARE reconciled INTEGER;
BEGIN
 IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones)
 OR (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX718'; END IF;
 -- Separate statements give the post-prune read a new command snapshot;
 -- volatile function/subquery evaluation within one expression is unordered.
 reconciled:=internal.reconcile_identification_usage(1000);
 IF reconciled<>0 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 THEN RAISE EXCEPTION USING ERRCODE='ZX718'; END IF;
END $$;SET CONSTRAINTS ALL IMMEDIATE;COMMIT;""")
        observer.run('c1_pruning_preserves_event_receipt_funding_and_replay', """DO $$
DECLARE rejected BOOLEAN:=FALSE; original c1_prune_before;
BEGIN
 SELECT * INTO STRICT original FROM c1_prune_before;
 IF EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones)
 OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation')<>1
 OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE source_type='identification_invocation') IS DISTINCT FROM original.event
 OR (SELECT to_jsonb(c) FROM internal.initial_analysis_cancellations c) IS DISTINCT FROM original.cancellation
 OR (SELECT to_jsonb(f) FROM internal.initial_analysis_lifecycle_fences f WHERE scan_id='00000000-0000-4000-8000-000000000401') IS DISTINCT FROM original.lifecycle
 OR (""" + C1_FUNDING + """) IS DISTINCT FROM (SELECT image FROM c1_funding_before)
 THEN RAISE EXCEPTION USING ERRCODE='ZX719'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 IF public.cancel_initial_analysis((original.cancellation->>'owner_id')::UUID,
  '00000000-0000-4000-8000-000000000401') IS DISTINCT FROM
  '{"version":1,"outcome":"cancelled","dispatch":"dispatch_outcome_unknown"}'::JSONB
 THEN RAISE EXCEPTION USING ERRCODE='ZX720'; END IF;
 BEGIN
  PERFORM internal.complete_identification_usage(original.invocation,'draft','{}');
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'identification_invocation_not_found' THEN RAISE; END IF;
  rejected:=TRUE;
 END;
 IF NOT rejected OR (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE source_type='identification_invocation') IS DISTINCT FROM original.event
 THEN RAISE EXCEPTION USING ERRCODE='ZX721'; END IF;
 PERFORM internal.assert_initial_cancellation_transients_absent('00000000-0000-4000-8000-000000000401');
END $$;
""")
        observer.run('pruned_c1_preserves_original_cpm_liability', C1_CPM_CHECK)
        passed = True
    finally:
        errors = []
        for session in sorted(sessions, key=lambda s: s.pending is not None):
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
        qualification.record['checks'].append({
            'case': 'both_order_accounting_public_c1', 'passed': passed and not errors,
            'accounting_first_blocking_observed': first_blocked,
            'c1_first_blocking_observed': second_blocked,
            'close_errors': errors,
            'scope': 'Actual public pending/unknown C1; reconciler-first rollback and C1-first commit, late-report reuse, then actual thirty-day pruning without a scan tombstone; original event/receipt/funding preservation, saved cancellation replay and post-prune report rejection. Observer uses an existing independent connection/new transaction. No all-media/account-deletion or automatic-cron claim.',
        })
        qualification.save()
        if errors:
            raise RuntimeError('owned C1 session cleanup failed')


def run_report_witness(qualification, *, existing_winner):
    """Installed report observers + real writer on injected original; no producer authority."""
    qualification.execute('install_disposable_report_wrapper', """
CREATE FUNCTION public.s0_report_fixture() RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE original internal.identification_invocations; event UUID;
BEGIN
 SELECT * INTO STRICT original FROM internal.identification_invocations WHERE is_initial_analysis FOR UPDATE;
 IF original.event_id IS NOT NULL THEN RETURN internal.complete_identification_usage(original.id,NULL,'null'); END IF;
 -- Synthetic authority only: this wrapper intentionally tests no receipt lookup
 -- or outer producer validation and is installed only in this owned disposable.
 INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
  admission_receipt_digest,reservation_id,invocation_id,expected_writes,report_invocation)
 VALUES(pg_current_xact_id(),original.scan_id,original.user_id,'report',original.initial_admission_receipt_id,
  repeat('a',64),original.reservation_id,original.id,'[]',to_jsonb(original));
 event:=internal.complete_identification_usage(original.id,'draft','{"input_tokens":101,"candidate_tokens":37}');
 DELETE FROM internal.initial_consuming_staging;
 RETURN event;
END $$;
REVOKE ALL ON FUNCTION public.s0_report_fixture() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.s0_report_fixture() TO service_role;
""")
    sessions = []
    passed = False
    completed = []
    try:
        for name in ('report', 'peer', 'observer'):
            sessions.append(Session(qualification, 'report_witness_' + name))
        reporter, peer, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct report/peer/observer backends required')
        role = "BEGIN; SET LOCAL ROLE service_role; SELECT public.s0_report_fixture();"
        # Use a PL/pgSQL variable: expanding a volatile function result with .*
        # in a SELECT target list could evaluate it once per output field.
        orphan = """BEGIN; DO $$ DECLARE i internal.identification_invocations; e public.ai_usage_events; BEGIN
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 e:=internal.prepare_identification_usage_event(i,'unknown_execution','{}');
 INSERT INTO public.ai_usage_events SELECT (e).*; END $$;"""
        if existing_winner:
            # Different connections contend on the unique source event; no
            # fabricated timing or sleep stands in for an observed blocker.
            peer.run('uncommitted_winner', orphan)
            reporter.start('report_waits_for_event', role)
            wait_for_blocker(observer, reporter, peer)
            peer.run('abort_winner', 'ROLLBACK;')
            reporter.finish()
            reporter.run('insert_after_winner_rollback_role_validation', 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
            completed.append('event_rollback_then_insert')

            reporter.run('report_first', role)
            peer.start('erasure_waits_for_report', 'BEGIN;' + ERASE)
            wait_for_blocker(observer, peer, reporter)
            reporter.run('report_rollback', 'ROLLBACK;')
            peer.finish()
            peer.run('erasure_immediate_actual_role', RETIRED + 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
            completed.append('report_then_erasure')

            peer.run('erasure_first', 'BEGIN;' + ERASE + RETIRED)
            reporter.start('report_waits_for_erasure', role)
            wait_for_blocker(observer, reporter, peer)
            peer.run('erasure_rollback', 'ROLLBACK;')
            reporter.finish()
            reporter.run('report_after_erasure_rollback', 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
            completed.append('erasure_then_report')

            peer.run('winning_insert', orphan)
            reporter.start('report_waits_for_committed_winner', role)
            wait_for_blocker(observer, reporter, peer)
            peer.run('commit_winner', 'COMMIT;')
            reporter.finish()
            completed.append('event_commit_then_existing_winner')
        else:
            reporter.run('new_report_actual_role', role)
        # Keep service_role selected through COMMIT; private deferred validators
        # must work after the SECURITY DEFINER wrapper has returned.
        reporter.run('deferred_commit_actual_role', 'COMMIT;')
        expected = 'unknown' if existing_winner else 'success'
        observer.run('fresh_session_exact_final_accounting', """DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
  OR (SELECT count(*) FROM public.ai_usage_events WHERE source_type='identification_invocation')<>1
  OR (SELECT count(*) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON e.id=i.event_id
   WHERE i.is_initial_analysis AND e.source_id=i.id AND e.outcome='""" + expected + """')<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX761'; END IF; END $$;""")
        before = observer.run('exact_replay_prestate', "SELECT md5(to_jsonb(i)::TEXT||to_jsonb(e)::TEXT) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON e.id=i.event_id;")
        peer.run('already_accounted_replay_actual_role', role + 'COMMIT;')
        after = observer.run('exact_replay_poststate', "SELECT md5(to_jsonb(i)::TEXT||to_jsonb(e)::TEXT) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON e.id=i.event_id;")
        if before != after or len(before) != 1:
            raise RuntimeError('report replay altered winner or invocation')
        passed = True
    finally:
        errors = []
        for session in sorted(sessions, key=lambda s: s.pending is not None):
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
        qualification.record['checks'].append({
            'case': 'report_witness_existing' if existing_winner else 'report_witness_inserted_commit',
            'passed': passed and not errors, 'completed_schedules': completed,
            'actual_service_role_deferred_commit': passed, 'closure_errors': errors,
            'scope': 'Injected original invocation and installed report observers; fixture-only definer wrapper, not production authority.'})
        qualification.save()
        if errors:
            raise RuntimeError('report witness session closure failed')


def run_report_producer(qualification, *, commit=True):
    """Fixed private report producer; dispatch state alone is still injected."""
    qualification.execute('inject_dispatch_lifecycle_only', """
BEGIN;
ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized';
ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER USER;
COMMIT;
""")
    output = qualification.execute('original_report_identity_and_rollback', """
BEGIN;
SELECT extensions.no_plan();
CREATE TEMP TABLE report_inputs AS SELECT i.user_id owner_id,i.scan_id,i.id invocation,i.lease_sha256,
 (r.accounting::JSONB#>>'{reservation,lease_token}')::UUID lease,
 r.manifest::JSONB#>>'{proof,input,digest}' digest FROM internal.identification_invocations i
 JOIN internal.initial_preparation_admission_receipts r ON r.admission_receipt_id=i.initial_admission_receipt_id;
CREATE TEMP TABLE report_before AS SELECT
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservations q) quota,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservation_counters q) links,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_counters q) counters,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.complimentary_scan_usage q) credit;
CREATE FUNCTION pg_temp.producer_case(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE args RECORD; reply JSONB; replay JSONB; original internal.identification_invocations; e public.ai_usage_events; field TEXT;
BEGIN
 BEGIN
  SELECT * INTO STRICT args FROM report_inputs;
  IF mode LIKE 'bad_winner:%' OR mode LIKE 'bad_replay:%' THEN
   SELECT * INTO STRICT original FROM internal.identification_invocations WHERE id=args.invocation FOR UPDATE;
   e:=internal.prepare_identification_usage_event(original,'unknown_execution','{}');
   field:=split_part(mode,':',2);
   IF field='input_modality' THEN e.input_modality:='text';
   ELSIF field='outcome' THEN e.outcome:='success';
   ELSE e.metadata:=jsonb_set(e.metadata,ARRAY[field],'"corrupt"'::JSONB); END IF;
   INSERT INTO public.ai_usage_events SELECT (e).*;
   IF mode LIKE 'bad_replay:%' THEN
    UPDATE internal.identification_invocations SET event_id=e.id WHERE id=original.id;
   END IF;
  END IF;
  IF mode='pending' THEN
   ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
   UPDATE internal.initial_analysis_lifecycle_fences SET state='pending_pre_dispatch';
   ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER USER;
  END IF;
  reply:=internal.report_initial_analysis_usage(
   CASE WHEN mode='foreign_owner' THEN gen_random_uuid() ELSE args.owner_id END,args.scan_id,
   CASE WHEN mode='wrong_input' THEN repeat('f',64) ELSE args.digest END,
   CASE WHEN mode='wrong_invocation' THEN gen_random_uuid() ELSE args.invocation END,
   CASE WHEN mode='wrong_lease' THEN gen_random_uuid() ELSE args.lease END,'draft',
   CASE WHEN mode='noncanonical' THEN '{ "candidate_tokens":37,"input_tokens":101}'
    WHEN mode='invalid_json' THEN '{' ELSE '{"candidate_tokens":37,"input_tokens":101}' END);
  IF mode='replay' THEN
   replay:=internal.report_initial_analysis_usage(args.owner_id,args.scan_id,args.digest,args.invocation,args.lease,NULL,'invalid');
   IF replay IS DISTINCT FROM reply THEN RAISE EXCEPTION USING ERRCODE='ZX762'; END IF;
  END IF;
  IF reply->>'owner_id' IS DISTINCT FROM args.owner_id::TEXT OR reply->>'scan_id' IS DISTINCT FROM args.scan_id::TEXT
   OR reply->>'invocation_id' IS DISTINCT FROM args.invocation::TEXT OR reply->>'submission_digest' IS DISTINCT FROM args.digest
   OR (SELECT count(*) FROM public.ai_usage_events WHERE id=(reply->>'event_id')::UUID AND outcome='success')<>1
   OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
   OR (SELECT quota FROM report_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservations q)
   OR (SELECT links FROM report_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservation_counters q)
   OR (SELECT counters FROM report_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_counters q)
   OR (SELECT credit FROM report_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.complimentary_scan_usage q)
   THEN RAISE EXCEPTION USING ERRCODE='ZX763'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'success rollback' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN 'ok'; END;
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE||':'||SQLERRM;
END $$;
SELECT extensions.is(pg_temp.producer_case(mode),expected,mode) FROM (VALUES
 ('valid','ok'),('replay','ok'),
 ('pending','55000:initial_analysis_report_unavailable'),
 ('foreign_owner','P0002:initial_analysis_owner_unavailable'),
 ('wrong_input','55000:initial_analysis_report_conflict'),
 ('wrong_invocation','55000:initial_analysis_report_conflict'),
 ('wrong_lease','55000:initial_analysis_report_conflict'),
 ('noncanonical','22023:identification_usage_invalid'),
 ('invalid_json','22023:identification_usage_invalid')
) cases(mode,expected);
SELECT extensions.is(pg_temp.producer_case(prefix||field),'55000:initial_analysis_report_conflict',prefix||field)
 FROM unnest(ARRAY['bad_winner:','bad_replay:']) prefix CROSS JOIN
 unnest(ARRAY['input_modality','outcome','writer','ai_provider','ai_binding','ai_policy_version','ai_input_profile',
 'ai_attribution','ai_prompt','ai_schema','ai_provenance','ai_usage_contract','ai_outcome']) field;
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM public.ai_usage_events)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_consuming_staging),'all cases rolled back exact accounting');
SELECT extensions.ok(NOT has_function_privilege('service_role',
 'internal.report_initial_analysis_usage(uuid,uuid,text,uuid,uuid,text,text)','EXECUTE'), 'private producer has no API execution grant');
SELECT extensions.finish();
ROLLBACK;
""")
    import re
    passed = (not re.search(r'^not ok\b', output, re.M)
              and len(re.findall(r'^ok \d+\b', output, re.M)) == 37
              and re.search(r'^1\.\.37$', output, re.M) is not None)
    qualification.record['report_producer_assertions'] = re.findall(r'^(?:not )?ok \d+[^\n]*$', output, re.M)
    qualification.record['checks'].append({'case': 'report_producer_assertions', 'passed': passed, 'count': 37})
    qualification.save()
    if not passed:
        raise RuntimeError('report producer assertions failed; sanitized receipt retained')
    if not commit:
        return
    qualification.execute('install_disposable_producer_wrapper', """
CREATE FUNCTION public.s0_report_producer_fixture() RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.identification_invocations; r internal.initial_preparation_admission_receipts;
BEGIN
 -- Read request arguments without row locks. The real producer takes all locks
 -- in its own original outer order; this wrapper grants no production access.
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE admission_receipt_id=i.initial_admission_receipt_id;
 RETURN internal.report_initial_analysis_usage(i.user_id,i.scan_id,r.manifest::JSONB#>>'{proof,input,digest}',i.id,
  (r.accounting::JSONB#>>'{reservation,lease_token}')::UUID,'draft','{"candidate_tokens":37,"input_tokens":101}');
END $$;
REVOKE ALL ON FUNCTION public.s0_report_producer_fixture() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.s0_report_producer_fixture() TO service_role;
BEGIN; SET LOCAL ROLE service_role; SELECT public.s0_report_producer_fixture(); COMMIT;
""")
    qualification.execute('verify_committed_original_report', """DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR (SELECT count(*) FROM internal.identification_invocations i JOIN public.ai_usage_events e ON e.id=i.event_id
  WHERE i.is_initial_analysis AND e.source_id=i.id AND e.outcome='success' AND e.prompt_tokens=101 AND e.candidate_tokens=37)<>1
 THEN RAISE EXCEPTION USING ERRCODE='ZX764'; END IF;
END $$;""")


def install_result_fixture(qualification, *, injected_dispatch=True, primary_species=False):
    """Synthetic result content; optionally require a real committed dispatch."""
    import json
    import re
    from pathlib import Path
    from initial_atomic_admission_test_support import ROOT
    fixture = ROOT / 'services/supabase/functions/_shared/initialAnalysis/fixtures/retainedResultV1.json'
    qualification.record['source_manifest'][str(fixture.relative_to(ROOT))] = qualification.digest(fixture)
    data = json.loads(json.loads(fixture.read_text())['evidence']['result_canonical'])['data']
    if primary_species:
        # Select synthetic content before its first retained write. Provenance
        # still comes exclusively from the original dispatched invocation.
        data['primary_identification'] = dict(version=1, resolution='species',
                                              scientific_name=data['scientific_name'], common_name=data['common_name'])
        data['candidates'] = [dict(candidate, taxon_rank='species') for candidate in data['candidates']]
        data['pet_identification'] = None
        data['is_new_to_merian_dictionary'] = False
    encoded = json.dumps(data, separators=(',', ':'), ensure_ascii=False).replace("'", "''")
    preparation = """
BEGIN;
ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
UPDATE internal.initial_analysis_lifecycle_fences SET state='dispatch_authorized';
ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER USER;
COMMIT;
""" if injected_dispatch else """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.identification_invocations WHERE is_initial_analysis)<>1
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR NOT EXISTS(SELECT 1 FROM internal.identification_invocations i
   JOIN internal.ai_quota_reservations q ON q.id=i.reservation_id
   JOIN internal.initial_analysis_lifecycle_fences f ON f.scan_id=i.scan_id
   WHERE i.is_initial_analysis AND q.state='committed' AND f.state='dispatch_authorized')
 THEN RAISE EXCEPTION USING ERRCODE='ZX791'; END IF;
END $$;
"""
    qualification.execute('install_disposable_result_fixture', preparation + """
CREATE FUNCTION public.s0_result_suppress() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION public.s0_result_mutate() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.result_snapshot:=jsonb_set(NEW.result_snapshot,'{data,ai_reasoning}','"mutation"');RETURN NEW;END $$;
CREATE FUNCTION public.s0_result_fixture(mode TEXT DEFAULT 'valid') RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i internal.identification_invocations; a internal.initial_analysis_admissions;
 r internal.initial_preparation_admission_receipts; d JSONB; p JSONB; value JSONB; reply JSONB; before_event JSONB;
 evidence UUID:='00000000-0000-4000-8000-000000000901'; canonical TEXT; digest TEXT; lease UUID;
BEGIN
 SELECT * INTO STRICT i FROM internal.identification_invocations WHERE is_initial_analysis;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=i.scan_id;
 SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE admission_receipt_id=i.initial_admission_receipt_id;
 lease:=(r.accounting::JSONB#>>'{reservation,lease_token}')::UUID;
 -- Fixture's v1 provenance has one fractional field. This independent encoder
 -- preserves the original numeric value; it does not call the new decoder.
 p:=jsonb_set(i.provenance,'{generation,temperature}',to_jsonb(i.provenance#>>'{generation,temperature}'));
 d:='""" + encoded + """'::JSONB||jsonb_build_object('scan_id',i.scan_id,'identification_provenance',p);
 value:=jsonb_build_object('version',1,'state','validated_success','scan_id',i.scan_id,'invocation_id',i.id,
  'submission_digest',a.submission_digest,'config_digest',a.configuration_digest,'funding_binding_digest',a.funding_digest,
  'data',d,'provider_usage',jsonb_build_object('input_tokens',101,'cached_tokens',NULL,'cache_write_tokens',NULL,
   'output_tokens',37,'candidate_tokens',37,'thinking_tokens',NULL,'tool_tokens',NULL,'total_tokens',138,'service_tier',NULL,
   'modality_breakdown',jsonb_build_object('prompt','{}'::JSONB,'cached','{}'::JSONB,'candidates','{}'::JSONB,'tool','{}'::JSONB)));
 IF mode LIKE 'wrong_reference:%' THEN value:=jsonb_set(value,ARRAY[split_part(mode,':',2)],to_jsonb(repeat('f',64))); END IF;
 IF mode='wrong_provenance' THEN p:=jsonb_set(p,'{generation,temperature}','"0.2"');value:=jsonb_set(value,'{data,identification_provenance}',p); END IF;
 IF mode='numeric_string' THEN p:=jsonb_set(p,'{prompt}','"123"');value:=jsonb_set(value,'{data,identification_provenance}',p); END IF;
 IF mode='malformed_usage' THEN value:=jsonb_set(value,'{provider_usage,total_tokens}','-1'); END IF;
 IF mode='unknown' THEN
  PERFORM internal.complete_identification_usage(i.id,'unknown_execution','{}');
  SELECT to_jsonb(e) INTO before_event FROM public.ai_usage_events e WHERE source_id=i.id;
 END IF;
 canonical:=internal.initial_canonical(value);
 digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||canonical,'UTF8'),'sha256'),'hex');
 IF mode='absent' THEN
  reply:=internal.read_initial_analysis_result(i.user_id,i.scan_id,a.submission_digest,evidence,digest);
  IF reply->>'outcome' IS DISTINCT FROM 'absent' OR reply->'evidence' IS DISTINCT FROM 'null'::JSONB
   OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) THEN RAISE EXCEPTION USING ERRCODE='ZX786'; END IF;
  RETURN reply;
 END IF;
 IF mode='wrong_digest' THEN digest:=repeat('f',64); END IF;
 IF mode='noncanonical' THEN canonical:=' '||canonical; END IF;
 IF mode='pending' THEN
  ALTER TABLE internal.initial_analysis_lifecycle_fences DISABLE TRIGGER USER;
  UPDATE internal.initial_analysis_lifecycle_fences SET state='pending_pre_dispatch';
  ALTER TABLE internal.initial_analysis_lifecycle_fences ENABLE TRIGGER USER;
 END IF;
 IF mode='missing_after' THEN ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER s0_result_row_after; END IF;
 IF mode='missing_before' THEN ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER s0_result_row_before; END IF;
 IF mode='suppressed' THEN
  CREATE TRIGGER zzzz_result_suppress BEFORE INSERT ON internal.initial_analysis_results FOR EACH ROW EXECUTE FUNCTION public.s0_result_suppress();
 END IF;
 IF mode='mutated' THEN
  CREATE TRIGGER zzzz_result_mutate BEFORE INSERT ON internal.initial_analysis_results FOR EACH ROW EXECUTE FUNCTION public.s0_result_mutate();
 END IF;
 IF mode='unbound' THEN
  INSERT INTO internal.initial_consuming_staging(transaction_id,scan_id,owner_id,operation,admission_receipt_id,
   admission_receipt_digest,reservation_id,invocation_id,result_evidence_id,expected_writes)
  VALUES(pg_current_xact_id(),i.scan_id,i.user_id,'result',r.admission_receipt_id,r.receipt_digest,i.reservation_id,i.id,evidence,
   jsonb_build_array(jsonb_build_array(jsonb_build_object('old',NULL,'new',jsonb_build_object('scan_id',i.scan_id,
    'owner_id',i.user_id,'result_evidence_id',evidence,'result_schema_version',1,'result_snapshot',value,'provenance_snapshot',p)))));
 END IF;
 IF mode IN ('direct','unbound') THEN
  INSERT INTO internal.initial_analysis_results VALUES(i.scan_id,i.user_id,evidence,1,value,p);
 END IF;
 reply:=internal.record_initial_analysis_result(
  CASE WHEN mode='foreign_owner' THEN gen_random_uuid() ELSE i.user_id END,i.scan_id,a.submission_digest,
  CASE WHEN mode='wrong_invocation' THEN gen_random_uuid() ELSE i.id END,
  CASE WHEN mode='wrong_lease' THEN gen_random_uuid() ELSE lease END,evidence,canonical,internal.initial_canonical(p),digest);
 IF reply->>'outcome' IS DISTINCT FROM 'recorded' THEN RAISE EXCEPTION USING ERRCODE='ZX781'; END IF;
 IF mode IN ('replay','conflicting_uuid','conflicting_content') THEN
  IF mode='conflicting_content' THEN
   value:=jsonb_set(value,'{data,ai_reasoning}','"another original result"');
   canonical:=internal.initial_canonical(value);
   digest:=encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||canonical,'UTF8'),'sha256'),'hex');
  END IF;
  reply:=internal.record_initial_analysis_result(i.user_id,i.scan_id,a.submission_digest,i.id,lease,
   CASE WHEN mode='conflicting_uuid' THEN gen_random_uuid() ELSE evidence END,canonical,internal.initial_canonical(p),digest);
  IF reply->>'outcome' IS DISTINCT FROM 'replay' THEN RAISE EXCEPTION USING ERRCODE='ZX782'; END IF;
 END IF;
 IF mode IN ('read','wrong_read_uuid','wrong_read_digest') THEN
  reply:=internal.read_initial_analysis_result(i.user_id,i.scan_id,a.submission_digest,
   CASE WHEN mode='wrong_read_uuid' THEN gen_random_uuid() ELSE evidence END,
   CASE WHEN mode='wrong_read_digest' THEN repeat('f',64) ELSE digest END);
  IF reply->>'outcome' IS DISTINCT FROM 'found' OR reply#>>'{evidence,result_canonical}' IS DISTINCT FROM canonical
   OR reply#>>'{evidence,provenance_canonical}' IS DISTINCT FROM internal.initial_canonical(p)
   OR reply->'reference' IS DISTINCT FROM reply#>'{evidence,reference}' THEN RAISE EXCEPTION USING ERRCODE='ZX787'; END IF;
 END IF;
 IF mode='unknown' AND (SELECT to_jsonb(e) FROM public.ai_usage_events e WHERE source_id=i.id) IS DISTINCT FROM before_event THEN
  RAISE EXCEPTION USING ERRCODE='ZX783'; END IF;
 IF mode='terminal_damage' THEN
  -- Inject damage after the real writer: bypass only immutable row protection
  -- inside the caller's rollback-only fault case; terminal comparison must fail.
  ALTER TABLE internal.initial_analysis_results DISABLE TRIGGER guard_initial_analysis_result;
  UPDATE internal.initial_analysis_results SET result_snapshot=jsonb_set(result_snapshot,'{data,ai_reasoning}','"damage"');
  ALTER TABLE internal.initial_analysis_results ENABLE TRIGGER guard_initial_analysis_result;
 END IF;
 RETURN reply;
END $$;
REVOKE ALL ON FUNCTION public.s0_result_fixture(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.s0_result_fixture(TEXT) TO service_role;
""")


def run_result_producer(qualification):
    import re
    install_result_fixture(qualification)
    output = qualification.execute('result_original_cases', """
BEGIN;SELECT extensions.no_plan();
CREATE TEMP TABLE result_before AS SELECT
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservations q) quota,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservation_counters q) links,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_counters q) counters,
 (SELECT jsonb_agg(to_jsonb(q)) FROM internal.complimentary_scan_usage q) credit;
CREATE FUNCTION pg_temp.result_case(mode TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  PERFORM public.s0_result_fixture(mode);
  IF (SELECT quota FROM result_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservations q)
   OR (SELECT links FROM result_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_reservation_counters q)
   OR (SELECT counters FROM result_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.ai_quota_counters q)
   OR (SELECT credit FROM result_before) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q)) FROM internal.complimentary_scan_usage q)
   OR (mode<>'unknown' AND EXISTS(SELECT 1 FROM public.ai_usage_events)) THEN RAISE EXCEPTION USING ERRCODE='ZX784'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN RETURN 'ok'; END;
EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE;
END $$;
SELECT extensions.is(pg_temp.result_case(mode),expected,mode) FROM (VALUES
 ('valid','ok'),('replay','ok'),('unknown','ok'),('read','ok'),('absent','ok'),
 ('wrong_read_uuid','55000'),('wrong_read_digest','55000'),('wrong_provenance','55000'),('numeric_string','55000'),
 ('wrong_reference:submission_digest','55000'),('wrong_reference:config_digest','55000'),('wrong_reference:funding_binding_digest','55000'),
 ('wrong_digest','22023'),('noncanonical','22023'),('malformed_usage','22023'),
 ('foreign_owner','P0002'),('wrong_invocation','55000'),('wrong_lease','55000'),('pending','55000'),
 ('conflicting_uuid','55000'),('conflicting_content','55000'),('direct','55000'),
 ('missing_before','55000'),('missing_after','55000'),('terminal_damage','55000'),
 ('unbound','55000'),('suppressed','55000'),('mutated','55000')) cases(mode,expected);
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_consuming_staging),'all result effects rolled back');
SELECT extensions.ok(NOT has_function_privilege('service_role',
 'internal.record_initial_analysis_result(uuid,uuid,text,uuid,uuid,uuid,text,text,text)','EXECUTE'),'private result producer API denied');
SELECT extensions.finish();ROLLBACK;
""")
    assertions = re.findall(r'^(?:not )?ok \d+[^\n]*$', output, re.M)
    passed = (not re.search(r'^not ok\b', output, re.M) and len(assertions) == 30
              and re.search(r'^1\.\.30$', output, re.M) is not None)
    qualification.record['result_producer_assertions'] = assertions
    qualification.record['checks'].append({'case': 'result_producer_assertions', 'passed': passed, 'count': 30})
    qualification.save()
    if not passed:
        raise RuntimeError('result producer assertions failed; sanitized receipt retained')
    qualification.execute('result_actual_role_deferred_commit', """
BEGIN;SET LOCAL ROLE service_role;SELECT public.s0_result_fixture('valid');COMMIT;
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.initial_analysis_results)<>1
 OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 OR EXISTS(SELECT 1 FROM public.ai_usage_events)
 THEN RAISE EXCEPTION USING ERRCODE='ZX785'; END IF;
END $$;
""")

    qualification.execute('committed_result_cancellation_and_late_read_denial', """
BEGIN;
CREATE TEMP TABLE late_result_request AS SELECT r.owner_id,r.scan_id,r.result_evidence_id,a.submission_digest,
 encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex') digest
 FROM internal.initial_analysis_results r JOIN internal.initial_analysis_admissions a USING(scan_id);
DO $$ DECLARE owner_id UUID; reply JSONB; BEGIN
 SELECT l.owner_id INTO STRICT owner_id FROM late_result_request l;
 SET LOCAL ROLE service_role;
 reply:=public.cancel_initial_analysis(owner_id,'00000000-0000-4000-8000-000000000401');
 IF reply->>'dispatch' IS DISTINCT FROM 'dispatch_already_authorized' THEN RAISE EXCEPTION USING ERRCODE='ZX788'; END IF;
END $$;
COMMIT;
DO $$ DECLARE request RECORD; denied BOOLEAN:=FALSE; BEGIN
 IF EXISTS(SELECT 1 FROM internal.initial_analysis_results)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions)
 OR (SELECT count(*) FROM internal.identification_invocations i WHERE internal.initial_invocation_retired(i))<>1
 OR (SELECT count(*) FROM public.ai_usage_events WHERE outcome='unknown')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX789'; END IF;
 SELECT * INTO STRICT request FROM late_result_request;
 BEGIN
  PERFORM internal.read_initial_analysis_result(request.owner_id,request.scan_id,request.submission_digest,request.result_evidence_id,request.digest);
 EXCEPTION WHEN SQLSTATE '55000' THEN denied:=TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX790'; END IF;
END $$;
""")


def run_result_races(qualification):
    """Three observed-blocker result/read/scan-erasure schedules, no provider IO."""
    from initial_atomic_admission_sessions import PROJECTION
    run_report_producer(qualification, commit=False)
    install_result_fixture(qualification)
    qualification.execute('install_disposable_result_read_wrapper', """
CREATE FUNCTION public.s0_result_read_denied_fixture() RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r internal.initial_analysis_results; a internal.initial_analysis_admissions; denied BOOLEAN:=FALSE;
BEGIN
 -- Read request facts before the helper owns its scope; the eraser's uncommitted
 -- deletion is invisible. No pre-acquired row lock masks the real reader order.
 SELECT * INTO STRICT r FROM internal.initial_analysis_results;
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id;
 BEGIN
  PERFORM internal.read_initial_analysis_result(r.owner_id,r.scan_id,a.submission_digest,r.result_evidence_id,
   encode(extensions.digest(convert_to('merian.initial-analysis.result.v1'||chr(10)||internal.initial_canonical(r.result_snapshot),'UTF8'),'sha256'),'hex'));
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM IS DISTINCT FROM 'initial_analysis_deleted' THEN RAISE; END IF;
  denied:=TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX791'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.s0_result_read_denied_fixture() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.s0_result_read_denied_fixture() TO service_role;
""")
    sessions = []
    passed = False
    try:
        for name in ('writer', 'eraser', 'observer'):
            sessions.append(Session(qualification, 'result_' + name))
        writer, eraser, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('three distinct result race sessions required')
        write = "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',true);SET LOCAL ROLE service_role;DO $$ BEGIN PERFORM public.s0_result_fixture('valid');END $$;"
        # Normal erasure first acquires the owner/scan scope. Raw privileged
        # tombstone insertion deliberately uses NOWAIT and must not wait behind
        # this result producer's outer owner lock.
        erase = """BEGIN;SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$ DECLARE o UUID; s UUID; BEGIN
 SELECT user_id,scan_id INTO STRICT o,s FROM internal.identification_invocations WHERE is_initial_analysis;
 PERFORM internal.lock_initial_preparation_scope(o,s);
END $$;""" + ERASE
        writer.run('result_first', write)
        eraser.start('erasure_waits_for_result', erase)
        wait_for_blocker(observer, eraser, writer)
        writer.run('rollback_result', 'ROLLBACK;')
        eraser.finish()
        eraser.run('validate_erasure_then_rollback', 'SET LOCAL ROLE service_role;SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;')
        observer.run('no_partial_result_after_rollbacks', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM public.ai_usage_events) OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones) THEN RAISE EXCEPTION USING ERRCODE='ZX792'; END IF; END $$;")
        eraser.run('erasure_first', erase)
        writer.start('result_waits_for_erasure', write)
        wait_for_blocker(observer, writer, eraser)
        eraser.run('rollback_erasure', 'ROLLBACK;')
        writer.finish()
        writer.run('commit_result_actual_role', 'COMMIT;')
        observer.run('one_committed_result', "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_results)<>1 OR EXISTS(SELECT 1 FROM public.ai_usage_events) OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX793'; END IF; END $$;")
        eraser.run('delete_committed_result', erase)
        writer.start('read_waits_for_committed_erasure', "BEGIN;SELECT set_config('request.jwt.claim.role','service_role',true);SET LOCAL ROLE service_role;SELECT public.s0_result_read_denied_fixture();")
        wait_for_blocker(observer, writer, eraser)
        eraser.run('commit_erasure_actual_role', 'SET LOCAL ROLE service_role;COMMIT;')
        writer.finish()
        erased_digest = observer.run('committed_erasure_digest_before_read_commit', 'SELECT md5((' + PROJECTION + ')::TEXT);')
        writer.run('commit_denied_read_without_write', 'COMMIT;')
        if observer.run('committed_erasure_digest_after_read_commit', 'SELECT md5((' + PROJECTION + ')::TEXT);') != erased_digest:
            raise RuntimeError('denied original read changed committed scoped state')
        observer.run('erasure_terminal_state', RETIRED + "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX794'; END IF;END $$;")
        passed = True
    finally:
        errors = []
        for session in sorted(sessions, key=lambda s: s.pending is not None):
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
        qualification.record['checks'].append({'case': 'result_scan_erasure_schedules', 'passed': passed and not errors, 'schedule_count': 3, 'session_count': len(sessions), 'cleanup_errors': errors})
        qualification.save()
        if errors:
            raise RuntimeError('owned result race session cleanup failed')

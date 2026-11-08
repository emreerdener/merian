"""Both actual service-role public cancellation orders against a foreign owner."""
import datetime
import re
import subprocess
import time
from initial_atomic_admission_sessions import BASE, IDS, PROJECTION, Session


def cross_owner_cases(qualification):
    base, ids, projection = BASE, IDS, PROJECTION
    execute = qualification.execute
    sessions = []
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = (
        'Both public service-role cancellation orders, a held synthetic admission '
        'and existing foreign owner. Trusted selected-scan row-lock scheduler; '
        'no provider dispatch, general cross-owner or hosted qualification.')
    qualification.execute('singleton_cross_owner_fixture', """
DO $$ BEGIN
 IF (SELECT count(*) FROM internal.initial_preparation_admission_receipts)<>1
 OR (SELECT count(*) FROM internal.initial_analysis_submissions)<>1
 OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='held')<>1
 OR (SELECT count(*) FROM public.users)<2
 THEN RAISE EXCEPTION USING ERRCODE='ZX524'; END IF;
END $$;
""")

    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({
            'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session

    def blocking(observer, blocker, waiter):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if observer.run('observe_blocker', f'SELECT {blocker.pid}=ANY(pg_blocking_pids({waiter.pid}));') == ['t']:
                qualification.record.setdefault('observed_blockers', []).append({
                    'blocker': blocker.name, 'waiter': waiter.name})
                qualification.save()
                return
            time.sleep(0.05)
        raise RuntimeError('expected endpoint blocking missing')

    def close_group(group):
        failures = []
        for session in group:
            try:
                session.close()
            except Exception as error:
                failures.append(type(error).__name__)
            finally:
                sessions.remove(session)
        if failures:
            qualification.record['close_errors'] = failures
            qualification.save()
            raise RuntimeError('session cleanup failed')

    def invoke(body):
        return 'DO $$ DECLARE o UUID; a UUID; result JSONB; BEGIN ' + ids + body + ' END $$;'
    positive = invoke('\n SET LOCAL ROLE service_role;\n result:=public.cancel_initial_analysis(o,a);\n IF result IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX401\'; END IF;\n RESET ROLE;\n IF NOT internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)\n  OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents)\n  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>\'refunded\' OR refund_count<>1)\n  OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters)\n  OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state<>\'released\' OR settlement_reason<>\'cancelled_before_dispatch\')\n  OR EXISTS(SELECT 1 FROM internal.identification_invocations)\n  OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=a)<>\'cancelled_pre_dispatch\'\n THEN RAISE EXCEPTION USING ERRCODE=\'ZX402\'; END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(a);\n SET LOCAL ROLE service_role;\n')
    wrong = 'DO $$ DECLARE o UUID;a UUID;b UUID;failed BOOLEAN:=FALSE;BEGIN ' + ids + "SELECT id INTO STRICT b FROM public.users WHERE id<>o ORDER BY id LIMIT 1;BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(b,a);EXCEPTION WHEN SQLSTATE 'P0002' THEN IF SQLERRM<>'initial_analysis_owner_unavailable' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed OR (SELECT value FROM before_wrong) IS DISTINCT FROM " + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX521';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(a);END $$;"
    wrong_start = base + 'CREATE TEMP TABLE before_wrong AS SELECT ' + projection + ' AS value;' + wrong + "SELECT 'WRONG_DENIED';"
    owner_before = 'CREATE TEMP TABLE all_users_before AS SELECT * FROM public.users;CREATE TEMP TABLE owner_before AS SELECT u.* FROM public.users u JOIN internal.initial_preparation_admission_receipts r ON r.owner_id=u.id;'
    owner_after = "RESET ROLE;DO $$ BEGIN IF (SELECT count(*) FROM owner_before)<>1 OR (SELECT count(*) FROM public.users)<>(SELECT count(*) FROM all_users_before) OR EXISTS(SELECT 1 FROM all_users_before b FULL JOIN public.users u ON u.id=b.id WHERE b.id NOT IN (SELECT id FROM owner_before) AND to_jsonb(b) IS DISTINCT FROM to_jsonb(u)) OR EXISTS(SELECT 1 FROM owner_before b JOIN public.users u ON u.id=b.id WHERE to_jsonb(u) IS DISTINCT FROM to_jsonb(b)||jsonb_build_object('complimentary_entitlement_epoch',b.complimentary_entitlement_epoch+1,'entitlement_version',b.entitlement_version+1)) THEN RAISE EXCEPTION USING ERRCODE='ZX522';END IF;END $$;"
    try:
        actor = peer('valid_first')
        wrong_peer = peer('foreign_waiter')
        observer = peer('first_observer')
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct backends required')
        actor.run('valid_cancellation', base + positive)
        wrong_peer.start('foreign_exact_denial', wrong_start)
        blocking(observer, actor, wrong_peer)
        actor.run('valid_rollback', 'ROLLBACK;')
        wrong_peer.finish()
        wrong_peer.run('foreign_commit', 'COMMIT;')
        close_group([actor, wrong_peer, observer])
        qualification.record['checks'].append({
            'case': 'valid_owner_first_rolls_back_foreign_waiter_denied',
            'passed': True, 'blocking_observed': True, 'wrong_exact_p0002': True,
            'wrong_projection_unchanged': True})
        qualification.save()

        fixture = peer('selected_scan_lock_fixture')
        wrong_peer = peer('foreign_first')
        actor = peer('valid_waiter')
        observer = peer('second_observer')
        if len({s.pid for s in sessions}) != 4:
            raise RuntimeError('distinct backends required')
        fixture.run('lock_selected_scan', base + "DO $$ BEGIN PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=(SELECT scan_id FROM internal.initial_preparation_admission_receipts) FOR UPDATE;END $$;")
        wrong_peer.start('foreign_exact_denial', wrong_start)
        blocking(observer, fixture, wrong_peer)
        actor.start('valid_cancellation', base + owner_before + positive + owner_after)
        blocking(observer, wrong_peer, actor)
        fixture.run('release_fixture', 'ROLLBACK;')
        wrong_peer.finish()
        actor.finish()
        wrong_peer.run('foreign_commit', 'COMMIT;')
        actor.run('valid_commit', 'COMMIT;')
        close_group([fixture, wrong_peer, actor, observer])
        qualification.record['checks'].append({
            'case': 'foreign_owner_first_denies_valid_waiter_commits',
            'passed': True, 'fixture_to_foreign_blocking_observed': True,
            'foreign_to_valid_blocking_observed': True, 'wrong_exact_p0002': True,
            'wrong_projection_unchanged_before_valid_commit': True,
            'valid_owner_exact_projection': True})
        qualification.save()
        execute('fresh_final_one_original_refund_held_release_and_no_authority', "DO $$ BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations WHERE dispatch='dispatch_prevented')<>1 OR (SELECT count(*) FROM internal.ai_quota_reservations)<>1 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'refunded' OR refund_count<>1) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters) OR (SELECT count(*) FROM internal.complimentary_scan_usage)<>1 OR (SELECT count(*) FROM internal.complimentary_scan_usage h JOIN internal.initial_analysis_cancellations c ON h.user_id=c.owner_id AND h.client_scan_id=c.scan_id)<>1 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage h JOIN internal.initial_analysis_cancellations c ON h.user_id=c.owner_id AND h.client_scan_id=c.scan_id WHERE h.state IS DISTINCT FROM 'released' OR h.settlement_reason IS DISTINCT FROM 'cancelled_before_dispatch' OR h.settled_at IS NULL OR h.settled_at IS DISTINCT FROM h.updated_at) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX523';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(scan_id) FROM internal.initial_analysis_cancellations;END $$;")
    finally:
        failures = []
        # Creation order releases the blocking fixture/actor before waiters.
        if sessions:
            try:
                close_group(list(sessions))
            except Exception as error:
                failures.append(type(error).__name__)
        logs = subprocess.run(
            ['docker', 'logs', '--since', started, qualification.command[3]],
            text=True, capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall(r'ERROR:.*deadlock detected', raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [
                {'waiter': int(a), 'mode': mode, 'lock_object': lock, 'blocker': int(b)}
                for a, mode, lock, b in re.findall(
                    r'Process (\d+) waits for ([A-Za-z]+) on (transaction \d+|relation \d+ of database \d+|tuple \(\d+,\d+\) of relation \d+ of database \d+|virtual transaction \d+/\d+); blocked by process (\d+)', raw)]
            qualification.record['deadlock_root_cause_established'] = False
        qualification.save()
        if failures or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')

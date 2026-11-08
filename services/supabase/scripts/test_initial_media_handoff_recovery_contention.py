"""Public recovery versus private transfer, with actual original-cutoff passage.

Synthetic local fixture only. The SQL scheduling profile is not the bridge's
five-second latency qualification. No clock overrides or physical media I/O.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import time

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, Session
from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_media_handoff_contention import CANCEL, PRIVATE, PROJECTION, TERMINAL, TRANSFER
from test_initial_media_handoff_owners import OPERATIONS

CALLERS = {
    'status': 'public.get_initial_preparation_status(r.owner_id,r.scan_id)',
    'finalize': "public.finalize_initial_preparation(r.owner_id,r.scan_id,repeat('b',64))",
    'create': 'public.create_initial_preparation_intent(r.owner_id,r.scan_id,r.candidate)',
    'execution': "public.get_initial_preparation_execution_status(r.owner_id,r.scan_id,r.media_binding::JSONB->>'assignment_digest')",
}
DENIED = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;v TEXT;failed BOOLEAN:=FALSE;before_state JSONB;BEGIN
SELECT * INTO STRICT r FROM target;SELECT digest INTO STRICT v FROM verification;
before_state:=""" + PROJECTION + """;
BEGIN PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_handoff_expired' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR before_state IS DISTINCT FROM """ + PROJECTION + """
 OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX783';END IF;END $$;"""


def recover(caller, transferred, expired=False, expected_digest=None):
    body = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_state JSONB;cutoff NUMERIC;before_ms NUMERIC;after_ms NUMERIC;BEGIN
SELECT * INTO STRICT r FROM target;before_state:=""" + PROJECTION + ";"
    body += "cutoff:=(r.media_binding::JSONB#>>'{phase_window,cutoffs,transfer}')::NUMERIC;before_ms:=floor(extract(epoch FROM clock_timestamp())*1000);SET LOCAL ROLE service_role;answer:=" + CALLERS[caller] + ";RESET ROLE;after_ms:=floor(extract(epoch FROM clock_timestamp())*1000);"
    if caller == 'execution':
        body += "IF answer IS DISTINCT FROM '{\"version\":2,\"outcome\":\"held\",\"reason\":\"incoherent\",\"authority\":\"none\"}'::JSONB THEN RAISE EXCEPTION USING ERRCODE='ZX780';END IF;"
    elif transferred:
        body += "IF answer IS DISTINCT FROM jsonb_build_object('version',2,'outcome','transferred','authority','none','scan_id',r.scan_id,'admission_receipt_digest',r.receipt_digest,'binding',r.media_binding::JSONB,'transfer_receipt_digest',(SELECT receipt_digest FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id)) THEN RAISE EXCEPTION USING ERRCODE='ZX780';END IF;"
    else:
        body += "IF answer-'phase' IS DISTINCT FROM jsonb_build_object('version',2,'outcome','admitted','authority','none','scan_id',r.scan_id,'admission_receipt_digest',r.receipt_digest,'binding',r.media_binding::JSONB) OR answer->>'phase' IS DISTINCT FROM '" + ('expired' if expired else 'transfer') + "' THEN RAISE EXCEPTION USING ERRCODE='ZX780';END IF;"
    if expired:
        body += "IF after_ms<cutoff THEN RAISE EXCEPTION USING ERRCODE='ZX781';END IF;"
    elif not transferred:
        body += "IF after_ms>=cutoff THEN RAISE EXCEPTION USING ERRCODE='ZX781';END IF;"
    unchanged = 'before_state IS DISTINCT FROM ' + PROJECTION if expected_digest is None else "md5((" + PROJECTION + ")::TEXT) IS DISTINCT FROM '" + expected_digest + "'"
    body += "IF " + unchanged + " OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX782';END IF;END $$;"
    return body


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', "SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();"))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')

    def peer(name):
        s = Session(q, name)
        sessions.append(s)
        q.record.setdefault('backend_correlation', []).append({'session': name, 'pid': s.pid})
        q.save()
        return s

    def blocking(observer, first, second):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                q.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                q.save()
                return
            time.sleep(0.04)
        raise RuntimeError('required transfer/recovery blocking not observed')

    def remaining(observer, scan):
        rows = observer.run('original_cutoff_remaining', "SELECT (media_binding::JSONB#>>'{phase_window,cutoffs,transfer}')::BIGINT-floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "';")
        if len(rows) != 1 or not re.fullmatch('-?[0-9]+', rows[0]):
            raise ValueError('single original cutoff interval required')
        return int(rows[0])

    def wait_until(observer, scan, upper_ms):
        # No saved deadline rewrite. Short observations use the database clock;
        # monotonic wall time separately bounds this local fixture wait.
        deadline = time.monotonic() + 305
        while time.monotonic() < deadline:
            left = remaining(observer, scan)
            if left > 300000:
                raise ValueError('unbounded original fixture cutoff')
            if left <= upper_ms:
                return left
            time.sleep(min(0.5, (left - upper_ms) / 1000))
        raise TimeoutError('original cutoff wait exceeded fixture bound')

    try:
        fixture = AdmissionFixture(q)
        schedules = [(caller, transfer_first, False) for caller in CALLERS for transfer_first in [True, False]]
        schedules += [('status', transfer_first, True) for transfer_first in [True, False]]
        for caller, transfer_first, cutoff_wait in schedules:
            label = caller + ('_transfer_first' if transfer_first else '_recovery_first') + ('_cross_cutoff' if cutoff_wait else '')
            a = fixture.admit_one()
            for name, args, _, _ in OPERATIONS[:-1]:
                q.execute(label + '_prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.execute(label + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            first, second, observer = [peer(label + '_' + x) for x in ['first', 'second', 'observer']]
            if len({s.pid for s in [first, second, observer]}) != 3:
                raise ValueError('distinct race backends required')
            target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM verification)<>1 OR NOT EXISTS(SELECT 1 FROM source_before) OR NOT EXISTS(SELECT 1 FROM media_before) THEN RAISE EXCEPTION USING ERRCODE='ZX784';END IF;END $$;"
            first.run('save_original_identity', BASE + target)
            second.run('save_original_identity', BASE + target)
            first.run('first_operation', TRANSFER if transfer_first else recover(caller, False))
            expected = first.run('transferred_projection', 'SELECT md5((' + PROJECTION + ')::TEXT);')[-1] if transfer_first else None
            if expected is not None and not re.fullmatch('[0-9a-f]{32}', expected):
                raise ValueError('exact transferred projection digest required')
            if cutoff_wait:
                left = wait_until(observer, a.scan_id, 3000)
                if left < 1500:
                    raise ValueError('insufficient original cutoff waiting window')
            second.start('second_operation', recover(caller, True, cutoff_wait, expected) if transfer_first else DENIED if cutoff_wait else TRANSFER)
            blocking(observer, first, second)
            if cutoff_wait:
                before = remaining(observer, a.scan_id)
                if before <= 0:
                    raise ValueError('original cutoff already passed before observed wait')
                after = wait_until(observer, a.scan_id, -50)
                q.record.setdefault('cutoff_crossings', []).append({'case': label, 'observed_wait_before_cutoff_ms': before, 'release_after_cutoff_ms': -after})
                q.save()
            first.run('commit_first', 'COMMIT;')
            second.finish()
            second.run('commit_second', 'COMMIT;')
            # A new transaction observes the durable winner, never a stale
            # response or authority seal retained from either preceding call.
            second.run('final_recovery', 'BEGIN;' + recover('status', transfer_first or not cutoff_wait, cutoff_wait) + 'COMMIT;')
            first.run('actual_c1_cleanup', 'BEGIN;' + CANCEL + TERMINAL + 'COMMIT;')
            for s in [first, second, observer]:
                s.close()
                sessions.remove(s)
            q.execute(label + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.record['checks'].append({'case': label, 'passed': True, 'blocking_observed': True, 'original_cutoff_crossed': cutoff_wait, 'read_only_recovery_verified': True, 'c1_terminal_verified': True})
            q.save()
    finally:
        errors = []
        for s in sessions:
            try:
                s.close()
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        q.execute('restore_inactive', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        logs = subprocess.run(['docker', 'logs', '--since', started, q.command[3]], text=True, capture_output=True)
        count = len(re.findall(r'ERROR:.*deadlock detected', logs.stdout + logs.stderr))
        q.record.update(server_log_read_exit=logs.returncode, deadlock_reports=count, cleanup_errors=errors)
        q.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-recovery-contention', args.replay_manifest)
    for name in [Path(__file__), Path(__file__).with_name('test_initial_media_handoff_contention.py'), Path(__file__).with_name('test_initial_media_handoff_owners.py')]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Four actual public service-role recovery wrappers in both transfer orders, plus two status/transfer schedules crossing the unchanged original transfer cutoff using actual database time. Privileged synthetic private transfer, observed blocking, read-only recovery, exact expired fresh denial and actual C1 cleanup. No clock overrides, physical I/O, installed adapters or five-second bridge/resource qualification.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

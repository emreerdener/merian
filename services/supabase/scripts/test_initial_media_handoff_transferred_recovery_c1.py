"""Public recovery/C1 held-transaction races over durably transferred media.

The six private handoff owners commit before each race. Activation stays disabled
throughout recovery and C1. This is direct contention, not acceptance inferred
from separate transfer/recovery and transfer/C1 schedules.
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
from test_initial_media_handoff_contention import CANCEL, PRIVATE, TERMINAL
from test_initial_media_handoff_owners import OPERATIONS
from test_initial_media_handoff_recovery_contention import CALLERS, recover
from test_initial_media_handoff_scan_contention import FULL, PROJECTION_RELATIONS

RECOVERY_BEFORE = 'CREATE TEMP TABLE recovery_before AS SELECT ' + FULL + ' AS value;'
RECOVERY_AFTER = "DO $$ BEGIN IF (SELECT value FROM recovery_before) IS DISTINCT FROM " + FULL + " OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) THEN RAISE EXCEPTION USING ERRCODE='ZX850';END IF;END $$;"


def denied(caller, expected):
    assert re.fullmatch('[0-9a-f]{32}', expected)
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;
BEGIN SET LOCAL ROLE service_role;answer:=CALL;RESET ROLE;
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_cancelled' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR current_user<>'postgres' OR md5((FULL)::TEXT) IS DISTINCT FROM 'EXPECTED'
 OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout)
 OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX851';END IF;END $$;""".replace('CALL', CALLERS[caller]).replace('FULL', FULL).replace('EXPECTED', expected)


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    q.execute('retirement_comparators_preserve_stable_snapshot', """DO $$ BEGIN
IF (SELECT count(*) FROM pg_proc WHERE oid IN (
 'internal.assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean)'::regprocedure,
 'internal.assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean,jsonb)'::regprocedure)
 AND provolatile='s')<>2 THEN RAISE EXCEPTION USING ERRCODE='ZX852'; END IF;
END $$;""")
    catalog = json.loads(q.execute('exact_private_catalog', 'SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();'))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')
    try:
        fixture = AdmissionFixture(q)
        for caller in CALLERS:
            for c1_first in [False, True]:
                label = caller + ('_c1_first' if c1_first else '_recovery_first')
                a = fixture.admit_one()
                for name, args, _, _ in OPERATIONS:
                    q.execute(label + '_commit_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
                peers = []
                for role in ['first', 'second', 'observer']:
                    s = Session(q, label + '_' + role)
                    sessions.append(s)
                    peers.append(s)
                    q.record.setdefault('backend_correlation', []).append({'session': s.name, 'pid': s.pid})
                first, second, observer = peers
                if len({s.pid for s in peers}) != 3:
                    raise ValueError('distinct backends required')
                target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM target;IF (SELECT count(*) FROM source_before)<>1 OR (SELECT count(*) FROM media_before)<>1 OR (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_transfer_receipts WHERE scan_id=r.scan_id) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id) OR EXISTS(SELECT 1 FROM source_before WHERE NOT retired OR marker_confirmed OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL) OR EXISTS(SELECT 1 FROM media_before WHERE retired OR marker_confirmed OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL) THEN RAISE EXCEPTION USING ERRCODE='ZX852';END IF;PERFORM internal.assert_initial_admission_live_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);END $$;"
                first.run('save_durable_transferred_identity', BASE + target)
                second.run('save_durable_transferred_identity', BASE + target)
                expected = None
                if c1_first:
                    first.run('c1_uncommitted', CANCEL + TERMINAL)
                    rows = first.run('terminal_projection_digest', 'SELECT md5((' + FULL + ')::TEXT);')
                    if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
                        raise ValueError('single terminal digest required')
                    expected = rows[0]
                else:
                    first.run('public_recovery_retains_locks', RECOVERY_BEFORE + recover(caller, True) + RECOVERY_AFTER)
                second.start('second_operation', denied(caller, expected) if c1_first else CANCEL + TERMINAL)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if second.process.poll() is not None:
                        second.finish()
                        raise RuntimeError('waiter exited before blocking')
                    if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                        q.record.setdefault('observed_blockers', []).append({'case': label, 'blocker': first.name, 'waiter': second.name})
                        q.save()
                        break
                    time.sleep(0.04)
                else:
                    raise RuntimeError('required transferred recovery/C1 wait not observed')
                first.run('commit_first', 'COMMIT;')
                second.finish()
                second.run('terminal_and_commit', TERMINAL + "DO $$ BEGIN IF (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) THEN RAISE EXCEPTION USING ERRCODE='ZX853';END IF;END $$;COMMIT;")
                for s in peers:
                    s.close()
                    sessions.remove(s)
                q.record['checks'].append({'case': label, 'passed': True, 'blocking_observed': True, 'actual_service_role_recovery_and_c1': True, 'durable_transfer_precondition': True, 'activation_disabled_during_race': True, 'original_arguments_preserved': True, 'exact_once_refund_terminal': True, 'recovery_full_projection_unchanged': True})
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
            raise RuntimeError('session cleanup or server diagnostics failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-transferred-recovery-c1', args.replay_manifest)
    for name in [Path(__file__), *[Path(__file__).with_name('test_initial_media_handoff_' + suffix + '.py') for suffix in ['contention', 'owners', 'scan_contention', 'recovery_contention']]]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Four actual service-role public recovery routes versus C1 over durably transferred synthetic media, each explicit transaction winner order with observed blocker, exact transferred/execution-held response or cancelled denial, unchanged39relation projection and once-only original accounting/private erasure. Activation disabled throughout races. No physical I/O, installed use or five-second/resource qualification.'
    q.record['projection_relations'] = PROJECTION_RELATIONS
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

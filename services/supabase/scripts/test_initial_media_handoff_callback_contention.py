"""Five pre-transfer fixed handoff owners versus public C1, both winner orders.

Original object and verification token arguments are saved before either actor
runs. A late callback after C1 must reject the same operation, never reconstruct
private proof or renew authority. No physical callback or provider is invoked.
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
from test_initial_media_handoff_scan_contention import FULL, PROJECTION_RELATIONS


def call(index):
    name, args, _, _ = OPERATIONS[index]
    if index == 4:
        args = ',(SELECT token FROM original_claim)'
    return 'internal.' + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ')'


def callback(index):
    _, _, column, table = OPERATIONS[index]
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer RECORD;BEGIN
SELECT * INTO STRICT r FROM target;
SELECT * INTO STRICT answer FROM CALL;
IF answer.response->>'outcome' IS DISTINCT FROM 'admitted' OR answer.response->>'authority' IS DISTINCT FROM 'none'
 OR to_jsonb(answer.COLUMN) IS NULL
 OR to_jsonb(answer.COLUMN) IS DISTINCT FROM (SELECT to_jsonb(t) FROM internal.TABLENAME t WHERE scan_id=r.scan_id)
 OR NOT internal.initial_media_handoff_sealed()
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX840';END IF;
PERFORM internal.assert_initial_media_handoff_chain(r.owner_id,r.scan_id);
PERFORM internal.assert_initial_admission_live_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);
END $$;""".replace('CALL', call(index)).replace('COLUMN', '"' + column + '"').replace('TABLENAME', table)


def denied(index, expected):
    assert re.fullmatch('[0-9a-f]{32}', expected)
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;
BEGIN PERFORM * FROM CALL;
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_cancelled' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR md5((FULL)::TEXT) IS DISTINCT FROM 'EXPECTED'
 OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX841';END IF;END $$;""".replace('CALL', call(index)).replace('FULL', FULL).replace('EXPECTED', expected)


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', 'SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();'))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')
    try:
        fixture = AdmissionFixture(q)
        for index, (name, _, _, _) in enumerate(OPERATIONS[:-1]):
            for c1_first in [False, True]:
                label = name + ('_c1_first' if c1_first else '_callback_first')
                a = fixture.admit_one()
                for prior, args, _, _ in OPERATIONS[:index]:
                    q.execute(label + '_prepare_' + prior, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + prior + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
                q.execute(label + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
                peers = []
                for role in ['first', 'second', 'observer']:
                    s = Session(q, label + '_' + role)
                    sessions.append(s)
                    peers.append(s)
                    q.record.setdefault('backend_correlation', []).append({'session': s.name, 'pid': s.pid})
                first, second, observer = peers
                if len({s.pid for s in peers}) != 3:
                    raise ValueError('distinct backends required')
                target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE original_claim AS SELECT (claim::JSONB->>'claim_token')::UUID AS token FROM internal.initial_media_verification_claims_v2 WHERE scan_id='" + a.scan_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM source_before)<>1 OR (SELECT count(*) FROM media_before)<>1" + (" OR (SELECT count(*) FROM original_claim)<>1 OR (SELECT token FROM original_claim) IS NULL" if index == 4 else '') + " THEN RAISE EXCEPTION USING ERRCODE='ZX842';END IF;END $$;"
                first.run('save_original_arguments', BASE + target)
                second.run('save_original_arguments', BASE + target)
                first.run('first_operation', CANCEL + TERMINAL if c1_first else callback(index))
                expected = None
                if c1_first:
                    rows = first.run('terminal_projection_digest', 'SELECT md5((' + FULL + ')::TEXT);')
                    if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
                        raise ValueError('single terminal digest required')
                    expected = rows[0]
                second.start('second_operation', denied(index, expected) if c1_first else CANCEL + TERMINAL)
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
                    raise RuntimeError('required callback/C1 wait not observed')
                first.run('commit_first', 'COMMIT;')
                second.finish()
                second.run('exact_terminal_and_commit', TERMINAL + 'COMMIT;')
                for s in peers:
                    s.close()
                    sessions.remove(s)
                q.execute(label + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
                q.record['checks'].append({'case': label, 'passed': True, 'blocking_observed': True, 'actual_service_role_c1': True, 'original_callback_arguments_retained': True, 'original_once_refund_and_credit_release': True, 'private_catalog_absent': True, 'denied_callback_full_projection_unchanged': c1_first})
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
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-callback-contention', args.replay_manifest)
    for name in [Path(__file__), *[Path(__file__).with_name('test_initial_media_handoff_' + suffix + '.py') for suffix in ['contention', 'owners', 'scan_contention']]]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Both observed winner orders for five pre-transfer private fixed owners versus actual service-role C1; original object/token preserved across cancellation; exact original once-refund/credit release, 19privatecatalog absence, retired registries, lifecycle/fence and 39relation denied-callback preservation. Synthetic media only; no physical callback/provider, unknown-dispatch refund, installed use or five-second/resource qualification.'
    q.record['projection_relations'] = PROJECTION_RELATIONS
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

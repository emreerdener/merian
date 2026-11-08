"""Public deletion denial over an explicit defensive admitted-scan preimage.

No scan means not_found without mutation. A replica-only same-ID scan is not a
supported initial journey: the effective terminal-failure owner rejects it. The
transfer-first schedule observes the actual public wrapper waiting on its owner
lock, then verifies the entire post-transfer state survived the denial.
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
from test_initial_media_handoff_contention import PRIVATE, TRANSFER
from test_initial_media_handoff_owners import OPERATIONS
from test_initial_media_handoff_scan_contention import (
    FULL, NORMAL_INSERT_DENIED, PRECONDITION, PROJECTION_RELATIONS, projection,
)

WITHOUT_SCAN = projection([r for r in PROJECTION_RELATIONS if r != 'public.scans'])
SEED = """SET LOCAL session_replication_role=replica;
INSERT INTO public.scans(id,user_id,ai_confidence_score) SELECT scan_id,owner_id,0 FROM target;
SET LOCAL session_replication_role=origin;
CREATE TEMP TABLE scan_before AS SELECT * FROM public.scans;
"""
NO_SCAN = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;b JSONB;answer TEXT;BEGIN
SELECT * INTO STRICT r FROM target;b:=FULL;
SET LOCAL ROLE service_role;answer:=public.request_scan_deletion(r.scan_id,r.owner_id);RESET ROLE;
IF answer IS DISTINCT FROM 'not_found' OR b IS DISTINCT FROM FULL
 OR internal.initial_cancellation_sealed() OR internal.initial_media_handoff_sealed()
 OR internal.initial_admission_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX820';END IF;END $$;""".replace('FULL', FULL)


def denied(expected=None):
    comparison = "b IS DISTINCT FROM " + FULL if expected is None else "md5((" + WITHOUT_SCAN + ")::TEXT) IS DISTINCT FROM '" + expected + "' OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.scans t) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM scan_before t)"
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;b JSONB;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;b:=FULL;
BEGIN SET LOCAL ROLE service_role;PERFORM public.request_scan_deletion(r.scan_id,r.owner_id);RESET ROLE;
EXCEPTION WHEN SQLSTATE '55000' THEN
 IF SQLERRM<>'initial_analysis_execution_required' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR current_user<>'postgres' OR COMPARISON
 OR internal.initial_cancellation_sealed() OR internal.initial_media_handoff_sealed()
 OR internal.initial_admission_sealed() OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX821';END IF;END $$;""".replace('FULL', FULL).replace('COMPARISON', comparison)


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', 'SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();'))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')
    try:
        fixture = AdmissionFixture(q)
        a = fixture.admit_one()
        for name, args, _, _ in OPERATIONS[:-1]:
            q.execute('prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        identity = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';"
        q.execute('before_transfer_not_found_and_exact_denial_rollback', BASE + identity + PRECONDITION + NO_SCAN + NORMAL_INSERT_DENIED + SEED + denied() + 'ROLLBACK;')
        q.execute('enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
        for name in ['transfer_holder', 'public_delete_waiter', 'observer']:
            s = Session(q, name)
            sessions.append(s)
            q.record.setdefault('backend_correlation', []).append({'session': name, 'pid': s.pid})
        first, second, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('distinct backends required')
        first.run('save_original_identity', BASE + identity + PRECONDITION)
        second.run('save_original_identity', BASE + identity + PRECONDITION)
        first.run('transfer_uncommitted', TRANSFER)
        rows = first.run('post_transfer_projection_digest', 'SELECT md5((' + WITHOUT_SCAN + ')::TEXT);')
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
            raise ValueError('single projection digest required')
        second.run('explicit_uncommitted_replica_only_preimage', SEED)
        second.start('actual_public_deletion_denied_after_wait', denied(rows[0]))
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if second.process.poll() is not None:
                second.finish()
                raise RuntimeError('waiter exited before blocking')
            if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                q.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                q.save()
                break
            time.sleep(0.04)
        else:
            raise RuntimeError('public deletion owner wait not observed')
        first.run('commit_transfer', 'COMMIT;')
        second.finish()
        second.run('remove_only_replica_fixture_by_rollback', 'ROLLBACK;')
        for s in sessions:
            s.close()
        sessions.clear()
        q.execute('disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        q.execute('after_transfer_not_found_and_exact_denial_rollback', BASE + identity + NO_SCAN + SEED + denied() + 'ROLLBACK;')
        q.record['checks'].append({'case': 'public_delete_denial_boundary', 'passed': True, 'actual_service_role': True, 'blocking_observed': True, 'whole_projection_unchanged_after_denial': True, 'replica_only_scan_rolled_back': True, 'no_scan_not_found_before_and_after_transfer': True})
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
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-public-deletion', args.replay_manifest)
    for name in [Path(__file__), *[Path(__file__).with_name('test_initial_media_handoff_' + suffix + '.py') for suffix in ['contention', 'owners', 'scan_contention']]]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Actual service-role public deletion denial before/after synthetic private transfer, not_found with absent scan, explicit rollback-only replica scan preimage, observed transfer-first owner-lock wait and exact 39-relation preservation. No positive public deletion or supported initial journey, physical I/O, installed use or resource qualification.'
    q.record['projection_relations'] = PROJECTION_RELATIONS
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

"""Real local SQL bridge plus coordinator, with synthetic in-memory media I/O.

Bytes are fixed in the candidate BEFORE admission. No saved operation is
rewritten. This does not qualify media structure, installed artifacts or storage.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE
from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_media_handoff_contention import CANCEL, TERMINAL

PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII='


def cases(q, replay):
    fixed = ROOT / '.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json'
    if Path(replay).read_bytes() != fixed.read_bytes():
        raise ValueError('exact current disposable ownership receipt required')
    data = base64.b64decode(PNG, validate=True)
    assert len(data) == 68 and data[:8] == b'\x89PNG\r\n\x1a\n'
    digest = hashlib.sha256(data).hexdigest()
    fixture = AdmissionFixture(q)
    try:
        # Only the connection-local fresh request vector changes; downstream
        # composers calculate assignment/proof hashes from the new candidate.
        fixture.session.run('bind_actual_bytes_before_admission',
            "DO $$ BEGIN IF (SELECT count(*) FROM media_vectors WHERE i=1)<>1 OR "
            "(SELECT v#>>'{candidate,source_plan,sources,0,source_byte_count}' FROM media_vectors WHERE i=1)<>'68' "
            "THEN RAISE EXCEPTION USING ERRCODE='ZX860';END IF;END $$;"
            "UPDATE media_vectors SET v=jsonb_set(v,'{candidate,source_plan,sources,0,source_sha256}',to_jsonb('" + digest + "'::TEXT)) WHERE i=1;")
        for mode in ['lifecycle', 'cancel_source']:
            a = fixture.admit_one()
            fixture.session.run('retain_original_accounting_' + mode,
                'DROP TABLE IF EXISTS target,source_before,media_before;'
                "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';"
                "CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';"
                "CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';")
            receipt_digest = q.execute('private_identity_' + mode,
                "SELECT receipt_digest FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';")
            q.execute('enable_only_owned_synthetic_database_' + mode,
                'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            try:
                result = subprocess.run([
                    'deno', 'run', '--frozen', '--config', str(ROOT / 'services/supabase/functions/deno.json'),
                    '--allow-run=docker', '--allow-read=' + str(fixed),
                    str(ROOT / 'services/supabase/scripts/initial_media_handoff_coordinator_integration.ts')],
                    input=json.dumps({'mode': mode, 'png': PNG, 'identity': {
                        'owner_id': a.owner_id, 'scan_id': a.scan_id,
                        'admission_receipt_digest': receipt_digest}}),
                    text=True, capture_output=True, timeout=95)
                try:
                    report = json.loads(result.stdout)
                except (ValueError, json.JSONDecodeError):
                    report = {'passed': False}
                allowed = ['passed', 'mode', 'coordinator_ms', 'max_sql_ms', 'sql_calls', 'storage_calls',
                           'aliases', 'destinations', 'no_sql_during_io', 'original_preserved',
                           'late_sql_after_cancel', 'stage', 'last_sql', 'error']
                report = {k: v for k, v in report.items() if k in allowed}
                stderr_present = bool(result.stderr.strip())
                passed = result.returncode == 0 and not stderr_present and report.get('passed') is True and report.get('mode') == mode
                q.record.setdefault('coordinator_runs', []).append({'mode': mode, 'passed': passed,
                    'exit_code': result.returncode, 'stderr_present': stderr_present, 'report': report})
                q.save()
                print(('PASS ' if passed else 'FAIL ') + 'coordinator_' + mode, flush=True)
                if not passed:
                    raise RuntimeError('coordinator qualification failed; sanitized evidence retained')
            finally:
                q.execute('restore_inactive_' + mode,
                    'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            fixture.session.run('actual_c1_and_exact_terminal_' + mode, BASE + CANCEL + TERMINAL + 'COMMIT;')
        q.execute('inactive_no_invocations_or_private_receipts',
            "DO $$ BEGIN IF (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) "
            "OR EXISTS(SELECT 1 FROM internal.identification_invocations) "
            "OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) "
            "OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) "
            "THEN RAISE EXCEPTION USING ERRCODE='ZX861';END IF;END $$;")
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-coordinator', args.replay_manifest)
    files = [Path(__file__), Path(__file__).with_name('test_initial_media_handoff_contention.py'),
             Path(__file__).with_name('initial_media_handoff_bridge.ts'),
             Path(__file__).with_name('initial_media_handoff_coordinator_integration.ts'),
             *(ROOT / 'services/supabase/functions/_shared/initialAnalysis').glob('mediaHandoff*.ts')]
    for f in files:
        q.record['source_manifest'][str(f.resolve().relative_to(ROOT))] = q.digest(f)
    q.record['scope'] = 'One PNG alias cohort, exact bytes bound before admission; actual coordinator plus fixed disposable SQL bridge and synthetic in-memory conditional storage; copy/fullGET verification/original transferred recovery, committed SQL before I/O, caller cancellation with delayed transport and no late SQL. No media-structure, installed signer/backend, whole-cohort resource, provider or activation qualification.'
    q.save()
    cases(q, args.replay_manifest)
    q.finish()


if __name__ == '__main__':
    main()

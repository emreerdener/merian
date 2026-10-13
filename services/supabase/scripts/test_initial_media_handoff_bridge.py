"""Owned local bridge qualification only; no physical I/O or installed adapter.

The fresh owned replay contains synthetic admitted media. Direct fixed writers
are privileged fixture calls, never evidence that fake tuple bytes were read.
"""
import argparse
import json
from pathlib import Path
import subprocess
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_test_support import Qualification, ROOT


def cases(q, replay):
    fixed = ROOT / '.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json'
    if Path(replay).resolve() != fixed.resolve():
        raise ValueError('bridge uses only current checkout ownership receipt')
    fixture = AdmissionFixture(q)
    try:
        for mode in ['lifecycle', 'timeout']:
            a = fixture.admit_one()
            digest = q.execute('private_original_digest_' + mode, "SELECT receipt_digest FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';")
            q.execute('enable_only_synthetic_disposable_' + mode, 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            original_function = None
            try:
                if mode == 'timeout':
                    original_function = q.execute('retain_function_for_timeout_seam', "SELECT pg_get_functiondef('internal.begin_initial_media_copy_v2(uuid,uuid,text)'::REGPROCEDURE);")
                    if original_function.count('BEGIN\n') != 1:
                        raise ValueError('unique timeout seam required')
                    q.execute('install_delay_before_any_domain_mutation', original_function.replace('BEGIN\n', 'BEGIN\nPERFORM pg_catalog.pg_sleep(7);\n', 1))
                result = subprocess.run(['deno', 'run', '--frozen', '--config', str(ROOT / 'services/supabase/functions/deno.json'),
                    '--allow-run=docker', '--allow-read=' + str(fixed), str(ROOT / 'services/supabase/scripts/initial_media_handoff_bridge_integration.ts')],
                    input=json.dumps({'mode': mode, 'identity': {'owner_id':a.owner_id,'scan_id':a.scan_id,'admission_receipt_digest':digest}}),
                    text=True, capture_output=True, timeout=70)
                try:
                    receipt = json.loads(result.stdout)
                except (json.JSONDecodeError, ValueError):
                    receipt = {'passed': False}
                passed = result.returncode == 0 and receipt.get('passed') is True and receipt.get('mode') == mode
                q.record.setdefault('bridge_runs', []).append({'mode':mode,'passed':passed,'exit_code':result.returncode,
                    'checks':receipt.get('checks'), 'max_writer_ms':receipt.get('max_writer_ms'), 'last_writer_ms':receipt.get('last_writer_ms'), 'diagnostic':receipt.get('diagnostic') if receipt.get('diagnostic') in ['unknown','sql_22023','sql_23514','sql_25000','sql_55000','sql_57014','sql_55P03','sql_P0002','process_exit','process_wait','acknowledgement'] else None, 'stage':receipt.get('stage') if receipt.get('stage') in ['input','bridge_setup','initial_state','initial_decode','writer_progress','refresh_progress','writer_claim','refresh_claim','writer_verification','refresh_verification','writer_transfer','refresh_transfer','copy_loader','verification_loader'] else None})
                q.save()
                print(('PASS ' if passed else 'FAIL ') + 'private_bridge_' + mode, flush=True)
                if not passed:
                    raise RuntimeError('bridge qualification failed; sanitized receipt retained')
            finally:
                if original_function is not None:
                    q.execute('restore_exact_begin_owner', original_function)
                q.execute('disable_synthetic_disposable_' + mode, 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            if mode == 'timeout':
                q.execute('timeout_did_not_materialize_progress', "DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.initial_media_copy_progress WHERE scan_id='" + a.scan_id + "') THEN RAISE EXCEPTION USING ERRCODE='ZX760';END IF;END $$;")
            q.execute('actual_c1_' + mode, "BEGIN;SET LOCAL ROLE service_role;SELECT public.cancel_initial_analysis('" + a.owner_id + "','" + a.scan_id + "');COMMIT;")
        q.execute('inactive_no_private_invocations', "DO $$ BEGIN IF (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.identification_invocations) THEN RAISE EXCEPTION USING ERRCODE='ZX761';END IF;END $$;")
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-bridge', args.replay_manifest)
    files = [Path(__file__), *Path(__file__).parent.glob('initial_media_handoff_bridge*.ts'),
        * (ROOT / 'services/supabase/functions/_shared/initialAnalysis').glob('mediaHandoff*.ts')]
    for p in files:
        q.record['source_manifest'][str(p.resolve().relative_to(ROOT))] = q.digest(p)
    q.record['scope'] = 'Real fixed local disposable bridge, nine methods, original typed rows, independent transaction acknowledgement, six writers within 5s, and delayed pre-mutation unknown outcome. Direct synthetic fixture owners; no physical storage, installed signer, provider, hosted or full runtime qualification.'
    q.save()
    cases(q, args.replay_manifest)
    q.finish()


if __name__ == '__main__':
    main()

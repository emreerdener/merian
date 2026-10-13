"""One current-profile maximum transport cohort per fresh owned local replay."""
import argparse
import copy
import json
from pathlib import Path
import resource
import subprocess

from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE
from initial_atomic_admission_test_support import ROOT
from initial_media_handoff_resource_fixture import (
    ResourceQualification, install_before_admission, resource_fixture,
)
from test_initial_media_handoff_contention import CANCEL, TERMINAL
from test_initial_media_handoff_scan_contention import FULL


def cases(q, replay, shape):
    fixed = ROOT / '.artifacts/initial-media-handoff-v2/runtime-implementation/committed-disposable-state.json'
    if Path(replay).read_bytes() != fixed.read_bytes():
        raise ValueError('exact current local disposable ownership receipt required')
    spec = resource_fixture(shape)
    q.resource = spec
    q.record['resource_shape'] = {k: spec[k] for k in ['shape', 'vector', 'input_profile', 'source_count',
        'object_count', 'alias_count', 'unique_bytes', 'specs']}
    q.save()
    candidate_json = json.dumps(spec['candidate'], separators=(',', ':'))
    profile_text = spec['profile_canonical']
    assert '$candidate$' not in candidate_json and '$profile$' not in profile_text
    q.execute('unchanged_profile_accepts_exact_resource_candidate',
        'SELECT internal.assert_initial_media_profile_matches(internal.initial_canonical($candidate$' +
        candidate_json + '$candidate$::JSONB),$profile$' + profile_text + '$profile$);')
    fixture = AdmissionFixture(q)
    try:
        bad = copy.deepcopy(spec['candidate'])
        bad['source_plan']['sources'][0]['source_byte_count'] += 1
        encoded = json.dumps(bad, separators=(',', ':'))
        assert '$bad$' not in encoded
        q.execute('aggregate_image_cap_plus_one_rejected_before_admission_io',
            'DO $$ DECLARE before_image JSONB:=' + FULL + ';failed BOOLEAN:=FALSE;BEGIN '
            'BEGIN PERFORM internal.parse_initial_media_source_candidate(internal.initial_canonical($bad$' + encoded + '$bad$::JSONB));'
            "EXCEPTION WHEN SQLSTATE '22023' THEN IF SQLERRM<>'initial_analysis_input_invalid' THEN RAISE;END IF;failed:=TRUE;END;"
            'IF NOT failed OR before_image IS DISTINCT FROM ' + FULL +
            " THEN RAISE EXCEPTION USING ERRCODE='ZX873';END IF;END $$;")
        install_before_admission(fixture, spec)
        a = fixture.admit_one()
        fixture.session.run('retain_original_terminal_images',
            "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';"
            "CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';"
            "CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';"
            "DO $$ BEGIN IF (SELECT count(*) FROM source_before)<>" + str(spec['object_count']) +
            " OR (SELECT count(*) FROM media_before)<>" + str(spec['object_count']) +
            " THEN RAISE EXCEPTION USING ERRCODE='ZX871';END IF;END $$;")
        digest = q.execute('private_original_identity',
            "SELECT receipt_digest FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';")
        q.execute('enable_only_owned_synthetic_database',
            'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
        try:
            payload = {k: spec[k] for k in ['shape', 'source_count', 'object_count', 'alias_count', 'unique_bytes', 'specs']}
            payload['identity'] = {'owner_id': a.owner_id, 'scan_id': a.scan_id, 'admission_receipt_digest': digest}
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            result = subprocess.run(['deno', 'run', '--frozen', '--config', str(ROOT / 'services/supabase/functions/deno.json'),
                '--allow-run=docker', '--allow-read=' + str(fixed),
                str(ROOT / 'services/supabase/scripts/initial_media_handoff_resource_integration.ts')],
                input=json.dumps(payload), text=True, capture_output=True, timeout=95)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            try:
                report = json.loads(result.stdout)
            except (ValueError, json.JSONDecodeError):
                report = {'passed': False}
            allowed = ['passed', 'shape', 'coordinator_ms', 'source_aliases', 'destinations', 'unique_bytes',
                'sql_calls', 'storage_operations', 'baseline', 'peak', 'no_sql_during_io',
                'outcome', 'recovered', 'error', 'stage']
            report = {k: v for k, v in report.items() if k in allowed}
            stderr_present = bool(result.stderr.strip())
            passed = result.returncode == 0 and not stderr_present and report.get('passed') is True and report.get('shape') == shape
            q.record['resource_run'] = {'passed': passed, 'exit_code': result.returncode,
                'stderr_present': stderr_present, 'report': report,
                'local_child_user_cpu_seconds': after.ru_utime - before.ru_utime,
                'local_child_system_cpu_seconds': after.ru_stime - before.ru_stime,
                'measurement_limits': 'CPU includes local Deno/transport children, not database container CPU. Memory samples include in-memory storage fixture and are observations, not a handoff heap budget or proof of absolute peak.'}
            q.save()
            print(('PASS ' if passed else 'FAIL ') + 'resource_' + shape, flush=True)
            if not passed:
                raise RuntimeError('whole-cohort qualification failed; retain original outcome/evidence, never retry writes')
        finally:
            q.execute('restore_inactive', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        fixture.session.run('actual_c1_exact_original_terminal', BASE + CANCEL + TERMINAL + 'COMMIT;')
        q.execute('inactive_no_invocations_or_private_receipts',
            "DO $$ BEGIN IF (SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout) "
            "OR EXISTS(SELECT 1 FROM internal.identification_invocations) "
            "OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) "
            "OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) "
            "THEN RAISE EXCEPTION USING ERRCODE='ZX872';END IF;END $$;")
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--shape', choices=['photo_audio', 'photo_audio_images', 'video_audio'], required=True)
    args = parser.parse_args()
    q = ResourceQualification(args.container, args.evidence_directory, 'initial-media-handoff-resources-' + args.shape, args.replay_manifest)
    files = [Path(__file__), Path(__file__).with_name('initial_media_handoff_resource_fixture.py'),
        Path(__file__).with_name('initial_media_handoff_resource_integration.ts'),
        Path(__file__).with_name('initial_media_handoff_bridge.ts'),
        Path(__file__).with_name('test_initial_media_handoff_contention.py'),
        Path(__file__).with_name('test_initial_media_handoff_scan_contention.py'),
        *(ROOT / 'services/supabase/functions/_shared/initialAnalysis').glob('mediaHandoff*.ts')]
    for f in files:
        q.record['source_manifest'][str(f.resolve().relative_to(ROOT))] = q.digest(f)
    q.record['scope'] = 'Current allocated local test profile maximum cardinality/byte synthetic transport cohort through actual coordinator and disposable SQL bridge. Original admission bytes and phase cutoffs preserved. Positive acceptance requires durable transfer; bounded unresolved is failure evidence only. Observed local CPU/memory is not a numeric handoff budget, media structural/transform validation or installed/backend qualification.'
    q.save()
    cases(q, args.replay_manifest, args.shape)
    q.finish()


if __name__ == '__main__':
    main()

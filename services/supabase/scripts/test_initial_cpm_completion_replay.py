"""Concurrent CPM completion replay on a fresh owned disposable database.

Synthetic SQL byte proof only. The waiting replay supplies no new proof and
must return the first committed projection without changing retained state.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from initial_invocation_erasure_races import wait_for_blocker
from test_initial_cpm_completion import initialize
from test_initial_completion_preparation import SNAPSHOT
from test_initial_dispatch import ROLE


MEDIA_SNAPSHOT = """
SELECT encode(extensions.digest(convert_to(jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY scan_id) FROM internal.initial_preparation_transfer_receipts t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_cpm_photo_write_attempts t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY scan_id) FROM internal.initial_cpm_photo_capacity_reservations t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY scan_id) FROM internal.initial_analysis_preparation_intents t)
)::TEXT,'UTF8'),'sha256'),'hex');
"""


def verify_documents(q):
    documents = q.execute('original_completion_documents_in_memory', """
SELECT jsonb_build_array(receipt_snapshot,completion_projection_snapshot)
FROM internal.initial_analysis_completions;
""")
    result = subprocess.run([
        'deno', 'run', '--frozen', '--config',
        str(ROOT / 'services/supabase/functions/deno.json'),
        str(Path(__file__).with_name('validate_initial_completion_documents.ts')),
    ], input=documents, text=True, capture_output=True, cwd=ROOT)
    passed = result.returncode == 0 and result.stdout.strip() == '{"passed":true}'
    q.record['completion_documents_cross_language'] = {'passed': passed, 'exit_code': result.returncode}
    q.save()
    if not passed:
        raise ValueError('completion document decoder rejected original SQL output')

def run(q):
    initialize(q)
    q.record.update(passed=False, scope=__doc__)
    for path in [Path(__file__), Path(__file__).with_name('test_initial_completion_preparation.py'),
                 Path(__file__).with_name('initial_invocation_erasure_races.py'),
                 Path(__file__).with_name('validate_initial_completion_documents.ts'),
                 ROOT / 'services/supabase/functions/_shared/initialAnalysis/completionContract.ts',
                 ROOT / 'services/supabase/functions/_shared/initialAnalysis/completion-schema-v1.json']:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    sessions = []
    try:
        for name in ['first', 'replay', 'observer']:
            sessions.append(Session(q, 'cpm_completion_' + name))
        first, replay, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('three distinct backends required')
        first.run('first_completion_uncommitted', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete();')
        replay.start('proofless_replay_waits_for_completion', 'BEGIN;' + ROLE + 'SELECT public.test_cpm_complete(TRUE);')
        wait_for_blocker(observer, replay, first)
        first.run('commit_original_completion', 'COMMIT;')
        replay.finish()
        original = q.execute('original_completion_before_replay_commit', SNAPSHOT)
        media = q.execute('original_media_before_replay_commit', MEDIA_SNAPSHOT)
        replay.run('commit_exact_replay', 'COMMIT;')
        if q.execute('completion_after_replay_commit', SNAPSHOT) != original:
            raise ValueError('replay changed original completion or funding')
        if q.execute('media_after_replay_commit', MEDIA_SNAPSHOT) != media:
            raise ValueError('replay changed original media or retained capacity')
        q.execute('single_completion_settlement_and_adoption', """
DO $$ DECLARE a internal.initial_analysis_admissions; BEGIN
 SELECT * INTO STRICT a FROM internal.initial_analysis_admissions;
 IF (SELECT count(*) FROM internal.initial_analysis_completions)<>1
  OR (SELECT count(*) FROM internal.initial_preparation_transfer_receipts)<>1
  OR (SELECT count(*) FROM public.scans)<>1
  OR (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='consumed')<>1
  OR (SELECT count(*) FROM internal.identification_invocations)<>1
  OR EXISTS(SELECT 1 FROM internal.initial_consuming_staging)
 THEN RAISE EXCEPTION USING ERRCODE='ZX855'; END IF;
 PERFORM internal.assert_initial_cpm_completed_v1(a.owner_id,a.scan_id);
END $$;
""")
        verify_documents(q)
        q.record.update(passed=True, exact_blocker_observed=True)
    finally:
        for session in sessions:
            session.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--container', required=True)
    p.add_argument('--evidence-directory', required=True)
    p.add_argument('--replay-manifest', required=True)
    a = p.parse_args()
    start = time.monotonic()
    q = Qualification(a.container, a.evidence_directory, 'initial-cpm-completion-replay', a.replay_manifest)
    run(q)
    q.record['wall_seconds'] = time.monotonic() - start
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks']), 'session_commands': len(q.record.get('session_commands', []))}))


if __name__ == '__main__':
    main()

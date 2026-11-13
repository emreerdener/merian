"""Both-order CPM completion/C1 schedules on fresh owned local databases.

Uses actual completion and cancellation owners with synthetic byte proof only.
No physical IO, hosted mutation or native qualification.
"""
import argparse
import json
from pathlib import Path
import time

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from initial_invocation_erasure_races import wait_for_blocker
from initial_completion_journey_races import ARGS, FIXTURE
from test_initial_cpm_completion import initialize
from test_initial_cpm_adoption_erasure import install_report
from test_initial_completion_preparation import SNAPSHOT
from test_initial_dispatch import ROLE


def run(q, order):
    initialize(q)
    install_report(q)
    q.record.update(passed=False, scope=__doc__, completion_c1_order=order)
    for path in [Path(__file__), Path(__file__).with_name('initial_completion_journey_races.py'),
                 Path(__file__).with_name('test_initial_cpm_adoption_erasure.py')]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.save()
    original = 'reply:=internal.complete_initial_analysis_legacy_v1(a.owner_id,a.scan_id,a.submission_digest,a.result_evidence_id,a.result_digest);'
    if FIXTURE.count(original) != 1:
        raise ValueError('unique existing completion call required')
    fixture = FIXTURE.replace(original, "PERFORM public.test_cpm_complete(); reply:='{\"outcome\":\"fresh\"}'::JSONB;")
    q.execute('install_cpm_c1_race_adapter', fixture)
    funding_snapshot = "SELECT encode(extensions.digest(convert_to(COALESCE(jsonb_agg(to_jsonb(h) ORDER BY client_scan_id),'[]'::JSONB)::TEXT,'UTF8'),'sha256'),'hex') FROM internal.complimentary_scan_usage h;"
    original_funding = q.execute('original_cpm_funding', funding_snapshot)
    sessions = []
    try:
        for name in ['completion', 'cancellation', 'observer']:
            sessions.append(Session(q, 'cpm_c1_' + name))
        completion, cancellation, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('three distinct backends required')
        for session in sessions:
            session.run('capture_original_arguments', ARGS)
        if order == 'completion':
            completion.run('completed_before_c1', 'BEGIN;' + ROLE + 'SELECT public.test_completion_race(FALSE);')
            cancellation.start('c1_waits_for_adoption', 'BEGIN;' + ROLE + 'SELECT public.test_cancel_completion_race(TRUE);')
            wait_for_blocker(observer, cancellation, completion)
            completion.run('commit_adoption_first', 'COMMIT;')
            cancellation.finish()
            before = q.execute('completed_before_c1_denial', SNAPSHOT)
            cancellation.run('commit_c1_denial', 'COMMIT;')
        else:
            cancellation.run('c1_before_adoption', 'BEGIN;' + ROLE + 'SELECT public.test_cancel_completion_race(FALSE);')
            completion.start('adoption_waits_for_c1', 'BEGIN;' + ROLE + 'SELECT public.test_completion_race(TRUE);')
            wait_for_blocker(observer, completion, cancellation)
            cancellation.run('commit_c1_first', 'COMMIT;')
            completion.finish()
            before = q.execute('cancelled_before_adoption_denial', SNAPSHOT)
            completion.run('commit_adoption_denial', 'COMMIT;')
        if q.execute('losing_operation_preserves_original', SNAPSHOT) != before:
            raise ValueError('losing operation changed original state')
        counts = q.execute('cpm_c1_terminal_counts', """
SELECT (SELECT count(*) FROM public.scans),
 (SELECT count(*) FROM internal.initial_analysis_completions),
 (SELECT count(*) FROM internal.initial_analysis_cancellations),
 (SELECT count(*) FROM internal.initial_preparation_transfer_receipts),
 (SELECT count(*) FROM internal.initial_consuming_staging),
 (SELECT count(*) FROM internal.identification_invocations),
 (SELECT count(*) FROM public.ai_usage_events),
 (SELECT count(*) FROM internal.complimentary_scan_usage WHERE state='consumed'),
 (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id='00000000-0000-4000-8000-00000000f101' AND NOT retired);
""")
        if counts != ('1|1|0|1|0|1|1|1|3' if order == 'completion' else '0|0|1|0|0|1|1|0|0'):
            raise ValueError('CPM C1 terminal counts differ')
        if order == 'cancellation' and q.execute('c1_preserves_original_funding', funding_snapshot) != original_funding:
            raise ValueError('post-dispatch cancellation changed original funding')
        q.record['exact_blocker_observed'] = True
        q.record['passed'] = True
    finally:
        for session in sessions:
            session.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--order', choices=['completion', 'cancellation'], required=True)
    args = parser.parse_args()
    start = time.monotonic()
    q = Qualification(args.container, args.evidence_directory, 'initial-cpm-adoption-race', args.replay_manifest)
    run(q, args.order)
    q.record['wall_seconds'] = time.monotonic() - start
    q.save()
    print(json.dumps({'passed': True, 'checks': len(q.record['checks']), 'session_commands': len(q.record.get('session_commands', []))}))


if __name__ == '__main__':
    main()

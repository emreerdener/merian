"""Fresh disposable CPM invocation identity schedules; no signer or network IO.

Run after catalog tests on an owned fresh replay, then dispose that database.
The only fresh result allowed to reach a future signer is a committed one.
"""
import argparse
import hashlib
from pathlib import Path
import re
import sys
import time
import uuid

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session
from test_initial_cpm_photo_capacity import TEST, FIXTURE, create, expect_denied, finish_sessions
from test_initial_cpm_photo_write_holds import blocked


def run(q):
    for source in (TEST, FIXTURE, Path(__file__), Path(__file__).with_name('test_initial_cpm_photo_capacity.py'),
                   Path(__file__).with_name('test_initial_cpm_photo_write_holds.py')):
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    q.record['scope'] = 'Fresh-only service transition and nontransition status: concurrent commit/replay, rollback, cancellation, fail-fast capacity. No signer or hosted qualification.'
    source = TEST.read_text()
    marker = 'CREATE TEMP TABLE cpm_saved AS'
    policy_marker = 'CREATE TEMP TABLE closure_policy AS'
    if source.count(marker) != 1 or source.count(policy_marker) != 1:
        raise ValueError('unique synthetic fixture boundaries required')
    setup = source.split(marker)[0]
    setup += policy_marker + source.split(policy_marker)[1].split('FROM closure_policy;')[0] + 'FROM closure_policy;\n'
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(5)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
    setup += 'COMMIT;'
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    q.save()
    sessions = []
    started = time.monotonic()
    try:
        seeded = q.execute('synthetic_issuance_cohorts', setup)
        if re.search(r'^(not ok|Bail out!)', seeded, re.M):
            raise RuntimeError('synthetic fixture assertion failed')
        for name in ('issuer', 'contender', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        calls = []
        status_calls = []
        for owner, scan in identities:
            identity = observer.run('capture_role_identity', f"SELECT assignment_digest||':'||object_id FROM internal.initial_analysis_preparation_intents JOIN internal.initial_cpm_photo_role_mapping USING(scan_id) WHERE scan_id='{scan}' AND role='source';")[-1]
            digest, object_id = identity.split(':')
            calls.append(f"public.begin_initial_cpm_photo_write('{owner}','{scan}','{digest}','{object_id}',(SELECT digest FROM internal.initial_cpm_photo_write_policies))")
            status_calls.append(f"public.read_initial_cpm_photo_write_status('{owner}','{scan}','{digest}','{object_id}')")
        begin = "BEGIN; DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
        if actor.run('first_fresh_uncommitted', begin + f"SELECT {calls[0]}->>'outcome';") != ['fresh']:
            raise RuntimeError('initial invocation was not fresh')
        contender.run('other_owner_fails_fast', begin + expect_denied(calls[1], 'initial_analysis_scope_busy') + 'COMMIT;')
        contender.start('duplicate_waits_for_commit', begin + f"SELECT {calls[0]}->>'outcome';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_before_signer', 'COMMIT;')
        if contender.finish() != ['held']:
            raise RuntimeError('duplicate obtained fresh authority')
        if observer.run('lost_ack_replay_is_held', begin + f"SELECT {calls[0]}->>'outcome';COMMIT;") != ['held']:
            raise RuntimeError('lost acknowledgement renewed authority')

        if actor.run('fresh_to_rollback', begin + f"SELECT {calls[1]}->>'outcome';") != ['fresh']:
            raise RuntimeError('rollback fixture not fresh')
        contender.start('wait_for_rollback', begin + f"SELECT {calls[1]}->>'outcome';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('rollback_no_signer_allowed', 'ROLLBACK;')
        if contender.finish() != ['fresh']:
            raise RuntimeError('rolled back invocation prevented first committed transition')
        if observer.run('rollback_winner_replays_held', begin + f"SELECT {calls[1]}->>'outcome';COMMIT;") != ['held']:
            raise RuntimeError('committed rollback winner can sign twice')

        owner, scan = identities[2]
        actor.run('cancel_uncommitted', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        contender.start('fresh_waits_for_cancel', begin + expect_denied(calls[2], 'initial_analysis_cancelled') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_cancellation', 'COMMIT;')
        contender.finish()
        if observer.run('cancelled_role_never_issued', f"SELECT NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}') AND state='released' FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('cancelled role gained issuance liability')
        owner, scan = identities[3]
        if actor.run('fresh_before_cancellation', begin + f"SELECT {calls[3]}->>'outcome';") != ['fresh']:
            raise RuntimeError('issuance-first fixture not fresh')
        contender.start('cancellation_waits_for_fresh', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_fresh_before_retirement', 'COMMIT;')
        contender.finish()
        if observer.run('retirement_keeps_issued_liability', f"SELECT internal.initial_cpm_photo_retired_write_hold('{scan}') AND EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts w JOIN internal.initial_preparation_source_registry r USING(object_id) WHERE w.scan_id='{scan}' AND w.retired AND r.retired AND w.state='may_have_issued');") != ['t']:
            raise RuntimeError('retirement erased committed issuance liability')
        observer.run('retired_replay_cannot_be_fresh', begin + expect_denied(calls[3], 'initial_analysis_cancelled') + 'COMMIT;')
        # Observation must serialize with issuance/cancellation without becoming
        # a replacement begin. The same object is observed across rollback and
        # commit, proving absence is not turned into a new attempt.
        actor.run('status_begin_to_rollback', begin + f"SELECT {calls[4]}->>'outcome';")
        contender.start('status_waits_for_rollback', begin + f"SELECT {status_calls[4]}->'attempt' IS NULL OR {status_calls[4]}->'attempt'='null'::jsonb;COMMIT;")
        blocked(observer, actor, contender)
        actor.run('status_rollback', 'ROLLBACK;')
        if contender.finish() != ['t']:
            raise RuntimeError('status created or recovered a rolled-back attempt')
        actor.run('status_begin_to_commit', begin + f"SELECT {calls[4]}->>'outcome';")
        contender.start('status_waits_for_commit', begin + f"SELECT {status_calls[4]}#>>'{{attempt,state}}';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('status_commit', 'COMMIT;')
        if contender.finish() != ['may_have_issued']:
            raise RuntimeError('status failed to observe committed attempt')
        first = observer.run('status_original_projection', begin + f"SELECT {status_calls[4]};COMMIT;")
        if observer.run('status_repeat_projection', begin + f"SELECT {status_calls[4]};COMMIT;") != first:
            raise RuntimeError('status changed the original projection')
        owner, scan = identities[4]
        actor.run('status_cancel_uncommitted', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        contender.start('status_waits_for_cancellation', begin + expect_denied(status_calls[4], 'initial_analysis_cancelled') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('status_cancel_commit', 'COMMIT;')
        contender.finish()
        if observer.run('no_funding_or_invocation', 'SELECT NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations);') != ['t']:
            raise RuntimeError('issuance bookkeeping funded execution')
    finally:
        finish_sessions(q, list(reversed(sessions)), sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - started
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-fresh-issuance', args.replay_manifest))

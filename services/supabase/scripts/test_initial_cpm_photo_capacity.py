"""Fresh disposable CPM allocation tests and deterministic last-slot contention.

No provisioning, external IO, credentials, provider execution or activation of a
real deployment. The caller must dispose the named owned database after this run,
including failure. Fixture profiles and users are synthetic local-only values.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time
import uuid

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session

TEST = ROOT / 'services/supabase/tests/initial_cpm_photo_intents.sql'
FIXTURE = ROOT / 'services/supabase/functions/_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json'


def candidate(scan):
    value = json.loads(FIXTURE.read_text())['candidate']
    content = json.loads(value['content_canonical'])
    content['scan_id'] = scan
    canonical = lambda v: json.dumps(v, sort_keys=True, ensure_ascii=False, separators=(',', ':'))
    value['content_canonical'] = canonical(content)
    return canonical(value)


def create(owner, scan):
    # Synthetic JSON only; quote as an SQL string, never interpolate shell text.
    wire = candidate(scan).replace("'", "''")
    return f"public.create_initial_preparation_intent('{owner}','{scan}','{wire}')"


def expect_denied(expression, message):
    return f"""DO $denied$ BEGIN
 BEGIN PERFORM {expression};
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM='{message}' THEN RETURN; END IF; RAISE;
 END;
 RAISE EXCEPTION 'expected closed refusal was absent' USING ERRCODE='ZX601';
END; $denied$;"""


def finish_sessions(q, sessions, primary_error):
    """Attempt every owned closure and bounded gate restoration on all paths."""
    failures = []
    for session in reversed(sessions):
        try:
            session.close()
        except BaseException as error:
            failures.append({'phase': 'session_close', 'session': session.name,
                             'error_category': type(error).__name__})
    try:
        q.execute('restore_local_fixture_gate',
                  "SET lock_timeout='2s'; SET statement_timeout='5s'; "
                  'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
    except BaseException as error:
        failures.append({'phase': 'gate_restore', 'error_category': type(error).__name__})
    q.record['cleanup_failures'] = failures
    try:
        q.save()
    except BaseException as error:
        failures.append({'phase': 'cleanup_receipt', 'error_category': type(error).__name__})
    if failures and primary_error is None:
        raise RuntimeError('CPM qualification cleanup failed; no passing receipt')
    # When the test already failed, its exception remains active in the caller's
    # finally block. Never replace it with a secondary cleanup error.


def run(q):
    for source in (TEST, FIXTURE, Path(__file__)):
        q.record['source_manifest'][str(source.resolve().relative_to(ROOT))] = q.digest(source)
    q.record['scope'] = ('Fresh local synthetic CPM allocation/recovery/erasure and two distinct-owner '
                         'last-slot transactions. No installed, byte IO, provider or native qualification.')
    q.save()
    start = time.monotonic()
    source = TEST.read_text()
    tap = q.execute('cpm_intent_pgtap', source)
    (q.path.parent / (q.path.stem + '.tap')).write_text(tap + '\n')
    ok = re.findall(r'^ok (\d+)(?: |$)', tap, re.M)
    plan = re.findall(r'^1\.\.(\d+)$', tap, re.M)
    q.record['tap_assertions'] = len(ok)
    q.record['tap_sha256'] = hashlib.sha256(tap.encode()).hexdigest()
    q.save()
    if (re.search(r'^(not ok|Bail out!)', tap, re.M) or len(plan) != 1
            or int(plan[0]) != len(ok) or not ok
            or list(map(int, ok)) != list(range(1, len(ok) + 1))):
        raise RuntimeError('incomplete/failing TAP evidence retained')

    # Same qualification run, after the pgTAP transaction rolled back. Keep the
    # helper session alive only while building synthetic committed catalog rows.
    marker = 'CREATE TEMP TABLE cpm_saved AS'
    if source.count(marker) != 1:
        raise ValueError('unique CPM fixture boundary required')
    setup = source.split(marker)[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(17)]
    q.record['contention_identity_count'] = len(identities)
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');\n"
    for owner, scan in identities[:15]:
        setup += f"SELECT {create(owner, scan)}->>'outcome';\n"
    setup += 'COMMIT;'
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    sessions = []
    try:
        seeded = q.execute('fifteen_pending_cross_owner_fixture', setup)
        if re.search(r'^(not ok|Bail out!)', seeded, re.M):
            raise RuntimeError('synthetic setup assertion failed')
        for name in ('last_slot', 'contender', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        begin = "BEGIN; SELECT set_config('request.jwt.claim.role','service_role',TRUE);"
        owner_a, scan_a = identities[15]
        owner_b, scan_b = identities[16]
        actor.run('allocate_last_slot_uncommitted', begin + f"SELECT {create(owner_a, scan_a)}->>'outcome';")
        contender.run('competing_owner_fails_fast', begin + expect_denied(create(owner_b, scan_b), 'initial_analysis_scope_busy') + 'COMMIT;')
        actor.run('commit_sixteenth_slot', 'COMMIT;')
        contender.run('committed_limit_refuses_seventeenth', begin + expect_denied(create(owner_b, scan_b), 'initial_analysis_capacity_unavailable') + 'COMMIT;')
        result = observer.run('no_partial_contender_claim', f"""SELECT
 (SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending')=16
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id='{scan_b}')
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id='{scan_b}')
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id='{scan_b}');""")
        if result != ['t']:
            raise RuntimeError('contention left partial allocation or exceeded cap')
        actor.run('retire_never_issued_last_slot', begin + f"SELECT public.cancel_initial_analysis('{owner_a}','{scan_a}')->>'dispatch';COMMIT;")
        contender.run('reuse_proved_released_capacity', begin + f"SELECT {create(owner_b, scan_b)}->>'outcome';COMMIT;")
        result = observer.run('final_capacity_and_no_funding', """SELECT
 (SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='pending')=16
 AND (SELECT count(*) FROM internal.initial_cpm_photo_capacity_reservations WHERE state='released')=1
 AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_execution_grants);""")
        if result != ['t']:
            raise RuntimeError('capacity or no-funding invariant failed')
    finally:
        finish_sessions(q, sessions, sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - start
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-photo-capacity', args.replay_manifest))

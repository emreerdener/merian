"""Owned disposable CPM write/cancellation schedules; no signer or external IO.

Requires the exact fresh replay receipt. Run catalogs before this committing
suite, then dispose the owned database on success or failure. Evidence contains
only hashes, phase names, timing and SQLSTATE categories.
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


def write(owner, scan, action):
    return (f"internal.initial_cpm_photo_write_action('{action}','{owner}','{scan}',"
            f"(SELECT assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}'),"
            f"(SELECT object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='{scan}' AND role='source'))")


def blocked(observer, actor, contender):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if observer.run('observe_owner_wait', f'SELECT {actor.pid}=ANY(pg_blocking_pids({contender.pid}));') == ['t']:
            return
        time.sleep(0.05)
    raise RuntimeError('expected owner serialization was not observed')


def run(q):
    for source in (TEST, FIXTURE, Path(__file__), Path(__file__).with_name('test_initial_cpm_photo_capacity.py')):
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    q.record['scope'] = 'Inactive SQL bookkeeping only: issuance/cancel commit orders, rollback, fail-fast cross-owner capacity. No actual write, closure, installed or app journey proof.'
    source = TEST.read_text()
    marker = 'CREATE TEMP TABLE cpm_saved AS'
    if source.count(marker) != 1:
        raise ValueError('unique synthetic fixture boundary required')
    setup = source.split(marker)[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(5)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
        if (owner, scan) != identities[-1]:
            setup += f"SELECT ({write(owner, scan, 'bind')}).state;\n"
    setup += 'COMMIT;'
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    q.save()
    sessions = []
    started = time.monotonic()
    try:
        seeded = q.execute('synthetic_bound_roles', setup)
        if re.search(r'^(not ok|Bail out!)', seeded, re.M):
            raise RuntimeError('synthetic fixture assertion failed')
        for name in ('issuer', 'canceller', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        begin = "BEGIN; DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
        owner, scan = identities[0]
        actor.run('issuance_uncommitted', begin + f"SELECT ({write(owner, scan, 'may_have_issued')}).state;")
        other_owner, other_scan = identities[1]
        contender.run('other_owner_capacity_fails_fast', begin + expect_denied(write(other_owner, other_scan, 'may_have_issued'), 'initial_analysis_scope_busy') + 'COMMIT;')
        contender.start('cancel_waits_for_issuance', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_uncertain_issuance', 'COMMIT;')
        contender.finish()
        if observer.run('committed_issuance_retains_hold', f"SELECT internal.initial_cpm_photo_retired_write_hold('{scan}');") != ['t']:
            raise RuntimeError('committed issuance lost liability')

        owner, scan = identities[1]
        actor.run('cancel_uncommitted', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        # Preserve exact pre-cancellation inputs for the contender; subquery
        # recovery after erasure must not manufacture a missing-input refusal.
        attempt = observer.run('capture_bound_identity', f"SELECT assignment_digest||':'||object_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}';")[-1]
        digest, object_id = attempt.split(':')
        expression = f"internal.initial_cpm_photo_write_action('may_have_issued','{owner}','{scan}','{digest}','{object_id}')"
        contender.start('issuance_waits_for_cancel', begin + expect_denied(expression, 'initial_analysis_cancelled') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_retirement', 'COMMIT;')
        contender.finish()
        if observer.run('cancelled_bound_role_released', f"SELECT state='released' AND write_capability_state='never_issued' FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('never-issued retirement failed')

        owner, scan = identities[2]
        actor.run('issuance_to_rollback', begin + f"SELECT ({write(owner, scan, 'may_have_issued')}).state;")
        contender.start('cancel_waits_for_rollback', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('rollback_before_any_signer', 'ROLLBACK;')
        contender.finish()
        if observer.run('rollback_restores_never_issued', f"SELECT c.state='released' AND c.write_capability_state='never_issued' AND w.state='bound' AND w.retired FROM internal.initial_cpm_photo_capacity_reservations c JOIN internal.initial_cpm_photo_write_attempts w USING(scan_id) WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('rollback left partial write state')

        owner, scan = identities[3]
        actor.run('issuance_before_account_delete', begin + f"SELECT ({write(owner, scan, 'may_have_issued')}).state;")
        contender.start('account_delete_waits', begin + f"DELETE FROM public.users WHERE id='{owner}';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_before_account_delete', 'COMMIT;')
        contender.finish()
        if observer.run('account_delete_retains_detached_liability', f"SELECT internal.initial_cpm_photo_retired_write_hold('{scan}') AND owner_id IS NULL FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('account deletion lost liability')
        owner, scan = identities[4]
        actor.run('raw_insert_retirement_uncommitted', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        raw_insert = f"""INSERT INTO internal.initial_cpm_photo_write_attempts(scan_id,object_id,assignment_digest,
 backend_generation,backend_configuration_digest,created_at,admission_expires_at,capability_expires_at)
 SELECT s.scan_id,r.object_id,s.assignment_digest,r.backend_generation,b.configuration_digest,
 date_trunc('milliseconds',clock_timestamp()),s.expires_at,
 LEAST(s.expires_at,date_trunc('milliseconds',clock_timestamp())+INTERVAL '10 minutes')
 FROM internal.initial_analysis_preparation_intents s JOIN internal.initial_cpm_photo_role_mapping m USING(scan_id)
 JOIN internal.initial_preparation_source_registry r USING(scan_id,object_id)
 JOIN internal.initial_preparation_source_backends b ON b.generation=r.backend_generation
 WHERE s.scan_id='{scan}' AND m.role='source';"""
        # Cancellation owns capacity before its registry retirement sweep.
        # Raw INSERT must fail fast, before the permanent-registry FK can wait.
        contender.run('raw_insert_cannot_miss_retirement_sweep', begin + """DO $denied$ BEGIN
 BEGIN """ + raw_insert + """
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM='initial_analysis_scope_busy' THEN RETURN; END IF; RAISE;
 END;
 RAISE EXCEPTION 'raw insertion escaped retirement serialization' USING ERRCODE='ZX602';
 END; $denied$; COMMIT;""")
        actor.run('commit_before_raw_retry', 'COMMIT;')
        if observer.run('no_attempt_survives_released_retirement', f"SELECT NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}') AND state='released' FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('raw insertion missed retirement sweep')
        if observer.run('no_funding_or_invocation', "SELECT NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations);") != ['t']:
            raise RuntimeError('metadata funded execution')
    finally:
        # Actor first: release any held lock before awaiting blocked contender.
        finish_sessions(q, list(reversed(sessions)), sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - started
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-write-holds', args.replay_manifest))

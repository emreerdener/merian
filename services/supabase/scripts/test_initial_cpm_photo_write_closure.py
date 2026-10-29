"""Owned disposable CPM closure schedules; metadata only, never storage IO.

Run the complete catalogs first. Requires exact fresh replay ownership and must
be followed by disposal of only that owned database, including after failure.
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


def write(owner, scan, action, role='source'):
    return (f"internal.initial_cpm_photo_write_action('{action}','{owner}','{scan}',"
            f"(SELECT assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}'),"
            f"(SELECT object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='{scan}' AND role='{role}'))")


def settle(scan):
    return ("internal.settle_initial_cpm_photo_write_closure("
            f"(SELECT attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}'),"
            "(SELECT digest FROM internal.initial_cpm_photo_write_policies),'live_object',"
            f"(SELECT issued_at FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}'),NULL)")


def run(q):
    for source in (TEST, FIXTURE, Path(__file__), Path(__file__).with_name('test_initial_cpm_photo_capacity.py'),
                   Path(__file__).with_name('test_initial_cpm_photo_write_holds.py')):
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    q.record['scope'] = 'Inactive SQL closure serialization only. No storage observation, issuer, installed policy, physical retention, capacity release or app journey proof.'
    source = TEST.read_text()
    marker = 'CREATE TEMP TABLE cpm_saved AS'
    policy_start = 'CREATE TEMP TABLE closure_policy AS'
    policy_end = 'CREATE FUNCTION pg_temp.closure_write('
    if any(source.count(m) != 1 for m in (marker, policy_start, policy_end)):
        raise ValueError('unique synthetic fixture boundaries required')
    setup = source.split(marker)[0] + policy_start + source.split(policy_start)[1].split(policy_end)[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(6)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
        setup += f"SELECT ({write(owner, scan, 'bind')}).state;\n"
        setup += f"SELECT (internal.bind_initial_cpm_photo_write_policy('{owner}',(SELECT attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}'),(SELECT digest FROM internal.initial_cpm_photo_write_policies))).state;\n"
        if (owner, scan) != identities[-1]:
            setup += f"SELECT ({write(owner, scan, 'may_have_issued')}).state;\n"
    setup += 'COMMIT;'
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    q.save()
    sessions = []
    started = time.monotonic()
    try:
        seeded = q.execute('synthetic_policy_bound_issuance', setup)
        if re.search(r'^(not ok|Bail out!)', seeded, re.M):
            raise RuntimeError('synthetic fixture assertion failed')
        for name in ('closer', 'contender', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        begin = "BEGIN; DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"

        # Closure is invisible to a second role until committed.
        owner, scan = identities[0]
        actor.run('closure_uncommitted', begin + f"SELECT ({settle(scan)}).outcome;")
        contender.start('next_role_waits_for_closure', begin + f"SELECT ({write(owner, scan, 'bind', 'ai')}).state;COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_closure', 'COMMIT;')
        contender.finish()
        if observer.run('durable_closure_permits_next_role', f"SELECT count(*)=2 AND count(*) FILTER(WHERE write_closed)=1 FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('next role lost durable closure dependency')

        owner, scan = identities[1]
        actor.run('closure_to_rollback', begin + f"SELECT ({settle(scan)}).outcome;")
        contender.start('next_role_waits_for_rollback', begin + expect_denied(write(owner, scan, 'bind', 'ai'), 'initial_analysis_cpm_write_outstanding') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('rollback_closure', 'ROLLBACK;')
        contender.finish()
        if observer.run('rollback_keeps_original_hold', f"SELECT NOT write_closed AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_closures c WHERE c.attempt_id=a.attempt_id) FROM internal.initial_cpm_photo_write_attempts a WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('rolled-back receipt escaped')

        owner, scan = identities[2]
        actor.run('live_closure_before_retirement', begin + f"SELECT ({settle(scan)}).outcome;")
        contender.start('retirement_waits_for_closure', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('commit_before_retirement', 'COMMIT;')
        contender.finish()
        if observer.run('retired_closed_role_keeps_capacity', f"SELECT internal.initial_cpm_photo_retired_write_hold('{scan}') AND write_closed FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('retirement lost closed attempt liability')

        owner, scan = identities[3]
        actor.run('retirement_before_live_closure', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        contender.start('live_closure_waits_for_retirement', begin + expect_denied(settle(scan), 'initial_analysis_cancelled') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_retirement_first', 'COMMIT;')
        contender.finish()
        if observer.run('retirement_denies_fresh_live_receipt', f"SELECT retired AND NOT write_closed AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_closures c WHERE c.attempt_id=a.attempt_id) FROM internal.initial_cpm_photo_write_attempts a WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('fresh closure escaped retirement')

        # Keep the ORIGINAL claim captured before IO: replacement must not
        # rescue a stale observation. Cleanup owns registry, never owner locks.
        owner, scan = identities[3]
        observer.run('claim_retired_objects', begin + "DO $$ BEGIN FOR i IN 1..6 LOOP PERFORM public.claim_initial_preparation_source_erasure(); END LOOP; END $$;COMMIT;")
        claim = observer.run('capture_original_claim', f"SELECT a.attempt_id||':'||a.object_id||':'||r.claim_token||':'||p.digest FROM internal.initial_cpm_photo_write_attempts a JOIN internal.initial_preparation_source_registry r USING(object_id) CROSS JOIN internal.initial_cpm_photo_write_policies p WHERE a.scan_id='{scan}';")[-1]
        attempt, object_id, token, policy = claim.split(':')
        observation = observer.run('capture_marker_observation_time', "SELECT clock_timestamp()::TEXT;")[-1]
        expression = f"internal.settle_initial_cpm_photo_write_closure('{attempt}','{policy}','retired_marker','{observation}','{token}')"
        actor.run('replace_claim_uncommitted', begin + f"SELECT public.finish_initial_preparation_source_erasure('{object_id}','{token}',FALSE)->>'outcome';SELECT public.claim_initial_preparation_source_erasure()->>'outcome';")
        contender.start('marker_settlement_waits_for_claim_replacement', begin + expect_denied(expression, 'initial_analysis_preparation_required') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_replacement_claim', 'COMMIT;')
        contender.finish()
        if observer.run('replacement_claim_does_not_close_old_observation', f"SELECT r.claim_token IS NOT NULL AND r.claim_token<>'{token}' AND NOT a.write_closed FROM internal.initial_cpm_photo_write_attempts a JOIN internal.initial_preparation_source_registry r USING(object_id) WHERE a.attempt_id='{attempt}';") != ['t']:
            raise RuntimeError('stale marker observation escaped')

        # A concurrent policy revocation must fail fast, not invert lock order.
        owner, scan = identities[4]
        actor.run('revocation_uncommitted', "BEGIN;UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';")
        expression = settle(scan)
        contender.run('closure_fails_fast_during_revocation', begin + "DO $denied$ BEGIN BEGIN PERFORM " + expression + "; EXCEPTION WHEN lock_not_available THEN RETURN; END; RAISE EXCEPTION 'policy lock ignored' USING ERRCODE='ZX603'; END; $denied$;COMMIT;")
        actor.run('revoked_policy_stays_closed', expect_denied(expression, 'initial_analysis_preparation_unavailable'))
        actor.run('rollback_policy_revocation_fixture', 'ROLLBACK;')
        if observer.run('revocation_retains_outstanding_hold', f"SELECT NOT write_closed FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('revocation closed write')
        # Raw owner writes must enforce the same backend revocation boundary
        # as the normal action, including a concurrent revocation transaction.
        owner, scan = identities[5]
        raw = f"""UPDATE internal.initial_cpm_photo_write_attempts SET state='may_have_issued',issued_at=clock_timestamp() WHERE scan_id='{scan}';
 UPDATE internal.initial_cpm_photo_capacity_reservations SET write_capability_state='may_have_issued' WHERE scan_id='{scan}';
 SET CONSTRAINTS ALL IMMEDIATE;"""
        actor.run('backend_revocation_uncommitted', "BEGIN;UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';")
        contender.run('raw_issuance_fails_fast_during_backend_revocation', begin + "DO $denied$ BEGIN BEGIN " + raw + " EXCEPTION WHEN lock_not_available THEN RETURN; END; RAISE EXCEPTION 'backend lock ignored' USING ERRCODE='ZX604'; END; $denied$;COMMIT;")
        actor.run('commit_backend_revocation', 'COMMIT;')
        contender.run('raw_issuance_denied_after_backend_revocation', begin + "DO $denied$ BEGIN BEGIN " + raw + " EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM='initial_analysis_preparation_unavailable' THEN RETURN; END IF; RAISE; END; RAISE EXCEPTION 'backend revocation ignored' USING ERRCODE='ZX605'; END; $denied$;COMMIT;")
        if observer.run('raw_revocation_keeps_bound_attempt', f"SELECT state='bound' AND issued_at IS NULL FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}';") != ['t']:
            raise RuntimeError('raw issuance bypassed revocation')
        if observer.run('no_funding_or_invocation', "SELECT NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations);") != ['t']:
            raise RuntimeError('closure funded execution')
    finally:
        finish_sessions(q, list(reversed(sessions)), sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - started
    q.record['schedule_count'] = 7
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-write-closure', args.replay_manifest))

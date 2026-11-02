"""Owned disposable snapshot/current-check races, with metadata-only evidence.

Run after complete catalogs on a fresh owned replay; dispose that database after
the run, including failure. No storage, credentials, signer or provider IO.
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
from test_initial_cpm_photo_write_closure import write
from test_initial_cpm_photo_write_holds import blocked


def read(scan, outcome='live_object', claim=None, expected=None):
    token = 'NULL' if claim is None else "'" + claim.replace("'", "''") + "'"
    snapshot = 'NULL' if expected is None else "'" + expected.replace("'", "''") + "'::JSONB"
    return ("internal.read_initial_cpm_photo_observation("
            f"(SELECT attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}'),"
            f"'{outcome}',{token},{snapshot})")


def run(q):
    for source in (TEST, FIXTURE, Path(__file__),
                   Path(__file__).with_name('test_initial_cpm_photo_capacity.py'),
                   Path(__file__).with_name('test_initial_cpm_photo_write_closure.py'),
                   Path(__file__).with_name('test_initial_cpm_photo_write_holds.py')):
        q.record['source_manifest'][str(source.relative_to(ROOT))] = q.digest(source)
    q.record['scope'] = 'Inactive SQL snapshot serialization only; no adapter, storage observation, signer, closure, capacity release or app journey qualification.'
    source = TEST.read_text()
    marker = 'CREATE TEMP TABLE cpm_saved AS'
    policy_start = 'CREATE TEMP TABLE closure_policy AS'
    policy_end = '-- END CPM CLOSURE POLICY FIXTURE'
    if any(source.count(m) != 1 for m in (marker, policy_start, policy_end)):
        raise ValueError('unique synthetic fixture boundaries required')
    setup = source.split(marker)[0] + policy_start + source.split(policy_start)[1].split(policy_end)[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(3)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
        setup += f"SELECT ({write(owner, scan, 'bind')}).state;\n"
        setup += f"SELECT (internal.bind_initial_cpm_photo_write_policy('{owner}',(SELECT attempt_id FROM internal.initial_cpm_photo_write_attempts WHERE scan_id='{scan}'),(SELECT digest FROM internal.initial_cpm_photo_write_policies))).state;\n"
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
        for name in ('actor', 'contender', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        begin = "BEGIN; DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"

        owner, scan = identities[0]
        captured = actor.run('capture_live_snapshot', begin + f"SELECT {read(scan)};")[-1]
        contender.start('retirement_waits_for_snapshot', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';COMMIT;")
        blocked(observer, actor, contender)
        actor.run('end_snapshot_transaction_before_io', 'COMMIT;')
        contender.finish()
        actor.run('captured_live_snapshot_cannot_survive_retirement', begin + expect_denied(read(scan, expected=captured), 'initial_analysis_preparation_required') + 'COMMIT;')

        owner, scan = identities[1]
        captured = observer.run('capture_before_retirement_transaction', begin + f"SELECT {read(scan)};COMMIT;")[-1]
        actor.run('retirement_before_recheck', begin + f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
        contender.start('recheck_waits_for_retirement', begin + expect_denied(read(scan, expected=captured), 'initial_analysis_cancelled') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_retirement_before_recheck', 'COMMIT;')
        contender.finish()

        # Claim identity captured before IO is never replaced on the caller's
        # behalf, even when the same object has a new valid cleanup lease.
        observer.run('claim_retired_objects', begin + "DO $$ BEGIN FOR i IN 1..6 LOOP PERFORM public.claim_initial_preparation_source_erasure(); END LOOP; END $$;COMMIT;")
        original = observer.run('capture_original_claim', f"SELECT r.object_id||':'||r.claim_token FROM internal.initial_preparation_source_registry r JOIN internal.initial_cpm_photo_write_attempts a USING(object_id) WHERE a.scan_id='{scan}';")[-1]
        object_id, token = original.split(':')
        captured = observer.run('capture_marker_before_claim_replacement', begin + f"SELECT {read(scan, 'retired_marker', token)};COMMIT;")[-1]
        actor.run('replace_original_claim_uncommitted', begin + f"SELECT public.finish_initial_preparation_source_erasure('{object_id}','{token}',FALSE)->>'outcome';SELECT public.claim_initial_preparation_source_erasure()->>'outcome';")
        contender.start('marker_recheck_waits_for_claim_replacement', begin + expect_denied(read(scan, 'retired_marker', token, captured), 'initial_analysis_preparation_required') + 'COMMIT;')
        blocked(observer, actor, contender)
        actor.run('commit_replacement_claim', 'COMMIT;')
        contender.finish()
        if observer.run('new_claim_does_not_rescue_old_snapshot', f"SELECT claim_token IS NOT NULL AND claim_token<>'{token}' FROM internal.initial_preparation_source_registry WHERE object_id='{object_id}';") != ['t']:
            raise RuntimeError('replacement claim fixture missing')

        owner, scan = identities[2]
        captured = observer.run('capture_live_before_revocation', begin + f"SELECT {read(scan)};COMMIT;")[-1]
        for kind, table in (('policy', 'initial_cpm_photo_write_policies'),
                            ('backend', 'initial_preparation_backend_eligibility')):
            expression = read(scan, expected=captured)
            actor.run(kind + '_revocation_uncommitted', f"BEGIN;UPDATE internal.{table} SET state='revoked';")
            contender.run(kind + '_recheck_fails_fast', begin + "DO $denied$ BEGIN BEGIN PERFORM " + expression + "; EXCEPTION WHEN lock_not_available THEN RETURN; END; RAISE EXCEPTION 'revocation lock ignored' USING ERRCODE='ZX606'; END; $denied$;COMMIT;")
            actor.run(kind + '_recheck_denied_after_own_revocation', expect_denied(expression, 'initial_analysis_preparation_unavailable'))
            # Restore this synthetic revocation for the independent next race.
            actor.run(kind + '_rollback_revocation', 'ROLLBACK;')
            contender.run(kind + '_original_snapshot_valid_after_rollback', begin + f"SELECT {expression} IS NOT NULL;COMMIT;")
        if observer.run('reads_never_close_release_or_fund', "SELECT NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_attempts WHERE write_closed) AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_write_closures) AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE state='released') AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations);") != ['t']:
            raise RuntimeError('snapshot read changed lifecycle/accounting')
    finally:
        finish_sessions(q, list(reversed(sessions)), sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - started
    q.record['schedule_count'] = 5
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-observation-snapshot', args.replay_manifest))

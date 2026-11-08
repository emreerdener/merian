"""Owned disposable verification-start races; no media or provider I/O.

Run selected catalogs first on the exact fresh replay. Dispose the owned local
database after this committed synthetic run, including on failure.
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
from test_initial_cpm_photo_capacity import TEST, FIXTURE, create, finish_sessions
from test_initial_cpm_photo_write_holds import blocked


def start(owner, scan):
    return (f"internal.begin_initial_cpm_photo_verification('{owner}','{scan}',"
            f"(SELECT assignment_digest FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}'))")


def run(q):
    for path in (TEST, FIXTURE, Path(__file__),
                 Path(__file__).with_name('test_initial_cpm_photo_capacity.py'),
                 Path(__file__).with_name('test_initial_cpm_photo_write_holds.py')):
        q.record['source_manifest'][str(path.relative_to(ROOT))] = q.digest(path)
    q.record['scope'] = 'Private SQL start serialization and committed recovery only; no byte verification, media IO, funding, admission or app journey qualification.'
    source = TEST.read_text()
    markers = ('CREATE TEMP TABLE cpm_saved AS', 'CREATE TEMP TABLE closure_policy AS',
               '-- END CPM CLOSURE POLICY FIXTURE')
    if any(source.count(marker) != 1 for marker in markers):
        raise ValueError('unique setup-only fixture boundaries required')
    setup = source.split(markers[0])[0] + markers[1] + source.split(markers[1])[1].split(markers[2])[0]
    identities = [(str(uuid.uuid4()), str(uuid.uuid4())) for _ in range(6)]
    for owner, scan in identities:
        setup += f"SELECT pg_temp.admission_owner('{owner}');SELECT {create(owner, scan)}->>'outcome';\n"
        setup += f"""DO $$ DECLARE m RECORD; w internal.initial_cpm_photo_write_attempts; a TEXT; p TEXT;
BEGIN
 SELECT assignment_digest INTO STRICT a FROM internal.initial_analysis_preparation_intents WHERE scan_id='{scan}';
 SELECT digest INTO STRICT p FROM internal.initial_cpm_photo_write_policies;
 FOR m IN SELECT object_id FROM internal.initial_cpm_photo_role_mapping WHERE scan_id='{scan}' ORDER BY object_id LOOP
  w:=internal.initial_cpm_photo_write_action('bind','{owner}','{scan}',a,m.object_id);
  PERFORM internal.bind_initial_cpm_photo_write_policy('{owner}',w.attempt_id,p);
  w:=internal.initial_cpm_photo_write_action('may_have_issued','{owner}','{scan}',a,m.object_id);
  PERFORM internal.settle_initial_cpm_photo_write_closure(w.attempt_id,p,'live_object',w.issued_at,NULL);
 END LOOP;
END; $$;
"""
    setup += 'COMMIT;'
    q.record['setup_sha256'] = hashlib.sha256(setup.encode()).hexdigest()
    q.save()
    sessions = []
    began = time.monotonic()
    try:
        output = q.execute('complete_synthetic_closed_cohorts', setup)
        if re.search(r'^(not ok|Bail out!)', output, re.M):
            raise RuntimeError('synthetic fixture assertion failed')
        for name in ('starter', 'contender', 'observer'):
            sessions.append(Session(q, name))
        actor, contender, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise RuntimeError('distinct database sessions required')
        begin = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
        for index, resolution in enumerate(('COMMIT', 'ROLLBACK')):
            owner, scan = identities[index]
            if actor.run('first_start_' + resolution, begin + f"SELECT {start(owner, scan)}->>'outcome';")[-1] != 'started':
                raise RuntimeError('first start did not acquire authority')
            contender.start('second_start_waits_' + resolution, begin + f"SELECT {start(owner, scan)}->>'outcome';COMMIT;")
            blocked(observer, actor, contender)
            actor.run('resolve_first_' + resolution, resolution + ';')
            expected = 'held' if resolution == 'COMMIT' else 'started'
            if contender.finish()[-1] != expected:
                raise RuntimeError('concurrent start authority mismatch')

        # A separate connection represents a caller that lost the committed ack.
        owner, scan = identities[0]
        digest_sql = f"SELECT internal.initial_cpm_verification_intent_digest(s) FROM internal.initial_analysis_preparation_intents s WHERE scan_id='{scan}';"
        before = observer.run('committed_intent_image', digest_sql)
        recovered = q.execute('reconnected_lost_ack_is_held', begin + f"SELECT {start(owner, scan)}->>'outcome';COMMIT;")
        if recovered.splitlines()[-1] != 'held' or observer.run('recovery_keeps_image', digest_sql) != before:
            raise RuntimeError('recovery renewed committed start')

        for offset, deletion in enumerate((False, True)):
            for reverse in (False, True):
                owner, scan = identities[2 + offset * 2 + int(reverse)]
                label = ('deletion' if deletion else 'cancel') + ('_first' if reverse else '_second')
                retire = (f"SELECT public.apply_user_tombstone('{owner}');" if deletion
                          else f"SELECT public.cancel_initial_analysis('{owner}','{scan}')->>'dispatch';")
                if reverse:
                    actor.run(label, begin + retire)
                    # Owner deletion may report owner unavailable rather than cancellation.
                    denied = f"""DO $$ BEGIN BEGIN PERFORM {start(owner, scan)};
 EXCEPTION WHEN SQLSTATE '55000' OR SQLSTATE 'P0002' THEN
  IF SQLERRM IN ('initial_analysis_cancelled','initial_analysis_owner_unavailable') THEN RETURN; END IF; RAISE;
 END; RAISE EXCEPTION 'retirement allowed verification' USING ERRCODE='ZX710'; END; $$;"""
                    contender.start('start_waits_' + label, begin + denied + 'COMMIT;')
                else:
                    if actor.run('start_before_' + label, begin + f"SELECT {start(owner, scan)}->>'outcome';")[-1] != 'started':
                        raise RuntimeError('retirement schedule did not begin with fresh verification authority')
                    contender.start('retirement_waits_' + label, begin + retire + 'COMMIT;')
                blocked(observer, actor, contender)
                actor.run('commit_' + label, 'COMMIT;')
                contender.finish()
                if observer.run('retained_liability_' + label,
                                f"SELECT count(*)=3 AND bool_and(retired) FROM internal.initial_preparation_source_registry WHERE scan_id='{scan}';") != ['t']:
                    raise RuntimeError('retirement lost source cohort liability')
        if observer.run('no_context_or_funding', "SELECT NOT EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context) AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations) AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations) AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_admissions);") != ['t']:
            raise RuntimeError('start left context or funded execution')
    finally:
        finish_sessions(q, list(reversed(sessions)), sys.exc_info()[1])
    q.record['wall_seconds'] = time.monotonic() - began
    q.record['schedule_count'] = 6
    q.finish()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', type=Path, required=True)
    parser.add_argument('--replay-manifest', type=Path, required=True)
    args = parser.parse_args()
    run(Qualification(args.container, args.evidence_directory, 'cpm-verification-start-races', args.replay_manifest))

"""Source admission, direct writer, erasure and stop races on an owned local DB.

Synthetic records only. Exact blockers and both committed orders are observed
through separate PostgreSQL sessions; no hosted, storage or native actions.
"""
import argparse
import json
from pathlib import Path

from initial_atomic_admission_sessions import Session
from test_capture_retirement_races import Evidence, ROLE, blocked


def quote(value):
    return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"


def denied(statement, message):
    return ("DO $$ BEGIN BEGIN " + statement.replace('SELECT ', 'PERFORM ', 1)
            + " RAISE EXCEPTION 'unexpected admission'; EXCEPTION WHEN SQLSTATE '55000' THEN "
            + f"IF SQLERRM <> '{message}' THEN RAISE; END IF; END; END $$;")


def run(evidence):
    evidence.record['scope'] = __doc__
    first, second, observer = [Session(evidence, name) for name in ['first', 'second', 'observer']]
    fixtures = []
    source = (Path(__file__).parent.parent / 'tests/capture_source_admission.sql').read_text()
    fixture_sql = 'CREATE FUNCTION pg_temp.new_admission()' + source.split('CREATE FUNCTION pg_temp.new_admission()')[1].split('CREATE TEMP TABLE admission_fixture')[0]
    for session in [first, second, observer]:
        session.run('install_synthetic_helpers', fixture_sql)
    begin = 'BEGIN;' + ROLE
    try:
        for schedule in ['duplicate', 'changed', 'begin_before_account', 'account_before_begin',
                         'insert_before_account', 'account_before_insert',
                         'begin_before_scan', 'scan_before_begin', 'contraction_before_retry',
                         'retry_before_contraction', 'terminal_before_retry']:
            f = json.loads(observer.run('new_fixture', begin + 'SELECT pg_temp.new_admission(); COMMIT;')[-1])
            fixtures.append(f)
            admit = 'SELECT pg_temp.admit(' + quote(f) + ');'
            unavailable = denied(admit, 'capture_source_admission_unavailable')
            account = f"INSERT INTO internal.account_deletion_jobs(user_id) VALUES('{f['owner']}');"
            scan = (f"SELECT id FROM public.users WHERE id='{f['owner']}' FOR UPDATE;"
                    + f"SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:{f['scan']}',0));"
                    + f"INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('{f['scan']}','{f['owner']}');")
            if schedule in ['duplicate', 'changed']:
                receipt = first.run('initial_admission', begin + admit)[-1]
                retry = admit
                if schedule == 'changed':
                    changed = json.loads(json.dumps(f))
                    changed['payload']['captureSourceObservations']['items'][0]['sha256'] = 'd' * 64
                    retry = denied('SELECT pg_temp.admit(' + quote(changed) + ');', 'capture_source_admission_conflict')
                second.start('retry_waits_on_owner', begin + retry)
                blocked(observer, second, first)
                first.run('commit_admission', 'COMMIT;')
                result = second.finish()
                if schedule == 'duplicate':
                    assert result[-1] == receipt
                second.run('commit_retry', 'COMMIT;')
            elif schedule in ['begin_before_account', 'account_before_begin', 'begin_before_scan', 'scan_before_begin']:
                retirement = scan if 'scan' in schedule else account
                rejection = denied(admit, 'scan_generation_deleted') if 'scan' in schedule else unavailable
                if schedule.startswith('begin_before'):
                    first.run('admit_before_retirement', begin + admit)
                    second.start('retirement_waits', begin + retirement)
                    blocked(observer, second, first)
                    first.run('commit_admission', 'COMMIT;')
                    second.finish()
                    second.run('commit_retirement', 'COMMIT;')
                    assert observer.run('verify_erased_recovery', f"SELECT recovery IS NULL AND retired_at IS NOT NULL FROM internal.capture_source_admissions WHERE scan_id='{f['scan']}';") == ['t']
                else:
                    first.run('retire_before_admission', begin + retirement)
                    second.start('admission_waits', begin + rejection)
                    blocked(observer, second, first)
                    first.run('commit_retirement', 'COMMIT;')
                    second.finish()
                    second.run('commit_denial', 'COMMIT;')
                    assert observer.run('verify_no_new_seal', f"SELECT count(*) FROM internal.capture_source_admissions WHERE scan_id='{f['scan']}';") == ['0']
            else:
                observer.run('admit_fixture', begin + admit + 'COMMIT;')
                if schedule in ['insert_before_account', 'account_before_insert']:
                    canonical = json.loads(observer.run('retain_synthetic_projection', f"SELECT recovery->'intent' FROM internal.capture_source_admissions WHERE scan_id='{f['scan']}';")[-1])
                    observer.run('lose_mutable_intent', f"DELETE FROM public.scan_ingestion_intents WHERE scan_id='{f['scan']}';")
                    insert = (f"SELECT public.record_scan_ingestion_intent('{f['scan']}','{f['owner']}','identify-multimodal',"
                              + quote(canonical['request_payload']) + ',' + quote(f['counts']) + ',' + quote(f['keys'])
                              + f",ARRAY['{f['session']}']::uuid[],'{canonical['manifest_checksum']}','{canonical['payload_checksum']}',true,false,'{{}}',3);")
                    if schedule == 'insert_before_account':
                        first.run('direct_insert_before_retirement', begin + insert)
                        second.start('retirement_waits_for_shared_seal', begin + account)
                        blocked(observer, second, first)
                        first.run('commit_direct_insert', 'COMMIT;')
                        second.finish()
                        second.run('commit_retirement', 'COMMIT;')
                    else:
                        first.run('retirement_before_direct_insert', begin + account)
                        second.start('direct_insert_waits_for_erasure', begin + denied(insert, 'capture_source_admission_unavailable'))
                        blocked(observer, second, first)
                        first.run('commit_retirement', 'COMMIT;')
                        second.finish()
                        second.run('commit_denial', 'COMMIT;')
                        assert observer.run('verify_no_recreated_intent', f"SELECT count(*) FROM public.scan_ingestion_intents WHERE scan_id='{f['scan']}';") == ['0']
                    assert observer.run('verify_retirement_marker', f"SELECT recovery IS NULL FROM internal.capture_source_admissions WHERE scan_id='{f['scan']}';") == ['t']
                else:
                    contraction = f"UPDATE public.scan_ingestion_intents SET resumable=false WHERE scan_id='{f['scan']}';"
                    if schedule == 'terminal_before_retry':
                        contraction = f"UPDATE public.scan_ingestion_jobs SET status='failed_terminal' WHERE scan_id='{f['scan']}';"
                    if schedule == 'retry_before_contraction':
                        first.run('retry_before_stop', begin + admit)
                        second.start('stop_waits_for_retry', begin + contraction)
                        blocked(observer, second, first)
                        first.run('commit_retry', 'COMMIT;')
                        second.finish()
                        second.run('commit_stop', 'COMMIT;')
                    else:
                        first.run('stop_before_retry', begin + contraction)
                        second.start('retry_waits_for_stop', begin + unavailable)
                        blocked(observer, second, first)
                        first.run('commit_stop', 'COMMIT;')
                        second.finish()
                        second.run('commit_denial', 'COMMIT;')
                    observer.run('future_retry_denied', begin + unavailable + 'COMMIT;')
                    assert observer.run('stop_persists', f"SELECT count(*) FROM internal.capture_source_admission_stops WHERE scan_id='{f['scan']}';") == ['1']
            evidence.record.setdefault('schedules', []).append(dict(name=schedule, passed=True))
        evidence.record['passed'] = True
    finally:
        first.close()
        second.close()
        for f in fixtures:
            observer.run('remove_synthetic_fixture', f"""
                DELETE FROM public.scan_ingestion_intents WHERE user_id='{f['owner']}';
                DELETE FROM public.scan_ingestion_jobs WHERE user_id='{f['owner']}';
                DELETE FROM public.users WHERE id='{f['owner']}';
                DELETE FROM auth.users WHERE id='{f['owner']}';
                DELETE FROM internal.capture_object_authorities WHERE owner_id='{f['owner']}';
                DELETE FROM internal.capture_source_admissions WHERE scan_id='{f['scan']}';
                DELETE FROM internal.capture_source_admission_stops WHERE scan_id='{f['scan']}';
                DELETE FROM internal.scan_deletion_tombstones WHERE scan_id='{f['scan']}';
                DELETE FROM internal.account_deletion_jobs WHERE user_id='{f['owner']}';
            """)
        observer.close()
        evidence.save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    evidence = Evidence(args.container, args.evidence)
    run(evidence)
    print(json.dumps(dict(passed=evidence.record['passed'], schedules=len(evidence.record['schedules']))))

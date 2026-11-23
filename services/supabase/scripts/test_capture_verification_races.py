"""Retained destination receipts versus retirement on an owned disposable DB.

Observe exact session blocking and both commit orders. No object transport,
finalizer, release, hosted state or native actions are represented by this test.
"""
import argparse
import json
from pathlib import Path

from initial_atomic_admission_sessions import Session
from test_capture_retirement_races import Evidence, ROLE, blocked


def run(evidence):
    evidence.record['scope'] = __doc__
    first, second, observer = [Session(evidence, name) for name in ['first', 'second', 'observer']]
    fixtures = []
    source = (Path(__file__).parent.parent / 'tests/capture_promotion_cohorts.sql').read_text()
    helper = source.split('CREATE FUNCTION pg_temp.new_cohort()')[1].split('CREATE FUNCTION pg_temp.register_cohort')[0]
    observer.run('fixture_function', 'CREATE FUNCTION pg_temp.new_cohort()' + helper)
    begin = 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;'
    try:
        for peer in ['duplicate', 'target', 'source', 'account', 'scan']:
            for order in (['receipt'] if peer == 'duplicate' else ['receipt', 'retirement']):
                f = json.loads(observer.run('new_fixture', 'BEGIN;' + ROLE + 'SELECT pg_temp.new_cohort(); COMMIT;')[-1])
                fixtures.append(f)
                b = f['bindings'][0]
                binding = "'" + json.dumps(b) + "'::jsonb"
                bindings = "'" + json.dumps(f['bindings']) + "'::jsonb"
                registration = f"SELECT public.register_capture_promotion_ingestion('{f['cohort']}','{f['manifest']}','{f['request']}',{bindings});"
                observer.run('register_and_consume_write', begin + registration + f"SELECT public.authorize_capture_promotion_action({binding},'write_destination'); COMMIT;")
                receipt = f"SELECT public.record_capture_promotion_verification({binding},'destination_recovery');"
                if peer == 'duplicate':
                    saved = first.run('record_first_receipt', begin + receipt)[-1]
                    second.start('duplicate_receipt_waits', begin + receipt.replace('destination_recovery', 'write_acknowledged'))
                    blocked(observer, second, first)
                    first.run('commit_first_receipt', 'COMMIT;')
                    assert second.finish()[-1] == saved
                    second.run('commit_same_receipt', 'COMMIT;')
                else:
                    retirement = {
                        'target': f"SELECT public.retire_capture_promotion_operation({binding});",
                        'source': f"UPDATE internal.capture_object_authorities SET retired_at=clock_timestamp() WHERE backend_sha256='{b['backendSHA256']}' AND object_key='{b['sourceKey']}';",
                        'account': f"SELECT * FROM public.request_account_deletion('{b['ownerId']}');",
                        'scan': f"INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('{b['scanId']}','{b['ownerId']}');",
                    }[peer]
                    peer_begin = begin if peer in ['target', 'account'] else 'BEGIN;' + ROLE
                    denied = "DO $$ BEGIN BEGIN " + receipt.replace('SELECT ', 'PERFORM ', 1) + " RAISE EXCEPTION 'unexpected receipt'; EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM <> 'capture_promotion_unavailable' THEN RAISE; END IF; END; END $$;"
                    if order == 'receipt':
                        first.run('record_before_retirement', begin + receipt)
                        if peer == 'scan':
                            # The installed pre-scan tombstone guard uses try-lock,
                            # so it reports busy rather than waiting for the receipt.
                            busy = "DO $$ BEGIN BEGIN " + retirement + " RAISE EXCEPTION 'unexpected tombstone'; EXCEPTION WHEN SQLSTATE '55P03' THEN IF SQLERRM <> 'initial_analysis_erasure_busy' THEN RAISE; END IF; END; END $$;"
                            second.run('scan_retirement_reports_busy', peer_begin + busy + 'COMMIT;')
                            first.run('commit_receipt', 'COMMIT;')
                            second.run('retry_scan_retirement_after_receipt', peer_begin + retirement + 'COMMIT;')
                        else:
                            second.start('retirement_waits_for_receipt', peer_begin + retirement)
                            blocked(observer, second, first)
                            first.run('commit_receipt', 'COMMIT;')
                            second.finish()
                            second.run('commit_retirement', 'COMMIT;')
                        observer.run('late_receipt_denied', begin + denied + 'COMMIT;')
                    else:
                        first.run('retire_before_receipt', peer_begin + retirement)
                        second.start('receipt_waits_for_retirement', begin + denied)
                        blocked(observer, second, first)
                        first.run('commit_prior_retirement', 'COMMIT;')
                        second.finish()
                        second.run('commit_denial', 'COMMIT;')
                expected = ('t' if order == 'receipt' else 'f') + '|t|' + ('f' if peer == 'duplicate' else 't')
                actual = observer.run('verify_receipt_write_retirement', f"SELECT destination_verified_at IS NOT NULL,write_authorized_at IS NOT NULL,retired_at IS NOT NULL FROM internal.capture_promotion_operations WHERE operation_id='{b['operationId']}';")[-1]
                assert actual == expected, actual
                evidence.record.setdefault('schedules', []).append(dict(peer=peer, first=order, passed=True))
        evidence.record['passed'] = True
    finally:
        first.close()
        second.close()
        for f in fixtures:
            b = f['bindings'][0]
            observer.run('remove_synthetic_fixture', f"""
                DELETE FROM public.scan_ingestion_intents WHERE user_id='{b['ownerId']}';
                DELETE FROM public.scan_ingestion_jobs WHERE user_id='{b['ownerId']}';
                DELETE FROM public.users WHERE id='{b['ownerId']}';
                DELETE FROM auth.users WHERE id='{b['ownerId']}';
                DELETE FROM internal.account_deletion_jobs WHERE user_id='{b['ownerId']}';
                DELETE FROM internal.scan_deletion_tombstones WHERE scan_id='{b['scanId']}';
                DELETE FROM internal.capture_promotion_operations WHERE cohort_id='{f['cohort']}';
                DELETE FROM internal.capture_promotion_cohorts WHERE cohort_id='{f['cohort']}';
                DELETE FROM internal.capture_object_authorities WHERE owner_id='{b['ownerId']}';
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

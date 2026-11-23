"""Qualify prepared cohort registration and whole-member freshness on owned local DB.

Separate sessions observe exact blocking and committed orders. Synthetic SQL
only; no storage, finalization, logical-slot proof, hosted or native actions.
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
    fixture_sql = source.split('CREATE FUNCTION pg_temp.new_cohort()')[1].split('CREATE FUNCTION pg_temp.register_cohort')[0]
    observer.run('fixture_function', 'CREATE FUNCTION pg_temp.new_cohort()' + fixture_sql)
    try:
        for schedule in ['duplicate_registration', 'different_members', 'peer_change_first', 'authorization_first', 'intent_change_first', 'authorization_before_intent_change']:
            f = json.loads(observer.run('new_fixture', 'BEGIN;' + ROLE + 'SELECT pg_temp.new_cohort(); COMMIT;')[-1])
            fixtures.append(f)
            bindings = f['bindings']
            quoted = "'" + json.dumps(bindings) + "'::jsonb"
            registration = f"SELECT public.register_capture_promotion_cohort('{f['cohort']}','{f['job']}','{f['manifest']}','{f['request']}',{quoted});"
            def action(index):
                b = "'" + json.dumps(bindings[index]) + "'::jsonb"
                return f"SELECT public.authorize_capture_promotion_action({b},'write_destination');"
            begin = 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;'
            if schedule == 'duplicate_registration':
                seal = first.run('first_registration', begin + registration)[-1]
                second.start('duplicate_registration_waits', begin + registration)
                blocked(observer, second, first)
                first.run('commit_registration', 'COMMIT;')
                assert second.finish()[-1] == seal
                second.run('commit_identical_retry', 'COMMIT;')
            else:
                observer.run('register_cohort', 'BEGIN;' + ROLE + registration + 'COMMIT;')
                if schedule == 'different_members':
                    assert first.run('authorize_member_zero', begin + action(0))[-1] == 't'
                    second.start('other_member_waits_for_owner', begin + action(1))
                    blocked(observer, second, first)
                    first.run('commit_member_zero', 'COMMIT;')
                    assert second.finish()[-1] == 't'
                    second.run('commit_member_one', 'COMMIT;')
                else:
                    edit = f"UPDATE public.scan_media_assets SET role='inference_frame' WHERE id='{bindings[1]['assetId']}';"
                    if schedule in ['intent_change_first', 'authorization_before_intent_change']:
                        edit = f"""SELECT public.record_scan_ingestion_intent(scan_id,user_id,endpoint,
                            request_payload,media_counts,media_object_keys,upload_session_ids,
                            manifest_checksum,repeat('d',64),resumable,inline_media_redacted,
                            redacted_media_counts,payload_schema_version)
                            FROM public.scan_ingestion_intents WHERE id='{f['intent']}';"""
                    denied = "DO $$ BEGIN BEGIN " + action(0).replace('SELECT ', 'PERFORM ', 1) + " RAISE EXCEPTION 'unexpected authorization'; EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM <> 'capture_promotion_cohort_unavailable' THEN RAISE; END IF; END; END $$;"
                    if schedule in ['peer_change_first', 'intent_change_first']:
                        first.run('peer_projection_change', 'BEGIN;' + ROLE + edit)
                        second.start('whole_cohort_waits_for_peer', begin + denied)
                        blocked(observer, second, first)
                        first.run('commit_peer_change', 'COMMIT;')
                        second.finish()
                        second.run('commit_denial', 'COMMIT;')
                    else:
                        assert first.run('authorize_before_peer_change', begin + action(0))[-1] == 't'
                        second.start('peer_change_waits_for_whole_cohort', 'BEGIN;' + ROLE + edit)
                        blocked(observer, second, first)
                        first.run('commit_authorization', 'COMMIT;')
                        second.finish()
                        second.run('commit_later_peer_change', 'COMMIT;')
                        observer.run('fresh_authorization_denied', begin + denied + 'COMMIT;')
            expected_writes = 2 if schedule == 'different_members' else 1 if schedule in ['authorization_first', 'authorization_before_intent_change'] else 0
            outcome = observer.run('verify_exact_cohort_and_write_count', f"SELECT count(*),count(*) FILTER(WHERE write_authorized_at IS NOT NULL) FROM internal.capture_promotion_operations WHERE cohort_id='{f['cohort']}';")[-1]
            assert outcome == f'4|{expected_writes}', outcome
            evidence.record.setdefault('schedules', []).append(dict(name=schedule, passed=True))
        evidence.record['passed'] = True
    finally:
        first.close()
        second.close()
        for f in fixtures:
            owner = f['bindings'][0]['ownerId']
            observer.run('remove_synthetic_fixture', f"""
                DELETE FROM public.scan_ingestion_intents WHERE user_id='{owner}';
                DELETE FROM public.scan_ingestion_jobs WHERE user_id='{owner}';
                DELETE FROM public.users WHERE id='{owner}';
                DELETE FROM auth.users WHERE id='{owner}';
                DELETE FROM internal.capture_promotion_operations WHERE cohort_id='{f['cohort']}';
                DELETE FROM internal.capture_promotion_cohorts WHERE cohort_id='{f['cohort']}';
                DELETE FROM internal.capture_object_authorities WHERE owner_id='{owner}';
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

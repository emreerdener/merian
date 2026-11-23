"""Synthetic promotion authorization/retirement races on an owned disposable DB.

Independent sessions observe exact blockers and both committed orders. No
storage I/O, hosted mutation, final binding or native qualification is implied.
"""
import argparse
import json
import uuid

from initial_atomic_admission_sessions import Session
from test_capture_retirement_races import Evidence, ROLE, blocked


def fixture(observer):
    owner, scan, asset, session, operation = [str(uuid.uuid4()) for _ in range(5)]
    source = f"staging/{owner}/promotion-race"
    binding = dict(operationId=operation, ownerId=owner, scanId=scan,
                   assetId=asset, sessionId=session, backendSHA256='a' * 64,
                   sourceKey=source,
                   destinationKey=f"public_uploads/free/{owner}/capture-promotion-{operation}",
                   contentType='image/webp', byteCount=100, sha256='c' * 64)
    literal = "'" + json.dumps(binding) + "'::jsonb"
    observer.run('create_synthetic_promotion', "BEGIN;" + ROLE + f"""
        INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
        VALUES('{owner}','authenticated','authenticated','{{}}','{{}}',now(),now());
        INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size,checksum_sha256)
        VALUES('{asset}','{owner}','{scan}','{session}','image','display','staged','capture_upload','{source}',0,'image/webp',100,repeat('c',64));
        SELECT public.register_capture_upload_capabilities('{owner}',repeat('a',64),jsonb_build_array(jsonb_build_object(
          'object_key','{source}','expires_at',clock_timestamp()+interval '1 hour','scan_id','{scan}','asset_id','{asset}','session_id','{session}')));
        SELECT public.register_capture_promotion_operation({literal}); COMMIT;
    """)
    return owner, operation, literal


def run(evidence):
    evidence.record['scope'] = __doc__
    sessions = [Session(evidence, name) for name in ['first', 'second', 'observer']]
    first, second, observer = sessions
    fixtures = []
    try:
        for competing in ['second_write', 'account_retirement', 'target_retirement']:
            for first_action in (['write'] if competing == 'second_write' else ['write', 'retirement']):
                owner, operation, binding = fixture(observer)
                fixtures.append((owner, operation))
                write = f"SELECT public.authorize_capture_promotion_action({binding},'write_destination');"
                retirement = (f"SELECT * FROM public.request_account_deletion('{owner}');" if competing == 'account_retirement'
                              else f"SELECT public.retire_capture_promotion_operation({binding});")
                if first_action == 'write':
                    result = first.run('first_write_authorized', 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;' + write)
                    assert result[-1] == 't', 'first write must be authorized'
                    second.start('competitor_waits', 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;' + (write if competing == 'second_write' else retirement))
                    blocked(observer, second, first)
                    first.run('commit_first_authorization', 'COMMIT;')
                    result = second.finish()
                    if competing == 'second_write':
                        assert result[-1] == 'f', 'second write must be refused'
                    second.run('commit_competitor', 'COMMIT;')
                else:
                    first.run('retirement_before_write', 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;' + retirement)
                    denial = f"""DO $$ BEGIN BEGIN
                      PERFORM public.authorize_capture_promotion_action({binding},'write_destination');
                      RAISE EXCEPTION 'unexpected write authority';
                      EXCEPTION WHEN SQLSTATE '55000' THEN
                        IF SQLERRM <> 'capture_promotion_unavailable' THEN RAISE; END IF;
                      END; END $$;"""
                    second.start('write_waits_for_retirement', 'BEGIN;' + ROLE + 'SET LOCAL ROLE service_role;' + denial)
                    blocked(observer, second, first)
                    first.run('commit_retirement', 'COMMIT;')
                    second.finish()
                    second.run('commit_denied_write', 'COMMIT;')
                expected_retired = 'false' if competing == 'second_write' else 'true'
                expected_write = 'true' if first_action == 'write' else 'false'
                expected_source_retired = 'true' if competing == 'account_retirement' else 'false'
                observer.run('verify_durable_outcome', f"""DO $$ BEGIN
                  IF NOT EXISTS(SELECT 1 FROM internal.capture_promotion_operations WHERE operation_id='{operation}'
                    AND (retired_at IS NOT NULL)={expected_retired} AND (write_authorized_at IS NOT NULL)={expected_write})
                  THEN RAISE EXCEPTION 'unexpected durable promotion outcome'; END IF;
                  IF NOT EXISTS(SELECT 1 FROM internal.capture_object_authorities
                    WHERE owner_id='{owner}' AND object_key='staging/{owner}/promotion-race'
                    AND (retired_at IS NOT NULL)={expected_source_retired})
                  THEN RAISE EXCEPTION 'unexpected source retirement outcome'; END IF; END $$;""")
                evidence.record.setdefault('schedules', []).append(dict(competing=competing, first=first_action, passed=True))
        evidence.record['passed'] = True
    finally:
        for session in sessions[:2]:
            session.close()
        for owner, operation in fixtures:
            observer.run('remove_synthetic_fixture', f"""
              DELETE FROM internal.account_deletion_jobs WHERE user_id='{owner}';
              DELETE FROM public.users WHERE id='{owner}'; DELETE FROM auth.users WHERE id='{owner}';
              DELETE FROM internal.capture_promotion_operations WHERE operation_id='{operation}';
              DELETE FROM internal.capture_object_authorities WHERE owner_id='{owner}';
            """)
        observer.close()
        evidence.save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    record = Evidence(args.container, args.evidence)
    run(record)
    print(json.dumps(dict(passed=record.record['passed'], schedules=len(record.record['schedules']))))

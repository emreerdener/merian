"""Both-order baseline recovery versus real local deletion/account owners.

Only an exact owned fresh disposable replay is accepted. Synthetic identities,
SQL and reply bodies stay in memory; retained evidence is metadata and hashes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import uuid

from initial_atomic_admission_sessions import Session
from initial_atomic_admission_test_support import Qualification
from initial_invocation_erasure_races import wait_for_blocker


def auth(owner):
    return ("SELECT set_config('request.jwt.claims',jsonb_build_object('sub','" + owner
            + "','role','authenticated')::TEXT,TRUE); SET LOCAL ROLE authenticated;")


SERVICE = "SELECT set_config('request.jwt.claim.role','service_role',TRUE); SET LOCAL ROLE service_role;"


def seed(q, label):
    owner, target, scan, later = [str(uuid.uuid4()) for _ in range(4)]
    subject, secret = 'baseline-fixture-' + uuid.uuid4().hex, uuid.uuid4().hex + uuid.uuid4().hex
    q.execute(label + '_fixture', f"""
BEGIN;
INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_anonymous)
VALUES('{owner}','authenticated','authenticated','{owner}@example.invalid',now(),
 '{{"provider":"anonymous","providers":[]}}','{{}}',now(),now(),TRUE),
 ('{target}','authenticated','authenticated','{target}@example.invalid',now(),
 '{{"provider":"google","providers":["google"]}}','{{}}',now(),now(),FALSE);
INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
VALUES('{subject}','{target}',jsonb_build_object('sub','{subject}','email','{target}@example.invalid'),'google',now(),now(),now());
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
VALUES('{scan}','{owner}','failed_terminal','server_replay_limit_reached','replay_exhausted');
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
VALUES('{scan}','{owner}','{{}}',0.9,TRUE,'flash','private');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
{auth(owner)}
DO $$ BEGIN PERFORM public.enroll_owned_observation_history('{scan}',9); END $$;
RESET ROLE;
UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE,saved_import_enabled=FALSE;
DO $$ DECLARE b internal.observation_analysis_results; BEGIN
 SELECT * INTO STRICT b FROM internal.observation_analysis_results WHERE observation_id='{scan}' AND ordinal=1;
 INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
 VALUES('{later}',b.observation_id,2,repeat('a',64),now(),b.result_snapshot,
 '{{"schema_version":1,"captured_media":[{{"description":{{"_0":{{"freeText":"Synthetic later result"}}}}}}]}}');
 INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
 SELECT b.observation_id,'{later}',review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=b.analysis_id;
 UPDATE internal.observation_histories SET selected_analysis_id='{later}',state_revision=4 WHERE observation_id=b.observation_id;
END $$;
COMMIT;
""")
    handoff = q.execute(label + '_issue_handoff', 'BEGIN;' + auth(owner)
                        + f"SELECT handoff_id FROM public.issue_ghost_profile_merge_handoff('{secret}','google','{subject}'); COMMIT;").splitlines()[-1]
    # The preceding auth set_config result is never retained; accept only a UUID.
    handoff = str(uuid.UUID(handoff))
    return owner, target, scan, later, handoff, secret


def read(owner, scan, deny=False):
    request = '{"schema_version":1,"observation_id":"' + scan + '"}'
    return auth(owner) + f"""
DO $$ DECLARE r JSONB; denied BOOLEAN:=FALSE; BEGIN
 BEGIN r:=public.get_owned_observation_enrollment_baseline('{request}',9);
 EXCEPTION WHEN SQLSTATE 'P0002' THEN
  IF SQLERRM IS DISTINCT FROM 'analysis_history_not_found' THEN RAISE; END IF; denied:=TRUE;
 END;
 IF denied IS DISTINCT FROM {str(deny).upper()} THEN RAISE EXCEPTION USING ERRCODE='ZX901'; END IF;
 IF NOT denied AND (r->>'owner_id' IS DISTINCT FROM '{owner}' OR r->>'observation_id' IS DISTINCT FROM '{scan}'
  OR (r->>'snapshot')::JSONB->>'ordinal' IS DISTINCT FROM '1'
  OR r->>'snapshot_sha256' IS DISTINCT FROM encode(extensions.digest(convert_to(E'merian.observation-history.enrollment-baseline.v1\\n'||(r->>'snapshot'),'UTF8'),'sha256'),'hex'))
 THEN RAISE EXCEPTION USING ERRCODE='ZX902'; END IF;
END $$;
"""


def reply(q, label, owner, scan):
    request = '{"schema_version":1,"observation_id":"' + scan + '"}'
    output = q.execute(label, 'BEGIN;' + auth(owner)
                       + f"SELECT public.get_owned_observation_enrollment_baseline('{request}',9); COMMIT;")
    return json.loads(output.splitlines()[-1])


def run(q, operation, order):
    label = operation + '_' + order
    owner, target, scan, later, handoff, secret = seed(q, label)
    if operation == 'legacy_delete':
        writer_sql = SERVICE + f"""DO $$ BEGIN
 IF public.request_scan_deletion('{scan}','{owner}') IS DISTINCT FROM 'legacy_observation_delete_requires_upgrade'
 THEN RAISE EXCEPTION USING ERRCODE='ZX903'; END IF; END $$;"""
    elif operation == 'account_delete':
        writer_sql = SERVICE + f"SELECT public.apply_user_tombstone('{owner}');"
    else:
        writer_sql = auth(target) + f"""DO $$ DECLARE r RECORD; BEGIN
 SELECT * INTO STRICT r FROM public.consume_ghost_profile_merge_handoff('{handoff}','{secret}');
 IF r.already_merged IS DISTINCT FROM FALSE OR r.ghost_user_id IS DISTINCT FROM '{owner}'::UUID OR r.target_user_id IS DISTINCT FROM '{target}'::UUID
 THEN RAISE EXCEPTION USING ERRCODE='ZX904'; END IF; END $$;"""
    before = reply(q, label + '_original_response', owner, scan)
    sessions = []
    try:
        for name in ['reader', 'writer', 'observer']:
            sessions.append(Session(q, label + '_' + name))
        reader, writer, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('distinct backends required')
        if order == 'reader_first':
            reader.run('recover_existing_baseline', 'BEGIN;' + read(owner, scan))
            writer.start('writer_waits_for_recovery', 'BEGIN;' + writer_sql)
            wait_for_blocker(observer, writer, reader)
            reader.run('commit_read', 'COMMIT;')
            writer.finish()
            writer.run('commit_writer', 'COMMIT;')
        else:
            writer.run('writer_first', 'BEGIN;' + writer_sql)
            reader.start('recovery_waits_for_writer', 'BEGIN;' + read(owner, scan, operation != 'legacy_delete'))
            wait_for_blocker(observer, reader, writer)
            writer.run('commit_writer', 'COMMIT;')
            reader.finish()
            reader.run('commit_read', 'COMMIT;')
        reader.run('fresh_poststate_read', 'BEGIN;' + read(owner, scan, operation != 'legacy_delete') + 'COMMIT;')
        if operation == 'merge':
            after = reply(q, label + '_destination_response', target, scan)
            if after != dict(before, owner_id=target):
                raise ValueError('merge changed immutable baseline response')
        elif operation == 'legacy_delete':
            if reply(q, label + '_preserved_response', owner, scan) != before:
                raise ValueError('legacy deletion refusal changed baseline response')
        if operation == 'account_delete':
            condition = f"NOT EXISTS(SELECT 1 FROM public.users WHERE id='{owner}') AND NOT EXISTS(SELECT 1 FROM public.scans WHERE id='{scan}' AND user_id IS NOT NULL)"
        else:
            expected_owner = target if operation == 'merge' else owner
            condition = f"""EXISTS(SELECT 1 FROM public.scans WHERE id='{scan}' AND user_id='{expected_owner}' AND NOT is_tombstoned)
 AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id='{scan}')
 AND EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id='{scan}' AND selected_analysis_id='{later}' AND state_revision=4)
 AND (SELECT count(*) FROM internal.observation_analysis_results WHERE observation_id='{scan}')=2"""
        if q.execute(label + '_terminal_facts', 'SELECT ' + condition + ';') != 't':
            raise ValueError('terminal facts mismatch')
        q.record.setdefault('orders', []).append({'operation': operation, 'order': order, 'exact_blocker_observed': True, 'source_sorts_before_target': owner < target, 'passed': True})
        q.save()
    finally:
        # Release the held first actor before waiting on its peer during failure.
        ordered = sessions if order == 'reader_first' else sessions[1:2] + sessions[:1] + sessions[2:]
        for session in ordered:
            session.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence, 'baseline-recovery-races', args.replay_manifest)
    q.record['scope'] = 'Actual authenticated baseline read against legacy deletion refusal, service-role account tombstone and authenticated successful Ghost merge, both orders with observed blockers. Local synthetic SQL only; no hosted/provider/native or fault/crash qualification.'
    q.record['owner_order_limit'] = 'Random fixture owner ordering is recorded per case; not exhaustive coverage of both owner-ID orderings for every transaction schedule.'
    q.record['source_manifest'][str(Path(__file__).relative_to(Path(__file__).resolve().parents[3]))] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    q.save()
    for operation in ['legacy_delete', 'account_delete', 'merge']:
        for order in ['reader_first', 'writer_first']:
            run(q, operation, order)
    q.execute('restore_reader_holds', 'UPDATE internal.observation_history_rollout SET reader_enabled=FALSE,state_reader_enabled=FALSE;')
    q.record['passed'] = True
    q.save()
    print('PASS six both-order recovery schedules')


if __name__ == '__main__':
    main()

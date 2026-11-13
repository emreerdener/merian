"""Both-order atomic enrollment pair versus the actual authenticated selector.

Requires an exact owned disposable replay. SQL and synthetic reply bodies remain
in memory; evidence retains source hashes, assertions and observed blockers only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import uuid

from initial_atomic_admission_sessions import Session
from initial_atomic_admission_test_support import Qualification, ROOT
from initial_invocation_erasure_races import wait_for_blocker
from test_observation_baseline_recovery_races import auth

FIXTURE = ROOT / 'services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-selection-v1.json'


def seed(q, label):
    owner, scan, later = [str(uuid.uuid4()) for _ in range(3)]
    wire = json.loads(json.loads(FIXTURE.read_text())['selected_state']['analysis']['snapshot'])
    wire['result']['scan_id'] = scan
    result = json.dumps(wire['result']).replace("'", "''")
    evidence = json.dumps(wire['evidence_manifest']).replace("'", "''")
    q.execute(label + '_fixture', f"""
BEGIN;
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('{owner}','authenticated','authenticated','{owner}@example.invalid','{{}}','{{}}',now(),now());
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
VALUES('{scan}','{owner}','failed_terminal','server_replay_limit_reached','replay_exhausted');
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
VALUES('{scan}','{owner}','{{}}',0.9,TRUE,'flash','private');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,selection_enabled=TRUE,selection_api_enabled=TRUE;
{auth(owner)}
DO $$ BEGIN PERFORM public.enroll_owned_observation_history('{scan}',9); END $$;
RESET ROLE;
UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE,saved_import_enabled=FALSE;
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
VALUES('{later}','{scan}',2,repeat('a',64),now(),'{result}','{evidence}');
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'{later}',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='{scan}';
COMMIT;
""")
    initial = json.loads(q.execute(label + '_baseline', f"SELECT jsonb_build_object('analysis',selected_analysis_id,'revision',state_revision) FROM internal.observation_histories WHERE observation_id='{scan}';"))
    return owner, scan, later, str(uuid.UUID(initial['analysis'])), int(initial['revision'])


def read(owner, scan, original, selected, revision):
    request = json.dumps({'schema_version': 1, 'observation_id': scan})
    return auth(owner) + f"""
DO $$ DECLARE r JSONB; a JSONB; b JSONB; BEGIN
 r:=public.get_owned_observation_enrollment_selection('{request}',11);
 a:=r->'baseline_state'; b:=r->'selected_state';
 IF r-ARRAY['schema_version','baseline_sha256','baseline_state','selected_state'] IS DISTINCT FROM '{{}}'::JSONB
 OR r->'schema_version' IS DISTINCT FROM '1'::JSONB
 OR a->>'owner_id' IS DISTINCT FROM '{owner}' OR b->>'owner_id' IS DISTINCT FROM '{owner}'
 OR a->>'observation_id' IS DISTINCT FROM '{scan}' OR b->>'observation_id' IS DISTINCT FROM '{scan}'
 OR a->>'state_revision' IS DISTINCT FROM '{revision}' OR b->>'state_revision' IS DISTINCT FROM '{revision}'
 OR a->>'selected_analysis_id' IS DISTINCT FROM '{selected}' OR b->>'selected_analysis_id' IS DISTINCT FROM '{selected}'
 OR (a#>>'{{analysis,snapshot}}')::JSONB->>'analysis_id' IS DISTINCT FROM '{original}'
 OR (b#>>'{{analysis,snapshot}}')::JSONB->>'analysis_id' IS DISTINCT FROM '{selected}'
 OR a IS DISTINCT FROM public.get_owned_observation_analysis_state('{request}'::JSONB||jsonb_build_object('analysis_id','{original}'),11)
 OR b IS DISTINCT FROM public.get_owned_observation_analysis_state('{request}'::JSONB||jsonb_build_object('analysis_id',NULL),11)
 OR r->>'baseline_sha256' IS DISTINCT FROM encode(extensions.digest(convert_to(E'merian.observation-history.enrollment-baseline.v1\\n'||(a#>>'{{analysis,snapshot}}'),'UTF8'),'sha256'),'hex')
 THEN RAISE EXCEPTION USING ERRCODE='ZX910'; END IF;
END $$;
"""


def run(q, order):
    owner, scan, later, original, revision = seed(q, order)
    immutable_sql = f"SELECT jsonb_agg(to_jsonb(r) ORDER BY ordinal) FROM internal.observation_analysis_results r WHERE observation_id='{scan}';"
    before = json.loads(q.execute(order + '_original_result_bytes', immutable_sql))
    operation = str(uuid.uuid4())
    request = json.dumps({'schema_version': 1, 'observation_id': scan, 'analysis_id': later,
                          'operation_id': operation, 'expected_observation_revision': revision,
                          'expected_review_revision': 0})
    writer_sql = auth(owner) + f"""DO $$ DECLARE r JSONB; BEGIN
 r:=public.select_owned_observation_analysis('{request}',9);
 IF r->>'selected_analysis_id' IS DISTINCT FROM '{later}' OR r->>'observation_revision' IS DISTINCT FROM '{revision+1}'
 THEN RAISE EXCEPTION USING ERRCODE='ZX911'; END IF; END $$;"""
    sessions = []
    try:
        for name in ['reader', 'writer', 'observer']:
            sessions.append(Session(q, order + '_' + name))
        reader, writer, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError('distinct backends required')
        if order == 'reader_first':
            reader.run('pair_before_selection', 'BEGIN;' + read(owner, scan, original, original, revision))
            writer.start('selection_waits_for_pair', 'BEGIN;' + writer_sql)
            wait_for_blocker(observer, writer, reader)
            reader.run('commit_read', 'COMMIT;')
            writer.finish()
            writer.run('commit_selection', 'COMMIT;')
        else:
            writer.run('selection_first', 'BEGIN;' + writer_sql)
            reader.start('pair_waits_for_selection', 'BEGIN;' + read(owner, scan, original, later, revision + 1))
            wait_for_blocker(observer, reader, writer)
            writer.run('commit_selection', 'COMMIT;')
            reader.finish()
            reader.run('commit_read', 'COMMIT;')
        reader.run('fresh_pair_after_selection', 'BEGIN;' + read(owner, scan, original, later, revision + 1) + 'COMMIT;')
        condition = f"""(SELECT count(*) FROM internal.observation_analysis_results WHERE observation_id='{scan}')=2
 AND (SELECT count(*) FROM internal.observation_selection_receipts WHERE observation_id='{scan}' AND operation_id='{operation}')=1
 AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 AND NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage)"""
        if q.execute(order + '_immutable_results_single_selection_no_funding', 'SELECT ' + condition + ';') != 't':
            raise ValueError('terminal facts mismatch')
        if json.loads(q.execute(order + '_preserved_result_bytes', immutable_sql)) != before:
            raise ValueError('selection changed immutable result rows')
        q.record.setdefault('orders', []).append({'order': order, 'exact_blocker_observed': True, 'passed': True})
        q.save()
    finally:
        ordered = sessions if order == 'reader_first' else sessions[1:2] + sessions[:1] + sessions[2:]
        for session in ordered:
            session.close()


def main():
    parser = argparse.ArgumentParser()
    for name in ['container', 'evidence', 'replay-manifest']:
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence, 'enrollment-selection-races', args.replay_manifest)
    q.record['scope'] = 'Atomic baseline/current pair versus real authenticated selection in both orders, exact blockers and preserved results/funding. Local synthetic database only, not native persistence, all-media journey, crash or hosted acceptance.'
    for path in [Path(__file__).resolve(), FIXTURE, Path(__file__).with_name('test_observation_baseline_recovery_races.py'), Path(__file__).with_name('initial_invocation_erasure_races.py')]:
        q.record['source_manifest'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    q.save()
    for order in ['reader_first', 'writer_first']:
        run(q, order)
    q.execute('restore_reader_selection_holds', 'UPDATE internal.observation_history_rollout SET reader_enabled=FALSE,state_reader_enabled=FALSE,selection_enabled=FALSE,selection_api_enabled=FALSE;')
    q.record['passed'] = True
    q.save()
    print('PASS both-order enrollment pair/selection schedules')


if __name__ == '__main__':
    main()

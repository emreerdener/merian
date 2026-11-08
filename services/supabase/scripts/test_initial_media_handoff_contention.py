"""Both transfer/C1 winner orders in one owned disposable database.

The handoff owner is a privileged synthetic fixture; C1 uses its actual public
service-role entry point. Session scheduling proves locks and terminal state,
not the local bridge's separate five-second latency contract or physical I/O.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import time
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, Session
from initial_atomic_admission_test_support import Qualification, ROOT
from test_initial_media_handoff_owners import OPERATIONS

PRIVATE = [
    'initial_analysis_submissions', 'initial_analysis_admissions',
    'initial_preparation_admission_receipts', 'initial_media_copy_progress',
    'initial_media_verification_claims_v2', 'initial_media_verification_receipts_v2',
    'initial_preparation_transfer_receipts', 'initial_analysis_media_cohorts',
    'initial_analysis_media_preparations', 'initial_analysis_media_verifications',
    'initial_analysis_results', 'initial_analysis_completions',
    'initial_analysis_preparation_intents', 'initial_preparation_source_mapping',
    'initial_preparation_source_verifications', 'initial_preparation_execution_grants',
    'initial_preparation_output_manifests', 'initial_preparation_output_mapping',
    'initial_preparation_outcomes',
]
RELATIONS = ['public.users', 'public.scans', 'public.scan_ingestion_intents', 'public.scan_ingestion_jobs'] + ['internal.' + x for x in PRIVATE] + [
    'internal.initial_analysis_cancellations', 'internal.initial_analysis_lifecycle_fences',
    'internal.initial_preparation_source_fences', 'internal.initial_preparation_source_registry',
    'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_media_registry',
    'internal.initial_analysis_operation_fences', 'internal.ai_quota_reservations',
    'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters',
    'internal.complimentary_scan_usage', 'internal.identification_provider_attempts',
    'internal.identification_invocations', 'internal.initial_media_handoff_staging',
    'internal.initial_media_handoff_writes',
]
PROJECTION = 'jsonb_build_object(' + ','.join("'" + name + "',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)),'[]'::JSONB) FROM " + name + ' t)' for name in RELATIONS) + ')'
TRANSFER = """DO $$ DECLARE r internal.initial_preparation_admission_receipts; answer RECORD; v TEXT;BEGIN
SELECT * INTO STRICT r FROM target;SELECT digest INTO STRICT v FROM verification;
SELECT * INTO STRICT answer FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
IF answer.response->>'outcome' IS DISTINCT FROM 'transferred' OR answer.response->>'authority' IS DISTINCT FROM 'none'
 OR answer.transfer IS NULL OR NOT internal.initial_media_handoff_sealed()
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX770';END IF;
PERFORM internal.assert_initial_admission_live_receipt(r.owner_id,r.scan_id,r.admission_receipt_id);
END $$;"""
CANCEL = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;BEGIN
SELECT * INTO STRICT r FROM target;SET LOCAL ROLE service_role;
answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;
IF answer IS DISTINCT FROM '{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}'::JSONB
 OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX771';END IF;END $$;"""
DENIED = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;v TEXT;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;SELECT digest INTO STRICT v FROM verification;
BEGIN PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_cancelled' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX772';END IF;END $$;"""
TERMINAL = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;relation TEXT;present BOOLEAN;BEGIN
SELECT * INTO STRICT r FROM target;
FOR relation IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',relation) INTO present USING r.scan_id;
 IF present THEN RAISE EXCEPTION USING ERRCODE='ZX773';END IF;
END LOOP;
IF NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID
 AND user_id=r.owner_id AND original_analysis_id=r.scan_id AND state='refunded' AND refund_count=1)
 OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=r.owner_id AND client_scan_id=r.scan_id
 AND state='released' AND settlement_reason='cancelled_before_dispatch' AND settled_at IS NOT NULL AND settled_at=updated_at)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch='dispatch_prevented')
 OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'cancelled_pre_dispatch'
 OR (SELECT state FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR (SELECT state FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging) OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM source_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM media_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX774';END IF;
PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);
END $$;"""


def cases(q):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', "SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();"))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')
    def peer(name):
        s = Session(q, name)
        sessions.append(s)
        q.record.setdefault('backend_correlation', []).append({'session':name,'pid':s.pid})
        q.save()
        return s
    def blocking(observer, first, second):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                q.record.setdefault('observed_blockers', []).append({'blocker':first.name,'waiter':second.name})
                q.save()
                return
            time.sleep(0.04)
        raise RuntimeError('required transfer/C1 blocking not observed')
    try:
        fixture = AdmissionFixture(q)
        for cancellation_first in [False, True]:
            label = 'c1_first' if cancellation_first else 'transfer_first'
            a = fixture.admit_one()
            for name, args, _, _ in OPERATIONS[:-1]:
                q.execute(label + '_prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.execute(label + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            first, second, observer = [peer(label + '_' + x) for x in ['first','second','observer']]
            if len({s.pid for s in [first,second,observer]}) != 3:
                raise ValueError('distinct race backends required')
            target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM verification)<>1 OR NOT EXISTS(SELECT 1 FROM source_before) OR NOT EXISTS(SELECT 1 FROM media_before) THEN RAISE EXCEPTION USING ERRCODE='ZX775';END IF;END $$;"
            first.run('save_original_identity', BASE + target)
            second.run('save_original_identity', BASE + target)
            first.run('first_operation', CANCEL + TERMINAL if cancellation_first else TRANSFER)
            expected = first.run('terminal_digest_before_waiter', 'SELECT md5((' + PROJECTION + ')::TEXT);')[-1] if cancellation_first else None
            second.start('second_operation', DENIED if cancellation_first else CANCEL + TERMINAL)
            blocking(observer, first, second)
            first.run('commit_first', 'COMMIT;')
            second.finish()
            second.run('terminal_state_after_wait', TERMINAL)
            if expected is not None:
                actual = second.run('terminal_digest_after_waiter', 'SELECT md5((' + PROJECTION + ')::TEXT);')[-1]
                if actual != expected:
                    raise ValueError('denied original transfer changed terminal state')
            second.run('commit_second', 'COMMIT;')
            for s in [first, second, observer]:
                s.close()
                sessions.remove(s)
            q.execute(label + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.record['checks'].append({'case':label,'passed':True,'blocking_observed':True,'terminal_oracle_verified':True,'denied_transfer_unchanged':cancellation_first})
            q.save()
    finally:
        errors = []
        for s in sessions:
            try:s.close()
            except Exception as error:errors.append(type(error).__name__)
        if fixture is not None:
            try:fixture.close()
            except Exception as error:errors.append(type(error).__name__)
        q.execute('restore_inactive', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        logs = subprocess.run(['docker','logs','--since',started,q.command[3]],text=True,capture_output=True)
        count = len(re.findall(r'ERROR:.*deadlock detected',logs.stdout + logs.stderr))
        q.record.update(server_log_read_exit=logs.returncode,deadlock_reports=count,cleanup_errors=errors)
        q.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-transfer-c1', args.replay_manifest)
    for name in [Path(__file__), Path(__file__).with_name('test_initial_media_handoff_owners.py')]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Two real local backend transfer/C1 winner orders over original synthetic media and fixed owners. Actual public service-role C1; privileged private handoff fixture. Metadata-only blocker/terminal evidence. No physical I/O, installed adapters, five-second bridge contention or broader erasure/expiry/race qualification.'
    q.record['projection_relations'] = RELATIONS
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

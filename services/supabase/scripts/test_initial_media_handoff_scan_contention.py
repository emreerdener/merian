"""Defensive raw scan erasure versus transfer, with an explicit unreachable seam.

Normal same-ID scan insertion is rejected by the real provider barrier. Only
then does a local replica-only insertion construct the legacy/corrupt preimage.
This does not qualify a supported initial-identification or public deletion flow.
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
from test_initial_media_handoff_contention import PRIVATE, RELATIONS, TRANSFER
from test_initial_media_handoff_owners import OPERATIONS

LEDGER = ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'public.users']
PROJECTION_RELATIONS = RELATIONS + ['internal.scan_deletion_tombstones']


def projection(relations):
    return 'jsonb_build_array(' + ','.join("(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations) + ')'


FULL = projection(PROJECTION_RELATIONS)
ACCOUNT = projection(LEDGER)
NORMAL_INSERT_DENIED = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;b JSONB;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;b:=FULL;
BEGIN INSERT INTO public.scans(id,user_id,ai_confidence_score) VALUES(r.scan_id,r.owner_id,0);
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_preparation_provider_blocked' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR b IS DISTINCT FROM FULL OR EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX810';END IF;END $$;""".replace('FULL', FULL)
VISIBLE_SCAN_TRANSFER_DENIED = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;v TEXT;b JSONB;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;SELECT receipt_digest INTO STRICT v FROM internal.initial_media_verification_receipts_v2 WHERE scan_id=r.scan_id;b:=FULL;
BEGIN PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_admission_incomplete' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR b IS DISTINCT FROM FULL OR internal.initial_media_handoff_sealed()
 OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX819';END IF;END $$;""".replace('FULL', FULL)
PRECONDITION = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN
SELECT * INTO STRICT r FROM target;
IF (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'pending_pre_dispatch'
 OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id AND provider_barrier='blocked_pre_admission')
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID AND state='reserved' AND refund_count=0)
 OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state='held')
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
 OR NOT EXISTS(SELECT 1 FROM internal.identification_provider_attempts WHERE reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
 OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 THEN RAISE EXCEPTION USING ERRCODE='ZX811';END IF;END $$;"""
ERASURE = {
    'delete': 'DELETE FROM public.scans WHERE id=r.scan_id;',
    'detach': 'UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id=r.scan_id;',
}


def terminal(kind, check_scan=True):
    scan = "EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id)" if kind == 'delete' else "(SELECT to_jsonb(s) FROM public.scans s WHERE id=r.scan_id) IS DISTINCT FROM (SELECT to_jsonb(s)||'{\"user_id\":null,\"is_tombstoned\":true}'::JSONB FROM scan_before s)"
    if not check_scan:
        scan = 'FALSE'  # Waiter compares the whole post-erasure projection, including scans.
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;relation TEXT;present BOOLEAN;BEGIN
SELECT * INTO STRICT r FROM target;
FOR relation IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',relation) INTO present USING r.scan_id;
 IF present THEN RAISE EXCEPTION USING ERRCODE='ZX812';END IF;
END LOOP;
IF SCAN OR ACCOUNT IS DISTINCT FROM (SELECT value FROM account_before)
 OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=r.owner_id)
 OR NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=r.scan_id AND user_id IS NULL AND completed_at IS NOT NULL)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id)
 OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'cancelled_unknown'
 OR (SELECT state FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR (SELECT state FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging) OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM source_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM media_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id)
 OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX813';END IF;
PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);
END $$;""".replace('SCAN', scan).replace('ACCOUNT', ACCOUNT)


def erase(kind):
    return 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM target;' + ERASURE[kind] + "IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='ZX814';END IF;END $$;" + terminal(kind)


def fail_fast(kind):
    # Reject lock_timeout's identical SQLSTATE: only NOWAIT/try-lock denial counts.
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;b JSONB;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;b:=FULL;
BEGIN ERASURE
EXCEPTION WHEN SQLSTATE '55P03' THEN
 IF SQLERRM NOT IN ('could not obtain lock on row in relation "users"','initial_analysis_erasure_busy') THEN RAISE;END IF;
 failed:=TRUE;END;
IF NOT failed OR b IS DISTINCT FROM FULL OR internal.initial_media_handoff_sealed()
 OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX815';END IF;END $$;""".replace('ERASURE', ERASURE[kind]).replace('FULL', FULL)


def denied(kind, expected):
    code, message = ('55000', 'initial_analysis_deleted') if kind == 'delete' else ('P0002', 'initial_analysis_owner_unavailable')
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;v TEXT;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;SELECT digest INTO STRICT v FROM verification;
BEGIN PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
EXCEPTION WHEN SQLSTATE 'CODE' THEN IF SQLERRM<>'MESSAGE' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR md5((FULL)::TEXT) IS DISTINCT FROM 'EXPECTED'
 THEN RAISE EXCEPTION USING ERRCODE='ZX816';END IF;END $$;""".replace("'CODE'", "'" + code + "'").replace('MESSAGE', message).replace('FULL', FULL).replace('EXPECTED', expected) + terminal(kind, False)


def cases(q, kind):
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    catalog = json.loads(q.execute('exact_private_catalog', "SELECT json_agg(relation_name ORDER BY relation_name) FROM internal.initial_cancellation_private_catalog();"))
    if catalog != sorted('internal.' + x for x in PRIVATE):
        raise ValueError('private catalog drift')

    def peer(name):
        s = Session(q, name)
        sessions.append(s)
        q.record.setdefault('backend_correlation', []).append({'session': name, 'pid': s.pid})
        q.save()
        return s

    try:
        fixture = AdmissionFixture(q)
        for transfer_first in [True, False]:
            label = kind + ('_transfer_first' if transfer_first else '_erasure_first')
            a = fixture.admit_one(owner_id=fixture.owner if transfer_first else fixture.foreign)
            for name, args, _, _ in OPERATIONS[:-1]:
                q.execute(label + '_prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            identity = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';"
            q.execute(label + '_normal_insert_and_visible_scan_transfer_denied_rollback', BASE + identity + PRECONDITION + NORMAL_INSERT_DENIED + "SET LOCAL session_replication_role=replica;INSERT INTO public.scans(id,user_id,ai_confidence_score) SELECT scan_id,owner_id,0 FROM target;SET LOCAL session_replication_role=origin;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;" + VISIBLE_SCAN_TRANSFER_DENIED + 'ROLLBACK;')
            q.execute(label + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            first, second, observer = [peer(label + '_' + x) for x in ['first', 'second', 'observer']]
            if len({s.pid for s in [first, second, observer]}) != 3:
                raise ValueError('distinct race backends required')
            target = identity + "CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE account_before AS SELECT " + ACCOUNT + " AS value;DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM verification)<>1 OR NOT EXISTS(SELECT 1 FROM source_before) OR NOT EXISTS(SELECT 1 FROM media_before) THEN RAISE EXCEPTION USING ERRCODE='ZX817';END IF;END $$;" + PRECONDITION
            first.run('save_original_identity', BASE + target)
            second.run('save_original_identity', BASE + target)
            if transfer_first:
                first.run('transfer_uncommitted', TRANSFER)
            eraser = second if transfer_first else first
            # Never expose the synthetic scan to live-proof validation before
            # transfer: it exists only in the eraser's uncommitted transaction.
            eraser.run('explicit_uncommitted_replica_scan_preimage', "SET LOCAL session_replication_role=replica;INSERT INTO public.scans(id,user_id,ai_confidence_score) SELECT scan_id,owner_id,0 FROM target;SET LOCAL session_replication_role=origin;CREATE TEMP TABLE scan_before AS SELECT s.* FROM public.scans s JOIN target r ON s.id=r.scan_id;DO $$ BEGIN IF (SELECT count(*) FROM scan_before)<>1 OR EXISTS(SELECT 1 FROM scan_before WHERE species_id IS NOT NULL OR is_tombstoned OR cardinality(image_storage_urls)<>0) OR " + ACCOUNT + " IS DISTINCT FROM (SELECT value FROM account_before) THEN RAISE EXCEPTION USING ERRCODE='ZX818';END IF;END $$;")
            if transfer_first:
                second.run('raw_erasure_nowait_denied_unchanged', fail_fast(kind))
                first.run('commit_transfer', 'COMMIT;')
                second.run('explicit_erasure_after_known_denial', erase(kind))
            else:
                first.run('raw_erasure_uncommitted', erase(kind))
                rows = first.run('terminal_digest', 'SELECT md5((' + FULL + ')::TEXT);')
                if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
                    raise ValueError('single terminal digest required')
                second.start('transfer_after_erasure', denied(kind, rows[0]))
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if second.process.poll() is not None:
                        second.finish()  # Preserve a failed waiter's sanitized SQL evidence.
                        raise RuntimeError('waiter exited before required blocking')
                    if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                        q.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                        q.save()
                        break
                    time.sleep(0.04)
                else:
                    raise RuntimeError('required raw erasure/transfer blocking not observed')
                first.run('commit_erasure', 'COMMIT;')
                second.finish()
            second.run('terminal_and_commit', terminal(kind, transfer_first) + 'COMMIT;')
            for s in [first, second, observer]:
                s.close()
                sessions.remove(s)
            q.execute(label + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.record['checks'].append({'case': label, 'passed': True, 'normal_insert_denied': True, 'visible_scan_transfer_denied': True, 'replica_only_scan_preimage': True, 'nowait_denial_unchanged': transfer_first, 'blocking_observed': not transfer_first, 'original_ledger_and_users_unchanged': True, 'terminal_oracle_verified': True})
            q.save()
    finally:
        errors = []
        for s in sessions:
            try:
                s.close()
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        q.execute('restore_inactive', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
        logs = subprocess.run(['docker', 'logs', '--since', started, q.command[3]], text=True, capture_output=True)
        count = len(re.findall(r'ERROR:.*deadlock detected', logs.stdout + logs.stderr))
        q.record.update(server_log_read_exit=logs.returncode, deadlock_reports=count, cleanup_errors=errors)
        q.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--container', required=True)
    parser.add_argument('--evidence-directory', required=True)
    parser.add_argument('--replay-manifest', required=True)
    parser.add_argument('--root', choices=['delete', 'detach'], required=True)
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-scan-' + args.root, args.replay_manifest)
    for name in [Path(__file__), Path(__file__).with_name('test_initial_media_handoff_contention.py'), Path(__file__).with_name('test_initial_media_handoff_owners.py')]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Defensive raw scan ' + args.root + '/private transfer in both orders after proven normal INSERT denial and explicitly uncommitted replica-only unreachable scan preimage; guarded transfer starts without a visible scan. Transfer-first raw operation fails NOWAIT without change, then explicit erasure after known denial; erasure-first blocks original transfer then denies it unchanged. Original accounting/users exact; no public deletion/user journey, physical I/O, installed or five-second resource qualification.'
    q.record['projection_relations'] = PROJECTION_RELATIONS
    q.save()
    cases(q, args.root)
    q.finish()


if __name__ == '__main__':
    main()

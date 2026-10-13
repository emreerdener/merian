"""Actual account tombstone versus private transfer in both winner orders.

Privileged synthetic ghost admissions and local observation-only trigger seams.
No scan-deletion journey, physical erasure, provider or installed qualification.
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
from test_initial_media_handoff_contention import PRIVATE, PROJECTION, TRANSFER
from test_initial_media_handoff_owners import OPERATIONS

ACCOUNT_RELATIONS = ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'public.users']
ACCOUNT_PROJECTION = 'jsonb_build_array(' + ','.join("(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in ACCOUNT_RELATIONS) + ')'
HOOKS = """
CREATE FUNCTION pg_temp.handoff_account_no_mutation() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN
 IF current_setting('merian.test_handoff_account',TRUE)='on' THEN RAISE EXCEPTION USING ERRCODE='ZX790';END IF;RETURN NULL;END $$;
CREATE FUNCTION pg_temp.handoff_account_before_user() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE r internal.initial_preparation_admission_receipts; expected TEXT;relation TEXT;present BOOLEAN;BEGIN
 IF current_setting('merian.test_handoff_account',TRUE) IS DISTINCT FROM 'on' THEN RETURN OLD;END IF;
 SELECT * INTO STRICT r FROM pg_temp.target;SELECT digest INTO STRICT expected FROM pg_temp.account_expected;
 IF OLD.id<>r.owner_id OR md5(ACCOUNT_PROJECTION::TEXT) IS DISTINCT FROM expected
 OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() OR internal.initial_media_handoff_sealed()
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch='dispatch_outcome_unknown')
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID AND state='reserved' AND refund_count=0)
 OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=r.owner_id AND client_scan_id=r.scan_id AND state='held')
 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.user_id=r.owner_id)
 OR NOT EXISTS(SELECT 1 FROM internal.identification_provider_attempts a JOIN internal.ai_quota_reservations q ON q.id=a.reservation_id WHERE q.user_id=r.owner_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX791';END IF;
 FOR relation IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',relation) INTO present USING r.scan_id;
  IF present THEN RAISE EXCEPTION USING ERRCODE='ZX792';END IF;
 END LOOP;
 PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);
 INSERT INTO pg_temp.account_seen SELECT 'quota',to_jsonb(t) FROM internal.ai_quota_reservations t WHERE user_id=r.owner_id;
 INSERT INTO pg_temp.account_seen SELECT 'hold',to_jsonb(t) FROM internal.complimentary_scan_usage t WHERE user_id=r.owner_id;
 INSERT INTO pg_temp.account_seen SELECT 'attempt',to_jsonb(t) FROM internal.identification_provider_attempts t JOIN internal.ai_quota_reservations q ON q.id=t.reservation_id WHERE q.user_id=r.owner_id;
 INSERT INTO pg_temp.account_seen SELECT 'link',to_jsonb(t) FROM internal.ai_quota_reservation_counters t JOIN internal.ai_quota_reservations q ON q.id=t.reservation_id WHERE q.user_id=r.owner_id;
 INSERT INTO pg_temp.account_seen SELECT 'counters',coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters t;
 INSERT INTO pg_temp.account_seen VALUES('user_marker','true'::JSONB);RETURN OLD;
END $$;
CREATE FUNCTION pg_temp.handoff_account_cascade_row() RETURNS TRIGGER LANGUAGE plpgsql AS $$ DECLARE k TEXT;BEGIN
 IF current_setting('merian.test_handoff_account',TRUE) IS DISTINCT FROM 'on' THEN RETURN OLD;END IF;
 k:=CASE TG_TABLE_NAME WHEN 'ai_quota_reservations' THEN 'quota' WHEN 'complimentary_scan_usage' THEN 'hold' WHEN 'identification_provider_attempts' THEN 'attempt' ELSE 'link' END;
 IF (SELECT count(*) FROM pg_temp.account_seen WHERE kind='user_marker')<>1 OR NOT EXISTS(SELECT 1 FROM pg_temp.account_seen WHERE kind=k AND value=to_jsonb(OLD)) THEN RAISE EXCEPTION USING ERRCODE='ZX793';END IF;
 INSERT INTO pg_temp.account_seen VALUES(k||'_deleted',to_jsonb(OLD));RETURN OLD;END $$;
-- Observe legacy cancellation before the real owner fence creates its tombstone
-- and deletes the cancellation row. Subsequent mutation tripwires/cascade image
-- checks still cover every real owner-fence and user-cascade operation.
CREATE TRIGGER a_test_handoff_account_before_user BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.handoff_account_before_user();
""".replace('ACCOUNT_PROJECTION', ACCOUNT_PROJECTION)
for table in ACCOUNT_RELATIONS:
    HOOKS += 'CREATE TRIGGER test_handoff_account_no_update BEFORE UPDATE ON ' + table + ' FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.handoff_account_no_mutation();'
for table in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts']:
    HOOKS += 'CREATE TRIGGER test_handoff_account_cascade BEFORE DELETE ON ' + table + ' FOR EACH ROW EXECUTE FUNCTION pg_temp.handoff_account_cascade_row();'
HOOKS += 'CREATE TRIGGER test_handoff_account_no_counter_delete BEFORE DELETE ON internal.ai_quota_counters FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.handoff_account_no_mutation();'

TERMINAL = """DO $$ DECLARE r internal.initial_preparation_admission_receipts;relation TEXT;present BOOLEAN;BEGIN
SELECT * INTO STRICT r FROM target;
FOR relation IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',relation) INTO present USING r.scan_id;
 IF present THEN RAISE EXCEPTION USING ERRCODE='ZX794';END IF;
END LOOP;
IF EXISTS(SELECT 1 FROM public.users WHERE id=r.owner_id)
 OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=r.owner_id)
 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=(r.funding::JSONB#>>'{original,reservation_id}')::UUID)
 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=r.owner_id)
 OR (SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'cancelled_unknown'
 OR (SELECT state FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR (SELECT state FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id) IS DISTINCT FROM 'retired'
 OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.identification_provider_attempts)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=r.scan_id)
 OR EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id)
 OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_staging) OR EXISTS(SELECT 1 FROM internal.initial_media_handoff_writes)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM source_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id)
 OR (SELECT jsonb_agg(to_jsonb(t)||'{"retired":true}'::JSONB ORDER BY object_id) FROM media_before t)
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id)
 THEN RAISE EXCEPTION USING ERRCODE='ZX795';END IF;
PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);
END $$;"""


def account(expected):
    return "INSERT INTO account_expected VALUES('" + expected + "');DO $$ DECLARE r internal.initial_preparation_admission_receipts;k TEXT;BEGIN SELECT * INTO STRICT r FROM target;PERFORM set_config('merian.test_handoff_account','on',TRUE);SET LOCAL ROLE service_role;PERFORM public.apply_user_tombstone(r.owner_id);RESET ROLE;" + """
IF (SELECT count(*) FROM account_seen WHERE kind='user_marker')<>1
 OR (SELECT count(*) FROM account_seen WHERE kind='quota_deleted')<>1
 OR (SELECT count(*) FROM account_seen WHERE kind='hold_deleted')<>1
 OR (SELECT value FROM account_seen WHERE kind='counters') IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters t)
 OR internal.initial_cancellation_sealed() OR internal.initial_media_handoff_sealed()
 THEN RAISE EXCEPTION USING ERRCODE='ZX796';END IF;
FOR k IN SELECT unnest(ARRAY['quota','hold','link','attempt']) LOOP
 IF NOT EXISTS(SELECT 1 FROM account_seen WHERE kind=k) OR NOT EXISTS(SELECT 1 FROM account_seen WHERE kind=k||'_deleted')
 OR (SELECT coalesce(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) FROM account_seen WHERE kind=k)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) FROM account_seen WHERE kind=k||'_deleted') THEN RAISE EXCEPTION USING ERRCODE='ZX797';END IF;
END LOOP;END $$;
""" + TERMINAL


def denied(expected):
    return """DO $$ DECLARE r internal.initial_preparation_admission_receipts;v TEXT;failed BOOLEAN:=FALSE;BEGIN
SELECT * INTO STRICT r FROM target;SELECT digest INTO STRICT v FROM verification;
BEGIN PERFORM * FROM internal.transfer_initial_preparation_v2(r.owner_id,r.scan_id,r.receipt_digest,v);
EXCEPTION WHEN SQLSTATE 'P0002' THEN IF SQLERRM<>'initial_analysis_owner_unavailable' THEN RAISE;END IF;failed:=TRUE;END;
IF NOT failed OR internal.initial_media_handoff_sealed() OR internal.initial_cancellation_sealed()
 OR md5((""" + PROJECTION + ")::TEXT) IS DISTINCT FROM '" + expected + "' THEN RAISE EXCEPTION USING ERRCODE='ZX798';END IF;END $$;" + TERMINAL


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
        q.record.setdefault('backend_correlation', []).append({'session': name, 'pid': s.pid})
        q.save()
        return s

    def digest(s, label, projection):
        rows = s.run(label, 'SELECT md5((' + projection + ')::TEXT);')
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
            raise ValueError('single original projection digest required')
        return rows[0]

    try:
        fixture = AdmissionFixture(q)
        fixture.session.run('install_observation_only_account_hooks', HOOKS)
        for transfer_first in [True, False]:
            label = 'transfer_first' if transfer_first else 'account_first'
            a = fixture.admit_one(owner_id=fixture.owner if transfer_first else fixture.foreign)
            for name, args, _, _ in OPERATIONS[:-1]:
                q.execute(label + '_prepare_' + name, "BEGIN;SET LOCAL statement_timeout='45s';UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;DO $$ DECLARE r internal.initial_preparation_admission_receipts;BEGIN SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "';PERFORM * FROM internal." + name + '(r.owner_id,r.scan_id,r.receipt_digest' + args + ');END $$;COMMIT;UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.execute(label + '_enable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;')
            first, second, observer = [peer(label + '_' + x) for x in ['first', 'second', 'observer']]
            if len({s.pid for s in [first, second, observer]}) != 3:
                raise ValueError('distinct race backends required')
            target = "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + a.scan_id + "' AND owner_id='" + a.owner_id + "';CREATE TEMP TABLE verification AS SELECT receipt_digest AS digest FROM internal.initial_media_verification_receipts_v2 WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE source_before AS SELECT * FROM internal.initial_preparation_source_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE media_before AS SELECT * FROM internal.initial_analysis_media_registry WHERE scan_id='" + a.scan_id + "';CREATE TEMP TABLE account_expected(digest TEXT);CREATE TEMP TABLE account_seen(kind TEXT,value JSONB);DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 OR (SELECT count(*) FROM verification)<>1 OR NOT EXISTS(SELECT 1 FROM source_before) OR NOT EXISTS(SELECT 1 FROM media_before) THEN RAISE EXCEPTION USING ERRCODE='ZX799';END IF;END $$;"
            first.run('save_original_identity', BASE + target)
            second.run('save_original_identity', BASE + target)
            original_account = digest(first, 'original_accounting', ACCOUNT_PROJECTION)
            if transfer_first:
                first.run('transfer_uncommitted', TRANSFER)
                second.start('account_after_transfer', account(original_account))
            else:
                first.run('account_uncommitted', account(original_account))
                terminal = digest(first, 'erased_terminal_projection', PROJECTION)
                second.start('transfer_after_account', denied(terminal))
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if observer.run('observe_exact_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                    q.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                    q.save()
                    break
                time.sleep(0.04)
            else:
                raise RuntimeError('required transfer/account blocking not observed')
            first.run('commit_first', 'COMMIT;')
            second.finish()
            second.run('terminal_after_wait', TERMINAL)
            second.run('commit_second', 'COMMIT;')
            for s in [first, second, observer]:
                s.close()
                sessions.remove(s)
            q.execute(label + '_disable_disposable_fixture', 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;')
            q.record['checks'].append({'case': label, 'passed': True, 'blocking_observed': True, 'accounting_unchanged_before_user_delete': True, 'exact_cascade_images_verified': True, 'unknown_erasure_no_refund': True, 'terminal_oracle_verified': True})
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
    args = parser.parse_args()
    q = Qualification(args.container, args.evidence_directory, 'initial-media-handoff-account-contention', args.replay_manifest)
    for name in [Path(__file__), Path(__file__).with_name('test_initial_media_handoff_contention.py'), Path(__file__).with_name('test_initial_media_handoff_owners.py')]:
        q.record['source_manifest'][str(name.resolve().relative_to(ROOT))] = q.digest(name)
    q.record['scope'] = 'Two actual service-role account tombstone/private transfer winner orders over synthetic ghost admissions. Observation-only temporary-trigger seams verify no accounting mutation/refund before user deletion and exact cascade OLD images. Observed blocking, dynamic19private absence and retained retired registries/fences; no raw scan/public scan deletion journey, storage erasure, provider, installed or five-second bridge/resource qualification.'
    q.save()
    cases(q)
    q.finish()


if __name__ == '__main__':
    main()

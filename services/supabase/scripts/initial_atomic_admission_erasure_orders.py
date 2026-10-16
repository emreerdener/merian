"""Public scan-deletion no-op versus cancellation in both orders."""
import datetime
import re
import subprocess
import time
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, PROJECTION, Session

def scan_delete_order_cases(qualification):
    (base, projection) = (BASE, PROJECTION)
    execute = qualification.execute
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = 'Two actual service-role scan-deletion no-op/cancellation orders with successive held synthetic admissions. Enumerated 21-relation projection; no successful scan erasure/provider/media IO/hosted qualification.'

    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session

    def blocking(observer, first, second):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if observer.run('observe_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                qualification.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                qualification.save()
                return
            time.sleep(0.04)
        raise RuntimeError('expected recovery/cancellation blocking missing')

    def close_group(group):
        errors = []
        for session in group:
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
            finally:
                sessions.remove(session)
        if errors:
            qualification.record['close_errors'] = errors
            qualification.save()
            raise RuntimeError('session cleanup failed')
    no_authority = "IF internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX532';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);"
    callers = {'scan_delete': 'public.request_scan_deletion(r.scan_id,r.owner_id)'}

    def recover(caller, cancelled=False, expected=None):
        body = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer TEXT;before_state JSONB;BEGIN SELECT * INTO STRICT r FROM target;'
        body += "IF EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id) OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=r.scan_id) THEN RAISE EXCEPTION USING ERRCODE='ZX541';END IF;"
        body += 'before_state:=' + projection + ';SET LOCAL ROLE service_role;answer:=public.request_scan_deletion(r.scan_id,r.owner_id);RESET ROLE;'
        body += "IF answer IS DISTINCT FROM 'not_found' THEN RAISE EXCEPTION USING ERRCODE='ZX542';END IF;"
        if cancelled:
            body += 'IF md5((' + projection + ")::TEXT) IS DISTINCT FROM '" + expected + "' THEN RAISE EXCEPTION USING ERRCODE='ZX543';END IF;"
        else:
            body += 'IF before_state IS DISTINCT FROM ' + projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX544';END IF;"
        body += "IF EXISTS(SELECT 1 FROM public.scans WHERE id=r.scan_id) OR EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=r.scan_id) THEN RAISE EXCEPTION USING ERRCODE='ZX545';END IF;"
        return body + no_authority + 'END $$;'
    cancel = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_owner JSONB;other_users JSONB;old_terminals JSONB;life JSONB;sf JSONB;df JSONB;sr JSONB;dr JSONB;BEGIN\n SELECT * INTO STRICT r FROM target;\n SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=r.owner_id;\n SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;\n SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) INTO old_terminals FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'cancelled_pre_dispatch\') INTO STRICT life FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT sf FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT df FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO sr FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO dr FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id;\n SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;\n IF answer IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB\n OR (SELECT to_jsonb(u) FROM public.users u WHERE id=r.owner_id) IS DISTINCT FROM before_owner||jsonb_build_object(\'complimentary_entitlement_epoch\',(before_owner->>\'complimentary_entitlement_epoch\')::BIGINT+1,\'entitlement_version\',(before_owner->>\'entitlement_version\')::BIGINT+1)\n OR (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>r.owner_id) IS DISTINCT FROM other_users\n OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id) IS DISTINCT FROM old_terminals\n OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND user_id=r.owner_id AND state=\'refunded\' AND refund_count=1)\n OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state=\'released\' AND settlement_reason=\'cancelled_before_dispatch\' AND settled_at IS NOT NULL AND settled_at=updated_at)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch=\'dispatch_prevented\')\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM life\n OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM sf\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM df\n OR sr IS NULL OR dr IS NULL\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM sr\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM dr\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX537\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\nEND $$;\n'
    try:
        fixture = AdmissionFixture(qualification, held=True)
        for caller in callers:
            for cancellation_first in (False, True):
                phase = caller + ('_cancellation_first' if cancellation_first else '_scan_delete_first')
                identity = fixture.admit_one()
                start = base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE owner_id='" + identity.owner_id + "' AND scan_id='" + identity.scan_id + "' AND admission_receipt_id='" + identity.receipt_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX531';END IF;END $$;"
                first = peer(phase + '_first')
                second = peer(phase + '_second')
                observer = peer(phase + '_observer')
                if len({s.pid for s in sessions}) != 3:
                    raise RuntimeError('distinct backends required')
                first.run('save_original_identity', start)
                second.run('save_original_identity', start)
                if cancellation_first:
                    result = first.run('cancel_then_capture_expected', cancel + 'SELECT md5((' + projection + ')::TEXT);')
                    if len(result) != 1 or not re.fullmatch('[0-9a-f]{32}', result[0]):
                        raise RuntimeError('single private comparison image required')
                    second.start('recover_cancelled_original', recover(caller, True, result[0]))
                else:
                    first.run('recover_original', recover(caller))
                    second.start('cancel_after_recovery', cancel)
                blocking(observer, first, second)
                first.run('first_commit', 'COMMIT;')
                second.finish()
                second.run('second_commit', 'COMMIT;')
                close_group([first, second, observer])
                qualification.record['checks'].append({'case': phase, 'passed': True, 'blocking_observed': True, 'both_committed': True, 'actual_service_role_wrappers': True, 'original_accounting_and_owner_delta_verified': True, 'scan_delete_no_business_change': True})
                qualification.save()
        fixture.close()
        fixture = None
        execute('fresh_final_two_original_refunds_no_private_roots_or_authority', "DO $$ DECLARE c RECORD;BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations WHERE dispatch='dispatch_prevented')<>2 OR (SELECT count(*) FROM internal.ai_quota_reservations)<>2 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'refunded' OR refund_count<>1) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters) OR (SELECT count(*) FROM internal.complimentary_scan_usage)<>2 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state IS DISTINCT FROM 'released' OR settlement_reason IS DISTINCT FROM 'cancelled_before_dispatch' OR settled_at IS NULL OR settled_at IS DISTINCT FROM updated_at) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX538';END IF;FOR c IN SELECT scan_id FROM internal.initial_analysis_cancellations LOOP IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=c.scan_id AND state='cancelled_pre_dispatch') OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=c.scan_id AND state='retired') OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=c.scan_id AND state='retired') OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=c.scan_id) OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=c.scan_id)<>1 OR (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=c.scan_id)<>1 OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=c.scan_id AND (retired IS DISTINCT FROM TRUE OR marker_confirmed IS DISTINCT FROM FALSE OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL)) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=c.scan_id AND (retired IS DISTINCT FROM TRUE OR marker_confirmed IS DISTINCT FROM FALSE OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL)) THEN RAISE EXCEPTION USING ERRCODE='ZX539';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(c.scan_id);END LOOP;END $$;")
    finally:
        errors = []
        if sessions:
            try:
                close_group(list(sessions))
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        logs = subprocess.run(['docker', 'logs', '--since', started, qualification.command[3]], text=True, capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall('ERROR:.*deadlock detected', raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [{'waiter': int(a), 'mode': mode, 'lock_object': lock, 'blocker': int(b)} for (a, mode, lock, b) in re.findall('Process (\\d+) waits for ([A-Za-z]+) on (transaction \\d+|relation \\d+ of database \\d+|tuple \\(\\d+,\\d+\\) of relation \\d+ of database \\d+|virtual transaction \\d+/\\d+); blocked by process (\\d+)', raw)]
            qualification.record['deadlock_root_cause_established'] = False
        qualification.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')


def account_order_cases(qualification):
    base, projection = BASE, PROJECTION
    execute = qualification.execute
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = ('Two actual service-role account tombstone/C1 orders. Pre-user-delete accounting and cascade-row observations; global fences and retired registries retained. Trusted synthetic held admissions, no external erasure/provider/installed qualification.')
    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session
    def blocking(observer, first, second):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if observer.run('observe_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                qualification.record.setdefault('observed_blockers', []).append({'blocker': first.name, 'waiter': second.name})
                qualification.save()
                return
            time.sleep(0.04)
        raise RuntimeError('expected recovery/cancellation blocking missing')
    def close_group(group):
        errors = []
        for session in group:
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
            finally:
                sessions.remove(session)
        if errors:
            qualification.record['close_errors'] = errors
            qualification.save()
            raise RuntimeError('session cleanup failed')
    no_authority = "IF internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX532';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);"
    cancel = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_owner JSONB;other_users JSONB;old_terminals JSONB;life JSONB;sf JSONB;df JSONB;sr JSONB;dr JSONB;BEGIN\n SELECT * INTO STRICT r FROM target;\n SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=r.owner_id;\n SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;\n SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) INTO old_terminals FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'cancelled_pre_dispatch\') INTO STRICT life FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT sf FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT df FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO sr FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO dr FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id;\n SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;\n IF answer IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB\n OR (SELECT to_jsonb(u) FROM public.users u WHERE id=r.owner_id) IS DISTINCT FROM before_owner||jsonb_build_object(\'complimentary_entitlement_epoch\',(before_owner->>\'complimentary_entitlement_epoch\')::BIGINT+1,\'entitlement_version\',(before_owner->>\'entitlement_version\')::BIGINT+1)\n OR (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>r.owner_id) IS DISTINCT FROM other_users\n OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id) IS DISTINCT FROM old_terminals\n OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND user_id=r.owner_id AND state=\'refunded\' AND refund_count=1)\n OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state=\'released\' AND settlement_reason=\'cancelled_before_dispatch\' AND settled_at IS NOT NULL AND settled_at=updated_at)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch=\'dispatch_prevented\')\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM life\n OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM sf\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM df\n OR sr IS NULL OR dr IS NULL\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM sr\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM dr\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX537\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\nEND $$;\n'
    account_relations = ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'public.users']
    account_projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in account_relations)) + ')'
    hooks = "\nCREATE FUNCTION pg_temp.account_no_mutation() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN\n IF current_setting('merian.test_account_actor',TRUE)='on' THEN RAISE EXCEPTION USING ERRCODE='ZX551';END IF;RETURN NULL;END $$;\nCREATE FUNCTION pg_temp.account_before_user() RETURNS TRIGGER LANGUAGE plpgsql AS $$ DECLARE r internal.initial_preparation_admission_receipts;expected TEXT;prevented BOOLEAN;BEGIN\n IF current_setting('merian.test_account_actor',TRUE) IS DISTINCT FROM 'on' THEN RETURN OLD;END IF;\n SELECT * INTO STRICT r FROM pg_temp.target;SELECT digest,c1_first INTO STRICT expected,prevented FROM pg_temp.account_expected;\n IF OLD.id<>r.owner_id OR md5(ACCOUNT_PROJECTION::TEXT) IS DISTINCT FROM expected\n OR internal.initial_cancellation_sealed() OR internal.initial_admission_sealed()\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE owner_id=r.owner_id AND scan_id=r.scan_id AND dispatch=CASE WHEN prevented THEN 'dispatch_prevented' ELSE 'dispatch_outcome_unknown' END)\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n THEN RAISE EXCEPTION USING ERRCODE='ZX552';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\n INSERT INTO pg_temp.account_seen SELECT 'quota',to_jsonb(t) FROM internal.ai_quota_reservations t WHERE user_id=r.owner_id;\n INSERT INTO pg_temp.account_seen SELECT 'hold',to_jsonb(t) FROM internal.complimentary_scan_usage t WHERE user_id=r.owner_id;\n INSERT INTO pg_temp.account_seen SELECT 'attempt',to_jsonb(t) FROM internal.identification_provider_attempts t JOIN internal.ai_quota_reservations q ON q.id=t.reservation_id WHERE q.user_id=r.owner_id;\n INSERT INTO pg_temp.account_seen SELECT 'link',to_jsonb(t) FROM internal.ai_quota_reservation_counters t JOIN internal.ai_quota_reservations q ON q.id=t.reservation_id WHERE q.user_id=r.owner_id;\n INSERT INTO pg_temp.account_seen SELECT 'counters',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters t;\n INSERT INTO pg_temp.account_seen VALUES('user_marker',jsonb_build_object('owner',r.owner_id));RETURN OLD;END $$;\nCREATE FUNCTION pg_temp.account_cascade_row() RETURNS TRIGGER LANGUAGE plpgsql AS $$ DECLARE k TEXT;BEGIN\n IF current_setting('merian.test_account_actor',TRUE) IS DISTINCT FROM 'on' THEN RETURN OLD;END IF;\n k:=CASE TG_TABLE_NAME WHEN 'ai_quota_reservations' THEN 'quota' WHEN 'complimentary_scan_usage' THEN 'hold' WHEN 'identification_provider_attempts' THEN 'attempt' ELSE 'link' END;\n IF (SELECT count(*) FROM pg_temp.account_seen WHERE kind='user_marker')<>1 OR NOT EXISTS(SELECT 1 FROM pg_temp.account_seen WHERE kind=k AND value=to_jsonb(OLD)) THEN RAISE EXCEPTION USING ERRCODE='ZX553';END IF;\n INSERT INTO pg_temp.account_seen VALUES(k||'_deleted',to_jsonb(OLD));RETURN OLD;END $$;\nCREATE TRIGGER a_test_account_before_user BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION pg_temp.account_before_user();\n".replace('ACCOUNT_PROJECTION', account_projection)
    for table in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'public.users']:
        hooks += 'CREATE TRIGGER test_account_no_update BEFORE UPDATE ON ' + table + ' FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.account_no_mutation();'
    for table in ['internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts']:
        hooks += 'CREATE TRIGGER test_account_cascade BEFORE DELETE ON ' + table + ' FOR EACH ROW EXECUTE FUNCTION pg_temp.account_cascade_row();'
    hooks += 'CREATE TRIGGER test_account_no_counter_delete BEFORE DELETE ON internal.ai_quota_counters FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.account_no_mutation();'
    def account(expected, c1_first):
        return "INSERT INTO account_expected VALUES('" + expected + "'," + str(c1_first).lower() + ");DO $$ DECLARE r internal.initial_preparation_admission_receipts;k TEXT;BEGIN SELECT * INTO STRICT r FROM target;PERFORM set_config('merian.test_account_actor','on',TRUE);SET LOCAL ROLE service_role;PERFORM public.apply_user_tombstone(r.owner_id);RESET ROLE;" + "\n IF EXISTS(SELECT 1 FROM public.users WHERE id=r.owner_id)\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=r.owner_id)\n OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id=r.owner_id)\n OR EXISTS(SELECT 1 FROM internal.identification_provider_attempts) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT count(*) FROM account_seen WHERE kind='user_marker')<>1\n OR (SELECT count(*) FROM account_seen WHERE kind='quota_deleted')<>1\n OR (SELECT count(*) FROM account_seen WHERE kind='hold_deleted')<>1\n OR (SELECT value FROM account_seen WHERE kind='counters') IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters t)\n OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX554';END IF;\n FOR k IN SELECT unnest(ARRAY['quota','hold','link','attempt']) LOOP\n  IF (SELECT COALESCE(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) FROM account_seen WHERE kind=k) IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) FROM account_seen WHERE kind=k||'_deleted') THEN RAISE EXCEPTION USING ERRCODE='ZX555';END IF;\n END LOOP;\n IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=r.scan_id AND state=CASE WHEN (SELECT c1_first FROM account_expected) THEN 'cancelled_pre_dispatch' ELSE 'cancelled_unknown' END)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=r.scan_id AND state='retired')\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=r.scan_id AND state='retired')\n OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=r.scan_id AND retired AND NOT marker_confirmed AND claim_token IS NULL AND claim_expires_at IS NULL)<>1\n OR (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=r.scan_id AND retired AND NOT marker_confirmed AND claim_token IS NULL AND claim_expires_at IS NULL)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX556';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\n END $$;"
    def denied(expected):
        return "DO $$ DECLARE r internal.initial_preparation_admission_receipts;failed BOOLEAN:=FALSE;BEGIN SELECT * INTO STRICT r FROM target;BEGIN SET LOCAL ROLE service_role;PERFORM public.cancel_initial_analysis(r.owner_id,r.scan_id);EXCEPTION WHEN SQLSTATE 'P0002' THEN IF SQLERRM<>'initial_analysis_owner_unavailable' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed OR md5((" + projection + ")::TEXT) IS DISTINCT FROM '" + expected + "' THEN RAISE EXCEPTION USING ERRCODE='ZX557';END IF;" + no_authority + 'END $$;'
    def digest(rows):
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}', rows[0]):
            raise RuntimeError('one private accounting comparison image required')
        return rows[0]

    try:
        fixture = AdmissionFixture(qualification, held=True)
        fixture.session.run('install_account_observation_hooks', hooks)
        for c1_first in (True,False):
            phase = 'c1_first' if c1_first else 'account_first'
            identity = fixture.admit_one(owner_id=fixture.owner if c1_first else fixture.foreign)
            start = base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE owner_id='"+identity.owner_id+"' AND scan_id='"+identity.scan_id+"' AND admission_receipt_id='"+identity.receipt_id+"';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX531';END IF;END $$;"
            account_start = start + "CREATE TEMP TABLE account_expected(digest TEXT,c1_first BOOLEAN);CREATE TEMP TABLE account_seen(kind TEXT,value JSONB);"
            first = peer(phase+'_first')
            second = peer(phase+'_second')
            observer = peer(phase+'_observer')
            if len({s.pid for s in sessions}) != 3:
                raise RuntimeError('distinct account-order backends required')
            first.run('save_original_identity',start if c1_first else account_start)
            second.run('save_original_identity',account_start if c1_first else start)
            if c1_first:
                expected = digest(first.run('cancel_uncommitted_accounting',cancel+"SELECT md5(("+account_projection+")::TEXT);"))
                second.start('account_after_cancellation',account(expected,True))
            else:
                expected = digest(first.run('save_original_accounting',"SELECT md5(("+account_projection+")::TEXT);"))
                post = digest(first.run('account_uncommitted',account(expected,False)+"SELECT md5(("+projection+")::TEXT);"))
                second.start('cancel_after_account',denied(post))
            blocking(observer,first,second)
            first.run('first_commit','COMMIT;')
            second.finish()
            second.run('second_commit','COMMIT;')
            close_group([first,second,observer])
            qualification.record['checks'].append({'case':phase,'passed':True,'blocking_observed':True,'both_committed':True,'actual_service_role_wrappers':True,'pre_user_delete_accounting_verified':True,'cascade_rows_verified':True,'global_fences_retained':True})
            qualification.save()
        fixture.close()
        fixture = None
        execute('fresh_final_both_owners_erased_global_fences_retained', "DO $$ DECLARE c RECORD;BEGIN IF EXISTS(SELECT 1 FROM public.users) OR EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters) OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) OR (SELECT count(*) FROM internal.initial_analysis_lifecycle_fences WHERE state='cancelled_pre_dispatch')<>1 OR (SELECT count(*) FROM internal.initial_analysis_lifecycle_fences WHERE state='cancelled_unknown')<>1 OR (SELECT count(*) FROM internal.initial_analysis_operation_fences)<>2 OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE retired AND NOT marker_confirmed AND claim_token IS NULL AND claim_expires_at IS NULL)<>2 OR (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE retired AND NOT marker_confirmed AND claim_token IS NULL AND claim_expires_at IS NULL)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX558';END IF;FOR c IN SELECT scan_id FROM internal.initial_analysis_lifecycle_fences LOOP PERFORM internal.assert_initial_cancellation_transients_absent(c.scan_id);END LOOP;END $$;")
    finally:
        errors = []
        if sessions:
            try:
                close_group(list(sessions))
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        logs = subprocess.run(['docker', 'logs', '--since', started, qualification.command[3]], text=True, capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall('ERROR:.*deadlock detected', raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [{'waiter': int(a), 'mode': mode, 'lock_object': lock, 'blocker': int(b)} for (a, mode, lock, b) in re.findall('Process (\\d+) waits for ([A-Za-z]+) on (transaction \\d+|relation \\d+ of database \\d+|tuple \\(\\d+,\\d+\\) of relation \\d+ of database \\d+|virtual transaction \\d+/\\d+); blocked by process (\\d+)', raw)]
            qualification.record['deadlock_root_cause_established'] = False
        qualification.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')


def registry_order_cases(qualification):
    base, projection = BASE, PROJECTION
    execute = qualification.execute
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = ('Actual public source/media claim visibility before/during uncommitted C1, then per-family lease/release/reclaim/stale-token/ack and exact replay. Nonblocking empty visibility, not SKIP LOCKED/worker/external storage qualification.')
    relations = ['public.users', 'public.scans', 'internal.initial_preparation_admission_receipts', 'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents', 'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences', 'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations', 'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters', 'internal.complimentary_scan_usage', 'internal.identification_provider_attempts', 'internal.identification_invocations', 'internal.initial_preparation_source_fences', 'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_operation_fences', 'internal.initial_preparation_source_registry', 'internal.initial_analysis_media_registry', 'internal.initial_analysis_results', 'internal.initial_analysis_completions']
    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session
    def close_group(group):
        errors = []
        for session in group:
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
            finally:
                sessions.remove(session)
        if errors:
            qualification.record['close_errors'] = errors
            qualification.save()
            raise RuntimeError('session cleanup failed')
    no_authority = "IF internal.initial_cancellation_sealed() OR internal.initial_admission_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX532';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);"
    cancel = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_owner JSONB;other_users JSONB;old_terminals JSONB;life JSONB;sf JSONB;df JSONB;sr JSONB;dr JSONB;BEGIN\n SELECT * INTO STRICT r FROM target;\n SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=r.owner_id;\n SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;\n SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) INTO old_terminals FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'cancelled_pre_dispatch\') INTO STRICT life FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT sf FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT df FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO sr FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO dr FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id;\n SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;\n IF answer IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB\n OR (SELECT to_jsonb(u) FROM public.users u WHERE id=r.owner_id) IS DISTINCT FROM before_owner||jsonb_build_object(\'complimentary_entitlement_epoch\',(before_owner->>\'complimentary_entitlement_epoch\')::BIGINT+1,\'entitlement_version\',(before_owner->>\'entitlement_version\')::BIGINT+1)\n OR (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>r.owner_id) IS DISTINCT FROM other_users\n OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id) IS DISTINCT FROM old_terminals\n OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND user_id=r.owner_id AND state=\'refunded\' AND refund_count=1)\n OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state=\'released\' AND settlement_reason=\'cancelled_before_dispatch\' AND settled_at IS NOT NULL AND settled_at=updated_at)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch=\'dispatch_prevented\')\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM life\n OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM sf\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM df\n OR sr IS NULL OR dr IS NULL\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM sr\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM dr\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX537\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\nEND $$;\n'
    def empty_claims():
        return 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;b JSONB;a JSONB;d JSONB;BEGIN SELECT * INTO STRICT r FROM target;b:=' + projection + ';SET LOCAL ROLE service_role;a:=public.claim_initial_preparation_source_erasure();d:=public.claim_initial_analysis_media_erasure();RESET ROLE;IF a IS DISTINCT FROM \'{"version":1,"outcome":"empty"}\'::JSONB OR d IS DISTINCT FROM a OR b IS DISTINCT FROM ' + projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX561';END IF;" + no_authority + 'END $$;'
    def cleanup(table, claim, finish, release):
        other = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations if x != table)) + ')'
        sql = 'DO $$ DECLARE old_row JSONB;live JSONB;b JSONB;response JSONB;token UUID;prior_token UUID;wrong_token UUID;object UUID;before_clock TIMESTAMPTZ;after_clock TIMESTAMPTZ;BEGIN\n SELECT to_jsonb(t),t.object_id INTO STRICT old_row,object FROM TABLE_NAME t;\n IF old_row->>\'retired\' IS DISTINCT FROM \'true\' OR old_row->>\'marker_confirmed\' IS DISTINCT FROM \'false\' OR old_row->\'claim_token\' IS DISTINCT FROM \'null\'::JSONB OR old_row->\'claim_expires_at\' IS DISTINCT FROM \'null\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX562\';END IF;\n b:=OTHER_PROJECTION;before_clock:=clock_timestamp();SET LOCAL ROLE service_role;response:=CLAIM_FN();RESET ROLE;after_clock:=clock_timestamp();\n SELECT to_jsonb(t) INTO STRICT live FROM TABLE_NAME t WHERE object_id=object;\n token:=(live->>\'claim_token\')::UUID;\n IF token IS NULL OR live-\'claim_token\'-\'claim_expires_at\' IS DISTINCT FROM old_row-\'claim_token\'-\'claim_expires_at\' OR (live->>\'claim_expires_at\')::TIMESTAMPTZ<before_clock+INTERVAL \'1 minute\' OR (live->>\'claim_expires_at\')::TIMESTAMPTZ>after_clock+INTERVAL \'1 minute\'\n OR response IS DISTINCT FROM jsonb_build_object(\'version\',1,\'outcome\',\'claimed\',\'object\',jsonb_build_object(\'scan_id\',live->\'scan_id\',\'object_id\',live->\'object_id\',\'backend_generation\',live->\'backend_generation\',\'claim_token\',live->\'claim_token\',\'claim_expires_at\',floor(extract(epoch FROM (live->>\'claim_expires_at\')::TIMESTAMPTZ)*1000)::BIGINT)) THEN RAISE EXCEPTION USING ERRCODE=\'ZX563\';END IF;\n wrong_token:=((CASE WHEN left(token::TEXT,1)=\'0\' THEN \'1\' ELSE \'0\' END)||substring(token::TEXT FROM 2))::UUID;\n SET LOCAL ROLE service_role;response:=FINISH_FN(object,wrong_token,TRUE);RESET ROLE;\n IF response IS DISTINCT FROM \'{"version":1,"outcome":"stale"}\'::JSONB OR (SELECT to_jsonb(t) FROM TABLE_NAME t WHERE object_id=object) IS DISTINCT FROM live THEN RAISE EXCEPTION USING ERRCODE=\'ZX564\';END IF;\n SET LOCAL ROLE service_role;response:=FINISH_FN(object,token,FALSE);RESET ROLE;\n IF response IS DISTINCT FROM jsonb_build_object(\'version\',1,\'outcome\',\'RELEASE_RESULT\') OR (SELECT to_jsonb(t) FROM TABLE_NAME t WHERE object_id=object) IS DISTINCT FROM old_row THEN RAISE EXCEPTION USING ERRCODE=\'ZX565\';END IF;\n prior_token:=token;SET LOCAL ROLE service_role;response:=CLAIM_FN();RESET ROLE;\n SELECT to_jsonb(t) INTO STRICT live FROM TABLE_NAME t WHERE object_id=object;token:=(live->>\'claim_token\')::UUID;\n IF token IS NULL OR token=prior_token OR live-\'claim_token\'-\'claim_expires_at\' IS DISTINCT FROM old_row-\'claim_token\'-\'claim_expires_at\' OR response IS DISTINCT FROM jsonb_build_object(\'version\',1,\'outcome\',\'claimed\',\'object\',jsonb_build_object(\'scan_id\',live->\'scan_id\',\'object_id\',live->\'object_id\',\'backend_generation\',live->\'backend_generation\',\'claim_token\',live->\'claim_token\',\'claim_expires_at\',floor(extract(epoch FROM (live->>\'claim_expires_at\')::TIMESTAMPTZ)*1000)::BIGINT)) THEN RAISE EXCEPTION USING ERRCODE=\'ZX566\';END IF;\n SET LOCAL ROLE service_role;response:=FINISH_FN(object,prior_token,TRUE);RESET ROLE;\n IF response IS DISTINCT FROM \'{"version":1,"outcome":"stale"}\'::JSONB OR (SELECT to_jsonb(t) FROM TABLE_NAME t WHERE object_id=object) IS DISTINCT FROM live THEN RAISE EXCEPTION USING ERRCODE=\'ZX567\';END IF;\n SET LOCAL ROLE service_role;response:=FINISH_FN(object,token,TRUE);RESET ROLE;\n IF response IS DISTINCT FROM \'{"version":1,"outcome":"acknowledged"}\'::JSONB OR (SELECT to_jsonb(t) FROM TABLE_NAME t WHERE object_id=object) IS DISTINCT FROM old_row||jsonb_build_object(\'marker_confirmed\',TRUE) THEN RAISE EXCEPTION USING ERRCODE=\'ZX568\';END IF;\n SET LOCAL ROLE service_role;response:=FINISH_FN(object,token,TRUE);RESET ROLE;\n IF response IS DISTINCT FROM \'{"version":1,"outcome":"stale"}\'::JSONB OR (SELECT to_jsonb(t) FROM TABLE_NAME t WHERE object_id=object) IS DISTINCT FROM old_row||jsonb_build_object(\'marker_confirmed\',TRUE) THEN RAISE EXCEPTION USING ERRCODE=\'ZX569\';END IF;\n SET LOCAL ROLE service_role;response:=CLAIM_FN();RESET ROLE;\n IF response IS DISTINCT FROM \'{"version":1,"outcome":"empty"}\'::JSONB OR b IS DISTINCT FROM OTHER_PROJECTION OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX570\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent((old_row->>\'scan_id\')::UUID);\n END $$;'
        return sql.replace('TABLE_NAME', table).replace('OTHER_PROJECTION', other).replace('CLAIM_FN', claim).replace('FINISH_FN', finish).replace('RELEASE_RESULT', release)
    try:
        fixture = AdmissionFixture(qualification,held=True)
        identity = fixture.admit_one()
        start = base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE owner_id='"+identity.owner_id+"' AND scan_id='"+identity.scan_id+"' AND admission_receipt_id='"+identity.receipt_id+"';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX531';END IF;END $$;"
        phase = 'claims_before_and_during_c1'
        claims = peer('cleanup_actor')
        cancellation = peer('c1_actor')
        if claims.pid == cancellation.pid:
            raise RuntimeError('distinct registry/C1 backends required')
        claims.run('save_original_identity',start)
        cancellation.run('save_original_identity',start)
        claims.run('empty_before_cancellation',empty_claims())
        cancellation.run('cancel_uncommitted',cancel)
        claims.run('empty_during_uncommitted_cancellation',empty_claims())
        claims.run('claims_commit','COMMIT;')
        cancellation.run('cancellation_commit','COMMIT;')
        close_group([claims,cancellation])
        fixture.close()
        fixture = None
        qualification.record['checks'].append({'case':phase,'passed':True,'both_public_registry_claims_empty_before_and_during_uncommitted_c1':True,'both_committed':True,'claim_returned_before_c1_commit':True,'scope':'Visibility/nonblocking empty result; not proof of lock skipping.'})
        qualification.save()
        for (kind, table, claim, finish, release) in [('source', 'internal.initial_preparation_source_registry', 'public.claim_initial_preparation_source_erasure', 'public.finish_initial_preparation_source_erasure', 'released'), ('media', 'internal.initial_analysis_media_registry', 'public.claim_initial_analysis_media_erasure', 'public.finish_initial_analysis_media_erasure', 'acknowledged')]:
            phase = kind + '_post_c1_lease_release_reclaim_acknowledge'
            execute(phase, base + cleanup(table, claim, finish, release) + 'COMMIT;')
        phase = 'fresh_c1_replay_after_acknowledgment'
        execute(phase, base + 'DO $$ DECLARE r internal.initial_analysis_cancellations;b JSONB;a JSONB;BEGIN SELECT * INTO STRICT r FROM internal.initial_analysis_cancellations;b:=' + projection + ';SET LOCAL ROLE service_role;a:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;IF a IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB OR b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE NOT retired OR NOT marker_confirmed OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE NOT retired OR NOT marker_confirmed OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL) OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX571';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);END $$;COMMIT;")
    finally:
        errors = []
        if sessions:
            try:
                close_group(list(sessions))
            except Exception as error:
                errors.append(type(error).__name__)
        if fixture is not None:
            try:
                fixture.close()
            except Exception as error:
                errors.append(type(error).__name__)
        logs = subprocess.run(['docker', 'logs', '--since', started, qualification.command[3]], text=True, capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall('ERROR:.*deadlock detected', raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [{'waiter': int(a), 'mode': mode, 'lock_object': lock, 'blocker': int(b)} for (a, mode, lock, b) in re.findall('Process (\\d+) waits for ([A-Za-z]+) on (transaction \\d+|relation \\d+ of database \\d+|tuple \\(\\d+,\\d+\\) of relation \\d+ of database \\d+|virtual transaction \\d+/\\d+); blocked by process (\\d+)', raw)]
            qualification.record['deadlock_root_cause_established'] = False
        qualification.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')

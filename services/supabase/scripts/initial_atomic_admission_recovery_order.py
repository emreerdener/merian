"""Four public recovery wrappers versus cancellation, each observed in both orders."""
import datetime
import re
import subprocess
import time
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, PROJECTION, Session


def recovery_order_cases(qualification):
    base, projection = BASE, PROJECTION
    execute = qualification.execute
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = (
        'Eight actual service-role public recovery/cancellation schedules; '
        'four wrappers in both orders with successive held synthetic admissions. '
        'Enumerated 21-relation projection, no provider/media IO or hosted S0.')

    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({
            'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session

    def blocking(observer, first, second):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if observer.run('observe_blocker', f'SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));') == ['t']:
                qualification.record.setdefault('observed_blockers', []).append({
                    'blocker': first.name, 'waiter': second.name})
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
    callers = {'status': 'public.get_initial_preparation_status(r.owner_id,r.scan_id)', 'finalize': "public.finalize_initial_preparation(r.owner_id,r.scan_id,repeat('b',64))", 'create': 'public.create_initial_preparation_intent(r.owner_id,r.scan_id,r.candidate)', 'execution': "public.get_initial_preparation_execution_status(r.owner_id,r.scan_id,r.media_binding::JSONB->>'assignment_digest')"}

    def recover(caller, cancelled=False, expected=None):
        call = callers[caller]
        body = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_state JSONB;failed BOOLEAN:=FALSE;before_ms NUMERIC;after_ms NUMERIC;cutoff NUMERIC;BEGIN SELECT * INTO STRICT r FROM target;'
        if cancelled:
            body += 'BEGIN SET LOCAL ROLE service_role;answer:=' + call + ";EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_cancelled' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed OR md5((" + projection + ")::TEXT) IS DISTINCT FROM '" + expected + "' THEN RAISE EXCEPTION USING ERRCODE='ZX533';END IF;"
        else:
            body += 'before_state:=' + projection + ';before_ms:=floor(extract(epoch FROM clock_timestamp())*1000);SET LOCAL ROLE service_role;answer:=' + call + ';RESET ROLE;after_ms:=floor(extract(epoch FROM clock_timestamp())*1000);'
            if caller == 'execution':
                body += 'IF answer IS DISTINCT FROM \'{"version":2,"outcome":"held","reason":"incoherent","authority":"none"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX534\';END IF;'
            else:
                body += "cutoff:=(r.media_binding::JSONB#>>'{phase_window,cutoffs,copy}')::NUMERIC;IF answer-'phase' IS DISTINCT FROM jsonb_build_object('version',2,'outcome','admitted','authority','none','scan_id',r.scan_id,'admission_receipt_digest',r.receipt_digest,'binding',r.media_binding::JSONB) OR answer->>'phase' NOT IN ('copy','expired') OR (after_ms<cutoff AND answer->>'phase'<>'copy') OR (before_ms>=cutoff AND answer->>'phase'<>'expired') THEN RAISE EXCEPTION USING ERRCODE='ZX535';END IF;"
            body += 'IF before_state IS DISTINCT FROM ' + projection + " THEN RAISE EXCEPTION USING ERRCODE='ZX536';END IF;"
        return body + no_authority + 'END $$;'
    cancel = 'DO $$ DECLARE r internal.initial_preparation_admission_receipts;answer JSONB;before_owner JSONB;other_users JSONB;old_terminals JSONB;life JSONB;sf JSONB;df JSONB;sr JSONB;dr JSONB;BEGIN\n SELECT * INTO STRICT r FROM target;\n SELECT to_jsonb(u) INTO STRICT before_owner FROM public.users u WHERE id=r.owner_id;\n SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;\n SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) INTO old_terminals FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'cancelled_pre_dispatch\') INTO STRICT life FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT sf FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id;\n SELECT to_jsonb(t)||jsonb_build_object(\'state\',\'retired\') INTO STRICT df FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO sr FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id;\n SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(\'retired\',TRUE) ORDER BY object_id) INTO dr FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id;\n SET LOCAL ROLE service_role;answer:=public.cancel_initial_analysis(r.owner_id,r.scan_id);RESET ROLE;\n IF answer IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB\n OR (SELECT to_jsonb(u) FROM public.users u WHERE id=r.owner_id) IS DISTINCT FROM before_owner||jsonb_build_object(\'complimentary_entitlement_epoch\',(before_owner->>\'complimentary_entitlement_epoch\')::BIGINT+1,\'entitlement_version\',(before_owner->>\'entitlement_version\')::BIGINT+1)\n OR (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>r.owner_id) IS DISTINCT FROM other_users\n OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY scan_id) FROM internal.initial_analysis_cancellations c WHERE scan_id<>r.scan_id) IS DISTINCT FROM old_terminals\n OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND user_id=r.owner_id AND state=\'refunded\' AND refund_count=1)\n OR NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE client_scan_id=r.scan_id AND user_id=r.owner_id AND state=\'released\' AND settlement_reason=\'cancelled_before_dispatch\' AND settled_at IS NOT NULL AND settled_at=updated_at)\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations WHERE scan_id=r.scan_id AND owner_id=r.owner_id AND dispatch=\'dispatch_prevented\')\n OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.initial_analysis_admissions WHERE scan_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)\n OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions)\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_lifecycle_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM life\n OR (SELECT to_jsonb(t) FROM internal.initial_preparation_source_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM sf\n OR (SELECT to_jsonb(t) FROM internal.initial_analysis_media_allocation_fences t WHERE scan_id=r.scan_id) IS DISTINCT FROM df\n OR sr IS NULL OR dr IS NULL\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_preparation_source_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM sr\n OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY object_id) FROM internal.initial_analysis_media_registry t WHERE scan_id=r.scan_id) IS DISTINCT FROM dr\n OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=r.scan_id)\n OR NOT internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE=\'ZX537\';END IF;\n PERFORM internal.assert_initial_cancellation_transients_absent(r.scan_id);\nEND $$;\n'
    try:
        fixture = AdmissionFixture(qualification, held=True)
        for caller in callers:
            for cancellation_first in (False, True):
                phase = caller + ('_cancellation_first' if cancellation_first else '_recovery_first')
                identity = fixture.admit_one()
                # Explicit fixture identity; earlier terminal rows remain as peer evidence.
                start = base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE owner_id='" + identity.owner_id + "' AND scan_id='" + identity.scan_id + "' AND admission_receipt_id='" + identity.receipt_id + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX531';END IF;END $$;"
                first = peer(phase + '_first')
                second = peer(phase + '_second')
                observer = peer(phase + '_observer')
                if len({s.pid for s in sessions}) != 3:
                    raise RuntimeError('distinct backends required')
                first.run('save_original_identity', start)
                second.run('save_original_identity', start)
                if cancellation_first:
                    result = first.run('cancel_then_capture_expected', cancel + "SELECT md5((" + projection + ")::TEXT);")
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
                qualification.record['checks'].append({
                    'case': phase, 'passed': True, 'blocking_observed': True,
                    'both_committed': True, 'actual_service_role_wrappers': True,
                    'original_accounting_and_owner_delta_verified': True,
                    'recovery_no_business_change': True})
                qualification.save()
        fixture.close()
        fixture = None
        execute('fresh_final_eight_original_refunds_no_private_roots_or_authority', "DO $$ DECLARE c RECORD;BEGIN IF (SELECT count(*) FROM internal.initial_analysis_cancellations WHERE dispatch='dispatch_prevented')<>8 OR (SELECT count(*) FROM internal.ai_quota_reservations)<>8 OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>'refunded' OR refund_count<>1) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters) OR (SELECT count(*) FROM internal.complimentary_scan_usage)<>8 OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE state IS DISTINCT FROM 'released' OR settlement_reason IS DISTINCT FROM 'cancelled_before_dispatch' OR settled_at IS NULL OR settled_at IS DISTINCT FROM updated_at) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_submissions) OR EXISTS(SELECT 1 FROM internal.initial_analysis_preparation_intents) OR EXISTS(SELECT 1 FROM internal.identification_invocations) OR EXISTS(SELECT 1 FROM internal.initial_analysis_results) OR EXISTS(SELECT 1 FROM internal.initial_analysis_completions) OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE='ZX538';END IF;FOR c IN SELECT scan_id FROM internal.initial_analysis_cancellations LOOP IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=c.scan_id AND state='cancelled_pre_dispatch') OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences WHERE scan_id=c.scan_id AND state='retired') OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=c.scan_id AND state='retired') OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=c.scan_id) OR (SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=c.scan_id)<>1 OR (SELECT count(*) FROM internal.initial_analysis_media_registry WHERE scan_id=c.scan_id)<>1 OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=c.scan_id AND (retired IS DISTINCT FROM TRUE OR marker_confirmed IS DISTINCT FROM FALSE OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL)) OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=c.scan_id AND (retired IS DISTINCT FROM TRUE OR marker_confirmed IS DISTINCT FROM FALSE OR claim_token IS NOT NULL OR claim_expires_at IS NOT NULL)) THEN RAISE EXCEPTION USING ERRCODE='ZX539';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(c.scan_id);END LOOP;END $$;")
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
        logs = subprocess.run(
            ['docker', 'logs', '--since', started, qualification.command[3]],
            text=True, capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall(r'ERROR:.*deadlock detected', raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [
                {'waiter': int(a), 'mode': mode, 'lock_object': lock, 'blocker': int(b)}
                for a, mode, lock, b in re.findall(
                    r'Process (\d+) waits for ([A-Za-z]+) on (transaction \d+|relation \d+ of database \d+|tuple \(\d+,\d+\) of relation \d+ of database \d+|virtual transaction \d+/\d+); blocked by process (\d+)', raw)]
            qualification.record['deadlock_root_cause_established'] = False
        qualification.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')

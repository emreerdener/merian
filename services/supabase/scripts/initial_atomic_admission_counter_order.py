"""Two public cancellation versus trusted synthetic admission counter orders."""
import datetime
import json
import re
import subprocess
import time
import uuid
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, PROJECTION, Session


def counter_order_cases(qualification):
    base, projection = BASE, PROJECTION
    execute = qualification.execute
    qualification.record['scope'] = ('Two actual public service-role C1 versus privileged synthetic admission orders, distinct owners/scans sharing IP. Winner returns uncommitted; observed counter dependency and independent postimages; no third scheduler/provider/storage/public admission/installed qualification.')
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    fixture = None
    sessions = []
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
    def selected_start(scan):
        return base + "CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX591';END IF;END $$;"
    peer_tables = {'public.scans': 'id', 'internal.initial_preparation_admission_receipts': 'scan_id', 'internal.initial_analysis_submissions': 'scan_id', 'internal.initial_analysis_preparation_intents': 'scan_id', 'internal.initial_analysis_admissions': 'scan_id', 'internal.initial_analysis_lifecycle_fences': 'scan_id', 'internal.initial_analysis_cancellations': 'scan_id', 'internal.complimentary_scan_usage': 'client_scan_id', 'internal.identification_invocations': 'scan_id', 'internal.initial_preparation_source_fences': 'scan_id', 'internal.initial_analysis_media_allocation_fences': 'scan_id', 'internal.initial_analysis_operation_fences': 'scan_id', 'internal.initial_preparation_source_registry': 'scan_id', 'internal.initial_analysis_media_registry': 'scan_id', 'internal.initial_analysis_results': 'scan_id', 'internal.initial_analysis_completions': 'scan_id'}
    peer_parts = ["(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + table + ' t WHERE ' + field + '<>(SELECT scan_id FROM target))' for (table, field) in peer_tables.items()]
    peer_parts += ["(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + table + ' t WHERE ' + field + '<>(SELECT q.id FROM internal.ai_quota_reservations q JOIN target r ON q.original_analysis_id=r.scan_id))' for (table, field) in [('internal.ai_quota_reservations', 'id'), ('internal.ai_quota_reservation_counters', 'reservation_id'), ('internal.identification_provider_attempts', 'reservation_id')]]
    peer_projection = 'jsonb_build_array(' + ','.join(peer_parts) + ')'
    counter_projection = "(SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::TEXT),'[]'::JSONB) FROM internal.ai_quota_counters c)"
    prepare = "CREATE TEMP TABLE original_links AS SELECT l.* FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id JOIN target r ON r.scan_id=q.original_analysis_id;\nCREATE TEMP TABLE before_counters AS SELECT c.*,EXISTS(SELECT 1 FROM original_links l WHERE (l.scope_type,l.scope_key,l.bucket,l.window_start)=(c.scope_type,c.scope_key,c.bucket,c.window_start)) AS charged FROM internal.ai_quota_counters c;\nCREATE TEMP TABLE expected_counters AS SELECT CASE WHEN charged THEN (to_jsonb(c)-'charged')||jsonb_build_object('request_count',request_count-1,'updated_at',transaction_timestamp()) ELSE to_jsonb(c)-'charged' END AS value FROM before_counters c WHERE NOT charged OR request_count>1;\nCREATE TEMP TABLE peer_before AS SELECT PEER value;\nDO $$ BEGIN IF (SELECT count(*) FROM original_links)<>3 OR (SELECT count(*) FROM before_counters WHERE charged)<>3 OR EXISTS(SELECT 1 FROM before_counters WHERE charged AND request_count<1) THEN RAISE EXCEPTION USING ERRCODE='ZX592';END IF;END $$;\n".replace('PEER', peer_projection)
    def check_after(expected_shared, expected_unlinked):
        return "DO $$ DECLARE actual JSONB;expected JSONB;BEGIN SELECT COALESCE(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) INTO expected FROM expected_counters;actual:=" + counter_projection + ';IF actual IS DISTINCT FROM expected OR (SELECT value FROM peer_before) IS DISTINCT FROM ' + peer_projection + ' OR (SELECT count(*) FROM before_counters WHERE charged AND request_count>1)<>' + str(expected_shared) + ' OR (SELECT count(*) FROM before_counters WHERE NOT charged)<>' + str(expected_unlinked) + " THEN RAISE EXCEPTION USING ERRCODE='ZX593';END IF;END $$;"
    def literal(v):
        return "'" + json.dumps(v).replace("'", "''") + "'::JSONB"
    def admission_checks(a_counters, bowner, c1_first):
        image = literal(a_counters)
        expected = "SELECT (to_jsonb(c)||jsonb_build_object('scope_key',CASE WHEN scope_type='ip_rate' THEN scope_key ELSE '" + bowner + "' END,'request_count',1,'updated_at',transaction_timestamp())) value FROM jsonb_populate_recordset(NULL::internal.ai_quota_counters," + image + ') c'
        if not c1_first:
            expected = "SELECT CASE WHEN scope_type='ip_rate' THEN to_jsonb(c)||jsonb_build_object('request_count',2,'updated_at',transaction_timestamp()) ELSE to_jsonb(c) END value FROM jsonb_populate_recordset(NULL::internal.ai_quota_counters," + image + ') c UNION ALL ' + expected + " WHERE scope_type<>'ip_rate'"
        return "DO $$ DECLARE expected JSONB;r internal.initial_preparation_admission_receipts;BEGIN SELECT COALESCE(jsonb_agg(value ORDER BY value::TEXT),'[]'::JSONB) INTO expected FROM (" + expected + ') x;IF expected IS DISTINCT FROM ' + counter_projection + " OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging) THEN RAISE EXCEPTION USING ERRCODE='ZX601';END IF;SELECT * INTO STRICT r FROM internal.initial_preparation_admission_receipts WHERE owner_id='" + bowner + "';IF (SELECT count(*) FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id WHERE q.original_analysis_id=r.scan_id)<>3 OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters l JOIN internal.ai_quota_reservations q ON q.id=l.reservation_id JOIN jsonb_populate_recordset(NULL::internal.ai_quota_counters," + image + ") a ON (a.scope_type,a.scope_key,a.bucket,a.window_start)=(l.scope_type,l.scope_key,l.bucket,l.window_start) WHERE q.original_analysis_id=r.scan_id AND l.scope_type='ip_rate') OR NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE original_analysis_id=r.scan_id AND state='reserved' AND refund_count=0) OR EXISTS(SELECT 1 FROM internal.identification_invocations) THEN RAISE EXCEPTION USING ERRCODE='ZX602';END IF;END $$;"
    def peer(name):
        session = Session(qualification, name)
        sessions.append(session)
        qualification.record.setdefault('backend_correlation', []).append({'statement_label': name, 'backend_pid': session.pid})
        qualification.save()
        return session

    def payload(rows):
        if len(rows) != 1:
            raise RuntimeError('one private synthetic postimage required')
        return json.loads(rows[0])

    def observe_counter_wait(observer, winner, loser):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if observer.run('observe_blocker', f'SELECT {winner.pid}=ANY(pg_blocking_pids({loser.pid}));') == ['t']:
                break
            time.sleep(.04)
        else:
            raise RuntimeError('expected counter dependency missing')
        sql = f"SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid={loser.pid} AND wait_event_type='Lock' AND wait_event='transactionid') AND EXISTS(SELECT 1 FROM pg_locks WHERE pid={loser.pid} AND relation='internal.ai_quota_counters'::regclass AND mode IN ('RowShareLock','RowExclusiveLock') AND granted);"
        if observer.run('observe_counter_wait', sql) != ['t']:
            raise RuntimeError('counter wait attribution missing')
        qualification.record.setdefault('observed_blockers', []).append({'blocker': winner.name, 'waiter': loser.name, 'transactionid_wait': True, 'counter_relation_granted': True})
        qualification.save()

    try:
        fixture = AdmissionFixture(qualification, held=True)
        owners = [fixture.owner, fixture.foreign, str(uuid.uuid4()), str(uuid.uuid4())]
        for owner in owners[2:]:
            fixture.ensure_owner(owner)
        b = fixture.session
        qualification.record.setdefault('backend_correlation', []).append({'statement_label': b.name, 'backend_pid': b.pid})
        for index, c1_first in enumerate([True, False]):
            phase = 'c1_first' if c1_first else 'admission_first'
            aowner, bowner = owners[index*2:index*2+2]
            ascan = fixture.admit_one(owner_id=aowner).scan_id
            bscan = str(uuid.uuid4())
            a_counters = payload(b.run('read_original_counter_baseline', 'SELECT '+counter_projection+'::TEXT;'))
            if len(a_counters) != 3 or not all(x['request_count'] == 1 for x in a_counters):
                raise RuntimeError('three original singleton counters required')
            fixture.bind_owner(bowner)
            p = peer(phase+'_c1_actor')
            observer = peer(phase+'_observer')
            if len({b.pid, p.pid, observer.pid}) != 3:
                raise RuntimeError('distinct actor backends required')
            p.run('save_original_identity', selected_start(ascan))
            # B intentionally selects A so its peer image includes B and older terminals.
            b_start = selected_start(ascan)
            b_call = fixture.prepare_admission(bowner, bscan, commit=False) + admission_checks(a_counters,bowner,c1_first) + "SELECT jsonb_build_object('counters',"+counter_projection+",'peers',"+peer_projection+",'other_users',(SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM public.users u WHERE id<>'"+aowner+"'))::TEXT;"
            if c1_first:
                p.run('cancel_uncommitted', prepare+cancel+check_after(0,0))
                b.start('admit_uncommitted_after_cancellation', b_start+b_call)
                observe_counter_wait(observer,p,b)
                p.run('cancel_commit','COMMIT;')
                winner = payload(b.finish())
                fixture.commit_prepared()
            else:
                winner = payload(b.run('admit_uncommitted_before_cancellation', b_start+b_call))
                prep=prepare.replace('FROM internal.ai_quota_counters c;', 'FROM jsonb_populate_recordset(NULL::internal.ai_quota_counters,'+literal(winner['counters'])+') c;').replace('SELECT '+peer_projection+' value;', 'SELECT '+literal(winner['peers'])+' value;')
                actual_cancel=cancel.replace('SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO other_users FROM public.users u WHERE id<>r.owner_id;', 'other_users:='+literal(winner['other_users'])+';')
                p.start('cancel_after_uncommitted_admission',prep+actual_cancel+check_after(1,2))
                observe_counter_wait(observer,b,p)
                fixture.commit_prepared()
                p.finish()
                p.run('cancel_commit','COMMIT;')
            p.run('peer_stable_after_both_commits',base+"DO $$ BEGIN IF "+peer_projection+" IS DISTINCT FROM "+literal(winner['peers'])+" THEN RAISE EXCEPTION USING ERRCODE='ZX603';END IF;END $$;COMMIT;")
            for session in (p,observer):
                session.close()
                sessions.remove(session)
            qualification.record['checks'].append({'case':phase,'passed':True,'actual_blocking_observed':True,'wait_kind':'transactionid with counter relation access; disjoint owner/scan and exact same IP key support source-bound attribution','both_committed':True,'new_admission_complete_and_preserved':True,'counter_expected_from':'raw source baseline' if c1_first else 'winner uncommitted raw postimage','third_scheduler':False})
            qualification.save()
            execute(phase+'_fresh_peer_recovery',selected_start(bscan)+recover('status')+'COMMIT;')
            execute(phase+'_cleanup_original_peer',selected_start(bscan)+prepare+cancel+check_after(0,0)+'COMMIT;')
            b.run('clear_selected_target','DROP TABLE target;')
        fixture.close()
        fixture = None
        phase = 'fresh_four_original_replays'
        execute(phase, base + 'DO $$ DECLARE c internal.initial_analysis_cancellations;b JSONB;a JSONB;BEGIN b:=' + projection + ';IF (SELECT count(*) FROM internal.initial_analysis_cancellations)<>4 OR EXISTS(SELECT 1 FROM internal.ai_quota_counters) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters) OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE state<>\'refunded\' OR refund_count<>1) OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts) OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE=\'ZX604\';END IF;FOR c IN SELECT * FROM internal.initial_analysis_cancellations LOOP SET LOCAL ROLE service_role;a:=public.cancel_initial_analysis(c.owner_id,c.scan_id);RESET ROLE;IF a IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX605\';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(c.scan_id);END LOOP;IF b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.identification_invocations) THEN RAISE EXCEPTION USING ERRCODE='ZX606';END IF;END $$;COMMIT;")

    finally:
        errors = []
        # Closing only owned sessions rolls back outstanding work. Lock waits are bounded.
        for session in ([fixture.session] if fixture is not None else []) + sessions:
            try:
                session.close()
            except Exception as error:
                errors.append(type(error).__name__)
        logs = subprocess.run(['docker','logs','--since',started,qualification.command[3]],text=True,capture_output=True)
        raw = logs.stdout + logs.stderr
        count = len(re.findall(r'ERROR:.*deadlock detected',raw))
        qualification.record['server_log_read_exit'] = logs.returncode
        qualification.record['deadlock_reports'] = count
        if count:
            qualification.record['deadlock_edges'] = [{'waiter':int(a),'mode':mode,'lock_object':lock,'blocker':int(b)} for a,mode,lock,b in re.findall(r'Process (\d+) waits for ([A-Za-z]+) on (transaction \d+|relation \d+ of database \d+|tuple \(\d+,\d+\) of relation \d+ of database \d+|virtual transaction \d+/\d+); blocked by process (\d+)',raw)]
            qualification.record['deadlock_root_cause_established'] = False
        if errors:
            qualification.record['close_errors'] = errors
        qualification.save()
        if errors or logs.returncode or count:
            raise RuntimeError('session cleanup or sanitized server diagnostics failed')

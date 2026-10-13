"""Synthetic Ghost preserved-reference denial against public cancellation."""
import datetime
import re
import subprocess
import time
import uuid
from initial_atomic_admission_fixture import AdmissionFixture
from initial_atomic_admission_sessions import BASE, RELATIONS, Session

def jwt(who):
    return "SELECT set_config('request.jwt.claims',jsonb_build_object('sub','" + who + "','role','authenticated')::TEXT,TRUE);SELECT set_config('request.jwt.claim.role','authenticated',TRUE);"


class GhostFixture:
    """Local synthetic identity/handoff preparation, separate from media composition."""
    def __init__(self, qualification):
        self.admissions = AdmissionFixture(qualification, held=True)
        self.session = self.admissions.session
        self.owner = self.admissions.owner
        self.destination = self.admissions.foreign
        self.second = str(uuid.uuid4())
        self.subject = 'synthetic-ghost-target-' + uuid.uuid4().hex
        try:
            self.admissions.ensure_owner(self.second)
            setup = BASE + "UPDATE auth.users SET is_anonymous=TRUE,raw_app_meta_data=jsonb_build_object('provider','anonymous','providers','[]'::JSONB) WHERE id IN ('"+self.owner+"','"+self.second+"');UPDATE auth.users SET is_anonymous=FALSE,raw_app_meta_data=jsonb_build_object('provider','google','providers',jsonb_build_array('google')) WHERE id='"+self.destination+"';INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at) VALUES('"+self.subject+"','"+self.destination+"',jsonb_build_object('sub','"+self.subject+"'),'google',now(),now(),now());COMMIT;"
            self.session.run('install_synthetic_ghost_identities',setup)
            self.session.run('no_purchase_principals',"DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.purchase_principals) OR EXISTS(SELECT 1 FROM internal.purchase_principal_bindings) THEN RAISE EXCEPTION USING ERRCODE='ZX585';END IF;END $$;")
        except Exception:
            self.close()
            raise

    def admit_and_issue(self, owner):
        if owner not in (self.owner,self.second):
            raise ValueError('installed synthetic Ghost owner required')
        identity = self.admissions.admit_one(owner_id=owner)
        secret = uuid.uuid4().hex + uuid.uuid4().hex
        issue = "BEGIN;"+jwt(owner)+"SET LOCAL ROLE authenticated;DO $$ BEGIN PERFORM * FROM public.issue_ghost_profile_merge_handoff('"+secret+"','google','"+self.subject+"');END $$;RESET ROLE;COMMIT;"
        self.session.run('issue_synthetic_handoff',issue)
        return identity

    def close(self):
        self.admissions.close()


def ghost_order_cases(qualification):
    base = BASE
    relations = RELATIONS + ['auth.users','auth.identities','internal.ghost_profile_merge_handoffs']
    projection = "jsonb_build_array("+','.join("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM "+x+' t)' for x in relations)+')'
    execute = qualification.execute
    sessions = []
    fixture = None
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    qualification.record['scope'] = ('Actual authenticated Ghost preserved-reference denial versus service-role C1 in both orders. Ghost-first uses a trusted relation-lock scheduler, not a runtime actor. Synthetic identities/media admission; 24-relation projection; no successful merge/Auth API/provider/storage/installed qualification.')
    qualification.record['purchase_principal_scope'] = 'Fixture has zero principals/bindings; no principal-row contention qualified; these relations are outside the 24-relation equality projection.'
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
    identity_projection = 'jsonb_build_array(' + ','.join(("(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM " + x + ' t)' for x in relations[-3:])) + ')'
    def denied(expected, message):
        return "DO $$ DECLARE r internal.initial_preparation_admission_receipts;h internal.ghost_profile_merge_handoffs;failed BOOLEAN:=FALSE;BEGIN SELECT * INTO STRICT r FROM target;SELECT * INTO STRICT h FROM internal.ghost_profile_merge_handoffs WHERE ghost_user_id=r.owner_id;BEGIN SET LOCAL ROLE authenticated;PERFORM * FROM public.consume_ghost_profile_merge_handoff(h.id,h.secret_hash);EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'ghost_merge_preserved_reference_present: internal." + message + ".owner_id' THEN RAISE;END IF;failed:=TRUE;END;RESET ROLE;IF NOT failed OR md5((" + projection + ")::TEXT) IS DISTINCT FROM '" + expected + "' THEN RAISE EXCEPTION USING ERRCODE='ZX581';END IF;" + no_authority + 'END $$;'
    def digest(rows):
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{32}',rows[0]):
            raise RuntimeError('one private synthetic comparison image required')
        return rows[0]

    try:
        fixture = GhostFixture(qualification)
        for c1_first in (True,False):
            phase = 'c1_first' if c1_first else 'ghost_first'
            identity = fixture.admit_and_issue(fixture.owner if c1_first else fixture.second)
            start = base+"CREATE TEMP TABLE target AS SELECT * FROM internal.initial_preparation_admission_receipts WHERE owner_id='"+identity.owner_id+"' AND scan_id='"+identity.scan_id+"' AND admission_receipt_id='"+identity.receipt_id+"';DO $$ BEGIN IF (SELECT count(*) FROM target)<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX531';END IF;END $$;"
            cancellation = peer(phase+'_c1')
            ghost = peer(phase+'_ghost')
            observer = peer(phase+'_observer')
            if len({s.pid for s in sessions}) != 3:
                raise RuntimeError('distinct Ghost/C1 actor backends required')
            cancellation.run('save_original_identity',start)
            ghost.run('save_original_identity_and_claims',start+jwt(fixture.destination))
            identity_before = digest(fixture.session.run('identity_before',"SELECT md5(("+identity_projection+")::TEXT);"))
            if c1_first:
                expected = digest(cancellation.run('cancel_uncommitted',cancel+"SELECT md5(("+projection+")::TEXT);"))
                ghost.start('denied_by_cancellation_reference',denied(expected,'initial_analysis_cancellations'))
                blocking(observer,cancellation,ghost)
                cancellation.run('cancellation_commit','COMMIT;')
                ghost.finish()
                ghost.run('ghost_commit','COMMIT;')
            else:
                expected = digest(fixture.session.run('original_business_image',"SELECT md5(("+projection+")::TEXT);"))
                gate = peer('trusted_relation_lock_scheduler')
                gate.run('hold_intent_relation','BEGIN;LOCK TABLE internal.initial_analysis_preparation_intents IN ACCESS EXCLUSIVE MODE;')
                ghost.start('denied_by_intent_reference',denied(expected,'initial_analysis_preparation_intents'))
                blocking(observer,gate,ghost)
                pause = f"SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid={ghost.pid} AND relation='internal.initial_analysis_preparation_intents'::regclass AND mode='AccessShareLock' AND NOT granted) AND EXISTS(SELECT 1 FROM pg_locks WHERE pid={ghost.pid} AND relation='public.users'::regclass AND mode='RowShareLock' AND granted);"
                if observer.run('observe_ghost_pause',pause) != ['t']:
                    raise RuntimeError('Ghost preserved-reference pause missing')
                cancellation.start('cancel_waiting_on_ghost',cancel)
                blocking(observer,ghost,cancellation)
                observed = f"SELECT NOT EXISTS(SELECT 1 FROM pg_locks WHERE pid={cancellation.pid} AND relation='internal.initial_analysis_preparation_intents'::regclass AND NOT granted);"
                if observer.run('c1_not_only_waiting_on_scheduler',observed) != ['t']:
                    raise RuntimeError('C1 wait attribution missing')
                gate.run('release_scheduler','COMMIT;')
                close_group([gate])
                ghost.finish()
                ghost.run('ghost_commit','COMMIT;')
                cancellation.finish()
                cancellation.run('cancellation_commit','COMMIT;')
            close_group([cancellation,ghost,observer])
            if digest(fixture.session.run('identity_after',"SELECT md5(("+identity_projection+")::TEXT);")) != identity_before:
                raise RuntimeError('synthetic identity/handoff changed')
            qualification.record['checks'].append({'case':phase,'passed':True,'actual_blocking_observed':True,'both_committed':True,'preserved_reference':'initial_analysis_cancellations' if c1_first else 'initial_analysis_preparation_intents','identity_and_prepared_handoff_unchanged':True,'ghost_denial_full_projection_unchanged':True,'scheduler':'none' if c1_first else 'trusted ACCESS EXCLUSIVE relation lock; released before preserved-reference denial; C1 observed waiting on Ghost actor'})
            qualification.save()
        fixture.close()
        fixture = None
        phase = 'fresh_final_original_replay'
        execute(phase, base + 'DO $$ DECLARE c internal.initial_analysis_cancellations;b JSONB;a JSONB;BEGIN b:=' + projection + ';IF (SELECT count(*) FROM internal.initial_analysis_cancellations)<>2 OR (SELECT count(*) FROM internal.ghost_profile_merge_handoffs WHERE status=\'prepared\' AND target_user_id IS NULL AND merged_at IS NULL AND auth_deleted_at IS NULL)<>2 OR EXISTS(SELECT 1 FROM internal.initial_analysis_rollout WHERE initial_analysis_lifecycle_enabled) THEN RAISE EXCEPTION USING ERRCODE=\'ZX582\';END IF;FOR c IN SELECT * FROM internal.initial_analysis_cancellations LOOP SET LOCAL ROLE service_role;a:=public.cancel_initial_analysis(c.owner_id,c.scan_id);RESET ROLE;IF a IS DISTINCT FROM \'{"version":1,"outcome":"cancelled","dispatch":"dispatch_prevented"}\'::JSONB THEN RAISE EXCEPTION USING ERRCODE=\'ZX583\';END IF;PERFORM internal.assert_initial_cancellation_transients_absent(c.scan_id);END LOOP;IF b IS DISTINCT FROM ' + projection + " OR internal.initial_cancellation_sealed() OR EXISTS(SELECT 1 FROM internal.identification_invocations) THEN RAISE EXCEPTION USING ERRCODE='ZX584';END IF;END $$;COMMIT;")
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

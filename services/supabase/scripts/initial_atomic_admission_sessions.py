"""Bounded local transaction-authority schedules; SQL and replies stay in memory."""
import queue
import re
import subprocess
import threading
import time
import uuid


class Session:
    """Persistent psql with bounded commands and metadata-only failure evidence."""

    def __init__(self, qualification, name, *, statement_seconds=12, marker_seconds=20):
        if (statement_seconds, marker_seconds) not in ((12, 20), (45, 55)):
            raise ValueError("unqualified local session timeout profile")
        self.marker_seconds = marker_seconds
        self.qualification = qualification
        self.name = name
        qualification.record.setdefault("session_timeouts", []).append({
            "session": name, "statement_seconds": statement_seconds,
            "lock_seconds": 10, "marker_seconds": marker_seconds})
        qualification.save()
        self.pending = None
        self.lines = queue.Queue()
        self.process = subprocess.Popen(
            qualification.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.run("timeouts", f"SET statement_timeout='{statement_seconds}s'; SET lock_timeout='10s';")
            self.pid = int(self.run("backend", "SELECT pg_backend_pid();")[-1])
        except Exception:
            self.close()
            raise

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.rstrip())
        self.lines.put(None)

    def start(self, label, sql):
        if self.pending is not None:
            raise RuntimeError("unfinished session command")
        self.pending = ("done_" + uuid.uuid4().hex, label)
        self.process.stdin.write(sql + "\n\\echo " + self.pending[0] + "\n")
        self.process.stdin.flush()

    def finish(self):
        if self.pending is None:
            raise RuntimeError("no pending session command")
        marker, label = self.pending
        result = []
        passed = False
        failure = None
        end = time.monotonic() + self.marker_seconds
        try:
            while time.monotonic() < end:
                line = self.lines.get(timeout=max(0.01, end - time.monotonic()))
                if line is None:
                    raise RuntimeError("local session exited")
                if line == marker:
                    passed = not any(re.search(r"(?:ERROR|FATAL|WARNING):", s) for s in result)
                    if not passed:
                        raise RuntimeError("session SQL failed")
                    return result
                if line:
                    result.append(line)
            raise TimeoutError("local session deadline")
        except Exception as error:
            failure = type(error).__name__
            raise
        finally:
            self.pending = None
            output = "\n".join(result)
            self.qualification.record.setdefault("session_commands", []).append({
                "session": self.name, "case": label, "passed": passed,
                "sqlstates": re.findall(r"(?:ERROR|FATAL):\s+([0-9A-Z]{5})", output),
                "error_owners": re.findall(r"PL/pgSQL function ([A-Za-z0-9_.]+)", output),
                "error_category": failure,
            })
            self.qualification.save()

    def run(self, label, sql):
        self.start(label, sql)
        return self.finish()

    def close(self):
        # EOF closes this harness-owned connection and rolls back any open work.
        # Never cancel a build, database, or another session's operation.
        if self.process.poll() is None:
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
            self.process.wait(timeout=20)
        code = self.process.returncode
        self.qualification.record.setdefault("session_closures", []).append({
            "session": self.name, "exit_code": code,
        })
        self.qualification.save()
        if code:
            raise RuntimeError("local session closed with failure")


RELATIONS = [
    'public.users', 'public.scans', 'internal.initial_preparation_admission_receipts',
    'internal.initial_analysis_submissions', 'internal.initial_analysis_preparation_intents',
    'internal.initial_analysis_admissions', 'internal.initial_analysis_lifecycle_fences',
    'internal.initial_analysis_cancellations', 'internal.ai_quota_reservations',
    'internal.ai_quota_reservation_counters', 'internal.ai_quota_counters',
    'internal.complimentary_scan_usage', 'internal.identification_provider_attempts',
    'internal.identification_invocations', 'internal.initial_preparation_source_fences',
    'internal.initial_analysis_media_allocation_fences', 'internal.initial_analysis_operation_fences',
    'internal.initial_preparation_source_registry', 'internal.initial_analysis_media_registry',
    'internal.initial_analysis_results', 'internal.initial_analysis_completions',
]
PROJECTION = "jsonb_build_array(" + ','.join(
    "(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT),'[]'::JSONB) FROM "
    + relation + ' t)' for relation in RELATIONS) + ')'
BASE = "BEGIN;DO $$ BEGIN PERFORM set_config('request.jwt.claim.role','service_role',TRUE); END $$;"
IDS = 'SELECT owner_id,scan_id INTO STRICT o,a FROM internal.initial_preparation_admission_receipts;'


def session_authority_cases(qualification):
    """Trusted postgres sessions with service claims, not service-role RPC tests.

    A fresh singleton fixture is deliberate here. Both capture-only and advanced
    quota/credit phases roll back; the outsider cannot borrow their authority.
    """
    qualification.record['scope'] = (
        'Two trusted local postgres owner sessions with service claims; one held '
        'synthetic admission. Transaction authority only, not cross-owner, '
        'public service-role or production execution qualification.')
    for advanced in (False, True):
        sessions = []
        label = 'quota_credit_phase' if advanced else 'captured_phase'
        passed = False
        blocked = False
        try:
            for name in ('actor', 'outsider', 'observer'):
                sessions.append(Session(qualification, label + '_' + name))
            actor, outsider, observer = sessions
            if len({s.pid for s in sessions}) != 3:
                raise RuntimeError('distinct backends required')
            body = "DO $$ DECLARE o UUID;a UUID;r internal.ai_quota_reservations;BEGIN " + IDS + "INSERT INTO internal.initial_admitted_cancellation_staging(scan_id,owner_id) VALUES(a,o);SELECT * INTO STRICT r FROM internal.ai_quota_reservations WHERE original_analysis_id=a;IF NOT internal.initial_cancellation_quota_authorized(r.id,o,r.lease_token,'refunded') THEN RAISE EXCEPTION USING ERRCODE='ZX511';END IF;"
            if advanced:
                body += "PERFORM internal.finalize_ai_quota_reservation_core(r.id,o,r.lease_token,'refunded');PERFORM internal.settle_complimentary_analysis(o,a,'cancelled_before_dispatch');"
            actor.run('capture_authority', BASE + body + "END $$;")
            outside = "DO $$ DECLARE o UUID;a UUID;r internal.ai_quota_reservations;old_image JSONB;BEGIN " + IDS + "SELECT * INTO STRICT r FROM internal.ai_quota_reservations WHERE original_analysis_id=a;SELECT to_jsonb(l) INTO STRICT old_image FROM internal.initial_analysis_lifecycle_fences l WHERE scan_id=a;IF EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) OR internal.initial_cancellation_quota_authorized(r.id,o,r.lease_token,'refunded') OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','sample') OR internal.initial_cancellation_credit_authorized(o,a,'cancelled_before_dispatch','settle') OR internal.initial_cancellation_lifecycle_authorized(old_image,old_image||jsonb_build_object('state','cancelled_pre_dispatch')) OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX512';END IF;END $$;"
            outsider.run('helpers_deny_borrowed_authority', BASE + 'CREATE TEMP TABLE outside_before AS SELECT ' + PROJECTION + ' AS value;' + outside)
            attempt = "DO $$ DECLARE r internal.ai_quota_reservations;failed BOOLEAN:=FALSE;BEGIN SELECT * INTO STRICT r FROM internal.ai_quota_reservations;BEGIN PERFORM internal.finalize_ai_quota_reservation_core(r.id,r.user_id,r.lease_token,'refunded');EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM<>'initial_analysis_settlement_unavailable' THEN RAISE;END IF;failed:=TRUE;END;IF NOT failed THEN RAISE EXCEPTION USING ERRCODE='ZX513';END IF;END $$;"
            outsider.start('original_owner_denied_after_wait', attempt)
            end = time.monotonic() + 5
            while time.monotonic() < end:
                if observer.run('observe_blocker', f'SELECT {actor.pid}=ANY(pg_blocking_pids({outsider.pid}));') == ['t']:
                    blocked = True
                    break
                time.sleep(0.05)
            if not blocked:
                raise RuntimeError('expected original-owner wait missing')
            actor.run('rollback_authority', 'ROLLBACK;')
            outsider.finish()
            outsider.run('rollback_preserves_relations', "DO $$ BEGIN IF (SELECT value FROM outside_before) IS DISTINCT FROM " + PROJECTION + " OR EXISTS(SELECT 1 FROM internal.initial_admitted_cancellation_staging) OR internal.initial_cancellation_sealed() THEN RAISE EXCEPTION USING ERRCODE='ZX514';END IF;END $$;COMMIT;")
            passed = True
        finally:
            errors = []
            # Release actor locks before closing a blocked outsider on failure.
            for session in sessions:
                try:
                    session.close()
                except Exception as error:
                    errors.append(type(error).__name__)
            qualification.record['checks'].append({
                'case': label, 'passed': passed and not errors,
                'original_owner_blocking_observed': blocked,
                'distinct_backends': len(sessions) == 3 and len({s.pid for s in sessions}) == 3,
                'close_errors': errors,
            })
            qualification.save()
            if errors:
                raise RuntimeError('session cleanup failed')

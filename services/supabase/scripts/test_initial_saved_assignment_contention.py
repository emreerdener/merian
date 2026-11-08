#!/usr/bin/env python3
"""Deterministic inactive IC-1 qualification on an explicitly disposable local DB.

Uses psql inside the named local Supabase Docker container; no DSN/secrets or
hosted connection support. Keeps only synthetic content-free operation fences.
All changed catalog values roll back. Run after the SQL catalog suite.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]


def literal(value):
    return "'" + value.replace("'", "''") + "'"


class Session:
    def __init__(self, container):
        self.process = subprocess.Popen(
            ["docker", "exec", "-i", container, "sh", "-c", "exec psql -X -qAt -U postgres -d postgres 2>&1"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        self.lines = queue.Queue()
        self.pending = None
        threading.Thread(target=self._read, daemon=True).start()
        self.run("\\set VERBOSITY verbose\nSET statement_timeout='8s'; SET lock_timeout='6s';")
        self.pid = int(self.run("SELECT pg_backend_pid();")[-1])

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.rstrip())
        self.lines.put(None)

    def start(self, sql):
        assert self.pending is None, "finish the previous command first"
        marker = "done_" + uuid.uuid4().hex
        self.pending = marker
        self.process.stdin.write(sql + "\n\\echo " + marker + "\n")
        self.process.stdin.flush()
        return marker

    def finish(self, marker):
        result = []
        end = time.monotonic() + 12
        while time.monotonic() < end:
            line = self.lines.get(timeout=max(0.01, end-time.monotonic()))
            if line == marker:
                self.pending = None
                return result
            if line is None:
                raise RuntimeError("local test session exited")
            if line:
                result.append(line)
        raise RuntimeError("local test session deadline exceeded")

    def run(self, sql, error=None):
        result = self.finish(self.start(sql))
        errors = [line for line in result if "ERROR:" in line or "FATAL:" in line]
        if error:
            assert any(error in line for line in errors), (error, result)
        else:
            assert not errors, result
        return result

    def close(self):
        if self.process.poll() is None:
            try:
                self.run("ROLLBACK;")
                self.process.stdin.write("\\q\n")
                self.process.stdin.flush()
                self.process.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.terminate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disposable-container", required=True)
    args = parser.parse_args()
    container = args.disposable_container
    assert container.startswith("supabase_db_") and all(c.isalnum() or c in "_-" for c in container)
    info = json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
    bindings = info["HostConfig"]["PortBindings"]["5432/tcp"]
    assert bindings, "named local database port binding required"
    # Docker exec stays inside the explicitly named local container. Supabase
    # may publish its local port on all interfaces; this is not a remote DSN.
    context = json.loads(subprocess.check_output(["docker", "context", "inspect"], text=True))[0]
    engine = os.environ.get("DOCKER_HOST") or context["Endpoints"]["docker"]["Host"]
    assert engine.startswith("unix://"), "local Unix-socket Docker engine required"
    sessions = [Session(container) for _ in range(3)]
    admin, first, second = sessions
    owners = [str(uuid.uuid4()) for _ in range(2)]
    scan = str(uuid.uuid4())
    fixture = json.loads((ROOT / "services/supabase/functions/_shared/initialAnalysis/fixtures/preparation-v2.json").read_text())
    candidate = literal(fixture["candidate_canonical"])
    tests = (ROOT / "services/supabase/tests/initial_analysis_admission.sql").read_text()
    helpers = tests.split("-- BEGIN INITIAL ADMISSION HELPERS\n")[1].split("-- END INITIAL ADMISSION HELPERS")[0]
    initialized = False
    try:
        assert admin.run("SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout;") == ["f"], "gate must begin disabled"
        admin.run(helpers)
        admin.run("BEGIN; " + "".join("SELECT pg_temp.admission_owner("+literal(o)+");" for o in owners) +
                  "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE; COMMIT;")
        initialized = True
        focused = (ROOT / "services/supabase/tests/initial_saved_assignment.sql").read_text()
        tripwires = focused.split("CREATE FUNCTION pg_temp.funding_tripwire()", 1)[1].split("SELECT set_config('merian.test_funding_tripwire'", 1)[0]
        admin.run("CREATE FUNCTION pg_temp.funding_tripwire()" + tripwires)
        for s in sessions:
            s.run("SELECT set_config('request.jwt.claim.role','service_role',FALSE);")
        create = "SELECT public.create_initial_preparation_intent("+literal(owners[0])+","+literal(scan)+","+candidate+");"
        finalize = "SELECT public.finalize_initial_preparation("+literal(owners[0])+","+literal(scan)+",repeat('a',64));"
        admin.run(create)
        plan = admin.run("SELECT canonical_assignment::JSONB->>'effective_plan' FROM internal.initial_analysis_preparation_intents WHERE scan_id="+literal(scan)+";")[-1]
        targets = [
            ("entitlement rollout", "internal.entitlement_rollout_config", "config_key='current'"),
            ("initial rollout", "internal.initial_analysis_rollout", "singleton"),
            ("policy", "internal.ai_quota_policies", "operation='scan_identification' AND effective_plan="+literal(plan)),
            ("binding", "internal.identification_provider_bindings", "operation='scan_identification' AND input_profile='description_compat_v1' AND effective_plan="+literal(plan)),
            ("consent rollout", "internal.ai_consent_rollout_config", "config_key='current'"),
            ("adult receipt", "public.user_adult_eligibility_receipts", "user_id="+literal(owners[0])),
            ("terms receipt", "public.user_terms_acceptance_receipts", "user_id="+literal(owners[0])),
            ("consent event", "public.user_ai_consent_events", "user_id="+literal(owners[0])),
        ]
        for label, table, where in targets:
            second.run("BEGIN; SELECT 1 FROM "+table+" WHERE "+where+" FOR UPDATE;")
            first.run("BEGIN; SELECT set_config('merian.test_funding_tripwire','on',TRUE);")
            first.run(finalize, error="55P03")
            first.run("ROLLBACK;")
            second.run("ROLLBACK;")
            assert admin.run("SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id="+literal(scan)+";") == ["0"]
            first.run("BEGIN; "+finalize)
            second.run("BEGIN;")
            second.run("SELECT 1 FROM "+table+" WHERE "+where+" FOR UPDATE NOWAIT;", error="55P03")
            second.run("ROLLBACK;")
            first.run("ROLLBACK;")
            print("PASS opposed locks:", label, flush=True)

        # A new consent row has no existing-row lock: prove immediate FK wait.
        first.run("BEGIN; "+finalize)
        second.run("BEGIN;")
        insert = "INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build) SELECT gen_random_uuid(),user_id,provider,disclosure_version,'revoked',clock_timestamp(),disclosure_text,action_text,platform,app_version,app_build FROM public.user_ai_consent_events WHERE user_id="+literal(owners[0])+" LIMIT 1;"
        pending = second.start(insert)
        deadline = time.monotonic()+3
        while time.monotonic()<deadline:
            if admin.run("SELECT "+str(first.pid)+"=ANY(pg_blocking_pids("+str(second.pid)+"));") == ["t"]:
                break
            time.sleep(0.02)
        else:
            raise AssertionError("new consent row did not wait on owner FK")
        first.run("ROLLBACK;")
        result = second.finish(pending)
        assert not any("ERROR:" in line for line in result), result
        second.run("ROLLBACK;")
        print("PASS new consent insertion waits on original owner", flush=True)

        # All receipt owner FKs must be immediate: unrelated-owner rows can
        # be reassigned only after the target owner releases its funding lock.
        for table in ["public.user_adult_eligibility_receipts", "public.user_terms_acceptance_receipts", "public.user_ai_consent_events"]:
            assert admin.run("SELECT count(*) FROM pg_constraint WHERE conrelid="+literal(table)+"::regclass AND contype='f' AND confrelid='public.users'::regclass AND NOT condeferrable;") == ["1"]
            move = "UPDATE "+table+" SET user_id="+literal(owners[0])+" WHERE user_id="+literal(owners[1])+";"
            first.run("BEGIN; "+finalize)
            second.run("BEGIN;")
            pending = second.start(move)
            deadline = time.monotonic()+3
            while time.monotonic()<deadline:
                if admin.run("SELECT "+str(first.pid)+"=ANY(pg_blocking_pids("+str(second.pid)+"));") == ["t"]:
                    break
                time.sleep(0.02)
            else:
                raise AssertionError("receipt reassignment did not wait on target owner")
            first.run("ROLLBACK;")
            result = second.finish(pending)
            assert not any("ERROR:" in line for line in result), result
            second.run("ROLLBACK;")
            # Opposite winner: the FK's key-share lock must hold funding at its
            # initial owner lock until the move transaction resolves.
            second.run("BEGIN; "+move)
            first.run("BEGIN;")
            pending = first.start(finalize)
            deadline = time.monotonic()+3
            while time.monotonic()<deadline:
                if admin.run("SELECT "+str(second.pid)+"=ANY(pg_blocking_pids("+str(first.pid)+"));") == ["t"]:
                    break
                time.sleep(0.02)
            else:
                raise AssertionError("funding did not wait on receipt reassignment")
            second.run("ROLLBACK;")
            result = first.finish(pending)
            assert not any("ERROR:" in line for line in result), result
            first.run("ROLLBACK;")
            print("PASS opposed immediate owner FK reassignment:", table, flush=True)

        # Same absent scan, different owners: contender must lose after the
        # first committed global claim, not bind a second private owner.
        collision = str(uuid.uuid4())
        first.run("BEGIN; SELECT public.create_initial_preparation_intent("+literal(owners[0])+","+literal(collision)+","+candidate+");")
        second.run("BEGIN;")
        pending = second.start("SELECT public.create_initial_preparation_intent("+literal(owners[1])+","+literal(collision)+","+candidate+");")
        deadline = time.monotonic()+3
        while time.monotonic()<deadline:
            if admin.run("SELECT "+str(first.pid)+"=ANY(pg_blocking_pids("+str(second.pid)+"));") == ["t"]:
                break
            time.sleep(0.02)
        else:
            raise AssertionError("cross-owner claim did not share the namespace lock")
        first.run("COMMIT;")
        result = second.finish(pending)
        assert any("P0002" in line for line in result), result
        second.run("ROLLBACK;")
        print("PASS concurrent no-row cross-owner claim", flush=True)

        # Deadline crosses the exact request lock wait inside the comparison.
        admin.run("BEGIN; ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage; UPDATE internal.initial_analysis_preparation_intents SET created_at=now()-INTERVAL '298 seconds',expires_at=now()+INTERVAL '2 seconds' WHERE scan_id="+literal(scan)+"; ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage; COMMIT;")
        second.run("BEGIN; SELECT pg_advisory_xact_lock(hashtextextended("+literal(owners[0]+":scan_identification:"+scan)+",0::BIGINT));")
        first.run("BEGIN; SELECT set_config('merian.test_funding_tripwire','on',TRUE);")
        pending = first.start(finalize)
        deadline = time.monotonic()+3
        while time.monotonic()<deadline:
            if admin.run("SELECT "+str(second.pid)+"=ANY(pg_blocking_pids("+str(first.pid)+"));") == ["t"]:
                break
            time.sleep(0.02)
        else:
            raise AssertionError("comparison did not reach exact request wait")
        while admin.run("SELECT clock_timestamp()>=expires_at FROM internal.initial_analysis_preparation_intents WHERE scan_id="+literal(scan)+";") != ["t"]:
            time.sleep(0.02)
        second.run("ROLLBACK;")
        result = first.finish(pending)
        assert any("55000" in line and "initial_analysis_preparation_expired" in line for line in result), result
        first.run("ROLLBACK;")
        assert admin.run("SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id="+literal(scan)+";") == ["0"]
        print("PASS expiry after actual pre-funding wait", flush=True)
    finally:
        for s in sessions:
            if s.process.poll() is None:
                if s.pending is not None:
                    s.finish(s.pending)
                s.run("ROLLBACK;")
        if initialized:
            for table in ["internal.ai_quota_reservations", "internal.ai_quota_counters", "internal.complimentary_scan_usage", "internal.identification_provider_attempts", "public.users"]:
                admin.run("DROP TRIGGER IF EXISTS test_funding_tripwire ON "+table+";")
            admin.run("UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            admin.run("BEGIN; DELETE FROM public.users WHERE id IN ("+",".join(map(literal, owners))+"); DELETE FROM auth.users WHERE id IN ("+",".join(map(literal, owners))+"); COMMIT;")
        for s in sessions:
            s.close()


if __name__ == "__main__":
    main()

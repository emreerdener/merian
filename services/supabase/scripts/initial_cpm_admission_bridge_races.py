"""Owned disposable CPM service-RPC schedules; no hosted, HTTP or provider I/O.

Each run needs a fresh replay. Three real sessions establish the blocked peer
before committing the first transaction. Synthetic identities/replies stay in
memory. This tests database serialization, not HTTP acknowledgement delivery.
"""
import argparse
import json
import re
import time
from pathlib import Path

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session, BASE
from initial_cpm_atomic_admission_committed import FIXTURE
from initial_cpm_admission_policy_order import PROJECTION

START = """
CREATE TEMP TABLE verification_started(value JSONB);
DO $$ DECLARE s internal.initial_analysis_preparation_intents; result JSONB;
BEGIN
 SELECT * INTO STRICT s FROM internal.initial_analysis_preparation_intents
 WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 SET LOCAL ROLE service_role;
 result:=public.begin_initial_cpm_photo_admission(s.owner_id,s.scan_id,
  s.canonical_candidate,s.canonical_assignment,s.assignment_digest);
 RESET ROLE;
 INSERT INTO verification_started VALUES(result);
END $$;
"""


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def expect_denial(expression, code):
    # An expected denial is a subtransaction; unexpected errors still abort.
    return "DO $$ BEGIN BEGIN PERFORM " + expression + "; EXCEPTION WHEN SQLSTATE '" + code + "' THEN RETURN; END; RAISE EXCEPTION 'missing expected denial' USING ERRCODE='ZX711'; END $$;"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--evidence-directory", required=True)
    parser.add_argument("--replay-manifest", required=True)
    parser.add_argument("--peer", choices=["recovery", "admission", "cancellation", "account-erasure", "scan-deletion"], required=True)
    parser.add_argument("--first", choices=["admission", "peer"], required=True)
    args = parser.parse_args()
    q = None
    sessions = []
    started = time.monotonic()
    try:
        q = Qualification(args.container, args.evidence_directory, "cpm-bridge-race", args.replay_manifest)
        for path in [Path(__file__).resolve(), FIXTURE,
                     Path(__file__).with_name("initial_cpm_atomic_admission_committed.py"),
                     Path(__file__).with_name("initial_cpm_admission_policy_order.py")]:
            q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
        q.record.update(peer=args.peer, first=args.first,
                        scope="Fresh local synthetic service RPCs, fresh begin, observed lock wait and both transactions committed. No HTTP, timed-out server statement, physical verification, terminal delivery or native qualification.")
        for name in ["admission", "peer", "observer"]:
            sessions.append(Session(q, name, statement_seconds=45, marker_seconds=55))
        actor, peer, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError("three distinct database sessions required")
        source = FIXTURE.read_text()
        boundary = "SAVEPOINT cpm_positive_admission;"
        old_start = "CREATE TEMP TABLE verification_started AS SELECT pg_temp.start_verification() value;"
        if source.count(boundary) != 1 or source.count(old_start) != 1:
            raise ValueError("unique fixture/start boundaries required")
        source = source.split(boundary)[0].replace(old_start, START)
        output = "\n".join(actor.run("commit_fresh_service_start_fixture", source + "SELECT * FROM extensions.finish();COMMIT;"))
        if (re.findall(r"^ok ([0-9]+) - .*$", output, re.M) != [str(i) for i in range(1, 133)]
                or re.findall(r"^1\.\.([0-9]+)$", output, re.M) != ["132"]
                or re.search(r"^not ok|#\s*(?:SKIP|TODO)", output, re.M | re.I)):
            raise ValueError("132 complete unskipped fixture assertions required")
        q.record["fixture_assertions"] = 132
        facts = json.loads(actor.run("saved_identity", "SELECT jsonb_build_array(owner_id,scan_id,canonical_candidate,canonical_assignment,assignment_digest,(SELECT evidence FROM cpm_admission_verified)) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101';")[0])
        identity = ",".join(map(literal, facts[:5]))
        read = "public.read_initial_cpm_photo_admission(" + identity + ")"
        admit = "public.admit_initial_cpm_photo(" + identity + "," + literal(facts[5]) + ",repeat('a',64))"
        cancel = "public.cancel_initial_analysis(" + ",".join(map(literal, facts[:2])) + ")"
        account = "public.apply_user_tombstone(" + literal(facts[0]) + ")"
        scan_delete = "public.request_scan_deletion(" + literal(facts[1]) + "," + literal(facts[0]) + ")"
        service = BASE + "SET LOCAL ROLE service_role;"
        peer_call = {"recovery": read, "admission": admit, "cancellation": cancel, "account-erasure": account, "scan-deletion": scan_delete}[args.peer]
        # The real pre-row deletion API is deliberately not_found, never raw tombstone insertion.
        delete_before = observer.run("before_scan_deletion_race", PROJECTION) if args.peer == "scan-deletion" else None
        # First execute the actual operation but hold its uncommitted transaction.
        first, second = (actor, peer) if args.first == "admission" else (peer, actor)
        first_call, second_call = (admit, peer_call) if args.first == "admission" else (peer_call, admit)
        first_result = first.run("first_operation_uncommitted", service + "SELECT " + first_call + ";")
        if args.peer == "scan-deletion":
            first_image = first.run("after_first_scan_deletion_race_operation", "RESET ROLE;" + PROJECTION + "SET LOCAL ROLE service_role;")
            if args.first == "peer" and first_image != delete_before:
                raise ValueError("pre-row deletion changed saved state")
        if args.peer == "account-erasure" and args.first == "admission":
            if json.loads(first_result[0])["outcome"] != "admitted":
                raise ValueError("admission must exist before account erasure")
            funded = first.run("original_funding_before_account_cascade", "RESET ROLE;SELECT count(*)=1 AND bool_and(state='reserved' AND refund_count=0) FROM internal.ai_quota_reservations WHERE request_id=" + literal(facts[1]) + ";SET LOCAL ROLE service_role;")
            if funded != ["t"]:
                raise ValueError("one original reservation required before account erasure")
        destructive_first = args.first == "peer" and args.peer in ["cancellation", "account-erasure"]
        second_sql = expect_denial(second_call, "P0002" if args.peer == "account-erasure" else "55000") if destructive_first else "SELECT " + second_call + ";"
        second.start("second_operation_waits_then_commits", service + second_sql + "COMMIT;")
        end = time.monotonic() + 5
        blocked = False
        while time.monotonic() < end:
            if observer.run("observe_actual_peer_lock", f"SELECT {first.pid}=ANY(pg_blocking_pids({second.pid}));") == ["t"]:
                blocked = True
                break
            time.sleep(0.05)
        if not blocked:
            raise ValueError("actual overlapping RPC lock wait not observed")
        first.run("commit_first_operation", "COMMIT;")
        second_result = second.finish()
        destructive = args.peer in ["cancellation", "account-erasure"]
        if not destructive:
            result = json.loads(observer.run("exact_committed_recovery", service + "SELECT " + read + ";COMMIT;")[0])
            if result["outcome"] != "admitted" or result["authority"] != "none":
                raise ValueError("committed observation required")
            admission_result = first_result if args.first == "admission" or args.peer == "admission" else second_result
            if json.loads(admission_result[0]) != result:
                raise ValueError("admission/recovery identity mismatch")
            if args.peer == "admission" and json.loads(second_result[0]) != result:
                raise ValueError("concurrent admission returned a different receipt")
            if args.peer == "recovery":
                expected = "admitted" if args.first == "admission" else "unadmitted"
                if json.loads((second_result if args.first == "admission" else first_result)[0])["outcome"] != expected:
                    raise ValueError("recovery serialization outcome mismatch")
            if args.peer == "scan-deletion":
                deletion_result = second_result if args.first == "admission" else first_result
                if deletion_result != ["not_found"]:
                    raise ValueError("pre-row deletion must return not_found")
                if args.first == "admission" and observer.run("scan_deletion_preserves_admitted_image", PROJECTION) != first_image:
                    raise ValueError("scan deletion changed admitted state")
                scan = literal(facts[1])
                postimage = "SELECT NOT EXISTS(SELECT 1 FROM public.scans WHERE id=" + scan + ")" + \
                    " AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=" + scan + ")" + \
                    " AND (SELECT count(*) FROM internal.initial_analysis_admissions WHERE scan_id=" + scan + ")=1" + \
                    " AND (SELECT count(*) FROM internal.initial_preparation_admission_receipts WHERE scan_id=" + scan + ")=1" + \
                    " AND EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=" + scan + " AND state='pending_pre_dispatch')" + \
                    " AND EXISTS(SELECT 1 FROM internal.initial_cpm_photo_capacity_reservations WHERE scan_id=" + scan + " AND state='admitted')" + \
                    " AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_results WHERE scan_id=" + scan + ")" + \
                    " AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_completions WHERE scan_id=" + scan + ");"
                if observer.run("pre_row_scan_deletion_postimage", postimage) != ["t"]:
                    raise ValueError("pre-row deletion/admission postimage mismatch")
        else:
            observer.run("post_commit_recovery_denied", service + expect_denial(read, "P0002" if args.peer == "account-erasure" else "55000") + "COMMIT;")
        # Only the real admission winner may fund; C1 alone refunds positive unused work.
        state = "refunded" if args.peer == "cancellation" else "reserved"
        refunds = 1 if args.peer == "cancellation" else 0
        expected_count = 0 if destructive_first or args.peer == "account-erasure" else 1
        check = f"""SELECT
 (SELECT count(*) FROM internal.ai_quota_reservations WHERE request_id={literal(facts[1])})={expected_count}
 AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE request_id={literal(facts[1])}
  AND (state<>{literal(state)} OR refund_count<>{refunds}))
 AND NOT EXISTS(SELECT 1 FROM internal.identification_invocations)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_cpm_verification_start_context);"""
        if observer.run("single_original_funding_and_no_execution", check) != ["t"]:
            raise ValueError("funding or transient invariant failed")
        for session in sessions:
            session.close()
        sessions = []
        q.execute("disable_synthetic_fixture_rollout", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
        q.record["wall_seconds"] = time.monotonic() - started
        q.finish()
        print("PASS CPM bridge " + args.first + " first / " + args.peer, flush=True)
        return 0
    except Exception as error:
        for session in sessions:
            try:
                session.close()
            except Exception:
                pass
        if q is not None:
            q.record.update(error_category=type(error).__name__, wall_seconds=time.monotonic() - started)
            q.save()
            try:
                q.execute("restore_disabled_gate_after_failure", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            except Exception:
                q.record["gate_restore_failed"] = True
                q.save()
        print("FAIL CPM bridge schedule: " + type(error).__name__, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

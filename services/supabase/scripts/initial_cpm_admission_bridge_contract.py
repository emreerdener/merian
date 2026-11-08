"""Local service-only CPM recovery identity, policy and atomicity qualification.

Promotes the retained bridge experiment into the existing owned replay harness.
No hosted DSN, HTTP/provider I/O, installed route or client verification authority.
"""
import argparse
import json
import re
import time
from pathlib import Path

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session, BASE
from initial_cpm_atomic_admission_committed import FIXTURE, cancellation_cases
from initial_cpm_admission_policy_order import PROJECTION
from initial_cpm_admission_bridge_races import START, literal

FUNDING = "SELECT jsonb_build_array(" + ",".join(
    "(SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT) FROM " + relation + " t)"
    for relation in ["internal.initial_analysis_preparation_intents",
                     "internal.initial_preparation_admission_receipts",
                     "internal.initial_analysis_submissions", "internal.initial_analysis_admissions",
                     "internal.ai_quota_reservations", "internal.ai_quota_reservation_counters",
                     "internal.ai_quota_counters", "internal.complimentary_scan_usage",
                     "internal.identification_provider_attempts", "internal.identification_invocations"]
) + ");"



def verification_current_cases(q, facts, phase):
    saved = json.loads(q.execute("current_original_start", "SELECT jsonb_build_array(cpm_verification_attempt_id,cpm_verification_snapshot_digest) FROM internal.initial_analysis_preparation_intents WHERE scan_id=" + literal(facts[1]) + ";"))
    args = [facts[0], facts[1], facts[4], saved[0], saved[1]]
    expression = "public.assert_initial_cpm_photo_verification_current(" + ",".join(map(literal, args)) + ")"
    service = BASE + "SET LOCAL ROLE service_role;"
    if phase == "admitted":
        q.execute("current_denies_admitted_work", service + "SELECT " + expression + ";COMMIT;", "22023")
        return
    before = q.execute("current_before_image", PROJECTION)
    expected = {"version":1,"outcome":"current","authority":"none","owner_id":facts[0],"scan_id":facts[1],"assignment_digest":facts[4],"attempt_id":saved[0],"snapshot_digest":saved[1]}
    for i in range(2):
        if json.loads(q.execute("current_exact_observation_" + str(i), service + "SELECT " + expression + ";COMMIT;")) != expected:
            raise ValueError("current acknowledgement identity mismatch")
    for role in ["anon", "authenticated"]:
        q.execute(role + "_current_denied", BASE + "SET LOCAL ROLE " + role + ";SELECT " + expression + ";COMMIT;", "42501")
    for index, label in [(2,"assignment"),(3,"attempt"),(4,"snapshot")]:
        wrong = list(args)
        wrong[index] = "00000000-0000-4000-8000-00000000f099" if index == 3 else "0" * 64
        q.execute("current_wrong_" + label, service + "SELECT public.assert_initial_cpm_photo_verification_current(" + ",".join(map(literal, wrong)) + ");COMMIT;", "22023")
    for label, mutation in [
        ("rollout", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;"),
        ("profile", "UPDATE internal.initial_cpm_photo_profile_eligibility SET state='revoked';"),
        ("backend", "UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';"),
        ("write_policy", "UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';")]:
        q.execute("current_revoked_" + label, BASE + mutation + "SET LOCAL ROLE service_role;SELECT " + expression + ";COMMIT;", "55000")
    if q.execute("current_after_image", PROJECTION) != before:
        raise ValueError("current checks changed saved/funding facts")



def partial_recovery_cases(q, facts):
    """Disposable fault injection only; each rejected transaction rolls back DDL/DML.

    Restore row guards before exercising the actual service reader. Never commit
    a partial image or treat this as evidence of a naturally reachable state.
    """
    before = q.execute("partial_recovery_original_image", PROJECTION)
    funding = q.execute("partial_recovery_original_funding", FUNDING)
    scan = literal(facts[1])
    identity = ",".join(map(literal, facts[:5]))
    for table, label in [
        ("internal.initial_analysis_admissions", "missing_admission"),
        ("internal.initial_preparation_admission_receipts", "missing_receipt"),
    ]:
        for operation in ["read", "begin", "admit"]:
            expression = "public." + operation + "_initial_cpm_photo_admission(" + identity + ")"
            if operation == "admit":
                expression = "public.admit_initial_cpm_photo(" + identity + "," + literal(facts[5]) + ",repeat('a',64))"
            fault = (BASE + "ALTER TABLE " + table + " DISABLE TRIGGER USER;"
                     + "DELETE FROM " + table + " WHERE scan_id=" + scan + ";"
                     + "ALTER TABLE " + table + " ENABLE TRIGGER USER;"
                     + "SET LOCAL ROLE service_role;SELECT " + expression + ";COMMIT;")
            q.execute("partial_" + label + "_" + operation + "_denied", fault, "55000")
            if "internal.read_initial_cpm_admission_state" not in q.record["checks"][-1]["error_owners"]:
                raise ValueError("partial-state denial did not reach service reader")
            if q.execute("partial_" + label + "_" + operation + "_restored", PROJECTION) != before:
                raise ValueError("partial-state fault escaped rollback")
            if q.execute("partial_" + label + "_" + operation + "_funding", FUNDING) != funding:
                raise ValueError("partial-state recovery changed funding")



def contradictory_recovery_cases(q, facts):
    """Inject schema-valid contradictions only in rollback-bound local fixtures."""
    before = q.execute("contradictory_original_image", PROJECTION)
    funding = q.execute("contradictory_original_funding", FUNDING)
    identity = ",".join(map(literal, facts[:5]))
    for label, table, change in [
        ("capacity_state", "internal.initial_cpm_photo_capacity_reservations", "state='pending'"),
        ("capacity_bytes", "internal.initial_cpm_photo_capacity_reservations", "declared_retained_bytes=declared_retained_bytes+1"),
        ("verification_digest", "internal.initial_analysis_preparation_intents", "cpm_verification_snapshot_digest=repeat('0',64)"),
    ]:
        for operation in ["read", "begin", "admit"]:
            expression = "public." + operation + "_initial_cpm_photo_admission(" + identity + ")"
            if operation == "admit":
                expression = "public.admit_initial_cpm_photo(" + identity + "," + literal(facts[5]) + ",repeat('a',64))"
            fault = (BASE + "ALTER TABLE " + table + " DISABLE TRIGGER USER;"
                     + "UPDATE " + table + " SET " + change + " WHERE scan_id=" + literal(facts[1]) + ";"
                     + "ALTER TABLE " + table + " ENABLE TRIGGER USER;"
                     + "SET LOCAL ROLE service_role;SELECT " + expression + ";COMMIT;")
            q.execute("contradictory_" + label + "_" + operation + "_denied", fault, "55000")
            owners = q.record["checks"][-1]["error_owners"]
            if ("internal.read_initial_cpm_admission_state" not in owners
                    or "internal.assert_initial_cpm_receipt_cohort" not in owners):
                raise ValueError("contradiction did not reach the retained-cohort validator")
            if q.execute("contradictory_" + label + "_" + operation + "_restored", PROJECTION) != before:
                raise ValueError("contradictory fault escaped rollback")
            if q.execute("contradictory_" + label + "_" + operation + "_funding", FUNDING) != funding:
                raise ValueError("contradictory recovery changed funding")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["container", "evidence-directory", "replay-manifest"]:
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--current-verification", action="store_true")
    parser.add_argument("--partial-recovery", action="store_true")
    parser.add_argument("--contradictory-recovery", action="store_true")
    args = parser.parse_args()
    q = None
    actor = None
    started = time.monotonic()
    try:
        q = Qualification(args.container, args.evidence_directory, "cpm-bridge-contract", args.replay_manifest)
        for path in [Path(__file__).resolve(), FIXTURE,
                     Path(__file__).with_name("initial_cpm_atomic_admission_committed.py"),
                     Path(__file__).with_name("initial_cpm_admission_policy_order.py"),
                     Path(__file__).with_name("initial_cpm_admission_bridge_races.py")]:
            q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
        q.record["current_verification"] = args.current_verification
        q.record["partial_recovery"] = args.partial_recovery
        q.record["contradictory_recovery"] = args.contradictory_recovery
        q.record["scope"] = "Fresh local synthetic service RPC identity/role denials, exact committed recovery after policy revocation, rollback fault and C1 fence. No HTTP or real media/native journey qualification."
        actor = Session(q, "fixture", statement_seconds=45, marker_seconds=55)
        source = FIXTURE.read_text()
        boundary = "SAVEPOINT cpm_positive_admission;"
        old_start = "CREATE TEMP TABLE verification_started AS SELECT pg_temp.start_verification() value;"
        if source.count(boundary) != 1 or source.count(old_start) != 1:
            raise ValueError("unique fixture boundaries required")
        output = "\n".join(actor.run("fresh_service_start", source.split(boundary)[0].replace(old_start, START) + "SELECT * FROM extensions.finish();COMMIT;"))
        if (re.findall(r"^ok ([0-9]+) - .*$", output, re.M) != [str(i) for i in range(1, 133)]
                or re.findall(r"^1\.\.([0-9]+)$", output, re.M) != ["132"]
                or re.search(r"^not ok|#\s*(?:SKIP|TODO)", output, re.M | re.I)):
            raise ValueError("complete unskipped fixture required")
        q.record["fixture_assertions"] = 132
        actor.run("distinct_existing_owner", BASE + "SELECT pg_temp.admission_owner('00000000-0000-4000-8000-00000000f002');COMMIT;")
        facts = json.loads(actor.run("saved_identity", "SELECT jsonb_build_array(owner_id,scan_id,canonical_candidate,canonical_assignment,assignment_digest,(SELECT evidence FROM cpm_admission_verified)) FROM internal.initial_analysis_preparation_intents WHERE scan_id='00000000-0000-4000-8000-00000000f101';")[0])
        actor.close()
        actor = None

        def expression(operation, values=facts):
            identity = ",".join(map(literal, values[:5]))
            if operation == "admit":
                return "public.admit_initial_cpm_photo(" + identity + "," + literal(values[5]) + ",repeat('a',64))"
            return "public." + operation + "_initial_cpm_photo_admission(" + identity + ")"

        def call(label, operation, values=facts, role="service_role", expected=None):
            return q.execute(label, BASE + "SET LOCAL ROLE " + role + ";SELECT " + expression(operation, values) + ";COMMIT;", expected)

        if args.current_verification:
            verification_current_cases(q, facts, "unadmitted")
        before = q.execute("original_unadmitted_image", PROJECTION)
        if json.loads(call("exact_unadmitted", "read"))["outcome"] != "unadmitted":
            raise ValueError("conclusive exact absence required")
        if json.loads(call("saved_start_held", "begin"))["outcome"] != "held":
            raise ValueError("saved start must not reissue")
        for role in ["anon", "authenticated"]:
            for op in ["read", "begin", "admit"]:
                call(role + "_" + op, op, role=role, expected="42501")

        def identity_denials(phase):
            mutations = [("missing_owner", 0, "00000000-0000-4000-8000-00000000f099", "P0002"),
                         ("wrong_owner", 0, "00000000-0000-4000-8000-00000000f002", "22023"),
                         ("missing_scan", 1, "00000000-0000-4000-8000-00000000f199", "22023"),
                         ("candidate_bytes", 2, facts[2] + " ", "22023"),
                         ("assignment_bytes", 3, facts[3] + " ", "22023"),
                         ("assignment_digest", 4, "0" * 64, "22023")]
            for name, index, replacement, code in mutations:
                changed = list(facts)
                changed[index] = replacement
                for op in ["read", "begin", "admit"]:
                    call(phase + "_" + name + "_" + op, op, changed, expected=code)

        identity_denials("unadmitted")
        if q.execute("denials_preserve_original_image", PROJECTION) != before:
            raise ValueError("denial changed saved or funding facts")
        q.execute("failure_after_composer_rolls_back", BASE + "SET LOCAL ROLE service_role;SELECT " + expression("admit") + ";DO $$ BEGIN RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='ZX701';END $$;COMMIT;", "ZX701")
        if q.execute("rollback_exact_image", PROJECTION) != before:
            raise ValueError("failed composer changed durable facts")
        admitted = json.loads(call("commit_actual_admission", "admit"))
        if admitted["outcome"] != "admitted" or admitted["authority"] != "none":
            raise ValueError("exact admission observation required")
        if args.current_verification:
            verification_current_cases(q, facts, "admitted")
        original = q.execute("original_admitted_image", FUNDING)
        if args.partial_recovery:
            partial_recovery_cases(q, facts)
        if args.contradictory_recovery:
            contradictory_recovery_cases(q, facts)
        identity_denials("admitted")
        wrong = list(facts)
        wrong[5] += " "
        call("retained_verification_bytes_must_match", "admit", wrong, expected="22023")
        q.execute("commit_policy_revocation", "BEGIN;UPDATE internal.initial_cpm_photo_profile_eligibility SET state='revoked';UPDATE internal.initial_preparation_backend_eligibility SET state='revoked';UPDATE internal.initial_cpm_photo_write_policies SET state='revoked';COMMIT;")
        for op in ["read", "admit"]:
            if json.loads(call("retained_" + op + "_after_revocation", op)) != admitted:
                raise ValueError("retained observation changed")
        if json.loads(call("retained_begin_stays_held", "begin"))["outcome"] != "held":
            raise ValueError("retained start repeated")
        if q.execute("retained_original_funding_unchanged", FUNDING) != original:
            raise ValueError("retained recovery changed funding or verification")
        cancellation_cases(q)
        for op in ["read", "begin", "admit"]:
            call("cancelled_" + op + "_denied", op, expected="55000")
        q.execute("disable_fixture_gate", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
        q.record["wall_seconds"] = time.monotonic() - started
        q.finish()
        print("PASS CPM bridge identity and retained recovery contract", flush=True)
        return 0
    except Exception as error:
        if actor is not None:
            actor.close()
        if q is not None:
            q.record.update(error_category=type(error).__name__, wall_seconds=time.monotonic() - started)
            q.save()
            try:
                q.execute("restore_disabled_gate", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            except Exception:
                q.record["gate_restore_failed"] = True
                q.save()
        print("FAIL CPM bridge contract: " + type(error).__name__, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

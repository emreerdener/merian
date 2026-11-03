"""Owned local two-session CPM eligibility lock orders; no hosted/provider IO.

The stage and full admission remain in one transaction. Trusted eligibility
administration is a separate peer transaction, never mixed into admission.
"""
import argparse
import json
import re
import time
from pathlib import Path

from initial_atomic_admission_test_support import Qualification, ROOT
from initial_atomic_admission_sessions import Session, BASE
from initial_cpm_atomic_admission_committed import FIXTURE

STAGE = """
DO $$ DECLARE s internal.initial_preparation_admission_staging; BEGIN
 PERFORM internal.create_initial_admission_stage(owner_id,scan_id,assignment_digest,
  (SELECT evidence FROM cpm_admission_verified)) FROM internal.initial_analysis_preparation_intents
  WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging;
 PERFORM set_config('merian.initial_admission_stage',s.stage_token::TEXT,TRUE);
 PERFORM set_config('merian.initial_preparation_funding',s.owner_id::TEXT||':'||s.scan_id::TEXT,TRUE);
 PERFORM set_config('merian.initial_analysis_admission',s.owner_id::TEXT||':'||s.scan_id::TEXT,TRUE);
END $$;
"""
FINISH = """
DO $$ DECLARE s internal.initial_preparation_admission_staging; BEGIN
 SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging;
 PERFORM * FROM public.reserve_identification_quota(s.owner_id,'scan_identification',s.scan_id,
  repeat('a',64),s.scan_id,FALSE,3,FALSE,'vision_compat_v1','google_gemini',6);
 PERFORM internal.materialize_initial_admission(s.scan_id);
 PERFORM internal.freeze_initial_admission_ledger(s.scan_id);
 PERFORM internal.begin_initial_admission_consumption(s.scan_id);
 PERFORM internal.finish_initial_admission(s.scan_id);
END $$;SET CONSTRAINTS ALL IMMEDIATE;
"""
RELATIONS = ["internal.initial_analysis_preparation_intents", "internal.initial_cpm_photo_role_mapping",
             "internal.initial_cpm_photo_capacity_reservations", "internal.initial_cpm_photo_write_attempts",
             "internal.initial_cpm_photo_write_closures", "internal.initial_preparation_admission_staging",
             "internal.initial_preparation_admission_writes", "internal.initial_preparation_admission_receipts",
             "internal.initial_analysis_submissions", "internal.initial_analysis_admissions",
             "internal.initial_analysis_lifecycle_fences", "internal.ai_quota_reservations",
             "internal.ai_quota_reservation_counters", "internal.ai_quota_counters",
             "internal.complimentary_scan_usage", "internal.identification_provider_attempts", "public.users",
             "internal.initial_preparation_source_registry", "internal.initial_preparation_source_fences",
             "internal.initial_analysis_operation_fences", "internal.initial_cpm_photo_profile_eligibility",
             "internal.initial_preparation_backend_eligibility", "internal.initial_cpm_photo_write_policies"]
PROJECTION = "SELECT jsonb_build_array(" + ",".join(
    "(SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::TEXT) FROM " + r + " t)" for r in RELATIONS) + ");"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--evidence-directory", required=True)
    parser.add_argument("--replay-manifest", required=True)
    args = parser.parse_args()
    q = None
    sessions = []
    started = time.monotonic()
    try:
        q = Qualification(args.container, args.evidence_directory, "cpm-policy-orders", args.replay_manifest)
        for path in [Path(__file__).resolve(), FIXTURE,
                     Path(__file__).with_name("initial_cpm_atomic_admission_committed.py")]:
            q.record["source_manifest"][str(path.relative_to(ROOT))] = q.digest(path)
        q.record["scope"] = "Local synthetic three-backend schedules: stage holds eligibility until complete admission rollback; peer update first forces NOWAIT refusal. No elapsed expiry, committed peer revocation, hosted or app qualification."
        for name in ["admission", "policy_peer", "observer"]:
            sessions.append(Session(q, name, statement_seconds=45, marker_seconds=55))
        actor, peer, observer = sessions
        if len({s.pid for s in sessions}) != 3:
            raise ValueError("three distinct backend sessions required")
        source = FIXTURE.read_text()
        marker = "SAVEPOINT cpm_positive_admission;"
        if source.count(marker) != 1:
            raise ValueError("unique pending verified fixture boundary required")
        output = "\n".join(actor.run("commit_pending_verified_fixture", source.split(marker)[0] + "SELECT * FROM extensions.finish();COMMIT;"))
        if (re.findall(r"^ok ([0-9]+) - .*$", output, re.M) != [str(i) for i in range(1, 133)]
                or re.findall(r"^1\.\.([0-9]+)$", output, re.M) != ["132"]
                or re.search(r"^not ok|#\s*(?:SKIP|TODO)", output, re.M | re.I)):
            raise ValueError("complete unskipped pending fixture required")
        q.record["fixture_assertions"] = 132
        baseline = observer.run("baseline", PROJECTION)
        for kind, table in [("profile", "internal.initial_cpm_photo_profile_eligibility"),
                            ("backend", "internal.initial_preparation_backend_eligibility"),
                            ("write", "internal.initial_cpm_photo_write_policies")]:
            actor.run(kind + "_stage_first", BASE + "SET CONSTRAINTS ALL DEFERRED;" + STAGE)
            peer.start(kind + "_peer_revocation_waits", "BEGIN;UPDATE " + table + " SET state='revoked';")
            blocked = False
            end = time.monotonic() + 5
            while time.monotonic() < end:
                if observer.run(kind + "_observe_blocker", f"SELECT {actor.pid}=ANY(pg_blocking_pids({peer.pid}));") == ["t"]:
                    blocked = True
                    break
                time.sleep(0.05)
            if not blocked:
                raise ValueError("peer revocation did not wait for stage")
            actor.run(kind + "_complete_admission_under_locked_eligibility", FINISH)
            if observer.run(kind + "_peer_still_blocked_after_completion", f"SELECT {actor.pid}=ANY(pg_blocking_pids({peer.pid}));") != ["t"]:
                raise ValueError("eligibility lock released before transaction ended")
            actor.run(kind + "_rollback_admission", "ROLLBACK;")
            peer.finish()
            peer.run(kind + "_rollback_revocation", "ROLLBACK;")
            if observer.run(kind + "_stage_first_restored", PROJECTION) != baseline:
                raise ValueError("stage-first schedule changed original data")
            peer.run(kind + "_peer_first", "BEGIN;UPDATE " + table + " SET state='revoked';")
            denied = """
DO $$ DECLARE denied BOOLEAN:=FALSE; BEGIN
 BEGIN
  PERFORM internal.create_initial_admission_stage(owner_id,scan_id,assignment_digest,
   (SELECT evidence FROM cpm_admission_verified)) FROM internal.initial_analysis_preparation_intents
   WHERE scan_id='00000000-0000-4000-8000-00000000f101';
 EXCEPTION WHEN lock_not_available THEN denied:=TRUE; END;
 IF NOT denied THEN RAISE EXCEPTION USING ERRCODE='ZX630'; END IF;
END $$;
"""
            actor.run(kind + "_peer_first_refuses_before_funding", BASE + "SET CONSTRAINTS ALL DEFERRED;" + denied + "SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;")
            peer.run(kind + "_peer_first_rollback", "ROLLBACK;")
            if observer.run(kind + "_peer_first_restored", PROJECTION) != baseline:
                raise ValueError("peer-first refusal changed original data")
        for session in sessions:
            session.close()
        sessions = []
        q.execute("disable_synthetic_fixture_rollout", "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
        q.record["wall_seconds"] = time.monotonic() - started
        q.finish()
        print("PASS six CPM eligibility ordering schedules", flush=True)
        return 0
    except Exception as error:
        # Release admission locks first, including when the peer is waiting.
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
        print("FAIL CPM eligibility orders: " + type(error).__name__, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

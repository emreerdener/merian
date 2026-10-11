#!/usr/bin/env python3
"""Qualify dormant source locks in a fresh, explicitly disposable local database.

Uses synthetic installation catalogs only. Leaves them revoked and the rollout
closed; reset this disposable database before another suite or run. No hosted
DSN, runtime, storage request or provider invocation is supported.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

from test_initial_saved_assignment_contention import Session, literal

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disposable-container", required=True)
    args = parser.parse_args()
    container = args.disposable_container
    assert container.startswith("supabase_db_") and all(c.isalnum() or c in "_-" for c in container)
    context = json.loads(subprocess.check_output(["docker", "context", "inspect"], text=True))[0]
    assert (os.environ.get("DOCKER_HOST") or context["Endpoints"]["docker"]["Host"]).startswith("unix://")
    info = json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
    assert info["HostConfig"]["PortBindings"]["5432/tcp"]
    sessions = [Session(container) for _ in range(3)]
    admin, first, second = sessions
    owners = [str(uuid.uuid4()) for _ in range(3)]
    initialized = False
    catalog = False
    fixture = json.loads((ROOT / "services/supabase/functions/_shared/initialAnalysis/fixtures/media-lifecycle-v2.json").read_text())
    candidate = literal(json.dumps(fixture["valid"][2]["candidate"], ensure_ascii=False, sort_keys=True, separators=(",", ":")))

    def create(scan, owner=owners[0]):
        return "SELECT public.create_initial_preparation_intent(" + literal(owner) + "," + literal(scan) + "," + candidate + ")->>'outcome';"

    def cancel(scan):
        return "SELECT public.cancel_initial_analysis(" + literal(owners[0]) + "," + literal(scan) + ")->>'dispatch';"

    def wait_for(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.run("SELECT " + str(blocker.pid) + "=ANY(pg_blocking_pids(" + str(waiter.pid) + "));") == ["t"]:
                return
            time.sleep(0.02)
        raise AssertionError("expected real lock wait was not observed")

    def successful(lines):
        assert not any("ERROR:" in line or "FATAL:" in line for line in lines), lines

    try:
        assert admin.run("SELECT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout;") == ["f"]
        assert admin.run("SELECT count(*) FROM internal.initial_preparation_profiles;") == ["0"], "fresh disposable database required"
        tests = (ROOT / "services/supabase/tests/initial_media_source_lifecycle.sql").read_text()
        helper = tests.split("CREATE FUNCTION pg_temp.admission_owner", 1)[1].split("CREATE TEMP TABLE media_vectors", 1)[0]
        vector = tests.split("CREATE TEMP TABLE media_vectors", 1)[1].split("SELECT extensions.is", 1)[0]
        install = tests.split("-- Synthetic transaction-local installation is not storage/runtime qualification.\n", 1)[1].split("CREATE TEMP TABLE saved_media", 1)[0]
        admin.run("CREATE FUNCTION pg_temp.admission_owner" + helper)
        admin.run("CREATE TEMP TABLE media_vectors" + vector)
        admin.run("BEGIN;" + "".join("SELECT pg_temp.admission_owner(" + literal(o) + ");" for o in owners) + "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE; COMMIT;")
        initialized = True
        admin.run("BEGIN;" + install + "COMMIT;")
        catalog = True
        for s in sessions:
            s.run("SELECT set_config('request.jwt.claim.role','service_role',FALSE);")
        targets = [
            ("selector", "internal.initial_preparation_current_selection", "input_profile='multimodal_audio_v1'"),
            ("profile eligibility", "internal.initial_preparation_profile_eligibility", "profile_digest=" + literal(fixture["valid"][2]["profile_digest"])),
            ("backend eligibility", "internal.initial_preparation_backend_eligibility", "generation='00000000-0000-4000-8000-00000000fb01'"),
        ]
        for label, table, where in targets:
            scan = str(uuid.uuid4())
            second.run("BEGIN; SELECT 1 FROM " + table + " WHERE " + where + " FOR UPDATE;")
            first.run("BEGIN;")
            first.run(create(scan), error="55P03")
            first.run("ROLLBACK;")
            second.run("ROLLBACK;")
            assert admin.run("SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id=" + literal(scan) + ";") == ["0"]
            first.run("BEGIN;" + create(scan))
            second.run("BEGIN;")
            second.run("SELECT 1 FROM " + table + " WHERE " + where + " FOR UPDATE NOWAIT;", error="55P03")
            second.run("ROLLBACK;")
            first.run("ROLLBACK;")
            print("PASS opposed catalog locks:", label, flush=True)

        # Absence is not a lock: an uncommitted newly inserted current row must
        # not make a missing selector pass its first-acquisition FOUND check.
        generation = admin.run("DELETE FROM internal.initial_preparation_current_selection WHERE input_profile='multimodal_audio_v1' RETURNING generation;")[-1]
        second.run("BEGIN; INSERT INTO internal.initial_preparation_current_selection VALUES('multimodal_audio_v1'," + literal(generation) + ");")
        missing = str(uuid.uuid4())
        first.run(create(missing), error="initial_analysis_preparation_unavailable")
        second.run("COMMIT;")
        assert admin.run("SELECT count(*) FROM internal.initial_analysis_operation_fences WHERE scan_id=" + literal(missing) + ";") == ["0"]
        print("PASS missing selector concurrent insertion leaves no claim", flush=True)

        for creation_first in [True, False]:
            scan = str(uuid.uuid4())
            winner = create(scan) if creation_first else cancel(scan)
            loser = cancel(scan) if creation_first else create(scan)
            first.run("BEGIN;" + winner)
            second.run("BEGIN;")
            pending = second.start(loser)
            wait_for(first, second)
            first.run("COMMIT;")
            result = second.finish(pending)
            if creation_first:
                successful(result)
                assert "dispatch_prevented" in result, result
                second.run("COMMIT;")
            else:
                assert any("initial_analysis_cancelled" in line for line in result), result
                second.run("ROLLBACK;")
            assert admin.run("SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=" + literal(scan) + " AND NOT retired;") == ["0"]
            print("PASS creation/C1 order:", creation_first, flush=True)

        # Pre-row scan erasure takes the same owner and operation locks. The
        # raw writer's documented NOWAIT guard fails fast if creation won.
        for creation_first in [True, False]:
            scan = str(uuid.uuid4())
            tombstone = "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES(" + literal(scan) + "," + literal(owners[0]) + ",clock_timestamp());"
            if creation_first:
                first.run("BEGIN;" + create(scan))
                second.run("BEGIN;")
                second.run(tombstone, error="55P03")
                second.run("ROLLBACK;")
                first.run("COMMIT;")
                second.run(tombstone)
            else:
                first.run("BEGIN;" + tombstone)
                second.run("BEGIN;")
                pending = second.start(create(scan))
                wait_for(first, second)
                first.run("COMMIT;")
                result = second.finish(pending)
                assert any("initial_analysis_deleted" in line for line in result), result
                second.run("ROLLBACK;")
            assert admin.run("SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=" + literal(scan) + " AND NOT retired;") == ["0"]
            print("PASS creation/pre-row scan erasure order:", creation_first, flush=True)

        for operation in ["supported tombstone", "raw owner deletion"]:
            for creation_first in [True, False]:
                owner = str(uuid.uuid4())
                owners.append(owner)
                admin.run("SELECT pg_temp.admission_owner(" + literal(owner) + ");")
                scan = str(uuid.uuid4())
                erase = ("SELECT public.apply_user_tombstone(" + literal(owner) + ");" if operation == "supported tombstone" else "DELETE FROM public.users WHERE id=" + literal(owner) + ";")
                first.run("BEGIN;" + (create(scan, owner) if creation_first else erase))
                second.run("BEGIN;")
                pending = second.start(erase if creation_first else create(scan, owner))
                wait_for(first, second)
                first.run("COMMIT;")
                result = second.finish(pending)
                if creation_first:
                    successful(result)
                    second.run("COMMIT;")
                else:
                    assert any("initial_analysis_owner_unavailable" in line or "initial_analysis_deleted" in line for line in result), result
                    second.run("ROLLBACK;")
                assert admin.run("SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id=" + literal(scan) + ";") == ["0"]
                assert admin.run("SELECT count(*) FROM internal.initial_preparation_source_registry WHERE scan_id=" + literal(scan) + " AND NOT retired;") == ["0"]
                print("PASS creation/account erasure order:", operation, creation_first, flush=True)

        expiring = str(uuid.uuid4())
        admin.run(create(expiring))
        admin.run("BEGIN; ALTER TABLE internal.initial_analysis_preparation_intents DISABLE TRIGGER guard_initial_preparation_storage; UPDATE internal.initial_analysis_preparation_intents SET created_at=statement_timestamp()-INTERVAL '298 seconds',expires_at=statement_timestamp()+INTERVAL '2 seconds' WHERE scan_id=" + literal(expiring) + "; SET CONSTRAINTS ALL IMMEDIATE; ALTER TABLE internal.initial_analysis_preparation_intents ENABLE TRIGGER guard_initial_preparation_storage; COMMIT;")
        second.run("BEGIN; SELECT pg_advisory_xact_lock(hashtextextended(" + literal("merian-scan-ingestion:" + expiring) + ",0::BIGINT));")
        first.run("BEGIN;")
        pending = first.start(create(expiring))
        wait_for(second, first)
        while admin.run("SELECT clock_timestamp()>=expires_at FROM internal.initial_analysis_preparation_intents WHERE scan_id=" + literal(expiring) + ";") != ["t"]:
            time.sleep(0.02)
        second.run("ROLLBACK;")
        result = first.finish(pending)
        successful(result)
        assert "expired" in result, result
        first.run("COMMIT;")
        print("PASS exact original expiry after actual operation lock wait", flush=True)

        scan = str(uuid.uuid4())
        first.run("BEGIN;" + create(scan))
        second.run("BEGIN;")
        pending = second.start(create(scan, owners[1]))
        wait_for(first, second)
        first.run("COMMIT;")
        result = second.finish(pending)
        assert any("initial_analysis_identity_conflict" in line for line in result), result
        second.run("ROLLBACK;")
        assert admin.run("SELECT count(*) FROM internal.initial_analysis_preparation_intents WHERE scan_id=" + literal(scan) + ";") == ["1"]
        print("PASS cross-owner no-row allocation collision", flush=True)
        admin.run(cancel(scan))
        object_id = admin.run("SELECT object_id FROM internal.initial_preparation_source_registry WHERE scan_id=" + literal(scan) + ";")[-1]
        # Existing retired objects do not serialize fresh work for another owner.
        first.run("BEGIN; SELECT 1 FROM internal.initial_preparation_source_registry WHERE object_id=" + literal(object_id) + " FOR UPDATE;")
        second.run("BEGIN;" + create(str(uuid.uuid4()), owners[1]) + "ROLLBACK;")
        claimed = json.loads(second.run("SELECT public.claim_initial_preparation_source_erasure();")[-1])
        assert claimed.get("object", {}).get("object_id") != object_id
        first.run("ROLLBACK;")
        print("PASS cleanup SKIP LOCKED and independent-owner allocation", flush=True)
    finally:
        for s in sessions:
            if s.process.poll() is None:
                if s.pending is not None:
                    s.finish(s.pending)
                s.run("ROLLBACK;")
        if initialized:
            admin.run("UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;")
            if catalog:
                admin.run("DELETE FROM internal.initial_preparation_current_selection; UPDATE internal.initial_preparation_profile_eligibility SET state='revoked' WHERE state='eligible'; UPDATE internal.initial_preparation_backend_eligibility SET state='revoked' WHERE state='eligible';")
            admin.run("BEGIN; DELETE FROM public.users WHERE id IN (" + ",".join(map(literal, owners)) + "); DELETE FROM auth.users WHERE id IN (" + ",".join(map(literal, owners)) + "); COMMIT;")
        for s in sessions:
            s.close()


if __name__ == "__main__":
    main()

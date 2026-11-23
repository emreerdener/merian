"""Synthetic staging issuance/account-intake races on a named disposable DB.

No object I/O, hosted state, credentials, or native validation. Both committed
orders are observed through independent PostgreSQL sessions, not timed sleeps.
"""
import argparse
import json
from pathlib import Path
import re
import time
import uuid

from initial_atomic_admission_sessions import Session


class Evidence:
    def __init__(self, container, path):
        if not re.fullmatch(r"supabase_db_merian-capture-focus-[a-z0-9]+", container):
            raise ValueError("explicit Capture disposable container required")
        self.command = ["docker", "exec", "-i", container, "psql", "-X", "-qAt",
                        "-U", "postgres", "-d", "postgres", "-v", "VERBOSITY=verbose"]
        self.path = Path(path)
        self.record = {"passed": False, "scope": __doc__}

    def save(self):
        self.path.write_text(json.dumps(self.record, indent=2) + "\n")


ROLE = "SELECT set_config('request.jwt.claim.role','service_role',true);"


def blocked(observer, waiter, owner):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        if observer.run("exact_wait_observed", f"SELECT {owner.pid}=ANY(pg_blocking_pids({waiter.pid}));") == ["t"]:
            return
        time.sleep(.02)
    raise AssertionError("expected exact blocker absent")


def run(evidence):
    sessions = [Session(evidence, name) for name in ["signer", "deletion", "observer"]]
    signer, deletion, observer = sessions
    owners = []
    jobs = []
    try:
        for order in ["signer", "deletion"]:
            owner = str(uuid.uuid4())
            owners.append(owner)
            key = f"staging/{owner}/race.webp"
            observer.run("create_synthetic_owner", f"INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES('{owner}','authenticated','authenticated','{{}}','{{}}',now(),now());")
            registration = f"SELECT public.register_capture_upload_capabilities('{owner}',repeat('a',64),jsonb_build_array(jsonb_build_object('object_key','{key}','expires_at',clock_timestamp()+interval '1 hour','scan_id',NULL,'asset_id',NULL,'session_id',NULL)));"
            intake = f"SELECT * FROM public.request_account_deletion('{owner}');"
            if order == "signer":
                signer.run("issuance_before_intake", "BEGIN;" + ROLE + registration)
                deletion.start("intake_waits_for_issuance", "BEGIN;" + ROLE + intake)
                blocked(observer, deletion, signer)
                signer.run("commit_issuance", "COMMIT;")
                deletion.finish()
                deletion.run("commit_intake", "COMMIT;")
                observer.run("issued_capability_is_retired", f"DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM internal.capture_object_authorities WHERE owner_id='{owner}' AND retired_at IS NOT NULL) THEN RAISE EXCEPTION 'missing retirement'; END IF; END $$;")
            else:
                deletion.run("intake_before_issuance", "BEGIN;" + ROLE + intake)
                deny = f"DO $$ BEGIN BEGIN PERFORM public.register_capture_upload_capabilities('{owner}',repeat('a',64),jsonb_build_array(jsonb_build_object('object_key','{key}','expires_at',clock_timestamp()+interval '1 hour','scan_id',NULL,'asset_id',NULL,'session_id',NULL))); RAISE EXCEPTION 'unexpected issuance'; EXCEPTION WHEN SQLSTATE '55000' THEN IF SQLERRM <> 'capture_owner_unavailable' THEN RAISE; END IF; END; END $$;"
                signer.start("issuance_waits_for_intake", "BEGIN;" + ROLE + deny)
                blocked(observer, signer, deletion)
                deletion.run("commit_prior_intake", "COMMIT;")
                signer.finish()
                signer.run("commit_denial", "COMMIT;")
            observer.run("no_live_authority_after_intake", f"DO $$ BEGIN IF EXISTS(SELECT 1 FROM internal.capture_object_authorities WHERE owner_id='{owner}' AND retired_at IS NULL) THEN RAISE EXCEPTION 'live authority'; END IF; END $$;")
            jobs.extend(observer.run("remember_synthetic_job", f"SELECT id FROM internal.account_deletion_jobs WHERE user_id='{owner}';"))

        # Reproduce the cleanup lock order, then run the actual tombstone owner
        # while a real idempotent intake retries its job upsert. The retry must
        # not hold users while waiting for the job.
        owner = owners[0]
        deletion.run("cleanup_holds_job", "BEGIN;" + ROLE + f"SELECT id FROM internal.account_deletion_jobs WHERE user_id='{owner}' FOR UPDATE;")
        signer.start("retry_waits_on_cleanup_job", "BEGIN;" + ROLE + f"SELECT * FROM public.request_account_deletion('{owner}');")
        blocked(observer, signer, deletion)
        deletion.run("cleanup_can_tombstone_without_deadlock", f"SELECT public.apply_user_tombstone('{owner}'); COMMIT;")
        signer.finish()
        signer.run("retry_commits_after_cleanup", "COMMIT;")
        evidence.record["passed"] = True
    finally:
        # Release only these harness-owned connections before fixture cleanup.
        for session in sessions[:2]:
            session.close()
        for owner in owners:
            observer.run("remove_synthetic_fixture", f"DELETE FROM public.users WHERE id='{owner}'; DELETE FROM auth.users WHERE id='{owner}'; DELETE FROM internal.capture_object_authorities WHERE owner_id='{owner}'; DELETE FROM internal.account_deletion_jobs WHERE user_id='{owner}';")
        for job in jobs:
            job = str(uuid.UUID(job))
            observer.run("remove_detached_synthetic_job", f"DELETE FROM internal.account_deletion_jobs WHERE id='{job}';")
        observer.close()
        evidence.save()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--evidence", required=True)
    args = parser.parse_args()
    record = Evidence(args.container, args.evidence)
    run(record)
    print(json.dumps({"passed": record.record["passed"], "scope": "synthetic PostgreSQL races only"}))

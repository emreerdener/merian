"""Local-only support for committed atomic-admission qualification.

The caller names a disposable Supabase Docker container and an evidence directory.
Every invocation requires a fresh database. It never provisions, resets, retries,
or connects through a DSN. Dispose/reset the database after the run, including on
failure. Synthetic fixtures are privileged; tested public calls select their real
role explicitly. SQL, generated identities and replies stay in memory.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[3]
STAGE = "services/supabase/tests/initial_atomic_admission_stage.sql"
FIXTURE_END = "-- END ATOMIC ADMISSION COMPOSER FIXTURE\n"


class Qualification:
    def __init__(self, container, evidence_directory, suite, replay_manifest):
        if not re.fullmatch(r"supabase_db_[A-Za-z0-9_-]+", container):
            raise ValueError("named disposable Supabase container required")
        context = json.loads(subprocess.check_output(
            ["docker", "context", "inspect"], text=True))[0]
        engine = os.environ.get("DOCKER_HOST") or context["Endpoints"]["docker"]["Host"]
        if not engine.startswith("unix://"):
            raise ValueError("local Unix Docker required")
        info = json.loads(subprocess.check_output(
            ["docker", "inspect", container], text=True))[0]
        if (info["Name"] != "/" + container or not info["State"]["Running"]
                or not info["HostConfig"]["PortBindings"].get("5432/tcp")):
            raise ValueError("running disposable local database required")
        if shutil.disk_usage(ROOT).free < 20 * 1024**3:
            raise ValueError("20 GiB disk floor")
        self.command = ["docker", "exec", "-i", container, "psql", "-X", "-qAt",
                        "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1",
                        "-v", "VERBOSITY=verbose"]
        directory = Path(evidence_directory).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        self.path = directory / (suite + "-" + uuid.uuid4().hex + ".json")
        migrations = sorted((ROOT / "services/supabase/migrations").glob("*.sql"))
        sources = migrations + [ROOT / STAGE, ROOT / "services/supabase/tests/initial_saved_assignment.sql",
                                ROOT / "services/supabase/functions/_shared/initialAnalysis/fixtures/media-lifecycle-v2.json", Path(__file__),
                                Path(__file__).with_name("test_initial_atomic_admission_c1.py"),
                                Path(__file__).with_name("initial_atomic_admission_sessions.py"),
                                Path(__file__).with_name("initial_atomic_admission_explicit_edges.py"),
                                Path(__file__).with_name("initial_atomic_admission_cross_owner.py"),
                                Path(__file__).with_name("initial_atomic_admission_fixture.py"),
                                Path(__file__).with_name("initial_atomic_admission_recovery_order.py"),
                                Path(__file__).with_name("initial_atomic_admission_counter_images.py"),
                                Path(__file__).with_name("initial_atomic_admission_counter_order.py"),
                                Path(__file__).with_name("initial_atomic_admission_erasure_orders.py"),
                                Path(__file__).with_name("initial_atomic_admission_ghost_order.py"),
                                Path(__file__).with_name("initial_atomic_admission_account_expiry.py"),
                                Path(__file__).with_name("initial_atomic_admission_historical_expiry.py"),
                                Path(__file__).with_name("initial_atomic_admission_resource.py")]
        self.record = {
            "suite": suite, "container": container, "passed": False, "checks": [],
            "scope": "Fresh local synthetic SQL admission/C1 only; no provider, blob IO, installed or device qualification.",
            "source_manifest": {str(p.relative_to(ROOT)): self.digest(p) for p in sources},
        }
        replay_path = Path(replay_manifest).resolve()
        replay = json.loads(replay_path.read_text())
        expected_migrations = {p.name: self.digest(p) for p in migrations}
        if (replay.get("state") != "ready" or replay.get("container") != container
                or container != "supabase_db_" + replay.get("project", "")
                or replay.get("migration_hashes") != expected_migrations):
            raise ValueError("exact owned replay manifest required")
        self.record["replay_manifest_sha256"] = self.digest(replay_path)
        versions = self.execute("exact_migration_versions",
                                "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;").splitlines()
        if versions != [p.name.split("_", 1)[0] for p in migrations]:
            raise ValueError("local migration version mismatch")
        # The trusted replay owner supplies the byte manifest; live versions
        # corroborate that receipt, and are not by themselves byte identity.
        fresh = self.execute("fresh_inactive_database", """
SELECT NOT initial_analysis_lifecycle_enabled
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_profiles)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences)
 AND NOT EXISTS(SELECT 1 FROM internal.initial_preparation_admission_receipts)
 AND NOT EXISTS(SELECT 1 FROM internal.ai_quota_reservations)
 AND NOT EXISTS(SELECT 1 FROM internal.complimentary_scan_usage)
 AND NOT EXISTS(SELECT 1 FROM public.users)
FROM internal.initial_analysis_rollout;
""")
        if fresh != "t":
            raise ValueError("fresh inactive disposable replay required")

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def save(self):
        self.path.write_text(json.dumps(self.record, indent=2) + "\n")

    def execute(self, label, sql, expected=None):
        result = subprocess.run(self.command, input=sql, text=True, capture_output=True)
        codes = re.findall(r"(?:ERROR|FATAL):\s+([0-9A-Z]{5})", result.stderr)
        passed = (result.returncode == 0 and not codes if expected is None
                  else result.returncode != 0 and codes == [expected])
        passed = passed and "WARNING:" not in result.stderr
        check = {"case": label, "exit_code": result.returncode, "sqlstates": codes,
                 "expected": expected, "passed": passed,
                 "error_owners": re.findall(r"PL/pgSQL function ([A-Za-z0-9_.]+)", result.stderr)}
        self.record["checks"].append(check)
        self.save()
        print(("PASS " if passed else "FAIL ") + label, flush=True)
        if not passed:
            raise RuntimeError("SQL qualification failed; see sanitized receipt")
        return result.stdout.strip()

    @staticmethod
    def fixture_prefix(held=True):
        source = (ROOT / STAGE).read_text()
        if source.count(FIXTURE_END) != 1:
            raise ValueError("unique composer fixture marker required")
        fixture = source.split(FIXTURE_END)[0].replace("SELECT extensions.no_plan();", "")
        tripwire = "CREATE FUNCTION pg_temp.funding_tripwire()"
        next_helper = "CREATE FUNCTION pg_temp.source_receipt("
        if fixture.count(tripwire) != 1 or fixture.count(next_helper) != 1:
            raise ValueError("unique funding-tripwire fixture span required")
        start = fixture.index(tripwire)
        end = fixture.index(next_helper)
        if start >= end or fixture.count("\nBEGIN;\n") != 1 or "\nCOMMIT;" in fixture:
            raise ValueError("fixture must provide one open setup transaction")
        fixture = fixture[:start] + fixture[end:]
        owner, foreign = str(uuid.uuid4()), str(uuid.uuid4())
        fixture = fixture.replace("00000000-0000-4000-8000-00000000f001", owner)
        fixture = fixture.replace("00000000-0000-4000-8000-00000000f002", foreign)
        if held:
            fixture += "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';\n"
        return fixture, owner, foreign

    @staticmethod
    def admission_sql(owner, scan):
        return f"""
DO $admit$
DECLARE s internal.initial_preparation_admission_staging;
BEGIN
 PERFORM pg_temp.media_create('{scan}',1);
 PERFORM pg_temp.execution_advance('{scan}',4);
 PERFORM internal.create_initial_admission_stage('{owner}','{scan}');
 SELECT * INTO STRICT s FROM internal.initial_preparation_admission_staging WHERE scan_id='{scan}';
 PERFORM set_config('merian.initial_admission_stage',s.stage_token::TEXT,TRUE);
 PERFORM set_config('merian.initial_preparation_funding','{owner}:{scan}',TRUE);
 PERFORM set_config('merian.initial_analysis_admission','{owner}:{scan}',TRUE);
 PERFORM * FROM public.reserve_identification_quota('{owner}','scan_identification','{scan}',repeat('a',64),'{scan}',FALSE,3,FALSE,'vision_compat_v1','google_gemini',6);
 PERFORM internal.materialize_initial_admission('{scan}');
 PERFORM internal.freeze_initial_admission_ledger('{scan}');
 PERFORM internal.begin_initial_admission_consumption('{scan}');
 PERFORM internal.finish_initial_admission('{scan}');
END; $admit$;
COMMIT;
"""

    def seed(self, count=1, held=True):
        fixture, owner, _ = self.fixture_prefix(held)
        for index in range(count):
            scan = str(uuid.uuid4())
            if index:
                fixture += "BEGIN; SELECT set_config('request.jwt.claim.role','service_role',TRUE);\n"
            fixture += self.admission_sql(owner, scan)
        fixture += "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;"
        self.record["fixture_sha256"] = hashlib.sha256(fixture.encode()).hexdigest()
        self.execute("commit_complete_synthetic_admission", fixture)

    def finish(self):
        if self.execute("activation_remains_disabled", "SELECT NOT initial_analysis_lifecycle_enabled FROM internal.initial_analysis_rollout;") != "t":
            raise ValueError("activation changed")
        for name, digest in self.record["source_manifest"].items():
            if self.digest(ROOT / name) != digest:
                raise ValueError("candidate changed during qualification")
        self.record["passed"] = True
        self.save()

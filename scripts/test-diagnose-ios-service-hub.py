#!/usr/bin/env python3
"""Provenance, privacy and nonqualification boundaries for the host experiment."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / name)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


d = load("diagnose-ios-service-hub.py")
fixtures = load("test-discover-ios27-simulator.py")
ENV = dict(fixtures.HOST, GITHUB_REPOSITORY="emreerdener/merian", GITHUB_WORKSPACE="/workspace",
           IOS_IDENTITY_TEST_OUTCOME="success")


def remote():
    values = {
        f"actions/runs/{d.RUN}": {"id": d.RUN, "head_sha": d.SOURCE, "run_attempt": 1,
                                  "event": "workflow_dispatch", "path": ".github/workflows/ios-build-and-test.yml"},
        f"actions/jobs/{d.BUILD_JOB}": {"id": d.BUILD_JOB, "run_id": d.RUN, "head_sha": d.SOURCE,
                                       "name": "Compile and inventory iOS unit tests",
                                       "run_attempt": 1, "status": "completed", "conclusion": "success"},
    }
    for identifier, name, size, sha in d.ARTIFACTS.values():
        values[f"actions/artifacts/{identifier}"] = {
            "id": identifier, "name": name, "size_in_bytes": size, "expired": False, "digest": "sha256:" + sha,
            "workflow_run": {"id": d.RUN, "head_sha": d.SOURCE, "repository_id": 1174814681,
                             "head_repository_id": 1174814681}}
    return values


def receipt():
    return d.verify_origin(ENV, remote().__getitem__)


class HostDiagnosticTests(unittest.TestCase):
    def test_origin_and_execution_are_distinct_and_never_qualify(self):
        before = dict(ENV)
        r = receipt()
        self.assertEqual(r["product_provenance"]["source_sha"], d.SOURCE)
        self.assertEqual(r["execution_provenance"]["harness_sha"], ENV["GITHUB_SHA"])
        self.assertNotEqual(r["execution_provenance"]["run_id"], d.RUN)
        self.assertIs(r["qualified"], False)
        self.assertIs(r["release_eligible"], False)
        self.assertEqual(ENV, before)

    def test_wrong_execution_context_rejected(self):
        for key, value in (("GITHUB_REPOSITORY", "other/repo"), ("GITHUB_SHA", "bad"),
                           ("GITHUB_SHA", d.SOURCE),
                           ("GITHUB_RUN_ID", str(d.RUN)), ("GITHUB_RUN_ATTEMPT", "0"),
                           ("RUNNER_ENVIRONMENT", "self-hosted")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                d.verify_origin(dict(ENV, **{key: value}), remote().__getitem__)

    def test_wrong_remote_run_or_builder_rejected(self):
        for kind, key, value in (("runs", "head_sha", "b" * 40), ("runs", "run_attempt", 2),
                                 ("runs", "path", "other.yml"), ("runs", "event", "push"),
                                 ("jobs", "conclusion", "failure"), ("jobs", "status", "in_progress"),
                                 ("jobs", "head_sha", "b" * 40), ("jobs", "run_id", 999),
                                 ("jobs", "name", "other job")):
            values = remote()
            values[f"actions/{kind}/{d.RUN if kind == 'runs' else d.BUILD_JOB}"][key] = value
            with self.subTest(kind=kind, key=key), self.assertRaises(ValueError):
                d.verify_origin(ENV, values.__getitem__)

    def test_wrong_artifact_identity_digest_and_expiry_rejected(self):
        for artifact in d.ARTIFACTS.values():
            for key, value in (("id", 1), ("name", "other"), ("size_in_bytes", 1),
                               ("expired", True), ("digest", "sha256:" + "0" * 64)):
                values = remote(); values[f"actions/artifacts/{artifact[0]}"][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    d.verify_origin(ENV, values.__getitem__)
            for key, value in (("id", 1), ("head_sha", "b" * 40), ("repository_id", 1), ("head_repository_id", 1)):
                values = remote(); values[f"actions/artifacts/{artifact[0]}"]["workflow_run"][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    d.verify_origin(ENV, values.__getitem__)

    def test_receipt_cannot_claim_release_or_change_provenance(self):
        mutations = [lambda r: r.update(qualified=True), lambda r: r.update(release_eligible=True),
                     lambda r: r.update(status="passed"), lambda r: r.update(secret="private-sentinel"),
                     lambda r: r["product_provenance"].update(products_sha256="0" * 64),
                     lambda r: r["product_provenance"].update(run_attempt=2),
                     lambda r: r["execution_provenance"].update(run_id=d.RUN),
                     lambda r: r["product_provenance"].update(remote_metadata_verified=False)]
        for mutate in mutations:
            r = receipt(); mutate(r)
            with self.assertRaises(ValueError): d.validate_receipt(r, ENV)

    def input_fixture(self, directory, *, path="tests.xctestproducts/test.bin", **changes):
        product = directory / "ios-unit-products.tar.gz"
        with tarfile.open(product, "w:gz") as archive:
            root = tarfile.TarInfo("tests.xctestproducts"); root.type = tarfile.DIRTYPE; archive.addfile(root)
            item = tarfile.TarInfo(path); item.size = 4; archive.addfile(item, io.BytesIO(b"test"))
        product_hash = d.digest(product)
        plan = {"source_sha": d.SOURCE, "run_id": str(d.RUN), "run_attempt": "1",
                "build_workspace": ENV["GITHUB_WORKSPACE"], "products_sha256": product_hash, **changes}
        plan_path = directory / "ios-unit-plan.json"; plan_path.write_text(json.dumps(plan))
        return d.digest(plan_path), product_hash

    def test_exact_products_unpack_without_spoofing_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory)
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                r = d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertTrue(r["product_provenance"]["unpack_verified"])
                self.assertEqual((directory / "out/tests.xctestproducts/test.bin").read_bytes(), b"test")
                self.assertIs(r["qualified"], False)

    def test_modified_product_rejected_before_unpack(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory)
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                (directory / "ios-unit-products.tar.gz").write_bytes(b"changed")
                with self.assertRaises(ValueError): d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertFalse((directory / "out").exists())

    def test_wrong_source_workspace_and_attempt_rejected(self):
        for field, value in (("source_sha", "b" * 40), ("run_id", "9"), ("run_attempt", "2"),
                             ("build_workspace", "/different")):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); hashes = self.input_fixture(directory, **{field: value})
                with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                    with self.subTest(field=field), self.assertRaises(ValueError):
                        d.verify_inputs(receipt(), directory, directory / "out", ENV)
                    self.assertFalse((directory / "out").exists())

    def test_unsafe_archive_rejected_by_original_unpacker(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory, path="tests.xctestproducts/../escape")
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                with self.assertRaises(ValueError): d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertFalse((directory / "out").exists())

    def test_process_filter_never_retains_raw_paths_or_other_processes(self):
        raw = b"1 0 0 /private-sentinel/DTServiceHub\n2 1 501 /secret/path/unrelated\n3 2 501 secret-command --token secret\n"
        result = d.process_records(raw)
        self.assertEqual(result["records"], [{"role": "DTServiceHub", "pid": 1, "ppid": 0, "numeric_uid": 0}])
        self.assertNotIn("secret", json.dumps(result)); self.assertNotIn("private", json.dumps(result))
        self.assertTrue(d.process_records(b"1 0 0 DTServiceHub\n" * 65)["capped"])
        self.assertEqual(len(d.process_records(b"1 0 0 DTServiceHub\n" * 65)["records"]), 64)

    def test_all_supported_process_roles_are_retained_without_paths(self):
        raw = "\n".join(f"{i + 1} 1 501 /private-sentinel/{name}" for i, name in enumerate(d.ROLES))
        result = d.process_records(raw.encode())
        self.assertEqual({r["role"] for r in result["records"]}, set(d.ROLES.values()))
        self.assertNotIn("private-sentinel", json.dumps(result))

    def identity_fixture(self, directory):
        identity = directory / "identity"; identity.mkdir()
        fixtures.DiscoveryTests().fixture(identity)
        payload = identity / "attachments/identity.txt"
        value = json.loads(payload.read_text()); value["model_identifier"] = "iPhone19,2"
        payload.write_text(json.dumps(value))
        r = receipt(); r["product_provenance"]["unpack_verified"] = True
        return r

    def test_snapshot_retains_only_scoped_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.identity_fixture(directory)
            calls = []
            def probe(args, **bounds):
                calls.append((args, bounds))
                if args[0] == "ps":
                    raw = b"1 0 501 /private-sentinel/DTServiceHub\n2 1 501 /private-sentinel/unrelated\n"
                elif "runtimes" in args:
                    raw = json.dumps({"runtimes": [dict(fixtures.RUNTIME, name="private-sentinel")]}).encode()
                else:
                    raw = json.dumps({"devices": {fixtures.discovery.RUNTIME: [
                        {"udid": fixtures.DEVICE, "state": "Booted", "name": "private-sentinel"},
                        {"udid": "other", "state": "Shutdown", "name": "private-sentinel"}]}}).encode()
                return {"outcome": "passed", "direct_process_reaped": True}, raw
            with patch.object(d, "module", return_value=fixtures.discovery), \
                    patch.object(fixtures.discovery.simulator, "diagnostic_process", side_effect=probe):
                result = d.snapshot(directory, "after_test", dict(ENV, RUNNER_TEMP=temporary))
            self.assertEqual(result["target_runtime"], {"status": "available"})
            self.assertEqual(result["owned_device"], {"status": "observed", "state": "Booted"})
            self.assertIs(type(result["current_uid_is_root"]), bool)
            self.assertIs(type(result["free_mib"]), int)
            self.assertNotIn("private-sentinel", json.dumps(result))
            self.assertNotIn(fixtures.DEVICE, json.dumps(result))
            self.assertEqual(len(calls), 3)
            self.assertTrue(all(bounds == {"capture": "stdout", "limit": 512 * 1024, "timeout": 5}
                                for _, bounds in calls))

    def test_probe_failure_retains_no_partial_or_error_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            for outcome in ("timeout", "oversized", "nonzero"):
                with patch.object(d, "module", return_value=fixtures.discovery), \
                        patch.object(fixtures.discovery.simulator, "diagnostic_process", return_value=(
                            {"outcome": outcome, "direct_process_reaped": True}, b"private-sentinel")):
                    result = d.snapshot(Path(temporary), "after_test", dict(ENV, RUNNER_TEMP=temporary))
                self.assertEqual(result["processes"], {"status": "unavailable"})
                self.assertEqual(result["target_runtime"], {"status": "unavailable"})
                self.assertNotIn("private-sentinel", json.dumps(result))

    def test_before_snapshots_add_no_simulator_client(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.identity_fixture(directory)
            for phase in ("before_prepare", "before_test"):
                with patch.object(d, "module", return_value=fixtures.discovery), \
                        patch.object(fixtures.discovery.simulator, "diagnostic_process", return_value=(
                            {"outcome": "passed", "direct_process_reaped": True}, b"")) as probe:
                    result = d.snapshot(directory, phase, dict(ENV, RUNNER_TEMP=temporary))
                self.assertEqual(probe.call_count, 1)
                self.assertEqual(probe.call_args.args[0][0], "ps")
                self.assertEqual(result["target_runtime"]["status"],
                                 "not_probed" if phase == "before_prepare" else "verified_at_preparation")

    def test_missing_snapshot_never_changes_nonqualification(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); r = self.identity_fixture(directory)
            self.assertFalse((directory / "before_prepare.json").exists())
            result = d.finish(r, directory, ENV)
            self.assertIs(result["qualified"], False)
            self.assertIs(result["release_eligible"], False)

    def test_success_is_execution_observation_not_product_qualification(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); r = self.identity_fixture(directory)
            result = d.finish(r, directory, ENV)
            self.assertEqual(result["status"], "identity_observed")
            self.assertIs(result["qualified"], False); self.assertIs(result["release_eligible"], False)
            self.assertNotIn("methods", result); self.assertFalse((directory / "qualification.json").exists())
            self.assertEqual(result["execution_provenance"]["harness_sha"], ENV["GITHUB_SHA"])

    def test_failed_step_stale_identity_or_wrong_guest_cannot_pass(self):
        for kind in ("failed_step", "stale_identity", "wrong_guest", "skipped", "unverified_products"):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); r = self.identity_fixture(directory); env = dict(ENV)
                if kind == "failed_step": env["IOS_IDENTITY_TEST_OUTCOME"] = "failure"
                if kind == "unverified_products": r["product_provenance"]["unpack_verified"] = False
                if kind in ("stale_identity", "wrong_guest", "skipped"):
                    file, key, value = {"stale_identity": ("preparation.json", "source_sha", d.SOURCE),
                                        "wrong_guest": ("attachments/identity.txt", "model_identifier", "iPhone99,1"),
                                        "skipped": ("summary.json", "skippedTests", 1)}[kind]
                    path = directory / "identity" / file; data = json.loads(path.read_text()); data[key] = value
                    path.write_text(json.dumps(data))
                with self.subTest(kind=kind), self.assertRaises(ValueError): d.finish(r, directory, env)

    def test_workflow_only_consumes_fixed_artifacts_and_runs_one_selector(self):
        path = ROOT / ".github/workflows/ios-runtime-discovery.yml"
        w = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                       "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(path)], text=True))
        job = w["jobs"]["discover"]; steps = job["steps"]
        self.assertEqual(w["permissions"], {"contents": "read", "actions": "read"})
        downloads = [s for s in steps if s.get("uses", "").startswith("actions/download-artifact@")]
        self.assertEqual(len(downloads), 2)
        self.assertEqual({s["with"]["artifact-ids"] for s in downloads}, {v[0] for v in d.ARTIFACTS.values()})
        for step in downloads:
            self.assertEqual(step["with"]["run-id"], d.RUN)
            self.assertEqual(step["with"]["repository"], "emreerdener/merian")
            self.assertEqual(step["with"]["digest-mismatch"], "error")
        commands = "\n".join(s.get("run", "") for s in steps)
        self.assertEqual(commands.count("xcodebuild test-without-building"), 1)
        self.assertEqual(commands.count("-only-testing:"), 1)
        for forbidden in ("build-for-testing", "-skip-testing", "killall", "simctl erase", "GITHUB_SHA=",
                          "GITHUB_RUN_ID=", "GITHUB_RUN_ATTEMPT=", "qualification.json"):
            self.assertNotIn(forbidden, commands)
        self.assertEqual(next(s for s in steps if s.get("id") == "identity-test")["timeout-minutes"], 10)
        self.assertNotIn("environment", job)
        upload = steps[-1]["with"]["path"]
        self.assertNotIn("results.xcresult", upload); self.assertNotIn("diagnostic-products", upload)


if __name__ == "__main__":
    unittest.main()

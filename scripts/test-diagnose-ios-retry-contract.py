#!/usr/bin/env python3
"""Fail closed while testing the synthetic failed-jobs retry experiment."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("probe", ROOT / "scripts/diagnose-ios-retry-contract.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class RetryProbeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / "origin"
        self.env = {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "71", "GITHUB_RUN_ATTEMPT": "1"}
        p.origin(self.directory, self.env)
        self.env.update(PROBE_ORIGIN_ARTIFACT_ID="901", PROBE_ORIGIN_DIGEST=p.digest(self.directory / "origin.json"),
                        PROBE_ORIGIN_ATTEMPT="1", PROBE_ORIGIN_RUN="71", PROBE_ORIGIN_SHA="a" * 40)
        self.origin = p.load_origin(self.directory, self.env)
        self.first = [p.receipt(self.origin, slot, self.env) for slot in (0, 1)]
        self.retry_env = {**self.env, "GITHUB_RUN_ATTEMPT": "2"}
        self.history = self.first + [p.receipt(self.origin, 1, self.retry_env)]

    def test_initial_failure_is_retained_and_not_qualified(self):
        result = p.reconcile(self.origin, self.first, self.env)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["retained_failed_receipts"], 1)
        self.assertIs(result["qualified"], False)
        self.assertIs(result["release_eligible"], False)

    def test_retry_selects_original_success_and_new_success(self):
        self.assertEqual(p.load_origin(self.directory, self.retry_env), self.origin)
        result = p.reconcile(self.origin, self.history, self.retry_env)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["selected"], [{"slot": 0, "execution_attempt": 1, "status": "passed"},
                                              {"slot": 1, "execution_attempt": 2, "status": "passed"}])
        self.assertEqual(result["retained_failed_receipts"], 1)
        self.assertIs(result["qualified"], False)
        self.assertIs(result["release_eligible"], False)

    def test_no_foreign_origin_or_receipt_fields(self):
        for key, value in (("source_sha", "b" * 40), ("run_id", "72"), ("attempt", 2),
                           ("input_sha256", "0" * 64), ("artifact_id", "902"), ("origin_sha256", "0" * 64)):
            rows = copy.deepcopy(self.history); rows[-1]["origin"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.reconcile(self.origin, rows, self.retry_env)
        for key, value in (("qualified", True), ("release_eligible", True), ("qualified", 0),
                           ("slot", 2), ("slot", True), ("execution_attempt", 3), ("execution_attempt", True),
                           ("status", "skipped"), ("unexpected", "field")):
            rows = copy.deepcopy(self.history); rows[-1][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                p.reconcile(self.origin, rows, self.retry_env)

    def test_missing_duplicate_and_repeated_success_are_rejected(self):
        for rows in ([], self.history[1:], self.history[:-1], self.history + [self.history[-1]],
                     self.first + [p.receipt(self.origin, 0, self.retry_env)]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                p.reconcile(self.origin, rows, self.retry_env)

    def test_future_attempt_or_claimed_early_success_cannot_clear_failure(self):
        with self.assertRaises(ValueError): p.reconcile(self.origin, self.history, self.env)
        rows = copy.deepcopy(self.first); rows[1]["status"] = "passed"
        with self.assertRaises(ValueError): p.reconcile(self.origin, rows, self.env)

    def test_changed_execution_or_origin_output_is_rejected(self):
        for key, value in (("GITHUB_SHA", "b" * 40), ("GITHUB_RUN_ID", "72"), ("GITHUB_RUN_ATTEMPT", "3"),
                           ("PROBE_ORIGIN_ATTEMPT", "2"), ("PROBE_ORIGIN_RUN", "72"),
                           ("PROBE_ORIGIN_SHA", "b" * 40), ("PROBE_ORIGIN_DIGEST", "0" * 64),
                           ("PROBE_ORIGIN_ARTIFACT_ID", "")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.load_origin(self.directory, {**self.env, key: value})

    def test_origin_cannot_be_rebuilt_on_retry(self):
        with self.assertRaises(ValueError): p.origin(self.directory, self.retry_env)

    def test_changed_input_symlink_and_duplicate_json_are_rejected(self):
        (self.directory / "input.bin").write_bytes(b"y")
        with self.assertRaises(ValueError): p.load_origin(self.directory, self.env)
        (self.directory / "input.bin").unlink()
        (self.directory / "input.bin").symlink_to("origin.json")
        with self.assertRaises(ValueError): p.load_origin(self.directory, self.env)
        (self.directory / "origin.json").write_text('{"x":1,"x":2}')
        with self.assertRaises(ValueError): p.read(self.directory / "origin.json")

    def test_cli_retains_failed_receipt_and_reconciles_only_retry_union(self):
        root = Path(self.temporary.name)
        receipts = root / "receipts"
        command = [sys.executable, "-B", str(ROOT / "scripts/diagnose-ios-retry-contract.py")]
        for slot, attempt, expected_code in ((0, 1, 0), (1, 1, 1), (1, 2, 0)):
            env = {**self.env, "GITHUB_RUN_ATTEMPT": str(attempt)}
            output = receipts / f"retry-probe-receipt-71-1-{slot}-execution-{attempt}" / "receipt.json"
            result = subprocess.run(command + ["slot", "--origin", str(self.directory), "--slot", str(slot),
                                               "--output", str(output)], env=env, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, expected_code)
            self.assertTrue(output.is_file())
            if slot == 1:
                result_path = root / f"aggregate-{attempt}.json"
                aggregate = subprocess.run(command + ["aggregate", "--origin", str(self.directory),
                    "--receipts", str(receipts), "--output", str(result_path)], env=env,
                    capture_output=True, timeout=10)
                self.assertEqual(aggregate.returncode, expected_code)
                self.assertEqual(p.read(result_path)["retained_failed_receipts"], 1)
        extra = receipts / "unexpected"
        extra.mkdir()
        (extra / "receipt.json").write_text(json.dumps(self.history[-1]))
        result = subprocess.run(command + ["aggregate", "--origin", str(self.directory),
            "--receipts", str(receipts), "--output", str(root / "must-not-exist.json")],
            env=self.retry_env, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((root / "must-not-exist.json").exists())

    def test_probe_does_not_trigger_native_or_release_work(self):
        def yaml(name):
            return json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(ROOT / name)], text=True))
        workflow = yaml(".github/workflows/ios-retry-contract-diagnostic.yml")
        trigger = workflow.get("on", workflow.get("true"))
        self.assertEqual(set(trigger), {"push"})
        self.assertEqual(trigger["push"]["branches"], ["codex/pr152-simulator-diagnostics-20261114"])
        self.assertEqual(set(trigger["push"]["paths"]), {".github/workflows/ios-retry-contract-diagnostic.yml",
                                                          "scripts/diagnose-ios-retry-contract.py"})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(set(workflow["jobs"]), {"origin", "slot", "aggregate"})
        self.assertEqual(workflow["jobs"]["slot"]["strategy"], {"fail-fast": False, "matrix": {"slot": [0, 1]}})
        self.assertEqual(workflow["jobs"]["aggregate"]["if"], "always()")
        for job in workflow["jobs"].values():
            self.assertEqual(job["runs-on"], "ubuntu-latest")
            self.assertEqual(job["timeout-minutes"], 5)
            self.assertNotIn("environment", job)
            for step in job["steps"]:
                self.assertNotIn("continue-on-error", step)
                if step.get("uses", "").startswith("actions/download-artifact@"):
                    self.assertEqual(step["with"]["digest-mismatch"], "error")
        native = yaml(".github/workflows/ios-runtime-discovery.yml")
        native_trigger = native.get("on", native.get("true"))
        self.assertEqual(native_trigger["push"]["paths"], ["scripts/diagnose-ios-service-hub.py"])


if __name__ == "__main__":
    unittest.main()

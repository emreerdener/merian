#!/usr/bin/env python3
"""Fail-closed contracts for non-release candidate identity discovery."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("discovery", ROOT / "scripts/discover-ios27-simulator.py")
discovery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(discovery)
HOST = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", "GITHUB_SHA": "a" * 40,
        "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}
RUNTIME = {"identifier": discovery.RUNTIME, "version": discovery.VERSION, "buildversion": discovery.BUILD,
           "isAvailable": True, "supportedDeviceTypes": [{"identifier": discovery.DEVICE_TYPE}]}
DEVICE = "00000000-0000-4000-8000-000000000001"


class DiscoveryTests(unittest.TestCase):
    def invoke(self, *, inventory=None, env=None, model=b"iPhone99,1\n", outcome="passed", version=b"27.2\n"):
        self.calls = []
        def run(args, *, timeout):
            self.calls.append((args, timeout))
            if args[2:4] == ["list", "runtimes"]:
                return json.dumps({"runtimes": [RUNTIME]} if inventory is None else inventory)
            if args[2] == "create": return DEVICE
            return ""
        def probe(args, **kwargs):
            self.calls.append((args, kwargs))
            return {"outcome": outcome, "direct_process_reaped": True}, {
                "SIMULATOR_RUNTIME_VERSION": version, "SIMULATOR_RUNTIME_BUILD_VERSION": b"24B8117\n",
                "SIMULATOR_MODEL_IDENTIFIER": model}[args[-1]]
        receipt = {"qualified": False, "release_eligible": False}
        discovery.discover(receipt, run=run, probe=probe, env=HOST if env is None else env, machine="arm64")
        return receipt

    def test_observation_is_not_qualification_and_model_is_not_guessed(self):
        receipt = self.invoke()
        self.assertTrue(receipt["identity_observed"])
        self.assertEqual(receipt["observed_environment"]["SIMULATOR_MODEL_IDENTIFIER"], "iPhone99,1")
        self.assertFalse(receipt["qualified"]); self.assertFalse(receipt["release_eligible"])
        self.assertEqual([c[1] for c in self.calls[:4]], [10, 600, 20, 300])
        self.assertTrue(all(c[0][0] == "xcrun" for c in self.calls))
        self.assertTrue(all(c[0][3] == DEVICE and c[1] == {"capture": "stdout", "limit": 64, "timeout": 30}
                            for c in self.calls[4:]))

    def test_invalid_host_or_injection_rejected_before_commands(self):
        for env in ({}, dict(HOST, GITHUB_SHA="bad"), dict(HOST, GITHUB_RUN_ID="0"),
                    dict(HOST, SIMCTL_CHILD_SIMULATOR_MODEL_IDENTIFIER="iPhone99,1"),
                    dict(HOST, RUNNER_ENVIRONMENT="self-hosted")):
            with self.subTest(env=env), self.assertRaises(ValueError): self.invoke(env=env)
            self.assertEqual(self.calls, [])

    def test_missing_wrong_duplicate_or_unsupported_runtime_never_creates_device(self):
        bad = copy.deepcopy(RUNTIME); bad["supportedDeviceTypes"] = []
        for inventory in ([], {}, {"runtimes": []}, {"runtimes": [RUNTIME, RUNTIME]},
                          {"runtimes": [dict(RUNTIME, buildversion="24B0000")]}, {"runtimes": [bad]}):
            with self.subTest(inventory=inventory), self.assertRaises(ValueError): self.invoke(inventory=inventory)
            self.assertEqual(len(self.calls), 1)

    def test_guest_timeout_wrong_version_or_invalid_model_fails(self):
        for args in ({"outcome": "timeout"}, {"version": b"26.5"}, {"model": b"private-sentinel"}, {"model": b"\xff"}):
            with self.subTest(args=args), self.assertRaises(ValueError): self.invoke(**args)

    def fixture(self, directory):
        prepared = self.invoke()
        prepared.update(status="prepared", identity_observed=False)
        prepared.pop("observed_environment")
        prepared.pop("queries")
        case = {"nodeType": "Test Case", "name": "testRecordsBootedGuestIdentity()", "result": "Passed",
                "nodeIdentifier": discovery.CASE,
                "nodeIdentifierURL": "test://com.apple.xcode/merian/merianTests/SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity"}
        node = case
        for kind, name in (("Test Suite", "SimulatorRuntimeIdentityTests"), ("Unit test bundle", "merianTests"), ("Test Plan", "Merian")):
            node = {"nodeType": kind, "name": name, "result": "Passed", "children": [node]}
        tree = {"testNodes": [node], "devices": [{"deviceId": DEVICE, "architecture": "arm64", "osVersion": discovery.VERSION,
                "osBuildNumber": discovery.BUILD, "platform": "iOS Simulator"}],
                "testPlanConfigurations": [{"configurationName": "Test Scheme Action"}]}
        item = {"exportedFileName": "identity.txt", "suggestedHumanReadableName": discovery.ATTACHMENT + ".txt",
                "deviceId": DEVICE, "configurationName": "Test Scheme Action", "isAssociatedWithFailure": False}
        files = {"preparation.json": prepared,
                 "summary.json": {"result": "Passed", "totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0},
                 "tests.json": tree,
                 "attachments/manifest.json": [{"testIdentifier": discovery.CASE, "testIdentifierURL": case["nodeIdentifierURL"], "attachments": [item]}],
                 "attachments/identity.txt": {"runtime_version": discovery.VERSION, "runtime_build": discovery.BUILD, "model_identifier": "iPhone99,1"}}
        (directory / "attachments").mkdir()
        for name, value in files.items(): (directory / name).write_text(json.dumps(value))
        return files

    def verify_fixture(self, mutate=None, env=None):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            files = self.fixture(directory)
            if mutate:
                mutate(files)
                for name, value in files.items(): (directory / name).write_text(json.dumps(value))
            return discovery.verify(directory, env=dict(HOST, IOS_IDENTITY_TEST_OUTCOME="success") if env is None else env)

    def test_xctest_identity_remains_nonqualifying(self):
        result = self.verify_fixture()
        self.assertTrue(result["identity_observed"])
        self.assertFalse(result["qualified"])
        self.assertFalse(result["release_eligible"])
        self.assertEqual(result["observed_environment"]["SIMULATOR_MODEL_IDENTIFIER"], "iPhone99,1")
        self.assertEqual(len(result["files"]), 5)

    def test_stale_source_or_failed_process_rejected(self):
        for key, value in (("GITHUB_SHA", "b" * 40), ("GITHUB_RUN_ID", "124"),
                           ("GITHUB_RUN_ATTEMPT", "2"), ("IOS_IDENTITY_TEST_OUTCOME", "failure")):
            env = dict(HOST, IOS_IDENTITY_TEST_OUTCOME="success"); env[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.verify_fixture(env=env)

    def test_observed_xcode_export_name_is_exact_and_nonqualifying(self):
        name = "merian-simulator-identity_0_A0EBE5AF-9813-4C22-9356-E27AF02FD5DE.json"
        result = self.verify_fixture(lambda f: f["attachments/manifest.json"][0]["attachments"][0].update(
            suggestedHumanReadableName=name))
        self.assertTrue(result["identity_observed"])
        self.assertFalse(result["qualified"])
        self.assertFalse(result["release_eligible"])
        for invalid in (name.replace("_0_", "_1_"), name.replace("_0_", "_00_"),
                        name.replace("A0EBE5AF", "not-uuid"), name.lower(), name + ".txt",
                        "prefix-" + name, name.replace(".json", ".txt"), "../" + name, None):
            with self.subTest(name=invalid), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["attachments/manifest.json"][0]["attachments"][0].update(
                    suggestedHumanReadableName=invalid))

    def test_preparation_failure_or_qualification_claim_rejected(self):
        for key, value in (("status", "passed"), ("qualified", True), ("identity_observed", True),
                           ("release_eligible", True), ("runtime_identifier", "other"), ("phases", [])):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["preparation.json"].update({key: value}))

    def test_skip_extra_failure_or_bool_counts_rejected(self):
        for key, value in (("result", "Failed"), ("totalTestCount", 2), ("passedTests", True),
                           ("failedTests", 1), ("skippedTests", 1)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["summary.json"].update({key: value}))

    def test_wrong_result_device_or_configuration_rejected(self):
        for key, value in (("deviceId", "00000000-0000-4000-8000-000000000002"), ("architecture", "x86_64"),
                           ("osVersion", "26.5"), ("osBuildNumber", "23F77"), ("platform", "iOS")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["tests.json"]["devices"][0].update({key: value}))
        with self.assertRaises(ValueError):
            self.verify_fixture(lambda f: f["tests.json"]["testPlanConfigurations"].append({"configurationName": "Other"}))

    def test_extra_missing_or_nonpassing_result_nodes_rejected(self):
        def case(f): return f["tests.json"]["testNodes"][0]["children"][0]["children"][0]["children"][0]
        for key, value in (("result", "Skipped"), ("nodeIdentifier", "Other/test()"),
                           ("nodeIdentifierURL", "test://com.apple.xcode/merian/other/SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: case(f).update({key: value}))
        with self.assertRaises(ValueError):
            self.verify_fixture(lambda f: f["tests.json"]["testNodes"].append(copy.deepcopy(f["tests.json"]["testNodes"][0])))

    def test_attachment_must_be_single_and_bound(self):
        for key, value in (("deviceId", "other"), ("configurationName", "other"),
                           ("isAssociatedWithFailure", True), ("exportedFileName", "../identity.txt"),
                           ("suggestedHumanReadableName", "other.json")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["attachments/manifest.json"][0]["attachments"][0].update({key: value}))
        for key, value in (("testIdentifier", "Other/test()"), ("testIdentifierURL", "test://other"), ("attachments", [])):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["attachments/manifest.json"][0].update({key: value}))

    def test_payload_identity_and_allowlist_enforced(self):
        for key, value in (("runtime_version", "26.5"), ("runtime_build", "23F77"),
                           ("model_identifier", "private-sentinel"), ("extra", "not-allowed")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f["attachments/identity.txt"].update({key: value}))

    def test_attachment_bounds_duplicate_keys_and_symlinks_rejected(self):
        for value in ('{"runtime_version":"27.2","runtime_version":"27.2"}', "x" * 513):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); self.fixture(directory)
                (directory / "attachments/identity.txt").write_text(value)
                with self.assertRaises(ValueError): discovery.verify(directory, env=dict(HOST, IOS_IDENTITY_TEST_OUTCOME="success"))
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.fixture(directory)
            path = directory / "attachments/identity.txt"; path.unlink(); path.symlink_to(directory / "summary.json")
            with self.assertRaises(ValueError): discovery.verify(directory, env=dict(HOST, IOS_IDENTITY_TEST_OUTCOME="success"))

    def test_malformed_json_types_rejected(self):
        for name in ("preparation.json", "summary.json", "tests.json"):
            for value in (None, [], "x", 7):
                with self.subTest(name=name, value=value), self.assertRaises(ValueError):
                    self.verify_fixture(lambda f: f.update({name: value}))
        for value in ([None], [{"testIdentifier": discovery.CASE, "attachments": "x"}],
                      [{"testIdentifier": discovery.CASE, "attachments": [None]}]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.verify_fixture(lambda f: f.update({"attachments/manifest.json": value}))
        for key in ("devices", "testPlanConfigurations", "testNodes"):
            for value in (None, "x", [None]):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    self.verify_fixture(lambda f: f["tests.json"].update({key: value}))

    def test_malformed_external_evidence_writes_failed_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.fixture(directory)
            (directory / "attachments/manifest.json").write_text("[null]")
            output = directory / "receipt.json"
            result = subprocess.run(["python3", "-B", str(ROOT / "scripts/discover-ios27-simulator.py"),
                                     "--verify-directory", str(directory), "--evidence", str(output)],
                                    env=dict(__import__("os").environ, **HOST, IOS_IDENTITY_TEST_OUTCOME="success"),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn("Traceback", result.stderr)
            receipt = json.loads(output.read_text())
            self.assertEqual(receipt["status"], "failed")
            self.assertFalse(receipt["qualified"]); self.assertFalse(receipt["release_eligible"])

    def test_workflow_is_isolated_bounded_and_never_promotes(self):
        path = ROOT / ".github/workflows/ios-runtime-discovery.yml"
        workflow = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                              "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(path)], text=True))
        self.assertEqual(workflow.get("on", workflow.get("true")),
                         {"push": {"branches": ["codex/pr152-simulator-diagnostics-20261114"]}})
        self.assertEqual(workflow["permissions"], {"contents": "read", "actions": "read"})
        job = workflow["jobs"]["discover"]
        self.assertEqual(job["timeout-minutes"], 70)
        self.assertIs(job["steps"][0]["with"]["persist-credentials"], False)
        self.assertEqual(job["steps"][-1]["if"], "always()")
        self.assertNotIn("environment", job)
        budgets = {step.get("name"): step.get("timeout-minutes") for step in job["steps"]}
        self.assertEqual(budgets["Prepare exact preinstalled runtime on owned device"], 20)
        self.assertEqual(budgets["Observe guest identity inside XCTest"], 10)
        scripts = "\n".join(step.get("run", "") for step in job["steps"])
        self.assertIn("--prepare-only", scripts)
        self.assertIn("diagnose-ios-service-hub.py finish", scripts)
        self.assertNotIn("build-for-testing", scripts)
        self.assertIn("-parallel-testing-enabled NO", scripts)
        self.assertIn("-only-testing:merianTests/SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity", scripts)
        self.assertNotIn("-skip-testing", scripts)
        self.assertNotIn("simctl getenv", scripts)
        self.assertNotIn("continue-on-error", path.read_text())


if __name__ == "__main__": unittest.main()

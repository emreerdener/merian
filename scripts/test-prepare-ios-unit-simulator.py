#!/usr/bin/env python3
"""Portable, side-effect-free tests of hosted simulator qualification."""

import copy
import importlib.util
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("unit_simulator", ROOT / "scripts/prepare-ios-unit-simulator.py")
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)
DEVICE = "00000000-0000-4000-8000-000000000001"
HOST = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}
RUNTIME = {
    "identifier": simulator.RUNTIME, "version": simulator.VERSION,
    "buildversion": simulator.BUILD, "isAvailable": True,
    "supportedDeviceTypes": [{"identifier": simulator.DEVICE_TYPE}],
}


class Runner:
    def __init__(self, inventories=None, observed=None, device=DEVICE):
        self.inventories = list(inventories or [{"runtimes": [copy.deepcopy(RUNTIME)]}])
        self.observed = dict(simulator.EXPECTED_ENVIRONMENT if observed is None else observed)
        self.device = device
        self.commands = []

    def __call__(self, args, *, timeout=60):
        self.commands.append((args, timeout))
        if args[:4] == ["xcrun", "simctl", "list", "runtimes"]:
            item = self.inventories.pop(0) if len(self.inventories) > 1 else self.inventories[0]
            return json.dumps(item)
        if args[:2] == ["xcodebuild", "-downloadPlatform"]:
            return "Requested Apple runtime installed"
        if args == ["xcrun", "simctl", "runtime", "dyld_shared_cache", "update", simulator.RUNTIME]:
            return "Runtime cache ready"
        if args[:3] == ["xcrun", "simctl", "create"]:
            return self.device
        if args[:3] == ["xcrun", "simctl", "bootstatus"]:
            return "Boot completed"
        if args[:3] == ["xcrun", "simctl", "getenv"]:
            return self.observed.get(args[-1], "")
        raise AssertionError(f"Unexpected operation: {args}")


class QualificationTests(unittest.TestCase):
    def prepare(self, runner, **overrides):
        arguments = {"run": runner, "environment": HOST, "machine": "arm64"}
        arguments.update(overrides)
        return simulator.prepare(**arguments)

    def test_preinstalled_exact_runtime_creates_and_reads_back_owned_device(self):
        runner = Runner()
        result = self.prepare(runner)
        self.assertTrue(result["qualified"])
        self.assertEqual(result["simulator_destination"], f"platform=iOS Simulator,id={DEVICE}")
        self.assertEqual(result["observed_environment"], simulator.EXPECTED_ENVIRONMENT)
        self.assertTrue(result["runtime_cache_ready"])
        self.assertFalse(any(c[0][0] == "xcodebuild" for c in runner.commands))
        self.assertEqual(runner.commands[1], (["xcrun", "simctl", "runtime", "dyld_shared_cache",
                                             "update", simulator.RUNTIME], 600))
        self.assertEqual(runner.commands[2][0], ["xcrun", "simctl", "create",
                         "Merian measured unit tests", simulator.DEVICE_TYPE, simulator.RUNTIME])
        self.assertEqual(runner.commands[3][0], ["xcrun", "simctl", "bootstatus", DEVICE, "-b"])
        self.assertEqual([c[0][-1] for c in runner.commands[4:]], list(simulator.EXPECTED_ENVIRONMENT))

    def test_missing_runtime_requests_exact_build_and_rechecks_installed_identity(self):
        runner = Runner([{"runtimes": []}, {"runtimes": [RUNTIME]}])
        self.assertTrue(self.prepare(runner)["qualified"])
        self.assertEqual(runner.commands[1], (["xcodebuild", "-downloadPlatform", "iOS",
                         "-buildVersion", "23F77", "-architectureVariant", "arm64"], 360))
        self.assertEqual(runner.commands[2][0], ["xcrun", "simctl", "list", "runtimes", "--json"])
        self.assertEqual(sum(timeout for _, timeout in runner.commands), 1390)
        self.assertLess(sum(timeout for _, timeout in runner.commands), 25 * 60)

    def test_wrong_or_unavailable_runtime_never_falls_back_to_latest(self):
        for key, value in [("identifier", "com.apple.CoreSimulator.SimRuntime.iOS-27-2"),
                           ("version", "27.2"), ("buildversion", "23F73"),
                           ("isAvailable", False), ("isAvailable", "true")]:
            with self.subTest(key=key):
                runtime = dict(RUNTIME, **{key: value})
                runner = Runner([{"runtimes": [runtime]}])
                with self.assertRaisesRegex(ValueError, "unavailable"):
                    self.prepare(runner)
                self.assertFalse(any(c[0][:3] == ["xcrun", "simctl", "create"] for c in runner.commands))
                self.assertEqual(sum(c[0][0] == "xcodebuild" for c in runner.commands), 1)

    def test_duplicate_exact_runtimes_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.prepare(Runner([{"runtimes": [RUNTIME, RUNTIME]}]))

    def test_malformed_inventory_fails_before_download(self):
        for inventory in [[], {}, {"runtimes": None}, {"runtimes": ["invalid"]}]:
            with self.subTest(inventory=inventory):
                runner = Runner([inventory])
                with self.assertRaisesRegex(ValueError, "Invalid simulator"):
                    self.prepare(runner)
                self.assertEqual(len(runner.commands), 1)

    def test_unsupported_device_type_is_rejected_before_creation(self):
        runner = Runner([{"runtimes": [dict(RUNTIME, supportedDeviceTypes=[])]}])
        with self.assertRaisesRegex(ValueError, "device type"):
            self.prepare(runner)
        self.assertEqual(len(runner.commands), 1)

    def test_each_booted_identity_must_match_and_cannot_be_missing(self):
        for key in simulator.EXPECTED_ENVIRONMENT:
            for value in ["wrong", ""]:
                with self.subTest(key=key, value=value):
                    observed = dict(simulator.EXPECTED_ENVIRONMENT, **{key: value})
                    with self.assertRaisesRegex(ValueError, "Booted simulator identity"):
                        self.prepare(Runner(observed=observed))

    def test_identity_reads_use_owned_device_and_bounded_sequential_queries(self):
        runner = Runner()
        self.prepare(runner)
        queries = [(args, timeout) for args, timeout in runner.commands
                   if args[:3] == ["xcrun", "simctl", "getenv"]]
        self.assertEqual(queries, [(["xcrun", "simctl", "getenv", DEVICE, key], 30)
                                   for key in simulator.EXPECTED_ENVIRONMENT])

    def test_each_identity_timeout_stops_without_retry_and_retains_failed_receipt(self):
        keys = list(simulator.EXPECTED_ENVIRONMENT)
        for index, key in enumerate(keys):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                runner = Runner()
                def timeout_identity(args, **kwargs):
                    if args == ["xcrun", "simctl", "getenv", DEVICE, key]:
                        runner.commands.append((args, kwargs["timeout"]))
                        raise subprocess.TimeoutExpired(args, kwargs["timeout"])
                    return runner(args, **kwargs)
                evidence = Path(directory) / "qualification.json"
                original = simulator.prepare
                with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                        patch.object(simulator, "prepare", side_effect=lambda: original(
                            run=timeout_identity, environment=HOST, machine="arm64")):
                    with self.assertRaises(subprocess.TimeoutExpired):
                        simulator.main()
                queries = [(args, timeout) for args, timeout in runner.commands
                           if args[:3] == ["xcrun", "simctl", "getenv"]]
                self.assertEqual(queries, [(["xcrun", "simctl", "getenv", DEVICE, name], 30)
                                           for name in keys[:index + 1]])
                receipt = json.loads(evidence.read_text())
                self.assertFalse(receipt["qualified"])
                self.assertEqual(receipt["status"], "failed")
                self.assertNotIn("runtime_cache_ready", receipt)
                self.assertNotIn("observed_environment", receipt)
                self.assertIn("timed out after 30 seconds", receipt["failure"])

    def test_local_self_hosted_and_wrong_architecture_are_refused_without_commands(self):
        for environment, machine in [({}, "arm64"), (dict(HOST, RUNNER_ENVIRONMENT="self-hosted"), "arm64"),
                                     (HOST, "x86_64"), (dict(HOST, GITHUB_ACTIONS="false"), "arm64")]:
            with self.subTest(environment=environment, machine=machine):
                runner = Runner()
                with self.assertRaisesRegex(ValueError, "GitHub-hosted"):
                    self.prepare(runner, environment=environment, machine=machine)
                self.assertEqual(runner.commands, [])

    def test_simulator_child_identity_overrides_are_refused(self):
        runner = Runner()
        with self.assertRaisesRegex(ValueError, "injected child"):
            self.prepare(runner, environment=dict(HOST, SIMCTL_CHILD_SIMULATOR_RUNTIME_VERSION="26.5"))
        self.assertEqual(runner.commands, [])

    def test_invalid_created_device_cannot_reach_boot(self):
        for device in ["booted", DEVICE + "\nextra", ""]:
            with self.subTest(device=device):
                runner = Runner(device=device)
                with self.assertRaises(ValueError):
                    self.prepare(runner)
                self.assertEqual(len(runner.commands), 3)

    def test_cache_failure_or_timeout_prevents_device_creation_and_boot(self):
        for failure in [subprocess.CalledProcessError(1, ["xcrun"]),
                        subprocess.TimeoutExpired(["xcrun"], 600)]:
            with self.subTest(failure=type(failure)):
                runner = Runner()
                def fail_cache(args, **kwargs):
                    if args[:4] == ["xcrun", "simctl", "runtime", "dyld_shared_cache"]:
                        runner.commands.append((args, kwargs["timeout"]))
                        raise failure
                    return runner(args, **kwargs)
                with self.assertRaises(type(failure)):
                    self.prepare(fail_cache)
                self.assertEqual(len(runner.commands), 2)
                self.assertFalse(any(c[0][2] in ["create", "bootstatus"] for c in runner.commands))

    def test_command_failures_propagate_without_alternate_destination(self):
        for error in [subprocess.CalledProcessError(1, ["xcrun"]),
                      subprocess.TimeoutExpired(["xcrun"], 60)]:
            with self.subTest(error=type(error)):
                calls = []
                def failed(args, **kwargs):
                    calls.append(args)
                    raise error
                with self.assertRaises(type(error)):
                    self.prepare(failed)
                self.assertEqual(len(calls), 1)

    def test_ci_qualification_matches_unchanged_transport_safety_contract(self):
        source = (ROOT / "apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift").read_text()
        for key, value in simulator.EXPECTED_ENVIRONMENT.items():
            self.assertIn(f'env["{key}"] == "{value}"', source)
        self.assertIn("#if targetEnvironment(simulator) && arch(arm64)", source)
        self.assertIn('NSStringFromClass(receiver) == "merianTests.ScopedMockURLProtocol"', source)

    def test_failure_retains_nonpassing_requirement_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                    patch.object(simulator, "prepare", side_effect=ValueError("runtime mismatch")):
                with self.assertRaisesRegex(ValueError, "runtime mismatch"):
                    simulator.main()
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["status"], "failed")
            self.assertEqual(receipt["required_environment"], simulator.EXPECTED_ENVIRONMENT)
            self.assertEqual(receipt["failure"], "runtime mismatch")

    def test_external_interruption_retains_preparing_not_passed_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                    patch.object(simulator, "prepare", side_effect=KeyboardInterrupt):
                with self.assertRaises(KeyboardInterrupt):
                    simulator.main()
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["status"], "preparing")

    def test_boot_timeout_retains_bounded_progress_without_passing(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            failure = subprocess.TimeoutExpired(["xcrun", "simctl", "bootstatus", DEVICE, "-b"],
                                                300, output=b"x" * 9000 + b"Waiting for boot readiness")
            with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                    patch.object(simulator, "prepare", side_effect=failure):
                with self.assertRaises(subprocess.TimeoutExpired):
                    simulator.main()
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["status"], "failed")
            self.assertEqual(len(receipt["boot_diagnostic_tail"]), 8000)
            self.assertTrue(receipt["boot_diagnostic_tail"].endswith("Waiting for boot readiness"))

    def test_cache_timeout_retains_bounded_progress_without_passing(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            failure = subprocess.TimeoutExpired(
                ["xcrun", "simctl", "runtime", "dyld_shared_cache", "update", simulator.RUNTIME],
                600, output=b"x" * 9000 + b"Preparing runtime cache")
            with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                    patch.object(simulator, "prepare", side_effect=failure):
                with self.assertRaises(subprocess.TimeoutExpired):
                    simulator.main()
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["status"], "failed")
            self.assertEqual(len(receipt["runtime_cache_diagnostic_tail"]), 8000)
            self.assertTrue(receipt["runtime_cache_diagnostic_tail"].endswith("Preparing runtime cache"))
            self.assertNotIn("boot_diagnostic_tail", receipt)


if __name__ == "__main__":
    unittest.main()

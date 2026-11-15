#!/usr/bin/env python3
"""Portable, side-effect-free tests of hosted simulator qualification."""

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, call, patch
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

    def assert_transport_receiver_contract(self, source):
        # Compare the complete admission block, not disconnected substrings that
        # would still pass after adding a third tuple or an unconditional bypass.
        begin, end = "var measuredReceiver = false", "return PinnedPhotoUploadTask(owned: config"
        self.assertEqual(source.count(begin), 1)
        self.assertEqual(source.count(end), 1)
        actual = source.split(begin, 1)[1].split(end, 1)[0]
        expected = '''
        #if DEBUG
        if TestExecutionCoordinator.isRunningTests, let injected = withSessionLock({ storedOverridingSession?.configuration }) {
            config.protocolClasses = injected.protocolClasses
            if let scope = injected.httpAdditionalHeaders?["X-Merian-Test-Scope"] as? String, UUID(uuidString: scope) != nil {
                config.httpAdditionalHeaders = ["X-Merian-Test-Scope": scope]
                #if targetEnvironment(simulator) && arch(arm64)
                let env = ProcessInfo.processInfo.environment
                let matchesReceiverRuntime = (env["SIMULATOR_RUNTIME_VERSION"] == "26.5"
                    && env["SIMULATOR_RUNTIME_BUILD_VERSION"] == "23F77"
                    && env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone18,1")
                    || (env["SIMULATOR_RUNTIME_VERSION"] == "27.2"
                        && env["SIMULATOR_RUNTIME_BUILD_VERSION"] == "24B8117"
                        && env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,2")
                if let classes = config.protocolClasses, classes.count == 1, let receiver = classes.first {
                    measuredReceiver = NSStringFromClass(receiver) == "merianTests.ScopedMockURLProtocol"
                        && Bundle(for: receiver).bundleURL.pathExtension == "xctest"
                        && matchesReceiverRuntime
                }
                #endif
            }
        }
        #endif
        '''
        self.assertEqual(actual.split(), expected.split())
        self.assertIn("var hasPurgedMeasuredTransfer: Bool { measuredReceiver && acknowledgedOwnedSessionEnd }", source)

    def test_ci_runtime_pins_match_exact_debug_receiver_contract(self):
        source = (ROOT / "apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift").read_text()
        self.assert_transport_receiver_contract(source)
        self.assertEqual(simulator.EXPECTED_ENVIRONMENT, {
            "SIMULATOR_RUNTIME_VERSION": "26.5", "SIMULATOR_RUNTIME_BUILD_VERSION": "23F77",
            "SIMULATOR_MODEL_IDENTIFIER": "iPhone18,1"})
        spec = importlib.util.spec_from_file_location("receiver_shards", ROOT / "scripts/ios-unit-shards.py")
        shards = importlib.util.module_from_spec(spec); spec.loader.exec_module(shards)
        self.assertEqual(shards.RUNTIME, {
            "SIMULATOR_RUNTIME_VERSION": "27.2", "SIMULATOR_RUNTIME_BUILD_VERSION": "24B8117",
            "SIMULATOR_MODEL_IDENTIFIER": "iPhone19,2"})

    def test_debug_receiver_contract_rejects_broadened_admission(self):
        source = (ROOT / "apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift").read_text()
        mutations = (
            ('&& env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,2")',
             '&& env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,2") || true'),
            ('&& env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,2")',
             '&& env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,2") || (env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone99,1")'),
            ('if TestExecutionCoordinator.isRunningTests,', 'if true,'),
            ('UUID(uuidString: scope) != nil', 'true'),
            ('#if targetEnvironment(simulator) && arch(arm64)', '#if targetEnvironment(simulator)'),
            ('classes.count == 1', 'classes.count >= 1'),
            ('"merianTests.ScopedMockURLProtocol"', '"OtherReceiver"'),
            ('&& Bundle(for: receiver).bundleURL.pathExtension == "xctest"', ''),
            ('&& matchesReceiverRuntime', '|| matchesReceiverRuntime'),
            ('measuredReceiver && acknowledgedOwnedSessionEnd', 'measuredReceiver || acknowledgedOwnedSessionEnd'),
        )
        for before, after in mutations:
            with self.subTest(before=before):
                self.assertIn(before, source)
                with self.assertRaises(AssertionError):
                    self.assert_transport_receiver_contract(source.replace(before, after))

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


class IdentityProcessTests(unittest.TestCase):
    arguments = ["xcrun", "simctl", "getenv", DEVICE, "SIMULATOR_RUNTIME_VERSION"]

    def test_spawn_probe_is_failure_only_and_never_retries_or_qualifies(self):
        for key in simulator.EXPECTED_ENVIRONMENT:
            for outcome in ("passed", "timeout", "nonzero", "unavailable"):
                runner = Runner()
                failure = simulator.IdentityQueryTimeout(
                    ["xcrun", "simctl", "getenv", DEVICE, key], 30, {"identity_key": key})
                def run(args, **kwargs):
                    value = runner(args, **kwargs)
                    if args[:3] == ["xcrun", "simctl", "getenv"] and args[-1] == key:
                        raise failure
                    return value
                with self.subTest(key=key, outcome=outcome), tempfile.TemporaryDirectory() as directory:
                    evidence = Path(directory) / "qualification.json"
                    original = simulator.prepare
                    with patch.object(simulator, "post_boot_spawn", return_value={"outcome": outcome}) as probe, \
                            patch.object(simulator, "post_boot_device_state", return_value={"outcome": "missing"}) as state, \
                            patch.object(simulator, "prepare", side_effect=lambda: original(
                                run=run, environment=HOST, machine="arm64")), \
                            patch("sys.argv", ["prepare", "--evidence", str(evidence)]):
                        with self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                            simulator.main()
                    self.assertIs(raised.exception, failure)
                    receipt = json.loads(evidence.read_text())
                    self.assertFalse(receipt["qualified"])
                    self.assertEqual(receipt["status"], "failed")
                    self.assertEqual([(p["phase"], p["outcome"]) for p in receipt["phase_diagnostics"]],
                                     [("runtime_cache_update", "passed"), ("bootstatus", "passed")])
                    self.assertTrue(all(p["elapsed_ms"] >= 0 for p in receipt["phase_diagnostics"]))
                    reads = [a[-1] for a, _ in runner.commands if a[:3] == ["xcrun", "simctl", "getenv"]]
                    self.assertEqual(reads, list(simulator.EXPECTED_ENVIRONMENT)[:reads.index(key) + 1])
                    if key == "SIMULATOR_RUNTIME_VERSION":
                        probe.assert_called_once_with(DEVICE)
                        state.assert_called_once_with(DEVICE)
                        self.assertEqual(receipt["identity_query_diagnostics"]["post_boot_spawn"]["outcome"], outcome)
                        self.assertEqual(receipt["identity_query_diagnostics"]["post_probe_device_state"], {"outcome": "missing"})
                    else:
                        probe.assert_not_called()
                        state.assert_not_called()

    def test_success_never_probes_and_phase_evidence_has_no_output(self):
        with patch.object(simulator, "post_boot_spawn") as probe, \
                patch.object(simulator, "post_boot_device_state") as state:
            receipt = simulator.prepare(run=Runner(), environment=HOST, machine="arm64")
        probe.assert_not_called()
        state.assert_not_called()
        self.assertTrue(receipt["qualified"])
        for phase in receipt["phase_diagnostics"]:
            self.assertEqual(set(phase), {"phase", "outcome", "elapsed_ms"})

    def test_spawn_diagnostic_is_scoped_and_uses_bounded_capture(self):
        for code in (0, 1):
            observed = {"outcome": "passed" if code == 0 else "nonzero", "returncode": code,
                        "direct_process_reaped": True}
            with patch.object(simulator, "diagnostic_process", return_value=(observed, b"")) as capture:
                result = simulator.post_boot_spawn(DEVICE)
            capture.assert_called_once_with(["xcrun", "simctl", "spawn", DEVICE, "/usr/bin/true"],
                                            capture="stderr", limit=8192, timeout=10)
            self.assertEqual(result["outcome"], "passed" if code == 0 else "nonzero")
            self.assertEqual(result["returncode"], code)
            self.assertTrue(result["direct_process_reaped"])

    def test_spawn_timeout_reaps_only_direct_process_with_bounded_cleanup(self):
        for reaped in (True, False):
            process = Mock()
            process.poll.return_value = None
            process.wait.side_effect = [-9 if reaped else subprocess.TimeoutExpired(["probe"], 5)]
            with patch.object(simulator.subprocess, "Popen", return_value=process), \
                    patch.object(simulator.os, "set_blocking"), \
                    patch.object(simulator, "SPAWN_DIAGNOSTIC_TIMEOUT", 0):
                result = simulator.post_boot_spawn(DEVICE)
            self.assertEqual(result["outcome"], "timeout")
            self.assertTrue(result["direct_process_running_at_timeout"])
            self.assertEqual(result["direct_process_reaped"], reaped)
            self.assertEqual(process.wait.call_args_list, [call(timeout=5)])
            process.kill.assert_called_once_with()

    def test_null_bootstrap_control_is_bounded_and_not_a_readiness_probe(self):
        observed = {"outcome": "passed", "returncode": 0, "direct_process_reaped": True}
        with patch.object(simulator, "diagnostic_process", return_value=(observed, b"")) as capture:
            result = simulator.post_boot_spawn(DEVICE, standalone=True)
        capture.assert_called_once_with(["xcrun", "simctl", "spawn", "-s", DEVICE, "/usr/bin/true"],
                                        capture="stderr", limit=8192, timeout=10)
        self.assertEqual(result, observed)
        self.assertNotIn("qualified", result)

    def test_null_bootstrap_control_preserves_failure_and_runs_only_after_owned_booted_failure(self):
        baseline_probe = {"outcome": "timeout", "direct_process_reaped": True}
        baseline_state = {"outcome": "observed", "state": "Booted", "direct_process_reaped": True}
        cases = [(True, baseline_probe, baseline_state, True),
                 (True, dict(baseline_probe, outcome="nonzero"), baseline_state, True),
                 (False, baseline_probe, baseline_state, False),
                 (True, dict(baseline_probe, direct_process_reaped=False), baseline_state, False),
                 (True, dict(baseline_probe, outcome="passed"), baseline_state, False),
                 (True, dict(baseline_probe, outcome="unavailable"), baseline_state, False),
                 (True, baseline_probe, dict(baseline_state, state="Shutdown"), False),
                 (True, baseline_probe, dict(baseline_state, outcome="missing"), False),
                 (True, baseline_probe, dict(baseline_state, direct_process_reaped=False), False)]
        for reaped, probe, state, expected in cases:
            for outcome in ("passed", "nonzero", "timeout", "unavailable"):
                runner = Runner()
                failure = simulator.IdentityQueryTimeout(self.arguments, 30, {
                    "identity_key": "SIMULATOR_RUNTIME_VERSION", "direct_process_reaped": reaped})
                def run(args, **kwargs):
                    value = runner(args, **kwargs)
                    if args == self.arguments:
                        raise failure
                    return value
                events = []
                def spawn(device, *, standalone=False):
                    events.append("standalone" if standalone else "regular")
                    return {"outcome": outcome} if standalone else probe
                def snapshot(device):
                    events.append("state")
                    return state
                with self.subTest(reaped=reaped, probe=probe, state=state, outcome=outcome), \
                        patch.object(simulator, "post_boot_spawn", side_effect=spawn) as spawn_mock, \
                        patch.object(simulator, "post_boot_device_state", side_effect=snapshot), \
                        self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                    simulator.prepare(run=run, environment=HOST, machine="arm64")
                self.assertIs(raised.exception, failure)
                self.assertEqual(events, ["regular", "state"] + (["standalone"] if expected else []))
                self.assertEqual(spawn_mock.call_args_list,
                                 [call(DEVICE)] + ([call(DEVICE, standalone=True)] if expected else []))
                self.assertEqual("null_bootstrap_control" in failure.diagnostics, expected)
                if expected:
                    self.assertEqual(failure.diagnostics["null_bootstrap_control"], {"outcome": outcome})
                reads = [a for a, _ in runner.commands if a[:3] == ["xcrun", "simctl", "getenv"]]
                self.assertEqual(reads, [self.arguments])

    def test_probe_launch_error_has_no_raw_error_or_environment(self):
        for error in (OSError, RuntimeError, ValueError):
            with self.subTest(error=error), patch.object(
                    simulator.subprocess, "Popen", side_effect=error("private-sentinel")):
                result = simulator.post_boot_spawn(DEVICE)
            self.assertEqual(result["outcome"], "unavailable")
            self.assertNotIn("private-sentinel", json.dumps(result))

    def test_unexpected_probe_error_preserves_original_identity_timeout_receipt(self):
        runner = Runner()
        failure = simulator.IdentityQueryTimeout(self.arguments, 30,
                                                 {"identity_key": "SIMULATOR_RUNTIME_VERSION"})
        def run(args, **kwargs):
            if args == self.arguments:
                raise failure
            return runner(args, **kwargs)
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            original = simulator.prepare
            with patch.object(simulator.subprocess, "Popen", side_effect=RuntimeError("private-sentinel")), \
                    patch.object(simulator, "prepare", side_effect=lambda: original(
                        run=run, environment=HOST, machine="arm64")), \
                    patch("sys.argv", ["prepare", "--evidence", str(evidence)]):
                with self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                    simulator.main()
            self.assertIs(raised.exception, failure)
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["identity_query_diagnostics"]["post_boot_spawn"]["outcome"], "unavailable")
            self.assertEqual(receipt["identity_query_diagnostics"]["post_probe_device_state"]["outcome"], "unavailable")
            self.assertNotIn("private-sentinel", evidence.read_text())

    def test_phase_failure_retains_only_bounded_metadata_and_stops(self):
        runner = Runner()
        def fail(args, **kwargs):
            if args[:3] == ["xcrun", "simctl", "bootstatus"]:
                raise subprocess.TimeoutExpired(args, 300)
            return runner(args, **kwargs)
        with patch.object(simulator, "post_boot_spawn") as probe, self.assertRaises(subprocess.TimeoutExpired) as raised:
            simulator.prepare(run=fail, environment=HOST, machine="arm64")
        probe.assert_not_called()
        self.assertEqual(raised.exception.phase_diagnostics[-1]["outcome"], "failed")
        self.assertEqual(raised.exception.phase_diagnostics[-1]["phase"], "bootstatus")

    def process(self, raw, *, returncode=0, timeout=False, reap=True, running=True):
        process = Mock()
        process.poll.return_value = None if running else returncode
        process.wait.side_effect = (
            [subprocess.TimeoutExpired(self.arguments, 30),
             returncode if reap else subprocess.TimeoutExpired(self.arguments, 5)]
            if timeout else [returncode])
        def start(arguments, *, stdout):
            self.assertEqual(arguments, self.arguments)
            self.assertNotEqual(stdout, subprocess.PIPE)
            stdout.write(raw)
            stdout.flush()
            return process
        return process, start

    def test_completed_query_requires_zero_exit_and_exact_bounded_output(self):
        for raw in [b"26.5\n", b" 26.5\r\n"]:
            process, start = self.process(raw)
            with patch.object(simulator.subprocess, "Popen", side_effect=start):
                self.assertEqual(simulator.command(self.arguments, timeout=30), "26.5")
            process.wait.assert_called_once_with(timeout=30)
            process.kill.assert_not_called()
        for raw in [b"", b"wrong", b"\xff", b"26.5" + b" " * 61 + b"sentinel"]:
            process, start = self.process(raw)
            with self.subTest(raw=raw), patch.object(simulator.subprocess, "Popen", side_effect=start):
                with self.assertRaises(ValueError):
                    simulator.command(self.arguments, timeout=30)
        process, start = self.process(b"26.5\n", returncode=1)
        with patch.object(simulator.subprocess, "Popen", side_effect=start):
            with self.assertRaises(subprocess.CalledProcessError):
                simulator.command(self.arguments, timeout=30)

    def test_timeout_never_accepts_partial_output_and_cleanup_is_bounded(self):
        for raw, match in [(b"", False), (b"26.5\n", True), (b"private-sentinel", False)]:
            for reap in [True, False]:
                process, start = self.process(raw, timeout=True, reap=reap)
                with self.subTest(raw=raw, reap=reap), patch.object(
                        simulator.subprocess, "Popen", side_effect=start):
                    with self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                        simulator.command(self.arguments, timeout=30)
                diagnostic = raised.exception.diagnostics
                self.assertEqual(diagnostic["partial_output_present"], bool(raw))
                self.assertEqual(diagnostic["partial_output_exact_match"], match)
                self.assertTrue(diagnostic["direct_process_running_at_timeout"])
                self.assertEqual(diagnostic["direct_process_reaped"], reap)
                self.assertEqual(process.wait.call_args_list, [call(timeout=30), call(timeout=5)])
                process.kill.assert_called_once_with()
                self.assertNotIn("private-sentinel", str(raised.exception) + json.dumps(diagnostic))

    def test_exit_racing_timeout_still_fails_without_killing_exited_process(self):
        process, start = self.process(b"26.5\n", timeout=True, running=False)
        with patch.object(simulator.subprocess, "Popen", side_effect=start):
            with self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                simulator.command(self.arguments, timeout=30)
        self.assertFalse(raised.exception.diagnostics["direct_process_running_at_timeout"])
        self.assertEqual(raised.exception.diagnostics["direct_process_returncode_at_timeout"], 0)
        process.kill.assert_not_called()

    def test_timeout_receipt_contains_only_flags_not_raw_output(self):
        process, start = self.process(b"private-sentinel", timeout=True)
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "qualification.json"
            with patch("sys.argv", ["prepare", "--evidence", str(evidence)]), \
                    patch.object(simulator.subprocess, "Popen", side_effect=start), \
                    patch.object(simulator, "prepare", side_effect=lambda: simulator.command(
                        self.arguments, timeout=30)):
                with self.assertRaises(simulator.IdentityQueryTimeout):
                    simulator.main()
            text = evidence.read_text()
            receipt = json.loads(text)
            self.assertFalse(receipt["qualified"])
            self.assertEqual(receipt["status"], "failed")
            self.assertIn("identity_query_diagnostics", receipt)
            self.assertNotIn("private-sentinel", text)
            self.assertNotIn("observed_environment", receipt)

    def test_non_identity_commands_keep_existing_execution_path(self):
        arguments = ["xcrun", "simctl", "bootstatus", DEVICE, "-b"]
        with patch.object(simulator.subprocess, "Popen") as popen, \
                patch.object(simulator.subprocess, "run", return_value=Mock(stdout=" ready\n")) as run:
            self.assertEqual(simulator.command(arguments, timeout=300), "ready")
        popen.assert_not_called()
        run.assert_called_once_with(arguments, check=True, text=True,
                                    stdout=subprocess.PIPE, timeout=300)

    def test_inherited_stdout_can_hold_pipe_but_not_direct_process_wait(self):
        real_popen = subprocess.Popen
        child = ("import pathlib,sys,time; p=pathlib.Path(sys.argv[1]); "
                 "deadline=time.monotonic()+10\n"
                 "while not p.exists() and time.monotonic()<deadline: time.sleep(.01)\n"
                 "pathlib.Path(sys.argv[2]).write_text('done')\n")
        with tempfile.TemporaryDirectory() as directory:
            for use_file in [False, True]:
                release = Path(directory) / (str(use_file) + ".release")
                done = Path(directory) / (str(use_file) + ".done")
                parent = ("import subprocess,sys\n"
                          f"subprocess.Popen([sys.executable,'-c',{child!r},{str(release)!r},{str(done)!r}],"
                          "stdin=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
                          "print('26.5',flush=True)\n")
                processes = []
                def start(arguments, *, stdout):
                    process = real_popen([sys.executable, "-c", parent], stdout=stdout)
                    processes.append(process)
                    return process
                try:
                    if use_file:
                        with patch.object(simulator.subprocess, "Popen", side_effect=start):
                            self.assertEqual(simulator.command(self.arguments, timeout=5), "26.5")
                    else:
                        process = start(self.arguments, stdout=subprocess.PIPE)
                        self.assertEqual(process.wait(timeout=5), 0)
                        with self.assertRaises(subprocess.TimeoutExpired):
                            process.communicate(timeout=.05)
                    self.assertFalse(done.exists(), "Fixture descendant must still hold stdout open")
                finally:
                    release.write_text("release")
                    for process in processes:
                        process.communicate(timeout=5)
                    deadline = time.monotonic() + 5
                    while not done.exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue(done.exists(), "Owned fixture descendant must finish")

    def test_real_direct_process_timeout_is_killed_and_reaped(self):
        real_popen = subprocess.Popen
        processes = []
        def start(arguments, *, stdout):
            process = real_popen([sys.executable, "-c", "import time; time.sleep(10)"], stdout=stdout)
            processes.append(process)
            return process
        with patch.object(simulator.subprocess, "Popen", side_effect=start):
            with self.assertRaises(simulator.IdentityQueryTimeout) as raised:
                simulator.command(self.arguments, timeout=.05)
        self.assertTrue(raised.exception.diagnostics["direct_process_reaped"])
        self.assertIsNotNone(processes[0].poll())


class FailureDiagnosticTests(unittest.TestCase):
    error = (b"An error was encountered processing the command "
             b"(domain=com.apple.CoreSimulator.SimError, code=405):\n"
             b"private-sentinel\nUnderlying error "
             b"(domain=com.apple.SimLaunchHostService.RequestError, code=3):\n"
             b"private-sentinel")

    def inventory(self, state="Booted", **extra):
        return json.dumps({"devices": {simulator.RUNTIME: [
            dict(udid=DEVICE, state=state, name="private-sentinel", **extra)]}}).encode()

    def test_error_identity_retains_only_allowlisted_domains_and_numeric_codes(self):
        result = simulator.diagnostic_error_identity(self.error)
        self.assertEqual(result, {"outcome": "recognized", "errors": [
            {"domain": "com.apple.CoreSimulator.SimError", "code": 405},
            {"domain": "com.apple.SimLaunchHostService.RequestError", "code": 3}]})
        self.assertNotIn("private-sentinel", json.dumps(result))
        self.assertEqual(simulator.diagnostic_error_identity(self.error + b"\n" + self.error), result)

    def test_error_identity_rejects_unknown_malformed_and_oversized_output(self):
        cases = [(b"", "empty"), (b"\xff", "unrecognized"), (b"private-sentinel", "unrecognized"),
                 (self.error.replace(b"com.apple.CoreSimulator.SimError", b"private.sentinel")
                  .split(b"Underlying")[0], "unrecognized"),
                 (b"Underlying error (domain=NSPOSIXErrorDomain, code=123456):", "unrecognized"),
                 (self.error + b" " * simulator.DIAGNOSTIC_ERROR_LIMIT, "oversized")]
        for raw, outcome in cases:
            with self.subTest(outcome=outcome):
                self.assertEqual(simulator.diagnostic_error_identity(raw), {"outcome": outcome})
        self.assertEqual(simulator.diagnostic_error_identity(
            b"Underlying error (domain=NSPOSIXErrorDomain, code=2):"),
            {"outcome": "recognized", "errors": [{"domain": "NSPOSIXErrorDomain", "code": 2}]})

    def test_owned_state_discards_names_paths_and_other_devices(self):
        for state in simulator.DEVICE_STATES:
            raw = json.loads(self.inventory(state, availabilityError="private-sentinel"))
            raw["devices"]["private-runtime"] = [{"udid": "private-device", "state": "private-sentinel"}]
            result = simulator.owned_device_state(json.dumps(raw).encode(), DEVICE.lower())
            self.assertEqual(result, {"outcome": "observed", "state": state})
            self.assertNotIn("private", json.dumps(result))

    def test_state_parser_rejects_malformed_missing_ambiguous_and_unknown(self):
        duplicate = json.loads(self.inventory())
        duplicate["devices"][simulator.RUNTIME] *= 2
        cases = [(b"[]", "invalid"), (b"\xff", "invalid"), (b"{", "invalid"),
                 (b'{"devices": []}', "invalid"), (b'{"devices": {"x": [null]}}', "invalid"),
                 (b'{"devices": {}}', "missing"), (json.dumps(duplicate).encode(), "ambiguous"),
                 (self.inventory("private-sentinel"), "unrecognized"),
                 (self.inventory(None), "unrecognized"), (b" " * (simulator.DEVICE_STATE_LIMIT + 1), "oversized")]
        for raw, outcome in cases:
            with self.subTest(outcome=outcome):
                self.assertEqual(simulator.owned_device_state(raw, DEVICE), {"outcome": outcome})

    def test_state_read_is_scoped_bounded_and_reaps_only_its_direct_process(self):
        real_popen = subprocess.Popen
        handles = []
        processes = []
        def start(args, **options):
            self.assertEqual(args, ["xcrun", "simctl", "list", "devices", DEVICE, "--json"])
            self.assertEqual(options, {"bufsize": 0, "stdout": subprocess.PIPE, "stderr": subprocess.DEVNULL})
            process = real_popen([sys.executable, "-c", f"import sys;sys.stdout.buffer.write({self.inventory('Shutdown')!r})"], **options)
            handles.append(process.stdout)
            processes.append(process)
            return process
        with patch.object(simulator.subprocess, "Popen", side_effect=start):
            result = simulator.post_boot_device_state(DEVICE)
        self.assertEqual(result["state"], "Shutdown")
        self.assertTrue(result["direct_process_reaped"])
        self.assertTrue(handles[0].closed)
        self.assertEqual(processes[0].returncode, 0)

    def test_state_timeout_never_uses_partial_inventory(self):
        for reaped in (True, False):
            process = Mock()
            process.poll.return_value = None
            process.wait.side_effect = [-9 if reaped else subprocess.TimeoutExpired(["state"], 5)]
            with patch.object(simulator.subprocess, "Popen", return_value=process), \
                    patch.object(simulator.os, "set_blocking"), \
                    patch.object(simulator, "STATE_DIAGNOSTIC_TIMEOUT", 0):
                result = simulator.post_boot_device_state(DEVICE)
            self.assertEqual(result["outcome"], "timeout")
            self.assertEqual(result["direct_process_reaped"], reaped)
            self.assertNotIn("state", result)
            self.assertEqual(process.wait.call_args_list, [call(timeout=5)])
            process.kill.assert_called_once_with()

    def test_state_nonzero_does_not_parse_stdout(self):
        with patch.object(simulator, "diagnostic_process", return_value=(
                {"outcome": "nonzero", "returncode": 149}, b"private-sentinel")), \
                patch.object(simulator, "owned_device_state") as parse:
            result = simulator.post_boot_device_state(DEVICE)
        self.assertEqual(result["outcome"], "nonzero")
        self.assertEqual(result["returncode"], 149)
        parse.assert_not_called()

    def test_spawn_error_capture_is_bounded_private_and_never_changes_outcome(self):
        real_popen = subprocess.Popen
        for code in (0, 149):
            handles = []
            def start(args, **options):
                self.assertEqual(options, {"bufsize": 0, "stdout": subprocess.DEVNULL, "stderr": subprocess.PIPE})
                process = real_popen([sys.executable, "-c",
                                      f"import sys;sys.stderr.buffer.write({self.error!r});sys.exit({code})"], **options)
                handles.append(process.stderr)
                return process
            with patch.object(simulator.subprocess, "Popen", side_effect=start):
                result = simulator.post_boot_spawn(DEVICE)
            self.assertTrue(handles[0].closed)
            self.assertEqual(result["returncode"], code)
            self.assertNotIn("private-sentinel", json.dumps(result))
            if code:
                self.assertEqual(result["error_identity"]["errors"][0]["code"], 405)
            else:
                self.assertNotIn("error_identity", result)

    def test_diagnostic_cancellation_propagates_after_bounded_owned_cleanup(self):
        for diagnostic in (simulator.post_boot_spawn, simulator.post_boot_device_state):
            process = Mock()
            process.poll.return_value = None
            process.wait.return_value = -9
            with patch.object(simulator.subprocess, "Popen", return_value=process), \
                    patch.object(simulator.os, "set_blocking"), \
                    patch.object(simulator.os, "read", side_effect=KeyboardInterrupt()), \
                    self.assertRaises(KeyboardInterrupt):
                diagnostic(DEVICE)
            process.kill.assert_called_once_with()
            self.assertEqual(process.wait.call_args_list, [call(timeout=5)])

    def test_failure_diagnostics_fit_unused_identity_read_budget(self):
        diagnostic_maximum = (2 * simulator.SPAWN_DIAGNOSTIC_TIMEOUT + simulator.STATE_DIAGNOSTIC_TIMEOUT
                              + 3 * simulator.IDENTITY_CLEANUP_TIMEOUT)
        self.assertLess(diagnostic_maximum, 2 * 30)

    def test_real_oversized_writer_is_stopped_at_capture_limit_and_reaped(self):
        for capture, descriptor in (("stdout", 1), ("stderr", 2)):
            started = time.monotonic()
            result, raw = simulator.diagnostic_process(
                [sys.executable, "-c", f"import os,time;os.write({descriptor},b'x'*1000000);time.sleep(10)"],
                capture=capture, limit=512, timeout=2)
            self.assertEqual(result["outcome"], "oversized")
            self.assertTrue(result["direct_process_reaped"])
            self.assertEqual(len(raw), 512)
            self.assertLess(time.monotonic() - started, 3)

    def test_real_diagnostic_timeout_reaps_and_closes_capture(self):
        result, raw = simulator.diagnostic_process(
            [sys.executable, "-c", "import time;time.sleep(10)"],
            capture="stderr", limit=512, timeout=.05)
        self.assertEqual(result["outcome"], "timeout")
        self.assertTrue(result["direct_process_running_at_timeout"])
        self.assertTrue(result["direct_process_reaped"])
        self.assertEqual(raw, b"")

    def test_diagnostic_direct_exit_does_not_wait_for_inherited_pipe_eof(self):
        child = ("import pathlib,sys,time; p=pathlib.Path(sys.argv[1]); deadline=time.monotonic()+10\n"
                 "while not p.exists() and time.monotonic()<deadline: time.sleep(.01)\n"
                 "pathlib.Path(sys.argv[2]).write_text('done')\n")
        with tempfile.TemporaryDirectory() as directory:
            release, done = Path(directory) / "release", Path(directory) / "done"
            parent = ("import subprocess,sys\n"
                      f"subprocess.Popen([sys.executable,'-c',{child!r},{str(release)!r},{str(done)!r}],"
                      "stdin=subprocess.DEVNULL)\n"
                      f"sys.stderr.buffer.write({self.error!r});sys.stderr.flush();sys.exit(149)\n")
            try:
                result, raw = simulator.diagnostic_process([sys.executable, "-c", parent],
                                                           capture="stderr", limit=8192, timeout=2)
                self.assertEqual(result["outcome"], "nonzero")
                self.assertEqual(result["returncode"], 149)
                self.assertEqual(raw, self.error)
                self.assertTrue(result["direct_process_reaped"])
                self.assertFalse(done.exists(), "Owned descendant must still hold the descriptor")
            finally:
                release.write_text("release")
                deadline = time.monotonic() + 5
                while not done.exists() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(done.exists(), "Owned fixture descendant must finish")

    def test_capture_setup_failure_cleans_up_started_child_without_raw_error(self):
        with patch.object(simulator.os, "set_blocking", side_effect=OSError("private-sentinel")):
            result, raw = simulator.diagnostic_process(
                [sys.executable, "-c", "import time;time.sleep(10)"],
                capture="stderr", limit=512, timeout=2)
        self.assertEqual(result["outcome"], "unavailable")
        self.assertTrue(result["direct_process_reaped"])
        self.assertEqual(raw, b"")
        self.assertNotIn("private-sentinel", json.dumps(result))


if __name__ == "__main__":
    unittest.main()

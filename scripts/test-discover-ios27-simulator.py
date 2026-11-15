#!/usr/bin/env python3
"""Fail-closed contracts for non-release candidate identity discovery."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
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

    def test_workflow_is_isolated_bounded_and_never_promotes(self):
        path = ROOT / ".github/workflows/ios-runtime-discovery.yml"
        workflow = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                              "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(path)], text=True))
        self.assertEqual(workflow.get("on", workflow.get("true")),
                         {"push": {"branches": ["codex/pr152-simulator-diagnostics-20261114"]}})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        job = workflow["jobs"]["discover"]
        self.assertEqual(job["timeout-minutes"], 25)
        self.assertEqual(job["steps"][2]["timeout-minutes"], 20)
        self.assertIs(job["steps"][0]["with"]["persist-credentials"], False)
        self.assertEqual(job["steps"][-1]["if"], "always()")
        self.assertNotIn("environment", job)


if __name__ == "__main__": unittest.main()

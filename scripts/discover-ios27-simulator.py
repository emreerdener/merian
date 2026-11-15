#!/usr/bin/env python3
"""Observe a candidate runtime identity; never qualify tests or release."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time
import uuid

SPEC = importlib.util.spec_from_file_location("simulator", Path(__file__).with_name("prepare-ios-unit-simulator.py"))
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)
VERSION = "27.2"
BUILD = "24B8117"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"


def discover(receipt, *, run=simulator.command, probe=simulator.diagnostic_process, env=None, machine=None):
    env = os.environ if env is None else env
    if (env.get("GITHUB_ACTIONS") != "true" or env.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or (platform.machine() if machine is None else machine) != "arm64"
            or any(k.startswith("SIMCTL_CHILD_SIMULATOR_") for k in env)):
        raise ValueError("Unqualified host or injected identity")
    if not re.fullmatch(r"[0-9a-f]{40}", env.get("GITHUB_SHA", "")):
        raise ValueError("Missing exact source")
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        if not re.fullmatch(r"[1-9][0-9]*", env.get(key, "")):
            raise ValueError("Missing run identity")
    receipt.update(source_sha=env["GITHUB_SHA"], run_id=env["GITHUB_RUN_ID"],
                   run_attempt=env["GITHUB_RUN_ATTEMPT"], architecture="arm64",
                   runtime_identifier=RUNTIME, device_type_identifier=DEVICE_TYPE)
    inventory = json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"], timeout=10))
    runtimes = inventory.get("runtimes") if isinstance(inventory, dict) else None
    if not isinstance(runtimes, list) or any(not isinstance(r, dict) for r in runtimes):
        raise ValueError("Invalid runtime inventory")
    matches = [r for r in runtimes if r.get("identifier") == RUNTIME
               or (r.get("version") == VERSION and r.get("buildversion") == BUILD)]
    if len(matches) != 1 or any(matches[0].get(k) != v for k, v in
                              {"identifier": RUNTIME, "version": VERSION, "buildversion": BUILD, "isAvailable": True}.items()):
        raise ValueError("Exact preinstalled runtime unavailable or ambiguous")
    types = matches[0].get("supportedDeviceTypes")
    if (not isinstance(types, list) or any(not isinstance(t, dict) for t in types)
            or not any(t.get("identifier") == DEVICE_TYPE for t in types)):
        raise ValueError("Required device type unsupported")
    def phase(name, arguments, timeout):
        started = time.monotonic()
        item = {"phase": name, "outcome": "failed"}
        receipt.setdefault("phases", []).append(item)
        try:
            value = run(arguments, timeout=timeout)
            item["outcome"] = "passed"
            return value
        finally:
            item["elapsed_ms"] = round((time.monotonic() - started) * 1000)
    phase("cache", ["xcrun", "simctl", "runtime", "dyld_shared_cache", "update", RUNTIME], 600)
    device = phase("create", ["xcrun", "simctl", "create", "Merian runtime discovery", DEVICE_TYPE, RUNTIME], 20)
    if str(uuid.UUID(device)).upper() != device.upper():
        raise ValueError("Invalid owned device identity")
    phase("boot", ["xcrun", "simctl", "bootstatus", device, "-b"], 300)
    observed = {}
    for key, expected in (("SIMULATOR_RUNTIME_VERSION", VERSION), ("SIMULATOR_RUNTIME_BUILD_VERSION", BUILD),
                          ("SIMULATOR_MODEL_IDENTIFIER", None)):
        result, raw = probe(["xcrun", "simctl", "getenv", device, key], capture="stdout", limit=64, timeout=30)
        receipt.setdefault("queries", []).append({"key": key, **result})
        if result.get("outcome") != "passed" or result.get("direct_process_reaped") is not True:
            raise ValueError("Guest identity query failed")
        value = raw.decode("ascii").strip()
        if (expected is not None and value != expected) or (expected is None and not re.fullmatch(r"iPhone[0-9]{1,2},[0-9]{1,2}", value)):
            raise ValueError("Guest identity mismatch")
        observed[key] = value
    receipt.update(identity_observed=True, observed_environment=observed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    receipt = {"schema_version": 1, "status": "preparing", "qualified": False,
               "release_eligible": False, "identity_observed": False}
    args.evidence.write_text(json.dumps(receipt) + "\n")
    try:
        discover(receipt)
        receipt["status"] = "passed"
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        receipt.update(status="failed", failure_kind=type(error).__name__)
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Observe a candidate runtime identity; never qualify tests or release."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time
import uuid
from urllib.parse import unquote, urlsplit

SPEC = importlib.util.spec_from_file_location("simulator", Path(__file__).with_name("prepare-ios-unit-simulator.py"))
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)
VERSION = "27.2"
BUILD = "24B8117"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"


def prepare(receipt, *, run=simulator.command, env=None, machine=None):
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
    receipt["simulator_destination"] = f"platform=iOS Simulator,id={device}"
    return device


def discover(receipt, *, run=simulator.command, probe=simulator.diagnostic_process, env=None, machine=None):
    device = prepare(receipt, run=run, env=env, machine=machine)
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



CASE = "SimulatorRuntimeIdentityTests/testRecordsBootedGuestIdentity()"
ATTACHMENT = "merian-simulator-identity.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_bounded_json(path, limit):
    require(path.is_file() and not path.is_symlink(), "Missing or linked evidence")
    require(0 < path.stat().st_size <= limit, "Evidence exceeds bound")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate evidence key")
            result[key] = value
        return result
    return json.loads(path.read_bytes(), object_pairs_hook=unique)


def verify(directory, *, env=None):
    """Bind a single guest attachment to its passed test, owned device and source."""
    env = os.environ if env is None else env
    directory = Path(directory)
    prepared = read_bounded_json(directory / "preparation.json", 16384)
    require(isinstance(prepared, dict), "Invalid preparation object")
    require(prepared.get("status") == "prepared" and prepared.get("qualified") is False
            and prepared.get("release_eligible") is False and prepared.get("identity_observed") is False,
            "Preparation is not non-qualifying")
    for field, key in (("source_sha", "GITHUB_SHA"), ("run_id", "GITHUB_RUN_ID"), ("run_attempt", "GITHUB_RUN_ATTEMPT")):
        value = env.get(key, "")
        require(re.fullmatch(r"[0-9a-f]{40}" if field == "source_sha" else r"[1-9][0-9]*", value)
                and prepared.get(field) == value, "Stale source/run evidence")
    require(env.get("IOS_IDENTITY_TEST_OUTCOME") == "success", "Test process did not pass")
    require(prepared.get("architecture") == "arm64" and prepared.get("runtime_identifier") == RUNTIME
            and prepared.get("device_type_identifier") == DEVICE_TYPE, "Wrong prepared runtime")
    phases = prepared.get("phases", [])
    require(isinstance(phases, list) and all(isinstance(p, dict) for p in phases), "Invalid preparation phases")
    require([p.get("phase") for p in phases] == ["cache", "create", "boot"]
            and all(p.get("outcome") == "passed" for p in phases), "Incomplete preparation")
    destination = prepared.get("simulator_destination", "")
    match = re.fullmatch(r"platform=iOS Simulator,id=([A-Fa-f0-9-]{36})", destination)
    require(match is not None, "Invalid owned destination")
    device = match.group(1)
    require(str(uuid.UUID(device)).upper() == device.upper(), "Invalid owned UUID")
    summary = read_bounded_json(directory / "summary.json", 65536)
    require(isinstance(summary, dict), "Invalid summary object")
    require(summary.get("result") == "Passed", "Test summary failed")
    for key, expected in (("totalTestCount", 1), ("passedTests", 1), ("failedTests", 0), ("skippedTests", 0)):
        require(type(summary.get(key)) is int and summary[key] == expected, "Missing, extra, failed or skipped test")
    tree = read_bounded_json(directory / "tests.json", 65536)
    require(isinstance(tree, dict), "Invalid test tree")
    devices = tree.get("devices", [])
    require(isinstance(devices, list) and len(devices) == 1 and isinstance(devices[0], dict)
             and all(devices[0].get(k) == v for k, v in {
        "deviceId": device, "architecture": "arm64", "osVersion": VERSION,
        "osBuildNumber": BUILD, "platform": "iOS Simulator"}.items()), "Result device mismatch")
    configurations = tree.get("testPlanConfigurations", [])
    require(isinstance(configurations, list) and len(configurations) == 1 and isinstance(configurations[0], dict)
             and isinstance(configurations[0].get("configurationName"), str),
            "Missing or multiple test configurations")
    nodes = tree.get("testNodes", [])
    case = None
    for kind, name in (("Test Plan", None), ("Unit test bundle", "merianTests"),
                       ("Test Suite", "SimulatorRuntimeIdentityTests"),
                       ("Test Case", "testRecordsBootedGuestIdentity()")):
        require(isinstance(nodes, list) and len(nodes) == 1 and isinstance(nodes[0], dict), "Missing or extra result nodes")
        case = nodes[0]
        require(case.get("nodeType") == kind and case.get("result") == "Passed"
                and (name is None or case.get("name") == name), "Wrong or failed result node")
        nodes = case.get("children", [])
    require(nodes == [] and case.get("nodeIdentifier") == CASE, "Wrong identity test")
    url = case.get("nodeIdentifierURL", "")
    parsed = urlsplit(url)
    parts = [unquote(part) for part in parsed.path.split("/")[1:]]
    require(parsed.scheme == "test" and parsed.netloc == "com.apple.xcode" and not parsed.query
            and not parsed.fragment and len(parts) == 4 and parts[1:] ==
            ["merianTests", "SimulatorRuntimeIdentityTests", "testRecordsBootedGuestIdentity"], "Unbound test URL")
    attachments = directory / "attachments"
    require(attachments.is_dir() and not attachments.is_symlink(), "Invalid attachment directory")
    manifest = read_bounded_json(attachments / "manifest.json", 65536)
    require(isinstance(manifest, list) and len(manifest) == 1, "Missing or extra attachment cases")
    entry = manifest[0]
    require(isinstance(entry, dict), "Invalid attachment case")
    require(entry.get("testIdentifier") == CASE
            and entry.get("testIdentifierURL", url) == url, "Attachment belongs to another test")
    items = entry.get("attachments", [])
    require(isinstance(items, list) and len(items) == 1 and isinstance(items[0], dict), "Missing or extra identity attachment")
    item = items[0]
    require(item.get("isAssociatedWithFailure") is False and item.get("deviceId") == device
            and item.get("configurationName") == configurations[0]["configurationName"], "Unbound identity attachment")
    require(item.get("suggestedHumanReadableName") in (ATTACHMENT, ATTACHMENT + ".txt"), "Wrong attachment name")
    filename = item.get("exportedFileName", "")
    require(isinstance(filename, str) and filename not in ("", ".", "..", "manifest.json")
            and Path(filename).name == filename and "/" not in filename and "\\" not in filename,
            "Unsafe exported attachment path")
    require({p.name for p in attachments.iterdir()} == {"manifest.json", filename}, "Unexpected attachment files")
    payload_path = attachments / filename
    payload = read_bounded_json(payload_path, 512)
    require(isinstance(payload, dict) and set(payload) == {"runtime_version", "runtime_build", "model_identifier"}
            and payload["runtime_version"] == VERSION and payload["runtime_build"] == BUILD
            and isinstance(payload["model_identifier"], str)
            and re.fullmatch(r"iPhone[0-9]{1,2},[0-9]{1,2}", payload["model_identifier"]), "Invalid guest identity")
    return {**prepared, "status": "passed", "identity_observed": True, "observation_method": "xctest_attachment",
            "observed_environment": {"SIMULATOR_RUNTIME_VERSION": payload["runtime_version"],
                                     "SIMULATOR_RUNTIME_BUILD_VERSION": payload["runtime_build"],
                                     "SIMULATOR_MODEL_IDENTIFIER": payload["model_identifier"]},
            "files": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest() for name in
                      ("preparation.json", "summary.json", "tests.json", "attachments/manifest.json", "attachments/" + filename)}}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--verify-directory", type=Path)
    args = parser.parse_args()
    receipt = {"schema_version": 1, "status": "preparing", "qualified": False,
               "release_eligible": False, "identity_observed": False}
    args.evidence.write_text(json.dumps(receipt) + "\n")
    try:
        if args.prepare_only:
            prepare(receipt)
            receipt["status"] = "prepared"
            print(receipt["simulator_destination"])
        elif args.verify_directory:
            receipt = verify(args.verify_directory)
        else:
            discover(receipt)
            receipt["status"] = "passed"
    except (ValueError, OSError, TypeError, KeyError, AttributeError, subprocess.SubprocessError) as error:
        receipt.update(status="failed", failure_kind=type(error).__name__)
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["status"] in ("passed", "prepared") else 1


if __name__ == "__main__":
    raise SystemExit(main())

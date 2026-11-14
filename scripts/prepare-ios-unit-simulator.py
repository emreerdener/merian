#!/usr/bin/env python3
"""Prepare the measured-transfer simulator on disposable GitHub-hosted runners."""

import argparse
import json
import os
import platform
import subprocess
import sys
import uuid
from pathlib import Path


VERSION = "26.5"
BUILD = "23F77"
MODEL = "iPhone18,1"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
EXPECTED_ENVIRONMENT = {
    "SIMULATOR_RUNTIME_VERSION": VERSION,
    "SIMULATOR_RUNTIME_BUILD_VERSION": BUILD,
    "SIMULATOR_MODEL_IDENTIFIER": MODEL,
}


def command(arguments, *, timeout=60):
    result = subprocess.run(arguments, check=True, text=True,
                            stdout=subprocess.PIPE, timeout=timeout)
    return result.stdout.strip()


def qualified_runtime(inventory):
    if (not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list)
            or any(not isinstance(item, dict) for item in inventory["runtimes"])):
        raise ValueError("Invalid simulator runtime inventory.")
    matches = [r for r in inventory.get("runtimes", [])
               if r.get("identifier") == RUNTIME
               and r.get("version") == VERSION
               and r.get("buildversion") == BUILD
               and r.get("isAvailable") is True]
    if len(matches) > 1:
        raise ValueError("Ambiguous measured simulator runtime inventory.")
    return matches[0] if matches else None


def prepare(*, run=command, environment=None, machine=None):
    environment = os.environ if environment is None else environment
    machine = platform.machine() if machine is None else machine
    # This helper installs a runtime and creates a device. Never use it against
    # a developer's or a self-hosted runner's shared simulator inventory.
    if (environment.get("GITHUB_ACTIONS") != "true"
            or environment.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or machine != "arm64"):
        raise ValueError("Measured simulator preparation requires an arm64 GitHub-hosted runner.")
    if any(key.startswith("SIMCTL_CHILD_SIMULATOR_") for key in environment):
        raise ValueError("Simulator identity must come from the runtime, not injected child variables.")

    def inventory():
        return json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"], timeout=10))

    runtime = qualified_runtime(inventory())
    if runtime is None:
        # Request the exact build, not the release number (which can select a
        # different build). Independently verify the installed identity below.
        output = run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", BUILD,
                      "-architectureVariant", "arm64"], timeout=360)
        print(output, file=sys.stderr)
        runtime = qualified_runtime(inventory())
    if runtime is None:
        raise ValueError(f"Required iOS {VERSION} build {BUILD} is unavailable; no fallback is permitted.")
    device_types = runtime.get("supportedDeviceTypes")
    if (not isinstance(device_types, list) or any(not isinstance(item, dict) for item in device_types)
            or not any(item.get("identifier") == DEVICE_TYPE for item in device_types)):
        raise ValueError("The measured runtime does not support the required iPhone 17 Pro device type.")

    # Own a new device on this disposable runner instead of borrowing one by name.
    device = run(["xcrun", "simctl", "create", "Merian measured unit tests", DEVICE_TYPE, RUNTIME], timeout=20)
    if str(uuid.UUID(device)).upper() != device.upper():
        raise ValueError("Simulator creation returned an invalid device identifier.")
    run(["xcrun", "simctl", "bootstatus", device, "-b"], timeout=300)
    observed = {key: run(["xcrun", "simctl", "getenv", device, key], timeout=10)
                for key in EXPECTED_ENVIRONMENT}
    if observed != EXPECTED_ENVIRONMENT:
        raise ValueError("Booted simulator identity does not match the measured-transfer qualification: "
                         + json.dumps(observed, sort_keys=True))
    return {
        "schema_version": 1,
        "qualified": True,
        "status": "passed",
        "architecture": machine,
        "runtime_identifier": RUNTIME,
        "device_type_identifier": DEVICE_TYPE,
        "simulator_destination": f"platform=iOS Simulator,id={device}",
        "observed_environment": observed,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    # Retain a non-passing receipt even if the external step deadline interrupts
    # preparation. Never serialize the runner environment or downloaded content.
    result = {"schema_version": 1, "qualified": False, "status": "preparing",
              "required_environment": EXPECTED_ENVIRONMENT, "required_architecture": "arm64"}
    args.evidence.write_text(json.dumps(result, indent=2) + "\n")
    try:
        result = prepare()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result.update(status="failed", failure=str(error))
        if (isinstance(error, subprocess.TimeoutExpired)
                and isinstance(error.cmd, list)
                and error.cmd[:3] == ["xcrun", "simctl", "bootstatus"]
                and error.stdout):
            # This new, empty hosted simulator has not run the app. Preserve
            # bounded boot progress only, never command/environment dumps.
            output = error.stdout
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            result["boot_diagnostic_tail"] = output[-8000:]
        args.evidence.write_text(json.dumps(result, indent=2) + "\n")
        raise
    args.evidence.write_text(json.dumps(result, indent=2) + "\n")
    print(result["simulator_destination"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Measured unit simulator preparation failed: {error}", file=sys.stderr)
        sys.exit(1)

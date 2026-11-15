#!/usr/bin/env python3
"""Test Apple's exported-runtime installation on a disposable hosted runner only."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


SPEC = importlib.util.spec_from_file_location(
    "unit_simulator", Path(__file__).with_name("prepare-ios-unit-simulator.py"))
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)
DOWNLOAD = ["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", simulator.BUILD,
            "-architectureVariant", "arm64"]
INVENTORY = ["xcrun", "simctl", "list", "runtimes", "--json"]


def runtime_counts(output):
    inventory = json.loads(output)
    if (not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list)
            or any(not isinstance(item, dict) for item in inventory["runtimes"])):
        raise ValueError("Invalid runtime inventory.")
    # Count unavailable registrations too: Ready + Unusable must never look
    # like one clean installed runtime. Identifier collisions also fail closed.
    matches = [item for item in inventory["runtimes"]
               if item.get("identifier") == simulator.RUNTIME
               or (item.get("version") == simulator.VERSION and item.get("buildversion") == simulator.BUILD)]
    available = sum(item.get("isAvailable") is True for item in matches)
    return {"total": len(matches), "available": available, "unavailable": len(matches) - available}


def exported_bundle(directory):
    entries = list(directory.iterdir())
    if (len(entries) != 1 or entries[0].suffix != ".exportedBundle"
            or entries[0].is_symlink() or not entries[0].is_dir()
            or entries[0].resolve().parent != directory.resolve()):
        raise ValueError("Export must produce exactly one owned exportedBundle directory.")
    return entries[0]


def install_exported_runtime(directory, phases, *, timeout, inspect_before_import, clock=time.monotonic,
                             execute=subprocess.run):
    # Export and import share the existing installation allowance. Never accept
    # a nonzero export (including 70) based only on files being present.
    deadline = clock() + timeout

    def phase(name, arguments):
        remaining = deadline - clock()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(["runtime-installation"], timeout)
        started = clock()
        receipt = {"phase": name, "outcome": "failed"}
        phases.append(receipt)
        try:
            execute(arguments, check=True, timeout=remaining,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            receipt["outcome"] = "passed"
        finally:
            receipt["elapsed_ms"] = round((clock() - started) * 1000)

    phase("runtime_export", DOWNLOAD + ["-exportPath", str(directory)])
    bundle = exported_bundle(directory)
    remaining = deadline - clock()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(["runtime-installation"], timeout)
    # Export must not itself install/register the runtime on this target. That
    # would confound the import path and may create duplicate registrations.
    inspect_before_import(timeout=min(10, remaining))
    # Xcode owns verification of Apple's signed export metadata. Do not unpack,
    # edit, strip quarantine, or register an inner image directly.
    phase("runtime_import", ["xcodebuild", "-importPlatform", str(bundle)])


class ExportInstaller:
    def __init__(self, runner_temp, *, run=simulator.command):
        self.runner_temp = runner_temp
        self.run = run
        self.inventory_seen = False
        self.installed = False
        self.phases = []
        self.registrations = []

    def inspect(self, stage, *, timeout):
        output = self.run(INVENTORY, timeout=timeout)
        counts = runtime_counts(output)
        self.registrations.append({"stage": stage, **counts})
        required = 1 if stage == "after_import" else 0
        if counts["total"] != required:
            raise ValueError("Runtime registration count makes the installation experiment inconclusive.")
        return output

    def inspect_before_import(self, *, timeout):
        return self.inspect("after_export", timeout=timeout)

    def __call__(self, arguments, *, timeout=60):
        if arguments == INVENTORY:
            stage = "after_import" if self.installed else "before_export"
            output = self.inspect(stage, timeout=timeout)
            self.inventory_seen = True
            return output
        if arguments == DOWNLOAD:
            if not self.inventory_seen or self.installed or timeout != 360:
                raise ValueError("Unexpected runtime installation sequence.")
            # prepare() validates the hosted arm64 environment before invoking
            # this adapter. Only this fresh directory is removed afterward.
            with tempfile.TemporaryDirectory(prefix="merian-runtime-export-",
                                             dir=self.runner_temp) as directory:
                install_exported_runtime(Path(directory), self.phases, timeout=timeout,
                                         inspect_before_import=self.inspect_before_import)
            self.installed = True
            return "Apple runtime export/import completed; installed identity still requires verification."
        return self.run(arguments, timeout=timeout)


def experiment(adapter, **prepare_arguments):
    receipt = {"schema_version": 1, "experiment": "exported-runtime-installation",
               "release_eligible": False, "status": "failed", "setup_qualified": False}
    try:
        result = simulator.prepare(run=adapter, **prepare_arguments)
        if not adapter.installed:
            raise ValueError("Export/import was not exercised.")
        receipt.update(status="passed", setup_qualified=True, qualification=result)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        # No exception text, command output, environment, download contents or
        # paths enter the artifact. The original qualification failure remains.
        receipt["failure_kind"] = type(error).__name__
        if hasattr(error, "phase_diagnostics"):
            receipt["qualification_phases"] = error.phase_diagnostics
        if isinstance(error, simulator.IdentityQueryTimeout):
            receipt["identity_query_diagnostics"] = error.diagnostics
    receipt["installation_phases"] = adapter.phases
    receipt["runtime_registrations"] = adapter.registrations
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    runner_temp = os.environ.get("RUNNER_TEMP")
    if not runner_temp or not Path(runner_temp).is_dir():
        raise ValueError("A runner temporary directory is required.")
    args.evidence.write_text(json.dumps({"status": "preparing", "setup_qualified": False,
                                         "release_eligible": False}) + "\n")
    receipt = experiment(ExportInstaller(runner_temp))
    receipt["source_sha"] = os.environ.get("GITHUB_SHA", "")
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["setup_qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Transfer an intact Apple runtime between two disposable hosted runners."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import time

SPEC = importlib.util.spec_from_file_location(
    "unit_simulator", Path(__file__).with_name("prepare-ios-unit-simulator.py"))
simulator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(simulator)
DOWNLOAD = ["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", simulator.BUILD,
            "-architectureVariant", "arm64"]
INVENTORY = ["xcrun", "simctl", "list", "runtimes", "--json"]
MAX_TRANSFER = 16 * 1024**3
MAX_MEMBERS = 4096


def require(condition, message):
    if not condition:
        raise ValueError(message)


def hosted_identity(environment=None, machine=None):
    env = os.environ if environment is None else environment
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and (platform.machine() if machine is None else machine) == "arm64",
            "A disposable arm64 GitHub-hosted runner is required.")
    require(not any(key.startswith("SIMCTL_CHILD_SIMULATOR_") for key in env), "Injected identity is forbidden.")
    require(re.fullmatch(r"[0-9a-f]{40}", env.get("GITHUB_SHA", "")), "Invalid source identity.")
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", env.get(key, "")), "Invalid run identity.")
    return {"source_sha": env["GITHUB_SHA"], "run_id": env["GITHUB_RUN_ID"],
            "run_attempt": env["GITHUB_RUN_ATTEMPT"], "runtime_build": simulator.BUILD,
            "runtime_version": simulator.VERSION, "architecture": "arm64"}


def runtime_counts(output):
    inventory = json.loads(output)
    require(isinstance(inventory, dict) and isinstance(inventory.get("runtimes"), list)
            and all(isinstance(item, dict) for item in inventory["runtimes"]), "Invalid runtime inventory.")
    matches = [item for item in inventory["runtimes"]
               if item.get("identifier") == simulator.RUNTIME
               or (item.get("version") == simulator.VERSION and item.get("buildversion") == simulator.BUILD)]
    available = sum(item.get("isAvailable") is True for item in matches)
    return {"total": len(matches), "available": available, "unavailable": len(matches) - available}


def inspect_runtime(receipt, stage, expected, *, run=simulator.command, timeout=10):
    output = run(INVENTORY, timeout=timeout)
    counts = runtime_counts(output)
    receipt.setdefault("runtime_registrations", []).append({"stage": stage, **counts})
    require(counts["total"] == expected and counts["available"] == expected,
            "Runtime registration count does not match the experiment precondition.")
    if expected == 1:
        require(simulator.qualified_runtime(json.loads(output)) is not None,
                "Installed runtime identity does not match the exact required build.")
    return output


def exported_bundle(directory):
    entries = list(directory.iterdir())
    require(len(entries) == 1 and entries[0].suffix == ".exportedBundle"
            and not entries[0].is_symlink() and entries[0].is_dir()
            and entries[0].resolve().parent == directory.resolve(),
            "Expected one owned exportedBundle directory.")
    return entries[0]


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_members(members):
    require(0 < len(members) <= MAX_MEMBERS, "Invalid transfer member count.")
    names = {}
    folded = set()
    total = 0
    roots = set()
    for member in members:
        path = PurePosixPath(member.name)
        require(path.parts and not path.is_absolute() and str(path) == member.name
                and all(part not in (".", "..") for part in path.parts), "Unsafe transfer path.")
        require(member.isdir() or member.isfile(), "Links and special transfer members are forbidden.")
        require(not member.sparse and member.size >= 0, "Sparse or invalid transfer member.")
        require(member.name.casefold() not in folded, "Duplicate transfer member.")
        folded.add(member.name.casefold())
        names[member.name] = member
        roots.add(path.parts[0])
        total += member.size
        # File payload and the entire on-disk archive are independently capped.
        require(total <= MAX_TRANSFER, "Oversized transfer payload.")
    require(len(roots) == 1, "Multiple transfer roots.")
    root = next(iter(roots))
    require(root.endswith(".exportedBundle") and root in names and names[root].isdir(),
            "Missing exported bundle root.")
    for name in names:
        for parent in PurePosixPath(name).parents:
            if str(parent) != ".":
                require(str(parent) in names and names[str(parent)].isdir(), "Invalid transfer parent.")
    return root, total


def pack_bundle(bundle, archive_path):
    require(not bundle.is_symlink() and bundle.is_dir(), "Invalid exported bundle.")
    paths = [bundle] + sorted(bundle.rglob("*"))
    require(len(paths) <= MAX_MEMBERS, "Too many transfer members.")
    # Preserve hidden files and modes inside one tar; the artifact ZIP cannot
    # otherwise preserve modes. No arbitrary runner paths or raw logs are packed.
    with tarfile.open(archive_path, "x") as archive:
        members = []
        for path in paths:
            require(not path.is_symlink(), "Exported bundle links are unsupported.")
            archive.inodes.clear()  # Copy hard-linked regular files as data.
            name = bundle.name if path == bundle else bundle.name + "/" + path.relative_to(bundle).as_posix()
            member = archive.gettarinfo(str(path), arcname=name)
            member.uid = member.gid = 0
            member.uname = member.gname = ""
            member.mode &= 0o777
            members.append(member)
        validate_members(members)
        for path, member in zip(paths, members):
            if member.isfile():
                with path.open("rb") as source:
                    archive.addfile(member, source)
            else:
                archive.addfile(member)
    require(archive_path.stat().st_size <= MAX_TRANSFER, "Oversized transfer archive.")
    return digest(archive_path)


def unpack_bundle(archive_path, destination, expected_digest):
    require(re.fullmatch(r"[0-9a-f]{64}", expected_digest), "Invalid expected transfer digest.")
    require(not archive_path.is_symlink() and archive_path.is_file()
            and archive_path.stat().st_size <= MAX_TRANSFER, "Invalid transfer archive.")
    require(digest(archive_path) == expected_digest, "Transfer digest mismatch.")
    require(not destination.exists() and not destination.is_symlink(), "Extraction requires a fresh directory.")
    with tarfile.open(archive_path, "r:") as archive:
        members = []
        for member in archive:
            members.append(member)
            require(len(members) <= MAX_MEMBERS, "Too many transfer members.")
        root, total = validate_members(members)
        require(shutil.disk_usage(destination.parent).free >= total + 1024**3, "Insufficient extraction space.")
        destination.mkdir()
        # No extractall: validate the complete graph before any filesystem write.
        for member in sorted(members, key=lambda item: (item.name.count("/"), item.name)):
            path = destination / member.name
            if member.isdir():
                path.mkdir()
            else:
                with archive.extractfile(member) as source, path.open("xb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                path.chmod(member.mode & 0o777)
        for member in sorted((m for m in members if m.isdir()), key=lambda item: -item.name.count("/")):
            (destination / member.name).chmod(member.mode & 0o777)
    return destination / root


def execute_phase(receipt, name, arguments, timeout, *, execute=subprocess.run):
    phase = {"phase": name, "outcome": "failed"}
    receipt.setdefault("installation_phases", []).append(phase)
    started = time.monotonic()
    try:
        execute(arguments, check=True, timeout=timeout, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        phase["outcome"] = "passed"
    except subprocess.CalledProcessError as error:
        phase["returncode"] = error.returncode
        raise
    finally:
        phase["elapsed_ms"] = round((time.monotonic() - started) * 1000)


def export_runtime(runner_temp, archive_path, receipt, *, run=simulator.command, execute=subprocess.run):
    inspect_runtime(receipt, "before_export", 0, run=run)
    with tempfile.TemporaryDirectory(prefix="merian-runtime-export-", dir=runner_temp) as directory:
        execute_phase(receipt, "runtime_export", DOWNLOAD + ["-exportPath", directory], 360, execute=execute)
        # The previous experiment proved export installs on its source host.
        # Never import there. The consumer must independently start empty.
        inspect_runtime(receipt, "after_export", 1, run=run)
        bundle = exported_bundle(Path(directory))
        receipt["tar_sha256"] = pack_bundle(bundle, archive_path)
        receipt["tar_bytes"] = archive_path.stat().st_size


class ImportInstaller:
    def __init__(self, bundle, receipt, *, run=simulator.command, execute=subprocess.run):
        self.bundle, self.receipt, self.run, self.execute = bundle, receipt, run, execute
        self.inventory_seen = self.installed = False

    def __call__(self, arguments, *, timeout=60):
        if arguments == INVENTORY:
            output = inspect_runtime(self.receipt, "after_import" if self.installed else "before_import",
                                     1 if self.installed else 0, run=self.run, timeout=timeout)
            self.inventory_seen = True
            return output
        if arguments == DOWNLOAD:
            require(self.inventory_seen and not self.installed and timeout == 360, "Invalid import sequence.")
            require(exported_bundle(self.bundle.parent) == self.bundle, "Invalid imported bundle.")
            execute_phase(self.receipt, "runtime_import", ["xcodebuild", "-importPlatform", str(self.bundle)],
                          timeout, execute=self.execute)
            self.installed = True
            return "Runtime import completed; installed and guest identities still require verification."
        return self.run(arguments, timeout=timeout)


def verify_provenance(receipt, identity, env):
    for key in ("source_sha", "run_id", "run_attempt"):
        require(env.get("EXPORT_" + key.upper()) == identity[key], "Transfer source/run identity mismatch.")
    require(re.fullmatch(r"[1-9][0-9]*", env.get("EXPORT_ARTIFACT_ID", "")), "Invalid artifact identity.")
    require(re.fullmatch(r"(?:sha256:)?[0-9a-f]{64}", env.get("EXPORT_ARTIFACT_DIGEST", "")),
            "Invalid artifact digest.")
    require(re.fullmatch(r"[0-9a-f]{64}", env.get("EXPORT_TAR_SHA256", "")), "Invalid tar digest.")
    receipt.update(tar_sha256=env["EXPORT_TAR_SHA256"], artifact_id=env["EXPORT_ARTIFACT_ID"],
                   artifact_digest=env["EXPORT_ARTIFACT_DIGEST"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "unpack", "qualify"))
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    receipt = {"schema_version": 2, "experiment": "two-host-runtime-import", "mode": args.mode,
               "release_eligible": False, "status": "preparing", "setup_qualified": False}
    args.evidence.write_text(json.dumps(receipt) + "\n")
    try:
        identity = hosted_identity()
        receipt.update(identity)
        runner_temp = Path(os.environ["RUNNER_TEMP"])
        require(runner_temp.is_absolute() and runner_temp.is_dir(), "Invalid runner temporary directory.")
        if args.mode == "export":
            export_runtime(runner_temp, runner_temp / "runtime-export.tar", receipt)
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                for key in ("tar_sha256", "source_sha", "run_id", "run_attempt"):
                    output.write(key + "=" + receipt[key] + "\n")
        else:
            verify_provenance(receipt, identity, os.environ)
            destination = runner_temp / "runtime-import-bundle"
            if args.mode == "unpack":
                inspect_runtime(receipt, "before_unpack", 0)
                unpack_bundle(runner_temp / "runtime-input/runtime-export.tar", destination, receipt["tar_sha256"])
            else:
                # Same runner, with no intervening mutation step after verified
                # unpack. Recheck absence immediately before Apple's import.
                adapter = ImportInstaller(exported_bundle(destination), receipt)
                result = simulator.prepare(run=adapter)
                require(adapter.installed, "Import was not exercised.")
                receipt.update(setup_qualified=True, qualification=result)
        receipt["status"] = "passed"
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, tarfile.TarError) as error:
        receipt.update(status="failed", failure_kind=type(error).__name__)
        if hasattr(error, "phase_diagnostics"):
            receipt["qualification_phases"] = error.phase_diagnostics
        if isinstance(error, simulator.IdentityQueryTimeout):
            receipt["identity_query_diagnostics"] = error.diagnostics
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

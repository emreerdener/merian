#!/usr/bin/env python3
"""Portable adversarial contracts for the two-host runtime experiment."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


experiment = load("runtime_import_experiment", "experiment-ios-runtime-import.py")
fixtures = load("simulator_fixtures", "test-prepare-ios-unit-simulator.py")
HOST = dict(fixtures.HOST, GITHUB_SHA="a" * 40, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
PROVENANCE = dict(EXPORT_SOURCE_SHA="a" * 40, EXPORT_RUN_ID="123", EXPORT_RUN_ATTEMPT="1",
                  EXPORT_ARTIFACT_ID="456", EXPORT_ARTIFACT_DIGEST="b" * 64, EXPORT_TAR_SHA256="c" * 64)


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def bundle(self):
        bundle = self.root / "source/runtime.exportedBundle"
        bundle.mkdir(parents=True)
        (bundle / ".metadata").write_bytes(b"synthetic signed metadata placeholder")
        (bundle / "image.dmg").write_bytes(b"synthetic runtime payload")
        (bundle / "image.dmg").chmod(0o640)
        return bundle

    def test_host_and_immutable_run_identity_required(self):
        expected = experiment.hosted_identity(HOST, "arm64")
        self.assertEqual(expected["runtime_build"], "23F77")
        for env, machine in (({}, "arm64"), (HOST, "x86_64"),
                             (dict(HOST, RUNNER_ENVIRONMENT="self-hosted"), "arm64"),
                             (dict(HOST, GITHUB_SHA="main"), "arm64"),
                             (dict(HOST, GITHUB_RUN_ATTEMPT="0"), "arm64"),
                             (dict(HOST, SIMCTL_CHILD_SIMULATOR_RUNTIME_VERSION="26.5"), "arm64")):
            with self.subTest(env=env, machine=machine), self.assertRaises(ValueError):
                experiment.hosted_identity(env, machine)

    def test_provenance_rejects_other_source_run_attempt_or_artifact(self):
        identity = experiment.hosted_identity(HOST, "arm64")
        receipt = {}
        experiment.verify_provenance(receipt, identity, PROVENANCE)
        self.assertEqual(receipt["tar_sha256"], "c" * 64)
        for key, value in (("EXPORT_SOURCE_SHA", "d" * 40), ("EXPORT_RUN_ID", "999"),
                           ("EXPORT_RUN_ATTEMPT", "2"), ("EXPORT_ARTIFACT_ID", ""),
                           ("EXPORT_ARTIFACT_DIGEST", "wrong"), ("EXPORT_TAR_SHA256", "")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                experiment.verify_provenance({}, identity, dict(PROVENANCE, **{key: value}))

    def test_tar_round_trip_preserves_hidden_contents_and_modes(self):
        bundle = self.bundle()
        archive = self.root / "runtime.tar"
        sha = experiment.pack_bundle(bundle, archive)
        restored = experiment.unpack_bundle(archive, self.root / "unpacked", sha)
        self.assertEqual(restored.name, bundle.name)
        for name in (".metadata", "image.dmg"):
            self.assertEqual((restored / name).read_bytes(), (bundle / name).read_bytes())
        self.assertEqual((restored / "image.dmg").stat().st_mode & 0o777, 0o640)
        with tarfile.open(archive) as tar:
            self.assertTrue(all(m.uid == m.gid == 0 and m.uname == m.gname == "" for m in tar))

    def test_wrong_digest_or_existing_destination_rejected_before_writes(self):
        archive = self.root / "runtime.tar"
        sha = experiment.pack_bundle(self.bundle(), archive)
        destination = self.root / "unpacked"
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            experiment.unpack_bundle(archive, destination, "0" * 64)
        self.assertFalse(destination.exists())
        destination.mkdir()
        with self.assertRaisesRegex(ValueError, "fresh directory"):
            experiment.unpack_bundle(archive, destination, sha)
        self.assertEqual(list(destination.iterdir()), [])

    def test_source_links_and_special_members_cannot_be_transferred(self):
        bundle = self.bundle()
        (bundle / "link").symlink_to("image.dmg")
        with self.assertRaises(ValueError):
            experiment.pack_bundle(bundle, self.root / "runtime.tar")

    def test_unsafe_archive_graph_is_rejected_before_extraction(self):
        root = tarfile.TarInfo("runtime.exportedBundle"); root.type = tarfile.DIRTYPE
        def member(name, kind=tarfile.REGTYPE):
            value = tarfile.TarInfo(name); value.type = kind; value.linkname = "../../escape"
            return value
        bad_members = [member("../escape"), member("/absolute"), member("runtime.exportedBundle/../escape"),
                       member("runtime.exportedBundle/link", tarfile.SYMTYPE),
                       member("runtime.exportedBundle/hard", tarfile.LNKTYPE),
                       member("runtime.exportedBundle/fifo", tarfile.FIFOTYPE),
                       member("runtime.exportedBundle/missing/file"), member("second.exportedBundle", tarfile.DIRTYPE)]
        for index, bad in enumerate(bad_members):
            archive = self.root / (str(index) + ".tar")
            with tarfile.open(archive, "w") as tar:
                tar.addfile(root); tar.addfile(bad)
            destination = self.root / ("unpacked" + str(index))
            with self.subTest(name=bad.name), self.assertRaises(ValueError):
                experiment.unpack_bundle(archive, destination, experiment.digest(archive))
            self.assertFalse(destination.exists())

    def test_duplicate_case_collisions_and_payload_limits_rejected(self):
        root = tarfile.TarInfo("runtime.exportedBundle"); root.type = tarfile.DIRTYPE
        first = tarfile.TarInfo("runtime.exportedBundle/Data"); first.size = 10
        second = tarfile.TarInfo("runtime.exportedBundle/data")
        with self.assertRaises(ValueError):
            experiment.validate_members([root, first, second])
        with patch.object(experiment, "MAX_TRANSFER", 5), self.assertRaises(ValueError):
            experiment.validate_members([root, first])
        with patch.object(experiment, "MAX_MEMBERS", 1), self.assertRaises(ValueError):
            experiment.validate_members([root, first])

    def test_bundle_selection_rejects_extra_entries_and_symlinks(self):
        for mode in ("missing", "multiple", "symlink", "file"):
            directory = self.root / mode; directory.mkdir()
            bundle = directory / "runtime.exportedBundle"
            if mode == "multiple":
                bundle.mkdir(); (directory / "extra").touch()
            elif mode == "symlink":
                bundle.symlink_to(self.root, target_is_directory=True)
            elif mode == "file":
                bundle.touch()
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                experiment.exported_bundle(directory)

    def test_export_must_succeed_and_source_registration_is_never_imported(self):
        runner = fixtures.Runner([{"runtimes": []}, {"runtimes": [fixtures.RUNTIME]}])
        operations = []
        def execute(args, **kwargs):
            operations.append((args, kwargs))
            bundle = Path(args[-1]) / "runtime.exportedBundle"
            bundle.mkdir(); (bundle / "image.dmg").write_bytes(b"synthetic")
        receipt = {}
        archive = self.root / "runtime.tar"
        experiment.export_runtime(self.root, archive, receipt, run=runner, execute=execute)
        self.assertEqual(len(operations), 1)
        self.assertEqual(operations[0][0][:-2], experiment.DOWNLOAD)
        self.assertEqual(operations[0][1]["timeout"], 360)
        self.assertEqual(operations[0][1]["stdout"], subprocess.DEVNULL)
        self.assertEqual(operations[0][1]["stderr"], subprocess.DEVNULL)
        self.assertEqual(receipt["tar_sha256"], experiment.digest(archive))
        self.assertEqual([r["total"] for r in receipt["runtime_registrations"]], [0, 1])

    def test_nonzero_export_including_70_is_terminal(self):
        for code in (1, 70):
            runner = fixtures.Runner([{"runtimes": []}])
            def execute(args, **kwargs):
                (Path(args[-1]) / "runtime.exportedBundle").mkdir()
                raise subprocess.CalledProcessError(code, args)
            receipt = {}; archive = self.root / (str(code) + ".tar")
            with self.subTest(code=code), self.assertRaises(subprocess.CalledProcessError):
                experiment.export_runtime(self.root, archive, receipt, run=runner, execute=execute)
            self.assertFalse(archive.exists())
            self.assertEqual(receipt["installation_phases"][0]["returncode"], code)

    def adapter(self, inventories, *, observed=None, execute=lambda *a, **kw: None):
        runner = fixtures.Runner(inventories, observed=observed)
        receipt = {}
        adapter = experiment.ImportInstaller(self.bundle(), receipt, run=runner, execute=execute)
        return adapter, receipt, runner

    def test_import_only_on_empty_target_then_all_original_identity_queries(self):
        commands = []
        adapter, receipt, runner = self.adapter([{"runtimes": []}, {"runtimes": [fixtures.RUNTIME]}],
                                               execute=lambda args, **kw: commands.append((args, kw)))
        result = experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")
        self.assertTrue(result["qualified"])
        self.assertTrue(adapter.installed)
        self.assertEqual(commands[0][0][:2], ["xcodebuild", "-importPlatform"])
        self.assertEqual(commands[0][1]["timeout"], 360)
        self.assertEqual([c[0][-1] for c in runner.commands if c[0][:3] == ["xcrun", "simctl", "getenv"]],
                         list(experiment.simulator.EXPECTED_ENVIRONMENT))
        self.assertEqual([r["total"] for r in receipt["runtime_registrations"]], [0, 1])
        self.assertEqual([c[1] for c in runner.commands if c[0][:3] == ["xcrun", "simctl", "getenv"]], [30, 30, 30])

    def test_preinstalled_unavailable_or_duplicate_registration_never_passes(self):
        unavailable = dict(fixtures.RUNTIME, isAvailable=False)
        cases = [[{"runtimes": [fixtures.RUNTIME]}], [{"runtimes": [unavailable]}],
                 [{"runtimes": []}, {"runtimes": [fixtures.RUNTIME, unavailable]}]]
        for index, inventories in enumerate(cases):
            with tempfile.TemporaryDirectory() as directory:
                bundle = Path(directory) / "runtime.exportedBundle"; bundle.mkdir()
                calls = []
                runner = fixtures.Runner(inventories)
                adapter = experiment.ImportInstaller(bundle, {}, run=runner,
                                                      execute=lambda *args, **kw: calls.append(args))
                with self.subTest(index=index), self.assertRaises(ValueError):
                    experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")
                self.assertEqual(len(calls), 1 if index == 2 else 0)
                self.assertFalse(any(c[0][:3] == ["xcrun", "simctl", "create"] for c in runner.commands))

    def test_import_failure_or_wrong_guest_identity_cannot_qualify(self):
        def fail(args, **kwargs): raise subprocess.CalledProcessError(1, args)
        adapter, receipt, _ = self.adapter([{"runtimes": []}], execute=fail)
        with self.assertRaises(subprocess.CalledProcessError):
            experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")
        self.assertFalse(adapter.installed)
        runner = fixtures.Runner([{"runtimes": []}, {"runtimes": [fixtures.RUNTIME]}],
                                 observed={"SIMULATOR_RUNTIME_VERSION": "wrong"})
        adapter = experiment.ImportInstaller(adapter.bundle, {}, run=runner, execute=lambda *a, **kw: None)
        with self.assertRaises(ValueError):
            experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")

    def test_wrong_installed_build_fails_before_pack_or_boot(self):
        wrong = dict(fixtures.RUNTIME, buildversion="wrong")
        with self.assertRaises(ValueError):
            experiment.inspect_runtime({}, "after_export", 1,
                                       run=fixtures.Runner([{"runtimes": [wrong]}]))
        adapter, _, runner = self.adapter([{"runtimes": []}, {"runtimes": [wrong]}])
        with self.assertRaises(ValueError):
            experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")
        self.assertFalse(any(c[0][:3] == ["xcrun", "simctl", "create"] for c in runner.commands))

    def test_import_timeout_does_not_fall_back_or_qualify(self):
        calls = []
        def timeout(args, **kwargs):
            calls.append(args)
            raise subprocess.TimeoutExpired(args, kwargs["timeout"])
        adapter, receipt, runner = self.adapter([{"runtimes": []}], execute=timeout)
        with self.assertRaises(subprocess.TimeoutExpired):
            experiment.simulator.prepare(run=adapter, environment=HOST, machine="arm64")
        self.assertFalse(adapter.installed)
        self.assertEqual(len(calls), 1)
        self.assertEqual(receipt["installation_phases"][0]["outcome"], "failed")
        self.assertEqual(len(runner.commands), 1)

    def test_export_cli_success_is_never_setup_or_release_qualification(self):
        evidence = self.root / "export.json"
        output = self.root / "outputs"
        def export(runner_temp, archive, receipt):
            self.assertEqual(archive.name, f"runtime-export-{HOST['GITHUB_RUN_ID']}-attempt-1.tar")
            receipt["tar_sha256"] = "c" * 64
        env = dict(HOST, RUNNER_TEMP=str(self.root), GITHUB_OUTPUT=str(output))
        with patch.dict(os.environ, env, clear=True), patch.object(experiment.platform, "machine", return_value="arm64"), patch.object(sys, "argv", ["experiment", "export", "--evidence", str(evidence)]), patch.object(experiment, "export_runtime", side_effect=export):
            self.assertEqual(experiment.main(), 0)
        receipt = json.loads(evidence.read_text())
        self.assertEqual(receipt["status"], "passed")
        self.assertFalse(receipt["setup_qualified"])
        self.assertFalse(receipt["release_eligible"])
        self.assertIn("run_attempt=1\n", output.read_text())

    def test_unpack_uses_exact_raw_filename_from_current_run_and_attempt(self):
        evidence = self.root / "unpack.json"
        env = dict(HOST, **PROVENANCE, RUNNER_TEMP=str(self.root))
        with patch.dict(os.environ, env, clear=True), patch.object(experiment.platform, "machine", return_value="arm64"), patch.object(sys, "argv", ["experiment", "unpack", "--evidence", str(evidence)]), patch.object(experiment, "inspect_runtime"), patch.object(experiment, "unpack_bundle") as unpack:
            self.assertEqual(experiment.main(), 0)
            unpack.assert_called_once_with(
                self.root / "runtime-input" / f"runtime-export-{HOST['GITHUB_RUN_ID']}-attempt-1.tar",
                self.root / "runtime-import-bundle", PROVENANCE["EXPORT_TAR_SHA256"])
        self.assertFalse(json.loads(evidence.read_text())["setup_qualified"])

    def test_stale_provenance_cli_fails_before_extraction(self):
        evidence = self.root / "unpack.json"
        env = dict(HOST, **PROVENANCE, RUNNER_TEMP=str(self.root)); env["EXPORT_RUN_ATTEMPT"] = "2"
        with patch.dict(os.environ, env, clear=True), patch.object(experiment.platform, "machine", return_value="arm64"), patch.object(sys, "argv", ["experiment", "unpack", "--evidence", str(evidence)]), patch.object(experiment, "unpack_bundle") as unpack:
            self.assertEqual(experiment.main(), 1)
            unpack.assert_not_called()
        self.assertFalse(json.loads(evidence.read_text())["setup_qualified"])

    def test_nonhosted_cli_fails_before_export_or_unpack(self):
        for mode in ("export", "unpack", "qualify"):
            evidence = self.root / (mode + ".json")
            with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["experiment", mode, "--evidence", str(evidence)]), patch.object(experiment, "export_runtime") as export, patch.object(experiment, "unpack_bundle") as unpack:
                self.assertEqual(experiment.main(), 1)
                export.assert_not_called(); unpack.assert_not_called()
            receipt = json.loads(evidence.read_text())
            self.assertFalse(receipt["release_eligible"])
            self.assertFalse(receipt["setup_qualified"])
            self.assertEqual(receipt["status"], "failed")


class WorkflowTests(unittest.TestCase):
    def test_only_isolated_branch_can_transfer_and_qualify_on_two_hosts(self):
        path = Path(__file__).resolve().parents[1] / ".github/workflows/ios-runtime-install-experiment.yml"
        workflow = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                              "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(path)], text=True))
        self.assertEqual(workflow.get("on", workflow.get("true")),
                         {"workflow_dispatch": None})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(set(workflow["jobs"]), {"export-runtime", "import-runtime"})
        exporter, importer = (workflow["jobs"][key] for key in ("export-runtime", "import-runtime"))
        self.assertEqual(importer["needs"], "export-runtime")
        self.assertNotIn("if", importer)  # Implicit success dependency; no failed-export fallback.
        for job, minutes, count in ((exporter, 30, 5), (importer, 45, 6)):
            self.assertEqual(job["runs-on"], "xcode-27")
            self.assertEqual(job["timeout-minutes"], minutes)
            for key in ("environment", "permissions", "continue-on-error"):
                self.assertNotIn(key, job)
            steps = job["steps"]; self.assertEqual(len(steps), count)
            self.assertIs(steps[0]["with"]["persist-credentials"], False)
            self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', steps[1]["run"])
            self.assertIn("= 'Xcode 27.0'", steps[1]["run"])
            self.assertIn("= 'Build version 27A266a'", steps[1]["run"])
            self.assertEqual(job["env"]["DEVELOPER_DIR"], "/Applications/Xcode_27.0.app/Contents/Developer")
            self.assertTrue(all("continue-on-error" not in step for step in steps))
            self.assertEqual(steps[-1]["if"], "always()")
        upload = exporter["steps"][3]
        self.assertEqual(upload["timeout-minutes"], 10)
        self.assertEqual(upload["with"]["path"], "${{ runner.temp }}/runtime-export-${{ github.run_id }}-attempt-${{ github.run_attempt }}.tar")
        self.assertEqual(upload["with"]["retention-days"], 1)
        self.assertIs(upload["with"]["archive"], False)
        self.assertNotIn("name", upload["with"])
        self.assertNotIn("compression-level", upload["with"])
        self.assertNotIn("overwrite", upload["with"])
        download = importer["steps"][2]
        self.assertEqual(download["timeout-minutes"], 10)
        self.assertEqual(download["with"]["artifact-ids"], "${{ needs.export-runtime.outputs.artifact_id }}")
        self.assertEqual(download["with"]["digest-mismatch"], "error")
        self.assertIs(download["with"]["skip-decompress"], True)
        self.assertNotIn("name", download["with"]); self.assertNotIn("pattern", download["with"])
        self.assertEqual([s["timeout-minutes"] for s in importer["steps"][3:5]], [5, 25])
        self.assertIn("experiment-ios-runtime-import.py unpack", importer["steps"][3]["run"])
        self.assertIn("experiment-ios-runtime-import.py qualify", importer["steps"][4]["run"])
        self.assertEqual(importer["steps"][-1]["with"]["path"].splitlines(),
                         ["${{ runner.temp }}/runtime-unpack-receipt.json", "${{ runner.temp }}/runtime-import-receipt.json"])
        for key in ("artifact_id", "artifact_digest", "tar_sha256", "source_sha", "run_id", "run_attempt"):
            self.assertIn(key, exporter["outputs"])
            self.assertEqual(importer["env"]["EXPORT_" + key.upper()], "${{ needs.export-runtime.outputs." + key + " }}")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Portable contracts for the isolated runtime installation experiment."""

import importlib.util
import json
from pathlib import Path
import subprocess
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


class ImportTests(unittest.TestCase):
    def test_workflow_cannot_run_as_release_or_expand_artifact_scope(self):
        workflow_path = Path(__file__).resolve().parents[1] / ".github/workflows/ios-runtime-install-experiment.yml"
        workflow = json.loads(subprocess.check_output([
            "ruby", "-ryaml", "-rjson", "-e",
            "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json",
            str(workflow_path)], text=True))
        # Ruby's YAML 1.1 parser represents the GitHub `on` key as true.
        self.assertEqual(workflow.get("on", workflow.get("true")),
                         {"push": {"branches": ["codex/pr152-simulator-diagnostics-20261114"]}})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(set(workflow["jobs"]), {"exported-runtime"})
        job = workflow["jobs"]["exported-runtime"]
        self.assertEqual(job["runs-on"], "xcode-27")
        self.assertEqual(job["timeout-minutes"], 30)
        self.assertNotIn("environment", job)
        self.assertNotIn("permissions", job)
        self.assertNotIn("continue-on-error", job)
        steps = job["steps"]
        self.assertEqual(len(steps), 4)
        self.assertIs(steps[0]["with"]["persist-credentials"], False)
        verify = steps[1]["run"]
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', verify)
        self.assertIn("git diff --exit-code --quiet", verify)
        self.assertIn("= 'Xcode 27.0'", verify)
        self.assertIn("= 'Build version 27A266a'", verify)
        self.assertEqual(steps[2]["timeout-minutes"], 25)
        self.assertEqual(steps[2]["run"], 'python3 -B scripts/experiment-ios-runtime-import.py '
                         '--evidence "$RUNNER_TEMP/runtime-install-experiment.json"')
        self.assertNotIn("continue-on-error", steps[2])
        self.assertEqual(steps[3]["if"], "always()")
        self.assertEqual(steps[3]["with"]["path"], "${{ runner.temp }}/runtime-install-experiment.json")
        self.assertEqual(steps[3]["with"]["if-no-files-found"], "error")

    def test_export_import_share_original_budget_and_preserve_signed_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            now = [100.0]
            calls = []
            def execute(args, **kwargs):
                calls.append((args, kwargs))
                if "-exportPath" in args:
                    (root / "iossimulator_23F77.exportedBundle").mkdir()
                    now[0] += 120
            phases = []
            experiment.install_exported_runtime(root, phases, timeout=360, inspect_before_import=lambda **kw: None,
                                                execute=execute, clock=lambda: now[0])
            self.assertEqual(calls[0][0], experiment.DOWNLOAD + ["-exportPath", directory])
            self.assertEqual(calls[1][0], ["xcodebuild", "-importPlatform",
                                           str(root / "iossimulator_23F77.exportedBundle")])
            self.assertEqual([c[1]["timeout"] for c in calls], [360, 240])
            self.assertTrue(all(c[1]["check"] for c in calls))
            self.assertTrue(all(c[1]["stdout"] == subprocess.DEVNULL and
                                c[1]["stderr"] == subprocess.DEVNULL for c in calls))
            self.assertEqual([p["outcome"] for p in phases], ["passed", "passed"])

    def test_nonzero_export_even_with_bundle_never_imports(self):
        for code in (1, 70):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                calls = []
                def execute(args, **kwargs):
                    calls.append(args)
                    (root / "runtime.exportedBundle").mkdir()
                    raise subprocess.CalledProcessError(code, args)
                with self.assertRaises(subprocess.CalledProcessError):
                    experiment.install_exported_runtime(root, [], timeout=360, inspect_before_import=lambda **kw: None, execute=execute)
                self.assertEqual(len(calls), 1)

    def test_export_uses_entire_budget_so_import_is_not_started(self):
        with tempfile.TemporaryDirectory() as directory:
            now = [0]
            def execute(args, **kwargs):
                (Path(directory) / "runtime.exportedBundle").mkdir()
                now[0] = 360
            with self.assertRaises(subprocess.TimeoutExpired):
                experiment.install_exported_runtime(Path(directory), [], timeout=360, inspect_before_import=lambda **kw: None,
                                                    execute=execute, clock=lambda: now[0])

    def test_ambiguous_missing_wrong_and_symlink_exports_rejected(self):
        for mode in ("missing", "multiple", "file", "symlink", "wrong"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                bundle = root / "runtime.exportedBundle"
                if mode == "multiple":
                    bundle.mkdir()
                    (root / "other.exportedBundle").mkdir()
                elif mode == "file":
                    bundle.touch()
                elif mode == "symlink":
                    bundle.symlink_to(root, target_is_directory=True)
                elif mode == "wrong":
                    (root / "runtime.dmg").touch()
                with self.assertRaises(ValueError):
                    experiment.exported_bundle(root)

    def test_import_failure_never_returns_success(self):
        with tempfile.TemporaryDirectory() as directory:
            def execute(args, **kwargs):
                if "-exportPath" in args:
                    (Path(directory) / "runtime.exportedBundle").mkdir()
                else:
                    raise subprocess.CalledProcessError(1, args)
            phases = []
            with self.assertRaises(subprocess.CalledProcessError):
                experiment.install_exported_runtime(Path(directory), phases, timeout=360, inspect_before_import=lambda **kw: None, execute=execute)
            self.assertEqual([p["outcome"] for p in phases], ["passed", "failed"])

    def prepare(self, runner, **arguments):
        with tempfile.TemporaryDirectory() as directory:
            adapter = experiment.ExportInstaller(directory, run=runner)
            options = {"environment": fixtures.HOST, "machine": "arm64"}
            options.update(arguments)
            with patch.object(experiment, "install_exported_runtime") as install:
                result = experiment.experiment(adapter, **options)
            self.assertEqual(list(Path(directory).iterdir()), [])
            return result, install

    def test_success_requires_export_import_and_all_original_identity_reads(self):
        runner = fixtures.Runner([{"runtimes": []}, {"runtimes": [fixtures.RUNTIME]}])
        result, install = self.prepare(runner)
        self.assertTrue(result["setup_qualified"])
        self.assertFalse(result["release_eligible"])
        install.assert_called_once()
        self.assertEqual(result["qualification"]["observed_environment"],
                         experiment.simulator.EXPECTED_ENVIRONMENT)
        self.assertEqual([args[-1] for args, timeout in runner.commands
                          if args[:3] == ["xcrun", "simctl", "getenv"]],
                         list(experiment.simulator.EXPECTED_ENVIRONMENT))

    def test_preinstalled_runtime_is_inconclusive_without_creation_or_install(self):
        runner = fixtures.Runner()
        result, install = self.prepare(runner)
        self.assertFalse(result["setup_qualified"])
        self.assertEqual(len(runner.commands), 1)
        install.assert_not_called()

    def test_nonhosted_or_injected_identity_rejected_before_inventory_or_install(self):
        for options in ({"environment": {}}, {"machine": "x86_64"},
                        {"environment": dict(fixtures.HOST, SIMCTL_CHILD_SIMULATOR_RUNTIME_VERSION="26.5")}):
            with self.subTest(options=options):
                runner = fixtures.Runner()
                result, install = self.prepare(runner, **options)
                self.assertFalse(result["setup_qualified"])
                self.assertEqual(runner.commands, [])
                install.assert_not_called()

    def test_wrong_installed_build_or_guest_identity_cannot_pass(self):
        for runtime, observed in ((dict(fixtures.RUNTIME, buildversion="wrong"), None),
                                  (fixtures.RUNTIME, {"SIMULATOR_RUNTIME_VERSION": "wrong"})):
            runner = fixtures.Runner([{"runtimes": []}, {"runtimes": [runtime]}], observed=observed)
            result, install = self.prepare(runner)
            self.assertFalse(result["setup_qualified"])
            install.assert_called_once()

    def test_failure_artifact_omits_exception_contents(self):
        def runner(*args, **kwargs):
            raise ValueError("private path and raw command content")
        result, _ = self.prepare(runner)
        self.assertEqual(result["failure_kind"], "ValueError")
        self.assertNotIn("private", json.dumps(result))

    def test_export_registration_prevents_import(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            def execute(args, **kwargs):
                calls.append(args)
                (Path(directory) / "runtime.exportedBundle").mkdir()
            def registered(**kwargs):
                raise ValueError("Export registered the runtime")
            with self.assertRaises(ValueError):
                experiment.install_exported_runtime(Path(directory), [], timeout=360,
                                                    inspect_before_import=registered, execute=execute)
            self.assertEqual(len(calls), 1)

    def test_unavailable_preexisting_and_duplicate_imported_records_fail(self):
        unavailable = dict(fixtures.RUNTIME, isAvailable=False)
        for inventories in ([{"runtimes": [unavailable]}],
                            [{"runtimes": []}, {"runtimes": [fixtures.RUNTIME, unavailable]}]):
            result, _ = self.prepare(fixtures.Runner(inventories))
            self.assertFalse(result["setup_qualified"])
            self.assertFalse(result["release_eligible"])
            counts = result["runtime_registrations"][-1]
            self.assertEqual(counts["unavailable"], 1)

    def test_full_adapter_observes_zero_zero_one_without_changing_qualification(self):
        runner = fixtures.Runner([{"runtimes": []}, {"runtimes": []},
                                  {"runtimes": [fixtures.RUNTIME]}])
        installer = experiment.install_exported_runtime
        operations = []
        def execute(args, **kwargs):
            operations.append(args[:2])
            if "-exportPath" in args:
                (Path(args[-1]) / "runtime.exportedBundle").mkdir()
        def install(*args, **kwargs):
            return installer(*args, **kwargs, execute=execute)
        with tempfile.TemporaryDirectory() as directory, patch.object(
                experiment, "install_exported_runtime", side_effect=install):
            result = experiment.experiment(experiment.ExportInstaller(directory, run=runner),
                                           environment=fixtures.HOST, machine="arm64")
        self.assertTrue(result["setup_qualified"])
        self.assertEqual([r["total"] for r in result["runtime_registrations"]], [0, 0, 1])
        self.assertEqual(operations, [["xcodebuild", "-downloadPlatform"],
                                      ["xcodebuild", "-importPlatform"]])


if __name__ == "__main__":
    unittest.main()

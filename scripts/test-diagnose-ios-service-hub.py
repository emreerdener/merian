#!/usr/bin/env python3
"""Provenance, privacy and nonqualification boundaries for the host experiment."""
import copy
import importlib.util
import os
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / name)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


d = load("diagnose-ios-service-hub.py")
fixtures = load("test-discover-ios27-simulator.py")
ENV = dict(fixtures.HOST, GITHUB_REPOSITORY="emreerdener/merian", GITHUB_WORKSPACE="/workspace",
           IOS_IDENTITY_TEST_OUTCOME="success")


def remote():
    values = {
        f"actions/runs/{d.RUN}": {"id": d.RUN, "head_sha": d.SOURCE, "run_attempt": 1,
                                  "event": "workflow_dispatch", "path": ".github/workflows/ios-build-and-test.yml"},
        f"actions/jobs/{d.BUILD_JOB}": {"id": d.BUILD_JOB, "run_id": d.RUN, "head_sha": d.SOURCE,
                                       "name": "Compile and inventory iOS unit tests",
                                       "run_attempt": 1, "status": "completed", "conclusion": "success"},
    }
    for identifier, name, size, sha in d.ARTIFACTS.values():
        values[f"actions/artifacts/{identifier}"] = {
            "id": identifier, "name": name, "size_in_bytes": size, "expired": False, "digest": "sha256:" + sha,
            "workflow_run": {"id": d.RUN, "head_sha": d.SOURCE, "repository_id": 1174814681,
                             "head_repository_id": 1174814681}}
    return values


def receipt():
    return d.verify_origin(ENV, remote().__getitem__)


class HostDiagnosticTests(unittest.TestCase):
    def test_origin_and_execution_are_distinct_and_never_qualify(self):
        before = dict(ENV)
        r = receipt()
        self.assertEqual(r["product_provenance"]["source_sha"], d.SOURCE)
        self.assertEqual(r["execution_provenance"]["harness_sha"], ENV["GITHUB_SHA"])
        self.assertNotEqual(r["execution_provenance"]["run_id"], d.RUN)
        self.assertIs(r["qualified"], False)
        self.assertIs(r["release_eligible"], False)
        self.assertEqual(ENV, before)

    def test_wrong_execution_context_rejected(self):
        for key, value in (("GITHUB_REPOSITORY", "other/repo"), ("GITHUB_SHA", "bad"),
                           ("GITHUB_SHA", d.SOURCE),
                           ("GITHUB_RUN_ID", str(d.RUN)), ("GITHUB_RUN_ATTEMPT", "0"),
                           ("RUNNER_ENVIRONMENT", "self-hosted")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                d.verify_origin(dict(ENV, **{key: value}), remote().__getitem__)

    def test_wrong_remote_run_or_builder_rejected(self):
        for kind, key, value in (("runs", "head_sha", "b" * 40), ("runs", "run_attempt", 2),
                                 ("runs", "path", "other.yml"), ("runs", "event", "push"),
                                 ("jobs", "conclusion", "failure"), ("jobs", "status", "in_progress"),
                                 ("jobs", "head_sha", "b" * 40), ("jobs", "run_id", 999),
                                 ("jobs", "name", "other job")):
            values = remote()
            values[f"actions/{kind}/{d.RUN if kind == 'runs' else d.BUILD_JOB}"][key] = value
            with self.subTest(kind=kind, key=key), self.assertRaises(ValueError):
                d.verify_origin(ENV, values.__getitem__)

    def test_wrong_artifact_identity_digest_and_expiry_rejected(self):
        for artifact in d.ARTIFACTS.values():
            for key, value in (("id", 1), ("name", "other"), ("size_in_bytes", 1),
                               ("expired", True), ("digest", "sha256:" + "0" * 64)):
                values = remote(); values[f"actions/artifacts/{artifact[0]}"][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    d.verify_origin(ENV, values.__getitem__)
            for key, value in (("id", 1), ("head_sha", "b" * 40), ("repository_id", 1), ("head_repository_id", 1)):
                values = remote(); values[f"actions/artifacts/{artifact[0]}"]["workflow_run"][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    d.verify_origin(ENV, values.__getitem__)

    def test_receipt_cannot_claim_release_or_change_provenance(self):
        mutations = [lambda r: r.update(qualified=True), lambda r: r.update(release_eligible=True),
                     lambda r: r.update(status="passed"), lambda r: r.update(secret="private-sentinel"),
                     lambda r: r["product_provenance"].update(products_sha256="0" * 64),
                     lambda r: r["product_provenance"].update(run_attempt=2),
                     lambda r: r["execution_provenance"].update(run_id=d.RUN),
                     lambda r: r["product_provenance"].update(remote_metadata_verified=False)]
        for mutate in mutations:
            r = receipt(); mutate(r)
            with self.assertRaises(ValueError): d.validate_receipt(r, ENV)

    def input_fixture(self, directory, *, path="tests.xctestproducts/test.bin", **changes):
        product = directory / "ios-unit-products.tar.gz"
        with tarfile.open(product, "w:gz") as archive:
            root = tarfile.TarInfo("tests.xctestproducts"); root.type = tarfile.DIRTYPE; archive.addfile(root)
            item = tarfile.TarInfo(path); item.size = 4; archive.addfile(item, io.BytesIO(b"test"))
        product_hash = d.digest(product)
        plan = {"source_sha": d.SOURCE, "schema_version": 4, "origin_run_id": str(d.RUN), "build_attempt": "1",
                "build_workspace": ENV["GITHUB_WORKSPACE"], "products_sha256": product_hash, **changes}
        plan_path = directory / "ios-unit-plan.json"; plan_path.write_text(json.dumps(plan))
        return d.digest(plan_path), product_hash

    def test_exact_products_unpack_without_spoofing_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory)
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                r = d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertTrue(r["product_provenance"]["unpack_verified"])
                self.assertEqual((directory / "out/tests.xctestproducts/test.bin").read_bytes(), b"test")
                self.assertIs(r["qualified"], False)

    def test_modified_product_rejected_before_unpack(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory)
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                (directory / "ios-unit-products.tar.gz").write_bytes(b"changed")
                with self.assertRaises(ValueError): d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertFalse((directory / "out").exists())

    def test_wrong_source_workspace_and_attempt_rejected(self):
        for field, value in (("source_sha", "b" * 40), ("origin_run_id", "9"), ("build_attempt", "2"), ("schema_version", 3), ("schema_version", True),
                             ("build_workspace", "/different")):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); hashes = self.input_fixture(directory, **{field: value})
                with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                    with self.subTest(field=field), self.assertRaises(ValueError):
                        d.verify_inputs(receipt(), directory, directory / "out", ENV)
                    self.assertFalse((directory / "out").exists())

    def test_unsafe_archive_rejected_by_original_unpacker(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); hashes = self.input_fixture(directory, path="tests.xctestproducts/../escape")
            with patch.multiple(d, PLAN_HASH=hashes[0], PRODUCT_HASH=hashes[1]):
                with self.assertRaises(ValueError): d.verify_inputs(receipt(), directory, directory / "out", ENV)
                self.assertFalse((directory / "out").exists())

    def test_process_filter_never_retains_raw_paths_or_other_processes(self):
        raw = b"1 0 0 /private-sentinel/DTServiceHub\n2 1 501 /secret/path/unrelated\n3 2 501 secret-command --token secret\n"
        result = d.process_records(raw)
        self.assertEqual(result["records"], [{"role": "DTServiceHub", "pid": 1, "ppid": 0, "numeric_uid": 0}])
        self.assertNotIn("secret", json.dumps(result)); self.assertNotIn("private", json.dumps(result))
        self.assertTrue(d.process_records(b"1 0 0 DTServiceHub\n" * 65)["capped"])
        self.assertEqual(len(d.process_records(b"1 0 0 DTServiceHub\n" * 65)["records"]), 64)

    def test_all_supported_process_roles_are_retained_without_paths(self):
        raw = "\n".join(f"{i + 1} 1 501 /private-sentinel/{name}" for i, name in enumerate(d.ROLES))
        result = d.process_records(raw.encode())
        self.assertEqual({r["role"] for r in result["records"]}, set(d.ROLES.values()))
        self.assertNotIn("private-sentinel", json.dumps(result))

    def identity_fixture(self, directory):
        identity = directory / "identity"; identity.mkdir()
        fixtures.DiscoveryTests().fixture(identity)
        preparation = identity / "preparation.json"
        prepared = json.loads(preparation.read_text()); prepared["schema_version"] = 1
        preparation.write_text(json.dumps(prepared))
        payload = identity / "attachments/identity.txt"
        value = json.loads(payload.read_text()); value["model_identifier"] = "iPhone19,2"
        payload.write_text(json.dumps(value))
        r = receipt(); r["product_provenance"]["unpack_verified"] = True
        return r

    def test_snapshot_retains_only_scoped_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.identity_fixture(directory)
            calls = []
            def probe(args, **bounds):
                calls.append((args, bounds))
                if args[0] == "ps":
                    raw = b"1 0 501 /private-sentinel/DTServiceHub\n2 1 501 /private-sentinel/unrelated\n"
                elif "runtimes" in args:
                    raw = json.dumps({"runtimes": [dict(fixtures.RUNTIME, name="private-sentinel")]}).encode()
                else:
                    raw = json.dumps({"devices": {fixtures.discovery.RUNTIME: [
                        {"udid": fixtures.DEVICE, "state": "Booted", "name": "private-sentinel"},
                        {"udid": "other", "state": "Shutdown", "name": "private-sentinel"}]}}).encode()
                return {"outcome": "passed", "direct_process_reaped": True}, raw
            with patch.object(d, "module", return_value=fixtures.discovery), \
                    patch.object(fixtures.discovery.simulator, "diagnostic_process", side_effect=probe):
                result = d.snapshot(directory, "after_test", dict(ENV, RUNNER_TEMP=temporary))
            self.assertEqual(result["target_runtime"], {"status": "available"})
            self.assertEqual(result["owned_device"], {"status": "observed", "state": "Booted"})
            self.assertIs(type(result["current_uid_is_root"]), bool)
            self.assertIs(type(result["free_mib"]), int)
            self.assertNotIn("private-sentinel", json.dumps(result))
            self.assertNotIn(fixtures.DEVICE, json.dumps(result))
            self.assertEqual(len(calls), 3)
            self.assertTrue(all(bounds == {"capture": "stdout", "limit": 512 * 1024, "timeout": 5}
                                for _, bounds in calls))

    def test_probe_failure_retains_no_partial_or_error_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            for outcome in ("timeout", "oversized", "nonzero"):
                with patch.object(d, "module", return_value=fixtures.discovery), \
                        patch.object(fixtures.discovery.simulator, "diagnostic_process", return_value=(
                            {"outcome": outcome, "direct_process_reaped": True}, b"private-sentinel")):
                    result = d.snapshot(Path(temporary), "after_test", dict(ENV, RUNNER_TEMP=temporary))
                self.assertEqual(result["processes"], {"status": "unavailable"})
                self.assertEqual(result["target_runtime"], {"status": "unavailable"})
                self.assertNotIn("private-sentinel", json.dumps(result))

    def test_before_snapshots_add_no_simulator_client(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); self.identity_fixture(directory)
            for phase in ("before_prepare", "before_test"):
                with patch.object(d, "module", return_value=fixtures.discovery), \
                        patch.object(fixtures.discovery.simulator, "diagnostic_process", return_value=(
                            {"outcome": "passed", "direct_process_reaped": True}, b"")) as probe:
                    result = d.snapshot(directory, phase, dict(ENV, RUNNER_TEMP=temporary))
                self.assertEqual(probe.call_count, 1)
                self.assertEqual(probe.call_args.args[0][0], "ps")
                self.assertEqual(result["target_runtime"]["status"],
                                 "not_probed" if phase == "before_prepare" else "verified_at_preparation")

    def test_missing_snapshot_never_changes_nonqualification(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); r = self.identity_fixture(directory)
            self.assertFalse((directory / "before_prepare.json").exists())
            result = d.finish(r, directory, ENV)
            self.assertIs(result["qualified"], False)
            self.assertIs(result["release_eligible"], False)

    def test_success_is_execution_observation_not_product_qualification(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); r = self.identity_fixture(directory)
            result = d.finish(r, directory, ENV)
            self.assertEqual(result["status"], "identity_observed")
            self.assertIs(result["qualified"], False); self.assertIs(result["release_eligible"], False)
            self.assertNotIn("methods", result); self.assertFalse((directory / "qualification.json").exists())
            self.assertEqual(result["execution_provenance"]["harness_sha"], ENV["GITHUB_SHA"])

    def test_failed_step_stale_identity_or_wrong_guest_cannot_pass(self):
        for kind in ("failed_step", "stale_identity", "wrong_guest", "skipped", "unverified_products"):
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary); r = self.identity_fixture(directory); env = dict(ENV)
                if kind == "failed_step": env["IOS_IDENTITY_TEST_OUTCOME"] = "failure"
                if kind == "unverified_products": r["product_provenance"]["unpack_verified"] = False
                if kind in ("stale_identity", "wrong_guest", "skipped"):
                    file, key, value = {"stale_identity": ("preparation.json", "source_sha", d.SOURCE),
                                        "wrong_guest": ("attachments/identity.txt", "model_identifier", "iPhone99,1"),
                                        "skipped": ("summary.json", "skippedTests", 1)}[kind]
                    path = directory / "identity" / file; data = json.loads(path.read_text()); data[key] = value
                    path.write_text(json.dumps(data))
                with self.subTest(kind=kind), self.assertRaises(ValueError): d.finish(r, directory, env)

    def suite_fixture(self, directory):
        r = self.identity_fixture(directory)
        identity = d.finish(r, directory, ENV)
        (directory / "diagnostic.json").write_text(json.dumps(identity))
        helpers = load("test-ios-unit-shards.py")
        methods = sorted(d.SUITE_ARGUMENTS)
        all_methods = methods + ["merianTests/Other/testControl"]
        plan = {"source_sha": d.SOURCE, "schema_version": 4, "origin_run_id": str(d.RUN), "build_attempt": "1",
                "build_workspace": ENV["GITHUB_WORKSPACE"], "products_sha256": d.PRODUCT_HASH,
                "inventory": sorted(all_methods)}
        inputs = directory / "inputs"; inputs.mkdir()
        (inputs / "ios-unit-plan.json").write_text(json.dumps(plan))
        plan_pin = patch.object(d, "PLAN_HASH", d.digest(inputs / "ios-unit-plan.json"))
        plan_pin.start(); self.addCleanup(plan_pin.stop)
        # The identity receipt must retain the same independently pinned plan hash.
        identity["product_provenance"]["plan_sha256"] = d.PLAN_HASH
        (directory / "diagnostic.json").write_text(json.dumps(identity))
        selected = directory / "suite"; selected.mkdir()
        (selected / "enumeration.txt").write_text(helpers.enumeration_text(methods, full_inventory=all_methods))
        tree = helpers.tree_for(methods)
        tree["devices"][0]["deviceId"] = fixtures.DEVICE
        for suite in tree["testNodes"][0]["children"][0]["children"]:
            for case in suite["children"]:
                method = d.module("ios-unit-shards.py").canonical("merianTests/" + case["nodeIdentifier"])
                case["children"] = [{"nodeType": "Arguments", "result": "Passed",
                    "nodeIdentifierURL": case["nodeIdentifierURL"] + "?args=" + format(i, "02x")}
                    for i in range(d.SUITE_ARGUMENTS[method])]
        for suite in d.SUITES:
            name = suite.split("/")[1]
            scoped_methods = [m for m in methods if m.startswith(suite + "/")]
            scoped = copy.deepcopy(tree)
            scoped["testNodes"][0]["children"][0]["children"] = [n for n in
                scoped["testNodes"][0]["children"][0]["children"]
                if any(case["nodeIdentifier"].startswith(name + "/") for case in n["children"])]
            evidence = selected / name; evidence.mkdir()
            (evidence / "tests.json").write_text(json.dumps(scoped))
            (evidence / "summary.json").write_text(json.dumps(helpers.summary_for(scoped_methods)))
        env = dict(ENV, IOS_SAVED_MODEL_OUTCOME="success", IOS_COMPLETION_OUTCOME="success",
                   IOS_RESUME_OUTCOME="success", IOS_SUITE_ENUMERATION_OUTCOME="success")
        return inputs, env

    def test_replay_scope_has_independent_literal_methods_and_argument_counts(self):
        self.assertEqual(d.SUITE_ARGUMENTS, {
            'merianTests/CaptureVideoSavedModelTests/failedRefreshClearsRowsSelectionAndCannotInventAbsenceOrActions': 0,
            'merianTests/CaptureVideoSavedModelTests/inertFactoryKeepsUnknownUploadWithoutExecutionOrFileRepair': 0,
            'merianTests/CaptureVideoSavedModelTests/latePageCannotRestorePrivateState(_:)': 3,
            'merianTests/CaptureVideoSavedModelTests/lateResumeCannotReopenClosedPresentation': 0,
            'merianTests/CaptureVideoSavedModelTests/onlyExplicitSelectionAndFinalTapOpenExactOriginalBeforeTask': 0,
            'merianTests/CaptureVideoSavedModelTests/realPagesReplaceAndForwardOpaqueCursorWithoutAutomaticSelection': 0,
            'merianTests/ObservationVideoCompletionTests/changedScopeCannotAppendOrRetire(reason:)': 9,
            'merianTests/ObservationVideoCompletionTests/exactRequestBindingRejectsIdentityDigestManifestAndVersionDrift': 0,
            'merianTests/ObservationVideoCompletionTests/receivedResultSettlesCancelledRunningOrHeldWork(audio:held:)': 4,
            'merianTests/ObservationVideoCompletionTests/syncedLegacyUppercaseParentRequiresExactStoredParent(forgedLowerParent:)': 2,
            'merianTests/ObservationVideoCompletionTests/syncedResultMustBeByteIdentical(conflict:)': 3,
            'merianTests/ObservationVideoCompletionTests/syncedSettlementReaderRejectsUnprovenOrChangedWork(reason:)': 13,
            'merianTests/ObservationVideoCompletionTests/uncertainSaveReopensWithOnlySettlementOrReceipt(committed:)': 2,
            'merianTests/ObservationVideoCompletionTests/unconsumedAndStaleSnapshotsCannotComplete': 0,
            'merianTests/ObservationVideoResumeSubmissionTests/explicitContinuationKeepsOriginalChildAndPermittedPhase(_:)': 8,
            'merianTests/ObservationVideoResumeSubmissionTests/incompletePreparationDoesNotRegenerateFiles': 0,
            'merianTests/ObservationVideoResumeSubmissionTests/nonExecutableReservationStatesRemainHeldAfterReopen(_:)': 4,
            'merianTests/ObservationVideoResumeSubmissionTests/throwingStageCannotReturnDispatchEvenAfterCommit(_:commit:)': 4,
            'merianTests/ObservationVideoResumeSubmissionTests/uncertainAttemptNeverAdvancesOrRearms(_:)': 4,
        })

    def test_suite_cli_failure_is_nonqualifying_and_does_not_overwrite_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            identity = directory / "diagnostic.json"; identity.write_text('{"sentinel": "preserve"}')
            result = subprocess.run([__import__("sys").executable, "-B", str(ROOT / "scripts/diagnose-ios-service-hub.py"),
                "finish-suite", "--directory", str(directory), "--inputs", str(directory / "missing")],
                env=dict(os.environ, **ENV), capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0); self.assertNotIn("Traceback", result.stderr)
            evidence = json.loads((directory / "suite-diagnostic.json").read_text())
            self.assertEqual(evidence["kind"], "retained_product_suite_diagnostic")
            self.assertEqual(evidence["status"], "failed")
            self.assertFalse(evidence["qualified"]); self.assertFalse(evidence["release_eligible"])
            self.assertEqual(identity.read_text(), '{"sentinel": "preserve"}')

    def test_complete_retained_suite_is_fifty_six_leaves_and_never_qualifies(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); inputs, env = self.suite_fixture(directory)
            original = dict(env)
            preflight = d.suite_diagnostic(directory, inputs, env, completed=False)
            self.assertEqual(preflight["status"], "inventory_verified")
            self.assertNotIn("methods", preflight)
            result = d.suite_diagnostic(directory, inputs, env, completed=True)
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["kind"], "retained_product_suite_diagnostic")
            self.assertEqual(len(result["methods"]), 19); self.assertEqual(result["parameter_leaves"], 56)
            self.assertFalse(result["qualified"]); self.assertFalse(result["release_eligible"])
            self.assertEqual(env, original)
            self.assertEqual(result["product_provenance"]["source_sha"], d.SOURCE)
            self.assertEqual(result["execution_provenance"]["harness_sha"], env["GITHUB_SHA"])
            self.assertFalse((directory / "qualification.json").exists())

    def test_separate_suite_results_cannot_be_substituted_or_combined(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); inputs, env = self.suite_fixture(directory)
            target = directory / "suite/CaptureVideoSavedModelTests/tests.json"
            other = directory / "suite/ObservationVideoCompletionTests/tests.json"
            target.write_bytes(other.read_bytes())
            with self.assertRaises(ValueError):
                d.suite_diagnostic(directory, inputs, env, completed=True)

    def test_suite_failure_skip_or_unrun_step_cannot_be_reported_passed(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); inputs, env = self.suite_fixture(directory)
            for key in ("IOS_SAVED_MODEL_OUTCOME", "IOS_COMPLETION_OUTCOME", "IOS_RESUME_OUTCOME",
                        "IOS_SUITE_ENUMERATION_OUTCOME", "IOS_IDENTITY_TEST_OUTCOME"):
                for value in ("failure", "skipped", "cancelled", ""):
                    with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                        d.suite_diagnostic(directory, inputs, dict(env, **{key: value}), completed=True)
            path = directory / "suite/ObservationVideoCompletionTests/summary.json"; original = json.loads(path.read_text())
            for change in ({"result": "Failed"}, {"failedTests": 1}, {"skippedTests": 1}, {"passedTests": 1}):
                path.write_text(json.dumps(dict(original, **change)))
                with self.assertRaises(ValueError): d.suite_diagnostic(directory, inputs, env, completed=True)

    def test_suite_rejects_wrong_argument_partition_even_if_total_remains_fifty_six(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); inputs, env = self.suite_fixture(directory)
            path = directory / "suite/ObservationVideoCompletionTests/tests.json"; original = json.loads(path.read_text())
            for mode in ("missing", "extra", "repartition", "failed", "duplicate"):
                tree = copy.deepcopy(original); cases = [case for suite in tree["testNodes"][0]["children"][0]["children"]
                     for case in suite["children"] if len(case.get("children", [])) >= 2]
                if mode in ("missing", "repartition"): cases[0]["children"].pop()
                if mode in ("extra", "repartition"):
                    cases[1]["children"].append({"nodeType": "Arguments", "result": "Passed",
                        "nodeIdentifierURL": cases[1]["nodeIdentifierURL"] + "?args=ff"})
                if mode == "failed": cases[0]["children"][0]["result"] = "Failed"
                if mode == "duplicate": cases[0]["children"][1] = copy.deepcopy(cases[0]["children"][0])
                path.write_text(json.dumps(tree))
                with self.subTest(mode=mode), self.assertRaises(ValueError):
                    d.suite_diagnostic(directory, inputs, env, completed=True)

    def test_suite_rejects_wrong_plan_narrow_inventory_or_stale_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); inputs, env = self.suite_fixture(directory)
            path = directory / "suite/enumeration.txt"; original = path.read_text()
            path.write_text(original.replace("\tmerianTests/Other/testControl (disabled)\n", ""))
            with self.assertRaises(ValueError): d.suite_diagnostic(directory, inputs, env, completed=False)
            path.write_text(original)
            identity_path = directory / "identity/preparation.json"; identity = json.loads(identity_path.read_text())
            identity["run_attempt"] = "999"; identity_path.write_text(json.dumps(identity))
            with self.assertRaises(ValueError): d.suite_diagnostic(directory, inputs, env, completed=True)
            plan_path = inputs / "ios-unit-plan.json"; plan_path.write_text("changed")
            with self.assertRaises(ValueError): d.suite_diagnostic(directory, inputs, env, completed=False)

    def test_workflow_only_consumes_fixed_artifacts_and_runs_identity_then_whole_suite(self):
        path = ROOT / ".github/workflows/ios-runtime-discovery.yml"
        w = json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
                       "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json", str(path)], text=True))
        job = w["jobs"]["discover"]; steps = job["steps"]
        self.assertEqual(w["permissions"], {"contents": "read", "actions": "read"})
        downloads = [s for s in steps if s.get("uses", "").startswith("actions/download-artifact@")]
        self.assertEqual(len(downloads), 2)
        self.assertEqual({s["with"]["artifact-ids"] for s in downloads}, {v[0] for v in d.ARTIFACTS.values()})
        for step in downloads:
            self.assertEqual(step["with"]["run-id"], d.RUN)
            self.assertEqual(step["with"]["repository"], "emreerdener/merian")
            self.assertEqual(step["with"]["digest-mismatch"], "error")
        commands = "\n".join(s.get("run", "") for s in steps)
        self.assertEqual(commands.count("xcodebuild test-without-building"), 5)
        self.assertEqual(commands.count("-only-testing:"), 7)
        for suite in d.SUITES:
            self.assertEqual(commands.count("-only-testing:" + suite), 2)
        for forbidden in ("build-for-testing", "-skip-testing", "killall", "simctl erase", "GITHUB_SHA=",
                          "GITHUB_RUN_ID=", "GITHUB_RUN_ATTEMPT=", "qualification.json", "-retry-tests-on-failure",
                          "-test-iterations", "-run-tests-until-failure", "continue-on-error"):
            self.assertNotIn(forbidden, commands)
        self.assertEqual(next(s for s in steps if s.get("id") == "identity-test")["timeout-minutes"], 10)
        self.assertNotIn("environment", job)
        for step in steps:
            if "xcodebuild test-without-building" in step.get("run", ""):
                self.assertEqual(step["run"].count("xcodebuild test-without-building"), 1)
                self.assertIn("-parallel-testing-enabled NO", step["run"])
                self.assertIn("set -o pipefail", step["run"])
        self.assertEqual(job["timeout-minutes"], 90)
        runs = [s for s in steps if s.get("id") in ("suite-saved-model", "suite-completion", "suite-resume")]
        self.assertEqual(len(runs), 3)
        for run in runs:
            self.assertEqual(run["timeout-minutes"], 10)
            self.assertEqual(run["if"], "always() && steps.suite-enumeration.outcome == 'success'")
        self.assertEqual(next(s for s in steps if s.get("id") == "suite-enumeration")["timeout-minutes"], 5)
        enumeration = next(s for s in steps if s.get("id") == "suite-enumeration")["run"]
        for flag in ("-enumerate-tests", "-test-enumeration-style flat", "-test-enumeration-format text",
                     '-test-enumeration-output-path "$RUNNER_TEMP/host-diagnostic/suite/enumeration.txt"'):
            self.assertIn(flag, enumeration)
        self.assertNotIn("-resultBundlePath", enumeration)
        self.assertIn("diagnose-ios-service-hub.py suite-enumeration", enumeration)
        self.assertLess(enumeration.index("xcodebuild test-without-building"),
                        enumeration.index("diagnose-ios-service-hub.py suite-enumeration"))
        names = [step.get("name") for step in steps]
        observed = []
        for run in runs:
            suite_run = run["run"]
            selectors = [suite for suite in d.SUITES if "-only-testing:" + suite in suite_run]
            self.assertEqual(len(selectors), 1)
            observed.extend(selectors)
            name = selectors[0].split("/")[1]
            self.assertIn(f'-resultBundlePath "$RUNNER_TEMP/host-diagnostic/suite/{name}/results.xcresult"', suite_run)
            self.assertNotIn("-enumerate-tests", suite_run)
            for flag in ("-retry-tests-on-failure", "-test-iterations", "-run-tests-until-failure", "-skip-testing"):
                self.assertNotIn(flag, suite_run)
            self.assertLess(names.index("Enumerate complete retained video failure suites"), names.index(run["name"]))
            self.assertLess(names.index(run["name"]), names.index("Validate complete suite diagnostic only"))
        self.assertEqual(sorted(observed), sorted(d.SUITES))
        self.assertLess(names.index("Validate diagnostic identity only"), names.index("Enumerate complete retained video failure suites"))
        self.assertLess(names.index("Validate complete suite diagnostic only"), names.index("Observe host after suite attempt"))
        final = next(s for s in steps if s.get("name") == "Validate complete suite diagnostic only")
        self.assertEqual(final["if"], "always()")
        self.assertEqual(final["env"], {"IOS_IDENTITY_TEST_OUTCOME": "${{ steps.identity-test.outcome }}",
            "IOS_SUITE_ENUMERATION_OUTCOME": "${{ steps.suite-enumeration.outcome }}",
            "IOS_SAVED_MODEL_OUTCOME": "${{ steps.suite-saved-model.outcome }}",
            "IOS_COMPLETION_OUTCOME": "${{ steps.suite-completion.outcome }}",
            "IOS_RESUME_OUTCOME": "${{ steps.suite-resume.outcome }}"})
        upload = next(s for s in steps if s.get("name") == "Retain nonqualifying diagnostic evidence")["with"]["path"]
        self.assertNotIn("results.xcresult", upload); self.assertNotIn("diagnostic-products", upload)


class FixtureReadinessWorkflowTests(unittest.TestCase):
    def workflow(self):
        return json.loads(subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
            "puts YAML.safe_load(File.read(ARGV[0]), aliases: false).to_json",
            str(ROOT / ".github/workflows/ios-runtime-discovery.yml")], text=True))

    def test_fresh_diagnostic_is_explicit_and_cannot_start_retained_or_release_work(self):
        workflow = self.workflow()
        trigger = workflow.get("on", workflow.get("true"))
        self.assertEqual(trigger["workflow_dispatch"]["inputs"]["diagnostic"], {
            "description": "Fixed diagnostic to execute; neither qualifies release", "type": "choice",
            "default": "retained-video", "options": ["retained-video", "fixture-readiness"]})
        job = workflow["jobs"]["fixture-readiness"]
        self.assertEqual(job["if"], "github.ref == 'refs/heads/codex/pr152-simulator-diagnostics-20261114' && inputs.diagnostic == 'fixture-readiness'")
        self.assertEqual(workflow["jobs"]["discover"]["if"], "github.ref == 'refs/heads/codex/pr152-simulator-diagnostics-20261114' && inputs.diagnostic == 'retained-video'")
        self.assertEqual(job["timeout-minutes"], 120)
        self.assertNotIn("environment", job)
        self.assertLessEqual(sum(step["timeout-minutes"] for step in job["steps"]), 117)
        self.assertEqual(workflow["permissions"], {"contents": "read", "actions": "read"})
        commands = "\n".join(step.get("run", "") for step in job["steps"])
        self.assertEqual(commands.count("xcodebuild build-for-testing"), 1)
        self.assertEqual(commands.count("xcodebuild test-without-building"), 3)
        for forbidden in ("-skip-testing", "-retry-tests-on-failure", "-test-iterations", "-run-tests-until-failure",
                          "continue-on-error", "simctl erase", "GITHUB_SHA=", "GITHUB_RUN_ID=", "GITHUB_RUN_ATTEMPT="):
            self.assertNotIn(forbidden, commands)
        self.assertIn("-onlyUsePackageVersionsFromResolvedFile", commands)
        self.assertIn("-disableAutomaticPackageResolution", commands)

    def test_both_probes_require_valid_identity_and_raw_results_fail_closed(self):
        steps = self.workflow()["jobs"]["fixture-readiness"]["steps"]
        probes = [step for step in steps if step.get("id") in ("readiness-boundaries", "readiness-consumers")]
        self.assertEqual(len(probes), 2)
        self.assertEqual([step["timeout-minutes"] for step in probes], [3, 10])
        for probe in probes:
            self.assertEqual(probe["if"], "always() && steps.readiness-identity.outcome == 'success'")
            self.assertIn("set -o pipefail", probe["run"])
            self.assertIn("-parallel-testing-enabled NO", probe["run"])
        self.assertIn("-only-testing:merianTests/CaptureScanVideoAudioExtractorTests", probes[0]["run"])
        self.assertNotIn("-only-testing:merianTests/CaptureScanVideoAudioExtractorTests/", probes[0]["run"])
        self.assertIn("-only-testing:merianTests/ObservationVideoCompletionTests", probes[1]["run"])
        self.assertIn("-only-testing:merianTests/ObservationVideoResumeSubmissionTests", probes[1]["run"])
        self.assertEqual(probes[1]["run"].count("-only-testing:"), 2)
        final = next(step for step in steps if step.get("name") == "Verify nonqualifying fixture diagnostic")
        self.assertEqual(final["if"], "always()")
        self.assertEqual(final["env"], {
            "IOS_IDENTITY_TEST_OUTCOME": "${{ steps.ios-identity-test.outcome }}",
            "READINESS_BOUNDARIES_OUTCOME": "${{ steps.readiness-boundaries.outcome }}",
            "READINESS_CONSUMERS_OUTCOME": "${{ steps.readiness-consumers.outcome }}"})
        code = final["run"].split("<<'PY'\n", 1)[1].split("\nPY", 1)[0]
        import ast
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(ast.parse(code))))
        compile(code, "fixture-result-validator", "exec")
        for required in ("'qualified': False", "'release_eligible': False", "== 'success'",
                         "reader.result_methods", "reader.require(methods == sorted(expected)", "reader.require(observed == expected", "reader.require(bucket == manifest",
                         "hashlib.sha256", "identity[\"files\"]", "parameter_leaves=65, files=files"):
            self.assertIn(required, code)
        upload = next(step for step in steps if step.get("name") == "Retain fixture diagnostic evidence")
        self.assertNotIn("fixture-diagnostic-identity.json", upload["with"]["path"])
        self.assertNotIn("tests.xctestproducts", upload["with"]["path"])


if __name__ == "__main__":
    unittest.main()

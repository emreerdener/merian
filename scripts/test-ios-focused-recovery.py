#!/usr/bin/env python3
"""Fail-closed checks for the test-only combined focused recovery route."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


r = module("focused_recovery", "ios-focused-recovery.py")
f = module("fixtures", "test-ios-unit-shards.py")


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.selectors = ["merianTests/Example/testOne", "merianUITests/Other/testTwo"]
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def raw(self, failed=True):
        summary, tree = f.summary_for(self.selectors), f.tree_for(self.selectors)
        if failed:
            summary.update(result="Failed", passedTests=1, failedTests=1)
            f.first_case(tree)["result"] = "Failed"
        return summary, tree

    def test_original_failure_and_replay_pass_are_distinct(self):
        summary, tree = self.raw()
        result = r.outcomes(summary, tree, self.selectors)
        self.assertEqual(result["failed"], self.selectors[:1])
        self.assertEqual(result["passed"], self.selectors[1:])
        summary, tree = self.raw(False)
        self.assertEqual(r.outcomes(summary, tree, self.selectors)["failed"], [])

    def test_only_two_literal_project_names_are_allowed(self):
        for name in ("Merian", "merian", "MERIAN", "MeRiAn", "%6derian", "other"):
            summary, tree = self.raw()
            for case in r.a.audit.nodes(tree):
                if case.get("nodeType") == "Test Case":
                    case["nodeIdentifierURL"] = case["nodeIdentifierURL"].replace("/Merian/", "/" + name + "/")
            if name in ("Merian", "merian"):
                self.assertEqual(len(r.outcomes(summary, tree, self.selectors)["failed"]), 1)
            else:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    r.outcomes(summary, tree, self.selectors)

    def test_missing_extra_duplicate_skip_unknown_and_parameter_cases_fail(self):
        summary, _ = self.raw()
        for methods in (self.selectors[:1], self.selectors * 2, self.selectors + ["merianTests/Extra/testX"]):
            with self.subTest(methods=methods), self.assertRaises(ValueError):
                r.outcomes(summary, f.tree_for(methods), self.selectors)
        for status in ("Skipped", "Expected Failure", "Unknown", None):
            summary, tree = self.raw()
            f.first_case(tree)["result"] = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                r.outcomes(summary, tree, self.selectors)
        summary, tree = self.raw()
        f.first_case(tree)["children"] = [{"nodeType": "Arguments", "result": "Failed"}]
        with self.assertRaises(ValueError):
            r.outcomes(summary, tree, self.selectors)

    def test_summary_identity_and_runtime_mismatches_fail(self):
        for key, value in (("result", "Passed"), ("failedTests", 0), ("passedTests", 2), ("totalTestCount", 1), ("skippedTests", 1)):
            summary, tree = self.raw()
            summary[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                r.outcomes(summary, tree, self.selectors)
        for url in ("", "test://com.apple.xcode/Merian/merianTests/Example/testOne?args=1",
                    "test://com.apple.xcode/Merian/merianTests/Example/%74estOne", "file:///Merian/merianTests/Example/testOne"):
            summary, tree = self.raw()
            f.first_case(tree)["nodeIdentifierURL"] = url
            with self.subTest(url=url), self.assertRaises(ValueError):
                r.outcomes(summary, tree, self.selectors)
        summary, tree = self.raw()
        tree["devices"] = []
        with self.assertRaises(ValueError):
            r.outcomes(summary, tree, self.selectors)

    def repair_fixture(self):
        selectors = r.shards.read_json(r.a.recovery.POLICY)["required_focused_selectors"]
        paths = sorted(r.REPAIR_PATHS)
        before = {p: {"mode": "100644", "type": "blob", "object": "a" * 40} for p in paths}
        before["apps/ios/Merian/App.swift"] = {"mode": "100644", "type": "blob", "object": "c" * 40}
        after = copy.deepcopy(before)
        for path in paths:
            after[path]["object"] = "b" * 40
        affected = [s for s in selectors if s.startswith("merianTests/CaptureWorkspaceViewModelRefinementTests/") or s.rsplit("/", 1)[1] in r.CAPTURE_UI_METHODS]
        repair = {"review": "Independent overlay/fixture review", "applicability": "Other routes do not construct the overlay",
                  "original_failed_selectors": [affected[0]], "replay_selectors": affected,
                  "reused_selectors": [s for s in selectors if s not in affected], "reuse_review": "Reviewed no-host branch and exact source closure",
                  "reviewed_delta": [{"path": p, "before": copy.deepcopy(before[p]), "after": copy.deepcopy(after[p]), "review_scope": "Exact reviewed correction"} for p in paths]}
        return {"focused_recovery": repair, "required_focused_selectors": selectors}, before, after

    def validate(self, policy, before, after):
        with patch.object(r.a, "tree_entries", side_effect=[before, after]):
            return r.validate_repair(policy, "a" * 40, "b" * 40, [policy["required_focused_selectors"][0]])

    def test_only_exact_reviewed_overlay_and_test_repair_is_allowed(self):
        policy, before, after = self.repair_fixture()
        self.assertTrue(self.validate(policy, before, after)["outside_reviewed_owners_unchanged"])
        for path in ("apps/ios/Merian/App.swift", "apps/ios/MerianTestSupport/helper.swift", "project.yml", "Config.xcconfig",
                     "scripts/local-ios-build.py", ".github/workflows/ios.yml", "services/supabase/db.sql", "apps/ios/Resources/fixture.mov"):
            changed = copy.deepcopy(after)
            changed[path] = {"mode": "100644", "type": "blob", "object": "d" * 40}
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.validate(policy, before, changed)

    def test_missing_review_scope_or_exact_object_blocks(self):
        for mutation in ("review", "applicability", "reuse_review", "failures", "replay", "reuse", "delta", "mode", "object"):
            policy, before, after = self.repair_fixture()
            repair = policy["focused_recovery"]
            if mutation in ("review", "applicability", "reuse_review"):
                repair[mutation] = ""
            elif mutation == "failures":
                repair["original_failed_selectors"] = []
            elif mutation == "replay":
                repair["replay_selectors"] = repair["replay_selectors"][:1]
            elif mutation == "reuse":
                repair["reused_selectors"] = []
            elif mutation == "delta":
                repair["reviewed_delta"] = []
            elif mutation == "mode":
                after[sorted(r.REPAIR_PATHS)[0]]["mode"] = "120000"
            else:
                after[sorted(r.REPAIR_PATHS)[0]]["object"] = "f" * 40
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.validate(policy, before, after)

    def evidence(self):
        directory = self.root / "original"
        directory.mkdir()
        bundle = self.root / ".artifacts/local-ios/result.xcresult"
        bundle.mkdir(parents=True)
        (bundle / "data").write_text("immutable result")
        (directory / "build.log").write_text("actual managed command log")
        summary, tree = self.raw()
        raw = {"summary": summary, "tests": tree}
        for key, value in raw.items():
            r.shards.write_json(directory / (key + ".json"), value)
        source = {"source_sha": "a" * 40, "tree": "b" * 40, "release_source_fingerprint": "c" * 64, "policy_sha256": "d" * 64, "workflow_run_id": None, "workflow_run_attempt": None}
        destination = "platform=iOS Simulator,id=" + f.DEVICE
        record = {"source": source, "source_after": source, "product_tree_sha256": "d" * 64,
                  "selectors": self.selectors, "toolchain": "Xcode fixture", "destination": destination,
                  "command": r.a.focused_command({"required_focused_selectors": self.selectors}, destination),
                  "exit_code": 2, "bundles": [str(bundle)]}
        r.shards.write_json(directory / "original-execution.json", record)
        record.update(original_execution_sha256=r.shards.digest(directory / "original-execution.json"),
                      result_bundle=str(bundle), result_bundle_sha256=r.a.bundle_digest(bundle),
                      build_log_sha256=r.shards.digest(directory / "build.log"),
                      raw_sha256={k: r.shards.digest(directory / (k + ".json")) for k in raw},
                      original_outcomes=r.outcomes(summary, tree, self.selectors))
        r.shards.write_json(directory / "execution.json", record)
        return directory, record, raw

    def verify_evidence(self, directory, raw):
        pin = r.pin_record(directory, "Independent original result review")
        with patch.object(r.a, "ROOT", self.root), patch.object(r.a.recovery, "git", return_value=("b" * 40).encode()), patch.object(r.a, "extract", return_value=raw):
            return r.verify_record(directory, pin, self.selectors, failed=True)

    def test_retained_original_evidence_is_reparsed_and_bound(self):
        directory, _, raw = self.evidence()
        self.assertEqual(self.verify_evidence(directory, raw)[1]["failed"], self.selectors[:1])
        raw["summary"]["failedTests"] = 0
        with self.assertRaises(ValueError):
            self.verify_evidence(directory, raw)

    def test_original_bundle_log_raw_and_execution_mutation_blocks(self):
        directory, record, raw = self.evidence()
        for path in (directory / "build.log", directory / "summary.json", directory / "tests.json",
                     directory / "original-execution.json", Path(record["result_bundle"]) / "data"):
            old = path.read_bytes()
            path.write_bytes(old + b"changed")
            with self.subTest(path=path.name), self.assertRaises((ValueError, KeyError)):
                self.verify_evidence(directory, raw)
            path.write_bytes(old)

    def test_source_and_canonical_command_cannot_change(self):
        directory, record, raw = self.evidence()
        for key, value in (("source_after", {"source_sha": "e" * 40}), ("selectors", self.selectors[:1]),
                           ("command", record["command"] + ["-test-timeouts-enabled", "NO"]), ("exit_code", 0),
                           ("destination", "platform=iOS Simulator,id=" + "2" * 36)):
            altered = {**record, key: value}
            r.shards.write_json(directory / "execution.json", altered)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify_evidence(directory, raw)
        r.shards.write_json(directory / "execution.json", record)
        with self.assertRaisesRegex(ValueError, "independent"):
            r.verify_record(directory, {}, self.selectors, failed=True)

    def test_replay_union_and_runtime_are_exact(self):
        policy, _, _ = self.repair_fixture()
        repair = policy["focused_recovery"]
        affected, reused = repair["replay_selectors"], repair["reused_selectors"]
        identity = {"source_sha": "a" * 40, "tree": "b" * 40, "release_source_fingerprint": "c" * 64, "policy_sha256": "d" * 64, "workflow_run_id": None, "workflow_run_attempt": None}
        original = {"source": identity, "toolchain": "Xcode pinned", "destination": "pinned device", "product_tree_sha256": "p"}
        replay = {**original, "source": {**identity, "source_sha": "b" * 40}}
        repair["original"] = {"execution_sha256": "1" * 64}
        repair["compiled_source"] = copy.deepcopy(replay["source"])
        repair["replays"] = [{"directory": "capture26", "selectors": affected, "execution_sha256": "2" * 64}]
        def verify_record(directory, pin, selectors, *, failed):
            if failed:
                return original, {"passed": sorted(set(policy["required_focused_selectors"]) - set(affected[:1])), "failed": affected[:1], "device": {"deviceId": "pinned"}}
            return replay, {"passed": selectors, "failed": [], "device": {"deviceId": "pinned"}}
        def verify():
            with patch.object(r.a.recovery, "git", return_value=("b" * 40).encode()), patch.object(r, "verify_record", side_effect=verify_record), patch.object(r, "validate_repair", return_value={}), patch.object(r, "validate_control_successor", return_value=[]), patch.object(r.a, "product_tree", return_value="p"):
                return r.verify(policy, self.root, {"source_sha": "b" * 40})
        result = verify()
        self.assertEqual(result["cases"], 40)
        self.assertTrue(result["original_focused_failed"])
        self.assertEqual(set(result["reused_methods"]), set(reused))
        saved = copy.deepcopy(repair["replays"])
        for bad in ([], saved + saved, [{**saved[0], "directory": "../escape"}],
                    [{**saved[0], "directory": None}], ["malformed pin"],
                    [{**saved[0], "selectors": affected[:6]}, {**saved[0], "directory": "remaining", "selectors": affected[6:]}],
                    [{**saved[0], "selectors": affected + reused[:1]}]):
            repair["replays"] = bad
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                verify()
        repair["replays"] = saved
        for key in ("toolchain", "destination", "product_tree_sha256", "source"):
            old = replay[key]
            replay[key] = "changed"
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify()
            replay[key] = old

    def test_only_reviewed_controls_can_follow_compilation(self):
        before = {"apps/ios/Merian/App.swift": {"mode": "100644", "type": "blob", "object": "a" * 40}}
        after = {**before, r.POLICY_PATH: {"mode": "100644", "type": "blob", "object": "b" * 40}}
        with patch.object(r.a, "tree_entries", side_effect=[before, after]):
            self.assertEqual(r.validate_control_successor("a" * 40, "b" * 40), [r.POLICY_PATH])
        for path in (*r.REPAIR_PATHS, "project.yml", "apps/ios/Merian/App.swift", "scripts/local-ios-build.py"):
            drift = {**after, path: {"mode": "100644", "type": "blob", "object": "c" * 40}}
            with self.subTest(path=path), patch.object(r.a, "tree_entries", side_effect=[before, drift]), self.assertRaises(ValueError):
                r.validate_control_successor("a" * 40, "b" * 40)

    def test_exact_local_compile_identity_is_required(self):
        identity = {"source_sha": "a" * 40, "tree": "b" * 40, "release_source_fingerprint": "c" * 64,
                    "policy_sha256": "d" * 64, "workflow_run_id": None, "workflow_run_attempt": None}
        with patch.object(r.a.recovery, "git", return_value=("b" * 40).encode()):
            r.validate_source_identity(identity)
            for broken in (None, {}, {"source_sha": "a" * 40}, {**identity, "tree": "f" * 40},
                           {**identity, "source_sha": 1}, {**identity, "policy_sha256": "bad"},
                           {**identity, "release_source_fingerprint": None}, {**identity, "workflow_run_id": "42"}):
                with self.subTest(broken=broken), self.assertRaises(ValueError):
                    r.validate_source_identity(broken)

    def test_evidence_links_and_incomplete_source_fingerprints_fail(self):
        directory, record, raw = self.evidence()
        log = directory / "build.log"
        target = self.root / "other-log"
        log.rename(target)
        log.symlink_to(target)
        with self.assertRaises(ValueError):
            self.verify_evidence(directory, raw)
        log.unlink()
        target.rename(log)
        record["source"] = {"source_sha": "a" * 40}
        record["source_after"] = dict(record["source"])
        r.shards.write_json(directory / "execution.json", record)
        with self.assertRaises(ValueError):
            self.verify_evidence(directory, raw)


if __name__ == "__main__":
    unittest.main()

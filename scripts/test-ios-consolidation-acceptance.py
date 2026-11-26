#!/usr/bin/env python3
"""Positive and adversarial checks for proportionate acceptance."""
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


acceptance = module("acceptance", "ios-consolidation-acceptance.py")
fixtures = module("fixtures", "test-ios-unit-shards.py")


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        git_patch = patch.object(acceptance.recovery, "git", side_effect=lambda *a: b"owner object" if a[0] == "ls-tree" else b"")
        git_patch.start()
        self.addCleanup(git_patch.stop)
        self.selectors = ["merianTests/Example/testOne", "merianUITests/Other/testTwo"]

    def test_exact_combined_methods_pass(self):
        result = acceptance.focused_results(fixtures.summary_for(self.selectors), fixtures.tree_for(self.selectors), self.selectors)
        self.assertEqual(result["cases"], 2)

    def test_missing_duplicate_extra_wrong_target_and_skipped_methods_fail(self):
        summary = fixtures.summary_for(self.selectors)
        for methods in (self.selectors[:1], self.selectors + [self.selectors[0]],
                        self.selectors + ["merianTests/Extra/testOther"],
                        [self.selectors[0], "otherTarget/Other/testTwo"]):
            with self.subTest(methods=methods), self.assertRaises(ValueError):
                acceptance.focused_results(summary, fixtures.tree_for(methods), self.selectors)
        for key, value in (("skippedTests", 1), ("failedTests", 1), ("passedTests", 0), ("result", "Failed")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                acceptance.focused_results({**summary, key: value}, fixtures.tree_for(self.selectors), self.selectors)

    def test_ambiguous_identity_and_parameter_leaves_fail(self):
        for url in ("", "test://com.apple.xcode/Merian/merianTests/Example/testOne?args=x",
                    "test://com.apple.xcode/Merian/merianTests/Example/%74estOne",
                    "test://com.apple.xcode/Merian/merianTests/Example/testOne#fragment"):
            tree = fixtures.tree_for(self.selectors)
            fixtures.first_case(tree)["nodeIdentifierURL"] = url
            with self.subTest(url=url), self.assertRaises(ValueError):
                acceptance.focused_results(fixtures.summary_for(self.selectors), tree, self.selectors)
        methods = ["merianTests/Example/testOne(arg:)"]
        with self.assertRaises(ValueError):
            acceptance.focused_results(fixtures.summary_for(methods), fixtures.tree_for(methods), methods)

    def test_missing_runtime_and_duplicate_selection_fail(self):
        tree = fixtures.tree_for(self.selectors)
        tree["devices"] = []
        with self.assertRaises(ValueError):
            acceptance.focused_results(fixtures.summary_for(self.selectors), tree, self.selectors)
        with self.assertRaises(ValueError):
            acceptance.focused_results(fixtures.summary_for(self.selectors), tree, self.selectors * 2)

    def policy(self):
        return {"origin": {"source_sha": "a" * 40}, "product_paths": ["apps/ios"],
                "reviewed_product_delta": [{"path": "apps/ios/view.swift", "base_sha256": acceptance.recovery.sha256(b"old"),
                                            "candidate_sha256": acceptance.recovery.sha256(b"new"), "justification": "Reviewed UI-only change"}],
                "reused_surface_paths": {"backend": ["services/supabase"]}}

    def git(self, *args):
        if args[0] == "show":
            return b"old" if args[1].startswith("a" * 40) else b"new"
        return b"apps/ios/view.swift\n" if args[-1] == "apps/ios" else b""

    def test_exact_impact_manifest_allows_unchanged_backend_reuse(self):
        with patch.object(acceptance.recovery, "git", side_effect=self.git):
            result = acceptance.validate_delta(self.policy(), "b" * 40, whole_tree=False)
            self.assertEqual(result["compiled_origin"], "a" * 40)
            self.assertEqual(result["candidate"], "b" * 40)

    def test_unknown_product_delta_and_changed_reused_surface_fail(self):
        for key in ("base_sha256", "candidate_sha256", "path", "justification"):
            policy = self.policy()
            policy["reviewed_product_delta"][0][key] = ""
            with self.subTest(key=key), patch.object(acceptance.recovery, "git", side_effect=self.git), self.assertRaises(ValueError):
                acceptance.validate_delta(policy, "b" * 40, whole_tree=False)
        def changed_backend(*args):
            return b"services/supabase/changed.sql\n" if args[-1] == "services/supabase" else self.git(*args)
        with patch.object(acceptance.recovery, "git", side_effect=changed_backend), self.assertRaises(ValueError):
            acceptance.validate_delta(self.policy(), "b" * 40, whole_tree=False)

    def test_missing_manual_evidence_stays_unresolved(self):
        accepted, missing = acceptance.reviewed_records({}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)
        self.assertEqual(accepted, [])
        self.assertEqual(missing, ["mixed-media"])

    def record(self):
        path = self.root / "review.json"
        path.write_text('reviewed report with exact source and observed journey\n')
        return {"requirement": "mixed-media", "path": path.name, "sha256": acceptance.shards.digest(path),
                "source_sha": "a" * 40, "applicability": "Unchanged media path, combined UI covered separately",
                "review": "Independent source/evidence review", "owned_paths": ["apps/ios/Merian/Media"]}

    def test_only_reviewed_pinned_reports_can_close_manual_requirements(self):
        record = self.record()
        accepted, missing = acceptance.reviewed_records({"journey_evidence": [record]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)
        self.assertEqual(missing, [])
        self.assertEqual(accepted, [record])
        for key, value in (("path", "../escape"), ("sha256", "0" * 64), ("source_sha", "unknown"),
                           ("applicability", ""), ("review", ""), ("requirement", "not-required")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                acceptance.reviewed_records({"journey_evidence": [{**record, key: value}]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)
        with self.assertRaises(ValueError):
            acceptance.reviewed_records({"journey_evidence": [record, record]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)

    def test_original_result_mutation_or_symlink_is_rejected(self):
        bundle = self.root / "result.xcresult"
        bundle.mkdir()
        (bundle / "data").write_bytes(b"original")
        original = acceptance.bundle_digest(bundle)
        (bundle / "data").write_bytes(b"changed")
        self.assertNotEqual(original, acceptance.bundle_digest(bundle))
        (bundle / "link").symlink_to(bundle / "data")
        with self.assertRaises(ValueError):
            acceptance.bundle_digest(bundle)

    def test_managed_make_command_does_not_duplicate_run_subcommand(self):
        import shlex
        command = acceptance.focused_command({"required_focused_selectors": self.selectors}, "platform=iOS Simulator,id=fixture")
        self.assertEqual(command[:2], ["make", "ios-local-build"])
        args = shlex.split(command[2].removeprefix("ARGS="))
        self.assertEqual(args[:2], ["simulator", "test"])
        self.assertNotIn("run", args)
        self.assertEqual([a for a in args if a.startswith("-only-testing:")], ["-only-testing:" + s for s in self.selectors])

    def test_full_tree_rejects_unknown_control_and_file_mode_change(self):
        policy_path = "scripts/config/ios-consolidation-acceptance.json"
        original = {"view": {"mode": "100644", "type": "blob", "object": "a" * 40}}
        current = {"view": {"mode": "100644", "type": "blob", "object": "b" * 40},
                   policy_path: {"mode": "100644", "type": "blob", "object": "c" * 40}}
        policy = {"origin": {"source_sha": "a" * 40}, "reviewed_source_delta": [
            {"path": "view", "before": original["view"], "after": current["view"], "review_scope": "Reviewed view change"}]}
        with patch.object(acceptance, "tree_entries", side_effect=[original, current]):
            self.assertEqual(acceptance.validate_full_delta(policy, "b" * 40)["policy_object"], current[policy_path])
        changed = copy.deepcopy(current)
        changed["unreviewed-workflow"] = original["view"]
        with patch.object(acceptance, "tree_entries", side_effect=[original, changed]), self.assertRaises(ValueError):
            acceptance.validate_full_delta(policy, "b" * 40)
        changed = copy.deepcopy(current)
        changed["view"]["mode"] = "100755"
        with patch.object(acceptance, "tree_entries", side_effect=[original, changed]), self.assertRaises(ValueError):
            acceptance.validate_full_delta(policy, "b" * 40)

    def test_historical_report_requires_unchanged_known_owned_paths(self):
        record = self.record()
        for owned in ([], ["docs/anything.md"], ["apps/ios/*"], ["apps/ios/../outside"]):
            with self.subTest(owned=owned), self.assertRaises(ValueError):
                acceptance.reviewed_records({"journey_evidence": [{**record, "owned_paths": owned}]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)
        for behavior in (lambda *args: b"", lambda *args: b"changed-owner"):
            with patch.object(acceptance.recovery, "git", side_effect=behavior), self.assertRaises(ValueError):
                acceptance.reviewed_records({"journey_evidence": [record]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)

    def test_unreviewed_local_receipt_cannot_qualify(self):
        with self.assertRaisesRegex(ValueError, "independent evidence review"):
            acceptance.verify_focused({}, self.root, {"source_sha": "b" * 40})

    def test_exact_release_owner_paths_are_allowed_but_arbitrary_roots_are_not(self):
        record = {**self.record(), "owned_paths": ["project.yml", "Config.xcconfig", "scripts/validate-ios-archive.sh", "scripts/validate-ios-privacy-manifest.sh", "scripts/validate-ios-transport-security.sh"]}
        self.assertEqual(acceptance.reviewed_records({"journey_evidence": [record]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)[1], [])
        for path in ("scripts/unreviewed.sh", "README.md", "docs/arbitrary.md", "/tmp/source"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                acceptance.reviewed_records({"journey_evidence": [{**record, "owned_paths": [path]}]}, "journey_evidence", ["mixed-media"], self.root, "b" * 40)

    def test_assessment_composes_evidence_without_granting_operation_authority(self):
        candidate = {"source_sha": "b" * 40, "tree": "c" * 40}
        policy = {"origin": {"source_sha": "a" * 40}, "recovery_workflow": ".github/workflows/ios-evidence-recovery.yml",
                  "reused_workflows": {"backend": 1}, "reused_workflow_paths": {"backend": "backend.yml"},
                  "required_journeys": ["mixed-media"], "journey_evidence": [self.record()],
                  "testflight_prerequisites": ["device-media-acceptance"],
                  "authorization": {"merge": False, "testflight_upload_or_distribution": False, "backend_or_sites_deploy": False}}
        class Client:
            def json(inner, path):
                return {"id": 9 if path.endswith("/9") else 1, "head_sha": "b" * 40 if path.endswith("/9") else "a" * 40,
                        "run_attempt": 1, "status": "completed", "conclusion": "success", "event": "push",
                        "path": policy["recovery_workflow"] if path.endswith("/9") else "backend.yml"}
            def listing(inner, path, key):
                return {"jobs": [{"name": "Recovered development evidence", "conclusion": "success"}]}
        def recovered(policy, directory, output, verifier):
            output.mkdir()
            result = {"compiled_source": "a" * 40}
            acceptance.shards.write_json(output / "coverage.json", result)
            return result
        with patch.object(acceptance, "source_identity", return_value=candidate), patch.object(acceptance, "validate_delta", return_value={}), patch.object(acceptance.recovery, "collect"), patch.object(acceptance.recovery, "verify", side_effect=recovered), patch.object(acceptance, "verify_combined_evidence", return_value={"cases": 40}):
            result = acceptance.assess(policy, self.root, self.root, self.root / "merge", "merge", Client(), 9)
            self.assertEqual(result["status"], "passed")
            self.assertFalse(result["satisfies_branch_protection"])
            self.assertFalse(result["authorization"]["merge"])
            self.assertFalse(result["old_workflow_relabelled"])
            with self.assertRaisesRegex(ValueError, "device-media-acceptance"):
                acceptance.assess(policy, self.root, self.root, self.root / "flight", "testflight", Client(), 9)
            report = acceptance.shards.read_json(self.root / "flight/acceptance.json")
            self.assertEqual(report["status"], "blocked")
            self.assertEqual(report["unresolved"], ["device-media-acceptance"])
            qa_required = ["exact-signed-archive-privacy-ats-history", "compatible-beta-backend", "consent-rollout-readiness"]
            with self.assertRaisesRegex(ValueError, "exact-signed-archive"):
                acceptance.assess(policy, self.root, self.root, self.root / "qa-missing", "qa-upload", Client(), 9)
            report = acceptance.shards.read_json(self.root / "qa-missing/acceptance.json")
            self.assertEqual(report["unresolved"], sorted(qa_required))
            policy["qa_upload_evidence"] = [{**self.record(), "requirement": requirement} for requirement in qa_required]
            report = acceptance.assess(policy, self.root, self.root, self.root / "qa-prepared", "qa-upload", Client(), 9)
            self.assertEqual(report["status"], "passed")
            self.assertIn("no tester assignment", report["qa_upload_scope"])
            self.assertEqual(report["qa_assignment_prerequisites"], ["completed consent distribution safety", "explicit named bounded migration-QA group authorization"])
            self.assertFalse(report["authorization"]["testflight_upload_or_distribution"])
            with self.assertRaisesRegex(ValueError, "device-media-acceptance"):
                acceptance.assess(policy, self.root, self.root, self.root / "flight-after-qa", "testflight", Client(), 9)
            with self.assertRaisesRegex(ValueError, "exact-verifier"):
                acceptance.assess(policy, self.root, self.root, self.root / "wrong", "merge", Client(), 2)
            policy["authorization"]["merge"] = True
            with self.assertRaisesRegex(ValueError, "cannot grant"):
                acceptance.assess(policy, self.root, self.root, self.root / "authority", "merge", Client(), 9)

    def test_combined_evidence_route_is_explicit_and_exclusive(self):
        for policy in ({}, {"focused_evidence": {"review": "yes"}, "focused_recovery": {"review": "yes"}}):
            with self.assertRaisesRegex(ValueError, "Exactly one"):
                acceptance.verify_combined_evidence(policy, self.root, {"source_sha": "b" * 40})
        with patch.object(acceptance, "verify_focused", return_value={"cases": 40}) as ordinary:
            self.assertEqual(acceptance.verify_combined_evidence({"focused_evidence": {"review": "yes"}}, self.root, {}), {"cases": 40})
            ordinary.assert_called_once()

    def test_literal_local_project_spelling_is_accepted_without_casefold(self):
        for project in ("merian", "MERIAN", "MeRiAn", "%6derian"):
            tree = fixtures.tree_for(self.selectors)
            for node in acceptance.audit.nodes(tree):
                if node.get("nodeType") == "Test Case":
                    node["nodeIdentifierURL"] = node["nodeIdentifierURL"].replace("/Merian/", "/" + project + "/")
            if project == "merian":
                self.assertEqual(acceptance.focused_results(fixtures.summary_for(self.selectors), tree, self.selectors)["cases"], 2)
            else:
                with self.assertRaises(ValueError):
                    acceptance.focused_results(fixtures.summary_for(self.selectors), tree, self.selectors)

    def test_recovery_workflow_is_read_only_and_cannot_cancel_or_run_native(self):
        workflow = (acceptance.ROOT / ".github/workflows/ios-evidence-recovery.yml").read_text()
        self.assertIn("actions: read", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        for forbidden in ("write", "pull_request_target", "xcodebuild", "secrets.", "workflow_run:"):
            self.assertNotIn(forbidden, workflow)
        self.assertIn("python3 -B scripts/ios-evidence-recovery.py", workflow)


def load_tests(loader, standard_tests, pattern):
    standard_tests.addTests(loader.loadTestsFromModule(module("focused_recovery_tests", "test-ios-focused-recovery.py")))
    standard_tests.addTests(loader.loadTestsFromModule(module("followup_tests", "test-ios-consolidation-followups.py")))
    return standard_tests


if __name__ == "__main__":
    unittest.main()

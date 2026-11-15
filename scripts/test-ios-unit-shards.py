#!/usr/bin/env python3
"""Adversarial compiled-inventory, artifact and result reconciliation tests."""

import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("shards", Path(__file__).with_name("ios-unit-shards.py"))
shards = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shards)
DEVICE = "11111111-1111-4111-8111-111111111111"
ENV = {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "1234", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKSPACE": "/Users/runner/work/merian/merian"}


EXPECTED_RUNTIME = {"SIMULATOR_RUNTIME_VERSION": "27.2", "SIMULATOR_RUNTIME_BUILD_VERSION": "24B8117",
                    "SIMULATOR_MODEL_IDENTIFIER": "iPhone19,2"}


EXPECTED_FOUNDATION = {"merianTests/AppleFoundationVisualCueProviderTests/" + name for name in (
    "schemaCanBeConstructed", "detailPresenceDoesNotPublishAnUnfinishedObject",
    "completedCuePublishesWhileTheNextCueIsStillStreaming", "malformedEntriesDoNotShiftLaterCueIndices",
    "mappingBoundsEvenAnOversizedResponse", "completeModelOutputStillPassesThroughIdentityValidation",
    "emptyOrUnrelatedContentProducesNoCues")}
EXPECTED_ARGUMENTS = {
    "merianTests/PinnedPhotoUploadTaskTests/maximumOriginalStreamResources(cancelHalfway:)": 2,
    "merianTests/CaptureNativePhotoRoleAllocationTests/freshCaptureSendsOneFrozenSourceAndFencesChanges(duringTicket:)": 7,
    "merianTests/CaptureNativePhotoRoleAllocationTests/firstOriginalPutChecksExactProgressOnce(_:)": 3,
}
EXPECTED_EMPTY_SUPPORT = {"merianTests/ConsentManagerTestCase", "merianTests/OfflineQueueTestCase"}


def enumeration_text(methods, *, full_target=False):
    selectors = list(methods) + (sorted(EXPECTED_EMPTY_SUPPORT) if full_target else [])
    return "Plan Merian\n" + "".join("\t" + method + "\n" for method in selectors)


def qualification():
    return {"schema_version": 1, **shards.identity(), "qualified": False, "release_eligible": False,
            "status": "passed", "identity_observed": True, "observation_method": "xctest_attachment", "architecture": "arm64",
            "runtime_identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
            "device_type_identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
            "observed_environment": dict(EXPECTED_RUNTIME), "simulator_destination": "platform=iOS Simulator,id=" + DEVICE,
            "phases": [{"phase": name, "outcome": "passed", "elapsed_ms": 1} for name in ("cache", "create", "boot")],
            "files": {name: "a" * 64 for name in ("preparation.json", "summary.json", "tests.json",
                                                  "attachments/manifest.json", "attachments/identity.txt")}}


def tree_for(methods):
    suites = {}
    for method in methods:
        target, name, test = method.split("/", 2)
        parameterized = ":" in test
        result_id = name + "/" + test + ("" if test.endswith(")") else "()")
        url = "test://com.apple.xcode/Merian/" + method
        case = {"nodeType": "Test Case", "result": "Passed", "name": test,
                "nodeIdentifier": result_id, "nodeIdentifierURL": url}
        if parameterized:
            case["children"] = [{"nodeType": "Arguments", "result": "Passed",
                                  "nodeIdentifierURL": url + "?args=" + format(i, "064x")} for i in range(EXPECTED_ARGUMENTS.get(method, 2))]
        suites.setdefault(name, {"nodeType": "Test Suite", "result": "Passed", "name": name,
                                 "children": []})["children"].append(case)
    return {"devices": [{"architecture": "arm64", "deviceId": DEVICE, "osBuildNumber": "24B8117",
                          "osVersion": "27.2", "platform": "iOS Simulator"}],
            "testPlanConfigurations": [{"configurationId": "1", "configurationName": "Test Scheme Action"}],
            "testNodes": [{"nodeType": "Test Plan", "result": "Passed", "name": "Merian", "children": [
                {"nodeType": "Unit test bundle", "result": "Passed", "name": "merianTests",
                 "children": list(suites.values())}]}]}


def summary_for(methods):
    return {"result": "Passed", "totalTestCount": len(methods), "passedTests": len(methods),
            "failedTests": 0, "skippedTests": 0}


def first_case(tree):
    return tree["testNodes"][0]["children"][0]["children"][0]["children"][0]


class ShardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = patch.dict(os.environ, ENV)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.methods = ["merianTests/Alpha/testOne", "merianTests/Alpha/parameter(value:)",
                        "merianTests/Beta/testTwo", "merianTests/Gamma/testThree"] + sorted(EXPECTED_FOUNDATION | set(EXPECTED_ARGUMENTS))
        self.enumeration = self.root / "enumeration.txt"
        self.enumeration.write_text(enumeration_text(self.methods, full_target=True))
        self.products = self.root / "products.tar.gz"
        self.products.write_bytes(b"compiled product fixture")
        self.plan = shards.make_plan(self.enumeration, self.products, {"Alpha": 50})
        self.plan_file = self.root / "plan.json"
        self.save_plan()
        self.focused = self.requalification_evidence()

    def save_plan(self):
        shards.write_json(self.plan_file, self.plan)
        os.environ["IOS_UNIT_PLAN_SHA256"] = shards.digest(self.plan_file)

    def evidence(self):
        root = self.root / "evidence"
        root.mkdir()
        for shard in self.plan["shards"]:
            directory = root / f"ios-unit-shard-1234-attempt-1-{shard['index']}"
            directory.mkdir()
            (directory / "enumeration.txt").write_text(enumeration_text(shard["methods"]))
            shards.write_json(directory / "summary.json", summary_for(shard["methods"]))
            shards.write_json(directory / "tests.json", tree_for(shard["methods"]))
            shards.write_json(directory / "qualification.json", qualification())
            shards.write_json(directory / "receipt.json", shards.receipt(self.plan, shard["index"], directory))
        return root

    def test_partition_is_complete_deterministic_and_never_splits_suite(self):
        self.assertEqual(shards.partition(self.methods, {"Alpha": 50}),
                         shards.partition(list(reversed(self.methods)), {"Alpha": 50}))
        plan = shards.load_plan(self.plan_file)
        self.assertEqual(sorted(m for s in plan["shards"] for m in s["methods"]), sorted(self.methods))
        alpha = [s for s in plan["shards"] if "merianTests/Alpha" in s["suites"]]
        self.assertEqual(len(alpha), 1)
        self.assertEqual(len(alpha[0]["methods"]), 2)

    def test_large_inventory_uses_bounded_sixteen_jobs_and_keeps_new_suites(self):
        methods = [f"merianTests/NewSuite{i}/test" for i in range(55)]
        partition = shards.partition(methods, {})
        self.assertEqual(len(partition), 16)
        self.assertEqual(sorted(m for s in partition for m in s["methods"]), sorted(methods))
        self.assertTrue(all(s["methods"] for s in partition))

    def test_plan_rejects_missing_required_ios27_parser_method(self):
        self.enumeration.write_text(enumeration_text(
            [m for m in self.methods if m != sorted(shards.FOUNDATION_METHODS)[0]], full_target=True))
        with self.assertRaisesRegex(ValueError, "parser inventory"):
            shards.make_plan(self.enumeration, self.products, {})

    def requalification_evidence(self):
        directory = self.root / "requalification"
        if directory.exists(): return directory
        directory.mkdir()
        methods = sorted(EXPECTED_FOUNDATION | set(EXPECTED_ARGUMENTS))
        shards.write_json(directory / "plan.json", self.plan)
        (directory / "full-inventory.txt").write_text(self.enumeration.read_text())
        (directory / "enumeration.txt").write_text(enumeration_text(methods))
        tree = tree_for(methods)
        for suite in tree["testNodes"][0]["children"][0]["children"]:
            for case in suite["children"]:
                method = shards.canonical("merianTests/" + case["nodeIdentifier"])
                if method in EXPECTED_ARGUMENTS:
                    case["children"] = [{"nodeType": "Arguments", "result": "Passed",
                        "nodeIdentifierURL": case["nodeIdentifierURL"] + "?args=" + format(i, "064x")}
                        for i in range(EXPECTED_ARGUMENTS[method])]
        shards.write_json(directory / "tests.json", tree)
        shards.write_json(directory / "summary.json", summary_for(methods))
        shards.write_json(directory / "qualification.json", qualification())
        (directory / "enumeration.log").write_text("")
        (directory / "xcodebuild.log").write_text("")
        (directory / "results.xcresult").mkdir()
        shards.write_json(directory / "receipt.json", shards.requalification(directory))
        return directory

    def test_requalification_derives_all_selected_methods_and_binds_evidence(self):
        directory = self.requalification_evidence()
        receipt = shards.requalification(directory)
        self.assertFalse(receipt["release_eligible"])
        self.assertEqual(receipt["parameter_leaves"], 12)
        self.assertEqual(len(receipt["methods"]), 10)
        self.assertEqual(len(receipt["files"]), 6)
        self.assertEqual(receipt["products_sha256"], shards.digest(self.products))
        self.assertEqual(receipt["plan_sha256"], shards.digest(self.plan_file))

    def test_requalification_rejects_omitted_compiled_method_even_when_focus_passes(self):
        directory = self.requalification_evidence()
        with (directory / "full-inventory.txt").open("a") as output:
            output.write("\tmerianTests/PinnedPhotoUploadTaskTests/newRequiredMethod\n")
        with self.assertRaisesRegex(ValueError, "Focused full inventory"):
            shards.requalification(directory)

    def test_protected_coverage_literals(self):
        self.assertEqual(shards.RUNTIME, EXPECTED_RUNTIME)
        self.assertEqual(shards.FOUNDATION_METHODS, EXPECTED_FOUNDATION)
        self.assertEqual(shards.REQUALIFICATION_ARGUMENT_COUNTS, EXPECTED_ARGUMENTS)

    def test_requalification_rejects_missing_extra_fixed_parameter_leaf_and_skip(self):
        directory = self.requalification_evidence()
        original = shards.read_json(directory / "tests.json")
        for method in EXPECTED_ARGUMENTS:
            for mode in ("missing", "extra", "skipped"):
                tree = copy.deepcopy(original)
                cases = tree["testNodes"][0]["children"][0]["children"]
                case = next(c for suite in cases for c in suite["children"]
                            if shards.canonical("merianTests/" + c["nodeIdentifier"]) == method)
                if mode == "missing": case["children"].pop()
                elif mode == "extra":
                    case["children"].append({"nodeType": "Arguments", "result": "Passed",
                        "nodeIdentifierURL": case["nodeIdentifierURL"] + "?args=" + "f" * 64})
                else: case["children"][0]["result"] = "Skipped"
                shards.write_json(directory / "tests.json", tree)
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    shards.requalification(directory)

    def test_focused_result_rejects_wrong_plan_product_or_stale_receipt(self):
        evidence = self.evidence()
        for key, value in (("products_sha256", "f" * 64), ("plan_sha256", "e" * 64), ("source_sha", "b" * 40)):
            original = shards.requalification(self.focused)
            original[key] = value
            shards.write_json(self.focused / "receipt.json", original)
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "Focused receipt mismatch"):
                shards.aggregate(self.plan, evidence, self.root / "out", self.focused)
        (self.focused / "extra").mkdir()
        with self.assertRaisesRegex(ValueError, "extra focused evidence"):
            shards.aggregate(self.plan, evidence, self.root / "out", self.focused)

    def test_inventory_rejects_duplicates_headers_empty_and_other_targets(self):
        for text in ["", "\n", "Plan Merian\n", "Test plan: Merian\n\tmerianTests/A/test\n",
                     "Plan Other\n\tmerianTests/A/test\n", "merianTests/A/test\n",
                     "Plan Merian\nmerianTests/A/test\n", "Plan Merian\n  merianTests/A/test\n",
                     "Plan Merian\n\t\tmerianTests/A/test\n", "Plan Merian\n\tmerianTests/A/test\n\n",
                     enumeration_text(["merianTests/A/test", "merianTests/A/test()"]),
                     enumeration_text(["other/A/test"]), enumeration_text(["merianTests/A/test?args=123"]),
                     enumeration_text(["merianTests/../test"]), enumeration_text(["merianTests/A/test\t"]),
                     enumeration_text(["merianTests/A/test", "Plan Merian"]),
                     enumeration_text(["merianTests/A/test", "merianTests/UnknownEmptySuite"])]:
            with self.subTest(text=text):
                self.enumeration.write_text(text)
                with self.assertRaises(ValueError):
                    shards.inventory(self.enumeration)

    def test_hosted_enumeration_framing_preserves_all_methods_and_support_entries(self):
        self.assertEqual(shards.EMPTY_SUPPORT_SUITES, EXPECTED_EMPTY_SUPPORT)
        self.assertEqual(shards.inventory(self.enumeration, full_target=True), sorted(self.methods))
        self.assertEqual(self.plan["empty_support_suites"], sorted(EXPECTED_EMPTY_SUPPORT))
        self.assertEqual(self.plan["enumeration_sha256"], shards.digest(self.enumeration))
        self.assertEqual(sorted(m for s in self.plan["shards"] for m in s["methods"]), sorted(self.methods))

    def test_full_inventory_requires_exact_empty_support_entries_and_no_executable_children(self):
        valid = self.enumeration.read_text()
        for text in [valid.replace("\tmerianTests/ConsentManagerTestCase\n", ""),
                     valid + "\tmerianTests/ConsentManagerTestCase\n",
                     valid + "\tmerianTests/ConsentManagerTestCase/newRequiredTest()\n",
                     valid + "\tmerianTests/UnknownEmptySuite\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.enumeration.write_text(text)
                shards.inventory(self.enumeration, full_target=True)

    def test_selected_inventory_rejects_unassigned_empty_support_entries(self):
        with self.assertRaisesRegex(ValueError, "empty support suite"):
            shards.inventory(self.enumeration)

    def test_full_inventory_raw_digest_is_reconciled_even_when_methods_are_identical(self):
        path = self.focused / "full-inventory.txt"
        lines = path.read_text().splitlines()
        path.write_text("\n".join([lines[0]] + list(reversed(lines[1:]))) + "\n")
        with self.assertRaisesRegex(ValueError, "enumeration digest"):
            shards.requalification(self.focused)

    def test_plan_rejects_removed_or_unbound_support_entries(self):
        original = copy.deepcopy(self.plan)
        for mutation in [lambda p: p.pop("empty_support_suites"),
                         lambda p: p["empty_support_suites"].pop(),
                         lambda p: p.update(enumeration_sha256="invalid"),
                         lambda p: p.pop("enumeration_sha256")]:
            self.plan = copy.deepcopy(original)
            mutation(self.plan)
            self.save_plan()
            with self.assertRaisesRegex(ValueError, "enumeration binding"):
                shards.load_plan(self.plan_file)

    def test_missing_overlapping_or_split_plan_never_loads(self):
        original = copy.deepcopy(self.plan)
        mutations = [lambda p: p["shards"].pop(),
                     lambda p: p["shards"][0]["methods"].pop(),
                     lambda p: p["shards"][1]["methods"].append(p["shards"][0]["methods"][0]),
                     lambda p: p["shards"][0].update(index=True),
                     lambda p: p.update(target="merianPerformanceTests")]
        for mutation in mutations:
            self.plan = copy.deepcopy(original)
            mutation(self.plan)
            self.save_plan()
            with self.assertRaises(ValueError):
                shards.load_plan(self.plan_file)

    def test_exact_source_run_attempt_and_digest_are_required(self):
        for key, wrong in [("GITHUB_SHA", "b" * 40), ("GITHUB_RUN_ID", "1235"),
                           ("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_WORKSPACE", "/different"), ("IOS_UNIT_PLAN_SHA256", "f" * 64)]:
            with self.subTest(key=key), patch.dict(os.environ, {key: wrong}):
                with self.assertRaises(ValueError):
                    shards.load_plan(self.plan_file)

    def test_native_methods_and_parameter_leaves_are_counted_separately(self):
        methods, leaves = shards.result_methods(summary_for(self.methods), tree_for(self.methods), qualification())
        self.assertEqual(methods, sorted(self.methods))
        self.assertEqual(leaves, 14)

    def test_linux_aggregate_changes_workspace_but_not_source_run_or_attempt(self):
        with patch.dict(os.environ, {"GITHUB_WORKSPACE": "/home/runner/work/merian/merian"}):
            self.assertEqual(shards.load_plan(self.plan_file, require_workspace=False), self.plan)
            for key, wrong in [("GITHUB_SHA", "b" * 40), ("GITHUB_RUN_ID", "1235"),
                               ("GITHUB_RUN_ATTEMPT", "2"), ("IOS_UNIT_PLAN_SHA256", "f" * 64)]:
                with self.subTest(key=key), patch.dict(os.environ, {key: wrong}):
                    with self.assertRaises(ValueError):
                        shards.load_plan(self.plan_file, require_workspace=False)

    def test_duplicate_missing_misbound_unknown_and_failed_method_nodes_fail(self):
        original = tree_for(self.methods)
        mutations = [lambda t: t["testNodes"].append(copy.deepcopy(t["testNodes"][0])),
                     lambda t: first_case(t).update(nodeIdentifier="Alpha/notEnumerated"),
                     lambda t: first_case(t).update(result="Failed"),
                     lambda t: first_case(t).update(nodeType="Unknown Test"),
                     lambda t: t["devices"][0].update(osBuildNumber="different"),
                     lambda t: t["testPlanConfigurations"].append({}),
                     lambda t: t["testNodes"][0]["children"][0]["children"][0]["children"].append(copy.deepcopy(first_case(t)))]
        for mutation in mutations:
            tree = copy.deepcopy(original)
            mutation(tree)
            with self.assertRaises(ValueError):
                shards.result_methods(summary_for(self.methods), tree, qualification())

    def test_failed_skipped_duplicated_missing_and_misbound_parameter_rows_fail(self):
        methods = ["merianTests/Alpha/parameter(value:)"]
        original = tree_for(methods)
        mutations = [lambda c: c["children"][0].update(result="Failed"),
                     lambda c: c["children"][0].update(result="Skipped"),
                     lambda c: c["children"].append(copy.deepcopy(c["children"][0])),
                     lambda c: c.update(children=[]),
                     lambda c: c["children"][0].update(nodeIdentifierURL="test://com.apple.xcode/Merian/merianTests/Else/test?args=" + "1" * 64)]
        for mutation in mutations:
            tree = copy.deepcopy(original)
            mutation(first_case(tree))
            with self.assertRaises(ValueError):
                shards.result_methods(summary_for(methods), tree, qualification())

    def test_nonpassing_counts_and_forged_qualification_fail(self):
        for change in [{"result": "Failed"}, {"failedTests": 1}, {"skippedTests": 1},
                       {"passedTests": 3}, {"totalTestCount": True}, {"totalTestCount": 5, "passedTests": 5}]:
            summary = summary_for(self.methods)
            summary.update(change)
            with self.assertRaises(ValueError):
                shards.result_methods(summary, tree_for(self.methods), qualification())
        for change in [{"qualified": True}, {"release_eligible": True}, {"identity_observed": False},
                       {"observation_method": "getenv"}, {"source_sha": "b" * 40}, {"run_id": "1235"}, {"run_attempt": "2"},
                       {"phases": []}, {"files": {}}, {"observed_environment": {}},
                       {"architecture": "x86_64"}, {"simulator_destination": "platform=iOS Simulator,id=other"}]:
            value = qualification()
            value.update(change)
            with self.assertRaises(ValueError):
                shards.result_methods(summary_for(self.methods), tree_for(self.methods), value)

    def test_identity_observation_rejects_malformed_provenance(self):
        mutations = [lambda q: q.update(schema_version=True), lambda q: q.update(schema_version=2),
                     lambda q: q.update(runtime_identifier="other"), lambda q: q.update(device_type_identifier="other"),
                     lambda q: q["observed_environment"].update(SIMULATOR_MODEL_IDENTIFIER="iPhone99,1"),
                     lambda q: q["observed_environment"].update(SIMULATOR_RUNTIME_VERSION="26.5"),
                     lambda q: q["observed_environment"].update(SIMULATOR_RUNTIME_BUILD_VERSION="23F77"),
                     lambda q: q["phases"].reverse(), lambda q: q["phases"][0].update(outcome="failed"),
                     lambda q: q["phases"][0].update(elapsed_ms=True), lambda q: q["phases"][0].update(elapsed_ms=-1),
                     lambda q: q["files"].update(extra="a" * 64)]
        for mutation in mutations:
            value = qualification(); mutation(value)
            with self.assertRaises(ValueError): shards.observed_device(value)
        for name in qualification()["files"]:
            for mode in ("missing", "invalid"):
                value = qualification()
                if mode == "missing": value["files"].pop(name)
                else: value["files"][name] = "not-a-digest"
                with self.subTest(name=name, mode=mode), self.assertRaises(ValueError): shards.observed_device(value)
        for name in ("attachments/..", "attachments/../escape", "outside.txt", "attachments/dir/name"):
            value = qualification(); value["files"].pop("attachments/identity.txt"); value["files"][name] = "a" * 64
            with self.subTest(name=name), self.assertRaises(ValueError): shards.observed_device(value)
        for key, value in (("osVersion", "26.5"), ("osBuildNumber", "23F77"), ("deviceId", "22222222-2222-4222-8222-222222222222")):
            tree = tree_for(self.methods); tree["devices"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                shards.result_methods(summary_for(self.methods), tree, qualification())

    def test_aggregate_preserves_raw_trees_and_reconciles_complete_coverage(self):
        evidence = self.evidence()
        output = self.root / "aggregate"
        shards.aggregate(self.plan, evidence, output, self.focused)
        self.assertEqual(shards.read_json(output / "summary.json"), summary_for(self.methods))
        raw = shards.read_json(output / "tests.json")["shards"]
        self.assertEqual(raw, [shards.read_json(evidence / f"ios-unit-shard-1234-attempt-1-{i}" / "tests.json")
                               for i in range(len(self.plan["shards"]))])
        self.assertEqual(shards.read_json(output / "coverage.json")["parameter_leaves"], 14)

    def test_aggregate_rejects_missing_extra_and_stale_attempt_artifacts(self):
        evidence = self.evidence()
        path = next(evidence.iterdir())
        for name in ["stale", path.name.replace("attempt-1", "attempt-2")]:
            renamed = path.rename(evidence / name)
            with self.assertRaises(ValueError):
                shards.aggregate(self.plan, evidence, self.root / "output", self.focused)
            renamed.rename(path)
        (evidence / "extra").mkdir()
        with self.assertRaises(ValueError):
            shards.aggregate(self.plan, evidence, self.root / "output", self.focused)

    def test_aggregate_recomputes_receipts_and_rejects_tampered_evidence(self):
        evidence = self.evidence()
        path = next(evidence.iterdir()) / "receipt.json"
        value = shards.read_json(path)
        value["source_sha"] = "b" * 40
        shards.write_json(path, value)
        with self.assertRaises(ValueError):
            shards.aggregate(self.plan, evidence, self.root / "output", self.focused)

    def test_duplicate_json_keys_are_not_silently_accepted(self):
        self.plan_file.write_text('{"status":"failed","status":"passed"}')
        with self.assertRaises(ValueError):
            shards.read_json(self.plan_file)

    def test_pack_roundtrip_preserves_executable_and_internal_framework_link(self):
        product = self.root / "source.xctestproducts"
        binary = product / "Framework/Versions/A/binary"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"compiled")
        binary.chmod(0o755)
        (product / "Framework/Versions/Current").symlink_to("A")
        (product / "Framework/binary").symlink_to("Versions/Current/binary")
        archive = self.root / "compiled.tar.gz"
        shards.pack_product(product, archive)
        destination = self.root / "unpacked"
        shards.unpack_product({"products_sha256": shards.digest(archive)}, archive, destination)
        restored = destination / "tests.xctestproducts/Framework/binary"
        self.assertTrue(restored.is_symlink())
        self.assertEqual(restored.read_bytes(), b"compiled")
        self.assertTrue(restored.stat().st_mode & 0o100)

    def test_product_digest_and_existing_destination_fail_before_extract(self):
        with self.assertRaises(ValueError):
            shards.unpack_product({"products_sha256": "f" * 64}, self.products, self.root / "missing")
        self.assertFalse((self.root / "missing").exists())
        with self.assertRaises(ValueError):
            shards.unpack_product({"products_sha256": shards.digest(self.products)}, self.products, self.root)

    def test_archive_traversal_links_and_special_files_fail_before_writes(self):
        for attack in ["../outside", "/absolute", "tests.xctestproducts/../../outside", "link", "device", "through-link"]:
            archive = self.root / "attack.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                root = tarfile.TarInfo("tests.xctestproducts")
                root.type = tarfile.DIRTYPE
                tar.addfile(root)
                member = tarfile.TarInfo(attack if "/" in attack else "tests.xctestproducts/" + attack)
                if attack in ("link", "through-link"):
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../../outside" if attack == "link" else "."
                elif attack == "device":
                    member.type = tarfile.CHRTYPE
                else:
                    member.size = 1
                tar.addfile(member, io.BytesIO(b"x") if member.isfile() else None)
                if attack == "through-link":
                    child = tarfile.TarInfo("tests.xctestproducts/through-link/child")
                    child.size = 1
                    tar.addfile(child, io.BytesIO(b"x"))
            destination = self.root / "rejected"
            with self.assertRaises(ValueError):
                shards.unpack_product({"products_sha256": shards.digest(archive)}, archive, destination)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()

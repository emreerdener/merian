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


def qualification():
    return {"qualified": True, "status": "passed", "architecture": "arm64", "runtime_cache_ready": True,
            "runtime_identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            "device_type_identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
            "observed_environment": shards.RUNTIME,
            "simulator_destination": "platform=iOS Simulator,id=" + DEVICE}


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
                                  "nodeIdentifierURL": url + "?args=" + digit * 64} for digit in ("1", "2")]
        suites.setdefault(name, {"nodeType": "Test Suite", "result": "Passed", "name": name,
                                 "children": []})["children"].append(case)
    return {"devices": [{"architecture": "arm64", "deviceId": DEVICE, "osBuildNumber": "23F77",
                          "osVersion": "26.5", "platform": "iOS Simulator"}],
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
                        "merianTests/Beta/testTwo", "merianTests/Gamma/testThree"]
        self.enumeration = self.root / "enumeration.txt"
        self.enumeration.write_text("\n".join(self.methods) + "\n")
        self.products = self.root / "products.tar.gz"
        self.products.write_bytes(b"compiled product fixture")
        self.plan = shards.make_plan(self.enumeration, self.products, {"Alpha": 50})
        self.plan_file = self.root / "plan.json"
        self.save_plan()

    def save_plan(self):
        shards.write_json(self.plan_file, self.plan)
        os.environ["IOS_UNIT_PLAN_SHA256"] = shards.digest(self.plan_file)

    def evidence(self):
        root = self.root / "evidence"
        root.mkdir()
        for shard in self.plan["shards"]:
            directory = root / f"ios-unit-shard-1234-attempt-1-{shard['index']}"
            directory.mkdir()
            (directory / "enumeration.txt").write_text("\n".join(shard["methods"]) + "\n")
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

    def test_inventory_rejects_duplicates_headers_empty_and_other_targets(self):
        for text in ["", "\n", "merianTests/A/test\n\n", "Test plan: Merian\n",
                     "merianTests/A/test\nmerianTests/A/test()\n", "other/A/test\n",
                     "merianTests/A/test?args=123\n", "merianTests/../test\n", "merianTests/A/test\t\n"]:
            with self.subTest(text=text):
                self.enumeration.write_text(text)
                with self.assertRaises(ValueError):
                    shards.inventory(self.enumeration)

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
        self.assertEqual(leaves, 2)

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
        for change in [{"qualified": False}, {"runtime_cache_ready": False}, {"observed_environment": {}},
                       {"architecture": "x86_64"}, {"simulator_destination": "platform=iOS Simulator,id=other"}]:
            value = qualification()
            value.update(change)
            with self.assertRaises(ValueError):
                shards.result_methods(summary_for(self.methods), tree_for(self.methods), value)

    def test_aggregate_preserves_raw_trees_and_reconciles_complete_coverage(self):
        evidence = self.evidence()
        output = self.root / "aggregate"
        shards.aggregate(self.plan, evidence, output)
        self.assertEqual(shards.read_json(output / "summary.json"), summary_for(self.methods))
        raw = shards.read_json(output / "tests.json")["shards"]
        self.assertEqual(raw, [shards.read_json(evidence / f"ios-unit-shard-1234-attempt-1-{i}" / "tests.json")
                               for i in range(len(self.plan["shards"]))])
        self.assertEqual(shards.read_json(output / "coverage.json")["parameter_leaves"], 2)

    def test_aggregate_rejects_missing_extra_and_stale_attempt_artifacts(self):
        evidence = self.evidence()
        path = next(evidence.iterdir())
        for name in ["stale", path.name.replace("attempt-1", "attempt-2")]:
            renamed = path.rename(evidence / name)
            with self.assertRaises(ValueError):
                shards.aggregate(self.plan, evidence, self.root / "output")
            renamed.rename(path)
        (evidence / "extra").mkdir()
        with self.assertRaises(ValueError):
            shards.aggregate(self.plan, evidence, self.root / "output")

    def test_aggregate_recomputes_receipts_and_rejects_tampered_evidence(self):
        evidence = self.evidence()
        path = next(evidence.iterdir()) / "receipt.json"
        value = shards.read_json(path)
        value["source_sha"] = "b" * 40
        shards.write_json(path, value)
        with self.assertRaises(ValueError):
            shards.aggregate(self.plan, evidence, self.root / "output")

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

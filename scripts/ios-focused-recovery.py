#!/usr/bin/env python3
"""Recover a completed focused run after the reviewed Capture overlay and test-host repair.

Original failures remain failures. Only the three explicitly reviewed Capture owners may change.
"""
import argparse
import json
import shlex
import importlib.util
from pathlib import Path
import re
import tempfile
import urllib.parse


def load_acceptance():
    spec = importlib.util.spec_from_file_location("acceptance", Path(__file__).with_name("ios-consolidation-acceptance.py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


a = load_acceptance()
require, shards = a.require, a.shards
REPAIR_PATHS = {
    "apps/ios/Merian/Features/Capture/Shell/Modifiers/CaptureWorkspaceOrchestrationModifier.swift",
    "apps/ios/Merian/Features/Capture/Shell/Views/CaptureFieldNotesOverlay.swift",
    "apps/ios/MerianTests/Features/Capture/Shell/CapturePhotoReviewTests.swift",
}
CAPTURE_UI_METHODS = frozenset(['testFieldNotesDragsFromToolbarAndPreservesNotesOnDismissal', 'testFieldNotesOpensPromptsWithoutDescribeWorkspace', 'testNoteAtMediaCapacityWithLargerText', 'testFieldNotesTextAreaFocusesFromLowerRegion', 'testFieldNotesReturnToSameReviewAndKeepIdentifyAboveKeyboard', 'testFinishedRecordingJoinsTrayWithoutIntermediateReview', 'testStagedAudioBadgeOpensPlaybackReview', 'testFieldNotesReviewAndConfirmedDiscard', 'testNotesToolbarNavigatesToMediaAndCaptureWithoutLosingNotes'])
POLICY_PATH = "scripts/config/ios-consolidation-acceptance.json"
CONTROL_PATHS = {
    POLICY_PATH, "scripts/ios-focused-recovery.py", "scripts/test-ios-focused-recovery.py",
    "scripts/ios-consolidation-acceptance.py", "scripts/test-ios-consolidation-acceptance.py",
    "docs/features-and-hardware/29-staged-capture-review.md",
    "docs/development-guides/08-testing-strategy.md",
    "docs/development-guides/18-ios-runtime-quality-and-benchmarking.md",
}


def outcomes(summary, tree, selectors):
    require(selectors and len(selectors) == len(set(selectors)), "Invalid focused plan")
    cases = {}
    for node in a.audit.nodes(tree):
        require(node.get("nodeType") != "Arguments", "Parameterized recovery is unsupported")
        if node.get("nodeType") != "Test Case":
            continue
        url = urllib.parse.urlsplit(node.get("nodeIdentifierURL", ""))
        parts = url.path.strip("/").split("/")
        require(url.scheme == "test" and url.netloc == "com.apple.xcode" and not url.query and not url.fragment
                and len(parts) == 4 and parts[0] in ("Merian", "merian"), "Ambiguous focused identity")
        selector = "/".join(parts[1:]).removesuffix("()")
        require(selector in selectors and selector not in cases, "Extra or duplicate focused method")
        require(node.get("result") in ("Passed", "Failed"), "Skipped or incomplete focused method")
        cases[selector] = node["result"]
    require(set(cases) == set(selectors), "Incomplete focused coverage")
    require(all(type(summary.get(k)) is int for k in ("totalTestCount", "passedTests", "failedTests", "skippedTests")), "Invalid focused summary count types")
    require(summary.get("expectedFailures", 0) == 0, "Expected failures cannot qualify")
    passed = sorted(s for s, result in cases.items() if result == "Passed")
    failed = sorted(set(cases) - set(passed))
    require(summary.get("totalTestCount") == len(cases) and summary.get("passedTests") == len(passed)
            and summary.get("failedTests") == len(failed) and summary.get("skippedTests") == 0
            and summary.get("result") == ("Failed" if failed else "Passed"), "Focused summary disagrees with cases")
    devices = tree.get("devices", [])
    keys = ("deviceId", "osVersion", "osBuildNumber", "architecture")
    require(len(devices) == 1 and all(devices[0].get(k) for k in keys), "Missing focused runtime identity")
    return {"passed": passed, "failed": failed, "device": {k: devices[0][k] for k in keys}}


def pin_record(directory, review):
    record = shards.read_json(directory / "execution.json")
    return {"execution_sha256": shards.digest(directory / "execution.json"), "source": record["source"],
            "product_tree_sha256": record["product_tree_sha256"], "review": review,
            "provenance": {k: record[k] for k in ("result_bundle", "result_bundle_sha256", "raw_sha256", "build_log_sha256", "command", "selectors", "toolchain", "destination")}}


def validate_source_identity(source):
    keys = {"source_sha", "tree", "release_source_fingerprint", "policy_sha256", "workflow_run_id", "workflow_run_attempt"}
    require(isinstance(source, dict) and set(source) == keys, "Incomplete focused source identity")
    for key, width in (("source_sha", 40), ("tree", 40), ("release_source_fingerprint", 64), ("policy_sha256", 64)):
        require(isinstance(source[key], str) and re.fullmatch("[a-f0-9]{" + str(width) + "}", source[key]), "Invalid focused source identity")
    require(source["workflow_run_id"] is None and source["workflow_run_attempt"] is None, "Expected local managed focused execution")
    require(source["tree"] == a.recovery.git("rev-parse", source["source_sha"] + "^{tree}").decode().strip(), "Focused source tree mismatch")


def verify_record(directory, pin, selectors, *, failed):
    require(isinstance(pin, dict) and pin.get("review"), "Missing independent focused evidence review")
    require(not directory.is_symlink() and shards.digest(directory / "execution.json") == pin["execution_sha256"],
            "Reviewed focused receipt changed")
    for name in ("execution.json", "original-execution.json", "build.log", "summary.json", "tests.json"):
        path = directory / name
        require(path.is_file() and path.resolve() == path.absolute(), "Linked or missing focused evidence")
    record = shards.read_json(directory / "execution.json")
    original_path = directory / "original-execution.json"
    require(shards.digest(original_path) == record["original_execution_sha256"], "Original native execution receipt changed")
    original_record = shards.read_json(original_path)
    require(all(record.get(k) == v for k, v in original_record.items()), "Original native execution was rewritten")
    require(record["source"] == pin["source"] == record["source_after"], "Focused source changed")
    require(pin["provenance"] == {k: record[k] for k in ("result_bundle", "result_bundle_sha256", "raw_sha256", "build_log_sha256", "command", "selectors", "toolchain", "destination")}, "Reviewed execution provenance changed")
    validate_source_identity(record["source"])
    require(record["product_tree_sha256"] == pin["product_tree_sha256"], "Focused product identity changed")
    require(record["selectors"] == selectors and record["toolchain"], "Focused plan/toolchain mismatch")
    require(re.fullmatch(r"platform=iOS Simulator,id=[A-Fa-f0-9-]{36}", record["destination"]), "Invalid focused destination")
    require(record["command"] == a.focused_command({"required_focused_selectors": selectors}, record["destination"]),
            "Focused command or deadlines changed")
    require((record["exit_code"] != 0) == failed, "Unexpected focused process result")
    bundle = Path(record["result_bundle"])
    require(bundle.resolve() == bundle.absolute() and bundle.resolve().is_relative_to((a.ROOT / ".artifacts/local-ios").resolve()), "Result bundle outside retained local evidence")
    require(record["bundles"] == [str(bundle)] and a.bundle_digest(bundle) == record["result_bundle_sha256"], "Focused bundle changed")
    require(shards.digest(directory / "build.log") == record["build_log_sha256"], "Focused log changed")
    require(set(record["raw_sha256"]) == {"summary", "tests"}, "Incomplete focused exports")
    for name, digest in record["raw_sha256"].items():
        require(shards.digest(directory / (name + ".json")) == digest, "Focused raw evidence changed")
    with tempfile.TemporaryDirectory() as scratch:
        raw = a.extract(bundle, Path(scratch))
        require(all(raw[k] == shards.read_json(directory / (k + ".json")) for k in raw), "Focused export disagrees with original bundle")
    result = outcomes(raw["summary"], raw["tests"], selectors)
    require(record["original_outcomes"] == result, "Original result inventory changed")
    require(bool(result["failed"]) == failed, "Unexpected focused failures")
    require(result["device"]["deviceId"].lower() == record["destination"].split("id=")[1].lower(), "Destination/runtime mismatch")
    return record, result


def validate_repair(policy, original, repaired, failures, *, delta_key="reviewed_delta"):
    repair = policy["focused_recovery"]
    require(len(policy["required_focused_selectors"]) == 40, "Unexpected combined selector plan")
    require(repair.get("review") and repair.get("applicability"), "Missing independent repair applicability review")
    require(repair["original_failed_selectors"] == failures, "Unreviewed focused failure set")
    replay = repair["replay_selectors"]
    affected = {s for s in policy["required_focused_selectors"] if s.startswith("merianTests/CaptureWorkspaceViewModelRefinementTests/") or s.rsplit("/", 1)[1] in CAPTURE_UI_METHODS}
    require(len(affected) == 26 and set(replay) == affected, "All 26 affected Capture methods must be replayed")
    require(replay and len(replay) == len(set(replay)) and set(failures) <= set(replay)
            and set(replay) < set(policy["required_focused_selectors"]), "Invalid affected replay scope")
    reuse = repair["reused_selectors"]
    require(len(reuse) == len(set(reuse)) and set(reuse) == set(policy["required_focused_selectors"]) - set(replay)
            and repair.get("reuse_review"), "Missing unaffected selector applicability review")
    before, after = a.tree_entries(original), a.tree_entries(repaired)
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    require(REPAIR_PATHS <= changed and changed <= CONTROL_PATHS | REPAIR_PATHS,
            "Unreviewed runtime, build, support or unrelated source changed")
    delta = repair[delta_key]
    require(len(delta) == len({r["path"] for r in delta}) and {r["path"] for r in delta} == changed - {POLICY_PATH},
            "Unreviewed recovery source delta")
    for entry in delta:
        path = entry["path"]
        require(entry["before"] == before.get(path) and entry["after"] == after.get(path) and entry.get("review_scope"),
                "Recovery source object changed")
        require(after[path]["mode"] == "100644" and after[path]["type"] == "blob", "Unsafe recovery file mode")
    # Every construction condition, navigation/persistence owner, seed, project,
    # resource and dependency outside the three reviewed files is unchanged.
    unchanged = {p: value for p, value in before.items() if p not in CONTROL_PATHS | REPAIR_PATHS}
    require(unchanged == {p: value for p, value in after.items() if p not in CONTROL_PATHS | REPAIR_PATHS}, "Dependency drift")
    return {"reviewed_delta": delta, "affected_methods": replay, "reused_methods": reuse,
            "reuse_review": repair["reuse_review"], "outside_reviewed_owners_unchanged": True}


def validate_control_successor(compiled, candidate):
    before, after = a.tree_entries(compiled), a.tree_entries(candidate)
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    require(changed <= CONTROL_PATHS, "Non-control change after repaired compilation")
    return sorted(changed)


def verify(policy, directory, candidate):
    repair = policy["focused_recovery"]
    original, old = verify_record(directory / "original", repair["original"], policy["required_focused_selectors"], failed=True)
    compiled = repair["compiled_source"]
    validate_source_identity(compiled)
    validate_repair(policy, original["source"]["source_sha"], compiled["source_sha"], old["failed"], delta_key="compiled_delta")
    impact = validate_repair(policy, original["source"]["source_sha"], candidate["source_sha"], old["failed"])
    validate_control_successor(compiled["source_sha"], candidate["source_sha"])

    records, completed, pins = [], [], repair["replays"]
    require(isinstance(pins, list) and pins and all(isinstance(p, dict) and isinstance(p.get("directory"), str) for p in pins), "Invalid replay pin schema")
    require(len(pins) == 1, "Exactly one complete 26-method replay receipt is required")
    for pin in pins:
        path = Path(pin["directory"])
        require(len(path.parts) == 1 and path.name not in ("", ".", "..", "original"), "Unsafe replay evidence path")
        selectors = pin["selectors"]
        require(selectors == repair["replay_selectors"], "Replay must execute the entire reviewed affected plan")
        replay, new = verify_record(directory / path, pin, selectors, failed=False)
        require(replay["source"] == compiled, "Replay differs from reviewed repaired compile source")
        require(original["toolchain"] == replay["toolchain"] and original["destination"] == replay["destination"]
                and old["device"] == new["device"], "Recovery runtime/toolchain changed")
        require(a.product_tree(policy, replay["source"]["source_sha"]) == replay["product_tree_sha256"]
                == a.product_tree(policy, candidate["source_sha"]), "Post-replay product inputs changed")
        completed.extend(new["passed"])
        records.append({"source": replay["source"], "execution_sha256": pin["execution_sha256"], "methods": new["passed"]})
    require(len(completed) == len(set(completed)) and set(completed) == set(repair["replay_selectors"]), "Affected replay incomplete or duplicated")
    require(a.product_tree(policy, original["source"]["source_sha"]) == original["product_tree_sha256"], "Original product identity changed")
    reused = repair["reused_selectors"]
    require(set(reused) <= set(old["passed"]) and set(reused) | set(completed) == set(policy["required_focused_selectors"]), "Recovery union incomplete")
    return {"cases": len(policy["required_focused_selectors"]), "methods": sorted(policy["required_focused_selectors"]),
            "original_focused_failed": True, "original_source": original["source"], "replays": records,
            "reused_methods": reused, "replayed_methods": sorted(completed), "device": old["device"],
            "original_execution_sha256": repair["original"]["execution_sha256"], "change_impact": impact}


def capture(original, output):
    """Seal additional raw exports without overwriting the failed original receipt."""
    import shutil
    require(not output.exists(), "Recovery capture destination must be new")
    record = shards.read_json(original / "execution.json")
    require(record["source"] == record["source_after"] and len(record["bundles"]) == 1,
            "Original focused run is not complete and source-stable")
    output.mkdir(parents=True)
    shutil.copy2(original / "execution.json", output / "original-execution.json")
    shutil.copy2(original / "build.log", output / "build.log")
    bundle = Path(record["bundles"][0])
    raw = a.extract(bundle, output)
    result = outcomes(raw["summary"], raw["tests"], record["selectors"])
    require(bool(result["failed"]) == (record["exit_code"] != 0), "Process/result disagreement")
    policy = shards.read_json(a.recovery.POLICY)
    record.setdefault("product_tree_sha256", a.product_tree(policy, record["source"]["source_sha"]))
    args = shlex.split(record["command"][2].removeprefix("ARGS="))
    require(args.count("-destination") == 1, "Missing canonical destination")
    record.setdefault("destination", args[args.index("-destination") + 1])
    require(record["command"] == a.focused_command({"required_focused_selectors": record["selectors"]}, record["destination"]), "Unreviewed native command")
    record.update(original_execution_sha256=shards.digest(output / "original-execution.json"),
                  result_bundle=str(bundle), result_bundle_sha256=a.bundle_digest(bundle),
                  build_log_sha256=shards.digest(output / "build.log"),
                  raw_sha256={k: shards.digest(output / (k + ".json")) for k in raw}, original_outcomes=result)
    shards.write_json(output / "execution.json", record)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    capture(args.original, args.output)


if __name__ == "__main__":
    main()

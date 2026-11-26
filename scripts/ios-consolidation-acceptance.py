#!/usr/bin/env python3
"""Validate the reviewed consolidation delta without repeating unaffected suites.

This produces engineering acceptance, never merge or distribution authority.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import urllib.parse


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


recovery = module("recovery", "ios-evidence-recovery.py")
audit = module("audit", "ios-runtime-audit.py")
shards, ROOT, require = recovery.shards, recovery.ROOT, recovery.require
RELEASE_OWNER_PATHS = {
    "project.yml", "Config.xcconfig", "Signing.xcconfig", "HistoryQualification.xcconfig",
    "scripts/validate-ios-archive.sh", "scripts/validate-ios-exported-ipa.sh",
    "scripts/validate-ios-privacy-manifest.sh", "scripts/validate-ios-transport-security.sh",
    "scripts/check-ios-release-prep.sh", "scripts/ios-release-source-fingerprint.sh",
    "docs/development-guides/14-ios-release-versioning.md",
    "docs/development-guides/16-ios-privacy-manifest.md",
    "docs/development-guides/17-ios-transport-security.md",
    "docs/legal/production-consent-readiness-2026-08-03.md",
}



def source_identity():
    result = recovery.verifier_identity()
    result["release_source_fingerprint"] = subprocess.check_output(
        ["bash", "scripts/ios-release-source-fingerprint.sh"], cwd=ROOT, text=True).strip()
    require(re.fullmatch(r"[a-f0-9]{64}", result["release_source_fingerprint"]), "Invalid source fingerprint")
    return result


def tree_entries(revision):
    entries = {}
    for row in recovery.git("ls-tree", "-r", "-z", revision).split(b"\0"):
        if not row:
            continue
        metadata, path = row.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        entries[path.decode()] = {"mode": mode, "type": kind, "object": object_id}
    return entries


def validate_full_delta(policy, candidate):
    before, after = tree_entries(policy["origin"]["source_sha"]), tree_entries(candidate)
    policy_path = "scripts/config/ios-consolidation-acceptance.json"
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    records = policy["reviewed_source_delta"]
    require(len(records) == len({r["path"] for r in records}) and {r["path"] for r in records} == changed - {policy_path},
            "Unreviewed source/control change")
    for record in records:
        require(record["before"] == before.get(record["path"]) and record["after"] == after.get(record["path"])
                and record["review_scope"].strip(), "Reviewed source/control object changed")
    # A policy cannot embed its own object hash. The exact verifier commit and
    # successful trusted recovery job bind that one object, including this list.
    require(after[policy_path]["mode"] == "100644" and after[policy_path]["type"] == "blob", "Invalid policy object")
    return {"candidate_tree": recovery.git("rev-parse", candidate + "^{tree}").decode().strip(),
            "policy_object": after[policy_path], "reviewed_source_delta": records}


def validate_delta(policy, candidate, *, whole_tree=True):
    origin = policy["origin"]["source_sha"]
    paths = policy["product_paths"]
    changed = recovery.git("diff", "--name-only", origin, candidate, "--", *paths).decode().splitlines()
    entries = policy["reviewed_product_delta"]
    require(len(entries) == len(changed) and {e["path"] for e in entries} == set(changed), "Unreviewed product change")
    for entry in entries:
        require(entry["justification"].strip(), "Missing change-impact justification")
        for revision, key in ((origin, "base_sha256"), (candidate, "candidate_sha256")):
            if entry[key] is None:
                require(entry["path"] not in tree_entries(revision), "Reviewed absent product path appeared")
            else:
                require(recovery.sha256(recovery.git("show", revision + ":" + entry["path"])) == entry[key],
                        "Reviewed product bytes changed: " + entry["path"])
    for surface, owned in policy["reused_surface_paths"].items():
        require(not recovery.git("diff", "--name-only", origin, candidate, "--", *owned).strip(),
                "Reused " + surface + " source changed; affected validation is required")
    complete = validate_full_delta(policy, candidate) if whole_tree else {}
    return {**complete, "compiled_origin": origin, "candidate": candidate, "reviewed_delta": entries,
            "unchanged_surfaces": policy["reused_surface_paths"]}


def focused_results(summary, tree, selectors):
    require(len(selectors) == len(set(selectors)) and selectors, "Duplicate or empty selector plan")
    selections = [{"selector": s, "suite_names": [s.split("/")[1]]} for s in selectors]
    audit.validate_execution(summary, tree, selections)
    actual = []
    for node in audit.nodes(tree):
        if node.get("nodeType") != "Test Case":
            continue
        url = urllib.parse.urlsplit(node.get("nodeIdentifierURL", ""))
        require(url.scheme == "test" and not url.query and not url.fragment, "Missing/ambiguous test identity")
        parts = url.path.strip("/").split("/")
        require(len(parts) == 4 and parts[0] in ("Merian", "merian"), "Unexpected compiled test target")
        actual.append("/".join(parts[1:]).removesuffix("()"))
    require(len(actual) == len(set(actual)) and set(actual) == set(selectors), "Focused method coverage mismatch")
    require(summary["totalTestCount"] == len(actual), "Focused summary/tree count mismatch")
    require(not any(n.get("nodeType") == "Arguments" for n in audit.nodes(tree)),
            "Parameterized selection requires a separately reviewed compiled inventory")
    devices = tree.get("devices", [])
    require(len(devices) == 1 and all(devices[0].get(k) for k in ("deviceId", "osVersion", "osBuildNumber", "architecture")),
            "Missing exact focused runtime identity")
    return {"methods": sorted(actual), "cases": len(actual), "device": devices[0]}


def extract(bundle, output):
    result = {}
    for kind in ("summary", "tests"):
        raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle)])
        (output / (kind + ".json")).write_bytes(raw)
        result[kind] = json.loads(raw, object_pairs_hook=shards.unique_object)
    return result


def bundle_digest(bundle):
    import hashlib
    value = hashlib.sha256()
    require(bundle.is_dir() and not bundle.is_symlink(), "Missing original XCResult")
    for path in sorted(bundle.rglob("*")):
        require(not path.is_symlink(), "Linked XCResult file")
        if path.is_file():
            value.update(path.relative_to(bundle).as_posix().encode() + b"\0")
            value.update(bytes.fromhex(shards.digest(path)))
    return value.hexdigest()


def product_tree(policy, revision):
    return recovery.sha256(recovery.git("ls-tree", "-r", "-z", revision, "--", *policy["product_paths"]))


def focused_command(policy, destination):
    args = ["simulator", "test", "-destination", destination, "-parallel-testing-enabled", "NO"]
    args += ["-only-testing:" + selector for selector in policy["required_focused_selectors"]]
    return ["make", "ios-local-build", "ARGS=" + shlex.join(args)]


def run_focused(policy, destination, output):
    """One managed invocation; failures retain their evidence and are never retried here."""
    require(re.fullmatch(r"platform=iOS Simulator,id=[A-Fa-f0-9-]{36}", destination), "Exact simulator destination required")
    require(not policy.get("successor_followups"), "Reviewed follow-ups use retained evidence; do not restart the legacy plan")
    identity = source_identity()
    validate_delta(policy, identity["source_sha"])
    require(not output.exists(), "Focused evidence destination must be new")
    output.mkdir(parents=True)
    reports = ROOT / ".artifacts/local-ios"
    before = set(reports.glob("*.xcresult"))
    command = focused_command(policy, destination)
    with (output / "build.log").open("wb") as log:
        status = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
    bundles = set(reports.glob("*.xcresult")) - before
    record = {"product_tree_sha256": product_tree(policy, identity["source_sha"]), "source": identity, "source_after": source_identity(), "command": command, "exit_code": status,
              "selectors": policy["required_focused_selectors"],
              "toolchain": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
              "destination": destination, "bundles": [str(b) for b in sorted(bundles)]}
    shards.write_json(output / "execution.json", record)
    require(status == 0 and len(bundles) == 1, "Focused run failed; preserve evidence and diagnose before retry")
    require(record["source_after"] == identity, "Source changed during focused execution")
    bundle = next(iter(bundles))
    raw = extract(bundle, output)
    coverage = focused_results(raw["summary"], raw["tests"], record["selectors"])
    record.update(build_log_sha256=shards.digest(output / "build.log"), result_bundle=str(bundle), result_bundle_sha256=bundle_digest(bundle), coverage=coverage,
                  raw_sha256={name: shards.digest(output / (name + ".json")) for name in raw})
    shards.write_json(output / "execution.json", record)
    return record


def verify_focused(policy, directory, candidate):
    pin = policy.get("focused_evidence")
    require(isinstance(pin, dict) and pin.get("review"), "Combined local execution still needs independent evidence review")
    require(shards.digest(directory / "execution.json") == pin["execution_sha256"], "Reviewed focused execution changed")
    record = shards.read_json(directory / "execution.json")
    require(record["source"]["source_sha"] == pin["compiled_source"]
            and record["source"]["tree"] == pin["compiled_tree"]
            and record["source"]["release_source_fingerprint"] == pin["source_fingerprint"]
            and record["product_tree_sha256"] == pin["product_tree_sha256"], "Reviewed focused source identity mismatch")
    require(shards.digest(directory / "build.log") == record["build_log_sha256"], "Focused command log changed")
    require(record["exit_code"] == 0 and record["source"] == record["source_after"], "Combined source changed during execution")
    compiled = record["source"]["source_sha"]
    require(re.fullmatch(r"[a-f0-9]{40}", compiled), "Invalid compiled source revision")
    require(record["source"]["tree"] == recovery.git("rev-parse", compiled + "^{tree}").decode().strip(), "Compiled source tree mismatch")
    validate_delta(policy, compiled, whole_tree=False)
    require(record["product_tree_sha256"] == product_tree(policy, compiled)
            == product_tree(policy, candidate["source_sha"]), "Combined application/build inputs changed after focused validation")
    require(record["selectors"] == policy["required_focused_selectors"] and record["toolchain"], "Focused plan/toolchain mismatch")
    require(bundle_digest(Path(record["result_bundle"])) == record["result_bundle_sha256"], "Original XCResult changed")
    for name, digest in record["raw_sha256"].items():
        require(name in ("summary", "tests") and shards.digest(directory / (name + ".json")) == digest, "Focused raw evidence changed")
    require(set(record["raw_sha256"]) == {"summary", "tests"}, "Incomplete focused evidence")
    # Regenerate from the original bundle, rather than trusting editable JSON.
    import tempfile
    with tempfile.TemporaryDirectory() as scratch:
        raw = extract(Path(record["result_bundle"]), Path(scratch))
        require(all(raw[k] == shards.read_json(directory / (k + ".json")) for k in raw), "XCResult/export mismatch")
    coverage = focused_results(raw["summary"], raw["tests"], record["selectors"])
    require(record["coverage"] == coverage, "Focused receipt changed")
    return {**coverage, "compiled_source": compiled, "compiled_source_fingerprint": record["source"]["release_source_fingerprint"],
            "product_tree_sha256": record["product_tree_sha256"], "verifier_source": candidate["source_sha"]}


def verify_combined_evidence(policy, directory, candidate):
    if policy.get("successor_followups"):
        return module("followups", "ios-consolidation-followups.py").verify(policy, directory, candidate)
    legacy, recovered = bool(policy.get("focused_evidence")), bool(policy.get("focused_recovery"))
    require(legacy != recovered, "Exactly one reviewed focused evidence route is required")
    if recovered:
        return module("focused_recovery", "ios-focused-recovery.py").verify(policy, directory, candidate)
    return verify_focused(policy, directory, candidate)


def reviewed_records(policy, field, required, evidence, candidate):
    """Only policy-pinned, independently reviewed records can close a manual gate.

    An ad-hoc JSON claiming success is deliberately insufficient. A reviewer must
    add the exact report digest and applicability assessment to the policy first.
    """
    records = policy.get(field, [])
    require(len({r["requirement"] for r in records}) == len(records), "Duplicate acceptance record")
    require({r["requirement"] for r in records} <= set(required), "Unexpected acceptance record")
    accepted = []
    for record in records:
        path = Path(record["path"])
        require(not path.is_absolute() and ".." not in path.parts, "Unsafe acceptance record path")
        require(re.fullmatch(r"[a-f0-9]{40}", record["source_sha"]) and record["applicability"].strip()
                and record["review"].strip(), "Missing acceptance provenance/review")
        owned = record.get("owned_paths", [])
        require(owned and len(set(owned)) == len(owned) and all(
            isinstance(p, str) and (p.startswith(("apps/ios/", "apps/watch/", "services/supabase/", "resources/", "merian.xcodeproj/")) or p in RELEASE_OWNER_PATHS)
            and ".." not in Path(p).parts and not any(c in p for c in "*?[]:") for p in owned), "Missing concrete applicability owner paths")
        for owner in owned:
            require(recovery.git("ls-tree", "-r", record["source_sha"], "--", owner).strip(), "Unknown evidence source/owner")
        if recovery.git("diff", "--name-only", record["source_sha"], candidate, "--", *owned).strip():
            require(field == "journey_evidence" and policy.get("successor_followups"),
                    "Historical acceptance owner changed; rerun or supply current evidence")
            module("followups", "ios-consolidation-followups.py").journey_applicability(policy, record, candidate)
        report = evidence / path
        require(report.is_file() and not report.is_symlink() and shards.digest(report) == record["sha256"],
                "Reviewed acceptance evidence missing or changed")
        accepted.append(record)
    return accepted, sorted(set(required) - {r["requirement"] for r in records})


def assess(policy, focused, evidence, output, stage, client, recovery_run, archive_run=None):
    require(policy["authorization"] == {"merge": False, "testflight_upload_or_distribution": False, "backend_or_sites_deploy": False}, "Acceptance cannot grant operation authority")
    candidate = source_identity()
    impact = validate_delta(policy, candidate["source_sha"])
    hosted = client.json(f"/actions/runs/{recovery_run}")
    require(hosted["head_sha"] == candidate["source_sha"] and hosted["path"] == policy["recovery_workflow"]
            and hosted["status"] == "completed" and hosted["conclusion"] == "success"
            and hosted["event"] in ("push", "workflow_dispatch"), "Required exact-verifier recovery workflow has not passed")
    jobs = client.listing(f"/actions/runs/{recovery_run}/attempts/{hosted['run_attempt']}/jobs", "jobs")["jobs"]
    require(len(jobs) == 1 and jobs[0]["name"] == "Recovered development evidence" and jobs[0]["conclusion"] == "success", "Missing qualifying recovery job")
    require(not output.exists(), "Acceptance output must be new")
    output.mkdir(parents=True)
    # Recollect API metadata and pinned artifacts live. This is read-only and
    # cannot turn an uploaded, self-authored collection into trusted evidence.
    recovery.collect(policy, output / "recovery-input", client)
    coverage = recovery.verify(policy, output / "recovery-input", output / "recovery", candidate)
    current = verify_combined_evidence(policy, focused, candidate)
    surface_runs = {}
    for surface, run_id in policy["reused_workflows"].items():
        run = client.json(f"/actions/runs/{run_id}")
        require(run["head_sha"] == policy["origin"]["source_sha"] and run["status"] == "completed"
                and run["conclusion"] == "success" and run["path"] == policy["reused_workflow_paths"][surface],
                "Required " + surface + " workflow is not a verified pass")
        surface_runs[surface] = {k: run[k] for k in ("id", "head_sha", "run_attempt", "path", "conclusion")}
    journeys, missing = reviewed_records(policy, "journey_evidence", policy["required_journeys"], evidence, candidate["source_sha"])
    archive = None
    if policy.get("successor_followups"):
        if archive_run is None:
            missing.append("exact-source-unsigned-release-archive")
        else:
            archive = module("followups", "ios-consolidation-followups.py").verify_archive(client, archive_run, candidate, output / "archive-evidence")
    prerequisites = []
    if stage == "qa-upload":
        required = ["exact-signed-archive-privacy-ats-history", "compatible-beta-backend", "consent-rollout-readiness"]
        prerequisites, absent = reviewed_records(policy, "qa_upload_evidence", required, evidence, candidate["source_sha"])
        missing += absent
    if stage == "testflight":
        prerequisites, absent = reviewed_records(policy, "testflight_evidence", policy["testflight_prerequisites"], evidence, candidate["source_sha"])
        missing += absent
    result = {"schema_version": 1, "stage": stage, "status": "blocked" if missing else "passed",
              "candidate": candidate, "change_impact": impact, "native_origin": coverage["compiled_source"],
              "recovery_sha256": shards.digest(output / "recovery/coverage.json"), "combined_focused": current, "unsigned_release_archive": archive,
              "recovery_workflow_run": recovery_run, "reused_surfaces": surface_runs, "journeys": journeys, "testflight_prerequisites": prerequisites,
              "unresolved": missing, "authorization": policy["authorization"],
              "old_workflow_relabelled": False, "new_full_suite_required": False,
              "classification": "local-reviewed-engineering-acceptance", "satisfies_branch_protection": False,
              "qa_upload_scope": "Organizer upload/processing preparation only; no tester assignment" if stage == "qa-upload" else None,
              "qa_assignment_prerequisites": ["completed consent distribution safety", "explicit named bounded migration-QA group authorization"] if stage == "qa-upload" else [],
              "operator_prerequisites": ["fresh repository and Vercel controls", "target-specific approval", "applicable backend cutover/activation controls"]}
    shards.write_json(output / "acceptance.json", result)
    require(not missing, "Acceptance remains blocked: " + ", ".join(missing))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    focused = commands.add_parser("run-focused")
    focused.add_argument("--destination", required=True)
    focused.add_argument("--output", required=True, type=Path)
    acceptance = commands.add_parser("assess")
    acceptance.add_argument("--recovery-run", required=True, type=int)
    acceptance.add_argument("--archive-run", type=int)
    acceptance.add_argument("--focused", required=True, type=Path)
    acceptance.add_argument("--evidence", required=True, type=Path)
    acceptance.add_argument("--output", required=True, type=Path)
    acceptance.add_argument("--stage", required=True, choices=("merge", "qa-upload", "testflight"))
    args = parser.parse_args()
    policy = shards.read_json(recovery.POLICY)
    if args.action == "run-focused":
        run_focused(policy, args.destination, args.output)
    else:
        assess(policy, args.focused, args.evidence, args.output, args.stage, recovery.GitHub(policy["repository"]), args.recovery_run, args.archive_run)


if __name__ == "__main__":
    main()

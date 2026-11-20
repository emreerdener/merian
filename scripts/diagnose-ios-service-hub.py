#!/usr/bin/env python3
"""One retained-product host experiment; never emit a qualifying receipt."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "bd9e71193f071f26700dae5804731511aad24d34"
RUN = 44641770666
BUILD_JOB = 135974923152
PLAN_HASH = "1ec4faa33e9c449b99c5d65fd0317e516fa4584dc0563469e7508fe4d39da408"
PRODUCT_HASH = "a45d5a8bda7b1d4fc20c62090c6807b45955aec9e54d6fe6bacf014cf053d4f0"
ARTIFACTS = {
    "plan": (14594256119, "ios-unit-plan-44641770666-attempt-1", 316596,
             "bdaf1a18e6b42f605bfdf3f4991801c1ebc26716cf1874ece058b9d6a5a7f82a"),
    "products": (14593931710, "ios-unit-products-44641770666-attempt-1", 340267486,
                 "9bd84e38f1d1f7e9d0313a2221912a2e6b0ec79328664900fb02a537b13a2bcf"),
}
HELPERS = {
    "ios-unit-shards.py": "379567fd6c8d595fc45b36c391080233c711e66c8b687029e998734a6e235feb",
    "discover-ios27-simulator.py": "3aaef05f33ba32ad96dcadb6338345424b74c3f8c87c9f9d023ad439f3539cf8",
    "prepare-ios-unit-simulator.py": "510486d673fe6a439772fb83d822afd5429782f9e1c58d213ee78dcb09987e67",
}
ROLES = {name: name for name in (
    "DTServiceHub", "xcodebuild", "testmanagerd", "launchd_sim",
    "SimLaunchHost", "simdiskimaged", "SimulatorTrampoline",
)}
ROLES["com.apple.CoreSimulator.CoreSimulatorService"] = "CoreSimulatorService"


def require(value):
    if not value:
        raise ValueError("Diagnostic invariant failed")


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def module(name):
    path = ROOT / "scripts" / name
    require(digest(path) == HELPERS[name])
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def execution(env):
    require(env.get("GITHUB_REPOSITORY") == "emreerdener/merian")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_ENVIRONMENT") == "github-hosted")
    require(re.fullmatch(r"[0-9a-f]{40}", env.get("GITHUB_SHA", "")))
    require(env["GITHUB_SHA"] != SOURCE)
    require(all(re.fullmatch(r"[1-9][0-9]*", env.get(k, ""))
                for k in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")))
    require(int(env["GITHUB_RUN_ID"]) != RUN)
    return {"harness_sha": env["GITHUB_SHA"], "run_id": int(env["GITHUB_RUN_ID"]),
            "run_attempt": int(env["GITHUB_RUN_ATTEMPT"])}


def base_receipt(env):
    return {"schema_version": 1, "kind": "setup_only_host_diagnostic", "qualified": False,
            "release_eligible": False, "status": "incomplete",
            "execution_provenance": execution(env),
            "product_provenance": {"source_sha": SOURCE, "run_id": RUN, "run_attempt": 1,
                                   "plan_sha256": PLAN_HASH, "products_sha256": PRODUCT_HASH,
                                   "remote_metadata_verified": False, "unpack_verified": False}}


def validate_receipt(receipt, env, *, observed=False):
    base = base_receipt(env)
    require(set(receipt) == set(base) | ({"observed_environment"} if observed else set()))
    require(receipt["status"] == ("identity_observed" if observed else "incomplete"))
    if observed:
        require(receipt["observed_environment"] == module("ios-unit-shards.py").RUNTIME)
    for key in ("schema_version", "kind", "execution_provenance"):
        require(receipt[key] == base[key])
    require(receipt["qualified"] is False and receipt["release_eligible"] is False)
    origin = receipt["product_provenance"]
    expected = base["product_provenance"]
    require(set(origin) == set(expected) | {"artifacts", "download_action_digest_policy"})
    for key in ("source_sha", "run_id", "run_attempt", "plan_sha256", "products_sha256"):
        require(origin[key] == expected[key])
    require(origin["remote_metadata_verified"] is True and type(origin["unpack_verified"]) is bool)
    require(origin["download_action_digest_policy"] == "error")
    require(origin["artifacts"] == {role: {"artifact_id": value[0], "zip_sha256": value[3]}
                                    for role, value in ARTIFACTS.items()})


def api(path):
    # Fixed repository/path callers only. Never retain headers, bodies or errors.
    request = urllib.request.Request("https://api.github.com/repos/emreerdener/merian/" + path,
                                    headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                                             "Accept": "application/vnd.github+json"})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
        raw = response.read(1024 * 1024 + 1)
    require(len(raw) <= 1024 * 1024)
    return json.loads(raw)


def verify_origin(env, get=api):
    result = base_receipt(env)
    run = get(f"actions/runs/{RUN}")
    require(run.get("id") == RUN and run.get("head_sha") == SOURCE and run.get("run_attempt") == 1)
    require(run.get("event") == "workflow_dispatch" and run.get("path") == ".github/workflows/ios-build-and-test.yml")
    job = get(f"actions/jobs/{BUILD_JOB}")
    require(job.get("id") == BUILD_JOB and job.get("run_id") == RUN
            and job.get("name") == "Compile and inventory iOS unit tests"
            and job.get("head_sha") == SOURCE and job.get("run_attempt") == 1
            and job.get("status") == "completed" and job.get("conclusion") == "success")
    bound = {}
    for role, (identifier, name, size, sha) in ARTIFACTS.items():
        artifact = get(f"actions/artifacts/{identifier}")
        require(artifact.get("id") == identifier and artifact.get("name") == name
                and artifact.get("size_in_bytes") == size and artifact.get("expired") is False
                and artifact.get("digest") == "sha256:" + sha)
        origin = artifact.get("workflow_run", {})
        require(origin.get("id") == RUN and origin.get("head_sha") == SOURCE
                and origin.get("repository_id") == 1174814681
                and origin.get("head_repository_id") == 1174814681)
        bound[role] = {"artifact_id": identifier, "zip_sha256": sha}
    result["product_provenance"].update(remote_metadata_verified=True, artifacts=bound,
                                         download_action_digest_policy="error")
    return result


def verify_inputs(receipt, directory, destination, env):
    validate_receipt(receipt, env)
    origin = receipt["product_provenance"]
    require(origin["remote_metadata_verified"] is True and origin["source_sha"] == SOURCE
            and origin["run_id"] == RUN and origin["run_attempt"] == 1)
    plan_path = directory / "ios-unit-plan.json"
    products = directory / "ios-unit-products.tar.gz"
    require(not plan_path.is_symlink() and not products.is_symlink())
    require(digest(plan_path) == PLAN_HASH and digest(products) == PRODUCT_HASH)
    plan = json.loads(plan_path.read_bytes())
    require(type(plan.get("schema_version")) is int and plan["schema_version"] == 4
            and plan["source_sha"] == SOURCE and plan["origin_run_id"] == str(RUN) and plan["build_attempt"] == "1"
            and plan["build_workspace"] == env["GITHUB_WORKSPACE"]
            and plan["products_sha256"] == PRODUCT_HASH)
    # The exact immutable plan is already digest-bound. Use the unchanged hardened
    # unpacker without changing GITHUB_* or pretending this is its original run.
    module("ios-unit-shards.py").unpack_product(plan, products, destination)
    origin["unpack_verified"] = True
    return receipt


def process_records(raw):
    records = []
    for line in raw.decode("utf-8", errors="strict").splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) != 4 or not all(re.fullmatch(r"[0-9]{1,10}", x) for x in parts[:3]):
            continue
        name = Path(parts[3]).name
        if name in ROLES:
            records.append({"role": ROLES[name], "pid": int(parts[0]),
                            "ppid": int(parts[1]), "numeric_uid": int(parts[2])})
    return {"status": "observed", "records": records[:64], "capped": len(records) > 64}


def snapshot(directory, phase, env):
    discovery = module("discover-ios27-simulator.py")
    probe = discovery.simulator.diagnostic_process
    result = {"phase": phase, "current_uid_is_root": os.getuid() == 0}
    disk = os.statvfs(env["RUNNER_TEMP"])
    result["free_mib"] = disk.f_bavail * disk.f_frsize // (1024 * 1024)

    def observe(arguments, parser):
        outcome, raw = probe(arguments, capture="stdout", limit=512 * 1024, timeout=5)
        if outcome.get("outcome") != "passed" or not outcome.get("direct_process_reaped"):
            return {"status": "unavailable"}
        try:
            return parser(raw)
        except (ValueError, KeyError, TypeError, UnicodeError):
            return {"status": "unavailable"}

    result["processes"] = observe(["ps", "-axo", "pid=,ppid=,uid=,comm="], process_records)
    result["target_runtime"] = {"status": "not_probed"}
    result["owned_device"] = {"status": "not_created"}
    # Do not add a CoreSimulator client before the operation under investigation.
    if phase == "before_prepare":
        return result
    prep = directory / "identity/preparation.json"
    prepared = json.loads(prep.read_text()) if prep.is_file() else None
    match = None
    if prepared is not None:
        require(all(prepared.get(k) == env[v] for k, v in
                    (("source_sha", "GITHUB_SHA"), ("run_id", "GITHUB_RUN_ID"), ("run_attempt", "GITHUB_RUN_ATTEMPT"))))
        require(prepared.get("status") == "prepared" and prepared.get("identity_observed") is False
                and prepared.get("runtime_identifier") == discovery.RUNTIME
                and prepared.get("device_type_identifier") == discovery.DEVICE_TYPE)
        phases = prepared.get("phases", [])
        require(isinstance(phases, list) and all(isinstance(p, dict) for p in phases))
        require([p.get("phase") for p in phases] == ["cache", "create", "boot"]
                and all(p.get("outcome") == "passed" for p in phases))
        match = re.fullmatch(r"platform=iOS Simulator,id=([0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12})",
                             prepared.get("simulator_destination", ""))
        require(match is not None)
    if phase == "before_test":
        require(prepared is not None)
        result["target_runtime"] = {"status": "verified_at_preparation"}
        result["owned_device"] = {"status": "boot_completed_at_preparation"}
        return result

    def runtime(raw):
        matches = [r for r in json.loads(raw)["runtimes"] if r.get("identifier") == discovery.RUNTIME]
        if len(matches) != 1:
            return {"status": "absent" if not matches else "ambiguous"}
        exact = all(matches[0].get(k) == v for k, v in
                    {"version": discovery.VERSION, "buildversion": discovery.BUILD, "isAvailable": True}.items())
        return {"status": "available" if exact else "unavailable"}

    result["target_runtime"] = observe(["xcrun", "simctl", "list", "runtimes", "--json"], runtime)
    if match:
        def device(raw):
            entries = json.loads(raw)["devices"].get(discovery.RUNTIME, [])
            matches = [d for d in entries if d.get("udid") == match[1]]
            require(len(matches) == 1)
            state = matches[0].get("state")
            require(state in ("Booted", "Shutdown", "Booting", "Shutting Down"))
            return {"status": "observed", "state": state}
        result["owned_device"] = observe(["xcrun", "simctl", "list", "devices", "--json"], device)
    return result


def finish(receipt, directory, env):
    validate_receipt(receipt, env)
    require(receipt["product_provenance"]["unpack_verified"] is True)
    # Validate fresh harness execution with its REAL identity, never the product
    # origin's environment. Discard the ordinary verifier receipt; only a nested
    # runtime observation is retained in this permanently nonqualifying envelope.
    observation = module("discover-ios27-simulator.py").verify(directory / "identity", env=env)
    require(observation["observed_environment"] == {
        "SIMULATOR_RUNTIME_VERSION": "27.2", "SIMULATOR_RUNTIME_BUILD_VERSION": "24B8117",
        "SIMULATOR_MODEL_IDENTIFIER": "iPhone19,2"})
    receipt.update(status="identity_observed", observed_environment=observation["observed_environment"])
    return receipt


SUITES = {
    'merianTests/CaptureVideoSavedModelTests',
    'merianTests/ObservationVideoCompletionTests',
    'merianTests/ObservationVideoResumeSubmissionTests',
}
SUITE_ARGUMENTS = {
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
}


def suite_diagnostic(directory, inputs, env, *, completed):
    """Three fixed complete retained suites; this namespace never feeds native coverage."""
    shards = module("ios-unit-shards.py")
    receipt = shards.read_json(directory / "diagnostic.json")
    validate_receipt(receipt, env, observed=True)
    require(receipt["product_provenance"]["unpack_verified"] is True)
    plan_path = inputs / "ios-unit-plan.json"
    require(not plan_path.is_symlink() and digest(plan_path) == PLAN_HASH)
    plan = shards.read_json(plan_path)
    require(type(plan.get("schema_version")) is int and plan["schema_version"] == 4
            and plan["source_sha"] == SOURCE and plan["origin_run_id"] == str(RUN) and plan["build_attempt"] == "1"
            and plan["build_workspace"] == env["GITHUB_WORKSPACE"] and plan["products_sha256"] == PRODUCT_HASH)
    expected = sorted(m for m in plan["inventory"] if shards.suite(m) in SUITES)
    require(expected == sorted(SUITE_ARGUMENTS))
    qualification = module("discover-ios27-simulator.py").verify(directory / "identity", env=env)
    require(qualification["observed_environment"] == shards.RUNTIME)
    selected = directory / "suite"
    require(shards.inventory(selected / "enumeration.txt", plan=plan) == expected)
    result = {"schema_version": 1, "kind": "retained_product_suite_diagnostic",
              "qualified": False, "release_eligible": False, "status": "inventory_verified",
              "execution_provenance": execution(env), "product_provenance": receipt["product_provenance"],
              "suites": sorted(SUITES), "expected_methods": expected, "expected_argument_counts": SUITE_ARGUMENTS,
              "files": {"suite/enumeration.txt": digest(selected / "enumeration.txt"),
                        "diagnostic.json": digest(directory / "diagnostic.json")},
              "identity_files": qualification["files"]}
    if completed:
        require(env.get("IOS_SUITE_ENUMERATION_OUTCOME") == "success")
        methods, leaves = [], 0
        outcomes = {
            "merianTests/CaptureVideoSavedModelTests": "IOS_SAVED_MODEL_OUTCOME",
            "merianTests/ObservationVideoCompletionTests": "IOS_COMPLETION_OUTCOME",
            "merianTests/ObservationVideoResumeSubmissionTests": "IOS_RESUME_OUTCOME",
        }
        for suite in sorted(SUITES):
            require(env.get(outcomes[suite]) == "success")
            name = suite.split("/")[1]
            evidence = selected / name
            tree = shards.read_json(evidence / "tests.json")
            executed, arguments = shards.result_methods(shards.read_json(evidence / "summary.json"), tree, qualification,
                context={"source_sha": env["GITHUB_SHA"], "run_id": env["GITHUB_RUN_ID"], "run_attempt": env["GITHUB_RUN_ATTEMPT"]})
            require(executed == [m for m in expected if shards.suite(m) == suite])
            def counts(node):
                if node.get("nodeType") == "Test Case":
                    method = shards.canonical("merianTests/" + node["nodeIdentifier"])
                    require(len(node.get("children", [])) == SUITE_ARGUMENTS[method])
                for child in node.get("children", []):
                    counts(child)
            for node in tree["testNodes"]:
                counts(node)
            methods.extend(executed)
            leaves += arguments
            result["files"].update({"suite/" + name + "/" + file: digest(evidence / file)
                                    for file in ("summary.json", "tests.json")})
        require(sorted(methods) == expected and leaves == 56)
        result.update(status="passed", methods=sorted(methods), parameter_leaves=leaves)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("origin", "inputs", "snapshot", "finish", "suite-enumeration", "finish-suite"))
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--products", type=Path)
    parser.add_argument("--phase", choices=("before_prepare", "before_test", "after_test"))
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    is_suite = args.action in ("suite-enumeration", "finish-suite")
    path = args.directory / ("suite-diagnostic.json" if is_suite else "diagnostic.json")
    receipt = base_receipt(os.environ)
    valid_receipt = False
    try:
        for name in HELPERS:
            require(digest(ROOT / "scripts" / name) == HELPERS[name])
        if is_suite:
            require(args.inputs is not None)
            receipt = suite_diagnostic(args.directory, args.inputs, os.environ, completed=args.action == "finish-suite")
        elif args.action == "origin":
            receipt = verify_origin(os.environ)
        elif args.action == "snapshot":
            require(args.phase is not None)
            value = snapshot(args.directory, args.phase, os.environ)
            (args.directory / (args.phase + ".json")).write_text(json.dumps(value, indent=2) + "\n")
            return 0
        else:
            receipt = json.loads(path.read_text())
            validate_receipt(receipt, os.environ)
            valid_receipt = True
            if args.action == "inputs":
                require(args.inputs is not None and args.products is not None)
                receipt = verify_inputs(receipt, args.inputs, args.products, os.environ)
            else:
                receipt = finish(receipt, args.directory, os.environ)
    except (ValueError, OSError, KeyError, TypeError) as error:
        if not valid_receipt:
            receipt = base_receipt(os.environ)
        if is_suite:
            receipt["kind"] = "retained_product_suite_diagnostic"
        receipt.update(status="failed", failure_kind=type(error).__name__)
        path.write_text(json.dumps(receipt, indent=2) + "\n")
        return 1
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

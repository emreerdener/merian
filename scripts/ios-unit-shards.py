#!/usr/bin/env python3
"""Inventory every method; reconcile hosted suites and disclose separate integration."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import tarfile
import uuid
from urllib.parse import unquote, urlsplit

TARGET = "merianTests"
# Xcode's full flat enumeration also reports these XCTest lifecycle bases.
# Neither declares test methods. Preserve their presence separately from methods;
# unknown bare suite selectors fail instead of silently dropping possible tests.
EMPTY_SUPPORT_SUITES = {TARGET + "/ConsentManagerTestCase", TARGET + "/OfflineQueueTestCase"}
SHARDS = 16
TOOLCHAIN = "Xcode 27.0 Build version 27A266a"
RUNTIME = {"SIMULATOR_RUNTIME_VERSION": "27.2",
           "SIMULATOR_RUNTIME_BUILD_VERSION": "24B8117",
           "SIMULATOR_MODEL_IDENTIFIER": "iPhone19,2"}
PRODUCT = "tests.xctestproducts"
MAX_JSON = 64 * 1024 * 1024
# This existing opt-in integration requires an owned disposable SQL bridge.
# Preserve it in the compiled inventory, but never claim that unarmed hosted
# execution qualifies it. No other method may leave the ordinary shard union.
SEPARATE_INTEGRATIONS = ["merianTests/SharedMediaNativeLiteralRecoveryTests/"
                         "nativeCandidateAndSQLRepliesRemainLiteralThroughDurableRecovery"]
REQUALIFICATION_SUITES = {"merianTests/" + name for name in (
    "PinnedPhotoUploadTaskTests", "CaptureNativePhotoRoleAllocationTests", "AppleFoundationVisualCueProviderTests")}
FOUNDATION_METHODS = {"merianTests/AppleFoundationVisualCueProviderTests/" + name for name in (
    "schemaCanBeConstructed", "detailPresenceDoesNotPublishAnUnfinishedObject",
    "completedCuePublishesWhileTheNextCueIsStillStreaming", "malformedEntriesDoNotShiftLaterCueIndices",
    "mappingBoundsEvenAnOversizedResponse", "completeModelOutputStillPassesThroughIdentityValidation",
    "emptyOrUnrelatedContentProducesNoCues")}
# These protected methods have fixed literal argument arrays in the candidate.
# General compiled enumeration identifies methods, not dynamic argument values.
REQUALIFICATION_ARGUMENT_COUNTS = {
    "merianTests/PinnedPhotoUploadTaskTests/maximumOriginalStreamResources(cancelHalfway:)": 2,
    "merianTests/CaptureNativePhotoRoleAllocationTests/freshCaptureSendsOneFrozenSourceAndFencesChanges(duringTicket:)": 7,
    "merianTests/CaptureNativePhotoRoleAllocationTests/firstOriginalPutChecksExactProgressOnce(_:)": 3,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def read_json(path):
    require(Path(path).is_file() and Path(path).stat().st_size <= MAX_JSON, "Invalid JSON evidence file")
    return json.loads(Path(path).read_text(), object_pairs_hook=unique_object)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def identity(context=None):
    result = {key: (context[key] if context is not None else os.environ.get(env, "")) for key, env in (
        ("source_sha", "GITHUB_SHA"), ("run_id", "GITHUB_RUN_ID"),
        ("run_attempt", "GITHUB_RUN_ATTEMPT"))}
    require(re.fullmatch(r"[0-9a-f]{40}", result["source_sha"]), "Missing exact source SHA")
    for key in ("run_id", "run_attempt"):
        require(re.fullmatch(r"[1-9][0-9]*", result[key]), "Missing run identity")
    return result


def build_identity(context=None):
    current = identity(context)
    attempt = context["build_attempt"] if context is not None else os.environ.get("IOS_UNIT_BUILD_ATTEMPT", current["run_attempt"])
    require(re.fullmatch(r"[1-9][0-9]*", attempt), "Missing build attempt")
    return {"source_sha": current["source_sha"], "origin_run_id": current["run_id"], "build_attempt": attempt}


def execution_context(plan, attempt=None, *, context=None):
    """Validate old evidence explicitly; never rewrite the aggregate's environment."""
    origin, current = build_identity(context), identity(context)
    require(all(plan.get(k) == v for k, v in origin.items()), "Plan source/run/build attempt mismatch")
    build = int(origin["build_attempt"])
    require(build <= int(current["run_attempt"]) <= build + 1, "Only one failed-jobs retry is allowed")
    attempt = current["run_attempt"] if attempt is None else attempt
    require(isinstance(attempt, str) and re.fullmatch(r"[1-9][0-9]*", attempt)
            and build <= int(attempt) <= int(current["run_attempt"]), "Invalid execution attempt")
    return {"source_sha": origin["source_sha"], "run_id": origin["origin_run_id"], "run_attempt": attempt}


def provenance(plan, attempt=None, *, context=None):
    execution_identity = execution_context(plan, attempt, context=context)
    return {**build_identity(context), "execution_attempt": execution_identity["run_attempt"]}


def artifact_ids(context=None):
    result = {role: (context["artifact_ids"][role] if context is not None else os.environ.get("IOS_UNIT_" + role.upper() + "_ID", ""))
              for role in ("products", "plan", "requalification")}
    require(all(re.fullmatch(r"[1-9][0-9]*", value) for value in result.values())
            and len(set(result.values())) == 3, "Missing or duplicate immutable artifact IDs")
    return result


def plan_digest(context=None):
    return context["plan_sha256"] if context is not None else os.environ.get("IOS_UNIT_PLAN_SHA256")


def canonical(selector):
    require(isinstance(selector, str) and 0 < len(selector) <= 4096, "Invalid test identifier")
    require(not any(ord(c) < 33 or ord(c) == 127 for c in selector), "Non-identifier enumeration line")
    parts = selector.split("/")
    require(len(parts) >= 3 and parts[0] == TARGET and all(parts), "Unexpected test target or identifier")
    require(all(p not in (".", "..") for p in parts) and "?" not in selector, "Invalid method identifier")
    # XCTest's result identifier adds () to the enumerated selector. Preserve
    # every other character, including Swift Testing's argument labels.
    return selector[:-2] if selector.endswith("()") else selector


def inventory(path, *, full_target=False, plan=None):
    require(Path(path).stat().st_size <= MAX_JSON, "Oversized compiled inventory")
    lines = Path(path).read_text().splitlines()
    require(len(lines) > 1 and lines[0] == "Plan Merian", "Missing or unexpected compiled test plan header")
    require(all(line.startswith("\t") and not line.startswith("\t\t") for line in lines[1:]),
            "Invalid compiled selector indentation")
    # Xcode retains the complete target in selected enumeration and annotates
    # every unselected entry. Never discard that complement: bind it to the plan.
    suffix = " (disabled)"
    entries = [(line[1:-len(suffix)] if line.endswith(suffix) else line[1:], line.endswith(suffix))
               for line in lines[1:]]
    require(not full_target or not any(disabled for _, disabled in entries), "Full target contains disabled entries")
    empty = [selector for selector, _ in entries if selector in EMPTY_SUPPORT_SUITES]
    require(len(empty) == len(set(empty)) and set(empty) == EMPTY_SUPPORT_SUITES,
            "Missing, duplicate or unexpected empty support suite")
    require(all(disabled == (not full_target) for selector, disabled in entries if selector in EMPTY_SUPPORT_SUITES),
            "Incorrect empty support suite selection state")
    methods = [(canonical(selector), disabled) for selector, disabled in entries if selector not in EMPTY_SUPPORT_SUITES]
    all_methods = [method for method, _ in methods]
    require(all_methods and not any(suite(method) in EMPTY_SUPPORT_SUITES for method in all_methods),
            "Empty support suite contains executable methods")
    require(len(set(all_methods)) == len(all_methods), "Duplicate compiled test identifier")
    if not full_target:
        require(isinstance(plan, dict) and sorted(all_methods) == plan.get("inventory"),
                "Selected enumeration does not retain the complete planned target")
    enabled = sorted(method for method, disabled in methods if not disabled)
    require(enabled, "No selected executable methods")
    return enabled


def suite(identifier):
    return "/".join(identifier.split("/")[:2])


def partition(methods, weights):
    groups = {}
    for method in methods:
        groups.setdefault(suite(method), []).append(method)
    require(groups, "No compiled unit suites")
    count = min(SHARDS, len(groups))
    shards = [{"index": index, "suites": [], "methods": [], "scheduling_weight": 0}
              for index in range(count)]
    # Historical weights only schedule work; they never remove tests, assert
    # performance, or change a test's timeout. Unknown suites remain mandatory.
    def weight(name):
        return max(len(groups[name]) * 5, weights.get(name.split("/", 1)[1], 0))
    for name in sorted(groups, key=lambda name: (-weight(name), name)):
        shard = min(shards, key=lambda item: (item["scheduling_weight"], item["index"]))
        shard["suites"].append(name)
        shard["methods"].extend(groups[name])
        shard["scheduling_weight"] += weight(name)
    for shard in shards:
        shard["suites"].sort()
        shard["methods"].sort()
    return shards


def make_plan(enumeration, products, weights):
    methods = inventory(enumeration, full_target=True)
    require(FOUNDATION_METHODS.issubset(methods), "Required iOS 27 parser inventory is incomplete")
    ordinary = hosted_methods(methods, SEPARATE_INTEGRATIONS)
    require(isinstance(weights, dict) and all(isinstance(k, str) and type(v) is int
            and 0 < v < 86400 for k, v in weights.items()), "Invalid scheduling weights")
    return {"schema_version": 4, **build_identity(), "toolchain": TOOLCHAIN,
            "configuration": "Debug", "runtime": RUNTIME, "target": TARGET,
            "build_workspace": os.environ["GITHUB_WORKSPACE"],
            "products_sha256": digest(products), "inventory": methods,
            "enumeration_sha256": digest(enumeration), "empty_support_suites": sorted(EMPTY_SUPPORT_SUITES),
            "separate_integrations": list(SEPARATE_INTEGRATIONS),
            "shards": partition(ordinary, weights)}


def hosted_methods(methods, integrations):
    require(integrations == SEPARATE_INTEGRATIONS, "Unreviewed integration classification")
    require(set(integrations).issubset(methods), "Required integration absent from compiled inventory")
    integration_suites = {suite(method) for method in integrations}
    require([m for m in methods if suite(m) in integration_suites] == integrations,
            "Integration suite changed; review its complete method classification")
    return [m for m in methods if m not in integrations]


def load_plan(path, *, require_workspace=True, context=None):
    require(digest(path) == plan_digest(context), "Plan digest mismatch")
    plan = read_json(path)
    execution_context(plan, context=context)
    require(type(plan.get("schema_version")) is int and plan.get("schema_version") == 4 and plan.get("toolchain") == TOOLCHAIN
            and plan.get("configuration") == "Debug" and plan.get("runtime") == RUNTIME
            and plan.get("target") == TARGET, "Plan qualification mismatch")
    require(isinstance(plan.get("build_workspace"), str) and plan["build_workspace"].startswith("/"), "Invalid build workspace")
    require(not require_workspace or plan.get("build_workspace") == os.environ.get("GITHUB_WORKSPACE"),
            "Compiled source paths require the same checkout location on each runner")
    methods = plan.get("inventory")
    require(isinstance(methods, list) and methods and methods == sorted(set(methods))
            and all(canonical(x) == x for x in methods), "Invalid plan inventory")
    require(FOUNDATION_METHODS.issubset(methods), "Required iOS 27 parser inventory is incomplete")
    ordinary = hosted_methods(methods, plan.get("separate_integrations"))
    require(plan.get("empty_support_suites") == sorted(EMPTY_SUPPORT_SUITES)
            and not any(suite(method) in EMPTY_SUPPORT_SUITES for method in methods)
            and isinstance(plan.get("enumeration_sha256"), str)
            and re.fullmatch(r"[a-f0-9]{64}", plan["enumeration_sha256"]), "Invalid full enumeration binding")
    shards = plan.get("shards")
    require(isinstance(shards, list) and len(shards) == min(SHARDS, len({suite(x) for x in ordinary})),
            "Invalid shard count")
    assigned, owned_suites = [], []
    for index, shard in enumerate(shards):
        require(shard.get("index") == index and type(shard.get("index")) is int, "Invalid shard index")
        selected = shard.get("methods")
        require(isinstance(selected, list) and selected and selected == sorted(set(selected)), "Empty/duplicate shard")
        names = sorted({suite(x) for x in selected})
        require(shard.get("suites") == names, "Suite assignment mismatch")
        require(selected == [x for x in methods if suite(x) in names], "A suite was split or omitted")
        assigned.extend(selected)
        owned_suites.extend(names)
    require(sorted(assigned) == ordinary and len(set(owned_suites)) == len(owned_suites),
            "Incomplete or overlapping shard partition")
    require(re.fullmatch(r"[a-f0-9]{64}", plan.get("products_sha256", "")), "Invalid product digest")
    return plan


def selected_shard(plan, index):
    require(0 <= index < len(plan["shards"]), "Shard index out of range")
    return plan["shards"][index]


def validate_members(members):
    names = {}
    for member in members:
        parts = PurePosixPath(member.name).parts
        require(parts and parts[0] == PRODUCT and posixpath.normpath(member.name) == member.name
                and not PurePosixPath(member.name).is_absolute()
                and all(p not in (".", "..") for p in parts), "Unsafe product archive path")
        require(member.name not in names, "Duplicate product archive member")
        require(member.isfile() or member.isdir() or member.issym(), "Unsupported product archive member")
        names[member.name] = member
    require(PRODUCT in names, "Missing portable product")
    for name, member in names.items():
        for parent in PurePosixPath(name).parents:
            require(str(parent) not in names or not names[str(parent)].issym(), "Archive writes through a symlink")
        if member.issym():
            require(not posixpath.isabs(member.linkname), "Absolute product symlink")
            target = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
            require(target == PRODUCT or target.startswith(PRODUCT + "/"), "Escaping product symlink")
            # Every link must end inside the known product member graph. Chained
            # links are resolved without touching the destination filesystem.
            seen = set()
            while True:
                require(target not in seen, "Cyclic product symlink")
                seen.add(target)
                changed = False
                pieces = target.split("/")
                for size in range(1, len(pieces) + 1):
                    prefix = "/".join(pieces[:size])
                    link = names.get(prefix)
                    if link is not None and link.issym():
                        require(not posixpath.isabs(link.linkname), "Absolute product symlink")
                        target = posixpath.normpath(posixpath.join(posixpath.dirname(prefix), link.linkname, *pieces[size:]))
                        require(target == PRODUCT or target.startswith(PRODUCT + "/"), "Escaping product symlink chain")
                        changed = True
                        break
                if not changed:
                    require(target in names, "Dangling product symlink")
                    break


def pack_product(product, output):
    product = Path(product)
    require(product.exists() and not product.is_symlink(), "Missing portable test product")
    paths = [product] + (sorted(product.rglob("*")) if product.is_dir() else [])
    with tarfile.open(output, "w:gz", compresslevel=1) as archive:
        members = []
        for path in paths:
            archive.inodes.clear()  # Copy hardlinked files; retain framework symlinks.
            name = PRODUCT if path == product else PRODUCT + "/" + path.relative_to(product).as_posix()
            member = archive.gettarinfo(str(path), arcname=name)
            member.uid = member.gid = 0
            member.uname = member.gname = ""
            members.append(member)
            if member.isfile():
                with path.open("rb") as stream:
                    archive.addfile(member, stream)
            else:
                archive.addfile(member)
        validate_members(members)


def unpack_product(plan, products, destination):
    require(digest(products) == plan["products_sha256"], "Compiled product digest mismatch")
    destination = Path(destination)
    require(not destination.exists(), "Product extraction requires a fresh directory")
    with tarfile.open(products, "r:gz") as archive:
        members = archive.getmembers()
        validate_members(members)
        require(sum(m.size for m in members) <= 16 * 1024**3, "Oversized product archive")
        destination.mkdir(parents=True)
        # Files/directories first, links last. Never follow an archive link on write.
        for member in sorted(members, key=lambda m: (m.issym(), m.name.count("/"), m.name)):
            path = destination / member.name
            path.parent.mkdir(parents=True, exist_ok=True)
            if member.isdir():
                path.mkdir(exist_ok=True)
            elif member.issym():
                path.symlink_to(member.linkname)
            else:
                with archive.extractfile(member) as source, path.open("xb") as output:
                    shutil.copyfileobj(source, output)
                path.chmod(member.mode & 0o777)


def observed_device(observation, *, context=None):
    """Identity observation is required but never itself release qualification."""
    require(isinstance(observation, dict) and type(observation.get("schema_version")) is int and observation["schema_version"] == 1
            and observation.get("qualified") is False and observation.get("release_eligible") is False
            and observation.get("status") == "passed" and observation.get("identity_observed") is True
            and observation.get("observation_method") == "xctest_attachment"
            and observation.get("architecture") == "arm64"
            and observation.get("runtime_identifier") == "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
            and observation.get("device_type_identifier") == "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
            and observation.get("observed_environment") == RUNTIME, "Unverified shard simulator identity")
    require(re.fullmatch(r"iPhone[0-9]{1,2},[0-9]{1,2}", RUNTIME["SIMULATOR_MODEL_IDENTIFIER"]), "Runtime model has not been observed")
    require(all(observation.get(k) == v for k, v in (identity() if context is None else context).items()), "Stale simulator identity evidence")
    phases = observation.get("phases")
    require(isinstance(phases, list) and len(phases) == 3 and all(isinstance(p, dict) for p in phases),
            "Missing simulator preparation phases")
    require([p.get("phase") for p in phases] == ["cache", "create", "boot"]
            and all(p.get("outcome") == "passed" and type(p.get("elapsed_ms")) is int and p["elapsed_ms"] >= 0
                    for p in phases), "Incomplete simulator preparation")
    files = observation.get("files")
    fixed = {"preparation.json", "summary.json", "tests.json", "attachments/manifest.json"}
    require(isinstance(files, dict) and len(files) == 5 and fixed.issubset(files)
            and all(isinstance(v, str) and re.fullmatch(r"[a-f0-9]{64}", v) for v in files.values()),
            "Missing identity evidence digests")
    attachment = next(iter(set(files) - fixed))
    require(re.fullmatch(r"attachments/[^/\\]+", attachment) and Path(attachment).name not in (".", ".."),
            "Invalid identity attachment digest path")
    destination = observation.get("simulator_destination", "")
    match = re.fullmatch(r"platform=iOS Simulator,id=([A-Fa-f0-9-]{36})", destination)
    require(match is not None, "Invalid observed simulator destination")
    require(str(uuid.UUID(match.group(1))).upper() == match.group(1).upper(), "Invalid simulator UUID")
    return match.group(1)


def result_methods(summary, tree, qualification, *, context=None):
    require(summary.get("result") == "Passed", "Native summary did not pass")
    for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
        require(type(summary.get(key)) is int, "Invalid native test count")
    require(summary["totalTestCount"] > 0 and summary["passedTests"] == summary["totalTestCount"]
            and summary["failedTests"] == summary["skippedTests"] == 0, "Incomplete, failed or skipped native tests")
    device = observed_device(qualification, context=context)
    devices = tree.get("devices")
    require(isinstance(devices, list) and len(devices) == 1, "Multiple/missing test devices")
    require(all(devices[0].get(k) == v for k, v in {"architecture": "arm64", "deviceId": device,
            "osBuildNumber": "24B8117", "osVersion": "27.2", "platform": "iOS Simulator"}.items()),
            "Result device differs from qualified simulator")
    configs = tree.get("testPlanConfigurations")
    require(isinstance(configs, list) and len(configs) == 1, "Multiple/missing test configurations")
    methods, arguments = [], set()
    def visit(node, parent=None, parent_url=None):
        require(isinstance(node, dict), "Malformed native test tree")
        kind = node.get("nodeType")
        require(kind in ("Test Plan", "Unit test bundle", "Test Suite", "Test Case", "Arguments"),
                "Unexpected test node or failure/skip diagnostic")
        require(node.get("result") == "Passed", "Non-passing node in native tree")
        children = node.get("children", [])
        require(isinstance(children, list), "Invalid test children")
        if kind == "Unit test bundle":
            require(node.get("name") == TARGET, "Unexpected executed test bundle")
        if kind == "Test Case":
            require(parent == "Test Suite", "Test case outside a suite")
            method = canonical(TARGET + "/" + node.get("nodeIdentifier", ""))
            url = node.get("nodeIdentifierURL", "")
            parsed = urlsplit(url)
            components = [unquote(x) for x in parsed.path.split("/")[1:]]
            require(parsed.scheme == "test" and parsed.netloc == "com.apple.xcode"
                    and not parsed.query and len(components) >= 4 and components[1] == TARGET,
                    "Unbound result method URL")
            require(canonical("/".join(components[1:])) == method, "Result method URL/identifier mismatch")
            require(":" not in method or children, "Parameterized method has no argument results")
            methods.append(method)
            require(all(c.get("nodeType") == "Arguments" for c in children), "Unexpected method child")
            if method in REQUALIFICATION_ARGUMENT_COUNTS:
                require(len(children) == REQUALIFICATION_ARGUMENT_COUNTS[method], "Protected parameter argument coverage is incomplete")
        elif kind == "Arguments":
            require(parent == "Test Case" and not children, "Invalid parameter leaf")
            url = node.get("nodeIdentifierURL", "")
            parsed = urlsplit(url)
            # Xcode emits opaque argument IDs, including short UTF-8 hex values.
            # Bound their size without assuming they are SHA-256 digests.
            require(not parsed.fragment and url == parent_url + "?" + parsed.query
                    and re.fullmatch(r"args=(?:[a-f0-9]{2}){1,2048}", parsed.query)
                    and url not in arguments, "Missing or duplicate parameter identity")
            arguments.add(url)
        else:
            require(children, "Empty native test container")
        for child in children:
            visit(child, kind, node.get("nodeIdentifierURL"))
    roots = tree.get("testNodes")
    require(isinstance(roots, list) and len(roots) == 1 and roots[0].get("nodeType") == "Test Plan",
            "Missing or multiple native test plans")
    visit(roots[0])
    require(len(methods) == len(set(methods)) == summary["totalTestCount"], "Duplicate/missing native methods")
    return sorted(methods), len(arguments)


def receipt(plan, index, directory, *, attempt=None, context=None):
    directory = Path(directory)
    shard = selected_shard(plan, index)
    require(inventory(directory / "enumeration.txt", plan=plan) == shard["methods"], "Selected enumeration differs from plan")
    methods, arguments = result_methods(read_json(directory / "summary.json"), read_json(directory / "tests.json"),
                                        read_json(directory / "qualification.json"), context=execution_context(plan, attempt, context=context))
    require(methods == shard["methods"], "Executed methods differ from compiled inventory")
    return {"schema_version": 2, **provenance(plan, attempt, context=context), "shard": index, "toolchain": TOOLCHAIN,
            "plan_sha256": plan_digest(context), "products_sha256": plan["products_sha256"],
            "methods": methods, "parameter_leaves": arguments, "status": "passed",
            "files": {name: digest(directory / name) for name in
                      ("enumeration.txt", "summary.json", "tests.json", "qualification.json")}}


def focused_methods(plan):
    expected = [m for m in plan["inventory"] if suite(m) in REQUALIFICATION_SUITES]
    require({suite(m) for m in expected} == REQUALIFICATION_SUITES
            and set(REQUALIFICATION_ARGUMENT_COUNTS).issubset(expected), "Missing transport requalification methods")
    return expected


def requalification(directory, *, require_workspace=True, context=None):
    """Focused prerequisite, never a substitute for complete shard coverage."""
    directory = Path(directory)
    plan = load_plan(directory / "plan.json", require_workspace=require_workspace, context=context)
    full = inventory(directory / "full-inventory.txt", full_target=True)
    require(full == plan["inventory"], "Focused full inventory differs from immutable plan")
    require(digest(directory / "full-inventory.txt") == plan["enumeration_sha256"],
            "Focused full enumeration digest differs from immutable plan")
    require(FOUNDATION_METHODS.issubset(full), "Required iOS 27 parser inventory is incomplete")
    expected = focused_methods(plan)
    require(inventory(directory / "enumeration.txt", plan=plan) == expected, "Focused enumeration differs from complete compiled suites")
    tree = read_json(directory / "tests.json")
    methods, leaves = result_methods(read_json(directory / "summary.json"), tree,
                                     read_json(directory / "qualification.json"), context=execution_context(plan, plan["build_attempt"], context=context))
    require(methods == expected, "Focused execution differs from complete compiled suites")
    return {"schema_version": 2, **provenance(plan, plan["build_attempt"], context=context), "toolchain": TOOLCHAIN, "runtime": RUNTIME,
            "status": "passed", "release_eligible": False, "methods": methods, "parameter_leaves": leaves,
            "plan_sha256": digest(directory / "plan.json"), "products_sha256": plan["products_sha256"],
            "files": {name: digest(directory / name) for name in (
                "plan.json", "full-inventory.txt", "enumeration.txt", "summary.json", "tests.json", "qualification.json")}}


SHARD_FILES = {"enumeration.txt", "summary.json", "tests.json", "qualification.json", "receipt.json"}
OUTCOME_KEYS = {"identity", "enumeration", "native", "receipt"}


def execution(plan, index, directory, outcomes, *, attempt=None, context=None):
    """Retain every attempt; only recomputed, complete raw results can pass."""
    directory = Path(directory)
    shard = selected_shard(plan, index)
    execution_identity = provenance(plan, attempt, context=context)
    require(isinstance(outcomes, dict) and set(outcomes) == OUTCOME_KEYS
            and all(v in ("success", "failure", "cancelled", "skipped") for v in outcomes.values()),
            "Invalid execution outcomes")
    files = {p.name for p in directory.iterdir() if p.name != "execution.json"}
    require(files <= SHARD_FILES and all((directory / name).is_file() and not (directory / name).is_symlink()
            for name in files), "Unexpected shard evidence files")
    passed = all(value == "success" for value in outcomes.values())
    if passed:
        require(files == SHARD_FILES, "Missing passed shard evidence")
        require(read_json(directory / "receipt.json") == receipt(plan, index, directory, attempt=attempt, context=context),
                "Shard receipt mismatch")
    else:
        require("receipt.json" not in files, "Failed execution carries a passing receipt")
    assignment = hashlib.sha256(json.dumps({"suites": shard["suites"], "methods": shard["methods"]},
                                         sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"schema_version": 1, **execution_identity, "shard": index, "status": "passed" if passed else "failed",
            "outcomes": outcomes, "toolchain": TOOLCHAIN, "runtime": RUNTIME,
            "plan_sha256": plan_digest(context), "products_sha256": plan["products_sha256"],
            "artifact_ids": artifact_ids(context), "assignment_sha256": assignment,
            "files": {name: digest(directory / name) for name in sorted(files)}}


def shard_artifact(plan, index, attempt):
    return f"ios-unit-shard-{plan['origin_run_id']}-build-{plan['build_attempt']}-attempt-{attempt}-{index}"


def read_executions(plan, evidence, *, context=None):
    current = execution_context(plan, context=context)["run_attempt"]
    attempts = [plan["build_attempt"]] if current == plan["build_attempt"] else [plan["build_attempt"], current]
    allowed = {shard_artifact(plan, s["index"], a): (s["index"], a) for s in plan["shards"] for a in attempts}
    executions = {}
    for directory in Path(evidence).iterdir():
        require(directory.name in allowed and directory.is_dir() and not directory.is_symlink(),
                "Missing/extra or stale shard artifact")
        index, attempt = allowed[directory.name]
        require((directory / "execution.json").is_file() and not (directory / "execution.json").is_symlink(),
                "Missing or linked execution envelope")
        value = read_json(directory / "execution.json")
        require(isinstance(value, dict) and type(value.get("schema_version")) is int
                and value["schema_version"] == 1 and type(value.get("shard")) is int, "Invalid execution schema")
        computed = execution(plan, index, directory, value.get("outcomes"), attempt=attempt, context=context)
        require(value == computed, "Execution envelope mismatch")
        executions[index, attempt] = (directory, value)
    return executions


def selected_executions(plan, evidence, *, context=None):
    executions = read_executions(plan, evidence, context=context)
    selected, failed = [], []
    for shard in plan["shards"]:
        index = shard["index"]
        require((index, plan["build_attempt"]) in executions, "Missing original execution envelope")
        original = executions[index, plan["build_attempt"]]
        retry = executions.get((index, str(int(plan["build_attempt"]) + 1)))
        if original[1]["status"] == "passed":
            require(retry is None, "Previously passing shard was rerun")
            selected.append(original)
        else:
            require(retry is not None and retry[1]["status"] == "passed", "Shard has no passing execution")
            selected.append(retry)
            failed.append({"shard": index, "artifact": original[0].name,
                           "execution_sha256": digest(original[0] / "execution.json")})
    return selected, failed


def verify_requalification(plan, requalification_directory, *, context=None):
    focused = Path(requalification_directory)
    require({p.name for p in focused.iterdir()} == {"plan.json", "full-inventory.txt", "enumeration.txt", "summary.json", "tests.json",
            "qualification.json", "receipt.json", "enumeration.log", "xcodebuild.log", "results.xcresult"}, "Missing or extra focused evidence")
    require((focused / "results.xcresult").is_dir() and not (focused / "results.xcresult").is_symlink(), "Missing focused native result")
    require(read_json(focused / "plan.json") == plan, "Focused result uses another plan")
    focused_receipt = requalification(focused, require_workspace=False, context=context)
    require(read_json(focused / "receipt.json") == focused_receipt, "Focused receipt mismatch")
    return focused_receipt


def write_aggregate(plan, selected, failed, output, requalification_directory, *, context=None):
    """Render already selected evidence, recomputing all receipts and union coverage."""
    output, focused = Path(output), Path(requalification_directory)
    focused_receipt = verify_requalification(plan, focused, context=context)
    trees, methods, parameters, selections = [], [], 0, []
    for directory, envelope in selected:
        value = receipt(plan, envelope["shard"], directory, attempt=envelope["execution_attempt"], context=context)
        methods.extend(value["methods"])
        parameters += value["parameter_leaves"]
        trees.append(read_json(directory / "tests.json"))
        selections.append({"shard": envelope["shard"], "execution_attempt": envelope["execution_attempt"],
                           "artifact": directory.name, "execution_sha256": digest(directory / "execution.json")})
    require(sorted(methods) == hosted_methods(plan["inventory"], plan["separate_integrations"])
            and len(methods) == len(set(methods)), "Aggregate coverage mismatch")
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "summary.json", {"result": "Passed", "totalTestCount": len(methods), "passedTests": len(methods),
                                        "failedTests": 0, "skippedTests": 0})
    # Preserve raw trees. The unchanged critical validator searches recursively
    # and still requires each protected suite and case exactly once.
    write_json(output / "tests.json", {"shards": trees})
    write_json(output / "coverage.json", {**provenance(plan, context=context), "artifact_ids": artifact_ids(context),
               "selected_executions": selections, "failed_executions": failed, "plan_sha256": plan_digest(context),
               "status": "passed", "methods": len(methods), "parameter_leaves": parameters, "shards": len(trees),
               "scope": "hosted-unit-suites", "complete_target": False, "release_eligible": False,
               "compiled_methods": len(plan["inventory"]),
               "separate_integrations": {"methods": plan["separate_integrations"], "status": "not-executed"},
               "requalification": {"receipt_sha256": digest(focused / "receipt.json"),
                                   "products_sha256": focused_receipt["products_sha256"]}})


def aggregate(plan, evidence, output, requalification_directory, *, context=None):
    # The ordinary gate has no artifact-loss exception, even with an explicit
    # offline verification context. The separate recovery verifier owns that
    # narrowly pinned, independently checked policy.
    verify_requalification(plan, requalification_directory, context=context)
    selected, failed = selected_executions(plan, evidence, context=context)
    write_aggregate(plan, selected, failed, output, requalification_directory, context=context)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("pack", "plan", "unpack", "selectors", "check-enumeration", "check-focused-enumeration", "receipt", "aggregate", "requalification", "execution"))
    for name in ("plan", "enumeration", "products", "output", "weights", "directory", "requalification-directory"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--index", type=int)
    args = parser.parse_args()
    if args.action == "requalification":
        require(os.environ.get("IOS_REQUALIFICATION_OUTCOME") == "success", "Focused native command did not succeed")
        write_json(args.output, requalification(args.directory))
        return
    if args.action == "pack":
        pack_product(args.products, args.output)
        return
    if args.action == "plan":
        weights = read_json(args.weights)["suite_seconds"]
        plan = make_plan(args.enumeration, args.products, weights)
        write_json(args.output, plan)
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write("build_attempt=" + plan["build_attempt"] + "\n")
            output.write("plan_sha256=" + digest(args.output) + "\n")
            output.write("matrix=" + json.dumps({"index": list(range(len(plan["shards"])))}, separators=(",", ":")) + "\n")
        return
    plan = load_plan(args.plan, require_workspace=args.action != "aggregate")
    if args.action == "unpack":
        unpack_product(plan, args.products, args.directory)
    elif args.action == "selectors":
        Path(args.output).write_text("\n".join(selected_shard(plan, args.index)["suites"]) + "\n")
    elif args.action == "check-enumeration":
        require(inventory(args.enumeration, plan=plan) == selected_shard(plan, args.index)["methods"], "Shard enumeration mismatch")
    elif args.action == "check-focused-enumeration":
        require(inventory(args.enumeration, plan=plan) == focused_methods(plan), "Focused enumeration differs from complete compiled suites")
    elif args.action == "execution":
        outcomes = {key: os.environ.get("IOS_UNIT_" + key.upper() + "_OUTCOME", "") for key in OUTCOME_KEYS}
        write_json(args.output, execution(plan, args.index, args.directory, outcomes))
    elif args.action == "receipt":
        require(os.environ.get("IOS_UNIT_TEST_OUTCOME") == "success", "Native test command did not succeed")
        write_json(args.output, receipt(plan, args.index, args.directory))
    else:
        aggregate(plan, args.directory, args.output, args.requalification_directory)


if __name__ == "__main__":
    main()

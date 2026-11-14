#!/usr/bin/env python3
"""Partition the compiled unit inventory and reconcile every native result."""

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
SHARDS = 16
TOOLCHAIN = "Xcode 27.0 Build version 27A266a"
RUNTIME = {"SIMULATOR_RUNTIME_VERSION": "26.5",
           "SIMULATOR_RUNTIME_BUILD_VERSION": "23F77",
           "SIMULATOR_MODEL_IDENTIFIER": "iPhone18,1"}
PRODUCT = "tests.xctestproducts"
MAX_JSON = 64 * 1024 * 1024


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


def identity():
    result = {key: os.environ.get(env, "") for key, env in (
        ("source_sha", "GITHUB_SHA"), ("run_id", "GITHUB_RUN_ID"),
        ("run_attempt", "GITHUB_RUN_ATTEMPT"))}
    require(re.fullmatch(r"[0-9a-f]{40}", result["source_sha"]), "Missing exact source SHA")
    for key in ("run_id", "run_attempt"):
        require(re.fullmatch(r"[1-9][0-9]*", result[key]), "Missing run identity")
    return result


def canonical(selector):
    require(isinstance(selector, str) and 0 < len(selector) <= 4096, "Invalid test identifier")
    require(not any(ord(c) < 33 or ord(c) == 127 for c in selector), "Non-identifier enumeration line")
    parts = selector.split("/")
    require(len(parts) >= 3 and parts[0] == TARGET and all(parts), "Unexpected test target or identifier")
    require(all(p not in (".", "..") for p in parts) and "?" not in selector, "Invalid method identifier")
    # XCTest's result identifier adds () to the enumerated selector. Preserve
    # every other character, including Swift Testing's argument labels.
    return selector[:-2] if selector.endswith("()") else selector


def inventory(path):
    require(Path(path).stat().st_size <= MAX_JSON, "Oversized compiled inventory")
    lines = Path(path).read_text().splitlines()
    require(lines and all(lines), "Empty enumeration or blank inventory line")
    result = [canonical(line) for line in lines]
    require(len(set(result)) == len(result), "Duplicate compiled test identifier")
    return sorted(result)


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
    methods = inventory(enumeration)
    require(isinstance(weights, dict) and all(isinstance(k, str) and type(v) is int
            and 0 < v < 86400 for k, v in weights.items()), "Invalid scheduling weights")
    return {"schema_version": 1, **identity(), "toolchain": TOOLCHAIN,
            "configuration": "Debug", "runtime": RUNTIME, "target": TARGET,
            "build_workspace": os.environ["GITHUB_WORKSPACE"],
            "products_sha256": digest(products), "inventory": methods,
            "shards": partition(methods, weights)}


def load_plan(path, *, require_workspace=True):
    require(digest(path) == os.environ.get("IOS_UNIT_PLAN_SHA256"), "Plan digest mismatch")
    plan = read_json(path)
    require(all(plan.get(k) == v for k, v in identity().items()),
            "Plan source/run/attempt mismatch; rerun all workflow jobs together")
    require(plan.get("schema_version") == 1 and plan.get("toolchain") == TOOLCHAIN
            and plan.get("configuration") == "Debug" and plan.get("runtime") == RUNTIME
            and plan.get("target") == TARGET, "Plan qualification mismatch")
    require(isinstance(plan.get("build_workspace"), str) and plan["build_workspace"].startswith("/"), "Invalid build workspace")
    require(not require_workspace or plan.get("build_workspace") == os.environ.get("GITHUB_WORKSPACE"),
            "Compiled source paths require the same checkout location on each runner")
    methods = plan.get("inventory")
    require(isinstance(methods, list) and methods and methods == sorted(set(methods))
            and all(canonical(x) == x for x in methods), "Invalid plan inventory")
    shards = plan.get("shards")
    require(isinstance(shards, list) and len(shards) == min(SHARDS, len({suite(x) for x in methods})),
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
    require(sorted(assigned) == methods and len(set(owned_suites)) == len(owned_suites),
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


def qualified_device(qualification):
    require(qualification.get("qualified") is True and qualification.get("status") == "passed"
            and qualification.get("architecture") == "arm64" and qualification.get("runtime_cache_ready") is True
            and qualification.get("runtime_identifier") == "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
            and qualification.get("device_type_identifier") == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
            and qualification.get("observed_environment") == RUNTIME, "Unqualified shard simulator")
    destination = qualification.get("simulator_destination", "")
    match = re.fullmatch(r"platform=iOS Simulator,id=([A-Fa-f0-9-]{36})", destination)
    require(match is not None, "Invalid qualified simulator destination")
    require(str(uuid.UUID(match.group(1))).upper() == match.group(1).upper(), "Invalid simulator UUID")
    return match.group(1)


def result_methods(summary, tree, qualification):
    require(summary.get("result") == "Passed", "Native summary did not pass")
    for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests"):
        require(type(summary.get(key)) is int, "Invalid native test count")
    require(summary["totalTestCount"] > 0 and summary["passedTests"] == summary["totalTestCount"]
            and summary["failedTests"] == summary["skippedTests"] == 0, "Incomplete, failed or skipped native tests")
    device = qualified_device(qualification)
    devices = tree.get("devices")
    require(isinstance(devices, list) and len(devices) == 1, "Multiple/missing test devices")
    require(all(devices[0].get(k) == v for k, v in {"architecture": "arm64", "deviceId": device,
            "osBuildNumber": "23F77", "osVersion": "26.5", "platform": "iOS Simulator"}.items()),
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
        elif kind == "Arguments":
            require(parent == "Test Case" and not children, "Invalid parameter leaf")
            url = node.get("nodeIdentifierURL", "")
            require(urlsplit(url)._replace(query="").geturl() == parent_url
                    and re.fullmatch(r"args=[a-f0-9]{64}", urlsplit(url).query) and url not in arguments, "Missing or duplicate parameter identity")
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


def receipt(plan, index, directory):
    directory = Path(directory)
    shard = selected_shard(plan, index)
    require(inventory(directory / "enumeration.txt") == shard["methods"], "Selected enumeration differs from plan")
    methods, arguments = result_methods(read_json(directory / "summary.json"), read_json(directory / "tests.json"),
                                        read_json(directory / "qualification.json"))
    require(methods == shard["methods"], "Executed methods differ from compiled inventory")
    return {"schema_version": 1, **identity(), "shard": index, "toolchain": TOOLCHAIN,
            "plan_sha256": os.environ["IOS_UNIT_PLAN_SHA256"], "products_sha256": plan["products_sha256"],
            "methods": methods, "parameter_leaves": arguments, "status": "passed",
            "files": {name: digest(directory / name) for name in
                      ("enumeration.txt", "summary.json", "tests.json", "qualification.json")}}


def aggregate(plan, evidence, output):
    evidence, output = Path(evidence), Path(output)
    expected = {f"ios-unit-shard-{plan['run_id']}-attempt-{plan['run_attempt']}-{s['index']}" for s in plan["shards"]}
    require({p.name for p in evidence.iterdir()} == expected, "Missing/extra shard artifacts; rerun all jobs together")
    trees, methods, parameters = [], [], 0
    for shard in plan["shards"]:
        directory = evidence / f"ios-unit-shard-{plan['run_id']}-attempt-{plan['run_attempt']}-{shard['index']}"
        require({p.name for p in directory.iterdir()} == {"receipt.json", "enumeration.txt", "summary.json", "tests.json", "qualification.json"},
                "Unexpected shard evidence files")
        value = receipt(plan, shard["index"], directory)
        require(read_json(directory / "receipt.json") == value, "Shard receipt mismatch")
        methods.extend(value["methods"])
        parameters += value["parameter_leaves"]
        trees.append(read_json(directory / "tests.json"))
    require(sorted(methods) == plan["inventory"] and len(methods) == len(set(methods)), "Aggregate coverage mismatch")
    output.mkdir(parents=True, exist_ok=True)
    write_json(output / "summary.json", {"result": "Passed", "totalTestCount": len(methods), "passedTests": len(methods),
                                        "failedTests": 0, "skippedTests": 0})
    # Preserve raw trees. The unchanged critical validator searches recursively
    # and still requires each protected suite and case exactly once.
    write_json(output / "tests.json", {"shards": trees})
    write_json(output / "coverage.json", {**identity(), "plan_sha256": os.environ["IOS_UNIT_PLAN_SHA256"],
               "status": "passed", "methods": len(methods), "parameter_leaves": parameters, "shards": len(trees)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("pack", "plan", "unpack", "selectors", "check-enumeration", "receipt", "aggregate"))
    for name in ("plan", "enumeration", "products", "output", "weights", "directory"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--index", type=int)
    args = parser.parse_args()
    if args.action == "pack":
        pack_product(args.products, args.output)
        return
    if args.action == "plan":
        weights = read_json(args.weights)["suite_seconds"]
        plan = make_plan(args.enumeration, args.products, weights)
        write_json(args.output, plan)
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write("plan_sha256=" + digest(args.output) + "\n")
            output.write("matrix=" + json.dumps({"index": list(range(len(plan["shards"])))}, separators=(",", ":")) + "\n")
        return
    plan = load_plan(args.plan, require_workspace=args.action != "aggregate")
    if args.action == "unpack":
        unpack_product(plan, args.products, args.directory)
    elif args.action == "selectors":
        Path(args.output).write_text("\n".join(selected_shard(plan, args.index)["suites"]) + "\n")
    elif args.action == "check-enumeration":
        require(inventory(args.enumeration) == selected_shard(plan, args.index)["methods"], "Shard enumeration mismatch")
    elif args.action == "receipt":
        require(os.environ.get("IOS_UNIT_TEST_OUTCOME") == "success", "Native test command did not succeed")
        write_json(args.output, receipt(plan, args.index, args.directory))
    else:
        aggregate(plan, args.directory, args.output)


if __name__ == "__main__":
    main()

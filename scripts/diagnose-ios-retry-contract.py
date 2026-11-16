#!/usr/bin/env python3
"""Synthetic same-run retry experiment; never qualify native tests or a release."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys


def require(value):
    if not value:
        raise ValueError("Retry diagnostic invariant failed")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size < 8192)
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def identity(env):
    require(re.fullmatch(r"[0-9a-f]{40}", env.get("GITHUB_SHA", "")))
    require(all(re.fullmatch(r"[1-9][0-9]*", env.get(k, ""))
                for k in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")))
    return {"source_sha": env["GITHUB_SHA"], "run_id": env["GITHUB_RUN_ID"],
            "attempt": int(env["GITHUB_RUN_ATTEMPT"])}


def origin(directory, env):
    execution = identity(env)
    require(execution["attempt"] == 1)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "input.bin").write_bytes(b"x")
    value = {"schema_version": 1, **execution, "input_sha256": digest(directory / "input.bin")}
    write(directory / "origin.json", value)
    return value


def load_origin(directory, env):
    current = identity(env)
    require(current["attempt"] in (1, 2))
    require(re.fullmatch(r"[1-9][0-9]*", env.get("PROBE_ORIGIN_ARTIFACT_ID", "")))
    require(env.get("PROBE_ORIGIN_ATTEMPT") == "1")
    require(env.get("PROBE_ORIGIN_RUN") == current["run_id"])
    require(env.get("PROBE_ORIGIN_SHA") == current["source_sha"])
    require(directory.is_dir() and not directory.is_symlink()
            and {p.name for p in directory.iterdir()} == {"origin.json", "input.bin"})
    require((directory / "input.bin").is_file() and not (directory / "input.bin").is_symlink()
            and (directory / "input.bin").stat().st_size == 1)
    value = read(directory / "origin.json")
    require(value == {"schema_version": 1, "source_sha": current["source_sha"],
                      "run_id": current["run_id"], "attempt": 1,
                      "input_sha256": hashlib.sha256(b"x").hexdigest()})
    require(digest(directory / "origin.json") == env.get("PROBE_ORIGIN_DIGEST"))
    require((directory / "input.bin").read_bytes() == b"x")
    return {**value, "artifact_id": env["PROBE_ORIGIN_ARTIFACT_ID"],
            "origin_sha256": env["PROBE_ORIGIN_DIGEST"]}


def receipt(bound_origin, slot, env):
    current = identity(env)
    require(type(slot) is int and slot in (0, 1))
    return {"schema_version": 1, "kind": "synthetic_retry_probe", "qualified": False,
            "release_eligible": False, "origin": bound_origin, "slot": slot,
            "execution_attempt": current["attempt"],
            "status": "failed" if slot == 1 and current["attempt"] == 1 else "passed"}


def reconcile(bound_origin, receipts, env):
    current = identity(env)
    require(1 <= len(receipts) <= 3)
    seen = {}
    for value in receipts:
        require(isinstance(value, dict))
        require(value.get("qualified") is False and value.get("release_eligible") is False)
        slot, attempt = value.get("slot"), value.get("execution_attempt")
        require(type(slot) is int and slot in (0, 1))
        require(type(attempt) is int and 1 <= attempt <= current["attempt"])
        require((slot, attempt) not in seen)
        expected = receipt(bound_origin, slot, {**env, "GITHUB_RUN_ATTEMPT": str(attempt)})
        require(value == expected)
        seen[slot, attempt] = value
    # This experiment has exactly one permitted operator path: retry failed jobs
    # once. A repeated origin or already-passing slot invalidates the experiment.
    expected_keys = {(0, 1), (1, 1)} | ({(1, 2)} if current["attempt"] == 2 else set())
    require(set(seen) == expected_keys)
    selected = [max((value for (index, _), value in seen.items() if index == slot),
                    key=lambda value: value["execution_attempt"]) for slot in (0, 1)]
    return {"schema_version": 1, "kind": "synthetic_retry_probe", "qualified": False,
            "release_eligible": False, "origin": bound_origin,
            "aggregation_attempt": current["attempt"],
            "selected": [{"slot": value["slot"], "execution_attempt": value["execution_attempt"],
                          "status": value["status"]} for value in selected],
            "retained_failed_receipts": sum(v["status"] == "failed" for v in seen.values()),
            "status": "passed" if all(v["status"] == "passed" for v in selected) else "failed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("origin", "slot", "aggregate"))
    parser.add_argument("--origin", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--receipts", type=Path)
    parser.add_argument("--slot", type=int)
    args = parser.parse_args()
    env = os.environ
    if args.action == "origin":
        value = origin(args.origin, env)
        with open(env["GITHUB_OUTPUT"], "a") as stream:
            stream.write("digest=" + digest(args.origin / "origin.json") + "\n")
            stream.write("attempt=1\nrun=" + value["run_id"] + "\nsha=" + value["source_sha"] + "\n")
        return 0
    bound_origin = load_origin(args.origin, env)
    require(args.output is not None)
    if args.action == "slot":
        value = receipt(bound_origin, args.slot, env)
    else:
        require(args.receipts is not None and args.receipts.is_dir())
        values = []
        for directory in args.receipts.iterdir():
            require(directory.is_dir() and not directory.is_symlink())
            require({p.name for p in directory.iterdir()} == {"receipt.json"})
            value = read(directory / "receipt.json")
            require(directory.name == f"retry-probe-receipt-{bound_origin['run_id']}-1-"
                    f"{value.get('slot')}-execution-{value.get('execution_attempt')}")
            values.append(value)
        value = reconcile(bound_origin, values, env)
    write(args.output, value)
    return 0 if value["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

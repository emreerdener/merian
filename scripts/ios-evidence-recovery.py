#!/usr/bin/env python3
"""Read-only collection and explicit-context recovery; never rewrites an old run."""

import argparse
from datetime import datetime
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SPEC = importlib.util.spec_from_file_location("shards", Path(__file__).with_name("ios-unit-shards.py"))
shards = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shards)
require = shards.require
ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "scripts/config/ios-consolidation-acceptance.json"
SUCCESS_STEPS = {
    "Checkout exact workflow SHA", "Verify shard source and toolchain",
    "Download exact compiled products", "Download exact unit plan", "Verify and unpack compiled products",
    "Prepare candidate shard simulator", "Observe exact guest identity inside XCTest",
    "Verify exact guest identity evidence", "Retain simulator identity evidence",
    "Reconcile selected compiled inventory", "Run complete assigned suites serially",
    "Verify shard execution against compiled inventory", "Record terminal shard execution",
}
UPLOAD_STEPS = {"Retain shard coverage evidence", "Retain shard failure diagnostics"}


def sha256(value):
    return hashlib.sha256(value).hexdigest()


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def verifier_identity():
    require(not git("status", "--porcelain", "--untracked-files=all").strip(), "Verifier checkout is dirty")
    source = git("rev-parse", "HEAD").decode().strip()
    require(not os.environ.get("GITHUB_SHA") or os.environ["GITHUB_SHA"] == source, "Verifier workflow/source mismatch")
    return {"source_sha": source, "tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
            "workflow_run_id": os.environ.get("GITHUB_RUN_ID"),
            "workflow_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
            "policy_sha256": shards.digest(POLICY)}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class GitHub:
    """Never forward credentials to signed artifact/log storage URLs."""
    def __init__(self, repository):
        require(repository == "emreerdener/merian", "Unexpected evidence repository")
        self.base = "https://api.github.com/repos/" + repository
        self.token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        require(self.token, "Read-only GitHub token required")

    def bytes(self, path, maximum=32 * 1024 * 1024):
        require(path.startswith("/actions/") and ".." not in path, "Invalid GitHub evidence path")
        request = urllib.request.Request(self.base + path, headers={
            "Authorization": "Bearer " + self.token, "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"})
        try:
            response = urllib.request.build_opener(NoRedirect).open(request, timeout=60)
        except urllib.error.HTTPError as error:
            require(error.code == 302, "GitHub evidence request failed: HTTP " + str(error.code))
            location = error.headers.get("Location", "")
            parsed = urllib.parse.urlsplit(location)
            require(parsed.scheme == "https" and not parsed.username and not parsed.password
                    and parsed.hostname and (parsed.hostname.endswith(".blob.core.windows.net")
                    or parsed.hostname.endswith(".actions.githubusercontent.com")), "Unexpected evidence redirect")
            response = urllib.request.urlopen(location, timeout=60)
        with response:
            value = response.read(maximum + 1)
        require(len(value) <= maximum, "Oversized GitHub evidence")
        return value

    def json(self, path):
        return json.loads(self.bytes(path), object_pairs_hook=shards.unique_object)

    def listing(self, path, key):
        separator = "&" if "?" in path else "?"
        result = self.json(path + separator + "per_page=100")
        require(type(result.get("total_count")) is int and result["total_count"] == len(result.get(key, []))
                and result["total_count"] < 100, "Truncated evidence listing")
        return result


def safe_unzip(raw, destination):
    destination = Path(destination)
    require(not destination.exists(), "Evidence destination already exists")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries = archive.infolist()
        require(entries and len(entries) < 10000 and sum(e.file_size for e in entries) < 64 * 1024 * 1024,
                "Oversized evidence archive")
        names = set()
        for entry in entries:
            name = entry.filename.rstrip("/")
            parts = PurePosixPath(name).parts
            require(name and name not in names and not name.startswith("/") and "\\" not in name
                    and all(p not in (".", "..") for p in parts) and "/".join(parts) == name,
                    "Unsafe or duplicate archive path")
            mode = entry.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), "Linked/special archive entry")
            names.add(name)
        destination.mkdir(parents=True)
        for entry in entries:
            path = destination / entry.filename
            if entry.is_dir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(entry))


def compact_job(job):
    return {key: job[key] for key in ("id", "run_id", "run_attempt", "head_sha", "name", "status", "conclusion",
                                     "started_at", "completed_at", "steps")}


def validate_jobs(policy, original, recovery):
    origin = policy["origin"]
    def indexed(value, attempt):
        require(value["total_count"] == len(value["jobs"]) < 100, "Incomplete job metadata")
        found = {}
        for job in value["jobs"]:
            match = re.fullmatch(r"iOS unit shard ([0-9]+)", job["name"])
            if not match:
                continue
            index = int(match[1])
            require(index not in found and job["run_id"] == origin["run_id"]
                    and job["head_sha"] == origin["source_sha"] and job["run_attempt"] == attempt,
                    "Unbound or duplicate shard job")
            require(type(job["id"]) is int and job["id"] > 0, "Invalid job identity")
            require(job["status"] == "completed", "Shard recovery is not finished")
            for key in ("started_at", "completed_at"):
                require(isinstance(job[key], str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", job[key]), "Invalid execution timestamp")
                datetime.strptime(job[key], "%Y-%m-%dT%H:%M:%SZ")
            require(job["completed_at"] > job["started_at"], "Reversed execution timestamps")
            found[index] = job
        return found
    before, after = indexed(original, 1), indexed(recovery, 2)
    require(set(before) == set(range(16)) and set(after) == set(before), "Unexpected retry scope")
    for index, job in before.items():
        require(job["conclusion"] == ("failure" if index in origin["retry_shards"] else "success"),
                "Original failure set changed")
    require(all(job["conclusion"] == "success" for job in after.values()), "Recovery shard did not pass")
    # GitHub assigns new IDs/attempt numbers to carried-forward successful jobs.
    # Their execution times and exact steps remain those of attempt 1. Only the
    # three failed jobs may actually execute again; artifact selection also
    # rejects any attempt-2 evidence for a previously successful group.
    for index, job in after.items():
        if index not in origin["retry_shards"]:
            require(all(job[key] == before[index][key] for key in ("started_at", "completed_at", "steps", "conclusion")),
                    "Previously passing job was executed again")
        else:
            require(job["id"] != before[index]["id"] and job["started_at"] > before[index]["completed_at"], "Retry is copied/stale execution metadata")
    return before, after


def loss_record(policy, original, absent, log_excerpt, metadata_digests, fallback_absent):
    origin = policy["origin"]
    job = original[origin["lost_shard"]]
    require(job["id"] == origin["lost_job_id"], "Wrong original loss job")
    require(absent == {"total_count": 0, "artifacts": []}, "Original artifact exists or absence is unverified")
    require(fallback_absent == {"total_count": 0, "artifacts": []}, "Fallback artifact exists or absence is unverified")
    steps = job["steps"]
    require(len({s["name"] for s in steps}) == len(steps), "Duplicate original step")
    by_name = {s["name"]: s for s in steps}
    require(SUCCESS_STEPS <= by_name.keys() and all(by_name[n]["status"] == "completed"
            and by_name[n]["conclusion"] == "success" for n in SUCCESS_STEPS), "Original pre-upload checks did not pass")
    require({s["name"] for s in steps if s["conclusion"] == "failure"} == UPLOAD_STEPS,
            "Loss is not exclusively an artifact-upload failure")
    require(all(s["status"] == "completed" and s["conclusion"] in ("success", "failure", "skipped") for s in steps),
            "Interrupted or incomplete original job")
    require(isinstance(log_excerpt, list) and len(log_excerpt) == 2
            and any("CreateArtifact" in line and "ETIMEDOUT" in line for line in log_excerpt)
            and any("FinalizeArtifact" in line and "ETIMEDOUT" in line for line in log_excerpt),
            "Missing original artifact-service timeout evidence")
    return {"schema_version": 1, "kind": "original-artifact-service-timeout", "source_sha": origin["source_sha"],
            "run_id": origin["run_id"], "build_attempt": 1, "execution_attempt": 1,
            "job_id": job["id"], "shard": origin["lost_shard"],
            "artifact_name": f"ios-unit-shard-{origin['run_id']}-build-1-attempt-1-{origin['lost_shard']}",
            "passing_coverage": False, "original_receipt_reconstructed": False, "metadata_sha256": metadata_digests}


def collect(policy, output, client):
    """CI calls this directly; uploaded user-authored loss attestations are not inputs."""
    output = Path(output)
    require(not output.exists(), "Collection output must be new")
    origin = policy["origin"]
    run = client.json(f"/actions/runs/{origin['run_id']}")
    require(run["head_sha"] == origin["source_sha"] and run["run_attempt"] == 2
            and run["status"] == "completed" and run["conclusion"] == "failure" and run["path"] == ".github/workflows/ios-build-and-test.yml",
            "Wrong or incomplete recovery origin")
    original = client.listing(f"/actions/runs/{origin['run_id']}/attempts/1/jobs", "jobs")
    recovery = client.listing(f"/actions/runs/{origin['run_id']}/attempts/2/jobs", "jobs")
    before, _ = validate_jobs(policy, original, recovery)
    name = f"ios-unit-shard-{origin['run_id']}-build-1-attempt-1-{origin['lost_shard']}"
    absent = client.listing(f"/actions/runs/{origin['run_id']}/artifacts?name={name}", "artifacts")
    fallback_name = f"ios-unit-failure-{origin['run_id']}-attempt-1-{origin['lost_shard']}"
    fallback_absent = client.listing(f"/actions/runs/{origin['run_id']}/artifacts?name={fallback_name}", "artifacts")
    log = client.bytes(f"/actions/jobs/{origin['lost_job_id']}/logs").decode("utf-8", errors="replace")
    excerpt = [line for line in log.splitlines() if "ETIMEDOUT" in line and
               ("CreateArtifact" in line or "FinalizeArtifact" in line)]
    metadata = {"original-jobs.json": {"total_count": original["total_count"], "jobs": [compact_job(j) for j in original["jobs"]]},
                "recovery-jobs.json": {"total_count": recovery["total_count"], "jobs": [compact_job(j) for j in recovery["jobs"]]},
                "original-absence.json": absent, "fallback-absence.json": fallback_absent, "upload-timeouts.json": excerpt}
    digests = {name: sha256(json_bytes(value)) for name, value in metadata.items()}
    loss = loss_record(policy, before, absent, excerpt, digests, fallback_absent)
    listing = client.listing(f"/actions/runs/{origin['run_id']}/artifacts", "artifacts")["artifacts"]
    by_name = {a["name"]: a for a in listing}
    require(len(by_name) == len(listing), "Duplicate artifact names")
    expected = {f"ios-unit-shard-{origin['run_id']}-build-1-attempt-1-{i}" for i in range(16) if i != origin["lost_shard"]}
    expected |= {f"ios-unit-shard-{origin['run_id']}-build-1-attempt-2-{i}" for i in origin["retry_shards"]}
    require({name for name in by_name if name.startswith("ios-unit-shard-")} == expected,
            "Unexpected/missing shard artifact or retry")
    output.mkdir(parents=True)
    for name, value in metadata.items():
        (output / name).write_bytes(json_bytes(value))
    shards.write_json(output / "loss.json", loss)
    selected = [(by_name[name], output / "shards" / name, None) for name in sorted(expected)]
    for role in ("plan", "requalification", "products"):
        pin = origin["artifacts"][role]
        artifact = next((a for a in listing if a["id"] == pin["id"]), None)
        require(artifact and artifact["digest"] == pin["archive_digest"] and not artifact["expired"], "Immutable origin artifact changed")
        if role != "products":
            selected.append((artifact, output / role, pin["archive_digest"]))
    (output / "archives").mkdir()
    retained = []
    for artifact, destination, pin in selected:
        require(not artifact["expired"] and re.fullmatch(r"sha256:[a-f0-9]{64}", artifact["digest"]), "Invalid artifact digest")
        raw = client.bytes(f"/actions/artifacts/{artifact['id']}/zip")
        require(len(raw) == artifact["size_in_bytes"] and "sha256:" + sha256(raw) == artifact["digest"], "Artifact bytes/digest mismatch")
        (output / "archives" / (str(artifact["id"]) + ".zip")).write_bytes(raw)
        safe_unzip(raw, destination)
        retained.append({"id": artifact["id"], "name": artifact["name"], "digest": artifact["digest"]})
    shards.write_json(output / "collection.json", {"origin_source": origin["source_sha"], "origin_run": origin["run_id"],
                      "original_workflow_conclusion": run["conclusion"], "artifacts": retained, "metadata_sha256": digests,
                      "loss_sha256": shards.digest(output / "loss.json")})


def verify_archives(policy, directory, collection):
    """Bind every extracted byte to the retained GitHub artifact, not just a receipt."""
    require(not directory.is_symlink(), "Linked evidence directory")
    directory = directory.resolve()
    origin = policy["origin"]
    expected = {f"ios-unit-shard-{origin['run_id']}-build-1-attempt-1-{i}": directory / "shards"
                for i in range(16) if i != origin["lost_shard"]}
    expected.update({f"ios-unit-shard-{origin['run_id']}-build-1-attempt-2-{i}": directory / "shards"
                     for i in origin["retry_shards"]})
    for role in ("plan", "requalification"):
        expected[f"ios-unit-{role}-{origin['run_id']}-attempt-1"] = directory
    require(not any(p.is_symlink() for p in directory.rglob("*")), "Linked evidence is forbidden")
    artifacts = collection["artifacts"]
    require(all(type(a["id"]) is int and a["id"] > 0 and re.fullmatch(r"sha256:[a-f0-9]{64}", a["digest"]) for a in artifacts), "Malformed artifact identity")
    require(len(artifacts) == len(expected) and {a["name"] for a in artifacts} == set(expected)
            and len({a["id"] for a in artifacts}) == len(artifacts), "Incomplete/duplicate artifact manifest")
    require({p.name for p in (directory / "archives").iterdir()} == {str(a["id"]) + ".zip" for a in artifacts},
            "Missing or extra retained archive")
    for artifact in artifacts:
        name = artifact["name"]
        role = next((role for role in ("plan", "requalification") if name == f"ios-unit-{role}-{origin['run_id']}-attempt-1"), None)
        destination = directory / role if role else directory / "shards" / name
        if role:
            pin = origin["artifacts"][role]
            require(artifact["id"] == pin["id"] and artifact["digest"] == pin["archive_digest"], "Origin artifact pin mismatch")
        archive = directory / "archives" / (str(artifact["id"]) + ".zip")
        require(not archive.is_symlink() and "sha256:" + shards.digest(archive) == artifact["digest"], "Retained artifact digest mismatch")
        with zipfile.ZipFile(archive) as bundle:
            files = [entry for entry in bundle.infolist() if not entry.is_dir()]
            require(len({entry.filename for entry in files}) == len(files), "Duplicate archived evidence")
            actual = {p.relative_to(destination).as_posix() for p in destination.rglob("*") if p.is_file()}
            require(actual == {entry.filename for entry in files}, "Extracted evidence file set changed")
            for entry in files:
                parts = PurePosixPath(entry.filename).parts
                require(parts and not entry.filename.startswith("/") and all(p not in (".", "..") for p in parts)
                        and "/".join(parts) == entry.filename and "\\" not in entry.filename, "Unsafe archived evidence")
                target = destination / entry.filename
                require(not any(p.is_symlink() for p in [target, *target.parents])
                        and sha256(bundle.read(entry)) == shards.digest(target), "Extracted evidence bytes changed")


def select_recovery(policy, plan, directory, context):
    """The single approved exception; ordinary selected_executions stays strict."""
    origin = policy["origin"]
    require(origin["lost_shard"] == 1 and origin["retry_shards"] == [1, 6, 11]
            and origin["build_attempt"] == 1 and origin["recovery_attempt"] == 2, "Unreviewed recovery shape")
    executions = shards.read_executions(plan, directory, context=context)
    expected = {(i, "1") for i in range(16) if i != 1} | {(i, "2") for i in (1, 6, 11)}
    require(set(executions) == expected, "Missing/extra original or recovery evidence")
    selected, failures = [], []
    for index in range(16):
        attempt = "2" if index in (1, 6, 11) else "1"
        chosen = executions[index, attempt]
        require(chosen[1]["status"] == "passed", "Recovery has no complete passing execution")
        selected.append(chosen)
        if index in (6, 11):
            original = executions[index, "1"]
            require(original[1]["status"] == "failed", "Original application/infrastructure failure was altered")
            failures.append({"shard": index, "artifact": original[0].name,
                             "execution_sha256": shards.digest(original[0] / "execution.json")})
    return selected, failures


def verify(policy, directory, output, verifier):
    directory, output = Path(directory), Path(output)
    origin = policy["origin"]
    collection = shards.read_json(directory / "collection.json")
    require(set(collection) == {"origin_source", "origin_run", "original_workflow_conclusion", "artifacts", "metadata_sha256", "loss_sha256"}, "Unexpected collection schema")
    require(collection["original_workflow_conclusion"] == "failure", "Original workflow failure must remain recorded")
    require(collection["origin_source"] == origin["source_sha"] and collection["origin_run"] == origin["run_id"], "Collection origin mismatch")
    verify_archives(policy, directory, collection)
    for name, digest in collection["metadata_sha256"].items():
        require(name in {"original-jobs.json", "recovery-jobs.json", "original-absence.json", "fallback-absence.json", "upload-timeouts.json"}
                and shards.digest(directory / name) == digest, "Metadata binding mismatch")
    require(len(collection["metadata_sha256"]) == 5, "Incomplete metadata")
    before, after = validate_jobs(policy, shards.read_json(directory / "original-jobs.json"), shards.read_json(directory / "recovery-jobs.json"))
    loss = loss_record(policy, before, shards.read_json(directory / "original-absence.json"),
                       shards.read_json(directory / "upload-timeouts.json"), collection["metadata_sha256"],
                       shards.read_json(directory / "fallback-absence.json"))
    require(shards.read_json(directory / "loss.json") == loss and shards.digest(directory / "loss.json") == collection["loss_sha256"], "Loss record tampered")
    context = {"source_sha": origin["source_sha"], "run_id": str(origin["run_id"]), "run_attempt": "2", "build_attempt": "1",
               "plan_sha256": origin["plan_sha256"], "artifact_ids": {role: str(pin["id"]) for role, pin in origin["artifacts"].items()}}
    plan = shards.load_plan(directory / "plan/ios-unit-plan.json", require_workspace=False, context=context)
    require(plan["products_sha256"] == origin["products_sha256"], "Wrong compiled products")
    selected, failures = select_recovery(policy, plan, directory / "shards", context)
    shards.write_aggregate(plan, selected, failures, output, directory / "requalification", context=context)
    subprocess.run(["bash", str(ROOT / "scripts/validate-ios-critical-test-results.sh"),
                    str(output / "summary.json"), str(output / "tests.json")], check=True)
    coverage = shards.read_json(output / "coverage.json")
    coverage.update(recovery_policy_version=policy["schema_version"], verifier=verifier,
                    evidence_losses=[{**loss, "record_sha256": shards.digest(directory / "loss.json")}],
                    compiled_source=origin["source_sha"], original_workflow_conclusion=collection["original_workflow_conclusion"],
                    old_workflow_relabelled=False, collection_sha256=shards.digest(directory / "collection.json"))
    shards.write_json(output / "coverage.json", coverage)
    return coverage


def trusted_workflow_identity():
    require(os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("GITHUB_REPOSITORY") == "emreerdener/merian", "Qualifying recovery requires the repository Actions job")
    require(os.environ.get("GITHUB_TOKEN") and not os.environ.get("GH_TOKEN"), "Use only the read-only workflow token")
    require(os.environ.get("GITHUB_EVENT_NAME") in ("push", "workflow_dispatch"), "Untrusted recovery event")
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", os.environ.get(key, "")), "Missing verifier workflow identity")
    require(re.fullmatch(r"[a-f0-9]{40}", os.environ.get("GITHUB_SHA", "")), "Missing verifier source")
    return verifier_identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    policy = shards.read_json(POLICY)
    verifier = trusted_workflow_identity()
    require(not args.output.exists(), "New verifier output required")
    # The qualifying entry point never accepts a preexisting collection. Live
    # collection and verification happen in this one trusted process/job.
    collect(policy, args.directory, GitHub(policy["repository"]))
    verify(policy, args.directory, args.output, verifier)


if __name__ == "__main__":
    main()

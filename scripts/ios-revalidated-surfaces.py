"""Exact-source non-native validation for the reviewed dependency successor.

This module never substitutes these checks for native or device evidence and
cannot grant publication, deployment, or distribution authority.
"""
CONTRACTS = {
    "backend": {
        "paths": ["services/supabase"],
        "workflow": ".github/workflows/supabase-candidate-validation.yml",
        "jobs": ["Determine Supabase candidate scope", "Validate exact candidate SHA", "Candidate readiness"],
        "steps": {},
    },
    "web": {
        "paths": ["apps/web"],
        "workflow": ".github/workflows/web-quality.yml",
        "jobs": ["Naturebook Web Quality / test"],
        "steps": {"Naturebook Web Quality / test": ["Install dependencies", "Audit dependencies", "Run unit tests", "Type-check", "Build production web app"]},
    },
    "admin": {
        "paths": ["apps/admin"],
        "workflow": ".github/workflows/admin-quality.yml",
        "jobs": ["Naturebook Admin Quality / test"],
        "steps": {"Naturebook Admin Quality / test": ["Install frozen dependencies", "Audit dependencies", "Run unit tests", "Type-check", "Build production admin app"]},
    },
    "agent_quality": {
        "paths": [".github/workflows/agent-quality.yml", "scripts/validate-agent-assets.ts"],
        "workflow": ".github/workflows/agent-quality.yml",
        "jobs": ["Deterministic validation"],
        "steps": {"Deterministic validation": ["Check out exact source", "Set up pinned Deno", "Validate agent assets"]},
    },
}
OPTIONAL_AGENT_JOBS = {"Live evaluation scope"} | {
    "Live evaluation (" + suite + ")" for suite in
    ("ios", "swiftdata", "supabase", "api-contracts", "docs", "incidents", "web-admin", "release", "agents")
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def covers(owner, path):
    return path == owner or path.startswith(owner + "/")


def validate(policy, candidate, git, trees):
    records = policy.get("revalidated_surfaces", {})
    if not records:
        return {}
    require(set(records) == set(CONTRACTS), "Incomplete or unknown revalidated surfaces")
    require(policy["reused_surface_paths"] == {} and policy["reused_workflows"] == {}
            and policy["reused_workflow_paths"] == {}, "Changed surfaces must not be declared reused")
    require(not policy.get("reviewed_surface_control_delta"), "Conflicting revalidation and control exception")
    origin = policy["origin"]["source_sha"]
    before, after = trees(origin), trees(candidate)
    ownership = [("native", p) for p in policy["product_paths"]]
    ownership += [(name, p) for name, contract in CONTRACTS.items() for p in contract["paths"]]
    for i, (name, path) in enumerate(ownership):
        for other, other_path in ownership[i + 1:]:
            require(name == other or not (covers(path, other_path) or covers(other_path, path)), "Overlapping validation ownership")
    verified = {}
    for name, contract in CONTRACTS.items():
        record = records[name]
        require(set(record) == {"owned_paths", "reviewed_delta"} and record["owned_paths"] == contract["paths"], "Revalidated ownership changed")
        changed = git("diff", "--name-only", origin, candidate, "--", *contract["paths"]).decode().splitlines()
        delta = record["reviewed_delta"]
        require(changed and isinstance(delta, list) and len(delta) == len(changed)
                and {r["path"] for r in delta} == set(changed), "Missing or extra revalidated delta")
        for item in delta:
            require(set(item) == {"path", "before", "after", "review"}
                    and isinstance(item["review"], str) and item["review"].strip(), "Unreviewed revalidated object")
            path = item["path"]
            require(any(covers(owner, path) for owner in contract["paths"])
                    and item["before"] == before.get(path) and item["after"] == after.get(path), "Revalidated object changed")
            require(item["before"] and item["after"]
                    and item["before"]["type"] == item["after"]["type"] == "blob"
                    and item["before"]["mode"] == item["after"]["mode"], "Revalidated mode/type changed")
        verified[name] = record
    return verified


def verify_runs(policy, candidate, client, run_ids, backend_verifier):
    records = policy.get("revalidated_surfaces", {})
    if not records:
        require(not run_ids, "Unexpected revalidated run")
        return {}
    require(set(records) == set(CONTRACTS) and set(run_ids) == set(records), "Missing or extra revalidated run")
    require(all(type(v) is int and v > 0 for v in run_ids.values())
            and len(set(run_ids.values())) == len(run_ids), "Invalid revalidated run identity")
    result = {}
    for name, contract in CONTRACTS.items():
        run_id = run_ids[name]
        run = client.json(f"/actions/runs/{run_id}")
        require(run["id"] == run_id and run["head_sha"] == candidate["source_sha"]
                and run["path"] == contract["workflow"]
                and run["event"] in ({"workflow_dispatch"} if name == "backend" else {"push", "pull_request", "workflow_dispatch"})
                and run["status"] == "completed" and run["conclusion"] == "success"
                and type(run["run_attempt"]) is int and run["run_attempt"] > 0,
                "Revalidated workflow is not an exact-candidate pass")
        listing = client.listing(f"/actions/runs/{run_id}/attempts/{run['run_attempt']}/jobs", "jobs")
        jobs = listing["jobs"]
        require(listing["total_count"] == len(jobs) and all(type(j["id"]) is int and j["id"] > 0 for j in jobs) and len({j["id"] for j in jobs}) == len(jobs), "Incomplete or duplicate job evidence")
        allowed = set(contract["jobs"]) | (OPTIONAL_AGENT_JOBS if name == "agent_quality" else set())
        require(len({j["name"] for j in jobs}) == len(jobs) and {j["name"] for j in jobs} <= allowed
                and set(contract["jobs"]) <= {j["name"] for j in jobs}, "Unexpected or missing validation job")
        require(all(j["run_id"] == run_id and j["run_attempt"] == run["run_attempt"]
                    and j["head_sha"] == candidate["source_sha"] and j["status"] == "completed" for j in jobs), "Unbound validation job")
        for job in jobs:
            if job["name"] not in contract["jobs"]:
                continue  # Live model evaluations retain their existing nonblocking status.
            require(job["conclusion"] == "success", "Required validation job skipped or failed")
            for step_name in contract["steps"].get(job["name"], []):
                matches = [s for s in job["steps"] if s["name"] == step_name]
                require(len(matches) == 1 and matches[0]["status"] == "completed"
                        and matches[0]["conclusion"] == "success", "Required validation step skipped or failed")
        result[name] = {k: run[k] for k in ("id", "head_sha", "run_attempt", "path", "conclusion")}
        result[name]["required_jobs"] = contract["jobs"]
        if name == "backend":
            # Retain the complete-scope, required database/Edge steps and C1
            # artifact provenance checks in the original backend verifier.
            verified_backend = backend_verifier(client, run_id, candidate)
            require(all(verified_backend[key] == run[key] for key in
                        ("id", "head_sha", "run_attempt", "path", "conclusion")),
                    "Backend attempt changed during verification")
            result[name]["backend_evidence"] = verified_backend
    return result

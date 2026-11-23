#!/usr/bin/env python3
"""Run the Explore recovery catalogs with only their owned accounting cron paused."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
JOB = "reconcile_identification_usage"
FIXTURES = ("reported_post_visibility", "identification_invocation_accounting",
            "privileged_routine_security")


def require(value, message):
    if not value:
        raise RuntimeError(message)


def local_environment(run=subprocess.run):
    result = run(["docker", "context", "inspect"], capture_output=True, text=True,
                 check=True, timeout=10)
    contexts = json.loads(result.stdout)
    require(len(contexts) == 1, "One local Docker context required")
    host = contexts[0]["Endpoints"]["docker"]["Host"]
    require(host.startswith("unix://"), "Local Unix Docker required")
    require(not os.environ.get("DOCKER_HOST") or os.environ["DOCKER_HOST"] == host,
            "Docker host differs from inspected local context")
    environment = os.environ.copy()
    for key in ("DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
        environment.pop(key, None)
    environment.update(DOCKER_HOST=host, SUPABASE_TELEMETRY_DISABLED="1")
    return environment


def owned_container(workdir, project, environment, run=subprocess.run):
    workdir = Path(workdir).resolve()
    require(re.fullmatch(r"merian-migration-recovery\.[A-Za-z0-9]+", workdir.name),
            "Owned recovery workdir required")
    require(re.fullmatch(r"merian-migration-recovery-[1-9][0-9]*-explore", project),
            "Owned Explore recovery project required")
    # This file is the runner's generated copy of the checked-in config. Read
    # only its two identity fields, rejecting duplicate/missing declarations.
    config = (workdir / "supabase/config.toml").read_text()
    projects = re.findall(r'^project_id\s*=\s*"([^"\n]+)"\s*$', config, re.MULTILINE)
    sections = re.findall(r'^\[db\]\s*\n(.*?)(?=^\[|\Z)', config, re.MULTILINE | re.DOTALL)
    ports = re.findall(r'^port\s*=\s*([0-9]+)\s*$', sections[0], re.MULTILINE) if len(sections) == 1 else []
    require(projects == [project] and ports == ["55432"],
            "Recovery project or local port mismatch")
    name = "supabase_db_" + project
    result = run(["docker", "inspect", name], env=environment, capture_output=True,
                 text=True, check=True, timeout=10)
    values = json.loads(result.stdout)
    require(len(values) == 1, "One owned database container required")
    info = values[0]
    ports = info.get("HostConfig", {}).get("PortBindings", {}).get("5432/tcp") or []
    require(info.get("Name") == "/" + name and info.get("State", {}).get("Running") is True
            and ports and all(p.get("HostPort") == "55432" for p in ports),
            "Running owned recovery database required")
    identifier = info.get("Id", "")
    require(re.fullmatch(r"[a-f0-9]{64}", identifier), "Immutable container identity required")
    return identifier


def query(container, environment, sql, run=subprocess.run):
    result = run(["docker", "exec", "-i", container, "psql", "-X", "-qAt",
                  "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
                 input="SET statement_timeout='5s'; SET lock_timeout='3s'; " + sql,
                 env=environment, capture_output=True, text=True, timeout=10)
    require(result.returncode == 0, "Owned recovery cron query failed")
    return result.stdout.strip()


def with_accounting_cron_paused(execute, fixtures):
    state_sql = "SELECT jobid::text||':'||active::text FROM cron.job WHERE jobname='" + JOB + "';"
    original = execute(state_sql)
    match = re.fullmatch(r"([1-9][0-9]*):(true|false)", original)
    require(match is not None, "Exactly one accounting cron job required")
    job_id, active = match.groups()
    where = "jobid=" + job_id + " AND jobname='" + JOB + "'"
    try:
        execute("SELECT cron.alter_job(jobid,active:=false) FROM cron.job WHERE " + where + ";")
        require(execute(state_sql) == job_id + ":false", "Accounting cron suspension mismatch")
        idle = execute("SELECT NOT EXISTS(SELECT 1 FROM cron.job_run_details r "
                       "JOIN cron.job j USING(jobid) WHERE j.jobid=" + job_id +
                       " AND j.jobname='" + JOB + "' AND r.end_time IS NULL "
                       "AND r.status NOT IN ('succeeded','failed'));")
        require(idle == "t", "Accounting cron still running; no fixture started or job cancelled")
        print("Owned recovery accounting cron suspended and idle.", flush=True)
        fixtures()
    finally:
        execute("SELECT cron.alter_job(jobid,active:=" + active +
                ") FROM cron.job WHERE " + where + ";")
        require(execute(state_sql) == original, "Accounting cron restoration mismatch")
        print("Owned recovery accounting cron restored and verified.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--project", required=True)
    args = parser.parse_args()
    environment = local_environment()
    container = owned_container(args.workdir, args.project, environment)

    def fixtures():
        subprocess.run(["supabase", "--workdir", str(args.workdir), "test", "db", "--local",
                        *[str(ROOT / "services/supabase/tests" / (name + ".sql")) for name in FIXTURES]],
                       env=environment, check=True, timeout=120)

    with_accounting_cron_paused(lambda sql: query(container, environment, sql), fixtures)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        # Never print command output, Docker configuration, or connection data.
        print("Owned recovery catalogs failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)

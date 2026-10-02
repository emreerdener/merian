#!/usr/bin/env bash
set +x
set -euo pipefail
reasoning_repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
exec python3 -I - "$reasoning_repository" "$@" <<'PY'
import getpass
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import warnings

stage = "preflight"
try:
    if len(sys.argv) != 3:
        raise ValueError()
    repository = Path(sys.argv[1]).resolve(strict=True)
    supplied = Path(sys.argv[2])
    packet = supplied.resolve(strict=True)
    if supplied.is_symlink() or not packet.is_dir() or repository == packet or repository in packet.parents or packet in repository.parents:
        raise ValueError()
    if any(c in str(p) for p in (repository, packet) for c in (",", "\n", "\r")):
        raise ValueError()
    if stat.S_IMODE(packet.stat().st_mode) != 0o700 or packet.stat().st_uid != os.getuid():
        raise ValueError()
    deno = shutil.which("deno")
    if not deno:
        raise ValueError()
    environment = {n: os.environ[n] for n in ("PATH", "HOME", "DENO_DIR") if n in os.environ}
    common = [deno, "run", "--frozen", "--no-prompt", "--cached-only", "--config", "services/supabase/functions/deno.json",
              "--allow-read=" + str(repository) + "," + str(packet), "--allow-write=" + str(packet)]
    entry = "services/supabase/scripts/evaluate_openai_reasoning.ts"
    check = subprocess.run(common + ["--allow-run=git", "--deny-net", "--deny-env", entry, "prepare", str(packet)],
                           cwd=repository, env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        raise ValueError()
    stage = "authorization"
    authorization = packet.parent / ".reasoning-authorizations"
    authorization.mkdir(mode=0o700, exist_ok=True)
    if authorization.is_symlink() or stat.S_IMODE(authorization.stat().st_mode) != 0o700 or authorization.stat().st_uid != os.getuid():
        raise ValueError()
    stage = "terminal"
    with open("/dev/tty", "r") as terminal:
        if not terminal.isatty():
            raise ValueError()
    warnings.simplefilter("error", getpass.GetPassWarning)
    stage = "key_entry"
    key = getpass.getpass("Paste Naturebook OpenAI key (hidden; not saved): ")
    if not key or len(key) > 512 or any(c.isspace() for c in key):
        raise ValueError()
    environment["OPENAI_EVALUATION_API_KEY"] = key
    stage = "evaluation"
    try:
        live = [arg + "," + str(authorization) if arg.startswith(("--allow-read=", "--allow-write=")) else arg for arg in common]
        result = subprocess.run(live + ["--allow-run=git,/usr/bin/open", "--allow-net=api.openai.com:443,127.0.0.1",
            "--allow-env=OPENAI_EVALUATION_API_KEY", "--deny-env=SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY",
            entry, "--live", str(packet)], cwd=repository, env=environment, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        environment.pop("OPENAI_EVALUATION_API_KEY", None)
        key = ""
    if result.returncode:
        raise ValueError()
    stage = "report"
    report = json.loads((packet / "reasoning-report.json").read_text())
    if report.get("version") != "openai_photo_reasoning_report_v1" or report.get("complete") is not True or report.get("attempted") != 12 or report.get("stop") is not None:
        raise ValueError()
    print("Comparison complete: 12 attempts recorded. The assistant will review the results.")
except (Exception, KeyboardInterrupt):
    print("openai_reasoning_launcher_stopped:" + stage + "; inspect the private report", file=sys.stderr)
    sys.exit(1)
PY

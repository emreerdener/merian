#!/usr/bin/env bash
set +x
set -euo pipefail
gemini_baseline_repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
exec python3 -I - "$gemini_baseline_repository" "$@" <<'PY'
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
    entry = "services/supabase/scripts/evaluate_gemini_photo_baseline.ts"
    check = subprocess.run(common + ["--allow-run=git", "--deny-net", "--deny-env", entry, "prepare", str(packet)],
                           cwd=repository, env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        raise ValueError()
    stage = "authorization"
    authorization = packet.parent / ".gemini-baseline-authorizations"
    authorization.mkdir(mode=0o700, exist_ok=True)
    if authorization.is_symlink() or stat.S_IMODE(authorization.stat().st_mode) != 0o700 or authorization.stat().st_uid != os.getuid():
        raise ValueError()
    stage = "terminal"
    with open("/dev/tty", "r") as terminal:
        if not terminal.isatty():
            raise ValueError()
    warnings.simplefilter("error", getpass.GetPassWarning)
    stage = "key_entry"
    key = getpass.getpass("Paste Naturebook Gemini key (hidden; not saved): ")
    if not key or len(key) > 512 or any(c.isspace() for c in key):
        raise ValueError()
    environment["GEMINI_PAID_API_KEY"] = key
    stage = "evaluation"
    try:
        live = [arg + "," + str(authorization) if arg.startswith(("--allow-read=", "--allow-write=")) else arg for arg in common]
        result = subprocess.run(live + ["--allow-run=git", "--allow-net=generativelanguage.googleapis.com:443",
            "--allow-env=GEMINI_PAID_API_KEY,GOOGLE_SDK_NODE_LOGGING,GOOGLE_GENAI_DEBUG,WS_NO_BUFFER_UTIL,WS_NO_UTF_8_VALIDATE,GOOGLE_GENAI_USE_ENTERPRISE,GOOGLE_GENAI_USE_VERTEXAI,GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_LOCATION,GOOGLE_VERTEX_BASE_URL,GOOGLE_GEMINI_BASE_URL,GOOGLE_API_KEY,GEMINI_API_KEY", "--deny-env=SUPABASE_*,R2_*,GOOGLE_APPLICATION_CREDENTIALS,OPENAI_*",
            entry, "--live", str(packet)], cwd=repository, env=environment, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        environment.pop("GEMINI_PAID_API_KEY", None)
        key = ""
    if result.returncode:
        raise ValueError()
    stage = "report"
    report = json.loads((packet / "gemini-report.json").read_text())
    if report.get("version") != "gemini_photo_baseline_report_v1" or report.get("complete") is not True or report.get("attempted") != 6 or report.get("stop") is not None:
        raise ValueError()
    print("Comparison complete: 6 attempts recorded. The assistant will review the results.")
except (Exception, KeyboardInterrupt):
    print("gemini_baseline_launcher_stopped:" + stage + "; inspect the private report", file=sys.stderr)
    sys.exit(1)
PY

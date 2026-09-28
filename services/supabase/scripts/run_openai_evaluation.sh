#!/usr/bin/env bash
# Disable inherited shell tracing before a credential can enter this process.
set +x
set -euo pipefail

evaluation_launcher_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
exec python3 -I -c '
"""Local terminal entry only. No key is saved, logged or passed in an argument."""
import getpass
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import warnings


def main():
    if len(sys.argv) not in (4, 5) or sys.argv[2] not in ("--credential-fingerprint", "--live", "--experiment-live", "--experiment-session", "--photo-model-live"):
        raise ValueError("arguments")
    session = sys.argv[2] == "--experiment-session"
    experiment = session or sys.argv[2] == "--experiment-live"
    photo_models = sys.argv[2] == "--photo-model-live"
    if len(sys.argv) != (5 if experiment and not session else 4):
        raise ValueError("arguments")
    run_id = sys.argv[4] if experiment and not session else None
    if run_id is not None and not re.fullmatch("[a-z0-9][a-z0-9_.:-]{0,79}", run_id):
        raise ValueError("arguments")
    repository = Path(sys.argv[1]).resolve(strict=True)
    mode = sys.argv[2]
    supplied_root = Path(sys.argv[3])
    # Permission lists use commas; paths must not inject additional grants.
    if any(c in str(path) for path in (repository, supplied_root) for c in (",", "\n", "\r")):
        raise ValueError("path")
    packet = supplied_root.resolve(strict=True)
    if packet == repository or repository in packet.parents or packet in repository.parents:
        raise ValueError("outside_repository")
    if supplied_root.is_symlink() or not packet.is_dir():
        raise ValueError("directory")
    if stat.S_IMODE(packet.stat().st_mode) != 0o700 or packet.stat().st_uid != os.getuid():
        raise ValueError("private_directory")
    # Never fall back to echoed stdin, shell history or an inherited credential.
    with open("/dev/tty", "r") as terminal:
        if not terminal.isatty():
            raise ValueError("terminal_required")
    warnings.simplefilter("error", getpass.GetPassWarning)
    deno = shutil.which("deno")
    if mode != "--credential-fingerprint" and not deno:
        raise ValueError("deno_required")
    environment = {name: os.environ[name] for name in ("PATH", "HOME", "DENO_DIR") if name in os.environ}
    if mode != "--credential-fingerprint":
        # Reject a different provider before even prompting for its credential.
        spec_path = packet / ("photo-model-plan.json" if photo_models else "experiment.json" if experiment else "spec.json")
        info = spec_path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= 65536:
            raise ValueError("spec")
        spec_bytes = spec_path.read_bytes()
        spec = json.loads(spec_bytes)
        if photo_models:
            if spec.get("version") != "photo_model_plan_v2" or spec.get("maxCalls") != 18 or spec.get("attemptsPerAssignment") != 1:
                raise ValueError("provider")
        elif experiment:
            if spec.get("version") not in ("identification_experiment_plan_v1", "identification_experiment_plan_v2", "identification_experiment_plan_v3", "identification_experiment_plan_v4") or spec.get("mode") != "live" or not isinstance(spec.get("runs"), list):
                raise ValueError("provider")
            allowed_profiles = {
                "identification_experiment_plan_v1": ("openai_photo_text_v1",),
                "identification_experiment_plan_v2": ("openai_photo_text_uncached_v1", "openai_photo_text_concise_uncached_v1"),
                "identification_experiment_plan_v3": ("openai_photo_text_uncached_v1", "openai_photo_text_concise_uncached_v1"),
                "identification_experiment_plan_v4": ("openai_photo_text_v1", "openai_photo_null_fields_v1"),
            }[spec["version"]]
            selected = spec["runs"] if session else [run for run in spec["runs"] if isinstance(run, dict) and run.get("runId") == run_id]
            if not 1 <= len(selected) <= (4 if session else 1) or any(
                not isinstance(run, dict) or not isinstance(run.get("runId"), str)
                or not re.fullmatch("[a-z0-9][a-z0-9_.:-]{0,79}", run["runId"])
                or run.get("profileId") not in allowed_profiles
                for run in selected
            ) or len({run["runId"] for run in selected}) != len(selected):
                raise ValueError("provider")
        elif spec.get("version") != "identification_provider_run_spec_v1" or spec.get("mode") != "live" or spec.get("profiles") != ["openai_gpt_6_sol"]:
            raise ValueError("provider")
        common = [deno, "run", "--frozen", "--no-prompt", "--cached-only",
                  "--config", "services/supabase/functions/deno.json",
                  "--allow-read=" + str(repository) + "," + str(packet),
                  "--allow-write=" + str(packet), "--allow-run=git"]
        entry = "services/supabase/scripts/evaluate_identification.ts"
        # Existing preflight checks all exact inputs; it cannot read keys or call a provider.
        preflight = subprocess.run(common + ["--deny-net", "--deny-env", entry, "preflight-free-pro-photo" if photo_models else "experiment-preflight" if experiment else "preflight", str(packet)],
                                   cwd=repository, env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if preflight.returncode != 0:
            raise ValueError("preflight")
        if photo_models:
            report_path = packet / "photo-model-preflight.json"
            info = report_path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= 65536:
                raise ValueError("preflight")
            report = json.loads(report_path.read_text())
            if (report.get("version") != "photo_model_preflight_v1" or report.get("budgetFitsRegionalReservation") is not True
                    or report.get("evidenceStatus") != "provisional_reference_pilot"
                    or not isinstance(report.get("source"), dict) or report["source"].get("dirty") is not False):
                raise ValueError("preflight")
    else:
        fingerprint_path = packet / "openai-credential-fingerprint.json"
        if fingerprint_path.exists() or fingerprint_path.is_symlink():
            raise ValueError("fingerprint_exists")
    key = getpass.getpass("Paste Naturebook OpenAI key (hidden; not saved): ")
    if not key or len(key) > 512 or any(c.isspace() for c in key):
        raise ValueError("credential")
    if mode == "--credential-fingerprint":
        record = {"version": "openai_evaluation_credential_fingerprint_v1",
                  "credentialSha256": hashlib.sha256(key.encode()).hexdigest()}
        descriptor = os.open(fingerprint_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(record, output)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        descriptor = os.open(packet, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        print("Credential fingerprint saved privately; no API request was made.")
    else:
        reviewed = photo_models or experiment and spec.get("version") in ("identification_experiment_plan_v2", "identification_experiment_plan_v3", "identification_experiment_plan_v4")
        if reviewed:
            # Only the private local view needs a loopback listener and fixed browser opener.
            common = [arg if arg != "--allow-run=git" else "--allow-run=git,/usr/bin/open" for arg in common]
        environment["OPENAI_EVALUATION_API_KEY"] = key
        # No inherited service keys or Git/SDK overrides; key exists only in child environment.
        # --no-prompt leaves ungranted variables in the "prompt" state. Admission
        # requires explicit denial of service credentials and other-provider overrides.
        try:
            # Reuse only this in-memory key; each run still enters the existing controller.
            for selected_id in ([run["runId"] for run in selected] if experiment else [None]):
                if session and spec_path.read_bytes() != spec_bytes:
                    raise ValueError("spec_changed")
                result = subprocess.run(common + ["--allow-net=api.openai.com:443,127.0.0.1" if reviewed else "--allow-net=api.openai.com:443",
                                        "--allow-env=OPENAI_EVALUATION_API_KEY",
                                        "--deny-env=SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY",
                                        entry, "--experiment-live" if experiment else mode, str(packet)] + ([selected_id] if experiment else []),
                                        cwd=repository, env=environment, stdin=subprocess.DEVNULL,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if result.returncode != 0:
                    raise ValueError("evaluation")
                if photo_models:
                    state_path = packet / "photo-model-run" / "state.json"
                    info = state_path.lstat()
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= 65536:
                        raise ValueError("photo_model_stopped")
                    state = json.loads(state_path.read_text())
                    if (not isinstance(state, dict) or state.get("version") != "photo_model_state_v1"
                            or state.get("complete") is not True or state.get("stop") is not None
                            or state.get("claimedCalls") != 18 or state.get("completedCalls") != 18):
                        raise ValueError("photo_model_stopped")
                if session:
                    state_path = packet / "experiment" / "state.json"
                    info = state_path.lstat()
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= 65536:
                        raise ValueError("session_stopped")
                    state = json.loads(state_path.read_text())
                    # A controller stop can return exit 0 after writing its durable outcome.
                    if (not isinstance(state, dict) or state.get("version") != "identification_experiment_state_v1"
                            or "stop" not in state or state["stop"] is not None
                            or not isinstance(state.get("completedRunIds"), list)
                            or selected_id not in state["completedRunIds"]):
                        raise ValueError("session_stopped")
        finally:
            environment.pop("OPENAI_EVALUATION_API_KEY", None)
            key = None
        print("Evaluation artifacts written. Review the private report for completion and failures.")
    key = None


try:
    main()
except (Exception, KeyboardInterrupt) as error:
    # Only fixed codes; never echo an arbitrary exception or private child output.
    allowed = {"arguments", "path", "outside_repository", "directory", "private_directory",
               "terminal_required", "deno_required", "spec", "provider", "preflight",
               "fingerprint_exists", "credential", "evaluation", "spec_changed", "session_stopped", "photo_model_stopped"}
    reason = str(error) if type(error) is ValueError and str(error) in allowed else "setup"
    if isinstance(error, KeyboardInterrupt):
        reason = "cancelled"
    print("openai_evaluation_launcher_stopped:" + reason, file=sys.stderr)
    sys.exit(1)
' "$evaluation_launcher_root" "$@"

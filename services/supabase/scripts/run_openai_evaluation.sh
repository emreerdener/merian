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
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import warnings


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in ("--credential-fingerprint", "--live"):
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
    if mode == "--live" and not deno:
        raise ValueError("deno_required")
    environment = {name: os.environ[name] for name in ("PATH", "HOME", "DENO_DIR") if name in os.environ}
    if mode == "--live":
        # Reject a different provider before even prompting for its credential.
        spec_path = packet / "spec.json"
        info = spec_path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or not 0 < info.st_size <= 65536:
            raise ValueError("spec")
        spec = json.loads(spec_path.read_text())
        if spec.get("version") != "identification_provider_run_spec_v1" or spec.get("mode") != "live" or spec.get("profiles") != ["openai_gpt_6_sol"]:
            raise ValueError("provider")
        common = [deno, "run", "--frozen", "--no-prompt", "--cached-only",
                  "--config", "services/supabase/functions/deno.json",
                  "--allow-read=" + str(repository) + "," + str(packet),
                  "--allow-write=" + str(packet), "--allow-run=git"]
        entry = "services/supabase/scripts/evaluate_identification.ts"
        # Existing preflight checks all exact inputs; it cannot read keys or call a provider.
        preflight = subprocess.run(common + ["--deny-net", "--deny-env", entry, "preflight", str(packet)],
                                   cwd=repository, env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if preflight.returncode != 0:
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
        environment["OPENAI_EVALUATION_API_KEY"] = key
        # No inherited service keys or Git/SDK overrides; key exists only in child environment.
        # --no-prompt leaves ungranted variables in the "prompt" state. Admission
        # requires explicit denial of service credentials and other-provider overrides.
        result = subprocess.run(common + ["--allow-net=api.openai.com:443",
                                "--allow-env=OPENAI_EVALUATION_API_KEY",
                                "--deny-env=SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY",
                                entry, "--live", str(packet)],
                                cwd=repository, env=environment, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        del environment["OPENAI_EVALUATION_API_KEY"]
        if result.returncode != 0:
            raise ValueError("evaluation")
        print("Evaluation artifacts written. Review the private report for completion and failures.")
    key = None


try:
    main()
except (Exception, KeyboardInterrupt) as error:
    # Only fixed codes; never echo an arbitrary exception or private child output.
    allowed = {"arguments", "path", "outside_repository", "directory", "private_directory",
               "terminal_required", "deno_required", "spec", "provider", "preflight",
               "fingerprint_exists", "credential", "evaluation"}
    reason = str(error) if type(error) is ValueError and str(error) in allowed else "setup"
    if isinstance(error, KeyboardInterrupt):
        reason = "cancelled"
    print("openai_evaluation_launcher_stopped:" + reason, file=sys.stderr)
    sys.exit(1)
' "$evaluation_launcher_root" "$@"

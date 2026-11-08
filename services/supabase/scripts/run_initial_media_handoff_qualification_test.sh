#!/usr/bin/env bash
set -euo pipefail
handoff_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$handoff_script_dir/run_initial_media_handoff_qualification_test.py"

#!/usr/bin/env bash
set -euo pipefail
counter_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$counter_script_dir/test_initial_counter_window.py"

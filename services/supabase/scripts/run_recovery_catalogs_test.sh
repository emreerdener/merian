#!/usr/bin/env bash
set -euo pipefail
recovery_test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 -B "$recovery_test_dir/run_recovery_catalogs_test.py"

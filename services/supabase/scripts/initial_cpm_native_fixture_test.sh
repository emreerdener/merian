#!/usr/bin/env bash
set -euo pipefail
native_fixture_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$native_fixture_script_dir/test_initial_cpm_native_packet.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$native_fixture_script_dir/test_initial_cpm_native_child.py"

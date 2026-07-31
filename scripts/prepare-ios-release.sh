#!/usr/bin/env bash
set -euo pipefail

echo "error: prepare-ios-release is retired; it must not write release build numbers." >&2
echo "Use the manually dispatched 'iOS TestFlight Publisher' workflow." >&2
echo "For a no-write allocation plan, run: make plan-ios-beta LATEST_ASC_BUILD=N" >&2
exit 2

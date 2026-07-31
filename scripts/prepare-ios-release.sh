#!/usr/bin/env bash
set -euo pipefail

echo "error: prepare-ios-release is retired; it must not write release build numbers." >&2
echo "Use the zero-input 'TestFlight Beta' workflow for a routine beta upload." >&2
echo "Use 'iOS TestFlight Publisher (Advanced)' only for planning or immutable recovery." >&2
echo "For a no-write allocation plan, run: make plan-ios-beta LATEST_ASC_BUILD=N" >&2
exit 2

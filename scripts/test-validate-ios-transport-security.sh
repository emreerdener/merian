#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-ios-transport-security.sh"
source_info="$repo_root/apps/ios/Merian/Configuration/Info.plist"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-ats-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "expected command to fail: $*"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "expected failure to contain '$expected'; actual: $output"
}

output="$(bash "$validator" "$source_info" --allow-build-settings)" \
  || fail "the checked-in app Info.plist must enforce ATS defaults"
grep -Fq "ATS defaults enforced" <<<"$output" \
  || fail "source validation did not report ATS enforcement"

python3 - "$test_root" <<'PY'
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])


def write(name, value):
    with (root / name).open("wb") as output:
        plistlib.dump(value, output, sort_keys=False)


write("valid.plist", {"SUPABASE_URL": "https://project.supabase.co"})
write("placeholder.plist", {"SUPABASE_URL": "$(SUPABASE_URL)"})
write(
    "arbitrary.plist",
    {"NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}},
)
write(
    "media.plist",
    {"NSAppTransportSecurity": {"NSAllowsArbitraryLoadsForMedia": True}},
)
write(
    "exceptions.plist",
    {
        "NSAppTransportSecurity": {
            "NSExceptionDomains": {"example.com": {"NSExceptionAllowsInsecureHTTPLoads": True}}
        }
    },
)
write("http.plist", {"SUPABASE_URL": "http://project.supabase.co"})
write(
    "credentials.plist",
    {"SUPABASE_URL": "https://user:secret@project.supabase.co"},
)
PY

bash "$validator" "$test_root/valid.plist" >/dev/null \
  || fail "credential-free HTTPS fixture must pass"
bash "$validator" "$test_root/placeholder.plist" --allow-build-settings >/dev/null \
  || fail "source build-setting placeholder must pass in source mode"

assert_fails_with \
  "unresolved build setting" \
  bash "$validator" "$test_root/placeholder.plist"
assert_fails_with \
  "NSAllowsArbitraryLoads must not enable" \
  bash "$validator" "$test_root/arbitrary.plist"
assert_fails_with \
  "NSAllowsArbitraryLoadsForMedia must not enable" \
  bash "$validator" "$test_root/media.plist"
assert_fails_with \
  "NSExceptionDomains is not approved" \
  bash "$validator" "$test_root/exceptions.plist"
assert_fails_with \
  "credential-free HTTPS URL" \
  bash "$validator" "$test_root/http.plist"
assert_fails_with \
  "credential-free HTTPS URL" \
  bash "$validator" "$test_root/credentials.plist"

ln -s "$test_root/valid.plist" "$test_root/symlink.plist"
assert_fails_with \
  "regular, non-symbolic-link file" \
  bash "$validator" "$test_root/symlink.plist"

echo "iOS transport-security validation tests passed."

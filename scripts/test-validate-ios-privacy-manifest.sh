#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-ios-privacy-manifest.sh"
manifest="$repo_root/apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-privacy-manifest-tests.XXXXXX")"
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

output="$(bash "$validator" "$manifest")" \
  || fail "the checked-in privacy manifest must pass validation"
grep -Fq "collectedDataTypes=16; accessedAPITypes=3" <<<"$output" \
  || fail "baseline validation did not report the expected manifest coverage"

assert_fails_with \
  "manifest must be a regular, non-symbolic-link file" \
  bash "$validator" "$test_root/missing.xcprivacy"

ln -s "$manifest" "$test_root/symlink.xcprivacy"
assert_fails_with \
  "manifest must be a regular, non-symbolic-link file" \
  bash "$validator" "$test_root/symlink.xcprivacy"

printf '%s\n' 'not a property list' > "$test_root/malformed.xcprivacy"
assert_fails_with \
  "could not be parsed" \
  bash "$validator" "$test_root/malformed.xcprivacy"

python3 - "$manifest" "$test_root" <<'PY'
import copy
import plistlib
import sys
from pathlib import Path

source = Path(sys.argv[1])
output_root = Path(sys.argv[2])
with source.open("rb") as source_file:
    baseline = plistlib.load(source_file)


def write_fixture(name, mutate):
    fixture = copy.deepcopy(baseline)
    mutate(fixture)
    with (output_root / name).open("wb") as fixture_file:
        plistlib.dump(fixture, fixture_file, sort_keys=False)


write_fixture(
    "tracking-enabled.xcprivacy",
    lambda fixture: fixture.__setitem__("NSPrivacyTracking", True),
)
write_fixture(
    "missing-user-defaults.xcprivacy",
    lambda fixture: fixture.__setitem__(
        "NSPrivacyAccessedAPITypes",
        [
            entry
            for entry in fixture["NSPrivacyAccessedAPITypes"]
            if entry["NSPrivacyAccessedAPIType"]
            != "NSPrivacyAccessedAPICategoryUserDefaults"
        ],
    ),
)


def replace_file_reason(fixture):
    for entry in fixture["NSPrivacyAccessedAPITypes"]:
        if entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryFileTimestamp":
            entry["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1"]


write_fixture("wrong-file-reason.xcprivacy", replace_file_reason)


def replace_disk_reason(fixture):
    for entry in fixture["NSPrivacyAccessedAPITypes"]:
        if entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryDiskSpace":
            entry["NSPrivacyAccessedAPITypeReasons"] = ["85F4.1"]


write_fixture("wrong-disk-reason.xcprivacy", replace_disk_reason)
write_fixture(
    "missing-name.xcprivacy",
    lambda fixture: fixture.__setitem__(
        "NSPrivacyCollectedDataTypes",
        [
            entry
            for entry in fixture["NSPrivacyCollectedDataTypes"]
            if entry["NSPrivacyCollectedDataType"] != "NSPrivacyCollectedDataTypeName"
        ],
    ),
)


def enable_product_tracking(fixture):
    for entry in fixture["NSPrivacyCollectedDataTypes"]:
        if entry["NSPrivacyCollectedDataType"] == "NSPrivacyCollectedDataTypeProductInteraction":
            entry["NSPrivacyCollectedDataTypeTracking"] = True


write_fixture("product-tracking.xcprivacy", enable_product_tracking)
PY

assert_fails_with \
  "NSPrivacyTracking must be false" \
  bash "$validator" "$test_root/tracking-enabled.xcprivacy"
assert_fails_with \
  "missing=[NSPrivacyAccessedAPICategoryUserDefaults]" \
  bash "$validator" "$test_root/missing-user-defaults.xcprivacy"
assert_fails_with \
  "NSPrivacyAccessedAPICategoryFileTimestamp reasons ['DDA9.1'] do not match ['C617.1']" \
  bash "$validator" "$test_root/wrong-file-reason.xcprivacy"
assert_fails_with \
  "NSPrivacyAccessedAPICategoryDiskSpace reasons ['85F4.1'] do not match ['E174.1']" \
  bash "$validator" "$test_root/wrong-disk-reason.xcprivacy"
assert_fails_with \
  "missing=[NSPrivacyCollectedDataTypeName]" \
  bash "$validator" "$test_root/missing-name.xcprivacy"
assert_fails_with \
  "NSPrivacyCollectedDataTypeProductInteraction configuration" \
  bash "$validator" "$test_root/product-tracking.xcprivacy"

echo "iOS privacy manifest validation tests passed."

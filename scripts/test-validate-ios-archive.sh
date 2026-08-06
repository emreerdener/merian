#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_validator="$repo_root/scripts/validate-ios-archive.sh"
privacy_manifest="$repo_root/apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy"
plistbuddy_fixture="$repo_root/scripts/test-plistbuddy.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-archive-validation-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

expected_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expected_fingerprint="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
archive_path="$test_root/Merian.xcarchive"
app_path="$archive_path/Products/Applications/Merian.app"
bundled_privacy_manifest="$app_path/PrivacyInfo.xcprivacy"

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

mkdir -p \
  "$app_path/PlugIns/MerianExploreWidget.appex" \
  "$app_path/PlugIns/MerianMessagesExtension.appex" \
  "$app_path/Watch/MerianWatch.app"

python3 - \
  "$archive_path" \
  "$app_path" \
  "$expected_revision" \
  "$expected_fingerprint" <<'PY'
import plistlib
import sys
from pathlib import Path

archive_path = Path(sys.argv[1])
app_path = Path(sys.argv[2])
source_revision = sys.argv[3]
source_fingerprint = sys.argv[4]


def write_plist(path, value):
    with path.open("wb") as plist_file:
        plistlib.dump(value, plist_file, sort_keys=False)


write_plist(
    archive_path / "Info.plist",
    {"ApplicationProperties": {"ApplicationPath": "Applications/Merian.app"}},
)
write_plist(
    app_path / "Info.plist",
    {
        "CFBundleIdentifier": "app.merian.Merian",
        "CFBundleShortVersionString": "1.0.3",
        "CFBundleVersion": "275",
        "MERIAN_SOURCE_REVISION": source_revision,
        "MERIAN_SOURCE_FINGERPRINT": source_fingerprint,
        "MERIAN_SOURCE_STATE": "clean",
    },
)

component_info = {
    "CFBundleShortVersionString": "1.0.3",
    "CFBundleVersion": "275",
}
for relative_path in (
    "PlugIns/MerianExploreWidget.appex/Info.plist",
    "PlugIns/MerianMessagesExtension.appex/Info.plist",
    "Watch/MerianWatch.app/Info.plist",
):
    write_plist(app_path / relative_path, component_info)
PY

cp "$privacy_manifest" "$bundled_privacy_manifest"

validation_command=(
  env MERIAN_PLISTBUDDY_COMMAND="$plistbuddy_fixture"
  bash "$archive_validator"
  "$archive_path"
  app.merian.Merian
  1.0.3
  275
  "$expected_revision"
  "$expected_fingerprint"
)

output="$("${validation_command[@]}")" \
  || fail "archive fixture with a valid privacy manifest must pass"
grep -Fq "privacyManifest=valid" <<<"$output" \
  || fail "archive validation did not report a valid privacy manifest"

rm "$bundled_privacy_manifest"
assert_fails_with \
  "manifest must be a regular, non-symbolic-link file" \
  "${validation_command[@]}"

cp "$privacy_manifest" "$bundled_privacy_manifest"
python3 - "$bundled_privacy_manifest" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as manifest_file:
    manifest = plistlib.load(manifest_file)
manifest["NSPrivacyTracking"] = True
with path.open("wb") as manifest_file:
    plistlib.dump(manifest, manifest_file, sort_keys=False)
PY
assert_fails_with \
  "NSPrivacyTracking must be false" \
  "${validation_command[@]}"

echo "iOS Release archive privacy-manifest tests passed."

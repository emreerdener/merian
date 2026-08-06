#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ipa_validator="$repo_root/scripts/validate-ios-exported-ipa.sh"
privacy_manifest="$repo_root/apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy"
plistbuddy_fixture="$repo_root/scripts/test-plistbuddy.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-ipa-validation-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

expected_revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expected_fingerprint="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
payload_root="$test_root/package"
app_path="$payload_root/Payload/Merian.app"
bundled_privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
zip_command="$(command -v zip)"
unzip_command="$(command -v unzip)"
shasum_command="$(command -v shasum)"

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

build_ipa() {
  local output="$1"
  (
    cd "$payload_root"
    "$zip_command" -qry "$output" Payload
  )
}

validation_command() {
  local ipa_path="$1"
  env \
    MERIAN_PLISTBUDDY_COMMAND="$plistbuddy_fixture" \
    MERIAN_UNZIP_COMMAND="$unzip_command" \
    MERIAN_SHASUM_COMMAND="$shasum_command" \
    bash "$ipa_validator" \
    "$ipa_path" \
    Merian.app \
    app.merian.Merian \
    1.0.3 \
    275 \
    "$expected_revision" \
    "$expected_fingerprint"
}

mkdir -p \
  "$app_path/PlugIns/MerianExploreWidget.appex" \
  "$app_path/PlugIns/MerianMessagesExtension.appex" \
  "$app_path/Watch/MerianWatch.app"

python3 - \
  "$app_path" \
  "$expected_revision" \
  "$expected_fingerprint" <<'PY'
import plistlib
import sys
from pathlib import Path

app_path = Path(sys.argv[1])
source_revision = sys.argv[2]
source_fingerprint = sys.argv[3]


def write_plist(path, value):
    with path.open("wb") as plist_file:
        plistlib.dump(value, plist_file, sort_keys=False)


write_plist(
    app_path / "Info.plist",
    {
        "CFBundlePackageType": "APPL",
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

valid_ipa="$test_root/valid.ipa"
build_ipa "$valid_ipa"
output="$(validation_command "$valid_ipa")" \
  || fail "IPA fixture with a valid root privacy manifest must pass"
grep -Fq "privacyManifest=valid" <<<"$output" \
  || fail "IPA validation did not report a valid privacy manifest"

missing_ipa="$test_root/missing-privacy.ipa"
mv "$bundled_privacy_manifest" "$test_root/PrivacyInfo.xcprivacy"
build_ipa "$missing_ipa"
assert_fails_with \
  "exactly one root application PrivacyInfo.xcprivacy; found 0" \
  validation_command "$missing_ipa"

mv "$test_root/PrivacyInfo.xcprivacy" "$bundled_privacy_manifest"
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
invalid_ipa="$test_root/invalid-privacy.ipa"
build_ipa "$invalid_ipa"
assert_fails_with \
  "NSPrivacyTracking must be false" \
  validation_command "$invalid_ipa"

echo "iOS exported-IPA privacy-manifest tests passed."

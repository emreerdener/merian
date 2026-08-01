#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plistbuddy_command="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}"

fail() {
  echo "error: Release archive validation failed: $*" >&2
  exit 1
}

read_plist_value() {
  local plist="$1"
  local key="$2"
  local value

  value="$("$plistbuddy_command" -c "Print :${key}" "$plist" 2>/dev/null)" \
    || fail "$plist has no readable ${key}."
  [[ -n "$value" ]] || fail "$plist has an empty ${key}."
  printf '%s\n' "$value"
}

verify_version() {
  local label="$1"
  local plist="$2"
  local version
  local build

  [[ -f "$plist" && ! -L "$plist" ]] || fail "$label Info.plist is missing."
  version="$(read_plist_value "$plist" CFBundleShortVersionString)"
  build="$(read_plist_value "$plist" CFBundleVersion)"
  [[ "$version" == "$expected_version" ]] \
    || fail "$label version $version does not match $expected_version."
  [[ "$build" == "$expected_build" ]] \
    || fail "$label build $build does not match $expected_build."
}

(( $# == 6 )) \
  || fail "usage: $0 ARCHIVE_PATH BUNDLE_ID VERSION BUILD SOURCE_REVISION SOURCE_FINGERPRINT"

archive_path="$1"
expected_bundle_id="$2"
expected_version="$3"
expected_build="$4"
expected_source_revision="$5"
expected_source_fingerprint="$6"

[[ -d "$archive_path" && ! -L "$archive_path" ]] \
  || fail "archive must be a non-symbolic-link directory."
[[ "$plistbuddy_command" == /* && -x "$plistbuddy_command" ]] \
  || fail "PlistBuddy must be an executable absolute path."
[[ "$expected_bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail "expected bundle ID is malformed."
[[ "$expected_version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] || fail "expected version is malformed."
[[ "$expected_build" =~ ^[1-9][0-9]*$ ]] || fail "expected build is malformed."
[[ "$expected_source_revision" =~ ^[0-9a-f]{40,64}$ ]] || fail "expected source revision is malformed."
[[ "$expected_source_fingerprint" =~ ^[0-9a-f]{64}$ ]] || fail "expected source fingerprint is malformed."

archive_info="$archive_path/Info.plist"
[[ -f "$archive_info" && ! -L "$archive_info" ]] || fail "archive Info.plist is missing."
application_path="$(read_plist_value "$archive_info" ApplicationProperties:ApplicationPath)"
[[ "$application_path" =~ ^Applications/[A-Za-z0-9][A-Za-z0-9._-]*\.app$ ]] \
  || fail "archive application path is malformed: $application_path."

app_path="$archive_path/Products/$application_path"
app_info="$app_path/Info.plist"
verify_version "main app" "$app_info"

bundle_id="$(read_plist_value "$app_info" CFBundleIdentifier)"
source_revision="$(read_plist_value "$app_info" MERIAN_SOURCE_REVISION)"
source_fingerprint="$(read_plist_value "$app_info" MERIAN_SOURCE_FINGERPRINT)"
source_state="$(read_plist_value "$app_info" MERIAN_SOURCE_STATE)"

[[ "$bundle_id" == "$expected_bundle_id" ]] \
  || fail "main app bundle ID $bundle_id does not match $expected_bundle_id."
[[ "$source_revision" == "$expected_source_revision" ]] \
  || fail "embedded source revision does not match the expected release source."
[[ "$source_fingerprint" == "$expected_source_fingerprint" ]] \
  || fail "embedded source fingerprint does not match the expected release source."
[[ "$source_state" == "clean" ]] \
  || fail "embedded source state is $source_state; expected clean."

verify_version "Explore widget" "$app_path/PlugIns/MerianExploreWidget.appex/Info.plist"
verify_version "Messages extension" "$app_path/PlugIns/MerianMessagesExtension.appex/Info.plist"
verify_version "watch app" "$app_path/Watch/MerianWatch.app/Info.plist"

archive_identity="$(bash "$script_dir/hash-ios-archive.sh" "$archive_path")"
[[ "$archive_identity" =~ ^[0-9a-f]{64}$ ]] || fail "archive identity is malformed."

echo "Release archive verified for ${bundle_id} ${expected_version} (${expected_build}); source=${source_revision} fingerprint=${source_fingerprint} state=clean; embeddedComponents=3."
echo "archive_identity=${archive_identity}"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plistbuddy_command="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}"
unzip_command="${MERIAN_UNZIP_COMMAND:-/usr/bin/unzip}"
shasum_command="${MERIAN_SHASUM_COMMAND:-/usr/bin/shasum}"

fail() {
  echo "error: Exported IPA validation failed: $*" >&2
  exit 1
}

usage() {
  fail "usage: $0 IPA_PATH APP_BUNDLE_NAME BUNDLE_ID VERSION BUILD SOURCE_REVISION SOURCE_FINGERPRINT"
}

read_plist_value() {
  local plist="$1"
  local key="$2"
  local value

  if ! value="$("$plistbuddy_command" -c "Print :${key}" "$plist" 2>/dev/null)"; then
    fail "$plist is missing a readable ${key}."
  fi
  [[ -n "$value" ]] || fail "$plist has an empty ${key}."
  printf '%s\n' "$value"
}

extract_plist() {
  local entry="$1"
  local output="$2"
  local byte_count

  if ! "$unzip_command" -p "$ipa_path" "$entry" > "$output"; then
    fail "could not extract ${entry}."
  fi
  [[ -s "$output" ]] || fail "${entry} is empty."

  byte_count="$(wc -c < "$output" | tr -d '[:space:]')"
  [[ "$byte_count" =~ ^[1-9][0-9]*$ ]] \
    || fail "could not determine the size of ${entry}."
  (( byte_count <= 1048576 )) \
    || fail "${entry} exceeds the 1 MiB plist validation limit."
}

verify_component_version() {
  local entry="$1"
  local plist="$2"
  local component_version
  local component_build

  component_version="$(read_plist_value "$plist" "CFBundleShortVersionString")"
  component_build="$(read_plist_value "$plist" "CFBundleVersion")"

  [[ "$component_version" == "$expected_version" ]] \
    || fail "${entry} version ${component_version} does not match expected version ${expected_version}."
  [[ "$component_build" == "$expected_build" ]] \
    || fail "${entry} build ${component_build} does not match expected build ${expected_build}."
}

hash_ipa() {
  local digest_output
  local digest

  if ! digest_output="$("$shasum_command" -a 256 -- "$ipa_path")"; then
    fail "could not compute the IPA SHA-256 digest."
  fi
  digest="$(awk 'NR == 1 { print $1 }' <<<"$digest_output")"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] \
    || fail "shasum returned a malformed IPA SHA-256 digest."
  printf '%s\n' "$digest"
}

(( $# == 7 )) || usage

ipa_path="$1"
expected_app_bundle_name="$2"
expected_bundle_id="$3"
expected_version="$4"
expected_build="$5"
expected_source_revision="$6"
expected_source_fingerprint="$7"

[[ "$expected_app_bundle_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]app$ ]] \
  || fail "expected app bundle name is malformed: ${expected_app_bundle_name}."
[[ "$expected_bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
  || fail "expected bundle identifier is malformed: ${expected_bundle_id}."
[[ "$expected_version" =~ ^[1-9][0-9]*[.][0-9]+[.][0-9]+$ ]] \
  || fail "expected semantic version is malformed: ${expected_version}."
[[ "$expected_build" =~ ^[1-9][0-9]*$ ]] \
  || fail "expected build is malformed: ${expected_build}."
[[ "$expected_source_revision" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail "expected source revision is malformed."
[[ "$expected_source_fingerprint" =~ ^[0-9a-f]{64}$ ]] \
  || fail "expected source fingerprint is malformed."

[[ "$plistbuddy_command" == /* ]] \
  || fail "PlistBuddy command must be an absolute path."
[[ -x "$plistbuddy_command" ]] \
  || fail "PlistBuddy is unavailable at ${plistbuddy_command}."
[[ "$unzip_command" == /* ]] \
  || fail "unzip command must be an absolute path."
[[ -x "$unzip_command" ]] \
  || fail "unzip is unavailable at ${unzip_command}."
[[ "$shasum_command" == /* ]] \
  || fail "shasum command must be an absolute path."
[[ -x "$shasum_command" ]] \
  || fail "shasum is unavailable at ${shasum_command}."
[[ -f "$ipa_path" && ! -L "$ipa_path" ]] \
  || fail "IPA must be a regular, non-symbolic-link file: ${ipa_path}."

initial_ipa_sha256="$(hash_ipa)"

validation_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ipa-validation.XXXXXX")"
trap 'rm -rf "$validation_tmp_dir"' EXIT HUP INT TERM

listing="$validation_tmp_dir/entries.txt"
if ! "$unzip_command" -Z1 "$ipa_path" > "$listing"; then
  fail "could not list the IPA archive."
fi
[[ -s "$listing" ]] || fail "IPA archive has no entries."

duplicate_entry="$(
  LC_ALL=C sort "$listing" | awk '
    previous == $0 && first == "" {
      first = $0
    }
    {
      previous = $0
    }
    END {
      print first
    }
  '
)"
[[ -z "$duplicate_entry" ]] \
  || fail "IPA contains a duplicate archive entry: ${duplicate_entry}."

root_info_entries="$validation_tmp_dir/root-info-entries.txt"
awk '$0 ~ "^Payload/[^/]+[.]app/Info[.]plist$" { print }' \
  "$listing" > "$root_info_entries"
root_info_count="$(awk 'END { print NR + 0 }' "$root_info_entries")"
(( root_info_count == 1 )) \
  || fail "IPA must contain exactly one root application Info.plist; found ${root_info_count}."

expected_root_info_entry="Payload/${expected_app_bundle_name}/Info.plist"
root_info_entry="$(awk 'NR == 1 { print }' "$root_info_entries")"
[[ "$root_info_entry" == "$expected_root_info_entry" ]] \
  || fail "root application path ${root_info_entry} does not match expected ${expected_root_info_entry}."

main_info="$validation_tmp_dir/main-Info.plist"
extract_plist "$root_info_entry" "$main_info"

root_privacy_entries="$validation_tmp_dir/root-privacy-entries.txt"
awk '$0 ~ "^Payload/[^/]+[.]app/PrivacyInfo[.]xcprivacy$" { print }' \
  "$listing" > "$root_privacy_entries"
root_privacy_count="$(awk 'END { print NR + 0 }' "$root_privacy_entries")"
(( root_privacy_count == 1 )) \
  || fail "IPA must contain exactly one root application PrivacyInfo.xcprivacy; found ${root_privacy_count}."

expected_root_privacy_entry="Payload/${expected_app_bundle_name}/PrivacyInfo.xcprivacy"
root_privacy_entry="$(awk 'NR == 1 { print }' "$root_privacy_entries")"
[[ "$root_privacy_entry" == "$expected_root_privacy_entry" ]] \
  || fail "root privacy manifest path ${root_privacy_entry} does not match expected ${expected_root_privacy_entry}."

main_privacy_manifest="$validation_tmp_dir/PrivacyInfo.xcprivacy"
extract_plist "$root_privacy_entry" "$main_privacy_manifest"
if ! bash "$script_dir/validate-ios-privacy-manifest.sh" "$main_privacy_manifest"; then
  fail "main app privacy manifest is invalid."
fi
if ! bash "$script_dir/validate-ios-transport-security.sh" "$main_info"; then
  fail "main app transport-security configuration is invalid."
fi

main_package_type="$(read_plist_value "$main_info" "CFBundlePackageType")"
main_bundle_id="$(read_plist_value "$main_info" "CFBundleIdentifier")"
main_version="$(read_plist_value "$main_info" "CFBundleShortVersionString")"
main_build="$(read_plist_value "$main_info" "CFBundleVersion")"
main_source_revision="$(read_plist_value "$main_info" "MERIAN_SOURCE_REVISION")"
main_source_fingerprint="$(read_plist_value "$main_info" "MERIAN_SOURCE_FINGERPRINT")"
main_source_state="$(read_plist_value "$main_info" "MERIAN_SOURCE_STATE")"

[[ "$main_package_type" == "APPL" ]] \
  || fail "main app package type ${main_package_type} is not APPL."
[[ "$main_bundle_id" == "$expected_bundle_id" ]] \
  || fail "main app bundle identifier ${main_bundle_id} does not match expected ${expected_bundle_id}."
[[ "$main_version" == "$expected_version" ]] \
  || fail "main app version ${main_version} does not match expected version ${expected_version}."
[[ "$main_build" == "$expected_build" ]] \
  || fail "main app build ${main_build} does not match expected build ${expected_build}."
[[ "$main_source_revision" == "$expected_source_revision" ]] \
  || fail "main app source revision does not match the exported archive."
[[ "$main_source_fingerprint" == "$expected_source_fingerprint" ]] \
  || fail "main app source fingerprint does not match the exported archive."
[[ "$main_source_state" == "clean" ]] \
  || fail "main app source state is ${main_source_state}; expected clean."

component_entries="$validation_tmp_dir/component-info-entries.txt"
awk -v prefix="Payload/${expected_app_bundle_name}/" '
  index($0, prefix "PlugIns/") == 1 {
    remainder = substr($0, length(prefix "PlugIns/") + 1)
    if (remainder ~ "^[^/]+[.]appex/Info[.]plist$") {
      print
    }
  }
  index($0, prefix "Watch/") == 1 {
    remainder = substr($0, length(prefix "Watch/") + 1)
    if (remainder ~ "^[^/]+[.]app/Info[.]plist$") {
      print
    }
  }
' "$listing" > "$component_entries"

required_component_entries=(
  "Payload/${expected_app_bundle_name}/PlugIns/MerianExploreWidget.appex/Info.plist"
  "Payload/${expected_app_bundle_name}/PlugIns/MerianMessagesExtension.appex/Info.plist"
  "Payload/${expected_app_bundle_name}/Watch/MerianWatch.app/Info.plist"
)
for required_component_entry in "${required_component_entries[@]}"; do
  grep -Fxq -- "$required_component_entry" "$component_entries" \
    || fail "IPA is missing required embedded component: ${required_component_entry}."
done

component_count=0
while IFS= read -r component_entry; do
  [[ -n "$component_entry" ]] || continue
  component_count=$((component_count + 1))
  component_info="$validation_tmp_dir/component-${component_count}-Info.plist"
  extract_plist "$component_entry" "$component_info"
  verify_component_version "$component_entry" "$component_info"
done < "$component_entries"

(( component_count >= ${#required_component_entries[@]} )) \
  || fail "IPA contains fewer embedded components than required."

[[ -f "$ipa_path" && ! -L "$ipa_path" ]] \
  || fail "IPA changed file type while it was being validated: ${ipa_path}."
final_ipa_sha256="$(hash_ipa)"
[[ "$final_ipa_sha256" == "$initial_ipa_sha256" ]] \
  || fail "IPA contents changed while metadata was being validated."

echo "Exported IPA metadata verified for ${main_bundle_id} ${main_version} (${main_build}); source=${main_source_revision} fingerprint=${main_source_fingerprint} state=clean; privacyManifest=valid; transportSecurity=ats-default; embeddedComponents=${component_count}."
echo "ipa_sha256=${final_ipa_sha256}"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"
repo_root="$(cd "$repo_root" && pwd -P)"
archive_validator="$script_dir/validate-ios-archive.sh"
ipa_validator="$script_dir/validate-ios-exported-ipa.sh"
plistbuddy_command="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}"
xcodebuild_command="${XCODEBUILD_COMMAND:-xcodebuild}"

fail() {
  echo "error: iOS release export: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
}

canonicalize_maybe_missing_path() {
  perl -MCwd=abs_path -MFile::Basename=basename,dirname -MFile::Spec -e '
    my $path = File::Spec->rel2abs($ARGV[0]);
    my @missing;
    while (!-e $path) {
      my $name = basename($path);
      my $parent = dirname($path);
      die "could not resolve path\n" if $parent eq $path;
      unshift @missing, $name;
      $path = $parent;
    }
    my $resolved = abs_path($path);
    die "could not canonicalize path\n" unless defined $resolved;
    print File::Spec->catfile($resolved, @missing);
  ' "$1"
}

reject_dot_path_components() {
  local label="$1"
  local path="$2"
  case "/$path/" in
    */../* | */./*) fail "$label must not contain . or .. path components: $path" ;;
  esac
}

read_plist_value() {
  local plist="$1"
  local key="$2"
  "$plistbuddy_command" -c "Print :${key}" "$plist" 2>/dev/null
}

write_export_options() {
  local output="$1"
  local team_id="$2"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    '  <key>destination</key>' \
    '  <string>export</string>' \
    '  <key>method</key>' \
    '  <string>app-store-connect</string>' \
    '  <key>signingStyle</key>' \
    '  <string>automatic</string>' \
    '  <key>manageAppVersionAndBuildNumber</key>' \
    '  <false/>' \
    '  <key>teamID</key>' \
    "  <string>${team_id}</string>" \
    '  <key>uploadSymbols</key>' \
    '  <true/>' \
    '  <key>stripSwiftSymbols</key>' \
    '  <true/>' \
    '  <key>testFlightInternalTestingOnly</key>' \
    '  <false/>' \
    '</dict>' \
    '</plist>' > "$output"
}

[[ "${MERIAN_RELEASE_PUBLISHER:-0}" == "1" ]] \
  || fail "standalone Organizer/manual export is unsupported; use the serialized publisher workflow."
[[ "${MERIAN_PUBLISHER_SERIALIZED:-0}" == "1" ]] \
  || fail "publisher concurrency lock is not asserted."

plan_path="${IOS_PUBLISHER_PLAN:-}"
archive_path="${ARCHIVE_PATH:-}"
export_path_input="${EXPORT_PATH:-}"
expected_version="${MERIAN_EXPECTED_MARKETING_VERSION:-}"
expected_build="${MERIAN_EXPECTED_BUILD_NUMBER:-}"
expected_revision="${MERIAN_EXPECTED_SOURCE_REVISION:-}"
expected_fingerprint="${MERIAN_EXPECTED_SOURCE_FINGERPRINT:-}"
expected_bundle_id="${IOS_APP_BUNDLE_ID:-app.merian.Merian}"

[[ -f "$plan_path" && ! -L "$plan_path" ]] || fail "publisher plan JSON is required."
[[ -d "$archive_path" && ! -L "$archive_path" ]] || fail "an explicit publisher archive path is required."
[[ -n "$export_path_input" ]] || fail "an explicit export path is required."
[[ "$expected_version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] || fail "expected version is malformed."
[[ "$expected_build" =~ ^[1-9][0-9]*$ ]] || fail "expected build is malformed."
[[ "$expected_revision" =~ ^[0-9a-f]{40,64}$ ]] || fail "expected source revision is malformed."
[[ "$expected_fingerprint" =~ ^[0-9a-f]{64}$ ]] || fail "expected source fingerprint is malformed."
[[ "$plistbuddy_command" == /* && -x "$plistbuddy_command" ]] || fail "PlistBuddy must be an executable absolute path."
[[ -f "$archive_validator" && -f "$ipa_validator" ]] || fail "release validators are missing."

ruby -rjson -e '
  path, version, build, revision, fingerprint = ARGV
  document = JSON.parse(File.binread(path))
  abort("invalid publisher plan") unless document.is_a?(Hash) && document["kind"] == "merian-ios-beta-publisher-plan"
  abort("plan is not a live build reservation") unless ["candidate", "upload"].include?(document["mode"])
  abort("plan is not at the build-reserved stage") unless document["stage"] == "build_reserved"
  abort("plan source is not clean") unless document.dig("source", "state") == "clean"
  abort("plan is not serialized") unless document.dig("publisher", "serialized") == true
  abort("plan has no external-state authorization") unless document.dig("publisher", "external_state_authorized") == true
  abort("plan live preconditions were not met") unless document["live_preconditions_met"] == true
  abort("plan does not authorize exactly one archive") unless document.dig("archive", "planned_invocations") == 1
  abort("plan version mismatch") unless document["version"] == version
  abort("plan build mismatch") unless document["build"] == Integer(build)
  abort("plan source mismatch") unless document.dig("source", "revision") == revision
  abort("plan fingerprint mismatch") unless document.dig("source", "fingerprint") == fingerprint
  abort("plan enabled Xcode renumbering") unless document.dig("export", "manageAppVersionAndBuildNumber") == false
' "$plan_path" "$expected_version" "$expected_build" "$expected_revision" "$expected_fingerprint" \
  || fail "publisher plan does not authorize this exact export."

mkdir -p "$repo_root/build"
build_root="$(cd "$repo_root/build" && pwd -P)"
reject_dot_path_components "EXPORT_PATH" "$export_path_input"
export_path="$(canonicalize_maybe_missing_path "$export_path_input")" \
  || fail "could not canonicalize EXPORT_PATH."
case "$export_path" in
  "$build_root"/*) ;;
  *) fail "EXPORT_PATH must be a child of $build_root; resolved: $export_path" ;;
esac
[[ ! -e "$export_path" ]] || fail "EXPORT_PATH already exists; a release export must never overwrite evidence."
mkdir "$export_path"

export_options="$export_path/exportOptions.plist"
team_id="${TEAM_ID:-${ASC_TEAM_ID:-}}"
if [[ -z "$team_id" ]]; then
  team_id="$(read_plist_value "$archive_path/Info.plist" ApplicationProperties:Team || true)"
fi
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "Apple team ID is missing or malformed."
write_export_options "$export_options" "$team_id"

archive_validation_output="$(
  MERIAN_PLISTBUDDY_COMMAND="$plistbuddy_command" \
    bash "$archive_validator" "$archive_path" "$expected_bundle_id" "$expected_version" "$expected_build" "$expected_revision" "$expected_fingerprint"
)"
archive_identity_before="$(awk -F= '$1 == "archive_identity" { print $2 }' <<<"$archive_validation_output")"
[[ "$archive_identity_before" =~ ^[0-9a-f]{64}$ ]] || fail "archive validator returned no identity."

command=(
  "$xcodebuild_command"
  -exportArchive
  -archivePath "$archive_path"
  -exportOptionsPlist "$export_options"
  -exportPath "$export_path"
  -allowProvisioningUpdates
)
if [[ -n "${ASC_KEY_ID:-}" || -n "${ASC_ISSUER_ID:-}" || -n "${ASC_PRIVATE_KEY_PATH:-}" ]]; then
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -r "${ASC_PRIVATE_KEY_PATH:-}" ]] \
    || fail "App Store Connect export credentials are incomplete."
  command+=(
    -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
  note "Using App Store Connect API-key authentication for export."
fi

export_log="$export_path/export.log"
note "Exporting evidence-bound ${expected_version} (${expected_build}) with Xcode renumbering disabled."
set +e
"${command[@]}" 2>&1 | tee "$export_log"
export_pipeline_status=("${PIPESTATUS[@]}")
status="${export_pipeline_status[0]}"
log_status="${export_pipeline_status[1]}"
set -e
(( log_status == 0 )) || fail "export log could not be retained; this build is not publishable."
(( status == 0 )) || fail "xcodebuild -exportArchive failed; see $export_log"

archive_identity_after="$(bash "$script_dir/hash-ios-archive.sh" "$archive_path")"
[[ "$archive_identity_after" == "$archive_identity_before" ]] || fail "archive changed while being exported."

shopt -s nullglob
ipa_candidates=("$export_path"/*.ipa "$export_path"/*/*.ipa)
shopt -u nullglob
(( ${#ipa_candidates[@]} == 1 )) || fail "export must produce exactly one IPA; found ${#ipa_candidates[@]}."
ipa_path="${ipa_candidates[0]}"
[[ -f "$ipa_path" && ! -L "$ipa_path" ]] || fail "exported IPA is not a regular file."

MERIAN_PLISTBUDDY_COMMAND="$plistbuddy_command" \
  bash "$ipa_validator" "$ipa_path" "Merian.app" "$expected_bundle_id" "$expected_version" "$expected_build" "$expected_revision" "$expected_fingerprint"

note "Exported publisher-bound IPA: $ipa_path"
note "Archive identity retained: $archive_identity_before"

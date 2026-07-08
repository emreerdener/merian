#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"

fail() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "$*" >&2
}

resolve_repo_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$repo_root" "$path"
  fi
}

extract_project_setting() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
}

read_plist_value() {
  local plist="$1"
  local key_path="$2"
  /usr/libexec/PlistBuddy -c "Print :${key_path}" "$plist" 2>/dev/null
}

newest_archive() {
  local archive_root="$HOME/Library/Developer/Xcode/Archives"
  [[ -d "$archive_root" ]] || return 1
  find "$archive_root" -maxdepth 3 -name "*.xcarchive" -print0 | perl -0ne '
    chomp;
    my $mtime = (stat($_))[9];
    if (!defined($best) || $mtime > $best_mtime) {
      $best = $_;
      $best_mtime = $mtime;
    }
    END {
      print $best if defined $best;
    }
  '
}

have_asc_key_auth() {
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY_PATH:-}" ]]
}

write_export_options() {
  local output="$1"
  local team_id="$2"

  cat > "$output" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>uploadSymbols</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>testFlightInternalTestingOnly</key>
  <false/>
</dict>
</plist>
PLIST
}

explain_export_failure() {
  local log_file="$1"
  local team_id="$2"

  if grep -Eq 'No Accounts|No signing certificate "iOS Distribution"|Invalid credentials.*Xcode-Username|Fetching apps .* timed out' "$log_file"; then
    {
      echo
      echo "error: App Store Connect export failed because Xcode has no valid Apple account/distribution signing credentials for team ${team_id}."
      echo "The archive version/build is valid; the blocker is local Apple account or distribution signing state."
      echo
      echo "Fix one of these, then run: make export-ios-release"
      echo "- Xcode > Settings > Accounts: remove and re-add the Apple ID for team ${team_id}, then refresh signing certificates/profiles."
      echo "- Or set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH so xcodebuild can authenticate with an App Store Connect API key."
    } >&2
  else
    {
      echo
      echo "error: App Store Connect export failed. See the export log for the full Xcode output:"
      echo "$log_file"
    } >&2
  fi
}

cd "$repo_root"

project_yml="${PROJECT_YML:-project.yml}"
[[ -f "$project_yml" ]] || fail "Missing project.yml at $repo_root/$project_yml"

if [[ "${IOS_EXPORT_SKIP_PREP_CHECK:-0}" != "1" ]]; then
  MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$repo_root" "$script_dir/check-ios-release-prep.sh"
fi

archive_path="${ARCHIVE_PATH:-}"
if [[ -z "$archive_path" ]]; then
  archive_path="$(newest_archive)" || true
fi
[[ -n "$archive_path" ]] || fail "No .xcarchive found. Archive Merian in Xcode first, or pass ARCHIVE_PATH=/path/to/Merian.xcarchive."
archive_path="$(resolve_repo_path "$archive_path")"
[[ -d "$archive_path" ]] || fail "Archive not found: $archive_path"

archive_info="$archive_path/Info.plist"
[[ -f "$archive_info" ]] || fail "Archive is missing Info.plist: $archive_info"

app_path="$(read_plist_value "$archive_info" "ApplicationProperties:ApplicationPath")" || fail "Could not read ApplicationPath from archive Info.plist"
app_info="$archive_path/Products/$app_path/Info.plist"
[[ -f "$app_info" ]] || fail "Archive app is missing Info.plist: $app_info"

project_version="$(extract_project_setting MARKETING_VERSION "$project_yml")" || fail "Could not read MARKETING_VERSION from $project_yml"
project_build="$(extract_project_setting CURRENT_PROJECT_VERSION "$project_yml")" || fail "Could not read CURRENT_PROJECT_VERSION from $project_yml"
archive_version="$(read_plist_value "$app_info" "CFBundleShortVersionString")" || fail "Could not read archive CFBundleShortVersionString"
archive_build="$(read_plist_value "$app_info" "CFBundleVersion")" || fail "Could not read archive CFBundleVersion"

if [[ "$archive_version" != "$project_version" || "$archive_build" != "$project_build" ]]; then
  fail "Archive is Merian ${archive_version} (${archive_build}) but release prep is ${project_version} (${project_build}). Archive again before exporting."
fi

team_id="${TEAM_ID:-${ASC_TEAM_ID:-}}"
if [[ -z "$team_id" ]]; then
  team_id="$(read_plist_value "$archive_info" "ApplicationProperties:Team")" || true
fi
[[ -n "$team_id" ]] || fail "Could not determine Apple team ID from archive. Pass TEAM_ID=..."

export_path="$(resolve_repo_path "${EXPORT_PATH:-build/ios-export}")"
case "$export_path" in
  "/"|"$repo_root")
    fail "Refusing to use unsafe EXPORT_PATH: $export_path"
    ;;
esac

rm -rf "$export_path"
mkdir -p "$export_path"

export_options="${EXPORT_OPTIONS_PLIST:-$export_path/exportOptions.plist}"
write_export_options "$export_options" "$team_id"

cmd=(
  xcodebuild
  -exportArchive
  -archivePath "$archive_path"
  -exportOptionsPlist "$export_options"
  -exportPath "$export_path"
  -allowProvisioningUpdates
)

if have_asc_key_auth; then
  [[ -r "$ASC_PRIVATE_KEY_PATH" ]] || fail "ASC_PRIVATE_KEY_PATH is not readable: $ASC_PRIVATE_KEY_PATH"
  cmd+=(
    -authenticationKeyPath "$ASC_PRIVATE_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
  note "Using App Store Connect API key authentication for export."
else
  note "Using Xcode account signing state for export."
fi

log_file="$export_path/export.log"
note "Exporting Merian ${archive_version} (${archive_build}) from:"
note "$archive_path"
note "Export path:"
note "$export_path"

set +e
"${cmd[@]}" 2>&1 | tee "$log_file"
status=${PIPESTATUS[0]}
set -e

if (( status != 0 )); then
  explain_export_failure "$log_file" "$team_id"
  exit "$status"
fi

ipa_path="$(find "$export_path" -maxdepth 2 -name "*.ipa" -print -quit)"
[[ -n "$ipa_path" && -f "$ipa_path" ]] || fail "Export completed but no .ipa was produced in $export_path"

note "Exported TestFlight-ready IPA:"
note "$ipa_path"

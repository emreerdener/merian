#!/usr/bin/env bash
set -euo pipefail

PROJECT_YML="${PROJECT_YML:-project.yml}"
if [[ -n "${PROJECT_FILE:-}" ]]; then
  resolved_project_file="$PROJECT_FILE"
elif [[ -f "Merian.xcodeproj/project.pbxproj" ]]; then
  resolved_project_file="Merian.xcodeproj/project.pbxproj"
else
  resolved_project_file="merian.xcodeproj/project.pbxproj"
fi
PROJECT_FILE="$resolved_project_file"

fail() {
  echo "error: $*" >&2
  exit 1
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

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_semantic_version() {
  [[ "$1" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]]
}

require_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -q -- "$pattern" "$file"; then
    fail "$message"
  fi
}

[[ -f "$PROJECT_YML" ]] || fail "Missing $PROJECT_YML"
[[ -f "$PROJECT_FILE" ]] || fail "Missing generated project file $PROJECT_FILE. Run make xcodegen."

marketing_version="$(extract_project_setting MARKETING_VERSION "$PROJECT_YML")" || fail "Could not read MARKETING_VERSION from $PROJECT_YML"
build_number="$(extract_project_setting CURRENT_PROJECT_VERSION "$PROJECT_YML")" || fail "Could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"

is_semantic_version "$marketing_version" || fail "MARKETING_VERSION must be semantic x.y.z with a positive major version, got: $marketing_version"
is_positive_int "$build_number" || fail "CURRENT_PROJECT_VERSION must be a positive integer, got: $build_number"

require_grep "MARKETING_VERSION = ${marketing_version};" "$PROJECT_FILE" "Generated project is not synced with MARKETING_VERSION=${marketing_version}. Run make xcodegen."
require_grep "CURRENT_PROJECT_VERSION = ${build_number};" "$PROJECT_FILE" "Generated project is not synced with CURRENT_PROJECT_VERSION=${build_number}. Run make xcodegen."
require_grep 'VERSIONING_SYSTEM = "apple-generic";' "$PROJECT_FILE" "Generated project must keep VERSIONING_SYSTEM=apple-generic."
require_grep 'scripts/check-ios-release-prep.sh' "$PROJECT_FILE" "Generated project is missing the release versioning preflight script."

for plist in \
  apps/ios/Merian/Configuration/Info.plist \
  apps/ios/widgets/Explore/Configuration/Info.plist \
  apps/ios/messages/MerianMessagesExtension/Configuration/Info.plist
do
  [[ -f "$plist" ]] || fail "Missing Info.plist: $plist"
  require_grep '<string>$(MARKETING_VERSION)</string>' "$plist" "$plist must inherit CFBundleShortVersionString from MARKETING_VERSION."
  require_grep '<string>$(CURRENT_PROJECT_VERSION)</string>' "$plist" "$plist must inherit CFBundleVersion from CURRENT_PROJECT_VERSION."
done

require_grep 'INFOPLIST_KEY_CFBundleShortVersionString = "$(MARKETING_VERSION)";' "$PROJECT_FILE" "Watch target must inherit generated CFBundleShortVersionString from MARKETING_VERSION."
require_grep 'INFOPLIST_KEY_CFBundleVersion = "$(CURRENT_PROJECT_VERSION)";' "$PROJECT_FILE" "Watch target must inherit generated CFBundleVersion from CURRENT_PROJECT_VERSION."

lowercase_project_refs="$(grep -REIn -- '-project[[:space:]]+merian[.]xcodeproj' Makefile scripts .github 2>/dev/null || true)"
if [[ -n "$lowercase_project_refs" ]]; then
  echo "$lowercase_project_refs" >&2
  fail "Automation must resolve the Xcode project path instead of hardcoding lowercase merian.xcodeproj."
fi

echo "iOS versioning guardrails passed for Merian ${marketing_version} (${build_number})."

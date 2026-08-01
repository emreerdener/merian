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
    $1 == key ":" { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$file"
}

require_literal() {
  local literal="$1"
  local file="$2"
  local message="$3"
  grep -Fq -- "$literal" "$file" || fail "$message"
}

[[ -f "$PROJECT_YML" ]] || fail "Missing $PROJECT_YML"
[[ -f "$PROJECT_FILE" ]] \
  || fail "Missing generated project file $PROJECT_FILE. Run make xcodegen."

marketing_version="$(extract_project_setting MARKETING_VERSION "$PROJECT_YML")" \
  || fail "Could not read MARKETING_VERSION from $PROJECT_YML"
build_baseline="$(extract_project_setting CURRENT_PROJECT_VERSION "$PROJECT_YML")" \
  || fail "Could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"

[[ "$marketing_version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] \
  || fail "MARKETING_VERSION must be semantic x.y.z, got: $marketing_version"
[[ "$build_baseline" =~ ^[1-9][0-9]*$ ]] \
  || fail "CURRENT_PROJECT_VERSION must be a positive integer, got: $build_baseline"

require_literal "MARKETING_VERSION = ${marketing_version};" "$PROJECT_FILE" \
  "Generated project is not synced with MARKETING_VERSION=${marketing_version}. Run make xcodegen."
require_literal "CURRENT_PROJECT_VERSION = ${build_baseline};" "$PROJECT_FILE" \
  "Generated project is not synced with CURRENT_PROJECT_VERSION=${build_baseline}. Run make xcodegen."
require_literal 'VERSIONING_SYSTEM = "apple-generic";' "$PROJECT_FILE" \
  "Generated project must keep VERSIONING_SYSTEM=apple-generic."
require_literal 'scripts/check-ios-release-prep.sh' "$PROJECT_FILE" \
  "Generated project is missing the Release archive preflight."
require_literal 'CODE_SIGN_STYLE: Automatic' "$PROJECT_YML" \
  "project.yml must use automatic signing."

for plist in \
  apps/ios/Merian/Configuration/Info.plist \
  apps/ios/widgets/Explore/Configuration/Info.plist \
  apps/ios/messages/MerianMessagesExtension/Configuration/Info.plist
do
  [[ -f "$plist" ]] || fail "Missing Info.plist: $plist"
  require_literal '<string>$(MARKETING_VERSION)</string>' "$plist" \
    "$plist must inherit CFBundleShortVersionString from MARKETING_VERSION."
  require_literal '<string>$(CURRENT_PROJECT_VERSION)</string>' "$plist" \
    "$plist must inherit CFBundleVersion from CURRENT_PROJECT_VERSION."
done

require_literal 'INFOPLIST_KEY_CFBundleShortVersionString = "$(MARKETING_VERSION)";' "$PROJECT_FILE" \
  "Watch target must inherit CFBundleShortVersionString from MARKETING_VERSION."
require_literal 'INFOPLIST_KEY_CFBundleVersion = "$(CURRENT_PROJECT_VERSION)";' "$PROJECT_FILE" \
  "Watch target must inherit CFBundleVersion from CURRENT_PROJECT_VERSION."

preflight_script="scripts/check-ios-release-prep.sh"
validation_workflow=".github/workflows/ios-build-and-test.yml"
xcode_contract_test="scripts/test-ios-xcode-release-workflow.sh"
for release_file in "$preflight_script" "$validation_workflow" "$xcode_contract_test"; do
  [[ -f "$release_file" ]] || fail "Missing Xcode release guardrail: $release_file"
done

for retired_file in \
  .github/workflows/ios-testflight-beta.yml \
  .github/workflows/ios-testflight-publisher.yml \
  scripts/publish-ios-beta.sh \
  scripts/export-ios-release.sh \
  scripts/prepare-ios-release.sh \
  scripts/test-ios-publisher-workflow.sh
do
  [[ ! -e "$retired_file" ]] \
    || fail "Retired GitHub distribution path must remain absent: $retired_file"
done

require_literal 'MERIAN_IOS_VALIDATION_ARCHIVE=1' "$validation_workflow" \
  "CI Release archives must explicitly remain validation-only."
require_literal 'CODE_SIGNING_ALLOWED=NO' "$validation_workflow" \
  "CI Release archives must remain unsigned."
require_literal 'CODE_SIGN_STYLE must remain Automatic for Organizer distribution' "$preflight_script" \
  "Release preflight must require Organizer automatic signing."
require_literal 'keep Manage version and build number enabled' "$preflight_script" \
  "Release preflight must direct Xcode to manage uploaded build numbers."
require_literal 'source checkout is dirty' "$preflight_script" \
  "Release preflight must reject dirty Organizer archives."

if grep -REq --include='*.yml' --include='*.yaml' \
  '(iTMSTransporter|notarytool|altool|IOS_DISTRIBUTION_CERTIFICATE|ASC_PRIVATE_KEY)' \
  .github/workflows; then
  fail "GitHub Actions must not contain an Apple signing or upload path."
fi

if grep -REq \
  'CODE_SIGN_IDENTITY[[:space:]]*[:=][[:space:]]*"?(Apple|iPhone) Distribution' \
  project.yml ./*.xcconfig "$PROJECT_FILE" 2>/dev/null; then
  fail "Automatic signing must not be combined with a forced distribution identity."
fi

lowercase_project_refs="$(grep -REIn -- '-project[[:space:]]+merian[.]xcodeproj' Makefile scripts .github 2>/dev/null || true)"
if [[ -n "$lowercase_project_refs" ]]; then
  echo "$lowercase_project_refs" >&2
  fail "Automation must resolve the project path instead of hardcoding lowercase merian.xcodeproj."
fi

echo "iOS versioning guardrails passed for Xcode Organizer baseline ${marketing_version} (${build_baseline})."

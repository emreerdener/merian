#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ios-testflight-publisher.yml"
publisher="$repo_root/scripts/publish-ios-beta.sh"
exporter="$repo_root/scripts/export-ios-release.sh"
preflight="$repo_root/scripts/check-ios-release-prep.sh"
validation_workflow="$repo_root/.github/workflows/ios-build-and-test.yml"
retired_prep="$repo_root/scripts/prepare-ios-release.sh"
release_guide="$repo_root/docs/development-guides/14-ios-release-versioning.md"
publisher_architecture="$repo_root/docs/system-architecture/09-ios-release-publisher.md"
agent_workflow="$repo_root/apps/ios/.agents/workflows/deploy_testflight.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local pattern="$1"
  local file="$2"
  grep -Fq -- "$pattern" "$file" || fail "$file is missing: $pattern"
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual
  actual="$(grep -Fc -- "$pattern" "$file" || true)"
  [[ "$actual" == "$expected" ]] \
    || fail "$file expected $expected occurrences of '$pattern', found $actual"
}

for required_file in "$workflow" "$publisher" "$exporter" "$preflight" "$validation_workflow" "$retired_prep" "$release_guide" "$publisher_architecture" "$agent_workflow"; do
  [[ -f "$required_file" ]] || fail "missing required release artifact: $required_file"
done

# The release publisher is deliberately manual and globally serialized.
assert_contains "workflow_dispatch:" "$workflow"
if grep -Eq '^[[:space:]]+(push|pull_request|merge_group|schedule):' "$workflow"; then
  fail "publisher workflow must not have an automatic trigger"
fi
assert_contains "group: ios-testflight-publisher" "$workflow"
assert_contains "cancel-in-progress: false" "$workflow"
assert_contains 'build/.ios-publisher.lock' "$publisher"
assert_contains "another local publisher holds" "$publisher"
assert_contains "contents: write" "$workflow"
assert_contains "persist-credentials: false" "$workflow"
assert_contains "runs-on: macos-26" "$workflow"
assert_contains "/Applications/Xcode_26.6.app/Contents/Developer" "$workflow"
assert_contains 'GITHUB_REF" != "refs/heads/main' "$workflow"
assert_contains "Publisher checkout, selected main, and workflow SHA must be identical" "$workflow"

# External state and uploads require unmistakable, independent confirmations.
assert_contains "RESERVE BUILD" "$workflow"
assert_contains "UPLOAD TO APP STORE CONNECT" "$workflow"
assert_contains "FAILED CONFIRMED" "$workflow"
assert_contains "--confirm-external-state" "$workflow"
assert_contains "--confirm-upload" "$workflow"
assert_contains "--confirm-failed-upload" "$workflow"

# A new distributable archive is allowed only after exact-SHA CI proof.
assert_contains 'ios-build-and-test.yml/runs?head_sha=$GITHUB_SHA&status=success' "$workflow"
assert_contains '"Full iOS unit tests"' "$workflow"
assert_contains '"Current-SHA Release archive"' "$workflow"
assert_contains '"Production readiness"' "$workflow"
assert_contains 'MERIAN_GREEN_SHA="$GITHUB_SHA"' "$workflow"
assert_contains 'MERIAN_GREEN_RUN_ID="$GREEN_RUN_ID"' "$workflow"
assert_contains 'the green iOS gate SHA must equal the exact publisher source SHA' "$publisher"

# There is one archive call site in the sole build-number writer. Validation
# archives explicitly use the tracked baseline and do not enter publisher mode.
assert_count 1 '"$xcodebuild_command" archive' "$publisher"
assert_contains "MERIAN_IOS_VALIDATION_ARCHIVE=1" "$validation_workflow"
assert_contains "CODE_SIGNING_ALLOWED=NO" "$validation_workflow"
assert_contains "CODE_SIGNING_REQUIRED=NO" "$validation_workflow"
assert_contains "no build number was allocated" "$preflight"
assert_contains "validation archive mode is restricted to unsigned archives" "$preflight"
assert_contains "validation archive changed or allocated CURRENT_PROJECT_VERSION" "$preflight"

# Allocation is monotonic across App Store Connect, the tracked baseline, and
# durable reservation tags. Reservation happens before the sole archive.
assert_contains "max(app_store_connect_latest, repository_baseline) + 1" "$publisher"
assert_contains "ios-build-allocations/" "$publisher"
assert_contains "ls-remote --refs origin 'refs/tags/ios-build-allocations/*'" "$publisher"
assert_contains "reserve_build" "$publisher"
assert_contains 'push --porcelain origin' "$publisher"
assert_contains "grep -Eq '^\\*[[:space:]]'" "$publisher"
assert_contains "was not newly created remotely; no archive was started" "$publisher"
assert_contains 'note "Archiving ${version}' "$publisher"
reserve_line="$(grep -n '^reserve_build$' "$publisher" | cut -d: -f1)"
archive_line="$(grep -n 'note "Archiving ' "$publisher" | cut -d: -f1)"
[[ "$reserve_line" =~ ^[0-9]+$ && "$archive_line" =~ ^[0-9]+$ && "$reserve_line" -lt "$archive_line" ]] \
  || fail "build reservation must precede archive"

# Export must preserve the allocated identity and validate both archive and IPA.
assert_contains "manageAppVersionAndBuildNumber" "$exporter"
assert_contains "  <false/>" "$exporter"
assert_contains 'document["stage"] == "build_reserved"' "$exporter"
assert_contains 'document.dig("publisher", "serialized") == true' "$exporter"
assert_contains 'document.dig("publisher", "external_state_authorized") == true' "$exporter"
assert_contains 'document["live_preconditions_met"] == true' "$exporter"
assert_contains "validate-ios-archive.sh" "$exporter"
assert_contains "validate-ios-exported-ipa.sh" "$exporter"
assert_contains "archive changed while being exported" "$exporter"
assert_contains "archive_identity" "$publisher"
assert_contains "ipa_sha256" "$publisher"
assert_contains "archive_invocations" "$publisher"
assert_contains "ios-builds/" "$publisher"
assert_contains "ios-uploads/" "$publisher"

# Retry and promotion semantics never archive or export again.
assert_contains "--upload-existing" "$publisher"
assert_contains "--retry-upload" "$publisher"
assert_contains "retry requires --confirm-failed-upload" "$publisher"
assert_contains "IPA hash does not match immutable evidence" "$publisher"
assert_contains '${{ runner.temp }}/existing-candidate/**/*.ipa' "$workflow"
assert_contains "same_uploaded_binary_only" "$publisher"
assert_contains "internal TestFlight, external TestFlight, and App Review" "$publisher"

# API credentials are materialized only in the trusted publisher step and are
# removed by a trap. Legacy prep is a hard failure and cannot edit project.yml.
assert_contains 'ASC_PRIVATE_KEY_P8_BASE64: ${{ secrets.ASC_PRIVATE_KEY_P8_BASE64 }}' "$workflow"
assert_contains 'trap cleanup EXIT' "$workflow"
assert_contains "trap 'exit 130' HUP INT TERM" "$workflow"
assert_contains "unset ASC_PRIVATE_KEY_P8_BASE64" "$workflow"
assert_contains "unset IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64 IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" "$workflow"
assert_contains '-H "@${header_file}"' "$publisher"
assert_contains 'PUBLISHER_GITHUB_TOKEN: ${{ github.token }}' "$workflow"
assert_contains "unset PUBLISHER_GITHUB_TOKEN" "$publisher"
assert_contains "git_with_publisher_auth" "$publisher"
assert_contains "GIT_CONFIG_VALUE_0=\"AUTHORIZATION: basic" "$publisher"
if grep -Fq -- '-c "http.https://github.com/.extraheader=AUTHORIZATION:' "$publisher"; then
  fail "publisher Git authorization must not be placed on a process command line"
fi
assert_contains 'rm -f "$private_key_path" "$certificate_path"' "$workflow"
assert_contains "prepare-ios-release is retired" "$retired_prep"
if grep -Eq '(agvtool[[:space:]]+(new-version|next-version)|write_project_versions|ios-release-prep[.]json)' "$publisher" "$exporter" "$preflight" "$retired_prep"; then
  fail "active publisher path contains a competing build-number writer or stale marker flow"
fi

# The canonical operator guide is itself a guarded release artifact. It must
# keep one entry point, the current train, immutable retry chaining, and no
# actionable legacy command.
assert_contains "one supported path for a distributable iOS build" "$release_guide"
assert_contains "## One-Time Repository and Apple Setup" "$release_guide"
assert_contains "## Routine Candidate Procedure" "$release_guide"
assert_contains "## Archive, Export, and Evidence" "$release_guide"
assert_contains "## Retry Decision Procedure" "$release_guide"
assert_contains "## TestFlight and App Review Promotion" "$release_guide"
assert_contains "## Emergency Stop and Recovery" "$release_guide"
tracked_marketing_version="$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' "$repo_root/project.yml")"
[[ "$tracked_marketing_version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] \
  || fail "project.yml has no valid tracked marketing version"
assert_contains "MARKETING_VERSION: $tracked_marketing_version" "$release_guide"
[[ -f "$repo_root/apps/ios/AppStore/ReleaseNotes/${tracked_marketing_version}.md" ]] \
  || fail "tracked marketing train has no reviewed App Store release-note source"
assert_contains "use that run and artifact as the" "$release_guide"
assert_contains "source for any authorized retry" "$release_guide"
if grep -Eq '(make prepare-ios-release|make export-ios-release|VERSION=1[.]0[.]2)' "$release_guide"; then
  fail "canonical operator guide contains an actionable retired release procedure"
fi

# Architecture explains writer authority and state; the agent workflow remains
# only a pointer to the canonical runbook and cannot restore a competing path.
assert_contains "sole writer of distributable iOS build numbers" "$publisher_architecture"
assert_contains "## Authority and Trust Boundaries" "$publisher_architecture"
assert_contains "## State Model" "$publisher_architecture"
assert_contains "## Non-Negotiable Invariants" "$publisher_architecture"
assert_contains "ios-build-allocations/<build>" "$publisher_architecture"
assert_contains "This file is an agent entry point, not a second deployment procedure" "$agent_workflow"
assert_contains "../../../../docs/development-guides/14-ios-release-versioning.md" "$agent_workflow"
assert_contains "iOS TestFlight Publisher" "$agent_workflow"
if grep -Eiq '^[[:space:]]*(\$[[:space:]]*)?(fastlane[[:space:]]+(beta|spaceauth)|make[[:space:]]+prepare-ios-release|make[[:space:]]+export-ios-release|agvtool[[:space:]]+(new-version|next-version))([[:space:]]|$)' "$agent_workflow"; then
  fail "agent workflow contains an actionable competing release procedure"
fi

echo "iOS publisher workflow invariants passed."

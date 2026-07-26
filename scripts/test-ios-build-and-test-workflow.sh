#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ios-build-and-test.yml"
startup_workflow="$repo_root/.github/workflows/ios-startup-safety.yml"
source_membership_check="$repo_root/scripts/check-ios-project-source-membership.sh"
source_membership_test="$repo_root/scripts/test-ios-project-source-membership.sh"
critical_results_check="$repo_root/scripts/validate-ios-critical-test-results.sh"

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$workflow" \
    || fail "iOS build workflow is missing: $expected"
}

assert_file_contains() {
  local checked_file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$checked_file" \
    || fail "$checked_file is missing: $expected"
}

assert_count() {
  local expected_count="$1"
  local text="$2"
  local actual_count
  actual_count="$(grep -Fc -- "$text" "$workflow" || true)"
  [[ "$actual_count" == "$expected_count" ]] \
    || fail "Expected $expected_count occurrence(s) of '$text'; found $actual_count."
}

assert_no_runner_context_in_job_env() {
  local checked_workflow="$1"
  if ! awk '
    /^    env:[[:space:]]*$/ {
      in_job_env = 1
      next
    }
    in_job_env && /^    [^[:space:]#]/ {
      in_job_env = 0
    }
    in_job_env && /\$\{\{[[:space:]]*runner\./ {
      exit 1
    }
  ' "$checked_workflow"; then
    fail "runner context is unavailable in jobs.<job_id>.env: $checked_workflow"
  fi
}

[[ -f "$workflow" ]] || fail "Missing iOS build workflow: $workflow"
[[ -f "$startup_workflow" ]] || fail "Missing startup workflow: $startup_workflow"
[[ -f "$source_membership_check" ]] \
  || fail "Missing generated-project source membership check: $source_membership_check"
[[ -f "$source_membership_test" ]] \
  || fail "Missing generated-project source membership test: $source_membership_test"
[[ -f "$critical_results_check" ]] \
  || fail "Missing critical iOS test-result validator: $critical_results_check"

assert_contains "  pull_request:"
assert_contains "  merge_group:"
assert_contains "macos-26"
assert_contains "/Applications/Xcode_26.6.app/Contents/Developer"
assert_contains "bash scripts/ci-detect-ios-build-source-changes.sh"
assert_count 1 "bash scripts/check-ios-project-source-membership.sh"
assert_count 1 "bash scripts/test-ios-project-source-membership.sh"
assert_contains "fetch-depth: 0"
assert_count 3 "persist-credentials: false"
# Lock the reviewed Node.js 24 action releases as well as requiring immutable
# refs below. This prevents a valid old SHA from restoring a deprecated runtime.
assert_count 3 "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2"
assert_count 2 "actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0"
assert_count 1 "actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0"
assert_count 5 "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1"
assert_contains "actual_sha=\"\$(git rev-parse HEAD)\""
assert_contains 'actual_sha" != "$GITHUB_SHA'
assert_contains "Compile app and shared test targets"
assert_contains "xcodebuild build-for-testing"
assert_contains "xcodebuild test-without-building"
assert_contains "xcresulttool get test-results tests"
assert_contains "xcodebuild archive"
assert_contains '-configuration Release'
assert_contains '-destination "generic/platform=iOS"'
assert_contains "-onlyUsePackageVersionsFromResolvedFile"
assert_contains "-disableAutomaticPackageResolution"
assert_contains "A non-empty checked-in Package.resolved is required."
assert_contains "Package resolution modified the checked-in lockfile."
assert_contains 'echo "SWIFT_PACKAGE_CACHE=$RUNNER_TEMP/ios-unit-package-cache"'
assert_contains 'echo "XCODE_ARCHIVE=$RUNNER_TEMP/Merian.xcarchive"'
assert_contains "CODE_SIGNING_ALLOWED=NO"
assert_contains "MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY"
assert_contains "bash scripts/validate-ios-critical-test-results.sh"
assert_contains "dwarfdump --uuid"
assert_contains 'main_dsym_binary="$main_dsym/Contents/Resources/DWARF/Merian"'
assert_contains 'if [ ! -s "$app_uuids" ] || [ ! -s "$dsym_uuids" ]'
assert_contains "dsym_uuid_match: true"
assert_contains "production-readiness:"
assert_contains "if: always()"
assert_contains 'UNIT_TEST_RESULT" != "success'
assert_contains 'RELEASE_ARCHIVE_RESULT" != "success'

if grep -Eq '^[[:space:]]+paths(-ignore)?:' "$workflow"; then
  fail "The required workflow must use in-workflow scope, not event path filters."
fi

# Building and running the whole unit-test target is deliberate. A selector
# below the target level can silently remove Camera, inference, or offline-sync
# coverage while leaving xcodebuild green.
assert_count 2 "-only-testing:merianTests"
assert_count 1 "-only-testing:merianUITests"
if grep -Fq -- "-only-testing:merianTests/" "$workflow"; then
  fail "The production gate must not narrow merianTests to selected suites."
fi
if grep -Fq -- "-skip-testing:merianTests" "$workflow"; then
  fail "The production gate must not skip any merianTests suite."
fi
if grep -Fq -- "-only-testing:merianUITests/" "$workflow" \
  || grep -Fq -- "-skip-testing:merianUITests" "$workflow"; then
  fail "The compile gate must include the complete merianUITests target."
fi

# Every third-party action must use an immutable 40-character commit SHA.
while IFS= read -r action_spec; do
  if [[ "$action_spec" == ./* ]]; then
    continue
  fi
  if [[ "$action_spec" != *@* ]]; then
    fail "Third-party action has no immutable ref: $action_spec"
  fi
  action_ref="${action_spec##*@}"
  if ! [[ "$action_ref" =~ ^[0-9a-f]{40}$ ]]; then
    fail "Third-party action is not commit-pinned: $action_spec"
  fi
done < <(
  sed -nE 's/^[[:space:]]+uses:[[:space:]]+([^[:space:]#]+).*/\1/p' "$workflow"
)

if grep -Fq "macos-latest" "$workflow"; then
  fail "The production gate must use its reviewed macOS/Xcode baseline."
fi
if grep -Fq "restore-keys:" "$workflow"; then
  fail "Package caches must match the exact Xcode and Package.resolved hash."
fi
assert_no_runner_context_in_job_env "$workflow"
bash -n "$source_membership_check"
bash -n "$source_membership_test"
bash -n "$critical_results_check"
assert_file_contains "$critical_results_check" '.result == "Passed"'
assert_file_contains "$critical_results_check" "CameraManagerTests"
assert_file_contains "$critical_results_check" "InferenceEngineTests"
assert_file_contains "$critical_results_check" "OfflineQueueManagerTests"
assert_file_contains "$critical_results_check" "SyncStateManagerTests"

for startup_requirement in \
  "runs-on: macos-26" \
  "/Applications/Xcode_26.6.app/Contents/Developer" \
  "-onlyUsePackageVersionsFromResolvedFile" \
  "-disableAutomaticPackageResolution"; do
  grep -Fq -- "$startup_requirement" "$startup_workflow" \
    || fail "Startup Safety is missing its shared toolchain invariant: $startup_requirement"
done
if grep -Fq "macos-latest" "$startup_workflow"; then
  fail "Startup Safety must use the same reviewed macOS/Xcode baseline."
fi
assert_no_runner_context_in_job_env "$startup_workflow"

echo "iOS build-and-test workflow contract passed."

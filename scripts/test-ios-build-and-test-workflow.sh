#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ios-build-and-test.yml"
project_guardrails_workflow="$repo_root/.github/workflows/ios-project-guardrails.yml"
startup_workflow="$repo_root/.github/workflows/ios-startup-safety.yml"
source_membership_check="$repo_root/scripts/check-ios-project-source-membership.sh"
source_membership_test="$repo_root/scripts/test-ios-project-source-membership.sh"
event_routing_check="$repo_root/scripts/check-ios-event-routing.sh"
event_routing_test="$repo_root/scripts/test-check-ios-event-routing.sh"
critical_results_check="$repo_root/scripts/validate-ios-critical-test-results.sh"
focused_results_check="$repo_root/scripts/validate-ios-focused-test-results.sh"
failure_diagnostics_extractor="$repo_root/scripts/extract-ios-test-failure-diagnostics.sh"
ui_test_source="$repo_root/apps/ios/MerianUITests/merianUITests.swift"
ui_seed_source="$repo_root/apps/ios/Merian/App/MerianApp.swift"
scanning_experience_source="$repo_root/apps/ios/Merian/Features/Insights/Content/Views/AnalyzingContentView.swift"
confidence_badge_source="$repo_root/apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Views/ConfidenceBadge.swift"
queued_content_source="$repo_root/apps/ios/Merian/Features/Insights/Content/Views/QueuedContentView.swift"
insight_sheet_source="$repo_root/apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView.swift"
insight_records_source="$repo_root/apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Records.swift"
insight_display_source="$repo_root/apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Display.swift"
audio_page_source="$repo_root/apps/ios/Merian/Features/Insights/Media/Carousel/Pages/AudioPlaybackCarouselPage.swift"
field_chat_toolbar_source="$repo_root/apps/ios/Merian/Features/Insights/Toolbars/BottomToolbar/InsightBottomToolbar.swift"
insight_share_button_source="$repo_root/apps/ios/Merian/Features/Insights/Sharing/Components/InsightShareButton.swift"
scans_sheet_source="$repo_root/apps/ios/Merian/Features/Scans/Shell/Views/ScansSheetView.swift"
scans_grid_source="$repo_root/apps/ios/Merian/Features/Scans/Shared/Components/ScansGrid.swift"
queued_context_source="$repo_root/apps/ios/Merian/Models/QueuedScanContext.swift"
queue_durability_source="$repo_root/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueDurability.swift"
queue_manager_source="$repo_root/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift"
queue_source="$repo_root/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Queue.swift"
queue_sync_source="$repo_root/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Sync.swift"
queue_url_session_source="$repo_root/apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+URLSession.swift"
background_database_actor_source="$repo_root/apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift"
network_client_test_source="$repo_root/apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift"
ios_test_sources="$repo_root/apps/ios/MerianTests"

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

assert_file_count() {
  local checked_file="$1"
  local expected_count="$2"
  local text="$3"
  local actual_count
  actual_count="$(grep -Fc -- "$text" "$checked_file" || true)"
  [[ "$actual_count" == "$expected_count" ]] \
    || fail \
      "Expected $expected_count occurrence(s) of '$text' in $checked_file; found $actual_count."
}

assert_count() {
  local expected_count="$1"
  local text="$2"
  local actual_count
  actual_count="$(grep -Fc -- "$text" "$workflow" || true)"
  [[ "$actual_count" == "$expected_count" ]] \
    || fail "Expected $expected_count occurrence(s) of '$text'; found $actual_count."
}

assert_before() {
  local first="$1"
  local second="$2"
  local first_line
  local second_line

  first_line="$(
    grep -Fn -- "$first" "$workflow" | head -n 1 | cut -d: -f1 || true
  )"
  second_line="$(
    grep -Fn -- "$second" "$workflow" | head -n 1 | cut -d: -f1 || true
  )"
  [[ -n "$first_line" && -n "$second_line" ]] \
    || fail "Cannot verify workflow ordering for '$first' before '$second'."
  (( first_line < second_line )) \
    || fail "Workflow must place '$first' before '$second'."
}

assert_file_before() {
  local checked_file="$1"
  local first="$2"
  local second="$3"
  local first_line
  local second_line

  first_line="$(
    grep -Fn -- "$first" "$checked_file" | head -n 1 | cut -d: -f1 || true
  )"
  second_line="$(
    grep -Fn -- "$second" "$checked_file" | head -n 1 | cut -d: -f1 || true
  )"
  [[ -n "$first_line" && -n "$second_line" ]] \
    || fail "Cannot verify ordering in $checked_file for '$first' before '$second'."
  (( first_line < second_line )) \
    || fail "$checked_file must place '$first' before '$second'."
}

assert_action_release() {
  local action_path="$1"
  local expected_count="$2"
  local required_major="$3"
  local actual_count
  local pinned_count
  local reviewed_version_count
  local release_count

  read -r \
    actual_count \
    pinned_count \
    reviewed_version_count \
    release_count < <(
    awk \
      -v action_path="$action_path" \
      -v required_major="$required_major" '
        $1 == "uses:" {
          prefix = action_path "@"
          if (index($2, prefix) != 1) {
            next
          }

          actual_count += 1
          ref = substr($2, length(prefix) + 1)
          version = $4
          valid_ref = ref ~ /^[0-9a-f]{40}$/
          version_pattern = "^v" required_major "\\.[0-9]+\\.[0-9]+$"
          valid_version = version ~ version_pattern
          if (valid_ref) {
            pinned_count += 1
          }
          if ($3 == "#" && valid_version) {
            reviewed_version_count += 1
          }
          releases[$2 " " version] = 1
        }
        END {
          for (release in releases) {
            release_count += 1
          }
          printf "%d %d %d %d\n",
            actual_count,
            pinned_count,
            reviewed_version_count,
            release_count
        }
      ' "$workflow"
  )

  [[ "$actual_count" == "$expected_count" ]] \
    || fail \
      "Expected $expected_count occurrence(s) of '$action_path'; found $actual_count."
  [[ "$pinned_count" == "$expected_count" ]] \
    || fail \
      "Every '$action_path' use must pin a full 40-character lowercase commit SHA."
  [[ "$reviewed_version_count" == "$expected_count" ]] \
    || fail \
      "Every '$action_path' use must declare the reviewed v$required_major.x.y release comment; action-major upgrades require an explicit contract review."
  [[ "$release_count" == "1" ]] \
    || fail "Every '$action_path' use must share one reviewed release."
}

assert_actions_share_release() {
  local first_action="$1"
  local second_action="$2"
  local first_release
  local second_release

  first_release="$(
    awk -v action_path="$first_action" '
      $1 == "uses:" && index($2, action_path "@") == 1 {
        print substr($2, length(action_path) + 2), $4
      }
    ' "$workflow" | sort -u
  )"
  second_release="$(
    awk -v action_path="$second_action" '
      $1 == "uses:" && index($2, action_path "@") == 1 {
        print substr($2, length(action_path) + 2), $4
      }
    ' "$workflow" | sort -u
  )"

  [[ -n "$first_release" && "$first_release" == "$second_release" ]] \
    || fail "'$first_action' and '$second_action' must share one release."
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
[[ -f "$project_guardrails_workflow" ]] \
  || fail "Missing iOS project guardrails workflow: $project_guardrails_workflow"
[[ -f "$startup_workflow" ]] || fail "Missing startup workflow: $startup_workflow"
[[ -f "$source_membership_check" ]] \
  || fail "Missing generated-project source membership check: $source_membership_check"
[[ -f "$source_membership_test" ]] \
  || fail "Missing generated-project source membership test: $source_membership_test"
[[ -f "$event_routing_check" ]] \
  || fail "Missing event-routing source guardrail: $event_routing_check"
[[ -f "$event_routing_test" ]] \
  || fail "Missing event-routing guardrail tests: $event_routing_test"
[[ -f "$critical_results_check" ]] \
  || fail "Missing critical iOS test-result validator: $critical_results_check"
[[ -f "$focused_results_check" ]] \
  || fail "Missing focused iOS test-result validator: $focused_results_check"
[[ -f "$failure_diagnostics_extractor" ]] \
  || fail "Missing iOS failure-diagnostics extractor: $failure_diagnostics_extractor"
[[ -f "$ui_test_source" ]] || fail "Missing iOS UI-test source: $ui_test_source"
[[ -f "$ui_seed_source" ]] || fail "Missing iOS UI seed source: $ui_seed_source"
[[ -f "$audio_page_source" ]] || fail "Missing Insight audio page: $audio_page_source"
[[ -f "$field_chat_toolbar_source" ]] \
  || fail "Missing Field Chat toolbar source: $field_chat_toolbar_source"
[[ -f "$insight_share_button_source" ]] \
  || fail "Missing Insight share-button source: $insight_share_button_source"
[[ -f "$scans_sheet_source" ]] || fail "Missing Scans sheet source: $scans_sheet_source"
[[ -f "$scans_grid_source" ]] || fail "Missing Scans grid source: $scans_grid_source"
[[ -d "$ios_test_sources" ]] || fail "Missing iOS unit-test sources: $ios_test_sources"

assert_contains "  pull_request:"
assert_contains "  merge_group:"
assert_contains "    name: Full iOS unit tests"
assert_contains 'group: ios-build-and-test-${{ github.event.pull_request.number || github.run_id }}'
assert_contains "macos-26"
assert_contains "/Applications/Xcode_26.6.app/Contents/Developer"
assert_contains "bash scripts/ci-detect-ios-build-source-changes.sh"
assert_count 1 "make validate-ios-event-routing"
assert_file_count \
  "$project_guardrails_workflow" \
  1 \
  "run: make validate-ios-event-routing"
assert_file_count \
  "$project_guardrails_workflow" \
  2 \
  '"scripts/check-ios-event-routing.sh"'
assert_file_count \
  "$project_guardrails_workflow" \
  2 \
  '"scripts/test-check-ios-event-routing.sh"'
assert_file_count \
  "$project_guardrails_workflow" \
  2 \
  '"scripts/config/ios-event-routing-singleton-allowlist.txt"'
assert_file_before \
  "$project_guardrails_workflow" \
  "run: make validate-ios-event-routing" \
  "run: make test-ios-ci-tooling"
assert_count 1 "bash scripts/check-ios-project-source-membership.sh"
assert_count 1 "bash scripts/test-ios-project-source-membership.sh"
assert_contains "fetch-depth: 0"
assert_count 3 "persist-credentials: false"
# Lock the reviewed Node.js 24 action major releases while allowing Dependabot
# to advance commit-pinned patch/minor releases. Major upgrades remain an
# explicit review boundary.
assert_action_release "actions/checkout" 3 7
assert_action_release "actions/cache/restore" 2 6
assert_action_release "actions/cache/save" 1 6
assert_action_release "actions/upload-artifact" 5 7
assert_actions_share_release "actions/cache/restore" "actions/cache/save"
assert_contains "actual_sha=\"\$(git rev-parse HEAD)\""
assert_contains 'actual_sha" != "$GITHUB_SHA'
assert_contains "bash scripts/ios-release-source-fingerprint.sh"
assert_contains '[[ "$expected_source_fingerprint" =~ ^[0-9a-f]{64}$ ]]'
assert_contains "MERIAN_IOS_VALIDATION_ARCHIVE=1"
assert_contains "source_fingerprint: \$source_fingerprint"
assert_contains 'MERIAN_EXPECTED_SOURCE_REVISION="$GITHUB_SHA"'
assert_contains "Print :MERIAN_SOURCE_REVISION"
assert_contains "Print :MERIAN_SOURCE_FINGERPRINT"
assert_contains "Print :MERIAN_SOURCE_STATE"
assert_contains 'archive_source_revision" != "$GITHUB_SHA'
assert_contains 'archive_source_state" != "clean'
assert_contains 'source_state: "clean"'
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
assert_contains "bash scripts/validate-ios-focused-test-results.sh"
assert_contains 'Critical scan-flow regressions: \`passed\`'
assert_contains 'Exact queued-scan UX regression: \`passed\`'
assert_contains "-only-testing:merianUITests/merianUITests/testQueuedAudioScanRetainsAudioAcrossCompletionHandoff"
assert_contains 'echo "XCODE_UI_RESULT_BUNDLE=$RUNNER_TEMP/ios-critical-scan-ui.xcresult"'
assert_contains '${{ runner.temp }}/ios-critical-scan-ui.xcresult'
assert_contains "bash scripts/extract-ios-test-failure-diagnostics.sh"
assert_contains "dwarfdump --uuid"
assert_contains 'main_dsym_binary="$main_dsym/Contents/Resources/DWARF/Merian"'
assert_contains 'if [ ! -s "$app_uuids" ] || [ ! -s "$dsym_uuids" ]'
assert_contains "dsym_uuid_match: true"
assert_contains 'privacy_manifest="$app_path/PrivacyInfo.xcprivacy"'
assert_contains 'bash scripts/validate-ios-privacy-manifest.sh "$privacy_manifest"'
assert_contains "privacy_manifest_valid: true"
assert_contains "Privacy manifest: bundled and validated"
assert_contains 'LC_ALL=C /usr/bin/strings -a "$main_binary"'
assert_contains '"-seedCurrentRequiredConsent"'
assert_contains '"-seedAchievementDetailFlow"'
assert_contains '"-seedAchievementDeletionRefreshFlow"'
assert_contains '"-seedQueuedAudioHandoffFlow"'
assert_contains '"ui_test_queued_audio_handoff.wav"'
assert_contains '"-seedMissingVideoFallbackFlow"'
assert_contains '"ui_test_video_fallback.png"'
assert_count 1 "ios-release-main-binary-strings.txt"
assert_contains "ui_test_seed_markers_absent: true"
assert_contains "Debug-only UI-test seed markers: absent"
assert_contains "production-readiness:"
assert_contains "if: always()"
assert_contains 'UNIT_TEST_RESULT" != "success'
assert_contains 'RELEASE_ARCHIVE_RESULT" != "success'
assert_before \
  "- name: Validate and summarize unit-test execution" \
  "- name: Run queued-scan completion UI smoke"
assert_before \
  "- name: Run queued-scan completion UI smoke" \
  "- name: Validate and summarize queued-scan completion UI smoke"
assert_before \
  "- name: Validate and summarize queued-scan completion UI smoke" \
  "- name: Upload unit-test evidence"

if grep -Eq '^[[:space:]]+paths(-ignore)?:' "$workflow"; then
  fail "The required workflow must use in-workflow scope, not event path filters."
fi

# Building and running the whole unit-test target is deliberate. A selector
# below the target level can silently remove Camera, inference, or offline-sync
# coverage while leaving xcodebuild green. The UI bundle is compiled in full,
# then exactly one deterministic critical-path regression is executed.
assert_count 2 "-only-testing:merianTests"
assert_count 2 "-only-testing:merianUITests"
assert_count 1 "-only-testing:merianUITests/"
if grep -Fq -- "-only-testing:merianTests/" "$workflow"; then
  fail "The production gate must not narrow merianTests to selected suites."
fi
if grep -Fq -- "-skip-testing:merianTests" "$workflow"; then
  fail "The production gate must not skip any merianTests suite."
fi
if grep -Fq -- "-skip-testing:merianUITests" "$workflow"; then
  fail "The production gate must not skip any merianUITests case."
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
bash -n "$focused_results_check"
bash -n "$failure_diagnostics_extractor"
assert_file_contains "$critical_results_check" '.result == "Passed"'
assert_file_contains "$critical_results_check" "CameraManagerTests"
assert_file_contains "$critical_results_check" "InferenceEngineTests"
assert_file_contains "$critical_results_check" "OfflineQueueManagerTests"
assert_file_contains "$critical_results_check" "SyncStateManagerTests"
assert_file_contains "$focused_results_check" '.totalTestCount == 1'
assert_file_contains "$focused_results_check" '.skippedTests == 0'
assert_file_contains "$focused_results_check" '($required_suites | length) == 1'
assert_file_contains "$focused_results_check" '$required_suites[0].result? == "Passed"'
assert_file_contains "$focused_results_check" '($all_cases | length) == 1'
assert_file_contains "$ui_seed_source" "try prepareQueuedAudioHandoffMedia()"
assert_file_contains "$ui_seed_source" 'appendASCII("RIFF")'
assert_file_contains "$ui_seed_source" "#if DEBUG"
assert_file_contains "$ui_seed_source" "#else"
assert_file_contains "$ui_seed_source" "return TestExecutionCoordinator.isRunningUITests"
assert_file_contains \
  "$ui_seed_source" \
  'private static let requiredConsentArgument = "-seedCurrentRequiredConsent"'
assert_file_contains \
  "$ui_seed_source" \
  "ProcessInfo.processInfo.arguments.contains(requiredConsentArgument)"
assert_file_contains "$ui_test_source" '"-seedCurrentRequiredConsent"'
assert_file_count \
  "$ui_seed_source" \
  2 \
  "static func prepareRequiredConsentIfNeeded("
assert_file_contains \
  "$ui_seed_source" \
  "consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini("
assert_file_contains "$ui_seed_source" "analyticsEnabled: false"
assert_file_contains "$ui_seed_source" "consentManager _: ConsentManager"
assert_file_contains \
  "$ui_seed_source" \
  "UITestSeedCoordinator.prepareRequiredConsentIfNeeded("
assert_file_before \
  "$ui_seed_source" \
  "UITestSeedCoordinator.prepareRequiredConsentIfNeeded(" \
  "shouldOpenExploreOnFreshLaunch = AppLaunchPresentationPolicy.shouldOpenExplore("
assert_file_count \
  "$ui_seed_source" \
  2 \
  "static func completeQueuedAudioHandoffIfNeeded("
assert_file_count \
  "$ui_seed_source" \
  0 \
  "static func triggerQueuedAudioHandoffIfNeeded("
assert_file_count "$ui_seed_source" 0 "4_000_000_000"
assert_file_contains "$ui_seed_source" "modelContext: ModelContext"
assert_file_contains "$ui_seed_source" "modelContext _: ModelContext"
assert_file_contains "$ui_seed_source" "try modelContext.save()"
assert_file_count "$ui_seed_source" 0 "ScanLibraryEvents.postLibraryDidUpdate()"
assert_file_count \
  "$ui_test_source" \
  1 \
  'let scanningStatusBadge = app.buttons["ScanningStatusBadge"]'
assert_file_count "$ui_test_source" 1 '"ScanningStatusBadge"'
assert_file_contains "$ui_test_source" "scanningStatusBadge.tap()"
assert_file_contains \
  "$ui_test_source" \
  "applicationFrame.contains(scanningStatusBadgeFrame)"
assert_file_contains "$ui_test_source" "appFrame=\\(applicationFrame)"
assert_file_contains "$ui_test_source" "badgeFrame=\\(scanningStatusBadgeFrame)"
assert_file_contains \
  "$scanning_experience_source" \
  ".fixedSize(horizontal: true, vertical: true)"
assert_file_contains "$confidence_badge_source" "private struct BadgeGlareSweep: View"
assert_file_contains "$confidence_badge_source" "Canvas { context, size in"
assert_file_count "$confidence_badge_source" 0 "GeometryReader"
assert_file_count "$confidence_badge_source" 0 ".offset(x:"
assert_file_contains "$confidence_badge_source" ".allowsHitTesting(false)"
assert_file_contains "$confidence_badge_source" ".accessibilityHidden(true)"
assert_file_count \
  "$confidence_badge_source" \
  0 \
  ".accessibilityElement(children: .ignore)"
assert_file_contains \
  "$confidence_badge_source" \
  ".accessibilityLabel(Text(data.label))"
assert_file_contains "$confidence_badge_source" ".contentTransition(.opacity)"
assert_file_contains \
  "$queued_content_source" \
  "UITestSeedCoordinator.completeQueuedAudioHandoffIfNeeded("
assert_file_contains "$queued_content_source" "modelContext: modelContext"
assert_file_count "$queued_content_source" 0 "container: modelContext.container"
assert_file_contains \
  "$queued_content_source" \
  "viewModel.promoteQueuedScanIfLocalRecordExists("
assert_file_count \
  "$queued_content_source" \
  1 \
  "appEventPublisher.send(.scanLibraryChanged)"
assert_file_before \
  "$queued_content_source" \
  "let didPromoteQueuedScan = viewModel.promoteQueuedScanIfLocalRecordExists(" \
  "appEventPublisher.send(.scanLibraryChanged)"
assert_file_before \
  "$queued_content_source" \
  "guard didPromoteQueuedScan else {" \
  "appEventPublisher.send(.scanLibraryChanged)"
assert_file_contains \
  "$insight_records_source" \
  "func bindQueuedPresentationPreferringCompletedRecord("
assert_file_contains \
  "$insight_records_source" \
  "isPresentingLocalRecord(scanId: queuedScan.id)"
assert_file_before \
  "$insight_records_source" \
  "isPresentingLocalRecord(scanId: queuedScan.id)" \
  "bindQueuedPresentation(queuedScan)"
assert_file_count \
  "$insight_sheet_source" \
  2 \
  "viewModel.bindQueuedPresentationPreferringCompletedRecord("
assert_file_contains \
  "$insight_sheet_source" \
  ".task(id: viewModel.scanBoundActionGeneration)"
assert_file_count \
  "$insight_sheet_source" \
  0 \
  ".task(id: viewModel.persistentScanId)"
assert_file_contains \
  "$insight_sheet_source" \
  "viewModel.revealBottomBarTools("
assert_file_contains \
  "$insight_display_source" \
  "func revealBottomBarTools("
assert_file_contains \
  "$network_client_test_source" \
  "testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay()"
assert_file_contains "$network_client_test_source" "defer { requestTask.cancel() }"
assert_file_contains \
  "$network_client_test_source" \
  "let firstRequestDeadline = ContinuousClock.now.advanced(by: .seconds(5))"
assert_file_contains \
  "$network_client_test_source" \
  "while probe.count == 0 && ContinuousClock.now < firstRequestDeadline"
assert_file_contains \
  "$network_client_test_source" \
  "try await Task.sleep(for: .milliseconds(10))"
assert_file_count "$network_client_test_source" 0 "for _ in 0..<100 {"
assert_file_contains \
  "$ui_seed_source" \
  "static var isEnabled: Bool { return false }"
assert_file_count "$ui_seed_source" 2 "enum UITestSeedCoordinator {"
assert_file_contains \
  "$ui_seed_source" \
  "static func prepareIfNeeded(container _: ModelContainer) {}"
assert_file_contains "$audio_page_source" '"AudioPlaybackControl_'
assert_file_contains \
  "$field_chat_toolbar_source" \
  '.accessibilityIdentifier("FieldChatToolbarButton")'
assert_file_contains \
  "$insight_share_button_source" \
  '.accessibilityIdentifier("InsightShareButton")'
assert_file_count "$scans_sheet_source" 3 "if hasAutomaticQueuedRecoveryWork {"
assert_file_count "$scans_sheet_source" 2 "guard hasAutomaticQueuedRecoveryWork else { return }"
assert_file_contains \
  "$scans_sheet_source" \
  "queuedScan.isAutomaticRecoveryEligibleForCurrentNetwork("
assert_file_contains "$scans_sheet_source" 'String($0.queueState.rawValue)'
assert_file_contains \
  "$scans_sheet_source" \
  '"constrained:\(offlineQueueManager.isCurrentNetworkConstrained)"'
assert_file_contains \
  "$scans_sheet_source" \
  "CapturedMediaSnapshot(items: capturedMediaItems)"
assert_file_contains \
  "$scans_sheet_source" \
  "let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue"
assert_file_contains \
  "$scans_sheet_source" \
  '$0.scanStateRaw < firstNonRunnableRaw || $0.queueNeedsAttention'
assert_file_contains "$scans_grid_source" "var isAutomaticRecoveryEligible: Bool"
assert_file_contains \
  "$scans_grid_source" \
  "func isAutomaticRecoveryEligibleForCurrentNetwork("
assert_file_contains "$scans_grid_source" "guard isOnline,"
assert_file_contains \
  "$queue_manager_source" \
  "private var currentPathIsConstrained = false"
assert_file_contains \
  "$queue_manager_source" \
  "private var currentPathIsExpensive = false"
assert_file_contains \
  "$queue_manager_source" \
  "var allowsAutomaticNetworkWorkOnCurrentPath: Bool"
assert_file_contains \
  "$queue_url_session_source" \
  "guard allowsAutomaticNetworkWorkOnCurrentPath,"
assert_file_contains \
  "$queue_url_session_source" \
  "self.allowsAutomaticNetworkWorkOnCurrentPath else"
assert_file_count \
  "$queue_url_session_source" \
  17 \
  "allowsAutomaticNetworkWorkOnCurrentPath"
assert_file_count \
  "$queue_sync_source" \
  3 \
  "Set<String>(liveTasks.compactMap { task -> String? in"
assert_file_contains \
  "$queue_source" \
  "Set<String>(allTasks.compactMap { task -> String? in"
assert_file_contains \
  "$queue_sync_source" \
  "func queuedUploadRequest("
assert_file_contains \
  "$queue_sync_source" \
  "request.allowsConstrainedNetworkAccess = false"
assert_file_contains \
  "$queue_sync_source" \
  "request.allowsExpensiveNetworkAccess ="
assert_file_contains "$queue_sync_source" "finalPolicy.isOnline"
assert_file_contains \
  "$queue_sync_source" \
  "var entriesByScanId: [String: [UploadDispatchEntry]]"
assert_file_contains "$queue_sync_source" "let uploadTasks = entries.map"
assert_file_contains "$queue_sync_source" "for uploadTask in uploadTasks"
assert_file_contains \
  "$queue_sync_source" \
  "candidateScanIds: undispatchedScanIDs"
assert_file_contains \
  "$background_database_actor_source" \
  'message: "Recovered an upload claim without an active task."'
assert_file_contains \
  "$background_database_actor_source" \
  'message: "Recovered an inference claim without an active task."'
assert_file_contains \
  "$scans_grid_source" \
  "guard queueState != .externalImport else { return false }"
assert_file_contains \
  "$queued_context_source" \
  "guard queueState != .externalImport else { return false }"
assert_file_contains \
  "$queue_durability_source" \
  "guard scan.queueState != .externalImport else { return false }"
assert_file_contains \
  "$ui_test_source" \
  'app.buttons["AudioPlaybackControl_ui_test_queued_audio_handoff.wav"]'
assert_file_contains "$ui_test_source" 'app.buttons["FieldChatToolbarButton"]'
assert_file_contains "$ui_test_source" 'app.buttons["InsightShareButton"]'

protected_case_count=0
while IFS="|" read -r protected_case_name protected_display_name; do
  [[ -n "$protected_case_name" ]] \
    || fail "Critical-result validator emitted an empty protected test-case name."

  protected_declarations="$(
    grep -REn \
      --include='*.swift' \
      "^[[:space:]]*(@Test(\\([^)]*\\))?[[:space:]]+)?func[[:space:]]+${protected_case_name}[[:space:]]*\\(" \
      "$ios_test_sources" \
      || true
  )"
  protected_declaration_count="$(
    printf '%s\n' "$protected_declarations" \
      | awk 'NF { count += 1 } END { print count + 0 }'
  )"
  if [[ "$protected_declaration_count" != "1" ]]; then
    fail \
      "Critical-result validator requires exactly one Swift declaration for $protected_case_name; found $protected_declaration_count."
  fi

  protected_declaration_file="${protected_declarations%%:*}"
  protected_declaration_tail="${protected_declarations#*:}"
  protected_declaration_line="${protected_declaration_tail%%:*}"
  protected_annotation_start="$protected_declaration_line"
  if (( protected_annotation_start > 1 )); then
    protected_annotation_start=$((protected_annotation_start - 1))
  fi
  protected_annotation="$(
    sed -n \
      "${protected_annotation_start},${protected_declaration_line}p" \
      "$protected_declaration_file"
  )"
  if ! grep -Eq \
    '^[[:space:]]*@Test([[:space:](]|$)' \
    <<<"$protected_annotation"; then
    fail \
      "Critical-result validator references a declaration that is not bound to @Test: $protected_case_name"
  fi
  if [[ -n "$protected_display_name" ]] \
    && ! grep -Fq \
      "@Test(\"${protected_display_name}\"" \
      <<<"$protected_annotation"; then
    fail \
      "Critical-result validator display name is not bound to $protected_case_name: $protected_display_name"
  fi
  protected_case_count=$((protected_case_count + 1))
done < <(
  awk '
    /assert_suite_has_passed_test_case \\/ {
      in_call = 1
      quoted_count = 0
      required_case = ""
      alternate_case = ""
      next
    }
    in_call && match($0, /"[^"]+"/) {
      value = substr($0, RSTART + 1, RLENGTH - 2)
      quoted_count += 1
      if (quoted_count == 4) {
        required_case = value
      } else if (quoted_count == 5) {
        alternate_case = value
      }
    }
    in_call && $0 !~ /\\[[:space:]]*$/ {
      printf "%s|%s\n", required_case, alternate_case
      in_call = 0
    }
  ' "$critical_results_check"
)
[[ "$protected_case_count" == "81" ]] \
  || fail \
    "Expected 81 exact protected iOS test cases; found $protected_case_count."

for exact_scan_regression in \
  "consentRequiredFailuresStayOutOfNetworkCircuitForVisualAndNonVisual" \
  "providerAdmissionFailuresStayOutOfNetworkCircuitForVisualAndNonVisual" \
  "observationRejectionStaysTerminalAndOutOfNetworkCircuitForVisualAndNonVisual" \
  "testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry" \
  "scheduledServerFailureRetryBreaksStatusUploadDeadlock" \
  "scheduledServerFailureMarkerIsReadFromDurableStore" \
  "testMarkScanAsStagedPreservesScheduledServerFailureRetry" \
  "testScheduleInferenceRetryUsesMonotonicMirroredAttempt" \
  "testInferenceRetryCannotOverrideCompletedCloudOwnership" \
  "testManualRetryResetsBudgetForDescriptionOnlyScan" \
  "consentReapprovalResumesOnlyNewestOwnedFundedScan" \
  "consentReapprovalSkipsUnownedOrUnfundedScans" \
  "testCompleteOnboardingResumesConsentBlockedScanForCurrentAccount" \
  "testCompleteOnboardingDoesNotResumeWithoutCurrentAccount" \
  "pausedScansCannotBeClaimedOrReconciled" \
  "testReconcileOrphanedUploadingScansResetsOrphansKeepsActive" \
  "pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork" \
  "emptyPendingQuarantineIsAtomicAndStateBound" \
  "unsyncedCountIncludesOnlyAutomaticallyRunnableScans" \
  "uploadBatchSelectionSkipsBlockedHeadRowsAndPacksLaterWork" \
  "testMediaStagingContractRejectsEmptyFilesBeforeUpload" \
  "testRetryQueuedScanNowRejectsLegacyExternalImport" \
  "cloudDeletionRequiresExplicitNetworkConfirmation" \
  "cloudDeletionRetriesNeverEnterAnUnrecoverableState" \
  "cloudDeletionDrainIsProcessSingleFlight" \
  "testExploreShareSendsMissingScanRecoveryPayload" \
  "testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion" \
  "testExploreMediaIncidentsAndLifecycleNotificationsDecode" \
  "testExploreMediaIncidentsRejectsUnknownSuccessShape" \
  "testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning" \
  "testDeleteScanRejectsUnconfirmedSuccessResponse"; do
  assert_file_contains "$critical_results_check" "$exact_scan_regression"
done

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

#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 TEST_SUMMARY_JSON TEST_TREE_JSON" >&2
  exit 2
fi

summary_path="$1"
test_tree_path="$2"

for required_file in "$summary_path" "$test_tree_path"; do
  if [[ ! -s "$required_file" ]]; then
    echo "Missing or empty iOS test result file: $required_file" >&2
    exit 1
  fi
done

if ! jq -e '
  .result == "Passed"
  and ((.totalTestCount | type) == "number")
  and (.totalTestCount > 0)
  and ((.passedTests | type) == "number")
  and (.passedTests > 0)
  and ((.failedTests | type) == "number")
  and (.failedTests == 0)
  and ((.skippedTests | type) == "number")
  and (.skippedTests == 0)
  and (.passedTests == .totalTestCount)
' "$summary_path" >/dev/null; then
  echo "The complete iOS unit-test target did not report a passing, non-empty, unskipped run." >&2
  exit 1
fi

assert_suite_has_passed_test() {
  local suite_label="$1"
  local primary_name="$2"
  local alternate_name="$3"

  if ! jq -e \
    --arg primary "$primary_name" \
    --arg alternate "$alternate_name" \
    '
      [
        ..
        | objects
        | select(.nodeType? == "Test Suite")
        | . as $suite
        | select(
            ([$primary, $alternate] | index($suite.name)) != null
          )
        | [
            $suite
            | ..
            | objects
            | select(
                .nodeType? == "Test Case"
                and .result? == "Passed"
              )
          ]
        | length
      ]
      | any(. > 0)
    ' "$test_tree_path" >/dev/null; then
    echo "$suite_label did not report a passed test case." >&2
    exit 1
  fi
}

assert_suite_has_passed_test_case() {
  local case_label="$1"
  local primary_suite_name="$2"
  local alternate_suite_name="$3"
  local required_case_name="$4"

  if ! jq -e \
    --arg primary_suite "$primary_suite_name" \
    --arg alternate_suite "$alternate_suite_name" \
    --arg required_case "$required_case_name" \
    '
      [
        ..
        | objects
        | select(.nodeType? == "Test Suite")
        | . as $suite
        | select(
            ([$primary_suite, $alternate_suite] | index($suite.name)) != null
          )
        | [
            $suite
            | ..
            | objects
            | select(
                .nodeType? == "Test Case"
                and .result? == "Passed"
                and (
                  .name? == $required_case
                  or .name? == ($required_case + "()")
                )
              )
          ]
        | length
      ]
      | any(. > 0)
    ' "$test_tree_path" >/dev/null; then
    echo "$case_label did not report a passed test case." >&2
    exit 1
  fi
}

assert_suite_has_passed_test \
  "CameraManagerTests" \
  "CameraManagerTests" \
  "Camera Manager Tests"
assert_suite_has_passed_test \
  "InferenceEngineTests" \
  "InferenceEngineTests" \
  "Inference Engine Tests"
assert_suite_has_passed_test \
  "OfflineQueueManagerTests" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests"
assert_suite_has_passed_test \
  "SyncStateManagerTests" \
  "SyncStateManagerTests" \
  "Sync State Manager Tests"

assert_suite_has_passed_test_case \
  "Foreground malformed-success recovery" \
  "InferenceEngineTests" \
  "Inference Engine Tests" \
  "decodedButUnusableSuccessEnvelopeRemainsRecoverable"
assert_suite_has_passed_test_case \
  "Identification confirmation presentation identity" \
  "InferenceEngineTests" \
  "Inference Engine Tests" \
  "testConfirmAIIdentificationRejectsChangedPresentationIdentity"
assert_suite_has_passed_test_case \
  "Identification override presentation identity" \
  "InferenceEngineTests" \
  "Inference Engine Tests" \
  "testApplyIdentificationOverrideRejectsChangedPresentationIdentity"
assert_suite_has_passed_test_case \
  "Bounded inference metadata-write backlog" \
  "InferenceEngineTests" \
  "Inference Engine Tests" \
  "testBackgroundWriteBacklogHasAHardMemoryBound"
assert_suite_has_passed_test_case \
  "Background malformed-success recovery" \
  "BackgroundDatabaseActorTests" \
  "Background Database Actor Tests" \
  "generatedBackgroundResultRejectsMalformedSuccessBody"
assert_suite_has_passed_test_case \
  "Confidence-zero source-media durability" \
  "BackgroundDatabaseActorTests" \
  "Background Database Actor Tests" \
  "generatedConfidenceZeroBackgroundResultIsTerminal"
assert_suite_has_passed_test_case \
  "Background HTTP-success disposition" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "backgroundInferencePreservesRecoverableHTTPFailures"
assert_suite_has_passed_test_case \
  "Inference replay process single-flight" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "inferenceReplayReconciliationCoalescesConcurrentWakeSources"
assert_suite_has_passed_test_case \
  "Retryable status/upload deadlock dispatch" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "scheduledServerFailureRetryBreaksStatusUploadDeadlock"
assert_suite_has_passed_test_case \
  "Durable server-failure retry latch" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "scheduledServerFailureMarkerIsReadFromDurableStore"
assert_suite_has_passed_test_case \
  "Scheduled retry survival through media restaging" \
  "BackgroundDatabaseActorTests" \
  "Background Database Actor Tests" \
  "testMarkScanAsStagedPreservesScheduledServerFailureRetry"
assert_suite_has_passed_test_case \
  "Monotonic mirrored retry accounting" \
  "BackgroundDatabaseActorTests" \
  "Background Database Actor Tests" \
  "testScheduleInferenceRetryUsesMonotonicMirroredAttempt"
assert_suite_has_passed_test_case \
  "Cloud-complete retry veto" \
  "BackgroundDatabaseActorTests" \
  "Background Database Actor Tests" \
  "testInferenceRetryCannotOverrideCompletedCloudOwnership"
assert_suite_has_passed_test_case \
  "Offline capture durability" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "testEnqueueCapture_WithValidData_PersistsQueuedScan"
assert_suite_has_passed_test_case \
  "Description-only manual retry budget reset" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "testManualRetryResetsBudgetForDescriptionOnlyScan"
assert_suite_has_passed_test_case \
  "Atomic offline completion" \
  "OfflineQueuedScanDeletionTests" \
  "Offline Queued Scan Deletion Tests" \
  "completedInferenceAndQueueDeletionCommitTogether"
assert_suite_has_passed_test_case \
  "Cloud deletion positive confirmation" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "cloudDeletionRequiresExplicitNetworkConfirmation"
assert_suite_has_passed_test_case \
  "Cloud deletion indefinite retry recovery" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "cloudDeletionRetriesNeverEnterAnUnrecoverableState"
assert_suite_has_passed_test_case \
  "Cloud deletion process single-flight" \
  "OfflineQueueManagerTests" \
  "Offline Queue Manager Tests" \
  "cloudDeletionDrainIsProcessSingleFlight"
assert_suite_has_passed_test_case \
  "Cloud deletion response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testDeleteScanRejectsUnconfirmedSuccessResponse"
assert_suite_has_passed_test_case \
  "Foreground scan submission" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON"
assert_suite_has_passed_test_case \
  "Explore share idempotency" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreShareSendsStableAIIdempotencyKey"
assert_suite_has_passed_test_case \
  "Explore share response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreShareRejectsContradictorySuccessResponses"
assert_suite_has_passed_test_case \
  "Existing Explore scan recovery payload" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreShareSendsMissingScanRecoveryPayload"
assert_suite_has_passed_test_case \
  "Existing Explore scan recovery safety" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion"
assert_suite_has_passed_test_case \
  "Existing Explore stable missing-scan classifier" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreCloudScanRestoreUsesStableNotFoundCodeWithLegacyFallback"
assert_suite_has_passed_test_case \
  "Field Chat local/cloud identity fence" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testFieldChatCloudPreflightRejectsMismatchedRecordIdentity"
assert_suite_has_passed_test_case \
  "Presented record stale-binding invalidation" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testMissingDifferentRecordClearsStaleScanBoundState"
assert_suite_has_passed_test_case \
  "Presented record action-generation invalidation" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testRecordSwitchInvalidatesPriorActionGeneration"
assert_suite_has_passed_test_case \
  "Insight reset monotonic request invalidation" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testResetMonotonicallyInvalidatesScanBoundRequests"
assert_suite_has_passed_test_case \
  "Field-notes presentation identity" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testFieldNotesRejectChangedPresentationIdentity"
assert_suite_has_passed_test_case \
  "Strong noncompetitive candidate toolbar policy" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates"
assert_suite_has_passed_test_case \
  "Competitive candidate toolbar policy" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates"
assert_suite_has_passed_test_case \
  "Published Explore Field Notes promotion" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty"
assert_suite_has_passed_test_case \
  "Private local Field Notes preservation" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes"
assert_suite_has_passed_test_case \
  "Explore composer Field Notes synchronization" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testShareComposerFieldNotesSyncImmediatelyIntoInsightState"
assert_suite_has_passed_test_case \
  "Preferred-name presentation-generation identity" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testPreferredNameRejectsStalePresentationGeneration"
assert_suite_has_passed_test_case \
  "Queued scan refresh presentation identity" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testQueuedRefreshRejectsChangedPresentationIdentity"
assert_suite_has_passed_test_case \
  "Queued scan parent presentation switch identity" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testQueuedPresentationSwitchInvalidatesPriorQueueIdentity"
assert_suite_has_passed_test_case \
  "Queued scan completion presentation identity" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testQueuedPromotionRejectsChangedPresentationIdentity"
assert_suite_has_passed_test_case \
  "Explore presented-record identity fence" \
  "InsightSheetViewModelTests" \
  "Insight Sheet View Model Tests" \
  "testExploreSharingRequiresExactEngineAndRecordIdentity"
assert_suite_has_passed_test_case \
  "Single scan-status response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testCheckScanStatusRejectsMalformedOrMismatchedSuccess"
assert_suite_has_passed_test_case \
  "Bulk scan-status response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testBulkScanStatusRejectsDuplicateMissingOrForeignRows"
assert_suite_has_passed_test_case \
  "Explore media-health rollout compatibility" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreMediaIncidentsAndLifecycleNotificationsDecode"
assert_suite_has_passed_test_case \
  "Explore media-health response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreMediaIncidentsRejectsUnknownSuccessShape"
assert_suite_has_passed_test_case \
  "Explore repair preflight budget" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload"
assert_suite_has_passed_test_case \
  "Community all-media recovery" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testCommunityRequestSendsStableAIIdempotencyKey"
assert_suite_has_passed_test_case \
  "Community response integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testCommunityRequestRejectsUnconfirmedSuccessResponse"
assert_suite_has_passed_test_case \
  "Explore reconciliation integrity" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testGetExploreShareStateRejectsUnconfirmedState"
assert_suite_has_passed_test_case \
  "Missing-owner stale publication reset" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testMissingOwnerShareStateClearsStaleLocalPublication"
assert_suite_has_passed_test_case \
  "Explore hidden-publication reconciliation" \
  "MerianNetworkClientTests" \
  "Network Client Tests" \
  "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
assert_suite_has_passed_test_case \
  "Explore Field Chat identifier routing" \
  "InsightChatTests" \
  "Insight Chat Tests" \
  "explorePostRequestUsesPostIdentifierContract"
assert_suite_has_passed_test_case \
  "Field Chat transient-readiness recovery" \
  "InsightChatTests" \
  "Insight Chat Tests" \
  "testTransientOwnedScanReadinessKeepsChatEntryRetryable"
assert_suite_has_passed_test_case \
  "Field Chat single-flight preparation" \
  "InsightChatTests" \
  "Insight Chat Tests" \
  "testConcurrentPresentationRequestsSharePreparationResult"
assert_suite_has_passed_test_case \
  "Field Chat stale-subject completion fence" \
  "InsightChatTests" \
  "Insight Chat Tests" \
  "testFieldChatRejectsStaleSubjectCompletion"
assert_suite_has_passed_test_case \
  "Field Chat changed-subject preparation replacement" \
  "InsightChatTests" \
  "Insight Chat Tests" \
  "testFieldChatReplacesPreparationForChangedSubject"
assert_suite_has_passed_test_case \
  "Issue-reporting presented-scan identity fence" \
  "ReportInsightViewModelTests" \
  "ReportInsightViewModel Tests" \
  "testSubmitFlagRejectsChangedScanIdentity"
assert_suite_has_passed_test_case \
  "Issue-reporting same-scan presentation-generation fence" \
  "ReportInsightViewModelTests" \
  "ReportInsightViewModel Tests" \
  "testSubmitFlagRejectsStaleSameScanCompletion"

echo "Critical iOS suites and exact scan-flow regressions reported passed test cases."

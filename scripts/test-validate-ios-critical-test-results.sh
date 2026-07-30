#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-ios-critical-test-results.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-test-results.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

summary_path="$tmp_dir/summary.json"
test_tree_path="$tmp_dir/tests.json"

write_summary() {
  local result="$1"
  local total="$2"
  local passed="$3"
  local failed="$4"
  local skipped="${5:-0}"
  jq -n \
    --arg result "$result" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    '{
      result: $result,
      totalTestCount: $total,
      passedTests: $passed,
      failedTests: $failed,
      skippedTests: $skipped
    }' > "$summary_path"
}

reported_case_name() {
  case "$1" in
    testSubmitFlagRejectsChangedScanIdentity)
      printf '%s\n' "Submit Flag Rejects Changed Scan Identity"
      ;;
    testSubmitFlagRejectsStaleSameScanCompletion)
      printf '%s\n' "Submit Flag Rejects Stale Same-Scan Completion"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

write_test_tree() {
  local omitted_suite="${1:-}"
  local omitted_case="${2:-}"
  local omitted_reported_case
  omitted_reported_case="$(reported_case_name "$omitted_case")"
  jq -n \
    --arg omitted_suite "$omitted_suite" \
    --arg omitted_case "$omitted_reported_case" \
    '
      def test_case($name):
        {
          nodeType: "Test Case",
          name: (
            if ($name | startswith("display:")) then
              $name | ltrimstr("display:")
            else
              $name + "()"
            end
          ),
          result: "Passed"
        };
      def suite($name; $case_names):
        {
          nodeType: "Test Suite",
          name: $name,
          result: "Passed",
          children: (
            $case_names
            | map(test_case(.))
            | map(select(
                .name != $omitted_case
                and .name != ($omitted_case + "()")
              ))
          )
        };
      {
        testNodes: (
          [
            suite("CameraManagerTests"; [
              "generationFenceTest"
            ]),
            suite("Inference Engine Tests"; [
              "generationFenceTest",
              "decodedButUnusableSuccessEnvelopeRemainsRecoverable",
              "testConfirmAIIdentificationRejectsChangedPresentationIdentity",
              "testApplyIdentificationOverrideRejectsChangedPresentationIdentity",
              "testBackgroundWriteBacklogHasAHardMemoryBound"
            ]),
            suite("OfflineQueueManagerTests"; [
              "generationFenceTest",
              "backgroundInferencePreservesRecoverableHTTPFailures",
              "inferenceReplayReconciliationCoalescesConcurrentWakeSources",
              "scheduledServerFailureRetryBreaksStatusUploadDeadlock",
              "scheduledServerFailureMarkerIsReadFromDurableStore",
              "cloudDeletionRequiresExplicitNetworkConfirmation",
              "cloudDeletionRetriesNeverEnterAnUnrecoverableState",
              "cloudDeletionDrainIsProcessSingleFlight",
              "unsyncedCountIncludesOnlyAutomaticallyRunnableScans",
              "uploadBatchSelectionSkipsBlockedHeadRowsAndPacksLaterWork",
              "testMediaStagingContractRejectsEmptyFilesBeforeUpload",
              "testRetryQueuedScanNowRejectsLegacyExternalImport",
              "testManualRetryResetsBudgetForDescriptionOnlyScan",
              "queueDiagnosticsExportOmitsPrivateAndFreeFormValues",
              "queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred",
              "testEnqueueCapture_WithValidData_PersistsQueuedScan"
            ]),
            suite("SyncStateManagerTests"; [
              "generationFenceTest"
            ]),
            suite("BackgroundDatabaseActorTests"; [
              "generatedBackgroundResultRejectsMalformedSuccessBody",
              "generatedConfidenceZeroBackgroundResultIsTerminal",
              "pausedScansCannotBeClaimedOrReconciled",
              "testReconcileOrphanedUploadingScansResetsOrphansKeepsActive",
              "pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork",
              "emptyPendingQuarantineIsAtomicAndStateBound",
              "testMarkScanAsStagedPreservesScheduledServerFailureRetry",
              "testScheduleInferenceRetryUsesMonotonicMirroredAttempt",
              "testInferenceRetryCannotOverrideCompletedCloudOwnership"
            ]),
            suite("Offline Queued Scan Deletion Tests"; [
              "completedInferenceAndQueueDeletionCommitTogether"
            ]),
            suite("CompositeLibraryTests"; [
              "testVisibleNeedsAttentionRowsDoNotDriveAutomaticRecovery"
            ]),
            suite("Network Client Tests"; [
              "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON",
              "testDeleteScanRejectsUnconfirmedSuccessResponse",
              "testExploreShareSendsStableAIIdempotencyKey",
              "testExploreShareRejectsContradictorySuccessResponses",
              "testExploreShareSendsMissingScanRecoveryPayload",
              "testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion",
              "testExploreCloudScanRestoreUsesStableNotFoundCodeWithLegacyFallback",
              "testFieldChatCloudPreflightRejectsMismatchedRecordIdentity",
              "testCheckScanStatusRejectsMalformedOrMismatchedSuccess",
              "testBulkScanStatusRejectsDuplicateMissingOrForeignRows",
              "testExploreMediaIncidentsAndLifecycleNotificationsDecode",
              "testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary",
              "testExploreMediaIncidentsRejectsUnknownSuccessShape",
              "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload",
              "testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning",
              "testCommunityRequestSendsStableAIIdempotencyKey",
              "testCommunityRequestRejectsUnconfirmedSuccessResponse",
              "testGetExploreShareStateRejectsUnconfirmedState",
              "testMissingOwnerShareStateClearsStaleLocalPublication",
              "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
            ]),
            suite("InsightSheetViewModelTests"; [
              "testMissingDifferentRecordClearsStaleScanBoundState",
              "testRecordSwitchInvalidatesPriorActionGeneration",
              "testResetMonotonicallyInvalidatesScanBoundRequests",
              "testFieldNotesRejectChangedPresentationIdentity",
              "testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates",
              "testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates",
              "testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty",
              "testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes",
              "testShareComposerFieldNotesSyncImmediatelyIntoInsightState",
              "testPreferredNameRejectsStalePresentationGeneration",
              "testQueuedRefreshRejectsChangedPresentationIdentity",
              "testQueuedPresentationSwitchInvalidatesPriorQueueIdentity",
              "testQueuedPromotionRejectsChangedPresentationIdentity",
              "testQueuedPresentationPrefersPersistedCompletionOverStaleRoute",
              "testQueuedPresentationRemainsQueuedWhenCompletionIsAbsent",
              "testExploreSharingRequiresExactEngineAndRecordIdentity"
            ]),
            suite("InsightChatTests"; [
              "explorePostRequestUsesPostIdentifierContract",
              "testTransientOwnedScanReadinessKeepsChatEntryRetryable",
              "testConcurrentPresentationRequestsSharePreparationResult",
              "testFieldChatRejectsStaleSubjectCompletion",
              "testFieldChatReplacesPreparationForChangedSubject"
            ]),
            suite("ReportInsightViewModel Tests"; [
              "display:Submit Flag Rejects Changed Scan Identity",
              "display:Submit Flag Rejects Stale Same-Scan Completion"
            ])
          ]
          | map(select(.name != $omitted_suite))
        )
      }
    ' > "$test_tree_path"
}

assert_rejected() {
  local description="$1"
  if bash "$validator" "$summary_path" "$test_tree_path" >/dev/null 2>&1; then
    fail "$description was accepted."
  fi
}

write_summary "Passed" 4 4 0
write_test_tree
bash "$validator" "$summary_path" "$test_tree_path" >/dev/null \
  || fail "A valid critical-suite result was rejected."

write_test_tree
jq \
  '(.testNodes[] | select(.name == "CameraManagerTests") | .result) = "Failed"' \
  "$test_tree_path" > "$tmp_dir/failed-suite.json"
mv "$tmp_dir/failed-suite.json" "$test_tree_path"
assert_rejected "A failed required suite containing a passed test"

write_test_tree
jq \
  '(.testNodes[] | select(.name == "Network Client Tests") | .result) = "Failed"' \
  "$test_tree_path" > "$tmp_dir/failed-suite.json"
mv "$tmp_dir/failed-suite.json" "$test_tree_path"
assert_rejected "A passed exact case inside a failed suite"

write_test_tree
jq \
  '.testNodes += [(.testNodes[] | select(.name == "CameraManagerTests"))]' \
  "$test_tree_path" > "$tmp_dir/duplicated-suite.json"
mv "$tmp_dir/duplicated-suite.json" "$test_tree_path"
assert_rejected "A duplicated required suite"

write_test_tree
jq '
  (
    .testNodes[]
    | select(.name == "Network Client Tests")
    | .children
  ) += [
    (
      .testNodes[]
      | select(.name == "Network Client Tests")
      | .children[]
      | select(
          .name ==
            "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON()"
        )
    )
  ]
' "$test_tree_path" > "$tmp_dir/duplicated-case.json"
mv "$tmp_dir/duplicated-case.json" "$test_tree_path"
assert_rejected "A duplicated exact protected case"

write_summary "Failed" 4 3 1
assert_rejected "A failed result"

write_summary "Passed" 0 0 0
assert_rejected "An empty result"

write_summary "Passed" 4 3 0 1
assert_rejected "A result with a skipped test"

write_summary "Passed" 5 4 0 0
assert_rejected "An incomplete passing result"

write_summary "Passed" 4 4 0
for omitted_suite in \
  "CameraManagerTests" \
  "Inference Engine Tests" \
  "OfflineQueueManagerTests" \
  "SyncStateManagerTests"; do
  write_test_tree "$omitted_suite"
  assert_rejected "A result missing $omitted_suite"
done

required_cases=(
  "decodedButUnusableSuccessEnvelopeRemainsRecoverable"
  "testConfirmAIIdentificationRejectsChangedPresentationIdentity"
  "testApplyIdentificationOverrideRejectsChangedPresentationIdentity"
  "testBackgroundWriteBacklogHasAHardMemoryBound"
  "generatedBackgroundResultRejectsMalformedSuccessBody"
  "generatedConfidenceZeroBackgroundResultIsTerminal"
  "backgroundInferencePreservesRecoverableHTTPFailures"
  "inferenceReplayReconciliationCoalescesConcurrentWakeSources"
  "scheduledServerFailureRetryBreaksStatusUploadDeadlock"
  "scheduledServerFailureMarkerIsReadFromDurableStore"
  "testMarkScanAsStagedPreservesScheduledServerFailureRetry"
  "testScheduleInferenceRetryUsesMonotonicMirroredAttempt"
  "testInferenceRetryCannotOverrideCompletedCloudOwnership"
  "testEnqueueCapture_WithValidData_PersistsQueuedScan"
  "testManualRetryResetsBudgetForDescriptionOnlyScan"
  "queueDiagnosticsExportOmitsPrivateAndFreeFormValues"
  "queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred"
  "completedInferenceAndQueueDeletionCommitTogether"
  "testVisibleNeedsAttentionRowsDoNotDriveAutomaticRecovery"
  "pausedScansCannotBeClaimedOrReconciled"
  "testReconcileOrphanedUploadingScansResetsOrphansKeepsActive"
  "pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork"
  "emptyPendingQuarantineIsAtomicAndStateBound"
  "unsyncedCountIncludesOnlyAutomaticallyRunnableScans"
  "uploadBatchSelectionSkipsBlockedHeadRowsAndPacksLaterWork"
  "testMediaStagingContractRejectsEmptyFilesBeforeUpload"
  "testRetryQueuedScanNowRejectsLegacyExternalImport"
  "cloudDeletionRequiresExplicitNetworkConfirmation"
  "cloudDeletionRetriesNeverEnterAnUnrecoverableState"
  "cloudDeletionDrainIsProcessSingleFlight"
  "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON"
  "testDeleteScanRejectsUnconfirmedSuccessResponse"
  "testExploreShareSendsStableAIIdempotencyKey"
  "testExploreShareRejectsContradictorySuccessResponses"
  "testExploreShareSendsMissingScanRecoveryPayload"
  "testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion"
  "testExploreCloudScanRestoreUsesStableNotFoundCodeWithLegacyFallback"
  "testFieldChatCloudPreflightRejectsMismatchedRecordIdentity"
  "testMissingDifferentRecordClearsStaleScanBoundState"
  "testRecordSwitchInvalidatesPriorActionGeneration"
  "testResetMonotonicallyInvalidatesScanBoundRequests"
  "testFieldNotesRejectChangedPresentationIdentity"
  "testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates"
  "testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates"
  "testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty"
  "testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes"
  "testShareComposerFieldNotesSyncImmediatelyIntoInsightState"
  "testPreferredNameRejectsStalePresentationGeneration"
  "testQueuedRefreshRejectsChangedPresentationIdentity"
  "testQueuedPresentationSwitchInvalidatesPriorQueueIdentity"
  "testQueuedPromotionRejectsChangedPresentationIdentity"
  "testQueuedPresentationPrefersPersistedCompletionOverStaleRoute"
  "testQueuedPresentationRemainsQueuedWhenCompletionIsAbsent"
  "testExploreSharingRequiresExactEngineAndRecordIdentity"
  "testCheckScanStatusRejectsMalformedOrMismatchedSuccess"
  "testBulkScanStatusRejectsDuplicateMissingOrForeignRows"
  "testExploreMediaIncidentsAndLifecycleNotificationsDecode"
  "testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary"
  "testExploreMediaIncidentsRejectsUnknownSuccessShape"
  "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload"
  "testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning"
  "testCommunityRequestSendsStableAIIdempotencyKey"
  "testCommunityRequestRejectsUnconfirmedSuccessResponse"
  "testGetExploreShareStateRejectsUnconfirmedState"
  "testMissingOwnerShareStateClearsStaleLocalPublication"
  "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
  "explorePostRequestUsesPostIdentifierContract"
  "testTransientOwnedScanReadinessKeepsChatEntryRetryable"
  "testConcurrentPresentationRequestsSharePreparationResult"
  "testFieldChatRejectsStaleSubjectCompletion"
  "testFieldChatReplacesPreparationForChangedSubject"
  "testSubmitFlagRejectsChangedScanIdentity"
  "testSubmitFlagRejectsStaleSameScanCompletion"
)

for omitted_case in "${required_cases[@]}"; do
  write_test_tree "" "$omitted_case"
  assert_rejected "A result missing $omitted_case"
done

for skipped_case in "${required_cases[@]}"; do
  write_test_tree
  skipped_reported_case="$(reported_case_name "$skipped_case")"
  jq \
    --arg skipped_case "$skipped_reported_case" \
    '
      (
        ..
        | objects
        | select(
            .nodeType? == "Test Case"
            and (
              .name? == $skipped_case
              or .name? == ($skipped_case + "()")
            )
          )
        | .result
      ) = "Skipped"
    ' "$test_tree_path" > "$tmp_dir/skipped-tests.json"
  mv "$tmp_dir/skipped-tests.json" "$test_tree_path"
  assert_rejected "$skipped_case reported as skipped"
done

for skipped_suite in \
  "CameraManagerTests" \
  "Inference Engine Tests" \
  "OfflineQueueManagerTests" \
  "SyncStateManagerTests"; do
  write_test_tree
  jq \
    --arg skipped_suite "$skipped_suite" \
    '
      (
        ..
        | objects
        | select(
            .nodeType? == "Test Suite"
            and .name? == $skipped_suite
          )
        | ..
        | objects
        | select(.nodeType? == "Test Case")
        | .result
      ) = "Skipped"
    ' "$test_tree_path" > "$tmp_dir/skipped-tests.json"
  mv "$tmp_dir/skipped-tests.json" "$test_tree_path"
  assert_rejected "$skipped_suite containing only skipped tests"
done

echo "Critical iOS suite and exact-regression result validation tests passed."

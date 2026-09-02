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

write_test_tree() {
  local omitted_suite="${1:-}"
  local omitted_case="${2:-}"
  jq -n \
    --arg omitted_suite "$omitted_suite" \
    --arg omitted_case "$omitted_case" \
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
              "consentRequiredFailuresStayOutOfNetworkCircuitForVisualAndNonVisual",
              "providerAdmissionFailuresStayOutOfNetworkCircuitForVisualAndNonVisual",
              "queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual",
              "queueBackedAttemptRequiresForegroundGenerationForAllMedia",
              "retiredQueueOwnerStillPublishesQueuedAfterTransportSuccess",
              "queueBackedServerFailureDoesNotMasqueradeAsConnectivityLoss",
              "queueLessTransportFailureKeepsReviewedNetworkTimeoutPresentation",
              "staleAttemptForSameScanCannotOverwriteReplacementGeneration",
              "recoveredBackgroundResultCanReplaceExactReleasedAttempt",
              "recoveredQueuedResultCanReplaceExactRetainedPresentation",
              "recoveredQueuedResultRejectsStaleOrMismatchedScan",
              "observationRejectionStaysTerminalAndOutOfNetworkCircuitForVisualAndNonVisual",
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
              "consentReapprovalResumesOnlyNewestOwnedFundedScan",
              "consentReapprovalSkipsUnownedOrUnfundedScans",
              "queueDiagnosticsExportOmitsPrivateAndFreeFormValues",
              "queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred",
              "testEnqueueCapture_WithValidData_PersistsQueuedScan"
            ]),
            suite("Onboarding Consent Recovery Tests"; [
              "testCompleteOnboardingResumesConsentBlockedScanForCurrentAccount",
              "testCompleteOnboardingDoesNotResumeWithoutCurrentAccount"
            ]),
            suite("SyncStateManagerTests"; [
              "generationFenceTest"
            ]),
            suite("Scan connectivity failure policy"; [
              "connectivityFailuresSelectQueueOnlyAdmission",
              "authenticationAndTrustFailuresRemainFailClosed",
              "secureTransportFailuresUseOnlyDurableRecovery"
            ]),
            suite("Capture workspace staging"; [
              "exhaustedImageImportAdmissionBlocksBeforePickerAndCrop",
              "automaticSingleCaptureFencesTheIdentifyTray",
              "requiredCropStateFencesCaptureChromeBeforePresentation"
            ]),
            suite("Capture scan dependencies"; [
              "testLifecycleInterruptionFencesOverlappingStillCapture",
              "testLifecycleInterruptionCancelsVideoWaitingOnAdmission"
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
            suite("ScansSharedPolicyTests"; [
              "queuedSnapshotRecoveryRespectsDurableAndNetworkPolicy"
            ]),
            suite("Network Client Tests"; [
              "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON",
              "queueBackedIdentifyReturnsFirstTransportFailureWithoutInlineReplay",
              "queueLessIdentifyRetainsOneReviewedInlineTransportReplay",
              "testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry",
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
              "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload",
              "testUploadStagedVideoFilesRejectsEmptyFileBeforeSigning",
              "testCommunityRequestSendsStableAIIdempotencyKey",
              "testCommunityRequestRejectsUnconfirmedSuccessResponse",
              "testMissingOwnerShareStateClearsStaleLocalPublication"
            ]),
            suite("Explore Media Incident Endpoints"; [
              "testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary",
              "testExploreMediaIncidentsRejectsUnknownSuccessShape"
            ]),
            suite("Explore Share State Endpoints"; [
              "testGetExploreShareStateRejectsUnconfirmedState",
              "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
            ]),
            suite("InsightShellRecordTests"; [
              "testMissingDifferentRecordClearsStaleScanBoundState",
              "testRecordSwitchInvalidatesPriorActionGeneration"
            ]),
            suite("InsightShellPresentationTests"; [
              "testResetMonotonicallyInvalidatesScanBoundRequests"
            ]),
            suite("InsightFieldNotesStateTests"; [
              "testFieldNotesRejectChangedPresentationIdentity",
              "testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty",
              "testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes",
              "testShareComposerFieldNotesSyncImmediatelyIntoInsightState"
            ]),
            suite("InsightShellCapabilitiesTests"; [
              "testTopMenuHidesConfirmAndReviewForStrongNonCompetitiveCandidates",
              "testTopMenuShowsConfirmAndReviewForVisibleCompetitiveCandidates"
            ]),
            suite("InsightContentActionsTests"; [
              "testPreferredNameRejectsStalePresentationGeneration"
            ]),
            suite("InsightSharingPresentationTests"; [
              "testExploreSharingRequiresExactEngineAndRecordIdentity"
            ]),
            suite("InsightQueuedHandoffTests"; [
              "testQueuedRefreshRejectsChangedPresentationIdentity",
              "testQueuedPresentationSwitchInvalidatesPriorQueueIdentity",
              "testQueuedPromotionRejectsChangedPresentationIdentity",
              "testQueuedPresentationPrefersPersistedCompletionOverStaleRoute"
            ]),
            suite("InsightQueuedRetryPresentationTests"; [
              "testQueuedPresentationRemainsQueuedWhenCompletionIsAbsent"
            ]),
            suite("FieldChatAPIModelsTests"; [
              "explorePostRequestUsesPostIdentifierContract"
            ]),
            suite("FieldChatViewModelStateTests"; [
              "testTransientOwnedScanReadinessKeepsChatEntryRetryable",
              "testFieldChatRejectsStaleSubjectCompletion"
            ]),
            suite("FieldChatPresentationPreparationTests"; [
              "testConcurrentPresentationRequestsSharePreparationResult",
              "testFieldChatReplacesPreparationForChangedSubject"
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
  "SyncStateManagerTests" \
  "Explore Media Incident Endpoints" \
  "Explore Share State Endpoints"; do
  write_test_tree "$omitted_suite"
  assert_rejected "A result missing $omitted_suite"
done

required_cases=(
  "decodedButUnusableSuccessEnvelopeRemainsRecoverable"
  "consentRequiredFailuresStayOutOfNetworkCircuitForVisualAndNonVisual"
  "providerAdmissionFailuresStayOutOfNetworkCircuitForVisualAndNonVisual"
  "connectivityFailuresSelectQueueOnlyAdmission"
  "authenticationAndTrustFailuresRemainFailClosed"
  "secureTransportFailuresUseOnlyDurableRecovery"
  "exhaustedImageImportAdmissionBlocksBeforePickerAndCrop"
  "automaticSingleCaptureFencesTheIdentifyTray"
  "requiredCropStateFencesCaptureChromeBeforePresentation"
  "testLifecycleInterruptionFencesOverlappingStillCapture"
  "testLifecycleInterruptionCancelsVideoWaitingOnAdmission"
  "queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual"
  "queueBackedAttemptRequiresForegroundGenerationForAllMedia"
  "retiredQueueOwnerStillPublishesQueuedAfterTransportSuccess"
  "queueBackedServerFailureDoesNotMasqueradeAsConnectivityLoss"
  "queueLessTransportFailureKeepsReviewedNetworkTimeoutPresentation"
  "staleAttemptForSameScanCannotOverwriteReplacementGeneration"
  "recoveredBackgroundResultCanReplaceExactReleasedAttempt"
  "recoveredQueuedResultCanReplaceExactRetainedPresentation"
  "recoveredQueuedResultRejectsStaleOrMismatchedScan"
  "observationRejectionStaysTerminalAndOutOfNetworkCircuitForVisualAndNonVisual"
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
  "consentReapprovalResumesOnlyNewestOwnedFundedScan"
  "consentReapprovalSkipsUnownedOrUnfundedScans"
  "testCompleteOnboardingResumesConsentBlockedScanForCurrentAccount"
  "testCompleteOnboardingDoesNotResumeWithoutCurrentAccount"
  "queueDiagnosticsExportOmitsPrivateAndFreeFormValues"
  "queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred"
  "completedInferenceAndQueueDeletionCommitTogether"
  "queuedSnapshotRecoveryRespectsDurableAndNetworkPolicy"
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
  "queueBackedIdentifyReturnsFirstTransportFailureWithoutInlineReplay"
  "queueLessIdentifyRetainsOneReviewedInlineTransportReplay"
  "testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry"
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
)

for omitted_case in "${required_cases[@]}"; do
  write_test_tree "" "$omitted_case"
  assert_rejected "A result missing $omitted_case"
done

for skipped_case in "${required_cases[@]}"; do
  write_test_tree
  jq \
    --arg skipped_case "$skipped_case" \
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

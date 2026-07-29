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
          name: ($name + "()"),
          result: "Passed"
        };
      def suite($name; $case_names):
        {
          nodeType: "Test Suite",
          name: $name,
          result: "Passed",
          children: (
            $case_names
            | map(select(. != $omitted_case))
            | map(test_case(.))
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
              "decodedButUnusableSuccessEnvelopeRemainsRecoverable"
            ]),
            suite("OfflineQueueManagerTests"; [
              "generationFenceTest",
              "backgroundInferencePreservesRecoverableHTTPFailures",
              "testEnqueueCapture_WithValidData_PersistsQueuedScan"
            ]),
            suite("SyncStateManagerTests"; [
              "generationFenceTest"
            ]),
            suite("BackgroundDatabaseActorTests"; [
              "generatedBackgroundResultRejectsMalformedSuccessBody",
              "generatedConfidenceZeroBackgroundResultIsTerminal"
            ]),
            suite("Offline Queued Scan Deletion Tests"; [
              "completedInferenceAndQueueDeletionCommitTogether"
            ]),
            suite("Network Client Tests"; [
              "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON",
              "testExploreShareSendsStableAIIdempotencyKey",
              "testExploreShareRejectsContradictorySuccessResponses",
              "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload",
              "testCommunityRequestSendsStableAIIdempotencyKey",
              "testCommunityRequestRejectsUnconfirmedSuccessResponse",
              "testGetExploreShareStateRejectsUnconfirmedState",
              "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
            ]),
            suite("InsightChatTests"; [
              "explorePostRequestUsesPostIdentifierContract",
              "testTransientOwnedScanReadinessKeepsChatEntryRetryable",
              "testConcurrentPresentationRequestsSharePreparationResult"
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
  "generatedBackgroundResultRejectsMalformedSuccessBody"
  "generatedConfidenceZeroBackgroundResultIsTerminal"
  "backgroundInferencePreservesRecoverableHTTPFailures"
  "testEnqueueCapture_WithValidData_PersistsQueuedScan"
  "completedInferenceAndQueueDeletionCommitTogether"
  "testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON"
  "testExploreShareSendsStableAIIdempotencyKey"
  "testExploreShareRejectsContradictorySuccessResponses"
  "testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload"
  "testCommunityRequestSendsStableAIIdempotencyKey"
  "testCommunityRequestRejectsUnconfirmedSuccessResponse"
  "testGetExploreShareStateRejectsUnconfirmedState"
  "testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest"
  "explorePostRequestUsesPostIdentifierContract"
  "testTransientOwnedScanReadinessKeepsChatEntryRetryable"
  "testConcurrentPresentationRequestsSharePreparationResult"
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

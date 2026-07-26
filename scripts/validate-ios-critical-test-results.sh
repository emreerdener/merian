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
' "$summary_path" >/dev/null; then
  echo "The complete iOS unit-test target did not report a passing, non-empty run." >&2
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

echo "Critical iOS concurrency suites reported passed test cases."

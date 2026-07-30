#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-ios-focused-test-results.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-focused-ios-test-results.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

summary_path="$tmp_dir/summary.json"
test_tree_path="$tmp_dir/tests.json"
suite_name="merianUITests"
case_name="testQueuedAudioScanRetainsAudioAcrossCompletionHandoff"

write_summary() {
  local result="${1:-Passed}"
  local total="${2:-1}"
  local passed="${3:-1}"
  local failed="${4:-0}"
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
  local reported_suite="${1:-$suite_name}"
  local reported_case="${2:-$case_name}"
  local result="${3:-Passed}"
  local duplicate="${4:-false}"

  jq -n \
    --arg suite "$reported_suite" \
    --arg case_name "$reported_case" \
    --arg result "$result" \
    --argjson duplicate "$duplicate" \
    '{
      testNodes: [
        {
          nodeType: "Test Suite",
          name: $suite,
          result: $result,
          children: (
            [{
              nodeType: "Test Case",
              name: ($case_name + "()"),
              result: $result
            }]
            + (
              if $duplicate then
                [{
                  nodeType: "Test Case",
                  name: ($case_name + "()"),
                  result: $result
                }]
              else
                []
              end
            )
          )
        }
      ]
    }' > "$test_tree_path"
}

assert_accepted() {
  local label="$1"
  if ! bash "$validator" \
    "$summary_path" \
    "$test_tree_path" \
    "$suite_name" \
    "$case_name" >/dev/null 2>&1; then
    fail "$label should have been accepted."
  fi
}

assert_rejected() {
  local label="$1"
  if bash "$validator" \
    "$summary_path" \
    "$test_tree_path" \
    "$suite_name" \
    "$case_name" >/dev/null 2>&1; then
    fail "$label should have been rejected."
  fi
}

bash -n "$validator"

write_summary
write_test_tree
assert_accepted "An exact one-case pass"

jq \
  --arg case_name "$case_name" \
  '(.testNodes[0].children[0].name) = $case_name' \
  "$test_tree_path" > "$tmp_dir/tests-without-parentheses.json"
mv "$tmp_dir/tests-without-parentheses.json" "$test_tree_path"
assert_accepted "An exact one-case pass without XCTest parentheses"

write_summary Failed 1 0 1
write_test_tree "$suite_name" "$case_name" Failed
assert_rejected "A failed focused run"

write_summary Passed 2 2 0
write_test_tree
assert_rejected "A summary reporting more than one test"

write_summary Passed 1 0 0 1
write_test_tree "$suite_name" "$case_name" Skipped
assert_rejected "A skipped focused run"

write_summary
write_test_tree "$suite_name" "$case_name" Skipped
assert_rejected "A passing summary contradicted by a skipped test tree"

write_summary
write_test_tree
jq \
  '(.testNodes[0].result) = "Failed"' \
  "$test_tree_path" > "$tmp_dir/failed-suite.json"
mv "$tmp_dir/failed-suite.json" "$test_tree_path"
assert_rejected "A passing case inside a failed exact suite"

write_summary
write_test_tree
jq \
  '.testNodes += [(.testNodes[0] | .children = [])]' \
  "$test_tree_path" > "$tmp_dir/duplicated-suite.json"
mv "$tmp_dir/duplicated-suite.json" "$test_tree_path"
assert_rejected "A duplicated exact suite"

write_summary
write_test_tree "DifferentUITests"
assert_rejected "A different suite"

write_test_tree "$suite_name" "testDifferentCriticalFlow"
assert_rejected "A different test case"

write_test_tree "$suite_name" "$case_name" Passed true
assert_rejected "Duplicated focused test evidence"

printf '{invalid json\n' > "$test_tree_path"
assert_rejected "Malformed test-tree JSON"

printf '{invalid json\n' > "$summary_path"
write_test_tree
assert_rejected "Malformed summary JSON"

: > "$summary_path"
write_test_tree
assert_rejected "An empty summary"

echo "Focused iOS test-result validation tests passed."

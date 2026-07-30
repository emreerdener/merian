#!/usr/bin/env bash
set -euo pipefail

if (( $# != 4 )); then
  echo "Usage: $0 TEST_SUMMARY_JSON TEST_TREE_JSON SUITE_NAME TEST_CASE_NAME" >&2
  exit 2
fi

summary_path="$1"
test_tree_path="$2"
required_suite_name="$3"
required_case_name="$4"

for required_file in "$summary_path" "$test_tree_path"; do
  if [[ ! -s "$required_file" ]]; then
    echo "Missing or empty focused iOS test result file: $required_file" >&2
    exit 1
  fi
done

if [[ -z "$required_suite_name" || -z "$required_case_name" ]]; then
  echo "Focused iOS suite and test-case names must be non-empty." >&2
  exit 1
fi

if ! jq -e '
  .result == "Passed"
  and ((.totalTestCount | type) == "number")
  and (.totalTestCount == 1)
  and ((.passedTests | type) == "number")
  and (.passedTests == 1)
  and ((.failedTests | type) == "number")
  and (.failedTests == 0)
  and ((.skippedTests | type) == "number")
  and (.skippedTests == 0)
' "$summary_path" >/dev/null; then
  echo "The focused iOS test did not report exactly one passed, unskipped test case." >&2
  exit 1
fi

if ! jq -e \
  --arg required_suite "$required_suite_name" \
  --arg required_case "$required_case_name" \
  '
    [
      ..
      | objects
      | select(.nodeType? == "Test Case")
    ] as $all_cases
    | [
        ..
        | objects
        | select(
            .nodeType? == "Test Suite"
            and .name? == $required_suite
          )
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
      ] as $required_cases
    | ($all_cases | length) == 1
      and ($required_cases | length) == 1
      and ($all_cases[0].result? == "Passed")
  ' "$test_tree_path" >/dev/null; then
  echo \
    "Focused iOS test '$required_suite_name/$required_case_name' did not report one exact passed test case." \
    >&2
  exit 1
fi

echo "Focused iOS test '$required_suite_name/$required_case_name' reported exactly one passed test case."

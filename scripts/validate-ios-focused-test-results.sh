#!/usr/bin/env bash
set -euo pipefail

if (( $# < 4 )); then
  echo "Usage: $0 TEST_SUMMARY_JSON TEST_TREE_JSON SUITE_NAME TEST_CASE_NAME [TEST_CASE_NAME ...]" >&2
  exit 2
fi

summary_path="$1"
test_tree_path="$2"
required_suite_name="$3"
shift 3
required_case_names=("$@")
expected_test_count="${#required_case_names[@]}"
required_cases_json="$({
  printf '%s\n' "${required_case_names[@]}"
} | jq -Rsc 'split("\n")[:-1]')"

for required_file in "$summary_path" "$test_tree_path"; do
  if [[ ! -s "$required_file" ]]; then
    echo "Missing or empty focused iOS test result file: $required_file" >&2
    exit 1
  fi
done

if [[ -z "$required_suite_name" ]] \
  || printf '%s\n' "${required_case_names[@]}" | grep -Eq '^$'; then
  echo "Focused iOS suite and all test-case names must be non-empty." >&2
  exit 1
fi

if (( $(printf '%s\n' "${required_case_names[@]}" | sort -u | wc -l) \
      != expected_test_count )); then
  echo "Focused iOS test-case names must be unique." >&2
  exit 1
fi

if ! jq -e \
  --argjson expected_test_count "$expected_test_count" \
  '
  .result == "Passed"
  and ((.totalTestCount | type) == "number")
  and (.totalTestCount == $expected_test_count)
  and ((.passedTests | type) == "number")
  and (.passedTests == $expected_test_count)
  and ((.failedTests | type) == "number")
  and (.failedTests == 0)
  and ((.skippedTests | type) == "number")
  and (.skippedTests == 0)
' "$summary_path" >/dev/null; then
  echo "The focused iOS run did not report exactly $expected_test_count passed, unskipped test case(s)." >&2
  exit 1
fi

if ! jq -e \
  --arg required_suite "$required_suite_name" \
  --argjson required_cases "$required_cases_json" \
  --argjson expected_test_count "$expected_test_count" \
  '
    def normalized_case_name:
      if endswith("()") then .[0:-2] else . end;
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
      ] as $required_suites
    | [
        $required_suites[]
        | ..
        | objects
        | select(.nodeType? == "Test Case")
      ] as $suite_cases
    | ($required_suites | length) == 1
      and ($required_suites[0].result? == "Passed")
      and ($all_cases | length) == $expected_test_count
      and ($suite_cases | length) == $expected_test_count
      and ([$all_cases[].result?] | all(. == "Passed"))
      and (
        [$suite_cases[] | .name? | normalized_case_name] | sort
      ) == ($required_cases | sort)
      and ([$suite_cases[].result?] | all(. == "Passed"))
  ' "$test_tree_path" >/dev/null; then
  echo \
    "Focused iOS suite '$required_suite_name' did not report the exact required passed test set: ${required_case_names[*]}." \
    >&2
  exit 1
fi

echo "Focused iOS suite '$required_suite_name' reported the exact $expected_test_count-case passed test set."

#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 TEST_SUMMARY_JSON TEST_TREE_JSON XCODEBUILD_LOG" >&2
  exit 2
fi

summary_path="$1"
test_tree_path="$2"
xcodebuild_log_path="$3"

summary_has_failures() {
  jq -e '
    def failure_items:
      if (.testFailures? | type) == "array" then
        .testFailures[]
      elif (.testFailures? | type) == "object"
        and ((.testFailures | length) > 0) then
        .testFailures
      else
        empty
      end;
    [failure_items] | length > 0
  ' "$summary_path" >/dev/null 2>&1
}

if [[ -s "$summary_path" ]] && summary_has_failures; then
  jq -r '
    def failure_items:
      if (.testFailures? | type) == "array" then
        .testFailures[]
      elif (.testFailures? | type) == "object"
        and ((.testFailures | length) > 0) then
        .testFailures
      else
        empty
      end;
    failure_items
    | [
        "Test: \(.testName // "unknown")",
        "Target: \(.targetName // "unknown")",
        "Identifier: \(.testIdentifierString // .testIdentifierURL // "unknown")",
        "Failure: \(.failureText // "Failure details unavailable.")"
      ]
    | join("\n") + "\n"
  ' "$summary_path"
  exit 0
fi

tree_has_failed_tests() {
  jq -e '
    [
      ..
      | objects
      | select(
          .nodeType? == "Test Case"
          and .result? == "Failed"
        )
    ]
    | length > 0
  ' "$test_tree_path" >/dev/null 2>&1
}

if [[ -s "$test_tree_path" ]] && tree_has_failed_tests; then
  jq -r '
    ..
    | objects
    | select(
        .nodeType? == "Test Case"
        and .result? == "Failed"
      )
    | . as $test
    | [
        "Test: \($test.name)",
        "Identifier: \($test.nodeIdentifier // $test.nodeIdentifierURL // "unknown")",
        (
          [
            $test
            | ..
            | objects
            | select(.nodeType? == "Failure Message")
            | .name
          ]
          | if length > 0 then
              .[]
            else
              "Failure details unavailable in the test tree."
            end
        )
      ]
    | join("\n") + "\n"
  ' "$test_tree_path"
  exit 0
fi

if [[ ! -f "$xcodebuild_log_path" ]]; then
  echo "No readable xcresult failure or xcodebuild log was produced."
  exit 0
fi

if grep -E \
  "^.*\\.(swift|m|mm|c|cc|cpp|h):[0-9]+(:[0-9]+)?: (error|fatal error):|xcodebuild: error|clang: error:|ld: .*error:|Test Case .* failed|The following build commands failed|\\([0-9]+ failures\\)" \
  "$xcodebuild_log_path"; then
  exit 0
fi

tail -n 160 "$xcodebuild_log_path"

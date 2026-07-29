#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
extractor="$repo_root/scripts/extract-ios-test-failure-diagnostics.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-failure-diagnostics.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

summary_path="$tmp_dir/summary.json"
test_tree_path="$tmp_dir/tests.json"
xcodebuild_log_path="$tmp_dir/xcodebuild.log"
diagnostics_path="$tmp_dir/diagnostics.txt"

write_empty_tree() {
  jq -n '{testNodes: []}' > "$test_tree_path"
}

assert_diagnostics_contain() {
  local expected="$1"
  grep -Fq -- "$expected" "$diagnostics_path" \
    || fail "Diagnostics are missing: $expected"
}

jq -n '{
  testFailures: [
    {
      testName: "manifestContract()",
      targetName: "merianTests",
      testIdentifierString: "OfflineQueueManagerTests/manifestContract()",
      failureText: "Expectation failed: manifest was rejected"
    }
  ]
}' > "$summary_path"
write_empty_tree
printf '%s\n' '[RepliesDebug] expected fixture failure with error: injected' > "$xcodebuild_log_path"
bash "$extractor" \
  "$summary_path" \
  "$test_tree_path" \
  "$xcodebuild_log_path" > "$diagnostics_path"
assert_diagnostics_contain "Test: manifestContract()"
assert_diagnostics_contain "Failure: Expectation failed: manifest was rejected"
if grep -Fq "RepliesDebug" "$diagnostics_path"; then
  fail "Result-summary diagnostics were polluted by expected negative-path logs."
fi

jq -n '{
  testFailures: {
    testName: "singleFailure()",
    targetName: "merianTests",
    testIdentifierURL: "test://singleFailure",
    failureText: "Single object failure"
  }
}' > "$summary_path"
bash "$extractor" \
  "$summary_path" \
  "$test_tree_path" \
  "$xcodebuild_log_path" > "$diagnostics_path"
assert_diagnostics_contain "Test: singleFailure()"
assert_diagnostics_contain "Identifier: test://singleFailure"

jq -n '{testFailures: []}' > "$summary_path"
jq -n '{
  testNodes: [
    {
      nodeType: "Test Case",
      name: "treeFailure()",
      nodeIdentifier: "OfflineQueueManagerTests/treeFailure()",
      result: "Failed",
      children: [
        {
          nodeType: "Test Case Run",
          name: "Run 1",
          children: [
            {
              nodeType: "Failure Message",
              name: "OfflineQueueManagerTests.swift:42: expected true"
            }
          ]
        }
      ]
    }
  ]
}' > "$test_tree_path"
bash "$extractor" \
  "$summary_path" \
  "$test_tree_path" \
  "$xcodebuild_log_path" > "$diagnostics_path"
assert_diagnostics_contain "Test: treeFailure()"
assert_diagnostics_contain "OfflineQueueManagerTests.swift:42: expected true"

write_empty_tree
printf '%s\n' \
  '[error] CoreData: error: expected corruption fixture' \
  '/tmp/Merian/File.swift:12:7: error: cannot find value in scope' > "$xcodebuild_log_path"
bash "$extractor" \
  "$summary_path" \
  "$test_tree_path" \
  "$xcodebuild_log_path" > "$diagnostics_path"
assert_diagnostics_contain "File.swift:12:7: error: cannot find value in scope"
if grep -Fq "CoreData" "$diagnostics_path"; then
  fail "Fallback diagnostics included an unstructured expected Core Data log."
fi

echo "iOS test-failure diagnostic extraction tests passed."

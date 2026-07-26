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
  jq -n \
    --arg result "$result" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    '{
      result: $result,
      totalTestCount: $total,
      passedTests: $passed,
      failedTests: $failed
    }' > "$summary_path"
}

write_test_tree() {
  local omitted_suite="${1:-}"
  jq -n \
    --arg omitted "$omitted_suite" \
    '
      def suite($name):
        {
          nodeType: "Test Suite",
          name: $name,
          result: "Passed",
          children: [
            {
              nodeType: "Test Case",
              name: "generationFenceTest()",
              result: "Passed"
            }
          ]
        };
      {
        testNodes: (
          [
            suite("CameraManagerTests"),
            suite("Inference Engine Tests"),
            suite("OfflineQueueManagerTests"),
            suite("SyncStateManagerTests")
          ]
          | map(select(.name != $omitted))
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

write_summary "Passed" 4 4 0
for omitted_suite in \
  "CameraManagerTests" \
  "Inference Engine Tests" \
  "OfflineQueueManagerTests" \
  "SyncStateManagerTests"; do
  write_test_tree "$omitted_suite"
  assert_rejected "A result missing $omitted_suite"
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

echo "Critical iOS test-result validation tests passed."

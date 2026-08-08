#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$repo_root/scripts/ci-detect-ios-build-source-changes.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-scope-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_scope() {
  local expected="$1"
  local event_name="$2"
  shift 2

  local output
  if ! output="$(
    env \
      -u GITHUB_ACTIONS \
      -u GITHUB_EVENT_PATH \
      -u GITHUB_OUTPUT \
      -u GITHUB_STEP_SUMMARY \
      GITHUB_EVENT_NAME="$event_name" \
      bash "$detector" "$@"
  )"; then
    fail "Scope detector failed for event=${event_name}, files=$*"
  fi

  if ! grep -Fq "iOS build should_run=${expected}" <<<"$output"; then
    fail "Expected should_run=${expected} for event=${event_name}, files=$*. Output: $output"
  fi
}

assert_event_scope() {
  local expected="$1"
  local event_name="$2"
  local event_path="$3"
  local test_repo="$4"
  local head_sha="$5"

  local output
  if ! output="$(
    cd "$test_repo"
    env \
      GITHUB_ACTIONS=true \
      GITHUB_EVENT_NAME="$event_name" \
      GITHUB_EVENT_PATH="$event_path" \
      GITHUB_SHA="$head_sha" \
      GITHUB_OUTPUT="" \
      GITHUB_STEP_SUMMARY="" \
      bash "$detector"
  )"; then
    fail "Scope detector failed for event payload $event_path"
  fi

  if ! grep -Fq "iOS build should_run=${expected}" <<<"$output"; then
    fail "Expected event should_run=${expected}. Output: $output"
  fi
}

bash -n "$detector"

assert_scope false pull_request "docs/README.md"
assert_scope false pull_request "services/supabase/functions/identify/index.ts"
assert_scope true pull_request "apps/ios/Merian/Core/AI/InferenceEngine.swift"
assert_scope true pull_request "apps/watch/MerianWatch/MerianWatchApp.swift"
assert_scope true pull_request "Merian.xcodeproj/project.pbxproj"
assert_scope true pull_request "project.yml"
assert_scope true pull_request "Config.xcconfig"
assert_scope true pull_request "Makefile"
assert_scope true pull_request ".swiftlint.yml"
assert_scope true pull_request ".github/workflows/ios-build-and-test.yml"
assert_scope true pull_request ".github/workflows/ios-startup-safety.yml"
assert_scope true pull_request "scripts/check-ios-release-prep.sh"
assert_scope true pull_request "scripts/embed-ios-build-provenance.sh"
assert_scope true pull_request "scripts/validate-ios-exported-ipa.sh"
assert_scope true pull_request "scripts/validate-ios-privacy-manifest.sh"
assert_scope true pull_request "scripts/test-validate-ios-archive.sh"
assert_scope true pull_request "scripts/test-validate-ios-exported-ipa.sh"
assert_scope true pull_request "scripts/test-validate-ios-privacy-manifest.sh"
assert_scope true pull_request "scripts/ios-release-source-fingerprint.sh"
assert_scope true pull_request "scripts/check-ios-project-source-membership.sh"
assert_scope true pull_request "scripts/test-ios-project-source-membership.sh"
assert_scope true pull_request "scripts/config/ios-event-routing-singleton-allowlist.txt"
assert_scope true pull_request "scripts/validate-ios-focused-test-results.sh"
assert_scope true pull_request "scripts/test-validate-ios-focused-test-results.sh"
assert_scope true workflow_dispatch "docs/README.md"
assert_scope true merge_group "docs/README.md"

test_repo="$tmp_dir/repository"
mkdir -p "$test_repo/apps/ios" "$test_repo/docs"
git -C "$test_repo" init -q
git -C "$test_repo" config user.email "ios-scope-test@example.invalid"
git -C "$test_repo" config user.name "iOS Scope Test"
printf 'initial\n' > "$test_repo/apps/ios/Tracked.swift"
printf 'initial\n' > "$test_repo/docs/README.md"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm "Initial"

docs_base="$(git -C "$test_repo" rev-parse HEAD)"
printf 'docs change\n' >> "$test_repo/docs/README.md"
git -C "$test_repo" add docs/README.md
git -C "$test_repo" commit -qm "Docs only"
docs_head="$(git -C "$test_repo" rev-parse HEAD)"
docs_event="$tmp_dir/docs-push.json"
printf '{"before":"%s","after":"%s"}\n' \
  "$docs_base" \
  "$docs_head" > "$docs_event"
assert_event_scope false push "$docs_event" "$test_repo" "$docs_head"

delete_base="$docs_head"
git -C "$test_repo" rm -q apps/ios/Tracked.swift
git -C "$test_repo" commit -qm "Delete iOS input"
delete_head="$(git -C "$test_repo" rev-parse HEAD)"
delete_event="$tmp_dir/delete-push.json"
printf '{"before":"%s","after":"%s"}\n' \
  "$delete_base" \
  "$delete_head" > "$delete_event"
assert_event_scope true push "$delete_event" "$test_repo" "$delete_head"

missing_event="$tmp_dir/missing-range.json"
printf '{"before":"1111111111111111111111111111111111111111","after":"2222222222222222222222222222222222222222"}\n' \
  > "$missing_event"
assert_event_scope true push "$missing_event" "$test_repo" "$delete_head"

pr_repo="$tmp_dir/pull-request-repository"
mkdir -p "$pr_repo/apps/ios" "$pr_repo/docs"
git -C "$pr_repo" init -q
git -C "$pr_repo" config user.email "ios-scope-test@example.invalid"
git -C "$pr_repo" config user.name "iOS Scope Test"
printf 'initial\n' > "$pr_repo/apps/ios/Tracked.swift"
printf 'initial\n' > "$pr_repo/docs/README.md"
git -C "$pr_repo" add .
git -C "$pr_repo" commit -qm "Common ancestor"
common_ancestor="$(git -C "$pr_repo" rev-parse HEAD)"

printf 'base-only iOS change\n' >> "$pr_repo/apps/ios/Tracked.swift"
git -C "$pr_repo" add apps/ios/Tracked.swift
git -C "$pr_repo" commit -qm "Advance base with iOS work"
pr_base="$(git -C "$pr_repo" rev-parse HEAD)"

git -C "$pr_repo" checkout -qb pull-request-head "$common_ancestor"
printf 'pull-request docs change\n' >> "$pr_repo/docs/README.md"
git -C "$pr_repo" add docs/README.md
git -C "$pr_repo" commit -qm "Pull request docs only"
pr_docs_head="$(git -C "$pr_repo" rev-parse HEAD)"
pr_docs_event="$tmp_dir/docs-pull-request.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$pr_base" \
  "$pr_docs_head" > "$pr_docs_event"
assert_event_scope false pull_request "$pr_docs_event" "$pr_repo" "$pr_docs_head"

printf 'pull-request iOS change\n' > "$pr_repo/apps/ios/New.swift"
git -C "$pr_repo" add apps/ios/New.swift
git -C "$pr_repo" commit -qm "Pull request iOS work"
pr_ios_head="$(git -C "$pr_repo" rev-parse HEAD)"
pr_ios_event="$tmp_dir/ios-pull-request.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$pr_base" \
  "$pr_ios_head" > "$pr_ios_event"
assert_event_scope true pull_request "$pr_ios_event" "$pr_repo" "$pr_ios_head"

echo "iOS build scope detector tests passed."

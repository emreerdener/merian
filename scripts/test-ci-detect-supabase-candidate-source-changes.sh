#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$repo_root/scripts/ci-detect-supabase-candidate-source-changes.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-supabase-scope-tests.XXXXXX")"
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

  if ! grep -Fq "Supabase candidate should_run=${expected}" <<< "$output"; then
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

  if ! grep -Fq "Supabase candidate should_run=${expected}" <<< "$output"; then
    fail "Expected event should_run=${expected}. Output: $output"
  fi
}

bash -n "$detector"

# Complete roots read or scanned by the candidate suite.
assert_scope true pull_request "services/supabase/functions/identify/index.ts"
assert_scope true pull_request "apps/ios/Merian/Core/Network/SupabaseManager.swift"
assert_scope true pull_request "apps/ios/MerianTests/Core/Network/SupabaseManagerTests.swift"
assert_scope true pull_request "apps/ios/Merian/Core/Security/ConsentManager.swift"
assert_scope true pull_request "apps/admin/lib/new-edge-caller.ts"
assert_scope true pull_request "apps/web/app/privacy/page.tsx"
assert_scope true pull_request "docs/backend-and-data/05-api-contracts.md"
assert_scope true pull_request ".github/workflows/ios-build-and-test.yml"
assert_scope true pull_request ".github/dependabot.yml"
assert_scope true pull_request "scripts/ci-run-summary.sh"
assert_scope true pull_request "README.md"
assert_scope true pull_request "CHANGELOG.md"
assert_scope true pull_request "Makefile"

# Build-only roots not inspected by this validation gate stay inexpensive.
assert_scope false pull_request "project.yml"
assert_scope false pull_request "Config.xcconfig"
assert_scope false pull_request "Merian.xcodeproj/project.pbxproj"
assert_scope false pull_request ".swiftlint.yml"
assert_scope true pull_request "future-contract-root/schema.json"

# Manual, merge-queue, and reusable production invocations are never scoped out.
assert_scope true workflow_dispatch "project.yml"
assert_scope true merge_group "project.yml"
assert_scope true push "project.yml"

test_repo="$tmp_dir/repository"
mkdir -p "$test_repo/apps/ios" "$test_repo/docs"
git -C "$test_repo" init -q
git -C "$test_repo" config user.email "supabase-scope-test@example.invalid"
git -C "$test_repo" config user.name "Supabase Scope Test"
printf 'initial\n' > "$test_repo/project.yml"
printf 'initial\n' > "$test_repo/apps/ios/Tracked.swift"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm "Initial"

build_base="$(git -C "$test_repo" rev-parse HEAD)"
printf 'build only\n' >> "$test_repo/project.yml"
git -C "$test_repo" add project.yml
git -C "$test_repo" commit -qm "Build only"
build_head="$(git -C "$test_repo" rev-parse HEAD)"
build_event="$tmp_dir/build-pull-request.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$build_base" \
  "$build_head" > "$build_event"
assert_event_scope false pull_request "$build_event" "$test_repo" "$build_head"

delete_base="$build_head"
git -C "$test_repo" rm -q apps/ios/Tracked.swift
git -C "$test_repo" commit -qm "Delete contract input"
delete_head="$(git -C "$test_repo" rev-parse HEAD)"
delete_event="$tmp_dir/delete-pull-request.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$delete_base" \
  "$delete_head" > "$delete_event"
assert_event_scope true pull_request "$delete_event" "$test_repo" "$delete_head"

missing_event="$tmp_dir/missing-range.json"
printf '{"pull_request":{"base":{"sha":"1111111111111111111111111111111111111111"},"head":{"sha":"2222222222222222222222222222222222222222"}}}\n' \
  > "$missing_event"
assert_event_scope true pull_request "$missing_event" "$test_repo" "$delete_head"

pr_repo="$tmp_dir/pull-request-repository"
mkdir -p "$pr_repo/apps/ios"
git -C "$pr_repo" init -q
git -C "$pr_repo" config user.email "supabase-scope-test@example.invalid"
git -C "$pr_repo" config user.name "Supabase Scope Test"
printf 'initial\n' > "$pr_repo/project.yml"
printf 'initial\n' > "$pr_repo/apps/ios/Tracked.swift"
git -C "$pr_repo" add .
git -C "$pr_repo" commit -qm "Common ancestor"
common_ancestor="$(git -C "$pr_repo" rev-parse HEAD)"

printf 'base-only contract change\n' >> "$pr_repo/apps/ios/Tracked.swift"
git -C "$pr_repo" add apps/ios/Tracked.swift
git -C "$pr_repo" commit -qm "Advance base"
pr_base="$(git -C "$pr_repo" rev-parse HEAD)"

git -C "$pr_repo" checkout -qb pull-request-head "$common_ancestor"
printf 'pull-request build change\n' >> "$pr_repo/project.yml"
git -C "$pr_repo" add project.yml
git -C "$pr_repo" commit -qm "PR build only"
pr_head="$(git -C "$pr_repo" rev-parse HEAD)"
pr_event="$tmp_dir/merge-base-pull-request.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$pr_base" \
  "$pr_head" > "$pr_event"
assert_event_scope false pull_request "$pr_event" "$pr_repo" "$pr_head"

echo "Supabase candidate scope detector tests passed."

#!/usr/bin/env bash
set -euo pipefail

detector="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/detect_production_source_changes.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-production-scope-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
cd "$test_root"
git init -q
git config user.name "Production Scope Test"
git config user.email "production-scope@example.invalid"
mkdir -p docs services/supabase/functions
printf 'initial\n' > docs/README.md
printf 'initial\n' > services/supabase/functions/example.ts
git add .
git commit -qm initial
baseline="$(git rev-parse HEAD)"

export GITHUB_EVENT_NAME=push
export DEPLOY_BASE_SHA="$baseline"
export PRODUCTION_SOURCE_PATHS=$'services/supabase/**\n.github/workflows/deploy.yml\napps/ios/Merian/Core/Security/**'
export GITHUB_OUTPUT="$test_root/output"
export GITHUB_STEP_SUMMARY="$test_root/summary"

expect_scope() {
  local expected="$1"
  export GITHUB_SHA="$(git rev-parse HEAD)"
  : > "$GITHUB_OUTPUT"
  bash "$detector" >/dev/null
  if [[ "$(cat "$GITHUB_OUTPUT")" != "should_deploy=$expected" ]]; then
    echo "Expected production scope $expected" >&2
    exit 1
  fi
}

expect_failure() {
  if bash "$detector" >/dev/null 2>&1; then
    echo "Unsafe production scope unexpectedly succeeded" >&2
    exit 1
  fi
}

expect_scope false
printf 'docs only\n' >> docs/README.md
git add docs
git commit -qm docs
expect_scope false
# A backend update followed by a docs-only push must still deploy the update.
printf 'backend\n' >> services/supabase/functions/example.ts
git add services
git commit -qm backend
backend_sha="$(git rev-parse HEAD)"
printf 'newer docs\n' >> docs/README.md
git add docs
git commit -qm newer-docs
expect_scope true
# The queued docs candidate becomes a no-op once the prior backend job deploys.
export DEPLOY_BASE_SHA="$backend_sha"
expect_scope false

# More than GitHub's path-filter window, including a nested security owner.
export DEPLOY_BASE_SHA="$(git rev-parse HEAD)"
for ((i=0; i<305; i++)); do printf 'doc\n' > "docs/$i.md"; done
mkdir -p apps/ios/Merian/Core/Security/Nested
printf 'security\n' > apps/ios/Merian/Core/Security/Nested/Owner.swift
git add .
git commit -qm large-push
expect_scope true

export DEPLOY_BASE_SHA="$(git rev-parse HEAD)"
git mv services/supabase/functions/example.ts docs/moved.ts
git commit -qm move-out-of-production
expect_scope true
export DEPLOY_BASE_SHA="$(git rev-parse HEAD)"
git rm -q apps/ios/Merian/Core/Security/Nested/Owner.swift
git commit -qm delete-owner
expect_scope true

export DEPLOY_BASE_SHA=""
expect_failure
export DEPLOY_BASE_SHA=1111111111111111111111111111111111111111
expect_failure
export DEPLOY_BASE_SHA="$(git rev-parse HEAD)"
export GITHUB_SHA="$baseline"
expect_failure
export GITHUB_EVENT_NAME=pull_request
expect_failure
# Manual deployment is an explicit full-deployment selection, even without history.
export GITHUB_EVENT_NAME=workflow_dispatch DEPLOY_BASE_SHA=""
expect_scope true
export PRODUCTION_SOURCE_PATHS=""
expect_failure
echo "Production scope regression tests passed."

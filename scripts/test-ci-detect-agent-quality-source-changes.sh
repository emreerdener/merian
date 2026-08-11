#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions injects GITHUB_OUTPUT into every step. These tests assert the
# detector's stdout fallback, so keep the runner channel out of child processes.
unset GITHUB_OUTPUT

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scope_script="$repo_root/scripts/ci-detect-agent-quality-source-changes.sh"

assert_output() {
  local expected_run="$1"
  local expected_suites="$2"
  shift 2
  local output
  output="$(EVENT_NAME=pull_request bash "$scope_script" "$@")"
  grep -Fqx "should_run=$expected_run" <<< "$output"
  grep -Fqx "suites=$expected_suites" <<< "$output"
}

assert_output true '["ios"]' skills/merian-ios/SKILL.md
assert_output true '["ios","supabase"]' \
  skills/merian-ios/SKILL.md skills/merian-supabase/SKILL.md
assert_output true '["all"]' AGENTS.md
assert_output true '["all"]' skills/merian-unknown/SKILL.md
assert_output false '[]' apps/ios/Merian/Features/Explore/ExploreView.swift

schedule_output="$(EVENT_NAME=schedule bash "$scope_script")"
grep -Fqx 'should_run=true' <<< "$schedule_output"
grep -Fqx 'suites=["all"]' <<< "$schedule_output"

manual_output="$(
  EVENT_NAME=workflow_dispatch REQUESTED_SUITE=release bash "$scope_script"
)"
grep -Fqx 'should_run=true' <<< "$manual_output"
grep -Fqx 'suites=["release"]' <<< "$manual_output"

push_output="$(EVENT_NAME=push bash "$scope_script")"
grep -Fqx 'should_run=false' <<< "$push_output"
grep -Fqx 'suites=[]' <<< "$push_output"

echo "Agent Quality scope detection tests passed."

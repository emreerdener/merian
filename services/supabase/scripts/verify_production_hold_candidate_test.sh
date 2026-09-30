#!/usr/bin/env bash
set -euo pipefail

verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_production_hold_candidate.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-hold-candidate-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir "$test_root/repo"
cd "$test_root/repo"
git init -q
git config user.name "Hold Candidate Test"
git config user.email "hold-candidate@example.invalid"
echo initial > source
git add source
git commit -qm initial
initial="$(git rev-parse HEAD)"
git update-ref refs/remotes/origin/main "$initial"
export GITHUB_REF=refs/heads/main GITHUB_SHA="$initial"
export GITHUB_OUTPUT="$test_root/output" GITHUB_STEP_SUMMARY="$test_root/summary"

check_result() {
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  bash "$verifier" > "$test_root/log" 2>&1
  grep -qx "status=$1" "$GITHUB_OUTPUT"
  test "$(tail -n 2 "$GITHUB_OUTPUT" | head -n 1)" = "current=$2"
}
expect_failure() {
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  if bash "$verifier" > "$test_root/log" 2>&1; then
    echo "Unsafe hold candidate unexpectedly succeeded" >&2
    exit 1
  fi
  test "$(cat "$GITHUB_OUTPUT")" = 'current=false'
  test ! -s "$GITHUB_STEP_SUMMARY"
}

check_result current true
# Exact workflow SHA, main ref, and cleanliness must hold before any no-op.
GITHUB_REF=refs/heads/feature expect_failure
GITHUB_SHA=1111111111111111111111111111111111111111 expect_failure
echo dirty >> source
expect_failure
git checkout -- source
echo untracked > extra
expect_failure
rm extra
git update-ref -d refs/remotes/origin/main
expect_failure
git update-ref refs/remotes/origin/main "$initial"
# A clean older candidate is a successful no-op only after main includes it.
echo newer >> source
git commit -qam newer
newer="$(git rev-parse HEAD)"
git update-ref refs/remotes/origin/main "$newer"
git checkout -q --detach "$initial"
check_result superseded false
grep -q "$initial" "$GITHUB_STEP_SUMMARY"
grep -q "$newer" "$GITHUB_STEP_SUMMARY"
! grep -q 'current=true' "$GITHUB_OUTPUT"
echo dirty >> source
expect_failure
git checkout -- source
GITHUB_REF=refs/heads/feature expect_failure
GITHUB_SHA="$newer" expect_failure
# Rewritten or diverged main cannot be treated as ordinary supersession.
echo divergent >> source
git commit -qam divergent
export GITHUB_SHA="$(git rev-parse HEAD)"
expect_failure
# A checkout ahead of the fetched main ref must also fail closed.
git checkout -q --detach "$newer"
export GITHUB_SHA="$newer"
git update-ref refs/remotes/origin/main "$initial"
expect_failure
echo "Production hold candidate regression tests passed."

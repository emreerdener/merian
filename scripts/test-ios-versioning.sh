#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-versioning-tests.XXXXXX")"
fixture_repo="$test_root/repository"
trap 'rm -rf "$test_root"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "expected command to fail: $*"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "expected failure to contain '$expected'; actual: $output"
}

assert_succeeds_with() {
  local expected="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    fail "expected command to succeed: $*; actual: $output"
  fi
  grep -Fq -- "$expected" <<<"$output" \
    || fail "expected success to contain '$expected'; actual: $output"
}

mkdir -p "$fixture_repo/scripts"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.name "Merian Release Tests"
git -C "$fixture_repo" config user.email "release-tests@example.invalid"

cat > "$fixture_repo/project.yml" <<'YAML'
name: Merian
settings:
  base:
    CODE_SIGN_STYLE: Automatic
    MARKETING_VERSION: 1.0.3
    CURRENT_PROJECT_VERSION: 275
    VERSIONING_SYSTEM: apple-generic
YAML
printf '%s\n' 'let fixtureSource = true' > "$fixture_repo/source.swift"
cp "$repo_root/scripts/ios-release-source-fingerprint.sh" \
  "$fixture_repo/scripts/ios-release-source-fingerprint.sh"
git -C "$fixture_repo" add -A
git -C "$fixture_repo" commit -q -m "fixture"
fixture_revision="$(git -C "$fixture_repo" rev-parse HEAD)"

for script in \
  check-ios-release-prep.sh \
  ios-release-source-fingerprint.sh \
  embed-ios-build-provenance.sh \
  validate-ios-archive.sh \
  validate-ios-exported-ipa.sh \
  hash-ios-archive.sh
do
  bash -n "$repo_root/scripts/$script"
done

run_validation_archive() {
  env \
    MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
    MERIAN_PROJECT_ROOT="$fixture_repo" \
    MERIAN_IOS_VALIDATION_ARCHIVE=1 \
    MERIAN_EXPECTED_SOURCE_REVISION="${EXPECTED_REVISION:-$fixture_revision}" \
    CODE_SIGNING_ALLOWED="${VALIDATION_SIGNING_ALLOWED:-NO}" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    DEVELOPMENT_TEAM= \
    MARKETING_VERSION="${RESOLVED_VERSION:-1.0.3}" \
    CURRENT_PROJECT_VERSION="${RESOLVED_BUILD:-275}" \
    bash "$repo_root/scripts/check-ios-release-prep.sh"
}

run_organizer_archive() {
  env \
    MERIAN_FORCE_RELEASE_PREP_CHECK=1 \
    MERIAN_PROJECT_ROOT="$fixture_repo" \
    CODE_SIGN_STYLE="${ORGANIZER_SIGN_STYLE:-Automatic}" \
    DEVELOPMENT_TEAM="${ORGANIZER_TEAM-ABC123DE45}" \
    MARKETING_VERSION="${RESOLVED_VERSION:-1.0.3}" \
    CURRENT_PROJECT_VERSION="${RESOLVED_BUILD:-275}" \
    REVENUECAT_API_KEY="${REVENUECAT_KEY:-appl_fixture_production_key}" \
    bash "$repo_root/scripts/check-ios-release-prep.sh"
}

assert_succeeds_with "Unsigned validation-only Release archive authorized" \
  run_validation_archive
EXPECTED_REVISION=0000000000000000000000000000000000000000 \
  assert_fails_with "does not match expected source" run_validation_archive
VALIDATION_SIGNING_ALLOWED=YES \
  assert_fails_with "restricted to unsigned archives" run_validation_archive
RESOLVED_BUILD=276 \
  assert_fails_with "changed or allocated CURRENT_PROJECT_VERSION" run_validation_archive

assert_succeeds_with "Xcode Organizer Release archive authorized" \
  run_organizer_archive
assert_succeeds_with "keep Manage version and build number enabled" \
  run_organizer_archive
ORGANIZER_SIGN_STYLE=Manual \
  assert_fails_with "CODE_SIGN_STYLE must remain Automatic" run_organizer_archive
ORGANIZER_TEAM= \
  assert_fails_with "DEVELOPMENT_TEAM is missing or malformed" run_organizer_archive
RESOLVED_VERSION=1.0.4 \
  assert_fails_with "expected tracked version 1.0.3" run_organizer_archive
RESOLVED_BUILD=276 \
  assert_fails_with "expected tracked baseline 275" run_organizer_archive
REVENUECAT_KEY=test_fixture \
  assert_fails_with "RevenueCat Test Store key" run_organizer_archive
REVENUECAT_KEY=appl_... \
  assert_fails_with "placeholder" run_organizer_archive

git -C "$fixture_repo" update-index --assume-unchanged source.swift
assert_fails_with "assume-unchanged or skip-worktree" \
  env MERIAN_PROJECT_ROOT="$fixture_repo" \
  bash "$repo_root/scripts/ios-release-source-fingerprint.sh"
git -C "$fixture_repo" update-index --no-assume-unchanged source.swift
printf '%s\n' 'let fixtureSource = false' > "$fixture_repo/source.swift"
assert_fails_with "source checkout is dirty" run_organizer_archive

echo "iOS versioning and Xcode Organizer regression tests passed."

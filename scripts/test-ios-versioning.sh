#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/merian-versioning-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

write_project_yml() {
  local version="$1"
  local build="$2"
  local file="$tmp_dir/project.yml"

  {
    printf 'name: Merian\n'
    printf 'settings:\n'
    printf '  base:\n'
    printf '    CODE_SIGN_STYLE: Automatic\n'
    printf '    MARKETING_VERSION: %s\n' "$version"
    printf '    CURRENT_PROJECT_VERSION: %s\n' "$build"
    printf '    VERSIONING_SYSTEM: apple-generic\n'
  } > "$file"
}

run_prepare() {
  env \
    -u ASC_APP_ID \
    -u ASC_ISSUER_ID \
    -u ASC_KEY_ID \
    -u ASC_PRIVATE_KEY_PATH \
    PROJECT_YML="$tmp_dir/project.yml" \
    PROJECT_FILE="$tmp_dir/Merian.xcodeproj/project.pbxproj" \
    IOS_RELEASE_PREP_MARKER="$tmp_dir/build/ios-release-prep.json" \
    RUN_XCODEGEN=0 \
    "$repo_root/scripts/prepare-ios-release.sh"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -q -- "$needle" "$file" || fail "Expected $file to contain: $needle"
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "Expected command to fail: $*"
  fi
}

assert_fails_with() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "Expected command to fail: $*"
  fi
  if ! grep -q -- "$expected" <<<"$output"; then
    fail "Expected failing command output to contain: $expected"
  fi
}

bash -n "$repo_root/scripts/prepare-ios-release.sh"
bash -n "$repo_root/scripts/check-ios-release-prep.sh"
bash -n "$repo_root/scripts/validate-ios-versioning.sh"
bash -n "$repo_root/scripts/export-ios-release.sh"

write_project_yml "1.0.0" "39"
VERSION=1.2.3 LATEST_ASC_BUILD=41 run_prepare >/dev/null
assert_contains "MARKETING_VERSION: 1.2.3" "$tmp_dir/project.yml"
assert_contains "CURRENT_PROJECT_VERSION: 42" "$tmp_dir/project.yml"
assert_contains '"build": 42' "$tmp_dir/build/ios-release-prep.json"

write_project_yml "1.0.0" "39"
VERSION=1.2.4 BUILD=50 run_prepare >/dev/null
assert_contains "MARKETING_VERSION: 1.2.4" "$tmp_dir/project.yml"
assert_contains "CURRENT_PROJECT_VERSION: 50" "$tmp_dir/project.yml"

write_project_yml "1.0.0" "39"
assert_fails env VERSION=1.2 LATEST_ASC_BUILD=41 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
assert_fails env -u ASC_APP_ID -u ASC_ISSUER_ID -u ASC_KEY_ID -u ASC_PRIVATE_KEY_PATH VERSION=1.2.3 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
assert_fails env VERSION=1.2.3 BUILD=39 PROJECT_YML="$tmp_dir/project.yml" RUN_XCODEGEN=0 "$repo_root/scripts/prepare-ios-release.sh"

write_project_yml "1.0.0" "39"
VERSION=1.2.5 LATEST_ASC_BUILD=41 run_prepare >/dev/null
MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh" >/dev/null
write_project_yml "1.2.5" "43"
assert_fails env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

rm -f "$tmp_dir/build/ios-release-prep.json"
assert_fails_with "error: Release archive blocked: missing release prep marker" \
  env MERIAN_FORCE_RELEASE_PREP_CHECK=1 MERIAN_PROJECT_ROOT="$tmp_dir" "$repo_root/scripts/check-ios-release-prep.sh"

echo "iOS versioning script tests passed."

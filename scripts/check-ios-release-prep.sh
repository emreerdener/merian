#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: Release archive blocked: $*" >&2
  echo "Distributable archives must come from the serialized GitHub Actions publisher." >&2
  exit 1
}

extract_project_setting() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '$1 == key ":" { print $2; found = 1; exit } END { if (!found) exit 1 }' "$file"
}

is_placeholder_revenuecat_key() {
  case "$1" in
    "appl_..." | appl_replace* | appl_your* | appl_live_key)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_revenuecat_key() {
  local key="${REVENUECAT_API_KEY:-}"

  if [[ -z "$key" ]]; then
    fail "REVENUECAT_API_KEY is missing."
  fi
  case "$key" in
    test_*) fail "REVENUECAT_API_KEY is a RevenueCat Test Store key." ;;
    appl_*)
      if is_placeholder_revenuecat_key "$key"; then
        fail "REVENUECAT_API_KEY is a placeholder, not the production iOS SDK key."
      fi
      ;;
    *) fail "REVENUECAT_API_KEY must be a production iOS SDK key beginning with appl_." ;;
  esac
}

should_enforce="false"
if [[ "${CONFIGURATION:-}" == "Release" ]]; then
  if [[ "${ACTION:-}" == "install" || "${DEPLOYMENT_LOCATION:-}" == "YES" || -n "${ARCHIVE_PRODUCTS_PATH:-}" ]]; then
    should_enforce="true"
  fi
fi
[[ "${MERIAN_FORCE_RELEASE_PREP_CHECK:-0}" == "1" ]] && should_enforce="true"
[[ "$should_enforce" == "true" ]] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-${SRCROOT:-$(cd "$script_dir/.." && pwd)}}"
repo_root="$(cd "$repo_root" && pwd -P)" || fail "could not canonicalize project root."
project_yml="$repo_root/project.yml"
fingerprint_script="$repo_root/scripts/ios-release-source-fingerprint.sh"

[[ -f "$project_yml" ]] || fail "missing project.yml."
[[ -f "$fingerprint_script" ]] || fail "missing release-source fingerprint tool."
git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "$repo_root is not a Git worktree."

project_version="$(extract_project_setting MARKETING_VERSION "$project_yml")" \
  || fail "could not read MARKETING_VERSION from project.yml."
project_baseline="$(extract_project_setting CURRENT_PROJECT_VERSION "$project_yml")" \
  || fail "could not read CURRENT_PROJECT_VERSION from project.yml."
[[ "$project_version" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]] \
  || fail "tracked MARKETING_VERSION is malformed."
[[ "$project_baseline" =~ ^[1-9][0-9]*$ ]] \
  || fail "tracked CURRENT_PROJECT_VERSION baseline is malformed."

source_status="$(git -C "$repo_root" status --porcelain --untracked-files=normal)"
if [[ -n "$source_status" ]]; then
  printf '%s\n' "$source_status" >&2
  fail "source checkout is dirty."
fi

source_revision="$(git -C "$repo_root" rev-parse HEAD)"
source_fingerprint="$(MERIAN_PROJECT_ROOT="$repo_root" bash "$fingerprint_script")"
[[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]] || fail "Git returned a malformed source revision."
[[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] || fail "release-source fingerprint is malformed."

expected_revision="${MERIAN_EXPECTED_SOURCE_REVISION:-}"
[[ "$expected_revision" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail "MERIAN_EXPECTED_SOURCE_REVISION is required for every Release archive."
[[ "$source_revision" == "$expected_revision" ]] \
  || fail "checked-out source $source_revision does not match expected source $expected_revision."

if [[ "${MERIAN_IOS_VALIDATION_ARCHIVE:-0}" == "1" ]]; then
  [[ "${MERIAN_RELEASE_PUBLISHER:-0}" != "1" ]] \
    || fail "validation and publisher archive modes are mutually exclusive."
  [[ "${CODE_SIGNING_ALLOWED:-}" == "NO" && "${CODE_SIGNING_REQUIRED:-}" == "NO" ]] \
    || fail "validation archive mode is restricted to unsigned archives."
  [[ -z "${CODE_SIGN_IDENTITY:-}" && -z "${DEVELOPMENT_TEAM:-}" ]] \
    || fail "validation archive mode cannot use a signing identity or development team."
  [[ "${MARKETING_VERSION:-$project_version}" == "$project_version" ]] \
    || fail "validation archive changed MARKETING_VERSION."
  [[ "${CURRENT_PROJECT_VERSION:-$project_baseline}" == "$project_baseline" ]] \
    || fail "validation archive changed or allocated CURRENT_PROJECT_VERSION."
  echo "Unsigned validation-only Release archive authorized for ${project_version} (${project_baseline}) at ${source_revision}; no build number was allocated."
  exit 0
fi

[[ "${MERIAN_RELEASE_PUBLISHER:-0}" == "1" ]] \
  || fail "manual Organizer and ad-hoc xcodebuild archives are unsupported."
[[ "${MERIAN_PUBLISHER_SERIALIZED:-0}" == "1" ]] \
  || fail "publisher concurrency lock is not asserted."

expected_version="${MERIAN_EXPECTED_MARKETING_VERSION:-}"
expected_build="${MERIAN_EXPECTED_BUILD_NUMBER:-}"
expected_fingerprint="${MERIAN_EXPECTED_SOURCE_FINGERPRINT:-}"

[[ "$expected_version" == "$project_version" ]] \
  || fail "publisher version must equal tracked MARKETING_VERSION $project_version."
[[ "$expected_build" =~ ^[1-9][0-9]*$ ]] \
  || fail "publisher supplied no valid allocated build number."
(( expected_build > project_baseline )) \
  || fail "allocated build $expected_build is not higher than tracked baseline $project_baseline."
[[ "$expected_fingerprint" == "$source_fingerprint" ]] \
  || fail "publisher source fingerprint does not match the clean checkout."
[[ "${MARKETING_VERSION:-}" == "$expected_version" ]] \
  || fail "Xcode resolved MARKETING_VERSION=${MARKETING_VERSION:-missing}; expected $expected_version."
[[ "${CURRENT_PROJECT_VERSION:-}" == "$expected_build" ]] \
  || fail "Xcode resolved CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION:-missing}; expected $expected_build."

validate_revenuecat_key

echo "Serialized publisher Release archive authorized for ${expected_version} (${expected_build}) at ${source_revision}."
echo "Release source fingerprint: ${source_fingerprint}"

#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: Release archive blocked: $*" >&2
  echo "Run from the repo root: make prepare-ios-release VERSION=x.y.z" >&2
  echo "Emergency fallback: BUILD=N make prepare-ios-release VERSION=x.y.z" >&2
  exit 1
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

read_xcconfig_key() {
  local key="$1"
  local file="$2"

  [[ -f "$file" ]] || return 1
  awk -v key="$key" '
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]*\/\/.*/, "", line)
      if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
        sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }
  ' "$file" | tail -n 1
}

print_revenuecat_local_state() {
  local root="${MERIAN_PROJECT_ROOT:-${SRCROOT:-$(pwd)}}"
  local local_config="$root/Config.local.xcconfig"
  local local_key

  if [[ ! -f "$local_config" ]]; then
    echo "Current state: $local_config does not exist, so Xcode is falling back to the tracked development key in Config.xcconfig." >&2
    return
  fi

  local_key="$(read_xcconfig_key REVENUECAT_API_KEY "$local_config" || true)"
  if [[ -z "$local_key" ]]; then
    echo "Current state: $local_config exists but has no active REVENUECAT_API_KEY line." >&2
  elif [[ "$local_key" == test_* ]]; then
    echo "Current state: $local_config still contains a RevenueCat Test Store key." >&2
  elif is_placeholder_revenuecat_key "$local_key"; then
    echo "Current state: $local_config contains a placeholder RevenueCat key, not the real production iOS SDK key." >&2
  else
    echo "Current state: $local_config has an active RevenueCat key; if Xcode still resolves test_, reopen the project or clean build settings." >&2
  fi
}

report_revenuecat_issue() {
  local message="$1"

  if [[ "${MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY:-0}" == "1" ]]; then
    echo "error: Release archive blocked: $message" >&2
  else
    echo "warning: Release archive is using non-production RevenueCat config: $message" >&2
  fi
  print_revenuecat_local_state
  echo "Production/TestFlight builds should use the RevenueCat iOS production SDK key:" >&2
  echo "  cp Config.local.example.xcconfig Config.local.xcconfig" >&2
  echo "  # edit Config.local.xcconfig: REVENUECAT_API_KEY = appl_..." >&2
  echo "Or let release prep write the ignored override:" >&2
  echo "  REVENUECAT_API_KEY=appl_... make prepare-ios-release VERSION=x.y.z" >&2

  if [[ "${MERIAN_REQUIRE_PRODUCTION_REVENUECAT_KEY:-0}" == "1" ]]; then
    exit 1
  fi
}

extract_project_setting() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '$1 == key ":" { print $2; found = 1; exit } END { if (!found) exit 1 }' "$file"
}

read_marker_value() {
  local key="$1"
  local expected_type="$2"
  local file="$3"

  /usr/bin/plutil \
    -extract "$key" raw \
    -expect "$expected_type" \
    -o - \
    "$file" \
    2>/dev/null
}

should_enforce="false"
if [[ "${CONFIGURATION:-}" == "Release" ]]; then
  if [[ "${ACTION:-}" == "install" || "${DEPLOYMENT_LOCATION:-}" == "YES" || -n "${ARCHIVE_PRODUCTS_PATH:-}" ]]; then
    should_enforce="true"
  fi
fi
if [[ "${MERIAN_FORCE_RELEASE_PREP_CHECK:-}" == "1" ]]; then
  should_enforce="true"
fi

if [[ "$should_enforce" != "true" ]]; then
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-${SRCROOT:-$(cd "$script_dir/.." && pwd)}}"
repo_root="$(cd "$repo_root" && pwd -P)" \
  || fail "could not canonicalize project root $repo_root."
project_yml="$repo_root/project.yml"

if [[ -n "${IOS_RELEASE_PREP_MARKER:-}" ]]; then
  if [[ "$IOS_RELEASE_PREP_MARKER" = /* ]]; then
    marker_file="$IOS_RELEASE_PREP_MARKER"
  else
    marker_file="$repo_root/$IOS_RELEASE_PREP_MARKER"
  fi
else
  marker_file="$repo_root/build/ios-release-prep.json"
fi

[[ -f "$project_yml" ]] || fail "missing project.yml at $project_yml."
[[ -f "$marker_file" ]] || fail "missing release prep marker at $marker_file."
[[ -x /usr/bin/plutil ]] || fail "plutil is unavailable."
/usr/bin/plutil -convert json -o - "$marker_file" >/dev/null 2>&1 \
  || fail "release prep marker is not valid JSON at $marker_file."

project_version="$(extract_project_setting MARKETING_VERSION "$project_yml")" || fail "could not read MARKETING_VERSION from project.yml."
project_build="$(extract_project_setting CURRENT_PROJECT_VERSION "$project_yml")" || fail "could not read CURRENT_PROJECT_VERSION from project.yml."

marker_version="$(read_marker_value version string "$marker_file")" \
  || fail "release prep marker has no string version."
marker_build="$(read_marker_value build integer "$marker_file")" \
  || fail "release prep marker has no integer build."
marker_source_fingerprint="$(
  read_marker_value source_fingerprint string "$marker_file"
)" || fail "release prep marker has no string release-source fingerprint."
marker_ci_validation_only="false"
if /usr/bin/plutil -type ci_validation_only "$marker_file" >/dev/null 2>&1; then
  marker_ci_validation_only="$(
    read_marker_value ci_validation_only bool "$marker_file"
  )" || fail "release prep marker has a malformed ci_validation_only flag."
fi

[[ "$marker_version" == "$project_version" ]] || fail "release prep marker version $marker_version does not match project version $project_version."
[[ "$marker_build" == "$project_build" ]] || fail "release prep marker build $marker_build does not match project build $project_build."
[[ "$marker_source_fingerprint" =~ ^[0-9a-f]{64}$ ]] \
  || fail "release prep marker has no valid release-source fingerprint."

fingerprint_script="$repo_root/scripts/ios-release-source-fingerprint.sh"
[[ -f "$fingerprint_script" ]] || fail "missing source fingerprint script at $fingerprint_script."

source_status="$(git -C "$repo_root" status --porcelain --untracked-files=normal)"
if [[ -n "$source_status" ]]; then
  echo "Current source changes:" >&2
  printf '%s\n' "$source_status" >&2
  fail "source checkout is dirty; commit the prepared source before archiving."
fi

source_fingerprint="$(
  MERIAN_PROJECT_ROOT="$repo_root" bash "$fingerprint_script"
)"
[[ "$source_fingerprint" == "$marker_source_fingerprint" ]] \
  || fail "tracked source changed after release prep; prepare a fresh, higher TestFlight build."

source_revision="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail "git returned an invalid source revision."

if [[ "$marker_ci_validation_only" == "true" ]]; then
  marker_source_sha="$(
    read_marker_value source_sha string "$marker_file"
  )" || fail "CI validation marker has no string exact source revision."
  [[ "$marker_source_sha" =~ ^[0-9a-f]{40,64}$ ]] \
    || fail "CI validation marker has no valid exact source revision."
  [[ "$marker_source_sha" == "$source_revision" ]] \
    || fail "CI release marker source $marker_source_sha does not match checked-out source $source_revision."
else
  marker_prepared_from_sha="$(
    read_marker_value prepared_from_sha string "$marker_file"
  )" || fail "local release marker has no string preparation-base revision."
  [[ "$marker_prepared_from_sha" =~ ^[0-9a-f]{40,64}$ ]] \
    || fail "local release marker has no valid preparation-base revision."
  git -C "$repo_root" cat-file -e "${marker_prepared_from_sha}^{commit}" \
    >/dev/null 2>&1 \
    || fail "local release marker preparation base $marker_prepared_from_sha is not a commit."
  git -C "$repo_root" merge-base \
    --is-ancestor "$marker_prepared_from_sha" "$source_revision" \
    || fail "release commit $source_revision does not descend from preparation base $marker_prepared_from_sha."
fi

if [[ -n "${MARKETING_VERSION:-}" && "$MARKETING_VERSION" != "$project_version" ]]; then
  fail "Xcode resolved MARKETING_VERSION=$MARKETING_VERSION but project.yml says $project_version."
fi
if [[ -n "${CURRENT_PROJECT_VERSION:-}" && "$CURRENT_PROJECT_VERSION" != "$project_build" ]]; then
  fail "Xcode resolved CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION but project.yml says $project_build."
fi

if [[ "${CONFIGURATION:-}" == "Release" ]]; then
  revenuecat_key="${REVENUECAT_API_KEY:-}"
  if [[ -z "$revenuecat_key" ]]; then
    report_revenuecat_issue "REVENUECAT_API_KEY is missing."
  else
    case "$revenuecat_key" in
      test_*)
        report_revenuecat_issue "REVENUECAT_API_KEY is a RevenueCat Test Store key."
        ;;
      appl_*)
        if is_placeholder_revenuecat_key "$revenuecat_key"; then
          report_revenuecat_issue "REVENUECAT_API_KEY is still a placeholder, not the real RevenueCat production iOS SDK key."
        fi
        ;;
      *)
        report_revenuecat_issue "REVENUECAT_API_KEY should be a RevenueCat iOS production key beginning with appl_."
        ;;
    esac
  fi
fi

echo "Release prep marker verified for Merian ${project_version} (${project_build}) at ${source_revision}."
echo "Release source fingerprint: ${source_fingerprint}"

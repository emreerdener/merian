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

project_version="$(extract_project_setting MARKETING_VERSION "$project_yml")" || fail "could not read MARKETING_VERSION from project.yml."
project_build="$(extract_project_setting CURRENT_PROJECT_VERSION "$project_yml")" || fail "could not read CURRENT_PROJECT_VERSION from project.yml."

marker_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$marker_file" | head -n 1)"
marker_build="$(sed -n 's/.*"build"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$marker_file" | head -n 1)"

[[ -n "$marker_version" && -n "$marker_build" ]] || fail "release prep marker is malformed at $marker_file."
[[ "$marker_version" == "$project_version" ]] || fail "release prep marker version $marker_version does not match project version $project_version."
[[ "$marker_build" == "$project_build" ]] || fail "release prep marker build $marker_build does not match project build $project_build."

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

echo "Release prep marker verified for Merian ${project_version} (${project_build})."

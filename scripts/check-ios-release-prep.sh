#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release archive blocked: $*" >&2
  echo "Run from the repo root: make prepare-ios-release VERSION=x.y.z" >&2
  echo "Emergency fallback: BUILD=N make prepare-ios-release VERSION=x.y.z" >&2
  exit 1
}

extract_project_setting() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $1 == key ":" {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$file"
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

echo "Release prep marker verified for Merian ${project_version} (${project_build})."

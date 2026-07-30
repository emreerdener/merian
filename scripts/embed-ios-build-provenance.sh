#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-${SRCROOT:-$(cd "$script_dir/.." && pwd)}}"
fingerprint_script="$script_dir/ios-release-source-fingerprint.sh"
plistbuddy_command="${MERIAN_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}"

fail() {
  echo "error: Could not embed iOS build provenance: $*" >&2
  exit 1
}

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  if "$plistbuddy_command" -c "Print :${key}" "$plist" >/dev/null 2>&1; then
    "$plistbuddy_command" -c "Set :${key} ${value}" "$plist"
  else
    "$plistbuddy_command" -c "Add :${key} string ${value}" "$plist"
  fi
}

[[ -f "$fingerprint_script" ]] || fail "missing $fingerprint_script."
git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "$repo_root is not a git worktree."

source_revision="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$source_revision" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail "git returned an invalid source revision."

if [[ -n "${MERIAN_EXPECTED_SOURCE_REVISION:-}" &&
      "$source_revision" != "$MERIAN_EXPECTED_SOURCE_REVISION" ]]; then
  fail "expected revision $MERIAN_EXPECTED_SOURCE_REVISION, found $source_revision."
fi

source_fingerprint="$(
  MERIAN_PROJECT_ROOT="$repo_root" bash "$fingerprint_script"
)"
[[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] \
  || fail "source fingerprint is malformed."

source_state="clean"
if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=normal)" ]]; then
  source_state="dirty"
fi

target_build_dir="${TARGET_BUILD_DIR:-}"
info_plist_path="${INFOPLIST_PATH:-}"
[[ -n "$target_build_dir" ]] || fail "TARGET_BUILD_DIR is missing."
[[ -n "$info_plist_path" ]] || fail "INFOPLIST_PATH is missing."
[[ -d "$target_build_dir" ]] || fail "TARGET_BUILD_DIR does not exist."
[[ "$info_plist_path" != /* ]] || fail "INFOPLIST_PATH must be relative."
case "/$info_plist_path/" in
  */../* | */./*)
    fail "INFOPLIST_PATH contains a traversal component."
    ;;
esac

product_candidate="$target_build_dir/$info_plist_path"
[[ ! -L "$product_candidate" ]] \
  || fail "product Info.plist must not be a symbolic link."
[[ -f "$product_candidate" ]] \
  || fail "product Info.plist is missing at $product_candidate."
product_link_count="$(
  perl -e '
    my @metadata = lstat($ARGV[0]);
    die "lstat failed\n" unless @metadata;
    print $metadata[3];
  ' "$product_candidate"
)" \
  || fail "could not inspect the product Info.plist link count."
[[ "$product_link_count" == "1" ]] \
  || fail "product Info.plist must not have multiple hard links."

target_build_root="$(cd "$target_build_dir" && pwd -P)"
product_parent="$(
  cd "$(dirname "$product_candidate")" \
    && pwd -P
)" || fail "could not canonicalize the product Info.plist parent."
product_plist="$product_parent/$(basename "$product_candidate")"
case "$product_plist" in
  "$target_build_root"/*)
    ;;
  *)
    fail "resolved product plist is outside TARGET_BUILD_DIR."
    ;;
esac

[[ "$plistbuddy_command" == /* ]] || fail "PlistBuddy command must be an absolute path."
[[ -x "$plistbuddy_command" ]] || fail "PlistBuddy is unavailable at $plistbuddy_command."
set_plist_string "$product_plist" "MERIAN_SOURCE_REVISION" "$source_revision"
set_plist_string "$product_plist" "MERIAN_SOURCE_FINGERPRINT" "$source_fingerprint"
set_plist_string "$product_plist" "MERIAN_SOURCE_STATE" "$source_state"

echo "Embedded iOS build provenance: revision=$source_revision fingerprint=$source_fingerprint state=$source_state"

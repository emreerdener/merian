#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

event_name="${GITHUB_EVENT_NAME:-local}"
summary_file="${GITHUB_STEP_SUMMARY:-}"
should_run="false"
reason="No iOS build input changed."
resolution_failed="false"

changed_files_path="$(mktemp "${TMPDIR:-/tmp}/merian-ios-build-files.XXXXXX")"
trap 'rm -f "$changed_files_path"' EXIT

is_zero_sha() {
  [[ "$1" =~ ^0+$ ]]
}

commit_exists() {
  [[ -n "$1" ]] && git cat-file -e "$1^{commit}" 2>/dev/null
}

write_changed_files_between() {
  local base_ref="$1"
  local head_ref="$2"
  local comparison_mode="${3:-direct}"

  if ! commit_exists "$base_ref" || ! commit_exists "$head_ref"; then
    return 1
  fi

  if [[ "$comparison_mode" == "merge-base" ]]; then
    base_ref="$(git merge-base "$base_ref" "$head_ref")" || return 1
  fi

  git diff \
    --name-only \
    --diff-filter=ACMRTUXBD \
    -z \
    "$base_ref" \
    "$head_ref" > "$changed_files_path"
}

write_local_changed_files() {
  {
    git diff --name-only --diff-filter=ACMRTUXBD -z HEAD
    git ls-files --others --exclude-standard -z
  } > "$changed_files_path"

  if [[ ! -s "$changed_files_path" ]]; then
    if commit_exists "HEAD^"; then
      git diff \
        --name-only \
        --diff-filter=ACMRTUXBD \
        -z \
        HEAD^ \
        HEAD > "$changed_files_path"
    else
      git diff-tree \
        --root \
        --no-commit-id \
        --name-only \
        --diff-filter=ACMRTUXBD \
        -r \
        -z \
        HEAD > "$changed_files_path"
    fi
  fi
}

is_ios_build_input() {
  case "$1" in
    .github/workflows/ios-*.yml | \
    .swiftlint.yml | \
    Config.xcconfig | \
    Signing.xcconfig | \
    project.yml | \
    Merian.xcodeproj/* | \
    merian.xcodeproj/* | \
    apps/ios/* | \
    apps/watch/* | \
    scripts/*ios*.sh | \
    scripts/select-ios-*.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ "$event_name" == "workflow_dispatch" ]]; then
  should_run="true"
  reason="Manual dispatch requires complete iOS verification."
elif [[ "$event_name" == "schedule" ]]; then
  should_run="true"
  reason="Scheduled drift verification requires the complete iOS gate."
elif [[ "$event_name" == "merge_group" ]]; then
  should_run="true"
  reason="Merge-queue commits must run the complete iOS gate."
elif (( $# > 0 )); then
  printf '%s\0' "$@" > "$changed_files_path"
else
  event_base=""
  event_head=""
  comparison_mode="direct"

  if command -v jq >/dev/null 2>&1 \
    && [[ -n "${GITHUB_EVENT_PATH:-}" ]] \
    && [[ -f "$GITHUB_EVENT_PATH" ]]; then
    case "$event_name" in
      pull_request)
        event_base="$(jq -r '.pull_request.base.sha // empty' "$GITHUB_EVENT_PATH")"
        event_head="$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")"
        comparison_mode="merge-base"
        ;;
      push)
        event_base="$(jq -r '.before // empty' "$GITHUB_EVENT_PATH")"
        event_head="$(jq -r '.after // empty' "$GITHUB_EVENT_PATH")"
        ;;
    esac
  fi

  if [[ -n "$event_base" ]] \
    && [[ -n "$event_head" ]] \
    && ! is_zero_sha "$event_base" \
    && write_changed_files_between \
      "$event_base" \
      "$event_head" \
      "$comparison_mode"; then
    :
  elif [[ "$event_name" == "local" || -z "${GITHUB_ACTIONS:-}" ]]; then
    write_local_changed_files
  else
    resolution_failed="true"
  fi
fi

if [[ "$should_run" != "true" && "$resolution_failed" == "true" ]]; then
  should_run="true"
  reason="Changed files could not be resolved; iOS verification is required fail-closed."
elif [[ "$should_run" != "true" ]]; then
  while IFS= read -r -d '' changed_file; do
    if is_ios_build_input "$changed_file"; then
      should_run="true"
      reason="An iOS build input changed."
      printf 'Matched iOS build input: %q\n' "$changed_file"
      break
    fi
  done < "$changed_files_path"
fi

echo "iOS build should_run=${should_run}"
echo "$reason"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "should_run=${should_run}"
    echo "reason=${reason}"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -n "$summary_file" ]]; then
  {
    echo ""
    echo "### iOS build scope"
    echo ""
    echo "- Run macOS verification: \`${should_run}\`"
    echo "- Reason: ${reason}"
  } >> "$summary_file"
fi

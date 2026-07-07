#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

event_name="${GITHUB_EVENT_NAME:-local}"
summary_file="${GITHUB_STEP_SUMMARY:-}"
should_run="false"
reason="No startup, schema, recovery, project, or focused startup-test source changes were detected."

event_before=""
event_after=""
if command -v jq >/dev/null 2>&1 && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  event_before="$(jq -r '.before // .pull_request.base.sha // empty' "$GITHUB_EVENT_PATH")"
  event_after="$(jq -r '.after // .pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")"
fi

head_ref="${event_after:-${GITHUB_SHA:-HEAD}}"
base_ref="${event_before:-}"
changed_files=""

if [ -n "$base_ref" ] && git cat-file -e "${base_ref}^{commit}" 2>/dev/null && git cat-file -e "${head_ref}^{commit}" 2>/dev/null; then
  changed_files="$(git diff --name-only "$base_ref" "$head_ref" || true)"
fi

if [ -z "$changed_files" ] && [ -z "${GITHUB_EVENT_PATH:-}" ] && git cat-file -e HEAD^{commit} 2>/dev/null; then
  changed_files="$(
    {
      git diff --name-only HEAD || true
      git ls-files --others --exclude-standard || true
    } | sort -u
  )"
fi

if [ -z "$changed_files" ] && git cat-file -e HEAD^{commit} 2>/dev/null; then
  changed_files="$(git diff-tree -m --no-commit-id --name-only -r HEAD | sort -u || true)"
fi

is_startup_runtime_file() {
  case "$1" in
    project.yml | \
    Merian.xcodeproj/* | \
    merian.xcodeproj/* | \
    apps/ios/Merian/App/MerianApp.swift | \
    apps/ios/Merian/App/MerianObjCExceptionBridge.* | \
    apps/ios/Merian/Configuration/Merian-Bridging-Header.h | \
    apps/ios/Merian/Core/Data/StoreRecovery/* | \
    apps/ios/Merian/Models/Aliases.swift | \
    apps/ios/Merian/Models/SchemaVersions.swift | \
    apps/ios/MerianTests/App/ModelStoreRecoveryCoordinatorTests.swift | \
    apps/ios/MerianTests/Models/MigrationPlanTests.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [ "$event_name" = "workflow_dispatch" ]; then
  should_run="true"
  reason="Manual dispatch requested the focused startup simulator lane."
elif [ "$event_name" = "schedule" ]; then
  should_run="true"
  reason="Scheduled drift check requested the focused startup simulator lane."
else
  while IFS= read -r changed_file; do
    [ -n "$changed_file" ] || continue
    if is_startup_runtime_file "$changed_file"; then
      should_run="true"
      reason="Startup simulator lane is required because ${changed_file} changed."
      break
    fi
  done <<EOF
$changed_files
EOF
fi

echo "startup simulator should_run=${should_run}"
echo "$reason"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "should_run=${should_run}"
    echo "reason=${reason}"
  } >> "$GITHUB_OUTPUT"
fi

if [ -n "$summary_file" ]; then
  {
    echo ""
    echo "### Startup simulator scope"
    echo ""
    echo "- Run simulator lane: \`${should_run}\`"
    echo "- Reason: ${reason}"
  } >> "$summary_file"
fi

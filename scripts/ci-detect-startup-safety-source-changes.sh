#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

event_name="${GITHUB_EVENT_NAME:-local}"
summary_file="${GITHUB_STEP_SUMMARY:-}"
should_run="false"
reason="No startup, schema, recovery, project, or focused startup-test source changes were detected."

resolution_failed="false"
changed_files_path="$(mktemp "${TMPDIR:-/tmp}/merian-startup-files.XXXXXX")"
trap 'rm -f "$changed_files_path"' EXIT

resolve_event_changes() {
  local base_ref head_ref
  command -v jq >/dev/null 2>&1 || return 1
  [[ -f "${GITHUB_EVENT_PATH:-}" ]] || return 1
  case "$event_name" in
    push)
      base_ref="$(jq -er '.before | select(type == "string")' "$GITHUB_EVENT_PATH" 2>/dev/null)" || return 1
      head_ref="$(jq -er '.after | select(type == "string")' "$GITHUB_EVENT_PATH" 2>/dev/null)" || return 1
      ;;
    pull_request)
      base_ref="$(jq -er '.pull_request.base.sha | select(type == "string")' "$GITHUB_EVENT_PATH" 2>/dev/null)" || return 1
      head_ref="$(jq -er '.pull_request.head.sha | select(type == "string")' "$GITHUB_EVENT_PATH" 2>/dev/null)" || return 1
      ;;
    *) return 1 ;;
  esac
  [[ "$base_ref" =~ ^[0-9a-fA-F]{40}$ && ! "$base_ref" =~ ^0+$ ]] || return 1
  [[ "$head_ref" =~ ^[0-9a-fA-F]{40}$ && ! "$head_ref" =~ ^0+$ ]] || return 1
  git cat-file -e "${base_ref}^{commit}" 2>/dev/null || return 1
  git cat-file -e "${head_ref}^{commit}" 2>/dev/null || return 1
  if [[ "$event_name" == "pull_request" ]]; then
    base_ref="$(git merge-base "$base_ref" "$head_ref")" || return 1
  fi
  git diff --name-only --no-renames -z "$base_ref" "$head_ref" > "$changed_files_path"
}

resolve_local_changes() {
  git diff --name-only --no-renames -z HEAD > "$changed_files_path" || return 1
  git ls-files --others --exclude-standard -z >> "$changed_files_path" || return 1
  if [[ ! -s "$changed_files_path" ]]; then
    git diff-tree --root -m --no-commit-id --name-only --no-renames -r -z HEAD > "$changed_files_path" || return 1
  fi
}

is_startup_runtime_file() {
  case "$1" in
    .github/workflows/ios-startup-safety.yml | \
    Makefile | \
    scripts/ci-detect-startup-safety-source-changes.sh | \
    scripts/test-ci-detect-startup-safety-source-changes.sh | \
    project.yml | \
    Merian.xcodeproj/* | \
    merian.xcodeproj/* | \
    apps/ios/Merian/App/MerianApp.swift | \
    apps/ios/Merian/App/MerianObjCExceptionBridge.* | \
    apps/ios/Merian/Configuration/Merian-Bridging-Header.h | \
    apps/ios/Merian/Core/Data/Database/ScanRepository.swift | \
    apps/ios/Merian/Core/Data/Images/LocalImageLoader.swift | \
    apps/ios/Merian/Core/UI/Components/AsyncLocalImageView.swift | \
    apps/ios/Merian/Core/UI/Modifiers/ImageRecoveryReloadModifier.swift | \
    apps/ios/Merian/Features/Explore/Shared/Media/Components/ExploreHeroImageView.swift | \
    apps/ios/Merian/Features/Explore/Feed/Components/Composer/ExplorePostComposerImageView.swift | \
    apps/ios/Merian/Features/Profile/UserProfile/Components/Publications/ProfilePublicScanImageView.swift | \
    apps/ios/Merian/Core/UI/Components/ScanThumbnail.swift | \
    apps/ios/Merian/Core/UI/Services/ScanThumbnailLoader.swift | \
    apps/ios/MerianTests/Core/UI/ScanThumbnailLoaderTests.swift | \
    apps/ios/MerianTests/Core/Data/Images/LocalScanMediaRecoveryRevisionTests.swift | \
    apps/ios/Merian/Core/Data/Images/Concurrency/* | \
    apps/ios/Merian/Core/Data/Images/Policies/* | \
    apps/ios/Merian/Core/Data/Images/Recovery/* | \
    apps/ios/Merian/Core/Data/Images/Services/CloudScanImageRepairActor.swift | \
    apps/ios/Merian/Core/Data/Images/Services/ScanMediaRecoveryRegistrationService.swift | \
    apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift | \
    apps/ios/Merian/Core/Data/StoreRecovery/* | \
    apps/ios/Merian/Models/Aliases.swift | \
    apps/ios/Merian/Models/Schema/SchemaV49Snapshots.swift | \
    apps/ios/Merian/Models/Schema/SchemaV50Snapshots.swift | \
    apps/ios/Merian/Models/Schema/SchemaV50ReleasedActiveSnapshots.swift | \
    apps/ios/Merian/Models/SchemaVersions.swift | \
    apps/ios/MerianTests/Core/Data/StoreRecovery/* | \
    apps/ios/MerianTests/Core/Data/Database/CoreDataIntegrationArchitectureTests.swift | \
    apps/ios/MerianTests/Core/Data/Images/CloudScanImageRepairActorTests.swift | \
    apps/ios/MerianTests/Core/Data/Images/ImageLoadingArchitectureTests.swift | \
    apps/ios/MerianTests/Core/Data/Images/LocalImageLoaderTests.swift | \
    apps/ios/MerianTests/Core/Data/Images/LocalImageLoaderTests+RecoveryEvidence.swift | \
    apps/ios/MerianTests/Core/Data/Images/ScanMediaRecoveryRegistrationTests.swift | \
    apps/ios/MerianTests/Core/Data/OfflineSync/QueueActorCacheTests.swift | \
    apps/ios/MerianTests/Core/Data/OfflineSync/ProfileActorCacheTests.swift | \
    apps/ios/MerianTests/Models/MigrationPlanTests.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

case "$event_name" in
  workflow_dispatch|schedule|merge_group)
    should_run="true"
    reason="Manual, scheduled, or merge-queue verification requires the focused startup simulator lane."
    ;;
  local)
    if [[ -n "${GITHUB_ACTIONS:-}" || -n "${GITHUB_EVENT_PATH:-}" ]]; then
      resolution_failed="true"
    else
      resolve_local_changes || resolution_failed="true"
    fi
    ;;
  *)
    resolve_event_changes || resolution_failed="true"
    ;;
esac

if [[ "$resolution_failed" == "true" ]]; then
  should_run="true"
  reason="The complete change range could not be resolved; startup verification is required fail-closed."
elif [[ "$should_run" != "true" ]]; then
  while IFS= read -r -d '' changed_file; do
    if is_startup_runtime_file "$changed_file"; then
      should_run="true"
      reason="A startup simulator input changed."
      printf 'Matched startup input: %q\n' "$changed_file"
      break
    fi
  done < "$changed_files_path"
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

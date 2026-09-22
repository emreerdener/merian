#!/usr/bin/env bash
set -euo pipefail

# Validation runs for every main push. Mutation is selected from the complete
# undeployed range so a newer docs commit cannot strand an earlier backend fix.
: "${GITHUB_SHA:?Missing candidate SHA}"
: "${PRODUCTION_SOURCE_PATHS:?Missing production path policy}"
should_deploy=false

if [[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]]; then
  should_deploy=true
elif [[ "${GITHUB_EVENT_NAME:-}" == push ]]; then
  if [[ ! "${DEPLOY_BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] \
    || [[ ! "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] \
    || ! git merge-base --is-ancestor "$DEPLOY_BASE_SHA" "$GITHUB_SHA"; then
    echo "Cannot prove the deployed baseline; production scope is blocked. Use an explicitly authorized manual deployment to establish a baseline." >&2
    exit 1
  fi
  changed_files="$(mktemp "${TMPDIR:-/tmp}/merian-production-scope.XXXXXX")"
  trap 'rm -f "$changed_files"' EXIT
  # Both sides of a rename must be classified, including moves out of scope.
  git diff --no-renames --name-only -z "$DEPLOY_BASE_SHA" "$GITHUB_SHA" > "$changed_files"
  while IFS= read -r -d '' changed_path; do
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      # Intentional pattern matching; never evaluate paths or policy as code.
      if [[ "$changed_path" == $pattern ]]; then
        should_deploy=true
        break 2
      fi
    done <<< "$PRODUCTION_SOURCE_PATHS"
  done < "$changed_files"
else
  echo "Production scope only accepts main push or manual workflow events." >&2
  exit 1
fi

echo "Production should_deploy=$should_deploy"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "should_deploy=$should_deploy" >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '\n### Production scope\n\n- Undeployed production inputs: `%s`\n' \
    "$should_deploy" >> "$GITHUB_STEP_SUMMARY"
fi

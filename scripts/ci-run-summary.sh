#!/usr/bin/env bash
set -euo pipefail

summary_file="${GITHUB_STEP_SUMMARY:-}"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
workflow_name="${GITHUB_WORKFLOW:-unknown workflow}"
event_name="${GITHUB_EVENT_NAME:-unknown}"
ref_name="${GITHUB_REF_NAME:-${GITHUB_REF:-unknown}}"
sha="${GITHUB_SHA:-unknown}"
actor="${GITHUB_ACTOR:-unknown}"
run_number="${GITHUB_RUN_NUMBER:-unknown}"
run_attempt="${GITHUB_RUN_ATTEMPT:-unknown}"
purpose="${WORKFLOW_PURPOSE:-Not specified.}"
reason="${WORKFLOW_REASON:-Not specified.}"

cd "$repo_root"

event_before=""
event_after=""
if command -v jq >/dev/null 2>&1 && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ]; then
  event_before="$(jq -r '.before // .pull_request.base.sha // empty' "$GITHUB_EVENT_PATH")"
  event_after="$(jq -r '.after // .pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")"
fi

head_ref="${event_after:-$sha}"
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

category_lines="$(
  printf '%s\n' "$changed_files" | awk '
    NF == 0 { next }
    /^services\/supabase\// || /^scripts\/supabase-db-url\.sh$/ || /^\.github\/workflows\/deploy\.yml$/ {
      backend = 1
    }
    /^apps\/ios\// || /^apps\/watch\// || /^project\.yml$/ || /^merian\.xcodeproj\// || /^Merian\.xcodeproj\// || /^scripts\/check-ios-/ || /^scripts\/select-ios-/ || /^\.github\/workflows\/ios-/ {
      ios = 1
    }
    /^apps\/web\// {
      web = 1
    }
    /^docs\// || /^README\.md$/ || /^CHANGELOG\.md$/ {
      docs = 1
    }
    /^\.github\/workflows\// || /^scripts\/ci-/ {
      workflow = 1
    }
    END {
      if (backend) print "- Supabase/backend"
      if (ios) print "- iOS/app/schema"
      if (web) print "- Web"
      if (docs) print "- Docs"
      if (workflow) print "- Workflow/tooling"
      if (!backend && !ios && !web && !docs && !workflow) print "- No changed files resolved"
    }
  '
)"

changed_count="$(
  printf '%s\n' "$changed_files" | awk 'NF { count += 1 } END { print count + 0 }'
)"

write_summary() {
  {
    echo "### Workflow context"
    echo ""
    echo "- Workflow: \`${workflow_name}\`"
    echo "- Purpose: ${purpose}"
    echo "- Why this ran: ${reason}"
    echo "- Event: \`${event_name}\`"
    echo "- Ref: \`${ref_name}\`"
    echo "- Commit: \`${sha}\`"
    echo "- Actor: \`${actor}\`"
    echo "- Run: \`${run_number}\` attempt \`${run_attempt}\`"
    echo "- Changed files resolved: \`${changed_count}\`"
    echo ""
    echo "Changed-file categories:"
    echo "$category_lines"

    if [ "$changed_count" -gt 0 ]; then
      echo ""
      echo "<details><summary>Changed files</summary>"
      echo ""
      printf '%s\n' "$changed_files" | awk 'NF { print "- `" $0 "`" }' | head -n 100
      if [ "$changed_count" -gt 100 ]; then
        echo "- ...truncated after 100 files"
      fi
      echo ""
      echo "</details>"
    fi
  }
}

if [ -n "$summary_file" ]; then
  write_summary >> "$summary_file"
else
  write_summary
fi

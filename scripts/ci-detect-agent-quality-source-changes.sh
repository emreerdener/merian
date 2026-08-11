#!/usr/bin/env bash
set -euo pipefail

event_name="${EVENT_NAME:-pull_request}"
requested_suite="${REQUESTED_SUITE:-all}"
output_file="${GITHUB_OUTPUT:-}"

emit() {
  local key="$1"
  local value="$2"
  if [[ -n "$output_file" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$output_file"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

valid_suite() {
  case "$1" in
    all|ios|swiftdata|supabase|api-contracts|web-admin|release|agents) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ "$event_name" == "schedule" ]]; then
  emit should_run true
  emit suites '["all"]'
  emit reason nightly-full-suite
  exit 0
fi

if [[ "$event_name" == "workflow_dispatch" ]]; then
  valid_suite "$requested_suite" || {
    echo "Invalid Agent Quality suite: $requested_suite" >&2
    exit 1
  }
  emit should_run true
  emit suites "[\"$requested_suite\"]"
  emit reason manual-dispatch
  exit 0
fi

if [[ "$event_name" == "push" ]]; then
  emit should_run false
  emit suites '[]'
  emit reason push-runs-deterministic-validation-only
  exit 0
fi

changed_files=("$@")
if [[ ${#changed_files[@]} -eq 0 ]]; then
  base_sha="${BASE_SHA:-}"
  head_sha="${HEAD_SHA:-HEAD}"
  if [[ -z "$base_sha" ]]; then
    emit should_run true
    emit suites '["all"]'
    emit reason unknown-scope-missing-base
    exit 0
  fi
  if ! diff_output="$(git diff --name-only "$base_sha" "$head_sha")"; then
    emit should_run true
    emit suites '["all"]'
    emit reason unknown-scope-diff-failed
    exit 0
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] && changed_files+=("$path")
  done <<< "$diff_output"
fi

need_all=false
need_ios=false
need_swiftdata=false
need_supabase=false
need_api=false
need_web=false
need_release=false
need_agents=false
agent_scope=false

for path in "${changed_files[@]}"; do
  case "$path" in
    AGENTS.md|docs/development-guides/07-ai-agent-guidelines.md|docs/CONTRIBUTING.md|Makefile)
      agent_scope=true
      need_all=true
      ;;
    .github/workflows/agent-quality.yml|.github/codex/*|skills/evals/*|scripts/validate-agent-assets.ts|scripts/render-agent-eval-input.ts|scripts/score-agent-evals.ts|scripts/score-agent-evals_test.ts|scripts/ci-detect-agent-quality-source-changes.sh|scripts/test-ci-detect-agent-quality-source-changes.sh)
      agent_scope=true
      need_all=true
      ;;
    skills/merian-ios/*)
      agent_scope=true
      need_ios=true
      ;;
    skills/merian-swiftdata-migrations/*|.agents/workflows/schema_update.md|apps/ios/.agents/workflows/schema_update.md)
      agent_scope=true
      need_swiftdata=true
      ;;
    skills/merian-supabase/*|skills/user/supabase/*|skills/user/supabase-postgres-best-practices/*)
      agent_scope=true
      need_supabase=true
      ;;
    skills/merian-api-contracts/*|apps/ios/.agents/workflows/verify_api_contracts.md)
      agent_scope=true
      need_api=true
      ;;
    skills/merian-web-admin/*)
      agent_scope=true
      need_web=true
      ;;
    skills/merian-release/*|apps/ios/.agents/workflows/deploy_edge_functions.md|apps/ios/.agents/workflows/deploy_testflight.md|apps/ios/.agents/workflows/revenuecat_entitlements.md)
      agent_scope=true
      need_release=true
      ;;
    .codex/agents/*|.codex/config.toml)
      agent_scope=true
      need_agents=true
      ;;
    .agents/skills/*)
      agent_scope=true
      need_all=true
      ;;
    skills/merian-*|.agents/*|.codex/*)
      agent_scope=true
      need_all=true
      ;;
  esac
done

if [[ "$agent_scope" != true ]]; then
  emit should_run false
  emit suites '[]'
  emit reason no-agent-quality-scope
  exit 0
fi

if [[ "$need_all" == true ]]; then
  emit should_run true
  emit suites '["all"]'
  emit reason full-suite-required
  exit 0
fi

suite_json=""
append_suite() {
  local suite="$1"
  if [[ -n "$suite_json" ]]; then
    suite_json+=","
  fi
  suite_json+="\"$suite\""
}

[[ "$need_ios" == true ]] && append_suite ios
[[ "$need_swiftdata" == true ]] && append_suite swiftdata
[[ "$need_supabase" == true ]] && append_suite supabase
[[ "$need_api" == true ]] && append_suite api-contracts
[[ "$need_web" == true ]] && append_suite web-admin
[[ "$need_release" == true ]] && append_suite release
[[ "$need_agents" == true ]] && append_suite agents

emit should_run true
emit suites "[$suite_json]"
emit reason changed-suites

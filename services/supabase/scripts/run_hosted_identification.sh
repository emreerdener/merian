#!/usr/bin/env bash
# Called by the manual Actions workflow. Never print child diagnostics or secrets.
set +x
set -euo pipefail

hosted_repository="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
hosted_temporary="${RUNNER_TEMP:?RUNNER_TEMP is required}"
case "$hosted_repository,$hosted_temporary" in
  *$'\n'* | *$'\r'*) exit 1 ;;
esac
[[ "$hosted_repository" != *,* && "$hosted_temporary" != *,* && "$hosted_temporary" = /* ]]
hosted_packet="$hosted_temporary/identification-packet"
hosted_summary="$hosted_temporary/identification-public/summary.json"
cd "$hosted_repository"
hosted_common=(deno run --frozen --cached-only --no-prompt --config services/supabase/functions/deno.json
  "--allow-read=$hosted_repository,$hosted_temporary" "--allow-write=$hosted_temporary" --allow-run=git)
hosted_cli=services/supabase/scripts/host_identification_comparison.ts
hosted_evaluator=services/supabase/scripts/evaluate_identification.ts
[[ $# -ge 1 ]]
hosted_mode="$1"
shift

case "$hosted_mode" in
  fetch)
    [[ $# -eq 1 ]]
    "${hosted_common[@]}" --deny-env --allow-net=media.merian.app:443 "$hosted_cli" fetch "$hosted_packet" "$1"
    ;;
  bind-gemini)
    [[ $# -eq 0 ]]
    "${hosted_common[@]}" --deny-net --allow-env=GEMINI_PAID_API_KEY "$hosted_cli" bind "$hosted_packet" gemini
    ;;
  bind-openai)
    [[ $# -eq 0 ]]
    "${hosted_common[@]}" --deny-net --allow-env=OPENAI_EVALUATION_API_KEY "$hosted_cli" bind "$hosted_packet" openai
    ;;
  check | prepare)
    [[ $# -eq 0 ]]
    "${hosted_common[@]}" --deny-net --deny-env "$hosted_cli" "$hosted_mode" "$hosted_packet"
    ;;
  claim | publish)
    [[ "${R2_ACCOUNT_ID:-}" =~ ^[a-f0-9]{32}$ ]]
    hosted_storage_env=R2_ACCOUNT_ID,R2_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY,GITHUB_ACTIONS,GITHUB_REPOSITORY,GITHUB_REF,GITHUB_EVENT_NAME,GITHUB_SHA,GITHUB_RUN_ID,GITHUB_RUN_ATTEMPT
    if [[ "$hosted_mode" = claim ]]; then
      [[ $# -eq 1 ]]
      hosted_argument="$1"
    else
      [[ $# -eq 0 ]]
      hosted_argument="$hosted_summary"
    fi
    "${hosted_common[@]}" "--allow-net=$R2_ACCOUNT_ID.r2.cloudflarestorage.com:443" "--allow-env=$hosted_storage_env" \
      "$hosted_cli" "$hosted_mode" "$hosted_packet" "$hosted_argument"
    ;;
  run-gemini | run-openai)
    [[ $# -eq 0 && -s "$hosted_packet/hosted-claim.json" ]]
    if [[ "$hosted_mode" = run-gemini ]]; then
      hosted_provider=gemini
      hosted_environment=GEMINI_PAID_API_KEY,GOOGLE_SDK_NODE_LOGGING,GOOGLE_GENAI_DEBUG,WS_NO_BUFFER_UTIL,WS_NO_UTF_8_VALIDATE,GOOGLE_GENAI_USE_ENTERPRISE,GOOGLE_GENAI_USE_VERTEXAI,GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_LOCATION,GOOGLE_VERTEX_BASE_URL,GOOGLE_GEMINI_BASE_URL,GOOGLE_API_KEY,GEMINI_API_KEY
      "${hosted_common[@]}" --allow-net=generativelanguage.googleapis.com:443 "--allow-env=$hosted_environment" \
        --deny-env='SUPABASE_*,R2_*,OPENAI_*,GOOGLE_APPLICATION_CREDENTIALS' "$hosted_evaluator" --experiment-live "$hosted_packet" gemini-baseline
    else
      hosted_provider=openai
      # A provider can return exit 0 while durably stopping the experiment.
      "${hosted_common[@]}" --deny-net --deny-env "$hosted_cli" assert-complete "$hosted_packet" gemini
      "${hosted_common[@]}" --allow-net=api.openai.com:443 --allow-env=OPENAI_EVALUATION_API_KEY \
        --deny-env='SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY' "$hosted_evaluator" --experiment-live "$hosted_packet" openai-baseline
    fi
    "${hosted_common[@]}" --deny-net --deny-env "$hosted_cli" assert-complete "$hosted_packet" "$hosted_provider"
    ;;
  report)
    [[ $# -eq 0 ]]
    "${hosted_common[@]}" --deny-net --deny-env "$hosted_cli" report "$hosted_packet" "$hosted_summary"
    ;;
  *) exit 1 ;;
esac

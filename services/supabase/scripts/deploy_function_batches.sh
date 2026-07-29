#!/usr/bin/env bash
set -euo pipefail

plan_file="${1:?Usage: deploy_function_batches.sh <plan-file> <project-ref>}"
project_ref="${2:?Usage: deploy_function_batches.sh <plan-file> <project-ref>}"
batch_size="${MERIAN_FUNCTION_DEPLOY_BATCH_SIZE:-8}"
jobs="${MERIAN_FUNCTION_DEPLOY_JOBS:-4}"
max_attempts="${MERIAN_FUNCTION_DEPLOY_ATTEMPTS:-3}"

if ! [[ "$batch_size" =~ ^[1-9][0-9]*$ ]] ||
  ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]] ||
  ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
  echo "Deploy batch settings must be positive integers." >&2
  exit 2
fi

functions=()
while IFS= read -r function_name; do
  if [ -n "$function_name" ]; then
    functions+=("$function_name")
  fi
done < "$plan_file"
if [ "${#functions[@]}" -eq 0 ]; then
  echo "No Edge Functions require deployment."
  exit 0
fi

seen_functions=()
for function_name in "${functions[@]}"; do
  if ! [[ "$function_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid function name in deployment plan: $function_name" >&2
    exit 2
  fi
  if [ "${#seen_functions[@]}" -gt 0 ]; then
    for seen_function in "${seen_functions[@]}"; do
      if [ "$seen_function" = "$function_name" ]; then
        echo "Duplicate function name in deployment plan: $function_name" >&2
        exit 2
      fi
    done
  fi
  seen_functions+=("$function_name")
done

# A graph plan may contain any subset of the critical scan functions. Deploy
# every selected member in compatibility order before unrelated parallel
# batches: signing first, producers next, state/recovery consumers after them,
# and public Explore projection last.
critical_scan_rollout_order=(
  generate-upload-urls
  identify-multimodal
  identify
  identify-describe
  audio-spec
  check-scan-status
  reconcile-scan-media-assets
  repair-scan-image
  share-scan-to-explore
  request-community-identification
)
ordered_scan_functions=()
remaining_functions=()

is_critical_scan_function() {
  local candidate="$1"
  local critical_function
  for critical_function in "${critical_scan_rollout_order[@]}"; do
    if [ "$candidate" = "$critical_function" ]; then
      return 0
    fi
  done
  return 1
}

for critical_function in "${critical_scan_rollout_order[@]}"; do
  for function_name in "${functions[@]}"; do
    if [ "$function_name" = "$critical_function" ]; then
      ordered_scan_functions+=("$function_name")
    fi
  done
done
for function_name in "${functions[@]}"; do
  if ! is_critical_scan_function "$function_name"; then
    remaining_functions+=("$function_name")
  fi
done

deploy_one_with_retry() {
  local function_name="$1"
  local attempt
  for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
    if supabase functions deploy "$function_name" \
      --project-ref "$project_ref"; then
      return 0
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      local delay=$((attempt * 20))
      echo "$function_name failed; retrying that function in ${delay}s..." >&2
      sleep "$delay"
    fi
  done
  return 1
}

if [ "${#ordered_scan_functions[@]}" -gt 0 ]; then
  for function_name in "${ordered_scan_functions[@]}"; do
    echo "Deploying ordered critical scan function: $function_name"
    if ! deploy_one_with_retry "$function_name"; then
      echo "Ordered critical scan function deployment failed: $function_name" >&2
      exit 1
    fi
  done
fi

failed=()
if [ "${#remaining_functions[@]}" -gt 0 ]; then
  for ((offset = 0; offset < ${#remaining_functions[@]}; offset += batch_size)); do
    batch=("${remaining_functions[@]:offset:batch_size}")
    echo "Deploying function batch: ${batch[*]}"
    if supabase functions deploy "${batch[@]}" \
      --project-ref "$project_ref" \
      --jobs "$jobs"; then
      continue
    fi

    echo "Batch failed or partially deployed; isolating retries to its members." >&2
    for function_name in "${batch[@]}"; do
      if ! deploy_one_with_retry "$function_name"; then
        failed+=("$function_name")
      fi
    done
  done
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo "Edge Function deployment failed: ${failed[*]}" >&2
  exit 1
fi

echo "Deployed ${#functions[@]} planned Edge Functions."

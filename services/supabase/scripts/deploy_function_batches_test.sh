#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fake_log="$temp_dir/supabase.log"
fake_bin="$temp_dir/bin"
mkdir -p "$fake_bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$*" >> "$FAKE_SUPABASE_LOG"' \
  'if [[ "$*" == *"functions deploy good bad "* ]] && [[ "$*" == *" --jobs "* ]]; then' \
  '  exit 1' \
  'fi' \
  'if [ -n "${FAKE_SUPABASE_FAIL_FUNCTION:-}" ] && [[ "$*" == "functions deploy ${FAKE_SUPABASE_FAIL_FUNCTION} --project-ref "* ]]; then' \
  '  exit 1' \
  'fi' \
  'exit 0' > "$fake_bin/supabase"
chmod +x "$fake_bin/supabase"

printf '%s\n' good bad other > "$temp_dir/plan.txt"
PATH="$fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$fake_log" \
  MERIAN_FUNCTION_DEPLOY_BATCH_SIZE=2 \
  MERIAN_FUNCTION_DEPLOY_JOBS=1 \
  MERIAN_FUNCTION_DEPLOY_ATTEMPTS=2 \
  bash "$script_dir/deploy_function_batches.sh" \
  "$temp_dir/plan.txt" test-project >/dev/null 2>&1

expected_log="$temp_dir/expected.log"
printf '%s\n' \
  'functions deploy good bad --project-ref test-project --jobs 1' \
  'functions deploy good --project-ref test-project' \
  'functions deploy bad --project-ref test-project' \
  'functions deploy other --project-ref test-project --jobs 1' \
  > "$expected_log"

if ! cmp -s "$expected_log" "$fake_log"; then
  echo "Unexpected isolated-retry command sequence." >&2
  diff -u "$expected_log" "$fake_log" >&2 || true
  exit 1
fi

: > "$fake_log"
printf '%s\n' \
  share-scan-to-explore \
  other \
  repair-scan-image \
  identify \
  audio-spec \
  generate-upload-urls \
  reconcile-scan-media-assets \
  identify-describe \
  check-scan-status \
  identify-multimodal \
  request-community-identification \
  > "$temp_dir/ordered-plan.txt"
PATH="$fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$fake_log" \
  MERIAN_FUNCTION_DEPLOY_BATCH_SIZE=2 \
  MERIAN_FUNCTION_DEPLOY_JOBS=1 \
  MERIAN_FUNCTION_DEPLOY_ATTEMPTS=2 \
  bash "$script_dir/deploy_function_batches.sh" \
  "$temp_dir/ordered-plan.txt" test-project >/dev/null 2>&1

printf '%s\n' \
  'functions deploy generate-upload-urls --project-ref test-project' \
  'functions deploy identify-multimodal --project-ref test-project' \
  'functions deploy identify --project-ref test-project' \
  'functions deploy identify-describe --project-ref test-project' \
  'functions deploy audio-spec --project-ref test-project' \
  'functions deploy check-scan-status --project-ref test-project' \
  'functions deploy reconcile-scan-media-assets --project-ref test-project' \
  'functions deploy repair-scan-image --project-ref test-project' \
  'functions deploy share-scan-to-explore --project-ref test-project' \
  'functions deploy request-community-identification --project-ref test-project' \
  'functions deploy other --project-ref test-project --jobs 1' \
  > "$expected_log"

if ! cmp -s "$expected_log" "$fake_log"; then
  echo "Unexpected critical scan rollout command sequence." >&2
  diff -u "$expected_log" "$fake_log" >&2 || true
  exit 1
fi

: > "$fake_log"
printf '%s\n' generate-upload-urls identify > "$temp_dir/failing-ordered-plan.txt"
if PATH="$fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$fake_log" \
  FAKE_SUPABASE_FAIL_FUNCTION=generate-upload-urls \
  MERIAN_FUNCTION_DEPLOY_ATTEMPTS=1 \
  bash "$script_dir/deploy_function_batches.sh" \
  "$temp_dir/failing-ordered-plan.txt" test-project >/dev/null 2>&1; then
  echo "A failed ordered scan deployment must fail the rollout." >&2
  exit 1
fi
printf '%s\n' \
  'functions deploy generate-upload-urls --project-ref test-project' \
  > "$expected_log"
if ! cmp -s "$expected_log" "$fake_log"; then
  echo "An ordered scan failure must stop every later deployment." >&2
  diff -u "$expected_log" "$fake_log" >&2 || true
  exit 1
fi

printf '%s\n' 'not a function' > "$temp_dir/invalid-plan.txt"
if PATH="$fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$fake_log" \
  bash "$script_dir/deploy_function_batches.sh" \
  "$temp_dir/invalid-plan.txt" test-project >/dev/null 2>&1; then
  echo "Invalid function names must be rejected." >&2
  exit 1
fi

printf '%s\n' identify identify > "$temp_dir/duplicate-plan.txt"
if PATH="$fake_bin:$PATH" \
  FAKE_SUPABASE_LOG="$fake_log" \
  bash "$script_dir/deploy_function_batches.sh" \
  "$temp_dir/duplicate-plan.txt" test-project >/dev/null 2>&1; then
  echo "Duplicate function names must be rejected." >&2
  exit 1
fi

printf '%s\n' "deploy_function_batches tests passed."

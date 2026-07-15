#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
summary_script="$repo_root/scripts/ci-run-summary.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

git -C "$temp_dir" init -q
git -C "$temp_dir" config user.name "Merian CI"
git -C "$temp_dir" config user.email "ci@merian.test"

printf '%s\n' baseline > "$temp_dir/baseline.txt"
git -C "$temp_dir" add baseline.txt
git -C "$temp_dir" commit -qm "baseline"

for index in $(seq 1 105); do
  printf 'file %s\n' "$index" > "$temp_dir/file-$index.txt"
done
git -C "$temp_dir" add .
git -C "$temp_dir" commit -qm "large change"

summary_file="$temp_dir/summary.md"
(
  cd "$temp_dir"
  GITHUB_STEP_SUMMARY="$summary_file" \
    GITHUB_WORKFLOW="Summary regression" \
    GITHUB_EVENT_NAME="push" \
    GITHUB_REF_NAME="main" \
    GITHUB_SHA="$(git rev-parse HEAD)" \
    GITHUB_ACTOR="merian-ci" \
    GITHUB_RUN_NUMBER="1" \
    GITHUB_RUN_ATTEMPT="1" \
    WORKFLOW_PURPOSE="Exercise large changed-file summaries." \
    WORKFLOW_REASON="Regression coverage." \
    bash "$summary_script"
)

grep -Fq 'Changed files resolved: `105`' "$summary_file"
grep -Fq -- '- ...truncated after 100 files' "$summary_file"

rendered_file_count="$(grep -c '^- `file-' "$summary_file")"
if [ "$rendered_file_count" -ne 100 ]; then
  echo "Expected 100 rendered files, found $rendered_file_count." >&2
  exit 1
fi

echo "ci-run-summary large-change regression test passed."

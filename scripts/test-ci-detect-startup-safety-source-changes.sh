#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
detector="$repo_root/scripts/ci-detect-startup-safety-source-changes.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-startup-scope-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

test_repo="$test_root/repository"
mkdir -p "$test_repo/apps/ios/Merian/Core/Data/StoreRecovery" "$test_repo/docs"
git -C "$test_repo" init -q
git -C "$test_repo" config user.name "Startup Scope Test"
git -C "$test_repo" config user.email "startup-scope@example.invalid"
printf 'initial\n' > "$test_repo/docs/README.md"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm Initial
base="$(git -C "$test_repo" rev-parse HEAD)"

assert_event() {
  local expected="$1" event="$2" payload="$3" checkout="${4:-$test_repo}"
  local output
  output="$(cd "$checkout" && env -u GITHUB_SHA GITHUB_ACTIONS=true \
    GITHUB_EVENT_NAME="$event" GITHUB_EVENT_PATH="$payload" \
    GITHUB_OUTPUT="$test_root/outputs" GITHUB_STEP_SUMMARY="" bash "$detector")"
  if ! grep -Fq "startup simulator should_run=$expected" <<<"$output"; then
    echo "Expected $expected for $event ($payload): $output" >&2
    exit 1
  fi
}

push_event() {
  printf '{"before":"%s","after":"%s"}\n' "$1" "$2" > "$test_root/event.json"
}

# A valid docs-only range and a valid empty range may skip.
printf 'docs\n' >> "$test_repo/docs/README.md"
git -C "$test_repo" commit -qam Docs
docs_head="$(git -C "$test_repo" rev-parse HEAD)"
push_event "$base" "$docs_head"
assert_event false push "$test_root/event.json"

# Earlier scoped input must survive an unrelated tip commit.
scoped_path='apps/ios/Merian/Core/Data/StoreRecovery/Scope.swift'
printf 'startup\n' > "$test_repo/$scoped_path"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm Startup
startup_head="$(git -C "$test_repo" rev-parse HEAD)"
push_event "$startup_head" "$startup_head"
assert_event false push "$test_root/event.json"
printf 'tip\n' >> "$test_repo/docs/README.md"
git -C "$test_repo" commit -qam Tip
tip="$(git -C "$test_repo" rev-parse HEAD)"
push_event "$docs_head" "$tip"
assert_event true push "$test_root/event.json"

# Exact missing-base shallow-checkout regression; no network is involved.
git clone -q --depth 2 "file://$test_repo" "$test_root/shallow"
if git -C "$test_root/shallow" cat-file -e "$docs_head^{commit}" 2>/dev/null; then
  echo "The shallow fixture unexpectedly contains the event base" >&2
  exit 1
fi
assert_event true push "$test_root/event.json" "$test_root/shallow"

# New branches, missing refs, malformed payloads, and missing event files run.
push_event 0000000000000000000000000000000000000000 "$tip"
assert_event true push "$test_root/event.json"
push_event 1111111111111111111111111111111111111111 "$tip"
assert_event true push "$test_root/event.json"
printf '{"before":null,"after":123}\n' > "$test_root/event.json"
assert_event true push "$test_root/event.json"
printf 'invalid json\n' > "$test_root/event.json"
assert_event true push "$test_root/event.json"
assert_event true push "$test_root/missing.json"
assert_event true merge_group "$test_root/missing.json"
assert_event true workflow_dispatch "$test_root/missing.json"
assert_event true schedule "$test_root/missing.json"
assert_event true unknown_event "$test_root/missing.json"

# PR comparisons use the merge base, not the current target branch tip.
git -C "$test_repo" checkout -qb target "$docs_head"
mkdir -p "$test_repo/$(dirname "$scoped_path")"
printf 'target startup\n' > "$test_repo/$scoped_path"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm Target
pr_base="$(git -C "$test_repo" rev-parse HEAD)"
git -C "$test_repo" checkout -qb topic "$docs_head"
printf 'topic docs\n' >> "$test_repo/docs/README.md"
git -C "$test_repo" commit -qam Topic
pr_head="$(git -C "$test_repo" rev-parse HEAD)"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$pr_base" "$pr_head" > "$test_root/event.json"
assert_event false pull_request "$test_root/event.json"
mkdir -p "$test_repo/$(dirname "$scoped_path")"
printf 'topic startup\n' > "$test_repo/$scoped_path"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm TopicStartup
pr_head="$(git -C "$test_repo" rev-parse HEAD)"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  "$pr_base" "$pr_head" > "$test_root/event.json"
assert_event true pull_request "$test_root/event.json"
printf '{"pull_request":{"base":{"sha":"%s"},"head":{"sha":"%s"}}}\n' \
  1111111111111111111111111111111111111111 "$pr_head" > "$test_root/event.json"
assert_event true pull_request "$test_root/event.json"

# Deletions/renames out of the scoped tree must run, even with rename detection.
git -C "$test_repo" mv "$scoped_path" docs/Moved.swift
git -C "$test_repo" commit -qm MoveOut
moved_head="$(git -C "$test_repo" rev-parse HEAD)"
push_event "$pr_head" "$moved_head"
assert_event true push "$test_root/event.json"

# A resolved event whose git diff fails must not turn into a successful skip.
mkdir "$test_root/bin"
cat > "$test_root/bin/git" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1" == diff ]]; then exit 1; fi
exec "$MERIAN_SCOPE_REAL_GIT" "$@"
SHIM
chmod +x "$test_root/bin/git"
export MERIAN_SCOPE_REAL_GIT="$(command -v git)"
PATH="$test_root/bin:$PATH" assert_event true push "$test_root/event.json"

assert_local() {
  local expected="$1" output
  output="$(cd "$test_repo" && env -u GITHUB_ACTIONS -u GITHUB_EVENT_PATH \
    -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY GITHUB_EVENT_NAME=local bash "$detector")"
  grep -Fq "startup simulator should_run=$expected" <<<"$output" || {
    echo "Unexpected local scope: $output" >&2; exit 1;
  }
}
printf 'local docs\n' >> "$test_repo/docs/README.md"
assert_local false
# NUL-delimited handling preserves scoped filenames with embedded newlines.
printf 'untracked\n' > "$test_repo/apps/ios/Merian/Core/Data/StoreRecovery/Line
Break.swift"
assert_local true

echo "Startup safety scope detector regression tests passed."

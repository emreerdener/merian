#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repository_root/scripts/check-changed-markdown-format.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-markdown-format.XXXXXX")"

bash -n "$checker"
bash -n "$repository_root/scripts/test-check-changed-markdown-format.sh"

cleanup() {
  if [[ -n "$fixture_root" && -d "$fixture_root" ]]; then
    rm -rf "$fixture_root"
  fi
}
trap cleanup EXIT

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$fixture_root/failure.log" 2>&1; then
    echo "Expected failure: $label" >&2
    exit 1
  fi
}

cd "$fixture_root"
git init -q
git config user.name "Markdown Format Test"
git config user.email "markdown-format-test@example.invalid"

cat > legacy.md <<'EOF'
# Legacy

This deliberately unformatted legacy paragraph is long enough that Deno would reflow it if a whole-repository format check touched historical files that were outside the current change range.
EOF
cat > changed.md <<'EOF'
# Changed

Initially formatted.
EOF
git add legacy.md changed.md
git commit -qm "initial fixture"
base_commit="$(git rev-parse HEAD)"

cat > changed.md <<'EOF'
# Changed

This changed paragraph is deliberately long enough that the Deno Markdown formatter must reflow it and the range-aware checker must reject the candidate revision.
EOF
git add changed.md
git commit -qm "add an unformatted Markdown change"
expect_failure "unformatted Markdown in an explicit Git range" \
  bash "$checker" "$base_commit" HEAD

deno fmt changed.md >/dev/null
git add changed.md
git commit --amend --no-edit -q
bash "$checker" "$base_commit" HEAD >/dev/null

previous_commit="$(git rev-parse HEAD)"
git rm -q changed.md
printf 'non-Markdown changes are outside this gate\n' > source.txt
git add source.txt
git commit -qm "delete Markdown and add source"
bash "$checker" "$previous_commit" HEAD >/dev/null

type_change_base="$(git rev-parse HEAD)"
rm legacy.md
ln -s source.txt legacy.md
git add legacy.md
git commit -qm "replace Markdown with a symlink"
expect_failure "tracked Markdown type change" \
  bash "$checker" "$type_change_base" HEAD

cat > 'working tree.md' <<'EOF'
# Working tree

This untracked Markdown paragraph is deliberately long enough that local worktree validation must detect and reject it before the change is committed.
EOF
expect_failure "unformatted untracked Markdown" bash "$checker"
deno fmt 'working tree.md' >/dev/null
bash "$checker" >/dev/null

rm 'working tree.md'
ln -s legacy.md linked.md
expect_failure "changed Markdown symlink" bash "$checker"

echo "Changed Markdown format checker tests passed."

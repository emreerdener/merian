#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bash scripts/check-changed-markdown-format.sh
  bash scripts/check-changed-markdown-format.sh <base-revision> <head-revision>

With no revisions, checks changed tracked and untracked Markdown in the working
tree. With two revisions, checks added, copied, modified, and renamed Markdown
across the complete Git range. Deleted files are ignored.
EOF
}

if [[ $# -ne 0 && $# -ne 2 ]]; then
  usage
  exit 2
fi

command -v deno >/dev/null 2>&1 || {
  echo "Deno is required to validate Markdown formatting." >&2
  exit 1
}

repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Run the Markdown format checker from inside a Git repository." >&2
  exit 1
}
cd "$repository_root"

markdown_files=()

append_markdown_path() {
  local path="$1"
  if [[ -L "$path" ]]; then
    echo "Changed Markdown must be a regular repository file, not a symlink: $path" >&2
    exit 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "Changed Markdown path is not a regular file: $path" >&2
    exit 1
  fi
  markdown_files+=("./$path")
}

if [[ $# -eq 0 ]]; then
  while IFS= read -r -d '' path; do
    append_markdown_path "$path"
  done < <(git diff --name-only --diff-filter=ACMRT -z HEAD -- '*.md')

  while IFS= read -r -d '' path; do
    append_markdown_path "$path"
  done < <(git ls-files --others --exclude-standard -z -- '*.md')
else
  base_commit="$(git rev-parse --verify "$1^{commit}" 2>/dev/null)" || {
    echo "Invalid Markdown comparison base revision: $1" >&2
    exit 1
  }
  head_commit="$(git rev-parse --verify "$2^{commit}" 2>/dev/null)" || {
    echo "Invalid Markdown comparison head revision: $2" >&2
    exit 1
  }

  while IFS= read -r -d '' path; do
    append_markdown_path "$path"
  done < <(
    git diff --name-only --diff-filter=ACMRT -z \
      "$base_commit" "$head_commit" -- '*.md'
  )
fi

if [[ ${#markdown_files[@]} -eq 0 ]]; then
  echo "No changed Markdown files require formatting validation."
  exit 0
fi

echo "Checking ${#markdown_files[@]} changed Markdown file(s)."
deno fmt --check "${markdown_files[@]}"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${MERIAN_PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"

fail() {
  echo "error: Could not fingerprint iOS release source: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is unavailable."
command -v perl >/dev/null 2>&1 || fail "perl is unavailable."
command -v shasum >/dev/null 2>&1 || fail "shasum is unavailable."
git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "$repo_root is not a git worktree."

tracked_xcode_user_state="$(
  git -C "$repo_root" ls-files \
    | awk '
        $0 ~ "(^|/)xcuserdata/" ||
        $0 ~ "(^|/)[^/]+[.]xcuserdatad/" {
          print
          exit
        }
      '
)"
if [[ -n "$tracked_xcode_user_state" ]]; then
  fail "tracked Xcode user state is nondeterministic release source: $tracked_xcode_user_state. Remove it from Git; xcuserdata is already ignored."
fi

hidden_index_path="$(
  git -C "$repo_root" ls-files -v \
    | awk '
        /^[a-zS][[:space:]]/ {
          sub(/^[^[:space:]]+[[:space:]]+/, "")
          print
          exit
        }
      '
)"
if [[ -n "$hidden_index_path" ]]; then
  fail "tracked source uses assume-unchanged or skip-worktree index state: ${hidden_index_path}. Clear hidden index flags and use a complete checkout."
fi

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-ios-source-fingerprint.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT
path_file="$temp_root/paths"
metadata_file="$temp_root/metadata"
hash_file="$temp_root/hashes"
manifest_file="$temp_root/manifest"

source_count=0
regular_count=0
while IFS= read -r -d '' relative_path; do
  full_path="$repo_root/$relative_path"
  if [[ "$relative_path" == *$'\n'* ||
        "$relative_path" == *$'\r'* ||
        "$relative_path" == *$'\t'* ]]; then
    fail "source paths containing tabs or line breaks are unsupported."
  fi

  if [[ -L "$full_path" ]]; then
    blob="$(
      perl -e '
        my $target = readlink($ARGV[0]);
        die "readlink failed\n" unless defined $target;
        print $target;
      ' "$full_path" \
        | git hash-object --stdin
    )"
    printf '120000\t%s\t%s\n' "$blob" "$relative_path" >> "$manifest_file"
  elif [[ -f "$full_path" ]]; then
    mode="100644"
    if [[ -x "$full_path" ]]; then
      mode="100755"
    fi
    printf '%s\n' "$relative_path" >> "$path_file"
    printf '%s\t%s' "$mode" "$relative_path" >> "$metadata_file"
    printf '\n' >> "$metadata_file"
    regular_count=$((regular_count + 1))
  elif [[ -d "$full_path" ]]; then
    # A tracked directory is a gitlink. Preserve its exact staged object ID.
    index_mode="$(
      git -C "$repo_root" ls-files --stage -- "$relative_path" \
        | awk 'NR == 1 { print $1 }'
    )"
    blob="$(
      git -C "$repo_root" ls-files --stage -- "$relative_path" \
        | awk 'NR == 1 { print $2 }'
    )"
    [[ "$index_mode" == "160000" ]] \
      || fail "source path unexpectedly resolved to a directory: $relative_path."
    [[ "$blob" =~ ^[0-9a-f]{40,64}$ ]] \
      || fail "could not resolve gitlink $relative_path."
    printf '160000\t%s\t%s\n' "$blob" "$relative_path" >> "$manifest_file"
  else
    # A deleted tracked path contributes no bytes before or after its deletion
    # is committed, keeping the same filesystem snapshot fingerprint.
    continue
  fi

  source_count=$((source_count + 1))
done < <(
  git -C "$repo_root" ls-files \
    --cached \
    --others \
    --exclude-standard \
    -z
)

(( source_count > 0 )) || fail "the worktree has no nonignored source files."

if (( regular_count > 0 )); then
  (
    cd "$repo_root"
    git hash-object --no-filters --stdin-paths < "$path_file"
  ) > "$hash_file"

  hash_count="$(wc -l < "$hash_file" | tr -d '[:space:]')"
  [[ "$hash_count" == "$regular_count" ]] \
    || fail "git hashed $hash_count of $regular_count tracked files."
  paste "$metadata_file" "$hash_file" >> "$manifest_file"
fi

LC_ALL=C sort "$manifest_file" -o "$manifest_file"
fingerprint="$(shasum -a 256 "$manifest_file" | awk '{ print $1 }')"
[[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] \
  || fail "shasum returned an invalid digest."

printf '%s\n' "$fingerprint"

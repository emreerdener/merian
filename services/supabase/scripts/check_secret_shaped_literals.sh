#!/usr/bin/env bash
set -euo pipefail

secret_literal_script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"
secret_literal_repository_root="$(
  cd -- "$secret_literal_script_dir/../../.." &&
    pwd
)"
secret_literal_scan_root="${1:-$secret_literal_repository_root}"
secret_literal_pattern='sb_secret_[A-Za-z0-9_-]{20,}'

# Current Supabase secret keys must only enter the process through encrypted
# environment configuration. Tests construct format-valid fakes from separate
# fragments so neither fixtures nor documentation resemble a usable key.
if command -v rg >/dev/null 2>&1; then
  matching_paths="$(
    rg \
      --files-with-matches \
      --hidden \
      --glob '!.git/**' \
      --glob '!**/node_modules/**' \
      --glob '!**/.next/**' \
      "$secret_literal_pattern" \
      "$secret_literal_scan_root" ||
      true
  )"
else
  # GitHub's hosted runner image does not guarantee ripgrep. Keep the security
  # gate operational with tools available on every supported runner rather than
  # weakening the scan or adding a mutable package-install step.
  matching_paths="$(
    find "$secret_literal_scan_root" \
      -type d \
      \( -name .git -o -name node_modules -o -name .next \) \
      -prune -o \
      -type f \
      -exec grep -EIl "$secret_literal_pattern" {} + ||
      true
  )"
fi

if [ -n "$matching_paths" ]; then
  echo "Complete Supabase secret-shaped literals are forbidden in repository files." >&2
  echo "Construct test values from separate fragments. Matching files:" >&2
  printf '%s\n' "$matching_paths" >&2
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

secret_literal_test_script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"
secret_literal_test_temp_dir="$(mktemp -d)"
trap 'rm -rf "$secret_literal_test_temp_dir"' EXIT

clean_fixture_dir="$secret_literal_test_temp_dir/clean"
blocked_fixture_dir="$secret_literal_test_temp_dir/blocked"
portable_bin_dir="$secret_literal_test_temp_dir/portable-bin"
mkdir -p "$clean_fixture_dir" "$blocked_fixture_dir" "$portable_bin_dir"

printf '%s\n' \
  'const fakeKey = ["sb", "secret", "fixture", "a".repeat(20)].join("_");' \
  > "$clean_fixture_dir/fixture.ts"

bash \
  "$secret_literal_test_script_dir/check_secret_shaped_literals.sh" \
  "$clean_fixture_dir"

secret_fragment="secret"
blocked_literal="sb_${secret_fragment}_fixture_aaaaaaaaaaaaaaaaaaaa"
printf '%s\n' "const leakedFixture = \"$blocked_literal\";" \
  > "$blocked_fixture_dir/fixture.ts"

for portable_command in dirname find grep; do
  ln -s "$(command -v "$portable_command")" \
    "$portable_bin_dir/$portable_command"
done

for scanner in ripgrep portable; do
  blocked_output="$secret_literal_test_temp_dir/$scanner-blocked-output.txt"
  if [ "$scanner" = portable ]; then
    PATH="$portable_bin_dir" /bin/bash \
      "$secret_literal_test_script_dir/check_secret_shaped_literals.sh" \
      "$clean_fixture_dir"
    if PATH="$portable_bin_dir" /bin/bash \
      "$secret_literal_test_script_dir/check_secret_shaped_literals.sh" \
      "$blocked_fixture_dir" >"$blocked_output" 2>&1; then
      echo "Portable secret-shaped literal gate accepted a complete provider-shaped value." >&2
      exit 1
    fi
  elif bash \
    "$secret_literal_test_script_dir/check_secret_shaped_literals.sh" \
    "$blocked_fixture_dir" >"$blocked_output" 2>&1; then
    echo "Secret-shaped literal gate accepted a complete provider-shaped value." >&2
    exit 1
  fi

  if grep -Fq "$blocked_literal" "$blocked_output"; then
    echo "Secret-shaped literal gate exposed the matching value in diagnostics." >&2
    exit 1
  fi
  if ! grep -Fq "fixture.ts" "$blocked_output"; then
    echo "Secret-shaped literal gate did not identify the matching file." >&2
    exit 1
  fi
done

printf '%s\n' "check_secret_shaped_literals tests passed."

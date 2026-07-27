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
mkdir -p "$clean_fixture_dir" "$blocked_fixture_dir"

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

blocked_output="$secret_literal_test_temp_dir/blocked-output.txt"
if bash \
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

printf '%s\n' "check_secret_shaped_literals tests passed."


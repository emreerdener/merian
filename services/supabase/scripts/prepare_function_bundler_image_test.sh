#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/merian-bundler-image-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir "$test_root/bin"
cat > "$test_root/bin/supabase" <<'MOCK'
#!/usr/bin/env bash
echo "${MOCK_CLI_VERSION:-2.109.1}"
MOCK
cat > "$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$MOCK_LOG"
case "$1" in
  info) test "${MOCK_DOCKER_DOWN:-0}" = 0 ;;
  image) test -f "$MOCK_CACHE" ;;
  pull) test "$2" = "$MOCK_MIRROR" || exit 1
        if [[ "$2" == public.ecr.aws/* ]]; then touch "$MOCK_CACHE"; fi ;;
  tag) test "${MOCK_TAG_FAIL:-0}" = 0 || exit 1
       touch "$MOCK_CACHE" ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
export MOCK_LOG="$test_root/log" MOCK_CACHE="$test_root/cache"
export MOCK_MIRROR=none
canonical=public.ecr.aws/supabase/edge-runtime:v1.74.2
reset_case() { rm -f "$MOCK_CACHE"; : > "$MOCK_LOG"; }
expect_failure() {
  if bash "$script_dir/prepare_function_bundler_image.sh" >/dev/null 2>&1; then
    echo "Unsafe bundler preparation unexpectedly passed." >&2
    exit 1
  fi
}
reset_case
touch "$MOCK_CACHE"
bash "$script_dir/prepare_function_bundler_image.sh" >/dev/null
! grep -q '^pull ' "$MOCK_LOG"
for mirror in "$canonical" ghcr.io/supabase/edge-runtime:v1.74.2 supabase/edge-runtime:v1.74.2; do
  reset_case
  export MOCK_MIRROR="$mirror"
  bash "$script_dir/prepare_function_bundler_image.sh" >/dev/null 2>&1
  test -f "$MOCK_CACHE"
  grep -qx "pull $mirror" "$MOCK_LOG"
  if [ "$mirror" != "$canonical" ]; then
    grep -qx "tag $mirror $canonical" "$MOCK_LOG"
  fi
done
reset_case
export MOCK_MIRROR=none
expect_failure
test "$(grep -c '^pull ' "$MOCK_LOG")" = 3
reset_case
MOCK_DOCKER_DOWN=1 expect_failure
! grep -q '^pull ' "$MOCK_LOG"
reset_case
MOCK_CLI_VERSION=2.90.0 expect_failure
test ! -s "$MOCK_LOG"
reset_case
MOCK_MIRROR=ghcr.io/supabase/edge-runtime:v1.74.2 MOCK_TAG_FAIL=1 expect_failure
! grep -qx 'pull supabase/edge-runtime:v1.74.2' "$MOCK_LOG"
echo "Pinned Function bundler mirror regression tests passed."

#!/usr/bin/env bash
set -euo pipefail

net_scope_test_script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"
net_scope_script="$net_scope_test_script_dir/deno_postgres_net_scope.sh"

assert_equals() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$actual" != "$expected" ]; then
    printf 'Expected %s to be %q, received %q.\n' \
      "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

ipv4_scope="$(
  MERIAN_DATABASE_URL='postgresql://user:redacted@127.0.0.1:6543/postgres?sslmode=require' \
    bash "$net_scope_script"
)"
assert_equals '127.0.0.1:6543' "$ipv4_scope" "the IPv4 scope"

ipv6_scope="$(
  MERIAN_DATABASE_URL='postgres://user:redacted@[::1]:6544/postgres' \
    bash "$net_scope_script"
)"
assert_equals '[::1]:6544' "$ipv6_scope" "the IPv6 scope"

localhost_scope="$(
  MERIAN_DATABASE_URL='postgresql://user:redacted@localhost:6545/postgres' \
    bash "$net_scope_script"
)"
case ",$localhost_scope," in
  *,localhost:6545,*)
    ;;
  *)
    echo "The DNS scope did not retain the configured hostname." >&2
    exit 1
    ;;
esac
case ",$localhost_scope," in
  *,127.0.0.1:6545,* | *,\[::1\]:6545,*)
    ;;
  *)
    echo "The DNS scope did not include a resolved loopback address." >&2
    exit 1
    ;;
esac
if [[ "$localhost_scope" == *redacted* ]]; then
  echo "The PostgreSQL network scope exposed URL credentials." >&2
  exit 1
fi

if MERIAN_DATABASE_URL='https://localhost/database' \
  bash "$net_scope_script" >/dev/null 2>&1; then
  echo "A non-PostgreSQL URL unexpectedly produced a network scope." >&2
  exit 1
fi

if MERIAN_DATABASE_URL='' bash "$net_scope_script" >/dev/null 2>&1; then
  echo "A missing PostgreSQL URL unexpectedly produced a network scope." >&2
  exit 1
fi

if MERIAN_DATABASE_URL='postgresql://user:do-not-print@localhost:not-a-port/postgres' \
  bash "$net_scope_script" >/dev/null 2>&1; then
  echo "An invalid PostgreSQL port unexpectedly produced a network scope." >&2
  exit 1
fi

if MERIAN_DATABASE_URL='postgresql://user:do-not-print@localhost:0/postgres' \
  bash "$net_scope_script" >/dev/null 2>&1; then
  echo "PostgreSQL port zero unexpectedly produced a network scope." >&2
  exit 1
fi

printf '%s\n' "deno_postgres_net_scope tests passed."

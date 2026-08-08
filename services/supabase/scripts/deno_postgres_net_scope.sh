#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: MERIAN_DATABASE_URL=... deno_postgres_net_scope.sh" >&2
  exit 2
fi

if [ -z "${MERIAN_DATABASE_URL:-}" ]; then
  echo "MERIAN_DATABASE_URL is required to resolve the PostgreSQL network scope." >&2
  exit 1
fi

# postgres uses Deno's Node TCP compatibility layer. Deno 2.9 rechecks the
# resolved peer address, so the least-privilege scope must contain both the
# configured hostname and every address returned immediately before execution.
python3 - <<'PY'
import ipaddress
import os
import socket
import sys
from urllib.parse import urlsplit


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


try:
    database_url = urlsplit(os.environ["MERIAN_DATABASE_URL"])
except ValueError:
    fail("MERIAN_DATABASE_URL is not a valid PostgreSQL URL.")

if database_url.scheme not in {"postgres", "postgresql"}:
    fail("MERIAN_DATABASE_URL must use the postgres or postgresql scheme.")

try:
    hostname = database_url.hostname
    configured_port = database_url.port
except ValueError:
    fail("MERIAN_DATABASE_URL contains an invalid PostgreSQL port.")

port = 5432 if configured_port is None else configured_port
if not hostname:
    fail("MERIAN_DATABASE_URL must contain a PostgreSQL hostname.")
if not 1 <= port <= 65535:
    fail("MERIAN_DATABASE_URL contains an invalid PostgreSQL port.")

try:
    configured_address = ipaddress.ip_address(hostname)
except ValueError:
    try:
        normalized_hostname = (
            hostname.encode("idna").decode("ascii").lower().rstrip(".")
        )
    except UnicodeError:
        fail("MERIAN_DATABASE_URL contains an invalid PostgreSQL hostname.")
    if not normalized_hostname or any(
        character.isspace() or character in {",", "[", "]"}
        for character in normalized_hostname
    ):
        fail("MERIAN_DATABASE_URL contains an invalid PostgreSQL hostname.")
else:
    normalized_hostname = configured_address.compressed

try:
    resolved = socket.getaddrinfo(
        normalized_hostname,
        port,
        family=socket.AF_UNSPEC,
        type=socket.SOCK_STREAM,
        proto=socket.IPPROTO_TCP,
    )
except OSError:
    fail("Unable to resolve the configured PostgreSQL network scope.")

resolved_addresses = set()
for result in resolved:
    try:
        resolved_addresses.add(ipaddress.ip_address(result[4][0]))
    except ValueError:
        fail("The configured PostgreSQL hostname resolved to an invalid address.")

if not resolved_addresses:
    fail("The configured PostgreSQL hostname resolved to no addresses.")


def scope_entry(host: str, host_port: int) -> str:
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return f"{host}:{host_port}"
    if address.version == 6:
        return f"[{address.compressed}]:{host_port}"
    return f"{address.compressed}:{host_port}"


scope = [scope_entry(normalized_hostname, port)]
for address in sorted(
    resolved_addresses,
    key=lambda item: (item.version, int(item)),
):
    entry = scope_entry(address.compressed, port)
    if entry not in scope:
        scope.append(entry)

print(",".join(scope))
PY

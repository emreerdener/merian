#!/usr/bin/env bash
set -euo pipefail

require=false
if [ "${1:-}" = "--require" ]; then
  require=true
  shift
fi

if [ "$#" -ne 0 ]; then
  echo "Usage: scripts/supabase-db-url.sh [--require]" >&2
  exit 2
fi

if [ -n "${SUPABASE_DB_PUSH_URL:-}" ]; then
  printf '%s\n' "$SUPABASE_DB_PUSH_URL"
  exit 0
fi

if [ -n "${SUPABASE_DB_URL:-}" ]; then
  printf '%s\n' "$SUPABASE_DB_URL"
  exit 0
fi

if [ -z "${SUPABASE_DB_PASSWORD:-}" ] && [ -z "${SUPABASE_DB_POOLER_HOST:-}" ]; then
  if [ "$require" = true ]; then
    echo "Missing database connection config. Set SUPABASE_DB_URL, or set SUPABASE_DB_POOLER_HOST plus SUPABASE_DB_PASSWORD." >&2
    exit 1
  fi

  exit 0
fi

if [ -z "${SUPABASE_DB_PASSWORD:-}" ]; then
  echo "Missing SUPABASE_DB_PASSWORD. Set SUPABASE_DB_URL, or set SUPABASE_DB_POOLER_HOST plus SUPABASE_DB_PASSWORD." >&2
  exit 1
fi

if [ -z "${SUPABASE_DB_POOLER_HOST:-}" ]; then
  echo "Missing SUPABASE_DB_POOLER_HOST. Set SUPABASE_DB_URL, or set SUPABASE_DB_POOLER_HOST plus SUPABASE_DB_PASSWORD." >&2
  exit 1
fi

project_id="${PROJECT_ID:-${SUPABASE_PROJECT_ID:-}}"
if [ -z "$project_id" ]; then
  echo "Missing PROJECT_ID or SUPABASE_PROJECT_ID for the Supabase pooler user." >&2
  exit 1
fi

pooler_host="$SUPABASE_DB_POOLER_HOST"
case "$pooler_host" in
  *://*|*/*)
    echo "SUPABASE_DB_POOLER_HOST must be a host only, for example aws-0-us-east-1.pooler.supabase.com." >&2
    exit 1
    ;;
  *.pooler.supabase.com)
    ;;
  *)
    echo "SUPABASE_DB_POOLER_HOST must be a Supabase shared pooler host, for example aws-0-us-east-1.pooler.supabase.com." >&2
    exit 1
    ;;
esac

pooler_port="${SUPABASE_DB_POOLER_PORT:-5432}"
case "$pooler_port" in
  ''|*[!0-9]*)
    echo "SUPABASE_DB_POOLER_PORT must be numeric." >&2
    exit 1
    ;;
esac

db_name="${SUPABASE_DB_NAME:-postgres}"
encoded_password="$(
  python3 - <<'PY'
import os
from urllib.parse import quote

print(quote(os.environ["SUPABASE_DB_PASSWORD"], safe=""))
PY
)"

printf 'postgresql://postgres.%s:%s@%s:%s/%s?sslmode=require\n' \
  "$project_id" \
  "$encoded_password" \
  "$pooler_host" \
  "$pooler_port" \
  "$db_name"

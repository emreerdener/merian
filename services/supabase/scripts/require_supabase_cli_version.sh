#!/usr/bin/env bash
set -euo pipefail

# Database replay, migration transaction boundaries, config parsing, and
# deployment commands are reviewed as one toolchain contract. Do not loosen
# this to a minimum-version check: changing the pin requires rerunning the full
# migration, catalog, Edge, and deployment-tooling suites.
required_supabase_cli_version="2.109.1"

export SUPABASE_TELEMETRY_DISABLED="${SUPABASE_TELEMETRY_DISABLED:-1}"

if ! command -v supabase >/dev/null 2>&1; then
  printf 'Supabase CLI %s is required, but supabase is not on PATH.\n' \
    "$required_supabase_cli_version" >&2
  exit 1
fi

if ! installed_supabase_cli_version="$(supabase --version 2>/dev/null)"; then
  printf 'Supabase CLI %s is required, but the installed CLI version could not be read.\n' \
    "$required_supabase_cli_version" >&2
  exit 1
fi

# The reviewed CLI prints one bare semantic version. Accept its optional "v"
# prefix, but reject update notices or any other ambiguous multi-line output.
case "$installed_supabase_cli_version" in
  "$required_supabase_cli_version" | "v$required_supabase_cli_version")
    ;;
  *)
    printf 'Supabase CLI %s is required; found %s. Use the exact reviewed version before database or deployment verification.\n' \
      "$required_supabase_cli_version" \
      "${installed_supabase_cli_version:-unrecognized output}" >&2
    exit 1
    ;;
esac

printf 'Validated Supabase CLI %s.\n' "$required_supabase_cli_version"

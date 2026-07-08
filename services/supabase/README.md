# Merian Supabase Backend

The Supabase backend for Merian. This directory contains the PostgreSQL database migrations, Deno Edge Functions, and related configuration.

## Structure

```text
services/supabase/
  config.toml      # Supabase CLI and Edge Function configuration
  functions/       # Deno Edge Functions (e.g., identify-multimodal)
  migrations/      # PostgreSQL database migrations
  scripts/         # Helper scripts for backend tasks
  test_auth.ts     # Auth testing utilities
```

## Edge Functions

Edge Functions are written in TypeScript and run on Deno. They handle logic like AI inference (`identify-multimodal`), gamification telemetry, public user profile updates, and Explore feed projections.

- **Configuration**: Every new Edge Function MUST have a `[functions.<name>]` entry in `config.toml`. Pay attention to `verify_jwt` (set to `false` for app-facing anonymous-compatible functions to bypass gateway-level JWT validation, allowing the function to handle validation internally).
- **Dependencies**: Runtime Edge dependencies are resolved through `functions/deno.json`.

### Testing Edge Functions

Before opening a PR targeting `services/supabase/functions`, run formatting, linting, and type checking:

```bash
cd services/supabase/functions
deno fmt --check
deno lint --config deno.json
deno check --config deno.json <changed edge files>
```

Run Deno tests:
```bash
deno test --config deno.json --allow-env --allow-net _tests/
```

### Testing Database Migrations

Media durability migrations have an additional static contract test that runs
without a local Postgres instance. It checks the normalized scan-media lifecycle
schema, the scan-ingestion job ledger, and the drift-repair SQL that must run
before media reconciliation indexes are created.

Field Trips migrations also have static contract coverage. The current chain is
V1 template/progress/publication storage, V2 guided detail/start/pins, V3
Community/activity, and V4 curated Seasonal Challenges with explicit joins,
challenge progress, badges, challenge entries, and optional Explore hashtag
suggestions.

From the repo root:

```bash
make validate-supabase-migrations
```

## Local Development

From the repo root, point the Supabase CLI at the backend service directory:

```bash
# Start local Supabase stack
supabase --workdir services start

# Serve edge functions locally
supabase --workdir services functions serve <function_name>
```

## Deployment

### Database Migrations
```bash
supabase --workdir services db push
```

### Edge Functions
```bash
supabase --workdir services functions deploy
```

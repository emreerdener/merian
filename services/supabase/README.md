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

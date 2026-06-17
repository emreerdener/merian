# Supabase Deployment Runbook

Merian's long-term Supabase release path is GitHub Actions, not an
interactive developer shell. Local `supabase login` is useful for emergency
maintenance, but production deploys should be repeatable from CI with explicit
secrets and validation.

## Production Path

Pushes to `main` and manual `workflow_dispatch` runs execute
`.github/workflows/deploy.yml`.

The workflow performs the following steps:

1. Installs Deno 2, matching `services/supabase/config.toml`.
2. Installs the Supabase CLI.
3. Fails fast if required deployment secrets are missing.
4. Validates Edge Function formatting, lint, type checks, and focused shared
   helper tests.
5. Links the Supabase project.
6. Pushes database migrations.
7. Deploys all configured Edge Functions with `supabase functions deploy
   --import-map supabase/functions/deno.json`.

Deploying all configured functions is intentional. Shared modules such as
`functions/_shared/aws.ts`, `functions/_shared/mediaBudgets.ts`, and
`functions/_shared/concurrency.ts` are bundled into each dependent Edge
Function at deploy time; deploying a hand-maintained partial list risks leaving
production on mixed helper versions.

The deploy command explicitly passes `services/supabase/functions/deno.json`
because many existing functions still import the historical
`https://esm.sh/@supabase/supabase-js@2.49.1` specifier. The import map remaps
that exact URL to Supabase's recommended npm package specifier for Edge
Functions, avoiding deploy-time failures when esm.sh returns transient 5xx
responses while the Supabase bundler creates each function graph.

## Required GitHub Secrets

Set these in the repository's GitHub Actions secrets:

- `SUPABASE_ACCESS_TOKEN` — Supabase CLI access token for the deployment actor.
- `SUPABASE_DB_PASSWORD` — database password used by `supabase link` and
  `supabase db push`.

The production Supabase project ref is intentionally stored in the workflow as
`qlarqavoqhkuwzmevrmf`. Project refs are routing identifiers, not credentials;
the deployment authority still comes from `SUPABASE_ACCESS_TOKEN` and
`SUPABASE_DB_PASSWORD`.

The workflow also inherits normal Supabase project Edge secrets at runtime.
Those live in Supabase, not GitHub Actions, and are documented in
`docs/backend-and-data/02-supabase-edge-and-database.md`.

## Manual Production Deploy

Use the manual GitHub Actions dispatch first:

1. Open the GitHub repository.
2. Go to **Actions**.
3. Select **Deploy Merian to Supabase**.
4. Click **Run workflow** on `main`.

This keeps deploy logs, validation, migration push, and function deployment in
one auditable place.

## Local Emergency Fallback

Only use the local path when GitHub Actions is unavailable.

```bash
cd /Users/emreerdener/Developer/merian

deno check \
  services/supabase/functions/_shared/aws.ts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/concurrency.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/update-public-avatar/index.ts \
  services/supabase/functions/auto-purge-nonbio/index.ts \
  services/supabase/functions/delete-scan/index.ts

deno test \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/update-public-avatar/avatar_test.ts

make db-push
supabase --workdir services functions deploy --import-map services/supabase/functions/deno.json
```

If `make db-push` reports a missing access token, authenticate the local CLI:

```bash
supabase login
```

For non-interactive local environments, export `SUPABASE_ACCESS_TOKEN` and
`SUPABASE_DB_PASSWORD` instead of relying on a browser login or password prompt.

## Post-Deploy Smoke Checks

After deployment:

- Confirm `supabase db push` applied the newest migration.
- Confirm `auto-purge-nonbio` and `delete-scan` were deployed after any
  `_shared/aws.ts` change.
- Confirm `update-public-avatar` was deployed after
  `20260528120000_add_custom_public_avatars.sql`.
- Inspect Cloudflare R2 lifecycle rules against `docs/r2-lifecycle.json` and
  confirm there is no enabled expiration rule for `avatars/`.
- Run one staging purge or safe delete and inspect Edge logs for bounded R2
  fanout, delete failures, duration spikes, and memory pressure.
- Upload a custom avatar, then run/inspect scan purge flows and confirm the
  `https://media.merian.app/avatars/{userId}/...` URL remains available.
- Confirm cron-triggered purge endpoints still receive service-role
  authorization from Supabase Vault/pg_net.

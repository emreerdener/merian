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
8. Smoke-tests the Community Taxonomy status endpoint and a dry-run bounded GBIF
   import with the production service-role credential.

Actual GBIF taxonomy imports are intentionally separated into
`.github/workflows/import-community-taxonomy.yml`. The deploy workflow only
smoke-tests a dry run; it does not write taxonomy rows or advance import
cursors.

Deploying all configured functions is intentional. Shared modules such as
`functions/_shared/aws.ts`, `functions/_shared/mediaBudgets.ts`, and
`functions/_shared/concurrency.ts` are bundled into each dependent Edge
Function at deploy time; deploying a hand-maintained partial list risks leaving
production on mixed helper versions.

The deploy command explicitly passes `supabase/functions/deno.json` from the
workflow's `services/` working directory. That import map keeps dependency
resolution stable while Supabase builds each function graph: historical
`https://esm.sh/@supabase/supabase-js@2.49.1` imports are remapped to the npm
package, and runtime dependencies such as `aws4fetch` and `jszip` also resolve
through npm instead of esm.sh. Edge entrypoints should use `Deno.serve(...)`
directly rather than importing `serve` from Deno std. Shared runtime helpers
should prefer local utilities such as `_shared/encoding.ts` for base64/hex
helpers so production deploys do not fail when deno.land or esm.sh returns a
transient 5xx during bundling.

## Required GitHub Secrets

Set these in the repository's GitHub Actions secrets:

- `SUPABASE_ACCESS_TOKEN` — Supabase CLI access token for the deployment actor.
- `SUPABASE_DB_PASSWORD` — database password used by `supabase link` and
  `supabase db push`.

The production Supabase project ref is intentionally stored in the workflow as
`qlarqavoqhkuwzmevrmf`. Project refs are routing identifiers, not credentials;
the deployment authority still comes from `SUPABASE_ACCESS_TOKEN` and
`SUPABASE_DB_PASSWORD`. Post-deploy smoke checks and manual taxonomy imports
resolve the service-role key at runtime through
`supabase projects api-keys --project-ref qlarqavoqhkuwzmevrmf`, then mask it in
GitHub Actions logs.

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

## Manual Taxonomy Import

Use **Actions > Import Community Taxonomy > Run workflow** when the deployed
Community Taxonomy endpoints are healthy and the next bounded GBIF batch should
be imported.

Recommended first production run after a deploy:

- `target`: `birds`
- `limit`: `100`
- `page_count`: `1`
- `dry_run`: `true`
- `retry`: `false`
- `update_checklist`: `true`

If that passes, run the same workflow again with `dry_run = false`. The workflow
uses `SUPABASE_ACCESS_TOKEN` to resolve the project service-role key at runtime
and constructs `https://qlarqavoqhkuwzmevrmf.supabase.co` from the project ref,
so operators do not need to paste service-role credentials locally.

For routine runs after the first clean production import, `dry_run = false` is
acceptable. The workflow uploads a JSON/Markdown summary artifact for every run
and, when `update_checklist = true`, commits
`docs/backend-and-data/07-community-taxonomy-import-checklist.md` after real
imports. Use `page_count = 3...5` only after several successful `page_count = 1`
runs.

## Local Emergency Fallback

Only use the local path when GitHub Actions is unavailable.

```bash
cd /Users/emreerdener/Developer/merian

deno check --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/aws.ts \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/encoding.ts \
  services/supabase/functions/_shared/concurrency.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/update-public-avatar/index.ts \
  services/supabase/functions/auto-purge-nonbio/index.ts \
  services/supabase/functions/delete-scan/index.ts

deno test --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/aws_test.ts \
  services/supabase/functions/_shared/concurrency_test.ts \
  services/supabase/functions/update-public-avatar/avatar_test.ts

make db-push
make functions-deploy
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
- Confirm `community-taxonomy-status` accepts a service-role request with
  `view = coverage` and returns the Birds coverage target quickly.
- Confirm `sync-community-taxonomy-index` accepts a tiny `dry_run = true` Birds
  request without advancing `taxonomy_coverage_targets.next_import_offset`.

---
name: merian-supabase
description: "Apply Merian-specific Supabase workflows and safety rules. Use for diagnosis, review, implementation, testing, or release planning involving services/supabase, Postgres migrations, RLS or database privileges, SECURITY DEFINER routines, Deno Edge Functions, Auth, Storage, Realtime, Supabase Swift clients, backend DTO contracts, or Supabase CI and deployment workflows."
---

# Merian Supabase

Use this overlay with the general `supabase` skill and, for SQL or schema work,
`supabase-postgres-best-practices` when available. Treat checked-in Merian
instructions, scripts, contracts, and exact tool pins as authoritative when
generic guidance differs.

## Start safely

1. Read `AGENTS.md` before proposing or making changes.
2. Inspect `git status` and preserve unrelated or concurrent user changes.
3. Read the relevant section of `services/supabase/README.md`, the affected
   function README, and the linked canonical document under `docs/`.
4. Run `services/supabase/scripts/require_supabase_cli_version.sh` before any
   command that parses Supabase configuration, starts a database, changes a
   database, or deploys a Function. Honor the repository pin; do not replace it
   with the newest available CLI.
5. Classify the target as disposable local, preview/staging, or hosted
   production. Resolve the project reference or database URL source and whether
   each available MCP/CLI path is read-only or mutating. Treat an unknown target
   as hosted and read-only.
6. Verify unstable Supabase behavior against current official documentation,
   but do not replace a reviewed repository contract or pin without changing
   and validating that contract explicitly.

## Keep mutation boundaries explicit

- Do not treat implementation authorization as deployment authorization.
- Never use MCP `execute_sql`, a linked CLI command, or a hosted SQL editor to
  create a repository schema change. Make the change through the checked-in
  migration workflow and prove it on a disposable database.
- Do not edit an applied historical migration. Add a forward repair.
- Do not run production deployment, cleanup, account deletion, migration
  repair, secret rotation, or other hard-to-reverse operations without explicit
  user authorization for the resolved target and operation.
- Prefer read-only inspection and dry-run commands when diagnosing hosted state.
- Never print credentials, database URLs, response bodies that may contain user
  data, raw coordinates, email addresses, names, or variable request IDs.

## Route the task

- **Migration, RLS, grants, triggers, indexes, database functions, or schema
  drift:** Read [migrations-and-database.md](references/migrations-and-database.md)
  completely before acting.
- **Edge Function, Auth, Storage, Realtime, API payload, generated DTO, or
  Supabase Swift boundary:** Read
  [edge-functions-and-clients.md](references/edge-functions-and-clients.md)
  completely before acting.
- **Hosted diagnosis, candidate evidence, rollout, deployment, rollback,
  cleanup, or incident work:** Read
  [release-and-operations.md](references/release-and-operations.md) completely
  before acting.
- Read every applicable reference when a change crosses boundaries. Follow the
  stricter rule when two workflows overlap.

## Verify proportionally

Run the narrowest relevant tests while iterating, then the complete checked-in
gate for the affected surface. Do not substitute a query, local unit test, or
successful migration push for the repository's contract, catalog, or candidate
evidence. Report which checks ran, which could not run, and why.

After changing an API payload, domain layer, operational contract, or release
workflow, audit and update the linked `docs/` files in the same change.

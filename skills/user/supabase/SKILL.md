---
name: supabase
description: "Apply safe, current Supabase workflows across Database, Auth, Edge Functions, Realtime, Storage, Vectors, Cron, Queues, CLI, MCP, and client libraries. Use for schema changes and migrations (imperative or declarative), RLS and database security, sessions, JWTs, cookies, SSR, Deno functions, production diagnosis, deployment planning, or Supabase integrations in Next.js, React, SvelteKit, Astro, Remix, Swift, Python, and other clients."
---

# Supabase

Treat current official documentation, the checked-in project configuration,
and repository-specific instructions as the sources of truth. Supabase products
and CLI behavior change frequently; do not rely on remembered commands or
hard-coded global version thresholds when a project pin or `--help` output is
available.

## Start with the operating context

1. Read the repository's `AGENTS.md` and the nearest project documentation.
2. Inspect `git status` and preserve unrelated or concurrent changes.
3. Classify every target as disposable local, preview/staging, hosted
   production, or unresolved. Treat an unresolved target as hosted production
   and remain read-only.
4. Determine whether database state is managed by declarative schema files or
   imperative migrations before changing SQL.
5. Resolve the project's exact CLI/runtime pins and inspect command help before
   invoking a CLI operation.
6. Separate authorization to implement or test from authorization to deploy or
   mutate a hosted project.

## Keep mutation boundaries explicit

- Do not create a repository schema change by mutating a hosted database with
  MCP `execute_sql`, a linked CLI command, Studio, or a SQL editor.
- Use direct SQL iteration only against an explicitly identified disposable
  local database and only when the repository workflow permits it.
- Keep applied migrations immutable. Create a forward migration or repair.
- Prefer read-only inspection and dry-run modes for hosted diagnosis.
- Do not deploy, repair migration history, rotate secrets, delete data, or run
  another hard-to-reverse operation without explicit authorization for the
  resolved target and exact operation.
- Never print API keys, database URLs, tokens, request bodies, provider response
  bodies, or user data.

## Route the task

- **Schema, migrations, RLS, views, grants, triggers, database functions, or
  Storage policies:** Read
  [database-and-security.md](references/database-and-security.md) completely.
- **Auth, sessions, SSR, Edge Functions, Realtime, Storage clients, or client
  libraries:** Read
  [edge-auth-and-clients.md](references/edge-auth-and-clients.md) completely.
- **CLI, MCP, hosted diagnosis, preview/staging, deployment, rollback, or
  destructive operations:** Read
  [operations-and-tooling.md](references/operations-and-tooling.md) completely.
- **Incorrect or missing skill guidance:** Read
  [skill-feedback.md](references/skill-feedback.md) before drafting feedback.
- Read every applicable reference for a cross-boundary change and follow the
  stricter repository rule when it differs from this general skill.

## Verify the actual boundary

Run focused tests while iterating, then the complete repository gate for the
affected surface. For database work, verify both allowed and denied callers on
a disposable database reconstructed from checked-in state. For client or Edge
changes, exercise authentication, error, retry, and payload boundaries. Report
source, merged, validated, applied, deployed, and released states separately.

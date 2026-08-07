# Operations and Tooling

## Classify tools and targets

Before using a CLI, MCP server, database URL, dashboard, or deployment action,
resolve:

- the project and environment;
- whether the action is read-only, reversible, or destructive;
- whether credentials are user-bound, service-level, or administrative;
- the repository source and candidate revision in scope; and
- the evidence and recovery path required for success.

Treat an unresolved target as hosted production and remain read-only.
Authorization to implement, diagnose, test, or prepare a release is not
authorization to mutate or deploy production.

## Use the CLI deliberately

- Honor the repository's exact CLI pin. If none exists, verify the current
  version against official documentation before relying on a feature.
- Discover commands and flags with `supabase --help` and the relevant nested
  `--help`; do not preserve global minimum-version claims indefinitely.
- Pass local or linked targeting flags explicitly when ambiguity could matter.
  Defaults differ between database commands.
- Treat `db reset --linked`, migration repair, database push, secret updates,
  Function deployment, branch deletion, and project deletion as hosted or
  destructive operations requiring explicit target authorization.
- Never bypass a repository version guard to make a command run.

## Use MCP safely

- Prefer documentation search and bounded read-only inspection first.
- Determine which project an MCP server is scoped to before calling a mutating
  tool. Do not infer the target from a repository name.
- Use `execute_sql` only for an explicitly identified disposable local or
  otherwise expressly authorized target. Do not use it to create a checked-in
  migration by mutating hosted state.
- Do not expose tool results containing credentials, user data, raw logs, or
  unbounded rows.

## Preserve release evidence

- Keep source, merged, migration-replayed, candidate-validated, hosted-applied,
  Function-deployed, and customer-path-verified states distinct.
- Use checked-in CI and release workflows when available. Do not replace their
  ordering, approvals, or audit trail with an interactive partial deployment.
- For schema and runtime changes, preserve expand/migrate/contract
  compatibility across the period when old and new code may coexist.
- After any authorized mutation, verify independent postconditions and report
  the recovery or forward-repair path.

Use current [Supabase local-development guidance](https://supabase.com/docs/guides/local-development/cli-workflows),
[CLI reference](https://supabase.com/docs/reference/cli/introduction), and
[MCP setup guidance](https://supabase.com/docs/guides/getting-started/mcp) for
unstable command and configuration details.

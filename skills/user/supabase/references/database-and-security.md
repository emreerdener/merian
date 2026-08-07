# Database Workflows and Security

## Choose the schema workflow first

Inspect `supabase/config.toml`, repository instructions, and the database
directory before editing SQL.

### Declarative schema projects

Use declarative workflow only when the repository treats `supabase/schemas/` or
non-empty `db.migrations.schema_paths` as its source of truth.

1. Edit the desired schema files rather than Studio, a SQL editor, or the live
   database.
2. Generate a migration with the repository's reviewed `supabase db diff`
   command and explicit local target.
3. Review every generated statement. Schema diffing has known gaps for DML,
   grants, some policies, publications, partitions, and other objects.
4. Replay the full migration history on a disposable database and run database
   security tests.

Read the current [declarative schema guide](https://supabase.com/docs/guides/local-development/declarative-database-schemas)
before relying on diff behavior.

### Imperative migration projects

1. Create a migration with the repository's pinned CLI and
   `supabase migration new <name>` command.
2. Hand-author the forward change in that file. Do not invent timestamps or
   edit an applied migration.
3. Iterate only on an explicitly disposable local database. Never use MCP
   `execute_sql`, linked CLI SQL, Studio, or a hosted editor as the source of a
   version-controlled schema change.
4. Rebuild from the full checked-in history and run catalog, concurrency, and
   denial-path tests before considering the migration ready.

## Enforce exposed-schema security

- Treat Data API exposure, object privileges, and RLS as separate layers. When
  a SQL-created table is unexpectedly inaccessible, inspect the project's
  exposed-schema settings plus schema/table grants before changing policies.
  Never fix reachability with broad grants; enable RLS before granting an API
  role access to a table in an exposed schema.
- Enable RLS on every table in an exposed schema, including `public` by
  default, even when the intended policy is default-deny.
- Grant only the operations required by the reviewed caller. RLS controls rows;
  schema and object privileges still control whether a role can reach a table.
- Scope policies with `TO anon`, `TO authenticated`, or another reviewed role
  instead of calling deprecated `auth.role()` in a predicate. Remember that an
  anonymously signed-in user still uses the `authenticated` PostgreSQL role;
  the row predicate must enforce the real authorization boundary.
- Treat `TO authenticated` as authentication, not authorization. Add ownership,
  membership, tenant, or capability predicates.
- Never authorize with user-editable `user_metadata`. Use server-controlled
  authorization data and account for JWT claim staleness.
- An UPDATE normally needs SELECT privileges and an applicable SELECT policy.
  Test this explicitly rather than interpreting a zero-row update as success.
- For UPDATE policies, `USING` filters old rows and `WITH CHECK` validates new
  rows. PostgreSQL reuses `USING` when `WITH CHECK` is omitted; omission does
  not remove the new-row check. Write both when they express distinct intent or
  when explicitness is valuable, and test cross-owner reassignment.
- Test `anon`, `authenticated`, service, owner, and cross-tenant cases that can
  actually reach the object.

Use the current [Supabase RLS guide](https://supabase.com/docs/guides/database/postgres/row-level-security)
and [PostgreSQL CREATE POLICY semantics](https://www.postgresql.org/docs/current/sql-createpolicy.html)
for details.

## Harden views and privileged routines

- Prefer `security_invoker` views and `SECURITY INVOKER` functions.
- Place a required `SECURITY DEFINER` routine outside exposed schemas, give it
  a fixed safe `search_path`, fully qualify referenced objects, and use a
  reviewed non-login owner where the project supports one.
- Revoke default `EXECUTE` from `PUBLIC` and unapproved API roles, then grant
  only the intended caller.
- Authorize the actual caller inside the routine. Use `auth.uid()` or validated
  claims for user-bound routines; use an explicit service-role, admin, worker,
  capability, or reservation check for service-only routines. Never impose a
  blanket `auth.uid()` requirement on a service worker.
- Do not add `SECURITY DEFINER` merely to silence a permission error.
- Run advisors plus exact catalog tests for ownership, search paths, overloads,
  grants, RLS state, and denial behavior.

## Preserve migration safety

- Keep migration transactions compatible with the repository's execution
  model. Do not add `CONCURRENTLY` inside a transactional migration.
- Keep lock-heavy operations short and bounded. For large constraints, prefer
  supported staged validation such as `NOT VALID` followed by a separately
  reviewed `VALIDATE CONSTRAINT` operation.
- Do not make a normal versioned migration silently idempotent to hide drift.
  A repair that tolerates known prior states must verify the exact existing
  object definition and fail on any unexpected state.
- Treat clean local replay, hosted dry-run, hosted application, and verified
  post-deploy state as distinct evidence.

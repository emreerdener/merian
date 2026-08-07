# Migrations and Database Security

## Establish the source of truth

Read these files before changing database behavior:

- `services/supabase/config.toml`
- the relevant sections of `services/supabase/README.md`
- `docs/backend-and-data/04-database-schema.md`
- `docs/backend-and-data/13-server-credentials-and-database-release-safety.md`
- the nearest analogous migration and its static and pgTAP contracts

Merian currently uses imperative migrations: `[db.migrations]` has
`schema_paths = []`. Treat a future change to that setting as a workflow change
that requires updating this skill and its contract test before schema work
continues.

## Create a forward migration

1. Inspect the latest migration files and `git status`. Do not overwrite or
   absorb an uncommitted migration that belongs to another task.
2. Run `services/supabase/scripts/require_supabase_cli_version.sh`.
3. Create a new file with
   `supabase --workdir services migration new <descriptive_name>`. Do not invent
   a timestamp. If the exact CLI pin is unavailable, stop before creating the
   migration rather than bypassing the guard.
4. Write a forward-only change. Keep applied historical files immutable.
5. Add or update a static migration contract and a catalog/pgTAP test whenever
   behavior, privileges, concurrency, or denial paths change.

Do not iterate by mutating a hosted database. For local experiments, use only a
disposable database that can be rebuilt from the full checked-in history, then
encode the reviewed result in the new migration.

## Preserve the migration execution contract

- Do not add top-level `BEGIN`, `COMMIT`, or `ROLLBACK` to new migrations.
- Do not add `CREATE INDEX CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, or
  concurrent `REINDEX` to checked-in migrations, including dynamic SQL.
- Use session `SET` plus a matching `RESET` for top-level timeout guards; do not
  use `SET LOCAL`.
- Fully qualify catalog calls and verify exact overloads. Do not qualify SQL
  syntax constructs such as `COALESCE` as though they were catalog functions.
- Use the supervised owner-session procedure in the deployment runbook for an
  index that cannot safely be built inside `db push`; verify both
  `pg_index.indisvalid` and `indisready` before retrying the unchanged gated
  migration.

## Enforce exposed-schema security

- Enable effective RLS for every table created in `public`, even when no direct
  client policy is intended.
- Revoke default access and grant only the operations required by the reviewed
  caller. Do not infer safety from an empty REST result.
- Treat `TO authenticated` as authentication only. Add the ownership,
  membership, or capability predicate that supplies authorization.
- For an UPDATE policy, reason about old-row visibility in `USING` and new-row
  admissibility in `WITH CHECK`. Write both explicitly when reviewing Merian
  policy intent. Do not claim that omitting `WITH CHECK` removes the new-row
  check: PostgreSQL reuses `USING` when no separate expression is supplied.
- Test policies under the actual `anon`, `authenticated`, and `service_role`
  roles, including denial and cross-owner cases.

## Harden privileged routines

Prefer `SECURITY INVOKER`. When `SECURITY DEFINER` is required:

1. Use the migration-owned exact-signature allowlist.
2. Use the reviewed owner, `SET search_path = ''`, and fully qualified objects,
   types, and operators.
3. Revoke execution from `PUBLIC` and every API role, then grant only the
   reviewed caller.
4. Authorize that caller inside the routine. Use caller-bound
   `auth.uid()`/`auth.jwt()` or `internal.require_admin(...)` for authenticated
   routines, and `internal.require_service_role()` for service-only routines.
   Never impose a blanket `auth.uid()` rule on a service-only worker.
5. Run the static migration tests, complete catalog tests, and privileged
   routine audit. Do not weaken a failing audit to make a grant pass.

## Verify

From the repository root, run the applicable sequence:

```bash
make validate-supabase-migrations
make test-supabase-privileged-routines
bash services/supabase/scripts/test_database_catalogs.sh
```

Use `supabase --workdir services db push --linked --dry-run` only when the user
has authorized hosted preflight for the resolved project. Confirm that only the
reviewed migrations appear. A merged file, a clean dry run, and an applied
production migration are three distinct states; report them separately.

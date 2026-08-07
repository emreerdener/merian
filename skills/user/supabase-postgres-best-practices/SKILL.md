---
name: supabase-postgres-best-practices
description: "Apply Supabase-maintained PostgreSQL guidance before writing or changing database objects: tables, columns, types, schemas, migrations, declarative schema files, constraints, RLS policies and tests, grants, indexes, triggers, functions, queues, cron jobs, pgvector search, restores, imports, and SQL queries. Also use when diagnosing slow queries, high CPU, timeouts, connection exhaustion, locks, bloat, unsafe privileges, or cross-user and cross-tenant visibility in Supabase or PostgreSQL."
---

# Supabase Postgres Best Practices

Use the smallest relevant reference set below. Read repository-specific database
instructions first and follow their migration, release, and verification
contracts when they are stricter than these general rules.

## Establish evidence before changing SQL

1. Identify the PostgreSQL version, extensions, schema workflow, caller roles,
   data scale, and target environment.
2. Inspect existing indexes, constraints, grants, policies, query plans, and
   analogous migrations before proposing a change.
3. Keep experiments on disposable local databases unless the user explicitly
   authorizes the resolved hosted target and operation.
4. Measure representative behavior before and after performance work. Do not
   infer improvement from a plausible-looking index or rewritten query.
5. Avoid `EXPLAIN ANALYZE` for mutating statements or expensive production
   queries without explicit authorization and bounded impact.
6. Verify allow and deny paths under the actual roles that reach the object.

## Load references by task

### Query performance — critical

- [Missing indexes](references/query-missing-indexes.md)
- [Composite indexes](references/query-composite-indexes.md)
- [Covering indexes](references/query-covering-indexes.md)
- [Partial indexes](references/query-partial-indexes.md)
- [Index types](references/query-index-types.md)

### Connection management — critical

- [Connection pooling](references/conn-pooling.md)
- [Connection limits](references/conn-limits.md)
- [Idle timeouts](references/conn-idle-timeout.md)
- [Prepared statements and poolers](references/conn-prepared-statements.md)

### Security and RLS — critical

- [RLS foundations](references/security-rls-basics.md)
- [RLS performance](references/security-rls-performance.md)
- [Least-privilege grants](references/security-privileges.md)

Read all three for an authorization or exposed-schema change.

### Schema design — high

- [Data types](references/schema-data-types.md)
- [Primary keys](references/schema-primary-keys.md)
- [Foreign-key indexes](references/schema-foreign-key-indexes.md)
- [Safe constraints](references/schema-constraints.md)
- [Lowercase identifiers](references/schema-lowercase-identifiers.md)
- [Partitioning](references/schema-partitioning.md)

### Concurrency and locking — medium-high

- [Short transactions](references/lock-short-transactions.md)
- [Deadlock prevention](references/lock-deadlock-prevention.md)
- [Skip locked](references/lock-skip-locked.md)
- [Advisory locks](references/lock-advisory.md)

Read the relevant lock guidance for any migration or worker that may touch many
rows or coordinate concurrent callers.

### Data access patterns — medium

- [Batch inserts](references/data-batch-inserts.md)
- [N+1 queries](references/data-n-plus-one.md)
- [Pagination](references/data-pagination.md)
- [Upserts](references/data-upsert.md)

### Monitoring and diagnostics — low-medium

- [EXPLAIN and EXPLAIN ANALYZE](references/monitor-explain-analyze.md)
- [pg_stat_statements](references/monitor-pg-stat-statements.md)
- [Vacuum and analyze](references/monitor-vacuum-analyze.md)

### Advanced features — incremental

- [Full-text search](references/advanced-full-text-search.md)
- [JSONB indexing](references/advanced-jsonb-indexing.md)

## Verify the result

Run the repository's migration replay, static SQL checks, catalog assertions,
concurrency tests, and query benchmarks as applicable. Report assumptions,
dataset scale, plan changes, lock implications, denied callers, and every gate
that could not run.

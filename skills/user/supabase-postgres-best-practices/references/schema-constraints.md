---
title: Add Constraints Safely in Migrations
impact: HIGH
impactDescription: Prevent migration drift and reduce validation locks
tags: constraints, migrations, schema, alter-table
---

## Add Constraints Safely in Migrations

PostgreSQL does not support `ADD CONSTRAINT IF NOT EXISTS`. Do not replace it
with a name-only `DO` block that silently accepts an unexpected existing
constraint. Normal versioned migrations should fail when the catalog differs
from the reviewed starting state.

**Incorrect:**

```sql
alter table public.profiles
add constraint if not exists profiles_birthchart_id_unique unique (birthchart_id);
```

**Correct for a deterministic versioned migration:**

```sql
alter table public.profiles
add constraint profiles_birthchart_id_unique unique (birthchart_id);
```

If a forward repair must tolerate one known prior state, inspect the exact
table, constraint type, columns, referenced relation, validation state, and
definition. Raise an exception for any other state instead of treating a
matching name as success. Repairs must fail on any unexpected state.

For a large CHECK or foreign-key constraint, reduce the initial table scan and
lock window with staged validation when the repository deployment contract
supports it:

```sql
alter table public.orders
add constraint orders_total_nonnegative
check (total_cents >= 0) not valid;

alter table public.orders
validate constraint orders_total_nonnegative;
```

Keep validation as a separately reviewed step when its scan may exceed the
normal migration window. `NOT VALID` is not available for every constraint
type, including UNIQUE and PRIMARY KEY constraints.

Inspect exact catalog state with schema-qualified relations:

```sql
select
  c.conname,
  c.contype,
  c.convalidated,
  pg_catalog.pg_get_constraintdef(c.oid, true) as definition
from pg_catalog.pg_constraint as c
where c.conrelid = 'public.profiles'::pg_catalog.regclass;
```

Reference: [PostgreSQL ALTER TABLE](https://www.postgresql.org/docs/current/sql-altertable.html)

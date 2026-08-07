---
title: Enable Row Level Security for Exposed Data
impact: CRITICAL
impactDescription: Database-enforced tenant isolation and default-deny access
tags: rls, row-level-security, multi-tenant, security
---

## Enable Row Level Security for Exposed Data

Enable RLS on every table in an exposed schema and grant only the operations
required by each API role. Application filtering does not replace database
authorization.

**Incorrect:**

```sql
-- A missing application predicate exposes every row.
select * from public.orders;
```

**Correct for a user-owned table:**

```sql
alter table public.orders enable row level security;

create policy orders_select_own
on public.orders
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy orders_insert_own
on public.orders
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy orders_update_own
on public.orders
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
```

`TO authenticated` supplies authentication only; the predicate supplies
authorization. An UPDATE usually also needs SELECT privilege and an applicable
SELECT policy.

For UPDATE and ALL policies, PostgreSQL reuses `USING` as `WITH CHECK` when no
separate check expression is supplied. Omission therefore does not eliminate
the new-row check, but explicit clauses make distinct old-row and new-row intent
reviewable.

Do not mechanically use `auth.uid()` for service-only workers. Authorize the
actual caller with a reviewed role, capability, claim, or reservation boundary.
Test allowed, denied, anonymous, cross-owner, and service cases under their real
PostgreSQL roles.

Reference: [PostgreSQL CREATE POLICY](https://www.postgresql.org/docs/current/sql-createpolicy.html)

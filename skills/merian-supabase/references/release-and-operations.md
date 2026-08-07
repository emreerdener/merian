# Release and Operations

## Classify the operation

Before using MCP, a database URL, a linked CLI command, GitHub Actions, or a
Supabase deployment command, record:

- the resolved project and environment;
- whether the action is read-only, reversible, or destructive;
- the credentials and authorization boundary it would use;
- the exact candidate SHA and source changes in scope; and
- the evidence, rollback, or forward-repair path required for success.

Treat unresolved target information as hosted production and remain read-only.
An instruction to implement, test, or prepare a release does not authorize a
production mutation.

## Keep evidence states distinct

- A source migration can exist without being merged.
- A merged migration can remain unapplied on a hosted database.
- Candidate Validation proves an exact source SHA against a disposable catalog;
  it does not prove that production changed.
- A successful `db push` does not prove Function deployment, schema-cache
  readiness, post-deploy grants, or customer-path health.
- A Function deployment does not prove an iOS build or release.

State each boundary explicitly in status and handoff messages.

## Use the checked-in release path

Read `docs/backend-and-data/06-supabase-deployment-runbook.md` completely before
release, rollback, cleanup, or incident work. Prefer the reusable **Supabase
Candidate Validation / Candidate readiness** workflow for exact-SHA evidence
without production access. Do not dispatch `.github/workflows/deploy.yml` merely
to obtain validation evidence.

Production deployment belongs to the GitHub `Production` job after candidate
validation. Do not replace it with an interactive developer login or a partial
manual fleet deployment. Emergency/manual commands remain exceptional and need
explicit authorization plus the runbook's preflight, audit, ordering, and smoke
checks.

For schema and Function changes in one release, preserve expand/migrate/contract
compatibility. Keep migrations safe for the currently live Function version,
deploy compatible readers and writers, prove them live, and ship destructive
cleanup only in a later reviewed change.

## Guard destructive operations

Before cleanup, deletion, migration repair, privilege repair, secret rotation,
or another hard-to-reverse operation:

1. Resolve exact targets with read-only queries.
2. Confirm backup/PITR or a tested forward-repair path where applicable.
3. Run the checked-in dry-run or audit mode and review bounded output.
4. Require explicit user authorization for the target, operation, and batch.
5. Start with the smallest supported batch and retain idempotency or reservation
   fences.
6. Verify postconditions independently without printing sensitive data.

Do not infer that a cleanup candidate remains safe between audit and execution;
use the operation's live reservation or revalidation boundary.

## Diagnose without widening access

Prefer bounded read-only catalog checks, aggregate health reports, and
caller-safe logs. Do not weaken RLS, grants, auth checks, timeouts, payload
ceilings, or smoke assertions to make a diagnosis pass. Treat the first concrete
PostgreSQL, Deno, or workflow error as the cause and later aggregate failures as
consequences until evidence shows otherwise.

Report the exact evidence obtained, any mutation performed, recovery options,
and every required gate that remains pending.

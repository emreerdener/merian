# Incident: Beta reconciliation and system analytics log errors

- **Date detected:** 2026-09-21
- **Status:** Mitigated in source; local validation passed; production checks
  pending
- **Affected versions/environments:** Production beta logs after deployment of
  `0932b5590d09e166fb80b843da7ebdbbdb73ae27`
- **Affected surfaces:** Supabase RevenueCat reconciliation and species-refresh
  telemetry
- **Current contracts:**
  [Database state](../backend-and-data/04-database-schema.md) and
  [telemetry boundary](../backend-and-data/05-api-contracts.md)

## Summary, impact, and detection

A user-supplied PostgreSQL log export contained 122 error entries on September
21. Of these, 31 validation rejections and 78 permission denials matched the
production deployment's intentional no-write and public-credential denial
checks. They do not indicate broken application permissions.

The remaining entries were one RevenueCat `23502` null-event constraint failure
and 12 `22P02` UUID parsing failures from the species worker's system label. The
owner confirmed that plans have not launched, users are beta users, and no one
has subscribed. The repair therefore needs no paid-customer conversion or
legacy-payment recovery. The export does not establish the affected account,
backlog size, or whether a later retry recovered.

## Timeline

| Time (UTC)       | Event                                                     | Evidence status                                        |
| ---------------- | --------------------------------------------------------- | ------------------------------------------------------ |
| 2026-09-21 15:09 | 109 expected deployment-probe errors                      | Export and successful workflow checks                  |
| 2026-09-21 15:45 | Null RevenueCat event ID rejected                         | One exported database error                            |
| 2026-09-21 15:47 | System identity queried as a user UUID                    | Twelve exported database errors; source path confirmed |
| 2026-09-21       | Both failures reproduced locally and source repairs added | Synthetic regression fixtures; production unchanged    |

## Root causes and reproduction

`apply_revenuecat_reconciliation` creates nullable input state on the first
provider snapshot even without a webhook. It also creates an ignored synthetic
event for the non-null customer-watermark foreign key. On a second, newer
snapshot, its old seed guard checked for a missing state row rather than a
missing event ID. The existing input row still had no webhook event ID, leaving
the insert value null. PostgreSQL checks that constraint before the upsert's
conflict update can proceed. Two successive free snapshots reproduce the exact
constraint error on a freshly replayed local catalog.

The scheduled species worker passes a system label into shared biology helpers.
Those helpers call optional PostHog capture, whose consent lookup previously
queried the UUID user column with that label. The error skips telemetry; it does
not by itself prove species enrichment failed. An injected-fetch test reproduces
the unwanted consent/capture calls without providers or production access.

## Repository mitigation and regression coverage

- Forward migration
  `20260921160147_fix_revenuecat_reconciliation_without_webhook_event.sql`
  creates or reuses the existing ignored seed whenever the input event ID is
  null. It performs no backfill and retains leases, ordering, access controls,
  entitlement recomputation, and normal retry scheduling.
- `tests/revenuecat_webhook_security.sql` covers two free reconciliations with
  no webhook or subscription, one unchanged ignored seed, no purchase subjects,
  advanced snapshot state, cleared failure/lease state, and the 24-hour
  schedule. Its existing cases retain stale-snapshot and claim-loss coverage.
- `revenueCatReconciliationSeedMigrationContract.test.ts` confines the routine
  change to seed admission and verifies service-only grants and bounded locks.
- `_shared/posthog.ts` rejects non-UUID identities before database lookup and
  before the injected consent checker or capture. `posthog_test.ts` covers
  system/empty/malformed identities and valid UUID permission denial/grant.

## Candidate validation

The new PostHog regression failed before the change and all five PostHog tests
passed afterward. The RevenueCat regression reproduced `23502` before applying
the repair on a separate disposable local database, then passed after the
forward migration. The disposable catalog replayed history through this repair;
the existing development database was not migrated or reset.

Local verification passed:

- All 52 pgTAP catalog files, 383 assertions, plus the enforced
  privileged-routine ACL audit and database lint.
- All 2,033 Edge Function tests, including the database concurrency tests with
  the disposable database explicitly configured.
- All 345 migration-contract tests across 59 discovered files.
- Complete Supabase tooling, including generated DTO checks and regenerated,
  diff-reviewed Field Chat deployment fingerprints for the shared-helper change.
- All 101 isolated function dependency graphs and entrypoint type checks,
  whole-tree Deno formatting/lint, changed Markdown formatting, and diff checks.

Security and performance advisor gates completed without errors. They reported
105 security warnings and 80 performance warnings on other existing catalog
objects; none concern the changed routine. These unrelated warnings were not
remediated by this incident. These are working-tree checks, not immutable
candidate or production deployment evidence.

Concurrent media-staging changes appeared during final verification. The final
whole-tree formatting recheck reported unformatted edits in
`functions/generate-upload-urls/storage_test.ts`, outside this repair. Those
edits were preserved. The passing suite counts above describe the tested repair
snapshot and do not certify the later combined worktree; rerun the complete gate
on the assembled release candidate.

## Production deployment and runtime verification

**Not performed.** After an authorized deployment, verify a successful repeated
free-account reconciliation, healthy aggregate queue state, and absence of the
system-label UUID errors during a scheduled species refresh. The intentional
deployment denial/validation probes remain enabled.

## Data recovery and closure

**Not performed.** Normal claim-fenced retries can recover after the migration;
no manual payment conversion, account reset, queue replay, or data deletion is
part of this repair. Closure requires production deployment, runtime checks, and
confirmation that affected reconciliation work has recovered.

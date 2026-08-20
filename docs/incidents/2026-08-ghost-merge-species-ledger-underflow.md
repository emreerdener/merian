# August 2026 Ghost-Merge Species-Ledger Underflow

**Date:** 2026-08-01\
**Severity:** Release-blocking account-upgrade reliability\
**Affected flow:** Anonymous Ghost session → existing Apple/Google account
conflict → `/merge-ghost-profile` completion\
**Repository status:** Core schema-aware remediation and all four hardening
requirements are implemented; release-proof gates remain open

**Production status:** Deployment status is unverified from this environment;
the incident remains open until the closure gates below pass

## Summary

The supplied Supabase exports contain ten distinct failed Ghost-profile merge
executions with the database diagnostic `user_species_scan_count_underflow`
between 06:14 and 20:22 UTC on 2026-08-01. All ten carry the same anonymized
subject, so this count does not establish ten affected users.

The merge ran inside one database transaction and failed while scan ownership
triggers were maintaining the private per-user/per-species ledger. PostgreSQL
rolled the transaction back, so the failure is fail-safe for ownership data, but
the user could not complete the existing-account upgrade. The incident-baseline
Edge mapper exposed this exact invariant failure as an unexpected HTTP 500
instead of the intended retryable 503 signed-out-profile-data-unchanged
response. The expanded mapper fixes that behavior in the repository; its
production status is not verified here.

Normal provider linking is unaffected. When Apple or Google can attach to the
anonymous Auth user, `linkIdentityWithIdToken` preserves the Ghost UUID and no
data merge occurs. This incident concerns only the exact
`identity_already_exists` fallback.

## Sanitized evidence

- Ten `user_species_scan_count_underflow` failures with ten distinct Edge
  execution identifiers appear in the runtime export reviewed on 2026-08-01.
  They span 06:14–20:22 UTC and carry one anonymized subject, proving repeated
  executions but not the client-side mechanism that initiated them.
- The unified request export contains the final four corresponding HTTP 500
  responses. Each is followed by an HTTP 200 merge POST 695–1,438 milliseconds
  later, but the rows have neither an authenticated user nor an Edge execution
  identifier. That temporal adjacency does not prove a same-client retry, a
  matching handoff receipt, or a successful prepared-to-merged transition.
- The failures occur in the Ghost merge database transaction, not in a provider
  API, direct-link request, or Auth cleanup worker.
- The error is emitted when a negative scan delta exceeds a still-live owner's
  ledger count. The trigger aborts instead of hiding ledger corruption.
- The export alone does not prove user count, species count, successful retry,
  or data loss. Those questions require receipt/ownership review through a
  private operational connection.

This incident record excludes user IDs, handoff IDs/secrets, provider subjects,
species IDs, scan IDs, coordinates, request bodies, and raw log payloads.

## Root cause

The original merge treated runtime discovery of a single-column foreign key as
sufficient evidence that the relationship represented transferable ownership. It
then processed relationships in catalog-dependent order.

`internal.user_species_scan_counts` is not independent ownership. It is derived
from `public.scans.user_id`, and the scan statement trigger is the sole
authority for source decrements, destination increments, and distinct-species
totals. If the derived ledger is moved or coalesced as an ordinary foreign-key
relation before all source scans move, a later scan decrement can exceed the
source ledger state and raise `user_species_scan_count_underflow`. Overlapping
species between source and destination also require additive scan counts but
only one distinct-species boundary.

The architectural defect was therefore semantic, not a missing cascade: catalog
discovery can verify coverage, but it cannot decide whether a relation is
ownership, derived state, immutable attribution, source-profile deletion, or a
conflict-prone projection.

## Core repository remediation

Schema-aware migration
[`20260801210102_make_ghost_merge_schema_aware.sql`](../../services/supabase/migrations/20260801210102_make_ghost_merge_schema_aware.sql)
establishes the core long-term correction:

1. A private, source-controlled
   `internal.ghost_profile_merge_reference_policies` manifest assigns reviewed
   semantics to every eligible user foreign key.
2. A complete topology assertion runs before the first mutating merge helper and
   rejects missing, stale, blocked, or unsupported composite policy.
3. Scans move first. Their statement trigger updates the derived species ledger;
   the merge never reparents that ledger directly.
4. Exact scan aggregates are compared with ledger rows for both users before
   source-profile deletion.
5. Immutable administrator, audit, session, and moderator attribution is
   preserved and causes a fail-closed result if the source still owns such a
   reference.
6. Reviewed handlers run before generic ownership moves for conflict-prone
   Community and RevenueCat state.

This is the correct semantic boundary and addresses the logged underflow cause.
It is not yet sufficient for production deployment.

## Double-check findings and release hold

The 2026-08-01 review found four additional requirements. They are implemented
in the forward hardening migration and Edge mapper, but remain release-blocking
until the disposable-CI database and release proof gates pass:

1. **Destination RevenueCat repair must be unconditional.** Anonymous sources
   may legitimately have no reconciliation row. Completion must upsert an
   immediately due, claim-free destination row even when the source row is
   absent, or a completely missed webhook can remain unrepaired until a later
   scheduled sweep.
2. **RevenueCat must use one lock order.** Merge holds `public.users` before the
   reconciliation queue, while the incident-baseline apply callback locked queue
   before user. The callback must lock user first, then lock and revalidate its
   claim, so concurrent completion cannot deadlock or apply a displaced provider
   snapshot.
3. **Community actor handling must not invert writer locks.** Normal activity
   append locks the activity group before its actor. The merge handler must
   coalesce only existing source/target collisions with update/delete and leave
   non-colliding rows for policy reparenting; it must not insert/upsert a target
   actor after actor locks.
4. **Ledger underflow needs the guarded public response.** Both
   `ghost_merge_species_ledger_mismatch` and `user_species_scan_count_underflow`
   must map through the real Edge mapper to HTTP 503
   `merge_temporarily_unavailable` with the exact statement that guest data is
   unchanged.

The authoritative implementation and automated release evidence is the
[Ghost Account Merge Security Rollout](../backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).

## Verification status

Evidence completed on the reviewed working tree:

- `make validate-supabase-migrations`: 211 passed;
- `make test-supabase-tooling`: 121 standard tests plus isolated suites passed;
- the complete Edge suite: 1,468 passed with zero failures;
- the documentation contract: 14 passed with zero failures;
- the iOS proof-capable client completed `build-for-testing`; and
- Deno type checks, formatting across 700 files, lint across 542 files, and
  `git diff --check` passed.

The production workflow now keeps its disposable database alive for strict
`public`/`internal` lint plus security and performance advisors. Each command
fails on warnings and must finish before deployment planning or any production
mutation. This is a fail-closed release gate, not evidence that the live
database checks have already passed for this SHA.

The repository also contains a privacy-safe scheduled and post-deploy Ghost
merge monitor. It reports aggregate recent receipt counts, overdue Auth cleanup,
and missing, misdirected, or unrefreshed destination RevenueCat queues. Its
focused unit tests pass, and
`20260802025258_index_ghost_merge_health_audits.sql` adds indexes matched to its
rolling predicates. It has not run against production in this sandbox; that
audit remains a post-deploy closure check, not a staging-project prerequisite.

Forward migration
`20260801220318_harden_ghost_merge_concurrency_and_provider_repair.sql` and the
expanded Edge mapper implement all four code corrections. The repository also
contains deterministic RevenueCat and Community schedules in
`ghostProfileMergeConcurrencyDb.test.ts`. The production workflow runs their
live bodies against its disposable Postgres instance and treats a connection
skip as failed release evidence.

The repository exact-pins Supabase CLI `2.109.1`, and the production workflow
installs that pin before starting a fresh database, running every checked-in
catalog test, and executing the two-session RevenueCat and Community probes. A
passing exact-SHA workflow run is the release-equivalent database evidence; a
developer's older local CLI does not block deployment.

## Safety, rollout, and recovery

- Keep the existing-account conflict fallback gated while this incident is open.
  Direct provider linking can remain enabled.
- Deploy the backwards-compatible expanded Edge error mapper before the pending
  database revisions, then apply the schema-aware and corrective forward
  migrations immediately in the same window. The secure baseline can already
  emit the ledger-underflow diagnostic recorded here. The production workflow
  detects Ghost migration/Function deltas, manual dispatch, and an unsafe
  baseline and predeploys both Ghost Functions before `db push`.
- Require the exact-SHA production workflow to pass its fresh disposable
  database replay, complete catalog and Edge suites, two-session concurrency
  probes, strict lint, and advisors before mutation. No hosted staging project
  or manual SHA attestation is required.
- Never restore the arbitrary source-UUID payload or client execution of legacy
  reparent helpers.
- Do not roll back an applied migration or manually reparent scans/ledger rows.
  Correct database behavior with a reviewed forward migration.
- Do not delete or edit handoff receipts/secrets to recover an attempt. Preserve
  queued proofs and let the idempotent completion and Auth cleanup worker retry.
- The iOS client retains HTTP 503 `merge_temporarily_unavailable` proofs in its
  device-only Keychain queue and retries them after permanent-session
  restoration. Only `handoff_expired` and `handoff_invalid` discard a proof.

## Closure criteria

Close this incident only when one exact SHA proves all of the following:

1. all four release-hold requirements have implementation and automated test
   evidence;
2. a clean migration replay and every pgTAP catalog file pass under Supabase CLI
   `2.109.1`;
3. duplicate and overlapping source/destination species produce exact ledger
   counts and the correct destination distinct-species total;
4. controlled ledger drift returns the guarded 503 and leaves both profiles and
   ownership unchanged;
5. a merge with no source RevenueCat queue leaves one immediately due,
   claim-free destination row that the normal reconciler can finish;
6. concurrent merge/reconciliation and merge/Community append probes complete
   without deadlock, stale claim application, duplicate actors, or lost counts;
7. completion replay is idempotent and the obsolete anonymous Auth shell is
   deleted only after data commit; and
8. production monitoring shows no repeated ledger underflow; missing,
   misdirected, or unrefreshed destination queue audit row; or cleanup receipt
   beyond its alert window.

# Species Preferences Data

`Core/Data/SpeciesPreferences` owns the durable preferred-common-name boundary
shared by Insights and Explore. A local preference is keyed by account plus
normalized scientific name, stored in SwiftData, and reconciled with the
`user_species_preferences` PostgREST table.

## Owners

- `SpeciesPreferredNameRepository.swift` owns account-scoped SwiftData reads,
  writes, clears, display-map hydration, the 1,000-row local bound, and
  fail-closed removal of device-global legacy values.
- `SpeciesPreferredNamePolicy.swift` owns normalization, the server-aligned
  200-character name limit, timestamps, and active-value/tombstone conflict
  decisions.
- `Models/SpeciesNameMigrationResult.swift` describes legacy cleanup, while
  `Models/SpeciesPreferenceCloudModels.swift` owns exact decoded-row, encoded
  upsert, page-request, and sync-error values. Explicit JSON nulls remain
  significant for tombstones.
- `Services/SpeciesPreferredNameCloudClient.swift` is the only direct Supabase
  owner in this package. It performs account-bound, scientific-name keyset pages
  and composite-key upserts.
- `Services/SpeciesPreferredNameCloudSyncCoordinator.swift` owns main-actor
  single-flight reconciliation, trailing-request coalescing, account-specific
  freshness and diagnostics, lease checks around every suspension, bounded
  remote accumulation, conflict application, and tombstone convergence.
- `Services/SpeciesPreferenceLocalRecovery.swift` owns repair of the non-atomic
  SwiftData/UserDefaults mutation boundary plus normalized union-bound
  validation before planning and after a network suspension.

The active `UserSpeciesPreference` model remains in `Models/ActiveSchema`. V51
adds its account-qualified stable identifier and `ownerUserId`; the V50→V51
migration deletes unowned rows while the frozen source schema is active, before
the new unique identifier is materialized, because no trustworthy account can be
inferred. The startup cleanup applies the same fail-closed rule to legacy
`speciesPreferredName_*` defaults. It never assigns device-global data to the
next account that signs in.

`Core/Preferences/Stores/SpeciesPreferredNameStore.swift` owns legacy cleanup
and the account-partitioned pending-delete and support-diagnostic keys.
`Core/Utilities/UserDefaultsKeys.swift` remains the exact key registry.

## Invariants

- Every repository operation requires an account UUID. Two accounts can store
  different preferred names for the same scientific name without sharing a
  SwiftData identity or defaults partition.
- Local mutations save before convergence markers change. A failed fetch, remote
  page, upsert, or remote-application save records failure for the leased
  account rather than a clean success.
- Because SwiftData and UserDefaults cannot commit atomically, reconciliation
  repairs an interrupted local update before planning remote writes. A
  newer-or-equal valid active row removes its stale delete marker; a newer
  tombstone removes its stale local row. One upsert batch therefore never
  contains both states for the same account/species key. An in-flight upsert
  clears only the captured tombstone timestamp, retaining any newer delete for
  the trailing reconciliation. After that suspension, the coordinator refetches
  local rows and tombstones before applying the earlier remote response, so the
  response cannot overwrite an edit made while the request was in flight.
- A clear remains queued until its tombstone upsert succeeds under the same
  current account-work lease.
- The coordinator acquires the account lease before consulting freshness, so one
  account's recent success cannot suppress another account's first pull.
- Lifecycle and Auth triggers share one active sync. A trigger received during
  that sync replaces the pending context and causes one trailing reconciliation.
  Force intent accumulates across the queued requests, so a later clean
  lifecycle trigger cannot suppress reconciliation requested by an edit.
- Remote pages order by immutable `scientific_name` and continue with a strict
  greater-than cursor. Inserts before an active cursor are deferred to the next
  sync instead of shifting offsets or duplicating rows. More than 1,000 unioned
  local, remote, or pending-delete species fails before upsert or local
  mutation.
- Freshness requires the most recent recorded outcome to be successful; an
  earlier recent success never masks a later failure or interrupted attempt.
- Matching normalized active values and existing tombstones are already
  converged. Genuine conflicts are timestamp-based, with local winning an
  equal-timestamp active/tombstone conflict.
- Preferred names longer than the server's 200-character constraint are rejected
  before SwiftData or network mutation. The client counts Unicode scalars rather
  than extended grapheme clusters so combining sequences cannot pass locally and
  then fail PostgreSQL `char_length`.
- Accepted account deletion removes the SwiftData rows and all legacy,
  per-account tombstone, and diagnostic keys before local cleanup is
  acknowledged.
- Views, feature models, the repository, and the coordinator issue no PostgREST
  requests. Feature composition supplies the current account ID; only the narrow
  cloud client resolves live Supabase transport.

The canonical server contract is documented in
[`docs/backend-and-data/02-supabase-edge-and-database.md`](../../../../../../docs/backend-and-data/02-supabase-edge-and-database.md#species-preferred-name-sync).
Consumer behavior is documented in
[`docs/features-and-hardware/05-insight-sheet.md`](../../../../../../docs/features-and-hardware/05-insight-sheet.md).

## Verification

Mirrored tests live in `MerianTests/Core/Data/SpeciesPreferences/` and cover
account isolation, legacy discard, the 200-character boundary, deterministic
keyset paging under remote mutation, per-account freshness and diagnostics,
local/remote bounds, interrupted-mutation recovery, lease fencing, convergence,
canonicalization, and trailing requests. `MigrationPlanTests` owns disk-backed
multi-row V49/V50→V51 coverage; `speciesPreferenceRLSMigrationContract.test.ts`
locks the forward SQL source, while
`services/supabase/tests/species_preference_rls_security.sql` verifies table
privileges, authenticated owner allow/deny paths, anonymous denial, and the
server length constraint against a migrated catalog.

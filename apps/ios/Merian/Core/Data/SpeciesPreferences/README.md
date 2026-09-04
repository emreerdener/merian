# Species Preferences Data

`Core/Data/SpeciesPreferences` owns the durable preferred-common-name boundary
shared by Insights and Explore. A preference is keyed by normalized scientific
name, stored locally in SwiftData, and reconciled with the existing
`user_species_preferences` PostgREST table.

## Owners

- `SpeciesPreferredNameRepository.swift` owns SwiftData reads, writes, clears,
  display-map hydration, and promotion of legacy values. Its existing static
  call surface remains stable for current consumers.
- `SpeciesPreferredNamePolicy.swift` owns normalization, timestamps, resource
  limits, and active-value/tombstone conflict decisions.
- `Models/SpeciesNameMigrationResult.swift` owns the local legacy-migration
  result, while `Models/SpeciesPreferenceCloudModels.swift` owns the exact
  decoded row and encoded upsert shapes. Explicit JSON nulls remain significant
  for active values and tombstones.
- `Services/SpeciesPreferredNameCloudClient.swift` is the only direct Supabase
  owner. Its live value resolves the current account-work lease and performs the
  paginated select and composite-key upsert. Pages use
  `(updated_at,
  scientific_name)` ordering so equal-timestamp rows cannot move
  across an offset boundary nondeterministically.
- `Services/SpeciesPreferredNameCloudSyncCoordinator.swift` owns the main-actor,
  single-flight reconciliation task, trailing-request coalescing, freshness
  gate, account-lease checks, conflict application, and diagnostic updates.
  Tests inject the narrow client and clock rather than replacing a global
  network object.

The active `UserSpeciesPreference` model remains in `Models/ActiveSchema`; this
move does not change the SwiftData schema. `Core/Preferences/Stores` retains the
legacy `UserDefaults` bridge, pending-delete timestamps, and support
diagnostics. `Core/Utilities/UserDefaultsKeys.swift` remains the exact key
registry.

## Invariants

- Local mutations save before their legacy or convergence markers are cleared; a
  failed SwiftData fetch or remote-application save records a failed sync rather
  than a clean success.
- A clear remains queued until its remote tombstone upsert succeeds under the
  same current account-work lease.
- Lifecycle and Auth triggers share one active sync. A trigger received during
  that sync records the latest context and runs one trailing reconciliation,
  preventing an edit made after the first local fetch from being stranded.
- Clean lifecycle/Auth syncs may use the existing 60-second freshness window;
  edit-triggered syncs force reconciliation. A future persisted success time is
  treated as clock skew and forces work instead of suppressing sync until the
  wall clock catches up.
- Matching normalized active values and existing tombstones are converged
  without timestamp-only rewrites. Genuine conflicts remain timestamp-based.
- Historical local or remote rows that differ only by surrounding whitespace are
  collapsed by normalized scientific name before conflict planning; the newest
  valid timestamp wins instead of allowing duplicate dictionary keys to
  terminate synchronization.
- Repository fetch failures never consume legacy data or create replacement
  rows. Clearing a valid name records and schedules a tombstone even when no
  local SwiftData row exists, and equal-timestamp local values win over remote
  tombstones consistently in both push planning and remote application.
- Accepted account deletion removes the SwiftData rows plus all preferred-name
  legacy keys, pending tombstones, and diagnostics before local cleanup is
  acknowledged.
- Views, feature view models, the local repository, and the sync coordinator do
  not issue PostgREST requests or resolve `SupabaseManager.shared`.
- The exact table, selected columns, page size, composite conflict key, JSON
  names, and null semantics are unchanged; the select now adds a deterministic
  scientific-name tie-breaker to its existing timestamp order.

The canonical server contract is documented in
[`docs/backend-and-data/02-supabase-edge-and-database.md`](../../../../../../docs/backend-and-data/02-supabase-edge-and-database.md#species-preferred-name-sync).
Consumer behavior is documented in
[`docs/features-and-hardware/05-insight-sheet.md`](../../../../../../docs/features-and-hardware/05-insight-sheet.md).

## Verification

Mirrored tests live in `MerianTests/Core/Data/SpeciesPreferences/`:

- repository tests retain the prior SwiftData CRUD, migration, display-map, and
  conflict-policy coverage;
- cloud-model tests lock decoding and explicit-null encoding;
- coordinator tests cover injected pushes, pagination, pulls, freshness and
  future-clock recovery, unavailable and failed sessions, post-upsert account
  fencing, equal-time conflicts, confirmed tombstones, recovery, and
  deterministic trailing reconciliation;
- canonicalization tests prove malformed local and remote whitespace aliases
  plan through one newest normalized row rather than trapping or producing
  duplicate upserts; and
- architecture tests freeze declaration ownership, framework imports, direct
  Supabase resolution, endpoint strings, source inventory, and the 600-line
  production-file ceiling.

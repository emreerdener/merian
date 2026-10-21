## October 20 — V65 receiving-intent storage foundation

The active schema is V65. Its additive V64→V65 stage introduces one empty
package-keyed receiving-intent slot table; it does not create operations, adopt
media or activate Capture. V64 was frozen and compiled first. Existing
source-isolated plans append the new stage, and V64 has its own recent startup
plan. Destructive rescue and quarantine eligibility remain unchanged.

Raw intent rows are conservative storage liabilities, including malformed or
unanchored rows. Until the intent-aware owner is qualified, they block legacy
qualification/purge and native scoped mutation audits, including after page
suspension. The canonical codec remains a descriptive value, not a writer
capability. Typed staging, receiving, exact recovery, abandonment and Capture
handoff remain subsequent acceptance gates. Numeric limits are unchanged.

Local validation passed 185 focused methods. The complete unit target recorded
6,456 passes and one omitted purge-inventory fixture; the corrected three-suite
rerun passed 23/23 methods with runtime sources unchanged. Full-run evidence,
including a synthetic video-fixture QoS warning, remains retained. This is
shared-checkout validation, not isolated, device or integrated acceptance. See
`docs/rfcs/identification-history-alpha-readiness-2026-10-11.md` for exact
results. Activation is disabled, PR116 frozen, deployment held and AWS
unapproved.

# Core Data Store Recovery

This directory owns launch-time SwiftData store inspection and preservation. It
chooses a migration strategy, records privacy-safe diagnostics, classifies
startup failures, and archives eligible store artifacts without touching account
identity. The canonical runtime contract is
[Startup Store Recovery](../../../../../../docs/backend-and-data/08-startup-store-recovery.md).

## Ownership

- `ModelStoreRecoveryCoordinator.swift` is the source-compatible façade for the
  production `ModelConfiguration` and configured store URL.
- `Models/StoreMigrationModels.swift` owns recent-source, V50 graph, migration
  hint, and decision values. `StartupStoreDiagnostic.swift` owns the local
  diagnostic and telemetry projection. `StartupStoreBootstrapModels.swift` owns
  the bootstrap outcome—including its optional `ModelContainer` reference—and
  the value-only startup state, notice, and telemetry event.
  `StoreRecoveryManifest.swift` owns the support archive format, while
  `StoreRecoveryJSONCoding.swift` contains the recovery-local deterministic JSON
  encoder.
- `Policies/ModelStoreRecoveryPolicy.swift` owns migration-hint selection,
  corruption classification, migration-failure recognition, quarantine/rescue
  eligibility, and safe-mode feedback. `StoreRecoveryPrivacyPolicy.swift` owns
  stable SHA-256 fingerprints and diagnostic sanitization.
- `Services/StoreRecoveryMetadataService.swift` owns Core Data metadata reads,
  version/checksum interpretation, and local diagnostic persistence.
  `StoreRecoveryArtifactArchiver.swift` owns exact SQLite/WAL/SHM discovery,
  transactional quarantine/rescue moves, rollback, and manifest writes.
  `ModelContainerFactory.swift` owns Objective-C-exception-safe SwiftData
  construction, exhaustive recent-source plan routing, ordered
  duplicate-checksum fallback, and the plan-free current-schema container used
  by safe mode. `ModelContainerBootstrapper.swift` owns launch diagnostics and
  the normal, quarantine, rescue, safe-mode, and blocked outcomes. The app root
  only attaches the returned container and presentation values.

## Invariants

- Production continues to resolve `default.store` through SwiftData's shipped
  `.automatic` App Group configuration. This code must not reconstruct an
  Application Support path.
- `RecentSourceSchema` remains consecutive from V42 through the schema
  immediately preceding `CurrentSchema`; V50 graph selection remains limited to
  the two reviewed checksum fingerprints.
- Only verified SQLite/Core Data corruption may enter quarantine. Non-corrupt
  failures may enter rescue only from a legacy migration strategy with existing
  artifacts. Generic current-store failures never move user data.
- Archive manifests contain error code, an allowlisted stable error domain or
  its deterministic fingerprint, and deterministic fingerprints of
  description/failure text. Diagnostic metadata strings and captured metadata
  keys are fingerprinted before local persistence or telemetry. Neither boundary
  persists raw error prose, arbitrary identifiers, paths, account identifiers,
  scan content, credentials, or session state.
- An archive succeeds only after every discovered artifact moves and its
  manifest is atomically written. Any move or manifest failure rolls completed
  moves back; a rollback failure leaves the archive directory intact as recovery
  evidence and never reports success.
- Store Recovery never references Auth, Keychain, Supabase, profile, sign-out,
  or cloud mutation owners.
- Preserved rescue databases are consumed read-only by Core Data Images after
  startup. Store Recovery does not fetch the current scan library or own the
  process-local media mapping registry.
- Safe mode creates an empty in-memory `CurrentSchema` container without a
  migration plan. A defect in a historical migration stage must not prevent the
  last-resort workspace from opening; `MigrationPlanTests` validates the full
  `MerianMigrationPlan` independently.
- Every production and focused test Swift file in this boundary remains at or
  below the 600-line review guard.
- `MerianApp` must not construct a `ModelContainer`, name a migration plan, or
  invoke quarantine/rescue effects directly.

## Verification

- `ModelStoreRecoveryCoordinatorTests` covers store configuration, migration
  decisions, V50 checksum routing, corruption/rescue eligibility, and safe-mode
  policy.
- `ModelContainerBootstrapperTests` covers the live plan-free in-memory safe
  mode, an injected successful fallback, and the terminal blocked result when
  even the in-memory container fails.
- `StartupStoreDiagnosticTests` covers fresh-store diagnostics, redacted error
  summaries and metadata identifiers, telemetry projection, and rescue flags.
- `StoreRecoveryArtifactArchiverTests` covers exact artifact moves, rescue
  manifests, raw private-text rejection, and content-preserving rollback after
  partial moves or manifest-write failures.
- `StoreRecoveryArchitectureTests` freezes declaration ownership, dependency
  exclusions, mirrored test ownership, line ceilings, and safe mode's
  independence from historical migration-plan validation.
- `MigrationPlanTests` retains the disk-backed source-schema and production
  plan-selection coverage; this refactor does not change a schema or migration
  stage.

At the V59 checkpoint, the immediate V58 source used
`MerianRecentV58MigrationPlan` with lightweight V58→V59. Older supported plans
retain their existing stages and append V58→V59; checksum retries try the
current store, V58 through V51, both V50 graphs and then V49 through V42. V58's
frozen scan and queue snapshots preserve the outgoing graph. V59 adds four
standalone photo-preparation entities with scalar IDs, no relationships to the
legacy graph and an initially empty ledger. Migration runs during ordinary
startup even while photo-preparation access remains disabled.

The earlier V57→V58 stage gives existing queued scans ordinary qualification and
nil parent, source and owner linkage without changing saved identification or
review state. Retain its disk-backed media-cascade and current-schema-reopen
coverage. The canonical
[SwiftData contract](../../../../../../docs/backend-and-data/04-database-schema.md)
and
[startup recovery guide](../../../../../../docs/backend-and-data/08-startup-store-recovery.md)
describe the active schema and source-isolated migration routing.

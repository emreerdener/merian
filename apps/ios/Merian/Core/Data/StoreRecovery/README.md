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
  diagnostic and telemetry projection. `StoreRecoveryManifest.swift` owns the
  support archive format, while `StoreRecoveryJSONCoding.swift` contains the
  recovery-local deterministic JSON encoder.
- `Policies/ModelStoreRecoveryPolicy.swift` owns migration-hint selection,
  corruption classification, migration-failure recognition, quarantine/rescue
  eligibility, and safe-mode feedback. `StoreRecoveryPrivacyPolicy.swift` owns
  stable SHA-256 fingerprints and diagnostic sanitization.
- `Services/StoreRecoveryMetadataService.swift` owns Core Data metadata reads,
  version/checksum interpretation, and local diagnostic persistence.
  `StoreRecoveryArtifactArchiver.swift` owns exact SQLite/WAL/SHM discovery,
  transactional quarantine/rescue moves, rollback, and manifest writes.

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
- Every production and focused test Swift file in this boundary remains at or
  below the 600-line review guard.

## Verification

- `ModelStoreRecoveryCoordinatorTests` covers store configuration, migration
  decisions, V50 checksum routing, corruption/rescue eligibility, and safe-mode
  policy.
- `StartupStoreDiagnosticTests` covers fresh-store diagnostics, redacted error
  summaries and metadata identifiers, telemetry projection, and rescue flags.
- `StoreRecoveryArtifactArchiverTests` covers exact artifact moves, rescue
  manifests, raw private-text rejection, and content-preserving rollback after
  partial moves or manifest-write failures.
- `StoreRecoveryArchitectureTests` freezes declaration ownership, dependency
  exclusions, mirrored test ownership, and line ceilings.
- `MigrationPlanTests` retains the disk-backed source-schema and production
  plan-selection coverage; this refactor does not change a schema or migration
  stage.

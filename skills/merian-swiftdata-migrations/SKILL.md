---
name: merian-swiftdata-migrations
description: "Plan, implement, review, or test Merian SwiftData model and schema-version changes. Use before editing apps/ios/Merian/Models/ActiveSchema when a persisted field, entity, relationship, uniqueness rule, or migration stage may change, and for VersionedSchema, SchemaVersions, CurrentSchema aliases, ModelContainer startup, store recovery, or MigrationPlanTests work."
---

# Merian SwiftData migrations

Protect every installed store by freezing the outgoing schema before the active
model changes and by verifying both migration and startup-recovery paths.

## Mandatory sequence

1. Read `AGENTS.md`, inspect `git status`, and read
   [schema-update.md](references/schema-update.md) completely.
2. Identify the current alias, all schema arrays and stages, the affected active
   models, and the startup/recovery plans that can open historical stores.
3. Freeze the outgoing schema and compile it **before** editing any affected
   file under `Models/ActiveSchema/`.
4. Change the active model, add the new current schema, advance the alias, and
   append the migration stage without editing any retired schema.
5. Add or update disk-backed migration fixtures and startup-recovery coverage.
6. Update the SwiftData portion of `docs/backend-and-data/04-database-schema.md`
   and any changed recovery contract.

If the outgoing shape cannot be reconstructed confidently, stop before the
active-model edit and recover it from the current source and version history.
Do not guess a historical schema.

## Non-negotiable invariants

- Retired `VersionedSchema` types are immutable snapshots and use fully
  qualified frozen model references.
- Only the current schema points at global active model types.
- Relationship-bearing models are frozen together when Swift type identity is
  part of their relationship key paths.
- Every consecutive stage has distinct from/to model references on iOS 26+.
- Migration failure does not justify broad store deletion. Recovery remains
  signature-gated, preserves recoverable artifacts, and is independently tested.

## Verification

Run `make validate-ios-migration-guardrails`, regenerate the Xcode project if a
schema file was added, build, and run the complete `MigrationPlanTests` suite on
the repository-supported simulator matrix. Run repository tests for affected
models and startup recovery. A fresh in-memory container is insufficient proof;
include disk-store migration from the outgoing schema and any relevant rescue or
quarantine decision fixture.

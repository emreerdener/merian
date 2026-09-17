# App Models

This directory owns values and persistence declarations shared across product
features. It is not a home for feature state, networking, filesystem work, or
live dependency resolution.

The canonical persistence contract is
[Database Schema](../../../../docs/backend-and-data/04-database-schema.md), and
the migration procedure is
[SwiftData and API Gotchas](../../../../docs/development-guides/11-swiftdata-and-api-gotchas.md).

## Ownership

- `Species/` owns the platform-neutral `SpeciesData` value graph, supporting
  observation values, deterministic display and identity policy, and rich
  lookalike values. It imports Foundation only and performs no networking,
  persistence, task creation, or live dependency lookup.
- `Media/` owns the Foundation-only captured-media value graph: the
  cross-feature `ObservationContext`, storage references, the ordered Codable
  timeline, deterministic snapshots and summaries, and scalar JSON coding.
  Filesystem resolution, cloud hydration, SwiftData mirror writes, and Capture
  submission projection remain outside this value owner.
- `ActiveSchema/` owns the current SwiftData model declarations. A stored-field,
  entity, relationship, uniqueness, or migration change must follow the
  repository's SwiftData migration procedure; moving a declaration is not a
  substitute for a schema version. `ModelContext` fetch/mutation workflows
  belong to the relevant Core Data persistence owner, not beside these
  declarations.
- `Schema/` contains immutable historical schema snapshots. Do not edit a
  released snapshot to make the current model compile.
- `SchemaVersions.swift` declares schema versions and migration stages. It
  remains a single migration registry so version and stage order can be reviewed
  together; `Aliases.swift` owns the current-schema alias.
- Root `ScanQueueState`, `UserReviewState`, and `QueuedScanContext` remain
  stable cross-feature vocabulary. They are deterministic values. Offline Sync's
  main-actor persistence projection copies a live queued row while its storage
  policy supplies the queued byte estimate; Insight's media-presentation
  extension maps the resulting context to `ActiveScanMedia` and restores Capture
  focus descriptors.

AI-bound adaptation is intentionally outside this directory. Core AI
[`Models/`](../Core/AI/Models/) owns capture telemetry and the
`EdgeResponse`-to-`SpeciesData` mapping because those values depend on inference
runtime and wire declarations. Generated and handwritten wire DTOs remain under
Core Network.

## Change Rules

- Keep shared value models deterministic and free of live effects.
- Preserve public and internal initializer, Codable, and presentation behavior
  when relocating declarations.
- Do not add a convenience network client, singleton, task, or model context to
  a value owner.
- Keep production files in `Models/Species` and `Models/Media` below the local
  600-line review ceiling. Prefer a cohesive owner over fragments created only
  to reduce line count.
- Mirror focused behavior and ownership tests under `MerianTests/Models`; Core
  AI model tests belong under `MerianTests/Core/AI/Models`.
- Keep Capture-specific transformations with Capture.
  `Features/Capture/Submission/Services/CaptureSubmissionTelemetry.swift` owns
  native-default zoom normalization, and `CaptureSubmissionPolicyTests` locks
  that behavior rather than the Core AI telemetry suite.

## Verification

`SpeciesModelsArchitectureTests` locks the exact species source and test
inventory, unique declaration ownership, Foundation-only imports, effect-free
model files, Core AI mapping ownership, retired aggregate paths, and the local
line ceiling. The focused Species suites preserve initializer, presentation,
identity, Codable, and lookalike behavior. Core AI's `CaptureTelemetryTests` and
`SpeciesDataEdgeResponseTests` preserve capture-context and wire-to-domain
mapping respectively. The architecture suite prevents the Capture-owned zoom
policy regression from drifting back into Core AI.

`CapturedMediaArchitectureTests` locks the captured-media declaration owners,
effect-free value layer, unchanged V51 persisted property shape, retired
aggregate path, mirrored focused tests, and the same 600-line ceiling. Behavior
coverage is split between captured-media value, resolution, active-schema
mirror, and cloud-hydration suites rather than one cross-layer test aggregate.

`ModelsIntegrationArchitectureTests` closes the boundary across root values,
`ActiveSchema`, Species, Media, and the migration registry. It freezes the root
and active-schema inventories, rejects live effects and persistence workflows in
those owners, verifies the queued-row projection plus the queued-byte,
Insight-media, and cloud-deletion adapters have one owner each, applies the
600-line guard to every nonhistorical model file, and leaves
`SchemaVersions.swift` as the explicit ordered-registry exception. The app-wide
`IOSHygieneClosureArchitectureTests` inventory independently records that file
as the only oversized Models owner, so another Models exception cannot appear
without review.

Run project generation, source membership, the focused model suites, and the
complete unit target after moving or adding Swift sources. The canonical
selector list is the Models closure matrix in the
[testing strategy](../../../../docs/development-guides/08-testing-strategy.md).

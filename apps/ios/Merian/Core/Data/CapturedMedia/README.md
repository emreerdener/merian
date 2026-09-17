# Captured Media Data

This directory owns durable captured-media reconciliation after the ordered
timeline has crossed a persistence or cloud-history boundary. It contains no UI,
networking, authentication, or feature state.

## Ownership

- `CapturedMediaCloudHydration.swift` merges canonical manifests with legacy
  image, video, audio, and observation-context columns. It also owns the policy
  deciding when a hydrated timeline may replace an existing local snapshot.
- `CapturedMediaRecordPersistence.swift` writes the scalar JSON and
  `CapturedMediaEntry` relationship mirror together, deletes replaced child rows
  through their owning model context, and reads scalar JSON before lazily
  faulting relationship rows.
- `CapturedMediaPersistenceService.swift` converts a Capture timeline into the
  durable ordered JSON representation. File adoption is injected; only its
  narrow live dependencies resolve `FileIOActor`.

Related ownership remains deliberately separate:

- [`Models/Media/`](../../../Models/Media/) owns the Foundation-only
  observation, timeline, reference, snapshot, summary, and JSON value graph.
- [`Models/ActiveSchema/CapturedMediaEntry.swift`](../../../Models/ActiveSchema/CapturedMediaEntry.swift)
  owns the unchanged active SwiftData declaration.
- [`Core/Media/CapturedMediaResolution.swift`](../../Media/CapturedMediaResolution.swift)
  owns local filesystem, approved HTTPS, and active-media resolution.
- [`CaptureSubmissionMediaProjection.swift`](../../../Features/Capture/Submission/Models/CaptureSubmissionMediaProjection.swift)
  owns the Capture transport adapter.
- Core Network owns generated and handwritten wire DTOs; this directory does not
  decode PostgREST rows or call endpoints.

## Invariants

- `capturedMediaJSON` remains the primary read source. Relationship rows are a
  migration, debugging, and fallback mirror and must not be faulted while valid
  scalar JSON exists.
- Cloud compatibility arrays provide missing media but do not invent cross-modal
  order or standalone-audio identity.
- A source relocation must not change `CapturedMediaEntry` fields,
  relationships, model names, schema version, or migration plan.
- Production and focused test files in this boundary remain below the local
  600-line review ceiling.

## Verification

`CapturedMediaCloudHydrationTests` covers canonical and compatibility hydration,
nonvisual preservation, sampled-video fallback, and replacement policy.
`CapturedMediaRecordPersistenceTests` covers scalar-first reads and
relationship/active-media round trips, and
`CapturedMediaPersistenceServiceTests` locks explicit and legacy-default
timeline conversion. `CapturedMediaArchitectureTests` enforces declaration
ownership, the effect-free value layer, the unchanged V51 shape, retired
aggregate paths, mirrored suite placement, and line limits.
